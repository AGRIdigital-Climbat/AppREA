import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/edan.dart';
import '../../models/edan_registro_v2.dart';
import '../api/edan_api_v2.dart';
import '../app_logger.dart';
import '../database_helper.dart';
import '../edan/edan_secciones_fuente.dart';
import '../edan/edan_store_v2.dart';
import '../edan/edan_uuid_helper.dart';
import '../edan_secciones_registry.dart';
import '../sync_debug_collector.dart';
import '../sync_debug_config.dart';

/// Resumen de una corrida de sync.
class EdanSyncResumen {
  final bool exito;
  final int enviados;
  final int conflictos;
  final int errores;
  final int fotosSubidas;
  final int fotosPendientes;
  final int fotosDescargadas;
  final String? ultimoError;
  final String? watermark;

  const EdanSyncResumen({
    required this.exito,
    this.enviados = 0,
    this.conflictos = 0,
    this.errores = 0,
    this.fotosSubidas = 0,
    this.fotosPendientes = 0,
    this.fotosDescargadas = 0,
    this.ultimoError,
    this.watermark,
  });

  @override
  String toString() =>
      'SyncResumen(exito=$exito, enviados=$enviados, conflictos=$conflictos, '
      'errores=$errores, fotos=$fotosSubidas pendientes=$fotosPendientes '
      'descargadas=$fotosDescargadas)';
}

/// Resultado de [EdanSyncEngineV2.descargarMunicipio].
class EdanMunicipioDescarga {
  final bool exito;
  final int total;
  final int descargados;
  final int omitidos;
  final int errores;
  final String? ultimoError;

  const EdanMunicipioDescarga({
    required this.exito,
    this.total = 0,
    this.descargados = 0,
    this.omitidos = 0,
    this.errores = 0,
    this.ultimoError,
  });

  @override
  String toString() =>
      'MunicipioDescarga(exito=$exito, total=$total, '
      'descargados=$descargados, omitidos=$omitidos, errores=$errores)';
}

/// Motor de sync v2: pull → apply → ack → push → fotos.
///
/// Orquesta `EdanApiV2` con las tablas `cola_sincronizacion` y `cola_fotos`.
/// No depende de la UI; los streams de pendientes/conflictos viven en
/// `EdanStoreV2`.
class EdanSyncEngineV2 {
  EdanSyncEngineV2({
    required EdanApiV2 api,
    DatabaseHelper? db,
    Directory? dirFotos,
    this.usuarioId,
  })  : _api = api,
        _db = db ?? DatabaseHelper.instance,
        _dirFotos = dirFotos;

  final EdanApiV2 _api;
  final DatabaseHelper _db;

  /// Dueño de los datos en este dispositivo. Cuando se informa, el watermark
  /// y el push se restringen a ese usuario (multi-cuenta segura en el mismo
  /// equipo: el usuario B no hereda el watermark del A ni empuja sus filas).
  /// `null` = comportamiento global (compatibilidad/tests).
  final int? usuarioId;

  /// Carpeta donde se guardan los bytes de las fotos bajadas por el pull
  /// (recuperación en un dispositivo nuevo). Si es `null` se omite la
  /// descarga (p.ej. en tests que no la necesitan).
  final Directory? _dirFotos;

  /// TEMP DIAG (borrar): último motivo de fallo de [enviarLocalidad], con el
  /// status HTTP real cuando exista (`null` = error de red/socket). Sirve para
  /// depurar el bug de `danos_agricultura` (400 vs 409 vs red) mientras se
  /// confirma si la Fase 1 alcanza o hay un segundo problema.
  String? ultimoErrorDiagnostico;

  static const String _claveWatermark = 'sync_watermark_v2';
  static const String _claveIdDispositivo = 'id_dispositivo';
  // ── Público ──

  /// Ejecuta el ciclo completo de sync.
  Future<EdanSyncResumen> sincronizar() async {
    var resumen = const EdanSyncResumen(exito: true);
    if (kSyncDebugMode) SyncDebugCollector.instance.startSession();
    AppLogger.instance.sync(titulo: 'Sincronización V2: inicio');

    try {
      // Arranque/recuperación: una corrida muerta (kill a mitad de sync)
      // pudo dejar operaciones en `subiendo`. Se liberan a `pendiente`
      // para que esta corrida las reprocese (arquitectura §17/§23).
      _fase('Preparando');
      await _recuperarSubiendoVencidos();
      if (kSyncDebugMode) {
        SyncDebugCollector.instance.addFase('V2 · Estados (cambios)');
      }
      _fase('Revisando cambios');
      resumen = await _verificarCambiosEstados(resumen);
      if (kSyncDebugMode) SyncDebugCollector.instance.addFase('V2 · Pull');
      _fase('Descargando datos');
      resumen = await _aplicarPull(resumen);
      // Recuperación en dispositivo nuevo: tras aplicar los metadatos de las
      // fotos del pull, descargar sus bytes a `ruta_local` (si se inyectó una
      // carpeta). Así un usuario que perdió el celular y volvió a entrar
      // recupera sus registros CON las fotos disponibles offline.
      if (kSyncDebugMode) {
        SyncDebugCollector.instance.addFase('V2 · Descarga de fotos');
      }
      _fase('Descargando fotos');
      resumen = await _descargarFotosPendientes(resumen);
      if (kSyncDebugMode) SyncDebugCollector.instance.addFase('V2 · Push (cola)');
      _fase('Subiendo cambios');
      resumen = await _pushSync(resumen);
      if (kSyncDebugMode) SyncDebugCollector.instance.addFase('V2 · Fotos');
      _fase('Subiendo fotos');
      resumen = await _pushFotos(resumen);
      if (kSyncDebugMode) {
        SyncDebugCollector.instance.addFase('V2 · Borrados de foto');
      }
      _fase('Finalizando');
      resumen = await _pushBorradosFotos(resumen);
      // Higiene (última): fotos huérfanas nunca subidas cuya dueña no se
      // persistió (capturar + salir sin guardar). Corre después de todas las
      // fases de subida/descarga — no hay nada en tránsito — y con guarda de
      // edad (7 días), de modo que una captura pendiente de su primer
      // guardado (minutos) no puede ser tocada aunque dispare un auto-sync.
      await _purgarFotosHuerfanasBestEffort();
      if (kSyncDebugMode) {
        SyncDebugCollector.instance.addDiagnostico('Resumen V2', {
          'exito': resumen.exito,
          'enviados': resumen.enviados,
          'conflictos': resumen.conflictos,
          'errores': resumen.errores,
          'fotos_subidas': resumen.fotosSubidas,
          'fotos_pendientes': resumen.fotosPendientes,
          'fotos_descargadas': resumen.fotosDescargadas,
          'watermark': resumen.watermark,
        });
      }
      return resumen;
    } on SocketException catch (e) {
      return EdanSyncResumen(
        exito: false,
        enviados: resumen.enviados,
        conflictos: resumen.conflictos,
        errores: resumen.errores,
        fotosSubidas: resumen.fotosSubidas,
        fotosPendientes: resumen.fotosPendientes,
        fotosDescargadas: resumen.fotosDescargadas,
        ultimoError: 'Sin conexión: $e',
      );
    } catch (e) {
      // Sesión expirada: mensaje accionable en vez del detalle crudo.
      final auth = e is EdanApiError && _esSesionExpirada(e);
      return EdanSyncResumen(
        exito: false,
        enviados: resumen.enviados,
        conflictos: resumen.conflictos,
        errores: resumen.errores,
        fotosSubidas: resumen.fotosSubidas,
        fotosPendientes: resumen.fotosPendientes,
        fotosDescargadas: resumen.fotosDescargadas,
        ultimoError: auth ? _mensajeSesionExpirada : e.toString(),
      );
    } finally {
      _fase('');
      if (kSyncDebugMode) SyncDebugCollector.instance.endSession();
      AppLogger.instance.sync(titulo: 'Sincronización V2: fin');
    }
  }

  /// Envuelve [EdanStoreV2.purgarFotosHuerfanas] sin riesgo para la corrida:
  /// una falla de higiene no puede volver `exito=false` un sync que ya
  /// subió/bajó todo. Registra el resultado en el log global cuando purga.
  Future<void> _purgarFotosHuerfanasBestEffort() async {
    try {
      final n = await EdanStoreV2.instance.purgarFotosHuerfanas();
      if (n > 0) {
        debugPrint('[SyncV2] fotos huerfanas purgadas: $n');
        AppLogger.instance.sync(
          titulo: 'Fotos huerfanas purgadas: $n',
          detalle: 'nunca subidas, dueña inexistente y > 7 días '
              '(capturas abandonadas sin guardar)',
        );
      }
    } catch (e) {
      debugPrint('[SyncV2] purga de fotos huerfanas omitida: $e');
    }
  }

  /// Publica la fase textual de la corrida en el store para la franja de
  /// progreso (best-effort: nunca lanza).
  void _fase(String fase) {
    try {
      EdanStoreV2.instance.faseSync.value = fase;
    } catch (_) {}
  }

  /// Paso 0 de sync: `GET /formularios/estados?fecha_modificacion_desde=<wm>`
  /// — listado ligero incremental. El servidor marca `tiene_cambios=true` en
  /// cada fila cuya `fecha_modificacion` es posterior al watermark guardado.
  /// Para esas filas se baja el documento completo con
  /// `GET /formularios/{uuid}/completo` y se aplica con `_normalizarDocCompleto`
  /// (la misma normalización que usa el pull completo). Los estados
  /// locales quedan actualizados incluso para las filas sin cambios.
  ///
  /// Este paso es complementario al `sync/pull` (que se ejecuta después): el
  /// pull sigue siendo la fuente de verdad para tombstones y secciones; los
  /// estados sirven para actualizar badges (`id_edan_localidad_estado`,
  /// `pendiente_*`) de forma barata sin bajar el documento entero.
  Future<EdanSyncResumen> _verificarCambiosEstados(
      EdanSyncResumen previo) async {
    final watermark = await _watermark;
    try {
      // §20.15: el watermark NO filtra la lista (solo marca el flag) → se
      // pide `todos=true` + watermark en la misma llamada. Lo ÚNICO que
      // decide bajar algo es `tiene_cambios` (booleano estricto, nunca
      // null): `true` → GET /completo; `false`/ausente → no se toca nada.
      final res = await _api.obtenerEstadosFormularios(
        todos: true,
        fechaModificacionDesde:
            (watermark != null && watermark.isNotEmpty) ? watermark : null,
      );
      final filas = res.data ?? const <Map<String, dynamic>>[];

      int actualizados = 0;
      int errores = 0;

      for (final fila in filas) {
        final uuid = fila['uuid_edan_localidad'] as String?;
        if (uuid == null || uuid.isEmpty) continue;

        // 1) Actualizar estado local desde la fila ligera (rápido,
        //    sin bajar documento). Ignora si la localidad está sucia (push
        //    pendiente): el push local es la fuente de verdad.
        final sucia = await _esLocalidadSucia(uuid);
        if (!sucia) {
          await _actualizarEstadoLocalDesdeEstados(fila);
        }

        // 2) Bajar el documento completo SOLO si `tiene_cambios=true`.
        //    - uuid nuevo (creado en web) o limpio → se inserta/refresca
        //      local y se asienta el watermark con su fecha_modificacion.
        //    - sucio local → NO se pisa: nuestro PUT posterior gana (LWW).
        //    - `false`/ausente → nada que bajar, aunque venga en la lista.
        final tieneCambios = fila['tiene_cambios'];
        if (tieneCambios != true) continue;
        final db = await _db.database;
        final existe = await db.query(
          'formularios',
          columns: ['uuid_edan_localidad'],
          where: 'uuid_edan_localidad = ?',
          whereArgs: [uuid],
          limit: 1,
        );
        if (existe.isNotEmpty && sucia) {
          debugPrint('[SyncV2] estados $uuid tiene_cambios pero sucio: '
              'gana el PUT local posterior');
          continue;
        }
        try {
          final doc = await _api.obtenerFormularioCompleto(uuid);
          if (doc.data != null) {
            await _normalizarDocCompleto(doc.data!);
            actualizados++;
            // Asentar watermark con la fecha del documento bajado
            // (string opaco del servidor, sin parsear ni timezones): la
            // próxima consulta ya lo verá como asentado (igualdad→false).
            final fm = _fechaDoc(doc.data!);
            if (fm != null && fm.isEmpty == false) {
              final actual = await _watermark;
              if (actual == null ||
                  actual.isEmpty ||
                  fm.compareTo(actual) > 0) {
                await _guardarWatermark(fm);
              }
            }
          }
        } on EdanApiConflict {
          errores++;
        } on EdanApiError {
          errores++;
        } on SocketException {
          break;
        }
      }

      if (kSyncDebugMode) {
        SyncDebugCollector.instance.addDiagnostico('Estados V2', {
          'watermark': watermark,
          'filas': filas.length,
          'con_cambios': actualizados,
          'errores': errores,
        });
      }

      return previo;
    } on SocketException {
      return previo; // sin red: dejar que siga con pull
    } on EdanApiConflict {
      return previo; // 409 inesperado en un GET: no bloquear sync
    } on EdanApiError {
      return previo; // endpoint no disponible o error: no bloquear sync
    }
  }

  /// Actualiza `formularios` desde una fila ligera de
  /// `GET /formularios/estados`: id_server, estado, pendiente_*,
  /// localidad, ids geográficos y `grup_*` planas. No toca secciones ni crea
  /// filas (los ítems de estados no traen `imp_*`). LWW: sin `version`.
  Future<void> _actualizarEstadoLocalDesdeEstados(
      Map<String, dynamic> fila) async {
    final uuid = fila['uuid_edan_localidad'] as String?;
    if (uuid == null || uuid.isEmpty) return;
    final db = await _db.database;

    // Construir las columnas que la fila ligera trae. El nodo
    // `estado_localidad` es `{id, nombre, orden}` → se mapea a
    // `id_edan_localidad_estado`. Los `grupos` van como las 9 flags.
    final cols = <String, dynamic>{};
    if (fila['id_edan_localidad'] != null) {
      cols['id_server'] = fila['id_edan_localidad'];
    }
    if (fila['localidad'] != null) cols['localidad'] = fila['localidad'];
    if (fila['id_usuario'] != null) cols['id_usuario'] = fila['id_usuario'];
    final estado = fila['estado_localidad'];
    if (estado is Map) {
      // El server envía {id_edan_localidad_estado, nombre, orden}.
      final m = Map<String, dynamic>.from(estado);
      final idEstado =
          m['id_edan_localidad_estado'] ?? m['id'];
      if (idEstado != null) cols['id_edan_localidad_estado'] = idEstado;
    }
    if (fila['id_edan_localidad_estado'] != null) {
      cols['id_edan_localidad_estado'] = fila['id_edan_localidad_estado'];
    }
    // NOTA (diseño limpio): `pendiente_actualizacion`/`pendiente_eliminacion`
    // del servidor son informativos y NO son columnas locales (el esquema
    // limpio no las tiene: escribirlas crasheaba en instalación fresca).
    // Lo local usa `pendiente_push` + cola `D`; se ignoran aquí.
    // Nodos anidados de la fila ligera (mismos campos que `_columnasCabecera`).
    final extras = _columnasCabecera(fila);
    extras.forEach((k, v) {
      if (!cols.containsKey(k)) cols[k] = v;
    });
    // Grupos: 9 `grup_*` planas (autoritativas desde 2026-10-14).
    final grupoCols = _columnasGrupo(fila);
    grupoCols.forEach((k, v) {
      if (!cols.containsKey(k)) cols[k] = v;
    });

    // Solo si la fila ya existe localmente (no crear filas desde estados).
    final existente = await db.query(
      'formularios',
      columns: ['uuid_edan_localidad'],
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (existente.isEmpty) return;

    await db.update(
      'formularios',
      cols,
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuid],
    );
  }

  /// Paso 1 de sync: `GET /sync/pull` (pull completo con watermark).
  //
  // El pull real (PLAN §15.1) devuelve arreglos separados en el nivel superior
  // (`formularios`, `secciones`, `viviendas`, `fotos`, `tombstones`) y un
  // `watermark`; NO un arreglo `registros` con campo `tabla`. Cada colección se
  // aplica contra su tabla local respetando LWW y sin pisar filas sucias.

  Future<EdanSyncResumen> _aplicarPull(EdanSyncResumen previo) async {
    final watermark = await _watermark;
    final result = await _api.pull(desde: watermark);
    final data = result.data ?? {};
    final nuevoWatermark = data['watermark'] as String?;

    final formularios = _listaPull(data['formularios']);
    final secciones = _listaPull(data['secciones']);
    final viviendas = _listaPull(data['viviendas']);
    final fotos = _listaPull(data['fotos']);
    final tombstones = _listaPull(data['tombstones']);

    final vacio = formularios.isEmpty &&
        secciones.isEmpty &&
        viviendas.isEmpty &&
        fotos.isEmpty &&
        tombstones.isEmpty;

    if (vacio) {
      if (nuevoWatermark != null && nuevoWatermark.isNotEmpty) {
        await _ack(nuevoWatermark);
      }
      return previo;
    }

    var aplicado = true;
    int filasFallidas = 0;
    int tombstonesFallidos = 0;
    String? primerError;
    Future<void> aplicar(Future<void> Function() fn, {String item = '?'}) async {
      try {
        await fn();
      } catch (e) {
        aplicado = false;
        filasFallidas++;
        primerError ??= e.toString();
        // NUNCA tragarse el fallo en silencio: antes un `catch (_) { }` dejaba
        // `exito=true` con 0 filas aplicadas → se marcaba la primera sync como
        // hecha y la lista quedaba VACÍA sin ningún aviso en el celular.
        // El texto solo vivía en logcat: ahora queda en el registro de 24 h
        // (log del usuario 2026-11-03: "1 de 28 falló" sin poder identificar
        // NI el ítem NI el error).
        AppLogger.instance.sync(
          nivel: AppLogLevel.warn,
          titulo: 'Pull V2: no aplicada $item',
          detalle: '$e',
        );
        debugPrint('[SyncV2] pull: fila no aplicada ($filasFallidas): $e');
      }
    }

    for (final r in formularios) {
      await aplicar(() => _aplicarFormularioPull(r),
          item: 'formulario ${r['uuid_edan_localidad'] ?? '?'}');
    }
    for (final r in secciones) {
      await aplicar(() => _aplicarSeccionPull(r),
          item: 'seccion ${r['uuid_registro'] ?? '?'}'
              ' (${r['tipo_seccion'] ?? r['tipo'] ?? '?'})');
    }
    for (final r in viviendas) {
      await aplicar(() => _aplicarViviendaPull(r),
          item: 'vivienda ${r['uuid_registro'] ?? '?'}');
    }
    for (final r in fotos) {
      await aplicar(() => _aplicarFotoPull(r),
          item: 'foto ${r['uuid_fotografia'] ?? '?'}');
    }
    // Un tombstone que no se pudo aplicar NO bloquea el ack del watermark:
    // es un borrado, su fallo significa "no había nada que borrar" (app
    // limpia: el servidor manda para siempre los tombstones de datos de
    // diagnóstico viejos, p. ej. uuids sintéticos `aaaa-...`). Bloquear acá
    // dejaba el watermark clavado, el mismo tombstone fallando en cada sync y
    // la alerta "Primera sincronización incompleta" PERMANENTE (bug
    // 2026-11-03, registro_20261103_052515: fallidas:1, ack:false).
    for (final t in tombstones) {
      final idT = (t['id_registro'] ?? t['uuid_registro'])?.toString() ?? '?';
      try {
        await _aplicarTombstonePull(t);
      } catch (e) {
        tombstonesFallidos++;
        AppLogger.instance.sync(
          nivel: AppLogLevel.warn,
          titulo: 'Pull V2: tombstone no aplicado '
              '${t['tabla'] ?? '?'}/$idT (no bloquea el ack)',
          detalle: '$e',
        );
        debugPrint('[SyncV2] pull: tombstone no aplicado ($idT): $e');
      }
    }

    if (kSyncDebugMode) {
      SyncDebugCollector.instance.addDiagnostico('Pull V2', {
        'formularios': formularios.length,
        'secciones': secciones.length,
        'viviendas': viviendas.length,
        'fotos': fotos.length,
        'tombstones': tombstones.length,
        'fallidas': filasFallidas,
        'tombstones_fallidos': tombstonesFallidos,
        'primer_error': primerError,
        'watermark': nuevoWatermark,
        'ack': aplicado,
      });
    }

    // Si el servidor trae filas y NO se aplicó NINGUNA, el pull está roto:
    // marcar `exito=false` con el motivo real para que la UI (snackbar de
    // `ultimoErrorPrimeraDescarga`) lo muestre en vez de silencio.
    final totalFilas = formularios.length +
        secciones.length +
        viviendas.length +
        fotos.length +
        tombstones.length;
    if (!aplicado && filasFallidas >= totalFilas && totalFilas > 0) {
      final detalle = primerError != null ? ': $primerError' : '';
      return EdanSyncResumen(
        exito: false,
        enviados: previo.enviados,
        conflictos: previo.conflictos,
        errores: previo.errores + filasFallidas,
        fotosSubidas: previo.fotosSubidas,
        fotosPendientes: previo.fotosPendientes,
        fotosDescargadas: previo.fotosDescargadas,
        ultimoError:
            'El servidor envió $totalFilas fila(s) y ninguna se pudo aplicar'
            '$detalle',
        watermark: previo.watermark,
      );
    }

    if (aplicado && nuevoWatermark != null && nuevoWatermark.isNotEmpty) {
      await _ack(nuevoWatermark);
    }
    // El pull aplicó contenido (aunque sea parcial): las listas recargan
    // una sola vez aquí en vez de por fila.
    EdanStoreV2.instance.datosCambiados();
    // Fallas parciales (algunas filas sí, otras no): exito=false + conteo, sin
    // ack (el próximo pull reintenta las fallidas desde el watermark viejo).
    if (!aplicado) {
      return EdanSyncResumen(
        exito: false,
        enviados: previo.enviados,
        conflictos: previo.conflictos,
        errores: previo.errores + filasFallidas,
        fotosSubidas: previo.fotosSubidas,
        fotosPendientes: previo.fotosPendientes,
        fotosDescargadas: previo.fotosDescargadas,
        ultimoError:
            'Pull parcial: $filasFallidas de $totalFilas fila(s) no aplicada(s)'
            '${primerError != null ? ' · $primerError' : ''}',
        watermark: previo.watermark,
      );
    }
    return previo;
  }

  List<Map<String, dynamic>> _listaPull(dynamic raw) =>
      raw is List ? raw.whereType<Map<String, dynamic>>().toList() : const [];

  /// Aplica el documento canónico de `GET /formularios/{uuid}/completo`
  /// (cabecera + nodo `grupos` + las 14 secciones anidadas + `fotos[]`) a las
  /// tablas locales, NORMALIZÁNDOLO hacia las tablas fila-a-fila. Público
  /// porque `EdanEnvioV2.descargar` lo usa para ver reportes de OTROS usuarios
  /// que aún no están en el dispositivo (reemplazo de
  /// `GET /localidades/{id}/documento`, grupo legado).
  Future<void> aplicarDocumentoCompleto(Map<String, dynamic> doc) =>
      _normalizarDocCompleto(doc);

  /// Cabecera de `formularios` a partir de un registro de `sync/pull` plano o
  /// de un documento `/completo`. Solo las columnas que el servidor sí
  /// conoce; el llamador añade las locales (`secciones_activas_json`,
  /// `estado_local`), los grupos (`grup_*`) y su caché (`datos_json` /
  /// `datos_json_servidor`).
  static Map<String, dynamic> _columnasCabecera(Map<String, dynamic> r) => {
        if (r['id_edan_localidad'] != null) 'id_server': r['id_edan_localidad'],
        // El dueño del reporte es necesario para que la lista offline
        // (`EdanStoreV2.listarFormularios(usuarioId:)`) recupere en un celular
        // nuevo los reportes PROPIOS que trae el pull. Sin esto, la fila queda
        // con `id_usuario` nulo y no la encuentra el filtro por usuario.
        if (r['id_usuario'] != null) 'id_usuario': r['id_usuario'],
        if (r['localidad'] != null) 'localidad': r['localidad'],
        if (r['id_municipio'] != null) 'id_municipio': r['id_municipio'],
        if (r['id_departamento'] != null)
          'id_departamento': r['id_departamento'],
        if (r['id_provincia'] != null) 'id_provincia': r['id_provincia'],
        if (r['id_tipo_evento'] != null) 'id_tipo_evento': r['id_tipo_evento'],
        if (r['id_tipo_localidad'] != null)
          'id_tipo_localidad': r['id_tipo_localidad'],
        if (r['id_edan_localidad_estado'] != null)
          'id_edan_localidad_estado': r['id_edan_localidad_estado'],
        // Motivo del ultimo cambio de estado (rechazo UGR, v43). Los listados
        // de Rol 6/7 lo muestran solo con estado "Rechazado".
        if (r['observacion_estado'] != null)
          'observacion_estado': r['observacion_estado'],
        if (r['fecha_llenado'] != null) 'fecha_llenado': r['fecha_llenado'],
        if (r['fecha_evento'] != null) 'fecha_evento': r['fecha_evento'],
        if (r['hora_evento'] != null) 'hora_evento': r['hora_evento'],
        if (r['total_poblacion_afectada'] != null)
          'total_poblacion_afectada': r['total_poblacion_afectada'],
        if (r['total_familias_afectadas'] != null)
          'total_familias_afectadas': r['total_familias_afectadas'],
        if (r['total_familias_damnificadas'] != null)
          'total_familias_damnificadas': r['total_familias_damnificadas'],
        // LWW: el servidor ya no expone `version` en ninguna respuesta.
        if (r['fecha_modificacion'] != null)
          'fecha_modificacion': r['fecha_modificacion'],
        ..._columnasNodos(r),
      };

  /// Nodos anidados §20.16 (solo lectura servidor → columnas espejo, nunca
  /// viajan ni entran a la firma): cada `id_*` trae su objeto y los objetos
  /// traen sus propios ids (`usuario → rol`, `municipio → departamento…`).
  /// Todo tolera `null` (edan/importacion en primeras creaciones) y usa el
  /// id plano cuando el nodo no viene (listados ligeros como `/estados`).
  static Map<String, dynamic> _columnasNodos(Map<String, dynamic> r) {
    final out = <String, dynamic>{};
    Map<String, dynamic>? nodo(Object? v) {
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
      return null;
    }

    final usuario = nodo(r['usuario']);
    if (usuario != null) {
      if (usuario['nombre'] != null) {
        out['usuario_nombre'] = '${usuario['nombre']}';
      }
      if (usuario['usuario'] != null) {
        out['usuario_login'] = '${usuario['usuario']}';
      }
      final idRol = usuario['id_rol'];
      if (idRol is num) out['id_rol'] = idRol.toInt();
      final rol = nodo(usuario['rol']);
      final nombreRol = rol?['nombre'];
      if (nombreRol != null) out['usuario_rol'] = '$nombreRol';
    }
    final estado = nodo(r['estado_localidad']);
    final nombreEstado = estado?['nombre'];
    if (nombreEstado != null) out['estado_nombre'] = '$nombreEstado';
    final evento = nodo(r['tipo_evento']);
    final nombreEvento = evento?['nombre'];
    if (nombreEvento != null) out['tipo_evento_nombre'] = '$nombreEvento';
    final tipoLoc = nodo(r['tipo_localidad']);
    final nombreTipo = tipoLoc?['nombre'];
    if (nombreTipo != null) out['tipo_localidad_nombre'] = '$nombreTipo';
    // Geo: el municipio trae departamento/provincia anidados (recursivo);
    // los niveles sueltos son fallback.
    final muni = nodo(r['municipio']);
    if (muni != null) {
      if (muni['nombre'] != null) out['municipio_nombre'] = '${muni['nombre']}';
      if (muni['codigo_ine'] != null) {
        out['municipio_codigo'] = '${muni['codigo_ine']}';
      }
      final dep = nodo(muni['departamento']) ?? nodo(r['departamento']);
      if (dep != null) {
        if (dep['nombre'] != null) {
          out['departamento_nombre'] = '${dep['nombre']}';
        }
        if (dep['codigo_ine'] != null) {
          out['departamento_codigo'] = '${dep['codigo_ine']}';
        }
      }
      final prov = nodo(muni['provincia']) ?? nodo(r['provincia']);
      if (prov != null) {
        if (prov['nombre'] != null) {
          out['provincia_nombre'] = '${prov['nombre']}';
        }
        if (prov['codigo_ine'] != null) {
          out['provincia_codigo'] = '${prov['codigo_ine']}';
        }
      }
    } else {
      final dep = nodo(r['departamento']);
      if (dep != null) {
        if (dep['nombre'] != null) {
          out['departamento_nombre'] = '${dep['nombre']}';
        }
        if (dep['codigo_ine'] != null) {
          out['departamento_codigo'] = '${dep['codigo_ine']}';
        }
      }
      final prov = nodo(r['provincia']);
      if (prov != null) {
        if (prov['nombre'] != null) {
          out['provincia_nombre'] = '${prov['nombre']}';
        }
        if (prov['codigo_ine'] != null) {
          out['provincia_codigo'] = '${prov['codigo_ine']}';
        }
      }
    }
    final edan = nodo(r['edan']);
    if (edan != null) {
      final idEdan = edan['id_edan'];
      if (idEdan is num) out['id_edan'] = idEdan.toInt();
      final codigo = edan['codigo_edan'];
      if (codigo != null) out['edan_codigo'] = '$codigo';
    } else if (r['id_edan'] is num) {
      out['id_edan'] = (r['id_edan'] as num).toInt();
    }
    return out;
  }

  /// Columnas LOCALES que el pull/`GET /completo` no provee y que un
  /// `INSERT OR REPLACE` borraría (volverían a su DEFAULT). Se preservan
  /// explícitamente si ya existían:
  ///  * `secciones_activas_json` — activación de secciones del usuario; sin
  ///    ella el wizard dejaba de cargar `filas_seccion` al reabrir (los
  ///    grupos marcados `true` no mostraban sus secciones tras sincronizar).
  ///  * `estado_local` — borrador vs. enviado; el servidor no lo conoce.
  ///  * `observacion_estado` — se conserva del valor previo cuando la fila
  ///    que llega del servidor NO trae el campo (listados ligeros que aún no
  ///    lo exponen); si lo trae, manda el servidor.
  Future<Map<String, dynamic>> _columnasPreservadas(
      String uuid, Map<String, dynamic> fila) async {
    final db = await _db.database;
    final previo = await db.query(
      'formularios',
      columns: ['secciones_activas_json', 'estado_local', 'observacion_estado'],
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (previo.isEmpty) return const {};
    final secciones = previo.first['secciones_activas_json'];
    final estado = previo.first['estado_local'];
    final obs = previo.first['observacion_estado'];
    return {
      if (secciones is String && secciones.isNotEmpty && secciones != '{}')
        'secciones_activas_json': secciones,
      if (estado != null) 'estado_local': estado,
      // Preservar el motivo SOLO si la fila que llega no lo trae (el INSERT
      // OR REPLACE lo pondria NULL). Si el servidor lo manda, manda él.
      if (fila['observacion_estado'] == null &&
          obs is String &&
          obs.isNotEmpty)
        'observacion_estado': obs,
    };
  }

  Future<void> _aplicarFormularioPull(Map<String, dynamic> r) async {
    final uuid = r['uuid_edan_localidad'] as String?;
    if (uuid == null || uuid.isEmpty) return;
    if (await _esLocalidadSucia(uuid)) return;
    final db = await _db.database;

    await db.insert(
      'formularios',
      {
        'uuid_edan_localidad': uuid,
        ..._columnasCabecera(r),
        // Flags de GRUPO (`grup_*`): se persisten como columnas para que las
        // páginas del wizard (`_construirPaginas`) y los badges del listado se
        // reconstruyan aunque `datos_json` no las traiga con el mismo nombre.
        // Desde 2026-10-14 las planas vienen sincronizadas (invariante
        // `grup=OR(imp)`) tanto en `/completo` como en el pull plano.
        ..._columnasGrupo(r),
        // `sync/pull` NO escribe `datos_json`: ese snapshot lo rellena el
        // wizard al guardar (`_formularioToRow`) y lo rescata
        // `EdanSeccionesFuente` solo para localidades legacy. El documento
        // CRUDO del servidor vive en `datos_json_servidor` (v34), que escribe
        // `_normalizarDocCompleto` (camino GET /completo). Así las dos vías
        // dejan de pisarse la copia del otro (doble-escritor).
        ...await _columnasPreservadas(uuid, r),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

      // §20.2 + invariante 2026-10-14: las 9 `grup_*` planas (OR de las
    // secciones miembro que deriva el servidor) se cachean en
    // `grupos_local.grup_servidor` para que los badges del listado se pinten
    // sin re-leer el formulario completo.
    await _aplicarGruposPull(uuid, r);
    await _asentarFirma(uuid);
  }

  /// Asienta la firma tras aplicar contenido del servidor (pull/estados):
  /// el contenido es la verdad y el dirty queda en 0. Nunca pisa sucio:
  /// si hay push pendiente, el PUT local posterior gana (LWW).
  Future<void> _asentarFirma(String uuid) async {
    try {
      if (uuid.isEmpty) return;
      if (await _esLocalidadSucia(uuid)) return;
      await EdanStoreV2.instance.recargarFirma(uuid, sincronizada: true);
      EdanStoreV2.instance.datosCambiados();
    } catch (_) {}
  }

  /// Aplica un documento `GET /formularios/{uuid}/completo` NORMALIZÁNDOLO
  /// hacia las tablas fila-a-fila.
  ///
  /// A diferencia de [_aplicarFormularioPull] (que solo escribe la cabecera y
  /// asume que las secciones llegan aparte vía `sync/pull` →
  /// `_aplicarSeccionPull`), el documento `/completo` trae las 14 secciones
  /// ANIDADAS en sus claves `llaveJson`. Sin normalizar, esas filas vivían
  /// solo en el snapshot `datos_json` y `prepararPayloadCompleto` (que lee
  /// `filas_seccion`) las veía vacías: el bug "tengo datos y el JSON/preview
  /// dice que no". Aquí se escriben:
  ///  * cabecera → `formularios` (+ `datos_json_servidor` = doc crudo);
  ///  * `grup_*` planas → columnas + caché `grupos_local.grup_servidor`;
  ///  * las 14 secciones → `filas_seccion` (la verdad local del POST);
  ///  * `danos_vivienda.viviendas[]` → tabla `viviendas`;
  ///  * `fotos[]` → tabla `fotografias`.
  ///
  /// Así el `GET /completo` y el `sync/pull` convergen: las dos vías
  /// normalizan a `filas_seccion`, y la pestaña GET (documento crudo) y la
  /// POST (payload) del diálogo de depuración leen de la MISMA fuente.
  /// Desempaqueta el nodo `cabecera` del documento `GET /formularios/{uuid}/completo`.
  ///
  /// El servidor devuelve el header anidado bajo `cabecera` y las secciones
  /// al nivel superior: `{"cabecera": {...header...}, "grupos": {...}, ...}`.
  /// El código interno (columnas, grupos, secciones) trabaja con el doc
  /// plano (header al nivel superior). Si no hay nodo `cabecera`, devuelve
  /// el doc tal cual (compatibilidad con pull plano y docs sin wrapper).
  /// Implementación compartida con `Edan.fromJson` (misma lógica, una sola
  /// copia): `EdanLocalidad.desempaquetarCabecera`.
  static Map<String, dynamic> unwrapCabecera(Map<String, dynamic> doc) =>
      EdanLocalidad.desempaquetarCabecera(doc);

  Future<void> _normalizarDocCompleto(Map<String, dynamic> docRaw) async {
    // El GET /formularios/{uuid}/completo devuelve el header anidado bajo
    // `cabecera` y las secciones al nivel superior. El código interno trabaja
    // con el doc plano (header al nivel superior); aquí se desempaqueta.
    // `datos_json_servidor` conserva el doc CRUDO (con `cabecera`) para que
    // el diálogo de depuración muestre exactamente lo que la API devuelve.
    final doc = unwrapCabecera(docRaw);
    final uuid = doc['uuid_edan_localidad'] as String?;
    if (uuid == null || uuid.isEmpty) return;
    if (await _esLocalidadSucia(uuid)) return;
    // Un `D` pendiente del formulario también bloquea la normalización: sus
    // secciones no deben volver a escribirse (mismo caso que el pull).
    if (await _tieneDeletePendiente(uuid)) return;
    final db = await _db.database;

    // 1) Cabecera + caché del documento CRUDO (la verdad del servidor). OJO:
    //    NO se escribe `datos_json` (snapshot del modelo local); ese sigue
    //    siendo responsabilidad del wizard. Aquí va `datos_json_servidor`.
    await db.insert(
      'formularios',
      {
        'uuid_edan_localidad': uuid,
        ..._columnasCabecera(doc),
        ..._columnasGrupo(doc),
        'datos_json_servidor': jsonEncode(docRaw),
        ...await _columnasPreservadas(uuid, doc),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _aplicarGruposPull(uuid, doc);

    // 2) Las 14 secciones anidadas → `filas_seccion`. `danos-vivienda` es 1:1
    //    en el servidor con `viviendas[]` anidadas (§20.4): se desanidan
    //    ANTES de guardar, porque localmente las hijas viven en la tabla
    //    `viviendas` (igual que las escribe el wizard y que las relee
    //    `prepararPayloadCompleto`).
    final porTipo = EdanSeccionesFuente.filasDesdeDocumentoApi(doc, uuid);
    final viviendasDelDoc = <Map<String, dynamic>>[];
    final filaPadre = porTipo['danos-vivienda'];
    if (filaPadre != null && filaPadre.isNotEmpty) {
      final padre = filaPadre.first;
      final hijas = padre['viviendas'];
      if (hijas is List) {
        final uuidPadre = padre['uuid_registro'] as String;
        for (final v in hijas) {
          if (v is! Map) continue;
          viviendasDelDoc.add({
            ...Map<String, dynamic>.from(v),
            'uuid_dano_vivienda': v['uuid_dano_vivienda'] ?? uuidPadre,
          });
        }
      }
      padre.remove('viviendas');
    }
    for (final e in porTipo.entries) {
      for (final fila in e.value) {
        // Servicios básicos: en el servidor la EXISTENCIA de la fila es el
        // marcado (no hay columna `afectado`). Se estampa igual que en
        // `_aplicarSeccionPull` para que al descargar el reporte por
        // `/completo` el check vuelva marcado, no solo con los números.
        if (e.key == 'servicios-basicos' &&
            !fila.containsKey('afectado') &&
            !fila.containsKey('impactado')) {
          fila['afectado'] = true;
        }
        // No contaminar `datos_json` con los meta-campos del documento del
        // servidor (ver `sinMetaServidor`): reenviarlos en el PUT pone la
        // fila en error (proteccion, 2026-11-02).
        sinMetaServidor(fila);
        await db.insert(
          'filas_seccion',
          {
            'uuid_registro': fila['uuid_registro'],
            'uuid_edan_localidad': uuid,
            'tipo': e.key,
            'datos_json': jsonEncode(fila),
            'fecha_modificacion_local': fila['fecha_modificacion'],
            'estado_sync': 'confirmado',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }

    // 3) Viviendas desanidadas → tabla `viviendas`.
    for (final v in viviendasDelDoc) {
      await _aplicarViviendaPull(v);
    }

    // 4) `fotos[]` → tabla `fotografias` (solo activas; las borradas lógicas
    //    las trata `_aplicarFotoPull` borrando el registro local).
    final fotos = doc['fotos'];
    if (fotos is List) {
      for (final f in fotos) {
        if (f is! Map) continue;
        await _aplicarFotoPull(<String, dynamic>{
          ...Map<String, dynamic>.from(f),
          'uuid_edan_localidad': f['uuid_edan_localidad'] ?? uuid,
        });
      }
    }
    // El documento vino del servidor: asienta la firma (limpio). Si estaba
    // sucio no se llegó aquí (retorno temprano en la entrada).
    await _asentarFirma(uuid);
  }

  /// Columnas `grup_*` de `formularios` derivadas del documento.
  ///
  /// Desde 2026-10-14 el servidor garantiza el invariante
  /// `grup_* = OR(imp miembros)` y las 9 planas vienen sincronizadas en la
  /// cabecera: **las planas son autoritativas** y se persisten siempre que
  /// vengan presentes. El nodo `grupos` (eliminado del servidor) solo se
  /// acepta como fallback legacy. Si no hay ni planas ni nodo, no se escribe
  /// nada y se conserva lo local.
  static Map<String, int> _columnasGrupo(Map<String, dynamic> r) {
    const cols = [
      'grup_poblacion',
      'grup_salud',
      'grup_infraestructura',
      'grup_servicios',
      'grup_educacion',
      'grup_vivienda',
      'grup_agropecuario',
      'grup_proteccion',
      'grup_necesidades',
    ];
    final out = <String, int>{};
    var planas = 0;
    for (final col in cols) {
      final valor = r[col];
      if (valor != null) {
        out[col] = _bit(valor);
        planas++;
      }
    }
    if (planas > 0) return out;
    final nido = r['grupos'] is Map
        ? Map<String, dynamic>.from(r['grupos'] as Map)
        : const <String, dynamic>{};
    for (final col in cols) {
      final valor = nido[col];
      if (valor != null) out[col] = _bit(valor);
    }
    return out;
  }

  /// Mapeo `grup_*` del servidor → ids locales de la matriz
  /// (`grup_poblacion` → `grupPoblacion`, PLAN_APIS_V2_EDAN §20.2). Vive en
  /// [EdanSeccionesRegistry] para que la traducción tenga UNA sola copia: la
  /// usan el pull y también el JSON de depuración de long-press.
  static Map<String, String> get _grupServidorAId =>
      EdanSeccionesRegistry.idDeGrupApi;

  /// Guarda la caché de grupos del servidor en `grupos_local`. Lee las 9
  /// `grup_*` planas de la fila (autoritativas desde 2026-10-14) con fallback
  /// al nodo `grupos` legacy. No toca `seleccion_usuario`: la selección del
  /// usuario es local y el servidor no la conoce. `INSERT OR IGNORE` +
  /// `UPDATE` de la sola columna del servidor (un `replace` borraría la fila
  /// entera y perdería la selección).
  Future<void> _aplicarGruposPull(
      String uuid, Map<String, dynamic> fila) async {
    final planas = _columnasGrupo(fila);
    if (planas.isEmpty) return;
    final db = await _db.database;
    for (final e in _grupServidorAId.entries) {
      final crudo = planas[e.key];
      if (crudo == null) continue;
      await db.insert(
        'grupos_local',
        {
          'uuid_edan_localidad': uuid,
          'grupo': e.value,
          'seleccion_usuario': 0,
          'grup_servidor': null,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await db.update(
        'grupos_local',
        {'grup_servidor': crudo},
        where: 'uuid_edan_localidad = ? AND grupo = ?',
        whereArgs: [uuid, e.value],
      );
    }
  }

  /// Normaliza un valor booleano/entero del servidor a 0/1 para SQLite.
  static int _bit(Object? v) => (v == true || v == 1) ? 1 : 0;

  Future<void> _aplicarSeccionPull(Map<String, dynamic> r) async {
    final uuid = r['uuid_registro'] as String?;
    if (uuid == null || uuid.isEmpty) return;
    if (await _esLocalidadSucia(uuid)) return;
    final db = await _db.database;
    var uuidLoc = r['uuid_edan_localidad'] as String? ?? '';
    if (uuidLoc.isEmpty && r['id_edan_localidad'] != null) {
      final f = await db.query(
        'formularios',
        columns: ['uuid_edan_localidad'],
        where: 'id_server = ?',
        whereArgs: [r['id_edan_localidad']],
        limit: 1,
      );
      if (f.isNotEmpty) {
        uuidLoc = f.first['uuid_edan_localidad'] as String? ?? '';
      }
    }
    // Un `D` pendiente del formulario protege a sus hijas aunque ya no quede
    // rastro local (el dueño se lee del dato del pull, no de la DB): si no,
    // el pull resucita secciones de una localidad que se está por borrar.
    if (await _tieneDeletePendiente(uuidLoc)) return;
    // El pull trae `tipo_seccion` con nombre de TABLA (`danos_agricultura`);
    // la columna `tipo` guarda SIEMPRE ruta (`danos-agricultura`, como el
    // wizard). Sin normalizar, la fila queda invisible para preview, payload
    // y flags (caso Urubo en vivo).
    final tipoCrudo = (r['tipo_seccion'] ?? r['tipo'] ?? '').toString();
    final tipo = tipoCrudo.isEmpty
        ? ''
        : EdanSeccionesRegistry.rutaDesdeTabla(tipoCrudo);
    // Servicios básicos: el servidor no tiene columna `afectado` — allí LA
    // EXISTENCIA de la fila ES el marcado. Se estampa al asentar la fila
    // (y solo si el JSON no trae la clave) para que otro dispositivo que
    // baje este reporte vea el checkbox activo, no solo los números.
    if (tipo == 'servicios-basicos' &&
        !r.containsKey('afectado') &&
        !r.containsKey('impactado')) {
      r['afectado'] = true;
    }
    // El documento del servidor trae por fila `tipo_seccion` e ids servidos;
    // persistirlos contamina `datos_json` y el PUT de vuelta los rechaza
    // ("campo desconocido o no escribible", proteccion 2026-11-02). El tipo
    // YA quedó capturado en la variable `tipo` (columna `tipo`).
    sinMetaServidor(r);
    await db.insert(
      'filas_seccion',
      {
        'uuid_registro': uuid,
        'uuid_edan_localidad': uuidLoc,
        'tipo': tipo,
        'datos_json': jsonEncode(r),
        'fecha_modificacion_local': r['fecha_modificacion'],
        'estado_sync': 'confirmado',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _asentarFirma(uuidLoc);
  }

  Future<void> _aplicarViviendaPull(Map<String, dynamic> r) async {
    final uuid = r['uuid_registro'] as String?;
    if (uuid == null || uuid.isEmpty) return;
    if (await _esLocalidadSucia(uuid)) return;
    // Igual que secciones: el dueño sale del dato del pull (la fila padre
    // puede ya no existir localmente si el formulario tiene `D` pendiente).
    final uuidLocPull = r['uuid_edan_localidad'] as String?;
    if (uuidLocPull != null &&
        uuidLocPull.isNotEmpty &&
        await _tieneDeletePendiente(uuidLocPull)) {
      return;
    }
    final db = await _db.database;
    await db.insert(
      'viviendas',
      {
        'uuid_registro': uuid,
        'uuid_dano_vivienda': r['uuid_dano_vivienda'] ?? '',
        'tipo_dano': (r['tipo_dano'] as String? ?? 'PARCIAL').toUpperCase(),
        // El servidor manda las coordenadas de `viviendas` como STRING
        // (verificado en vivo 2026-11-03, snackbar capturado: "type 'String'
        // is not a subtype of type 'num?'"): el `as num?` lanzaba TypeError,
        // esa 1 vivienda era el "Pull parcial: 1 de 28" de la app limpia y,
        // al no ackar el watermark, la alerta se repetía en CADA sync.
        'coordenada_lat': _doubleDeServidor(r['coordenada_lat']),
        'coordenada_lon': _doubleDeServidor(r['coordenada_lon']),
        'fotografia': r['fotografia'],
        'fecha_modificacion_local': r['fecha_modificacion'],
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (uuidLocPull != null && uuidLocPull.isNotEmpty) {
      await _asentarFirma(uuidLocPull);
    }
  }

  /// Resuelve el `uuid_edan_localidad` dueño de una foto del pull. El
  /// servidor NO siempre manda el campo dentro de `fotos` (a veces solo el
  /// `id_edan_localidad` numérico y el `uuid_registro` de la dueña — verificado
  /// en vivo 2026-11-02 con el documento de "Escoma"): escribir `''` en ese
  /// caso deja la foto invisible en la galería (el JOIN con `formularios`)
  /// para SIEMPRE, y en REPLACE pisa el valor ya resuelto localmente. Cadena:
  /// campo directo → formulario por `id_server` → dueña local (la foto es de
  /// cabecera, de fila de sección, o de hija `viviendas` → fila del padre).
  /// `null` = irresoluble.
  Future<String?> _resolverUuidLocalidadFoto(
    DatabaseExecutor db,
    Map<String, dynamic> r,
  ) async {
    final directo = r['uuid_edan_localidad'] as String?;
    if (directo != null && directo.isNotEmpty) return directo;
    // El documento del servidor identifica al formulario por su PK numérica
    // (`id_edan_localidad` = `formularios.id_server` local): única vía cuando
    // el pull no manda el uuid.
    if (r['id_edan_localidad'] != null) {
      final f = await db.query(
        'formularios',
        columns: ['uuid_edan_localidad'],
        where: 'id_server = ?',
        whereArgs: [r['id_edan_localidad']],
        limit: 1,
      );
      if (f.isNotEmpty) {
        final u = f.first['uuid_edan_localidad'] as String?;
        if (u != null && u.isNotEmpty) return u;
      }
    }
    // Dueña local de la fila `uuid_registro` (cabecera, sección, vivienda o
    // foto): cadena ya probada en `_uuidLocalidadDeRegistro`.
    return _uuidLocalidadDeRegistro((r['uuid_registro'] ?? '').toString());
  }

  Future<void> _aplicarFotoPull(Map<String, dynamic> r) async {
    final uuid = r['uuid_fotografia'] as String?;
    if (uuid == null || uuid.isEmpty) return;
    final db = await _db.database;
    final borrado = r['borrado_logico'] == true || r['borrado_logico'] == 1;
    final duenoResuelto = await _resolverUuidLocalidadFoto(db, r);
    if (!borrado) {
      // No revivir fotos de una localidad con `D` pendiente (el dueño sale
      // del dato del pull, resuelto con la cadena completa).
      if (duenoResuelto != null &&
          duenoResuelto.isNotEmpty &&
          await _tieneDeletePendiente(duenoResuelto)) {
        return;
      }
    }
    if (borrado) {
      final local = await db.query(
        'fotografias',
        columns: ['ruta_local'],
        where: 'uuid_fotografia = ?',
        whereArgs: [uuid],
        limit: 1,
      );
      if (local.isNotEmpty) {
        final ruta = local.first['ruta_local'] as String?;
        if (ruta != null && ruta.isNotEmpty) {
          try {
            final f = File(ruta);
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }
      }
      await db.delete('fotografias',
          where: 'uuid_fotografia = ?', whereArgs: [uuid]);
      return;
    }
    // REPLACE que preserva lo local: `ruta_local` (bytes ya bajados),
    // `last_error` (marcas 404/failed) e intentos. Sin esto, cada pull
    // re-enviando la misma foto borraba la ruta y re-descargaba en loop.
    // Si cambió `ruta_archivo` (foto reemplazada arriba), se rehabilita:
    // se limpia ruta/error/intentos para bajar la nueva.
    final previa = await db.query(
      'fotografias',
      columns: ['ruta_local', 'ruta_servidor', 'last_error', 'uuid_edan_localidad'],
      where: 'uuid_fotografia = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    String? rutaLocalPrevia;
    String? errorPrevio;
    if (previa.isNotEmpty) {
      final rutaNueva = r['ruta_archivo'] as String?;
      final rutaVieja = previa.first['ruta_servidor'] as String?;
      if (rutaNueva == null ||
          rutaNueva.isEmpty ||
          rutaNueva == rutaVieja) {
        rutaLocalPrevia = previa.first['ruta_local'] as String?;
        errorPrevio = previa.first['last_error'] as String?;
      }
    }
    // Enlace del dueño para el REPLACE de abajo: lo que el pull trae o se
    // puede resolver; si nada resuelve, PRESERVAR el enlace local existente
    // (pisarlo con '' invisibilizaba la foto en la galería de ambos roles).
    var uuidLocFoto = duenoResuelto;
    if ((uuidLocFoto == null || uuidLocFoto.isEmpty) && previa.isNotEmpty) {
      final local = previa.first['uuid_edan_localidad'] as String?;
      if (local != null && local.isNotEmpty) uuidLocFoto = local;
    }
    await db.insert(
      'fotografias',
      {
        'uuid_fotografia': uuid,
        'uuid_edan_localidad': uuidLocFoto ?? '',
        'tipo_entidad': r['tipo_entidad'] ?? '',
        'uuid_registro': r['uuid_registro'] ?? '',
        'ruta_servidor': r['ruta_archivo'],
        'sha256': r['sha256'],
        'borrado_logico': 0,
        'fecha_modificacion':
            r['fecha_modificacion'] ?? DateTime.now().toIso8601String(),
        if (rutaLocalPrevia != null && rutaLocalPrevia.isNotEmpty)
          'ruta_local': rutaLocalPrevia,
        if (errorPrevio != null && errorPrevio.isNotEmpty)
          'last_error': errorPrevio,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // LWW 1-activa-por-fila: si el servidor trae una activa y local queda
    // otra del mismo dueño ya sincronizada (reemplazo desde otro equipo),
    // se retira localmente. Las pendientes de subida NO se tocan: al
    // subirse ganan (LWW) y la confirmación retira a esta.
    try {
      final otras = await db.rawQuery('''
        SELECT uuid_fotografia AS u, ruta_local AS ruta FROM fotografias
        WHERE uuid_fotografia != ?
          AND tipo_entidad = ? AND uuid_registro = ?
          AND borrado_logico = 0
          AND ruta_servidor IS NOT NULL AND ruta_servidor != ''
          AND NOT EXISTS (SELECT 1 FROM cola_fotos c
                          WHERE c.uuid_fotografia = fotografias.uuid_fotografia)
      ''', [
        uuid,
        r['tipo_entidad'] ?? '',
        r['uuid_registro'] ?? '',
      ]);
      for (final o in otras) {
        final u = o['u'] as String?;
        if (u == null || u.isEmpty) continue;
        await db.delete('fotografias',
            where: 'uuid_fotografia = ?', whereArgs: [u]);
        final ruta = o['ruta'] as String?;
        if (ruta != null && ruta.isNotEmpty) {
          try {
            final f = File(ruta);
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Marca en `fotografias.last_error` cuando el archivo no existe en el
  /// servidor (404 definitivo). Mientras esté presente no se reintenta la
  /// descarga en cada sync; se limpia sola cuando el pull trae otra
  /// `ruta_archivo` (rehabilita la fila).
  static const String _marcaNoEncontrada = 'no-existe-en-servidor';

  /// Espera progresiva de descarga (minutos) por intento fallido.
  static const _backoffDescargaMin = [1, 5, 15];

  /// Registra un fallo de descarga no-404: suma intento, programa backoff y
  /// al 3er fallo deja `failed` + motivo VISIBLE (tope acordado: no loop
  /// caliente). Se rehabilita con metadatos nuevos del pull o reintento
  /// manual. Nunca lanza.
  Future<void> _falloDescargaFoto(String uuid, String motivo) async {
    try {
      final db = await _db.database;
      final rows = await db.query(
        'fotografias',
        columns: ['intentos_descarga'],
        where: 'uuid_fotografia = ?',
        whereArgs: [uuid],
        limit: 1,
      );
      final intentos =
          ((rows.isEmpty ? null : rows.first['intentos_descarga']) as num?)
                  ?.toInt() ??
              0;
      final nuevos = intentos + 1;
      if (nuevos >= 3) {
        // `failed` visible = intentos>=3 + motivo (el query ya no la
        // selecciona). No se toca `upload_state`: es del canal de subida.
        await db.update(
          'fotografias',
          {
            'intentos_descarga': nuevos,
            'last_error': 'Descarga fallida tras 3 intentos: $motivo',
            'fecha_proximo_intento': null,
          },
          where: 'uuid_fotografia = ?',
          whereArgs: [uuid],
        );
        debugPrint('[SyncV2] foto $uuid: descarga failed ($motivo)');
        return;
      }
      final esperaMin = _backoffDescargaMin[
          nuevos.clamp(0, _backoffDescargaMin.length - 1)];
      final proximo = DateTime.now()
          .add(Duration(minutes: esperaMin))
          .toIso8601String();
      await db.update(
        'fotografias',
        {
          'intentos_descarga': nuevos,
          'last_error': 'Descarga fallida (intento $nuevos/3): $motivo',
          'fecha_proximo_intento': proximo,
        },
        where: 'uuid_fotografia = ?',
        whereArgs: [uuid],
      );
    } catch (_) {}
  }

  /// Descarga los bytes de las fotos que el pull registró con `ruta_servidor`
  /// pero sin `ruta_local` (recuperación en un dispositivo nuevo: se perdieron
  /// los archivos al perder el celular). Metadatos por
  /// `GET /fotografias/{uuid}` + bytes por URL estática
  /// (`EdanApiV2.descargarBytesFoto`). Guarda cada imagen en [_dirFotos] con
  /// su extensión real y actualiza `ruta_local` para que quede disponible
  /// offline. Publica el progreso en el store (total/hechas) para la barra de
  /// la descarga inicial. Si no hay carpeta inyectada o una descarga falla,
  /// se omite sin romper el sync (los metadatos ya quedaron aplicados).
  Future<EdanSyncResumen> _descargarFotosPendientes(
    EdanSyncResumen previo,
  ) async {
    final dir = _dirFotos;
    if (dir == null) {
      // Antes era silencio total: metadatos sin bytes y nadie lo decía.
      debugPrint('[SyncV2] descarga de fotos omitida: sin carpeta local');
      if (kSyncDebugMode) {
        SyncDebugCollector.instance.addDiagnostico('Fotos descarga', {
          'omitida': 'sin carpeta local (dirFotos null)',
        });
      }
      return previo;
    }
    final db = await _db.database;
    final ahora = DateTime.now().toIso8601String();
    final rows = await db.query(
      'fotografias',
      columns: [
        'uuid_fotografia',
        'ruta_servidor',
        'last_error',
        'sha256',
        'size_bytes',
        'intentos_descarga',
      ],
      where: "borrado_logico = 0 AND ruta_servidor IS NOT NULL "
          "AND ruta_servidor != '' AND (ruta_local IS NULL OR ruta_local = '') "
          "AND (intentos_descarga IS NULL OR intentos_descarga < 3) "
          "AND (fecha_proximo_intento IS NULL OR fecha_proximo_intento <= ?)",
      whereArgs: [ahora],
    );
    if (rows.isEmpty) return previo;

    await dir.create(recursive: true);
    int descargadas = previo.fotosDescargadas;
    _progresoFotos(rows.length, 0);
    var hechas = 0;
    for (final raw in rows) {
      // Cada foto aislada: un disco lleno o un archivo corrupto no tumba
      // la corrida entera (antes `writeAsBytes` propagaba y el sync
      // completo terminaba en `exito=false`).
      try {
        final uuid = raw['uuid_fotografia'] as String;
        final rutaServidor = raw['ruta_servidor'] as String;
        // Archivo ya confirmado como inexistente en el servidor: no
        // martillarlo en cada sync (se reintenta solo si cambian los
        // metadatos, que limpian el marcador vía pull).
        final marcador = raw['last_error'] as String?;
        if (marcador != null && marcador.contains(_marcaNoEncontrada)) {
          continue;
        }
        var status = 0;
        final bytes = await _api.descargarBytesFoto(
          uuidFotografia: uuid,
          rutaArchivo: rutaServidor,
          onHttpStatus: (s) => status = s,
        );
        if (bytes == null || bytes.isEmpty) {
          if (status == 404) {
            await db.update(
              'fotografias',
              {
                'last_error':
                    'Archivo no encontrado en el servidor ($_marcaNoEncontrada)',
              },
              where: 'uuid_fotografia = ?',
              whereArgs: [uuid],
            );
            debugPrint('[SyncV2] foto $uuid: $_marcaNoEncontrada');
          } else {
            await _falloDescargaFoto(
                uuid, 'sin bytes del servidor (status $status)');
          }
          continue;
        }
        // Verificar integridad si el servidor dio sha256: un 200 truncado
        // no debe quedar como archivo válido.
        final shaEsperado = raw['sha256'] as String?;
        if (shaEsperado != null && shaEsperado.isNotEmpty) {
          final shaReal =
              sha256.convert(bytes).toString();
          if (shaReal != shaEsperado.toLowerCase()) {
            await _falloDescargaFoto(uuid, 'sha256 no coincide');
            continue;
          }
        }
        // Conservar la extensión REAL del servidor (.png, .webp…): forzar
        // `.jpg` dejaba mal el `mime_type` inferido por extensión.
        final nombre = uuid.isNotEmpty
            ? '$uuid${_extensionDeRuta(rutaServidor)}'
            : rutaServidor.replaceAll('/', '_');
        // Atómico: tmp + rename. Un kill a media escritura no deja un
        // archivo corrupto pasando por válido.
        final tmp = File('${dir.path}/$nombre.tmp');
        await tmp.writeAsBytes(bytes, flush: true);
        final archivo = File('${dir.path}/$nombre');
        try {
          if (await archivo.exists()) await archivo.delete();
          await tmp.rename(archivo.path);
        } catch (_) {
          // rename entre volúmenes puede fallar: copia como respaldo.
          await tmp.copy(archivo.path);
          try {
            await tmp.delete();
          } catch (_) {}
        }
        await db.update(
          'fotografias',
          {
            'ruta_local': archivo.path,
            'last_error': null,
            'intentos_descarga': 0,
            'fecha_proximo_intento': null,
          },
          where: 'uuid_fotografia = ?',
          whereArgs: [uuid],
        );
        descargadas++;
      } catch (e) {
        debugPrint('[SyncV2] descarga de foto omitida: $e');
      } finally {
        hechas++;
        _progresoFotos(rows.length, hechas);
      }
    }
    return EdanSyncResumen(
      exito: previo.exito,
      enviados: previo.enviados,
      conflictos: previo.conflictos,
      errores: previo.errores,
      fotosSubidas: previo.fotosSubidas,
      fotosPendientes: previo.fotosPendientes,
      fotosDescargadas: descargadas,
      ultimoError: previo.ultimoError,
      watermark: previo.watermark,
    );
  }

  /// Extensión de imagen desde una ruta del servidor (`.png`, `.webp`…);
  /// `.jpg` si no se puede determinar o no es imagen conocida.
  static String _extensionDeRuta(String ruta) {
    final punto = ruta.lastIndexOf('.');
    final slash = ruta.lastIndexOf('/');
    if (punto < 0 || punto < slash) return '.jpg';
    final ext = ruta.substring(punto).toLowerCase();
    const validas = {
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.gif',
      '.bmp',
      '.tif',
      '.tiff',
      '.heic',
      '.heif',
      '.avif',
    };
    return validas.contains(ext) ? ext : '.jpg';
  }

  /// Publica el progreso de descarga de fotos en el store (best-effort: la
  /// UI es opcional y el sync no depende de ella).
  void _progresoFotos(int total, int hechas) {
    try {
      final store = EdanStoreV2.instance;
      store.descargaFotosTotal.value = total;
      store.descargaFotosHechas.value = hechas;
    } catch (_) {}
  }

  Future<void> _aplicarTombstonePull(Map<String, dynamic> t) async {
    final tabla = t['tabla'] as String? ?? '';
    // `toString()` defensivo: el servidor puede traer el id numérico en
    // alguna tabla y un `as String?` lanzaría TypeError (que hoy ya no
    // bloquea el ack, pero tampoco debe ensuciar el registro).
    final id = (t['id_registro'] ?? t['uuid_registro'])?.toString();
    if (id == null || id.isEmpty) return;
    // P6: nunca pisar una localidad sucia (pendiente_push/cola): el push
    // local es la fuente de verdad y el tombstone se re-evalúa en el próximo
    // pull, cuando ya no haya cambios sin enviar.
    final uuidLocalidad = await _uuidLocalidadDeTombstone(tabla, id);
    if (uuidLocalidad != null && await _esLocalidadSucia(uuidLocalidad)) return;
    final db = await _db.database;
    if (tabla == 'edan_localidades' || tabla == 'edan') {
      await db.delete('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: [id]);
      await db.delete('filas_seccion',
          where: 'uuid_edan_localidad = ?', whereArgs: [id]);
      return;
    }
    if (tabla == 'edan_localidades_viviendas') {
      await db.delete('viviendas', where: 'uuid_registro = ?', whereArgs: [id]);
      return;
    }
    if (tabla == 'fotografias') {
      await db.delete('fotografias',
          where: 'uuid_fotografia = ?', whereArgs: [id]);
      return;
    }
    // Secciones (14 tablas): borra la fila por su uuid_registro.
    await db.delete('filas_seccion', where: 'uuid_registro = ?', whereArgs: [id]);
    await db.delete('viviendas', where: 'uuid_registro = ?', whereArgs: [id]);
  }

  /// Resuelve el `uuid_edan_localidad` dueño de un tombstone para el chequeo
  /// de sucio de [_aplicarTombstonePull]. `null` = sin dueño resoluble
  /// (se aplica igual: no hay nada local que proteger).
  Future<String?> _uuidLocalidadDeTombstone(String tabla, String id) async {
    if (tabla == 'edan_localidades' || tabla == 'edan') return id;
    final db = await _db.database;
    if (tabla == 'fotografias') {
      final f = await db.query('fotografias',
          columns: ['uuid_edan_localidad'],
          where: 'uuid_fotografia = ?',
          whereArgs: [id],
          limit: 1);
      if (f.isNotEmpty) return f.first['uuid_edan_localidad'] as String?;
      return null;
    }
    final fila = await db.query('filas_seccion',
        columns: ['uuid_edan_localidad'],
        where: 'uuid_registro = ?',
        whereArgs: [id],
        limit: 1);
    if (fila.isNotEmpty) return fila.first['uuid_edan_localidad'] as String?;
    final viv = await db.rawQuery('''
      SELECT s.uuid_edan_localidad AS u FROM filas_seccion s
      JOIN viviendas v ON v.uuid_dano_vivienda = s.uuid_registro
      WHERE v.uuid_registro = ? LIMIT 1
    ''', [id]);
    if (viv.isNotEmpty) return viv.first['u'] as String?;
    return null;
  }

  Future<bool> _esLocalidadSucia(String uuidRegistro) async {
    final db = await _db.database;
    // Fase D: la cola solo contiene `D` (borrados); los C/U ya no existen.
    // El marcador de "sucio" principal ahora es `formularios.pendiente_push=1`.
    // `uuidRegistro` puede ser el uuid de la cabecera, de una fila de sección
    // o de una vivienda; en los dos últimos casos hay que resolver el padre.
    final pendiente = await db.rawQuery('''
      SELECT 1 FROM formularios
      WHERE pendiente_push = 1 AND (
        uuid_edan_localidad = ?
        OR uuid_edan_localidad IN (
          SELECT uuid_edan_localidad FROM filas_seccion WHERE uuid_registro = ?
        )
        OR uuid_edan_localidad IN (
          SELECT s.uuid_edan_localidad FROM filas_seccion s
          JOIN viviendas v ON v.uuid_dano_vivienda = s.uuid_registro
          WHERE v.uuid_registro = ?
        )
      )
      LIMIT 1
    ''', [uuidRegistro, uuidRegistro, uuidRegistro]);
    if (pendiente.isNotEmpty) return true;
    final cola = await db.query(
      'cola_sincronizacion',
      columns: ['id'],
      where: 'uuid_registro = ? AND estado IN (?,?)',
      whereArgs: [uuidRegistro, 'pendiente', 'subiendo'],
      limit: 1,
    );
    if (cola.isNotEmpty) return true;
    // Un `D` pendiente del FORMULARIO protege también a sus hijas: el pull
    // no debe resucitar secciones/viviendas/fotos de una localidad que se
    // está por borrar en el servidor (bug verificado: la cabecera quedaba
    // limpia pero sus filas volvían como huérfanas).
    final uuidLoc = await _uuidLocalidadDeRegistro(uuidRegistro);
    if (uuidLoc != null && await _tieneDeletePendiente(uuidLoc)) return true;
    return false;
  }

  /// `true` si hay un borrado (`D`) pendiente del formulario [uuidLoc].
  Future<bool> _tieneDeletePendiente(String uuidLoc) async {
    if (uuidLoc.isEmpty) return false;
    final db = await _db.database;
    final rows = await db.query(
      'cola_sincronizacion',
      columns: ['id'],
      where: "tabla = 'formulario' AND uuid_registro = ? "
          "AND accion = 'D' AND estado IN ('pendiente','subiendo')",
      whereArgs: [uuidLoc],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Resuelve el `uuid_edan_localidad` dueño de cualquier uuid del dominio
  /// (cabecera, fila, vivienda o foto). `null` si no se resuelve.
  Future<String?> _uuidLocalidadDeRegistro(String uuidRegistro) async {
    if (uuidRegistro.isEmpty) return null;
    final db = await _db.database;
    final form = await db.query(
      'formularios',
      columns: ['uuid_edan_localidad'],
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuidRegistro],
      limit: 1,
    );
    if (form.isNotEmpty) {
      return form.first['uuid_edan_localidad'] as String?;
    }
    final fila = await db.query(
      'filas_seccion',
      columns: ['uuid_edan_localidad'],
      where: 'uuid_registro = ?',
      whereArgs: [uuidRegistro],
      limit: 1,
    );
    if (fila.isNotEmpty) {
      return fila.first['uuid_edan_localidad'] as String?;
    }
    final viv = await db.rawQuery(
      'SELECT s.uuid_edan_localidad AS u FROM filas_seccion s '
      'JOIN viviendas v ON v.uuid_dano_vivienda = s.uuid_registro '
      'WHERE v.uuid_registro = ? LIMIT 1',
      [uuidRegistro],
    );
    if (viv.isNotEmpty) return viv.first['u'] as String?;
    final foto = await db.query(
      'fotografias',
      columns: ['uuid_edan_localidad'],
      where: 'uuid_fotografia = ?',
      whereArgs: [uuidRegistro],
      limit: 1,
    );
    if (foto.isNotEmpty) {
      return foto.first['uuid_edan_localidad'] as String?;
    }
    return null;
  }

  Future<void> _ack(String watermark) async {
    final idDispositivo = await _idDispositivo;
    await _api.ack(
      idDispositivo: idDispositivo,
      watermark: watermark,
    );
    await _guardarWatermark(watermark);
  }

  /// Libera operaciones que quedaron en `subiendo` por un cierre
  /// inesperado (kill a mitad de sync): vuelven a `pendiente` para que la
  /// corrida actual las reprocese. Sin lease temporal: cualquier `subiendo`
  /// al arrancar una corrida es por definición vencido, porque el lock de
  /// corrida (`sincronizandoNotifier`) ya garantizó que no hay otra activa.
  Future<void> _recuperarSubiendoVencidos() async {
    final db = await _db.database;
    await db.update(
      'cola_sincronizacion',
      {'estado': 'pendiente'},
      where: "estado = 'subiendo'",
    );
    await db.update(
      'cola_fotos',
      {'estado': 'pendiente'},
      where: "estado = 'subiendo'",
    );
  }

  // ── Push sync ──

  Future<EdanSyncResumen> _pushSync(EdanSyncResumen previo) async {
    final db = await _db.database;

    // Fase D: 1) enviar cada formulario con pendiente_push=1 vía
    // POST /formularios/completo (una sola llamada por formulario).
    // Con usuario informado, solo sus filas (las de otro usuario del mismo
    // equipo esperan a su sesión; el servidor además lo exige por scope).
    final u = usuarioId;
    final pendientes = await db.query(
      'formularios',
      where: u == null
          ? 'pendiente_push = 1'
          : '(pendiente_push = 1) AND (id_usuario = ? OR id_usuario IS NULL)',
      whereArgs: u == null ? null : [u],
      limit: 200,
    );

    int enviados = previo.enviados;
    int conflictos = previo.conflictos;
    int errores = previo.errores;
    String? ultimoError = previo.ultimoError;

    for (final row in pendientes) {
      final uuid = row['uuid_edan_localidad'] as String;
      try {
        final envio = await _pushFormularioCompleto(uuid, row);
        await _confirmarPushLocalidad(
          uuid,
          firmaEnviada: envio.firma,
          pushStartIso: envio.pushStartIso,
          destinoCapturado: envio.destino,
          submitCapturado: envio.submit,
        );
        enviados++;
      } on EdanApiConflict catch (c) {
        // LWW (2026-10-16): el 409 por versión ya no existe en el servidor
        // (verificado en vivo: PUT/POST sin `version` → 200). Se conserva el
        // catch por defensa: queda pendiente con el motivo, sin snapshot ni
        // contador de conflictos (siempre 0).
        errores++;
        ultimoError = c.toString();
        await _rawUpdate(
          "UPDATE formularios SET pendiente_push = 1 WHERE uuid_edan_localidad = ?",
          [uuid],
        );
      } on EdanApiError catch (e) {
        // Sesión expirada: abortar la corrida con mensaje accionable (los
        // demás ítems quedarían igual); no marcar rechazos ni backoffs.
        if (_esSesionExpirada(e)) {
          errores++;
          ultimoError = _mensajeSesionExpirada;
          break;
        }
        errores++;
        // Conservar el mensaje real del servidor para que la UI lo muestre
        // (antes se perdía y solo se veía "La sincronización falló").
        ultimoError = e.detail;
        await _rawUpdate(
          "UPDATE formularios SET pendiente_push = 1 WHERE uuid_edan_localidad = ?",
          [uuid],
        );
      } on SocketException {
        break; // sin red: no seguir intentando
      }
    }

    // 2) procesar la cola (ahora solo contiene accion='D' de borrados).
    return _procesarCola(previo, enviados, conflictos, errores,
        ultimoError: ultimoError);
  }

  /// Paso 2 del push: ejecuta `cola_sincronizacion`, que desde la Fase D solo
  /// contiene borrados (`accion='D'`), propagados por las APIs nuevas
  /// (`DELETE /formularios/{uuid_ref}`, `…/secciones/{tipo}/{uuid_fila}`,
  /// `…/viviendas/{uuid_v}` y `DELETE /fotografias/{uuid}`).
  ///
  /// Está separado de [sincronizar] porque [procesarBorrados] lo invoca solo:
  /// al borrar una fila desde el wizard hay que propagar el `D` al instante,
  /// sin arrastrar un `pull` completo.
  Future<EdanSyncResumen> _procesarCola(
    EdanSyncResumen previo,
    int enviados,
    int conflictos,
    int errores, {
    String? ultimoError,
  }) async {
    final db = await _db.database;
    final items = await db.rawQuery('''
      SELECT * FROM cola_sincronizacion
      WHERE estado IN ('pendiente','subiendo')
        AND (fecha_proximo_intento IS NULL OR fecha_proximo_intento <= ?)
      ORDER BY
        CASE tabla
          WHEN 'formulario' THEN 0
          WHEN 'filas_seccion' THEN 1
          WHEN 'vivienda' THEN 2
          ELSE 3
        END,
        fecha_registro ASC
      LIMIT 200
    ''', [DateTime.now().toIso8601String()]);

    for (final raw in items) {
      final item = EdanColaItem.fromMap(raw);
      // Con usuario informado, los ítems de otro dueño esperan a su sesión
      // (se dejan pendientes sin tocarlos): el servidor además los
      // rechazaría por scope.
      if (usuarioId != null && !(await _colaItemEsDeUsuario(item))) {
        continue;
      }
      try {
        await _rawUpdate(
          "UPDATE cola_sincronizacion SET estado = 'subiendo' WHERE id = ?",
          [item.id],
        );
        await _ejecutarAccionSync(item);
        await _marcarPushExitoso(item);
        await _rawDelete(
          'DELETE FROM cola_sincronizacion WHERE id = ?',
          [item.id],
        );
        enviados++;
      } on EdanApiConflict catch (c) {
        // LWW: 409 imposible en el servidor; defensa sin snapshot.
        errores++;
        ultimoError = c.toString();
        await _rawUpdate(
          "UPDATE cola_sincronizacion SET estado = 'pendiente', ultimo_error = ? WHERE id = ?",
          [c.toString(), item.id],
        );
      } on EdanApiError catch (e) {
        // Un borrado (`D`) con 404 = el registro ya no existe en el servidor
        // (nunca se subió o se borró en otro lado): objetivo cumplido, se
        // purga la cola sin contarlo como error.
        if (item.accion == 'D' && e.statusCode == 404) {
          await _rawDelete(
            'DELETE FROM cola_sincronizacion WHERE id = ?',
            [item.id],
          );
          enviados++;
          continue;
        }
        // Sesión expirada: abortar con mensaje accionable.
        if (_esSesionExpirada(e)) {
          errores++;
          ultimoError = _mensajeSesionExpirada;
          await _rawUpdate('''
            UPDATE cola_sincronizacion
            SET estado = 'pendiente', ultimo_error = ?
            WHERE id = ?
          ''', [_mensajeSesionExpirada, item.id]);
          break;
        }
        errores++;
        ultimoError = e.detail;
        // P5: 400/403/404/422 son definitivos (dato/regla/permiso) → rechazar,
        // sin backoff infinito. Solo red/5xx reintentan.
        if (_esRechazoDefinitivo(e.statusCode)) {
          await _rawUpdate('''
            UPDATE cola_sincronizacion
            SET estado = 'rechazado',
                ultimo_error = ?
            WHERE id = ?
          ''', [e.detail, item.id]);
        } else {
          final intentos = item.intentos + 1;
          final proximo = _backoff(intentos);
          await _rawUpdate('''
            UPDATE cola_sincronizacion
            SET estado = 'pendiente',
                intentos = ?,
                fecha_proximo_intento = ?,
                ultimo_error = ?
            WHERE id = ?
          ''', [intentos, proximo, e.detail, item.id]);
        }
      } on SocketException {
        ultimoError ??= 'Sin conexión';
        await _rawUpdate('''
          UPDATE cola_sincronizacion
          SET estado = 'pendiente', ultimo_error = ?
          WHERE id = ?
        ''', ['Sin conexión', item.id]);
        break;
      }
    }

    return EdanSyncResumen(
      exito: previo.exito && conflictos == 0 && errores == 0,
      enviados: enviados,
      conflictos: conflictos,
      errores: errores,
      fotosSubidas: previo.fotosSubidas,
      fotosPendientes: previo.fotosPendientes,
      fotosDescargadas: previo.fotosDescargadas,
      ultimoError: ultimoError,
      watermark: previo.watermark,
    );
  }

  /// `true` si el ítem de cola pertenece al [usuarioId] del motor (o no se
  /// puede resolver dueño: se procesa y el scope del servidor decide).
  /// Las filas sin `id_usuario` (legado/migración) también se procesan.
  Future<bool> _colaItemEsDeUsuario(EdanColaItem item) async {
    final u = usuarioId;
    if (u == null) return true;
    final db = await _db.database;
    List<Map<String, Object?>> rows;
    switch (item.tabla) {
      case 'formulario':
        rows = await db.query(
          'formularios',
          columns: ['id_usuario'],
          where: 'uuid_edan_localidad = ?',
          whereArgs: [item.uuidRegistro],
          limit: 1,
        );
      case 'filas_seccion':
        rows = await db.rawQuery(
          'SELECT f.id_usuario AS id_usuario FROM formularios f '
          'JOIN filas_seccion s ON s.uuid_edan_localidad = f.uuid_edan_localidad '
          'WHERE s.uuid_registro = ? LIMIT 1',
          [item.uuidRegistro],
        );
      case 'vivienda':
        rows = await db.rawQuery(
          'SELECT f.id_usuario AS id_usuario FROM formularios f '
          'JOIN filas_seccion s ON s.uuid_edan_localidad = f.uuid_edan_localidad '
          'JOIN viviendas v ON v.uuid_dano_vivienda = s.uuid_registro '
          'WHERE v.uuid_registro = ? LIMIT 1',
          [item.uuidRegistro],
        );
      default:
        return true;
    }
    if (rows.isEmpty) return true;
    final dueno = rows.first['id_usuario'];
    if (dueno == null) return true;
    return (dueno as num?)?.toInt() == u;
  }

  /// Extrae `imp_*` del detail "El flag imp_X=true pero la sección … no trae
  /// filas…". `null` si el error es otro.
  static String? _flagSinFilasDe(String detail) {
    final m = RegExp(r'imp_[a-z_]+').firstMatch(detail);
    return m?.group(0);
  }

  /// `fecha_modificacion` de un documento `{cabecera, ...}` para asentar el
  /// watermark (§20.15: string opaco, se compara por string, sin parsear).
  static String? _fechaDoc(Map<String, dynamic> doc) {
    try {
      final cab = unwrapCabecera(doc);
      final fm = cab['fecha_modificacion'];
      return fm is String && fm.isNotEmpty ? fm : null;
    } catch (_) {
      return null;
    }
  }

  /// Propaga los borrados encolados (`accion='D'`) sin hacer `pull`. Es la vía
  /// del wizard al eliminar una fila: el `DELETE` debe salir ya, no en la
  /// próxima sincronización grande.
  Future<EdanSyncResumen> procesarBorrados() =>
      _procesarCola(const EdanSyncResumen(exito: true), 0, 0, 0);

  /// Guarda de re-entrancia ENTRE instancias: la app crea un motor por
  /// llamada, así que el flag vive en la clase (un solo download de municipio
  /// a la vez por dispositivo).
  static bool _descargandoMunicipio = false;

  /// Descarga el municipio [idMunicipio] completo por la familia V2 (refresco
  /// del mapa rol 6, que ve todo su municipio por scope de servidor).
  ///
  /// Flujo: pagina `GET /formularios?id_municipio=N&todos=false&modo=completo`
  /// (documentos completos con `cabecera`; sin watermark, así que el diff se
  /// hace LOCAL comparando `fecha_modificacion` por uuid) y aplica con
  /// `_normalizarDocCompleto` solo a los uuid nuevos o con fecha distinta
  /// (escribe `id_municipio` y las filas de sección con coordenadas que pinta
  /// el mapa).
  ///
  /// Contrato deliberado:
  /// * NO toca el watermark personal ni hace ack: es descarga de lectura
  ///   orthogonal al ciclo pull/push propio del usuario.
  /// * NO pisa sucios (`pendiente_push=1` / cola): el PUT local gana (LWW).
  /// * Un error por documento no aborta el lote (parcial = sigue).
  /// * Al terminar avisa `EdanStoreV2.datosCambiados()` si bajó algo.
  Future<EdanMunicipioDescarga> descargarMunicipio(int idMunicipio) async {
    if (idMunicipio <= 0) {
      return const EdanMunicipioDescarga(
          exito: false, ultimoError: 'idMunicipio inválido');
    }
    if (_descargandoMunicipio) {
      return const EdanMunicipioDescarga(exito: true);
    }
    _descargandoMunicipio = true;
    var total = 0;
    var descargados = 0;
    var omitidos = 0;
    var errores = 0;
    String? ultimoError;
    try {
      const limite = 200;
      var skip = 0;
      final vistos = <String>{};
      while (true) {
        final res = await _api.listarFormularios(
          idMunicipio: idMunicipio,
          limit: limite,
          skip: skip,
          modo: 'completo',
        );
        final docs = res.data ?? const <Map<String, dynamic>>[];
        if (res.total != null) total = res.total!;
        for (final raw in docs) {
          final doc = unwrapCabecera(raw);
          final uuid = doc['uuid_edan_localidad'] as String?;
          if (uuid == null || uuid.isEmpty) continue;
          if (!vistos.add(uuid)) continue;
          try {
            if (await _esLocalidadSucia(uuid)) {
              omitidos++;
              continue;
            }
            final local = await (await _db.database).query(
              'formularios',
              columns: ['fecha_modificacion'],
              where: 'uuid_edan_localidad = ?',
              whereArgs: [uuid],
              limit: 1,
            );
            final fmRemota = doc['fecha_modificacion'];
            if (local.isNotEmpty &&
                fmRemota is String &&
                fmRemota.isNotEmpty &&
                local.first['fecha_modificacion'] == fmRemota) {
              omitidos++;
              continue;
            }
            // El doc crudo (con `cabecera`) va a `_normalizarDocCompleto`,
            // que internamente desempaqueta y guarda el crudo en
            // `datos_json_servidor` (la verdad del servidor).
            await _normalizarDocCompleto(raw);
            descargados++;
          } on EdanApiConflict {
            omitidos++;
          } catch (e) {
            errores++;
            ultimoError = '$uuid: $e';
          }
        }
        if (docs.length < limite) break;
        skip += docs.length;
      }
      if (descargados > 0) {
        EdanStoreV2.instance.datosCambiados();
      }
    } catch (e) {
      errores++;
      ultimoError = e.toString();
    } finally {
      _descargandoMunicipio = false;
    }
    return EdanMunicipioDescarga(
      exito: errores == 0,
      total: total,
      descargados: descargados,
      omitidos: omitidos,
      errores: errores,
      ultimoError: ultimoError,
    );
  }

  /// Firma del documento que se va a enviar (misma canonicalización que
  /// `EdanStoreV2.firmaContenido`): el confirm la guarda como
  /// `firma_enviada` y el dirty se deriva comparando con la firma actual,
  /// sin ventana de carrera (deriva del MISMO snapshot enviado).
  static String firmaDePayload(Map<String, dynamic> payload) {
    final secciones = <String, dynamic>{};
    final viviendas = <Map<String, dynamic>>[];
    for (final e in payload.entries) {
      final v = e.value;
      if (v is! List && v is! Map) continue; // escalar de cabecera
      if (e.key == 'danos_vivienda') {
        final lista = v is List ? v : [v];
        final padres = <Map<String, dynamic>>[];
        for (final p in lista.whereType<Map>()) {
          final padre = Map<String, dynamic>.from(p);
          final hijas = padre.remove('viviendas');
          padres.add(padre);
          if (hijas is List) {
            viviendas.addAll(hijas
                .whereType<Map>()
                .map((m) => Map<String, dynamic>.from(m)));
          }
        }
        secciones['danos_vivienda'] = padres;
        continue;
      }
      secciones[e.key] = v;
    }
    return EdanStoreV2.firmaDeNormalizado({
      'cabecera': payload,
      'secciones': secciones,
      'viviendas': viviendas,
    });
  }

  /// Fase D: empuja el formulario COMPLETO (cabecera + 14 `imp_*` + las 14
  /// secciones + `viviendas[]`) vía `POST /formularios/completo`.
  ///
  /// El payload se reconstruye desde SQLite (no desde `EdanLocalidad`), de
  /// modo que el motor no depende del modelo Dart y funciona igual en el
  /// celular que en un dispositivo recién restaurado.
  ///
  /// Devuelve la firma del documento enviado + el instante de inicio (para
  /// la guardia anti-carrera del confirm) + la intención capturada.
  Future<
      ({
        String firma,
        String pushStartIso,
        int? destino,
        int submit,
      })> _pushFormularioCompleto(String uuid, Map<String, Object?> row) async {
    final db = await _db.database;
    final pushStartIso = DateTime.now().toIso8601String();
    // Intención de envío pendiente (`estado_destino`, v36): el payload debe
    // llevar el estado DESTINO, no el actual. Se aplica aquí (justo antes
    // de armar el payload) y se revierte si el push falla: el estado visible
    // sigue siendo el previo hasta la confirmación del servidor.
    final destino = (row['estado_destino'] as num?)?.toInt();
    final previo = (row['id_edan_localidad_estado'] as num?)?.toInt();
    final submitCapturado = (row['pending_submit'] as num?)?.toInt() ?? 0;
    Map<String, Object?> vigente = row;
    if (destino != null && destino != previo) {
      await db.update(
        'formularios',
        {'id_edan_localidad_estado': destino},
        where: 'uuid_edan_localidad = ?',
        whereArgs: [uuid],
      );
      final releida = await db.query(
        'formularios',
        where: 'uuid_edan_localidad = ?',
        whereArgs: [uuid],
        limit: 1,
      );
      if (releida.isNotEmpty) vigente = releida.first;
    }
    try {
      final firma = await _pushFormularioCompletoPayload(uuid, vigente);
      return (
        firma: firma,
        pushStartIso: pushStartIso,
        destino: destino,
        submit: submitCapturado,
      );
    } catch (_) {
      // Sin confirmación no hay transición: se restaura el estado previo.
      // La intención (`estado_destino` + `pendiente_push=1`) queda para el
      // próximo `sincronizar()`.
      if (destino != null && destino != previo) {
        await db.update(
          'formularios',
          {'id_edan_localidad_estado': previo},
          where: 'uuid_edan_localidad = ?',
          whereArgs: [uuid],
        );
      }
      rethrow;
    }
  }

  /// Cuerpo del push `/completo`: arma el payload desde [row] y lo envía
  /// por la vía que corresponde (§20.15): **POST solo crea**
  /// (`id_server` desconocido), **PUT edita** (ya existe). Con self-heal
  /// del 400 flag-sin-filas, valida que no sea parcial y reconcilia la
  /// cabecera + relectura best-effort. Devuelve la firma del documento
  /// enviado (el confirm la usa como `firma_enviada` sin ventana).
  Future<String> _pushFormularioCompletoPayload(
      String uuid, Map<String, Object?> row) async {
    final payload =
        await prepararPayloadCompleto(uuid, row, dbHelper: _db);
    final esEdicion = (row['id_server'] as num?) != null;
    final envio = await _enviarCompleto(payload, esEdicion: esEdicion);
    final resp = envio.resp;
    final enviado = envio.enviado;
    // P4: el 200 pero `resultados[]` puede traer errores por fila.
    // Un parcial NO es confirmado: se lanza para que el llamador deje
    // `pendiente_push=1` con el motivo real. (LWW: `conflictos` siempre 0.)
    final data = resp.data ?? {};
    final errores = (data['errores'] as num?)?.toInt() ?? 0;
    if (errores > 0) {
      throw EdanApiError(
        statusCode: 200,
        detail: detallePushParcial(data),
        rawBody: data,
      );
    }
    // Reconciliar la cabecera que devuelve el POST/PUT (`formulario`): id
    // servido y `grup_*` derivados. Sin esto, si la relectura de
    // abajo falla, lo local queda con id viejo. Solo columnas del
    // servidor; las locales se preservan.
    final formularioPost = data['formulario'];
    if (formularioPost is Map<String, dynamic>) {
      await _aplicarCabeceraPost(uuid, formularioPost);
    }
    // `hubo_cambios` solo se informa (el 200 ya confirma recepción y limpia
    // el dirty local, sea no-op o aplicado — regla 6: lo limpio no viaja).
    if (data.containsKey('hubo_cambios')) {
      debugPrint('[SyncV2] /completo $uuid hubo_cambios=${data['hubo_cambios']} '
          'cambios=${data['cambios']}');
    }
    // Reconciliar el documento canónico del servidor. El PUT/POST 200 YA lo
    // trae embebido en `data['formulario']` (cabecera + 14 secciones + fotos,
    // verificado en vivo 2026-10-18): reconciliar desde ahí evita un segundo
    // viaje de red que, si la red cae justo ahí, abortaba la confirmación
    // (la excepción cruda de http no es `EdanApiError`) y dejaba el
    // formulario `pendiente_push` para siempre → re-push eterno de un
    // documento que el servidor ya tiene igual ("Documento sin cambios").
    final formularioRespuesta = data['formulario'];
    if (formularioRespuesta is Map<String, dynamic> &&
        formularioRespuesta.containsKey('cabecera')) {
      try {
        await _normalizarDocCompleto(formularioRespuesta);
      } catch (e) {
        // La recepción ya fue confirmada con 200 y la cabecera reconciliada
        // arriba; una falla aplicando el espejo no debe revertir nada.
        debugPrint('[SyncV2] /completo $uuid: espejo embebido no aplicado: $e');
      }
    } else {
      // Respuesta sin documento embebido (servidor viejo): re-lectura
      // best-effort REAL — cualquier excepción se traga, nunca escapa.
      try {
        final resp = await _api.obtenerFormularioCompleto(uuid);
        if (resp.data != null) {
          await _normalizarDocCompleto(resp.data!);
        }
      } catch (e) {
        debugPrint('[SyncV2] /completo $uuid: relectura omitida: $e');
      }
    }
    return firmaDePayload(enviado);
  }

  /// Envía el documento por la vía §20.15 con fallbacks acotados (tope 1 por
  /// sentido, anti-loop): POST→409-ya-existe ⇒ PUT una vez; PUT→404 ⇒ POST
  /// una vez (y si ese POST 409ea por carrera, PUT final). La decisión la
  /// da lo LOCAL (`esEdicion` = ya tiene `id_server`); `hubo_cambios` solo
  /// se informa, no decide (el 200 confirma recepción y limpia el dirty).
  /// Devuelve respuesta + payload REALMENTE enviado (el self-heal puede
  /// corregirlo: la firma debe salir de ese, no del original).
  Future<
      ({
        EdanApiResult<Map<String, dynamic>> resp,
        Map<String, dynamic> enviado
      })> _enviarCompleto(
    Map<String, dynamic> payload, {
    required bool esEdicion,
  }) async {
    if (!esEdicion) {
      try {
        return await _completoConSelfHeal(
            payload, _api.crearFormularioCompleto);
      } on EdanPostSoloCreacion {
        debugPrint('[SyncV2] POST→409 ya existe: cambiando a PUT');
        return await _completoConSelfHeal(
            payload, _api.actualizarFormularioCompleto);
      }
    }
    try {
      return await _completoConSelfHeal(
          payload, _api.actualizarFormularioCompleto);
    } on EdanApiError catch (e) {
      if (e.statusCode != 404) rethrow;
      debugPrint('[SyncV2] PUT→404 no existe: cambiando a POST');
      try {
        return await _completoConSelfHeal(
            payload, _api.crearFormularioCompleto);
      } on EdanPostSoloCreacion {
        return await _completoConSelfHeal(
            payload, _api.actualizarFormularioCompleto);
      }
    }
  }

  /// Envía por [enviar] con self-heal del 400 "flag true sin filas" (caso
  /// Prueba10: el servidor quedó con un flag huérfano tras un borrado sin
  /// tombstone). Se reintenta UNA vez con ese flag en false y su sección
  /// fuera: el upsert no borra, así que no se pierde nada; si el dato
  /// existe en otro dispositivo, su próximo push lo restaura con flag true.
  Future<
      ({
        EdanApiResult<Map<String, dynamic>> resp,
        Map<String, dynamic> enviado
      })> _completoConSelfHeal(
    Map<String, dynamic> payload,
    Future<EdanApiResult<Map<String, dynamic>>> Function(
            Map<String, dynamic>)
        enviar,
  ) async {
    try {
      return (resp: await enviar(payload), enviado: payload);
    } on EdanApiError catch (e) {
      final flag = e.statusCode == 400 ? _flagSinFilasDe(e.detail) : null;
      final llave =
          flag == null ? null : EdanSeccionesRegistry.llaveJsonDeImp(flag);
      if (flag == null || llave == null) rethrow;
      debugPrint('[SyncV2] autocorrección $flag=false (400 flag sin filas)');
      final corregido = Map<String, dynamic>.from(payload)
        ..[flag] = false
        ..remove(llave);
      return (resp: await enviar(corregido), enviado: corregido);
    }
  }

  /// Aplica la cabecera `formulario` devuelta por `POST/PUT /completo`
  /// sobre la fila local: `id_server`, `fecha_modificacion` y `grup_*`
  /// planos. Preserva las columnas locales (`secciones_activas_json`,
  /// `estado_local`, etc.). Nunca lanza (reconciliación best-effort).
  ///
  /// OJO: el POST devuelve `formulario: {cabecera: {...}}` ANIDADO; sin
  /// desempaquetar no se encuentra el `id` y la reconciliación queda muda.
  Future<void> _aplicarCabeceraPost(
      String uuid, Map<String, dynamic> formulario) async {
    try {
      final plano = unwrapCabecera(formulario);
      final db = await _db.database;
      final cols = _columnasCabecera(plano)..addAll(
        _columnasGrupo(plano),
      );
      // El estado de negocio NO se reconcilia del POST: lo gobiernan el
      // destino pendiente (`estado_destino`) y los flujos de estados/pull.
      // (El doc del servidor trae el estado VIEJO y lo revertiría.)
      cols.remove('id_edan_localidad_estado');
      if (cols.isEmpty) return;
      await db.update(
        'formularios',
        cols,
        where: 'uuid_edan_localidad = ?',
        whereArgs: [uuid],
      );
    } catch (e) {
      debugPrint('[SyncV2] cabecera POST no aplicada: $e');
    }
  }

  /// Confirma localmente el push de una localidad: `pendiente_push=0`,
  /// `estado_local='enviado'`, sus filas `confirmado` (esto desbloquea las
  /// fotos, que solo suben cuando la dueña está confirmada), limpia la
  /// intención de envío (`pending_submit=0`, `estado_destino=NULL`, ya
  /// aplicada) y purga la cola `C`/`U` de ese formulario — los `D`
  /// (borrados) siguen su propio paso.
  /// Confirma un push exitoso con GUARDIA anti-carrera: si el usuario
  /// guardó durante el push (después de armar el payload), su cambio NO se
  /// pierde: la firma actual difiere de [firmaEnviada] y el dirty queda en
  /// 1 para el próximo sync. Sin guardia, ese cambio se marcaba limpio sin
  /// haberse enviado (data-loss).
  ///
  ///  - `firma_enviada` = hash del documento enviado; `pendiente_push` se
  ///    deriva comparando con la firma actual (+ intención pendiente).
  ///  - `pending_submit`/`estado_destino` solo se limpian si nadie los movió
  ///    durante el push ([destinoCapturado]/[submitCapturado]). La intención
  ///    registrada ANTES del push ya viajó (el payload la incluía), así que
  ///    no cuenta como cambio pendiente.
  ///  - `filas_seccion` → `confirmado` y purga de cola C/U solo para lo
  ///    anterior al inicio del push ([pushStartIso], comparación numérica
  ///    por época para no depender del formato del timestamp).
  Future<void> _confirmarPushLocalidad(
    String uuid, {
    required String firmaEnviada,
    required String pushStartIso,
    required int? destinoCapturado,
    required int submitCapturado,
  }) async {
    final db = await _db.database;
    final firmaActual =
        await EdanStoreV2.firmaContenido(db, uuid);
    final reg = await db.query(
      'formularios',
      columns: ['pending_submit', 'estado_destino'],
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    // Intención NUEVA durante el push (distinta de la capturada al inicio):
    // eso sí es trabajo pendiente. La registrada antes ya viajó.
    final submitAhora =
        reg.isEmpty ? 0 : (reg.first['pending_submit'] as num?)?.toInt() ?? 0;
    final destinoAhora =
        reg.isEmpty ? null : (reg.first['estado_destino'] as num?)?.toInt();
    final conIntencion =
        submitAhora != submitCapturado || destinoAhora != destinoCapturado;
    final limpio = firmaActual == firmaEnviada && !conIntencion;
    await _rawUpdate(
      'UPDATE formularios SET firma_enviada = ?, firma_contenido = ?, '
      'pendiente_push = ? WHERE uuid_edan_localidad = ?',
      [firmaEnviada, firmaActual, limpio ? 0 : 1, uuid],
    );
    // Intención cumplida solo si no cambió durante el push (comparación en
    // Dart con null seguro; `IS ?` con null no filtra en todos los casos).
    if (!conIntencion) {
      await _rawUpdate(
        'UPDATE formularios SET pending_submit = 0, estado_destino = NULL '
        'WHERE uuid_edan_localidad = ?',
        [uuid],
      );
    }
    if (limpio) {
      await _rawUpdate(
        "UPDATE formularios SET estado_local = 'enviado' WHERE uuid_edan_localidad = ?",
        [uuid],
      );
    }
    await _rawUpdate(
      "UPDATE filas_seccion SET estado_sync = 'confirmado' "
      "WHERE uuid_edan_localidad = ? "
      "AND (fecha_modificacion_local IS NULL OR "
      "strftime('%s', fecha_modificacion_local) <= strftime('%s', ?))",
      [uuid, pushStartIso],
    );
    await _rawDelete(
      "DELETE FROM cola_sincronizacion "
      "WHERE tabla IN ('formulario','filas_seccion','vivienda') "
      "AND accion != 'D' AND uuid_registro = ? "
      "AND (fecha_registro IS NULL OR "
      "strftime('%s', fecha_registro) <= strftime('%s', ?))",
      [uuid, pushStartIso],
    );
    await _rawDelete(
      "DELETE FROM cola_sincronizacion "
      "WHERE tabla IN ('filas_seccion','vivienda') AND accion != 'D' "
      'AND uuid_registro IN ('
      'SELECT uuid_registro FROM filas_seccion WHERE uuid_edan_localidad = ?) '
      "AND (fecha_registro IS NULL OR "
      "strftime('%s', fecha_registro) <= strftime('%s', ?))",
      [uuid, pushStartIso],
    );
    await EdanStoreV2.instance.refrescarPendientes();
    // Lo visible cambió (estado, pendientes, firma): las listas recargan.
    EdanStoreV2.instance.datosCambiados();
  }

  /// **Vía del botón "Enviar"** del listado RESP: empuja UNA localidad por
  /// `POST /api/v2/edan/formularios/completo` y después sus fotos pendientes
  /// por `POST /api/v2/edan/fotografias`.
  ///
  /// Sustituye a `EdanDocumentoSyncService.enviarLocalidadDocumento`
  /// (`POST/PUT /localidades/…/documento` + `POST /upload`, ambos del grupo
  /// legado `EDAN_LOCALIDADES`): así el envío manual y el sincronizador de
  /// fondo usan exactamente el mismo par de endpoints nuevos, el mismo payload
  /// ([prepararPayloadCompleto]) y las mismas banderas de confirmación.
  ///
  /// Si [idEdanLocalidadEstado] viene dado, se registra como intención de
  /// envío (`pending_submit=1` + `estado_destino`); el estado visible solo
  /// cambia con el 200 del servidor (lo aplica `_pushFormularioCompleto` y
  /// lo confirma `_confirmarPushLocalidad`). Si falla, la intención queda
  /// para el próximo `sincronizar()` — también sin red.
  ///
  /// Devuelve `false` (y deja `pendiente_push = 1`, para que el próximo
  /// `sincronizar()` reintente) si no hay fila en `formularios`, si el servidor
  /// rechaza (400/409) o si no hay red.
  Future<bool> enviarLocalidad(
    String uuid, {
    int? idEdanLocalidadEstado,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      'formularios',
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (rows.isEmpty) return false;

    // Etapa 5 (§6) + v36: la intención de envío se registra ANTES del push
    // (`pending_submit=1` + `estado_destino`); el estado `enviado` solo se
    // confirma con el 200. Si el push falla (incluido sin red), el estado
    // visible NO se tocó y la intención queda para el próximo `sincronizar()`.
    if (idEdanLocalidadEstado != null) {
      await _rawUpdate(
        'UPDATE formularios SET estado_destino = ?, '
        'pendiente_push = 1, pending_submit = 1 '
        'WHERE uuid_edan_localidad = ?',
        [idEdanLocalidadEstado, uuid],
      );
    } else {
      await _rawUpdate(
        'UPDATE formularios SET pendiente_push = 1, pending_submit = 1 '
        'WHERE uuid_edan_localidad = ?',
        [uuid],
      );
    }
    // Releer: el push debe ver la intención recién registrada.
    final vigente = await db.query(
      'formularios',
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (vigente.isEmpty) return false;
    final row = vigente.first;

    ultimoErrorDiagnostico = null; // TEMP DIAG (borrar)
    try {
      final envio = await _pushFormularioCompleto(uuid, row);
      await _confirmarPushLocalidad(
        uuid,
        firmaEnviada: envio.firma,
        pushStartIso: envio.pushStartIso,
        destinoCapturado: envio.destino,
        submitCapturado: envio.submit,
      );
    } on EdanApiConflict catch (c) {
      // TEMP DIAG (borrar)
      ultimoErrorDiagnostico = 'HTTP ${c.statusCode} · $c';
      debugPrint('[TEMP DIAG ENVIO] $ultimoErrorDiagnostico');
      await _rawUpdate(
        'UPDATE formularios SET pendiente_push = 1 WHERE uuid_edan_localidad = ?',
        [uuid],
      );
      return false;
    } on EdanApiError catch (e) {
      // TEMP DIAG (borrar)
      ultimoErrorDiagnostico = 'HTTP ${e.statusCode ?? '?'} · ${e.detail}';
      debugPrint('[TEMP DIAG ENVIO] $ultimoErrorDiagnostico');
      await _rawUpdate(
        'UPDATE formularios SET pendiente_push = 1 WHERE uuid_edan_localidad = ?',
        [uuid],
      );
      return false;
    } on SocketException catch (e) {
      // TEMP DIAG (borrar)
      ultimoErrorDiagnostico = 'Sin conexión (SocketException): $e';
      debugPrint('[TEMP DIAG ENVIO] $ultimoErrorDiagnostico');
      return false;
    }

    // El /completo ya confirmó las filas, así que sus fotos pasan el gate de
    // `_pushFotos` y suben en esta misma llamada.
    await _pushFotos(const EdanSyncResumen(exito: true), uuidLocalidad: uuid);
    return true;
  }

  /// Construye el payload `/completo` desde las tablas SQLite.
  ///
  /// **Estático**: lo usan el motor (`_pushFormularioCompleto`), el JSON de
  /// depuración de long-press (`EdanJsonPreviewDialog`) y los tests, para
  /// garantizar que los tres vean EXACTAMENTE lo mismo sin necesidad de
  /// instanciar el motor (que requiere un `EdanApiV2`).
  ///
  /// Contrato (`FormularioCompletoUpsert`, OpenAPI vivo):
  ///  * cabecera + **14 flags de sección** (`imp_impacto_poblacion` …
  ///    `imp_necesidad_humanitaria`), siempre explícitas true/false;
  ///  * los grupos (`grup_*`) **NO se envían** — el servidor los deriva;
  ///  * `danos_vivienda` es objeto único 1:1 con `viviendas[]` anidadas.
  ///
  /// Las secciones salen de [EdanSeccionesFuente] (`filas_seccion` y, si un
  /// tipo no tiene filas V2, el snapshot `formularios.datos_json`); como las
  /// 14 flags se derivan del MISMO conjunto, es imposible que un `imp_*` salga
  /// en `true` con su sección vacía — que era el fallo reportado.
  /// Quita de la fila los **meta-campos del documento del servidor** que no
  /// son columnas escribibles de `/completo`: el espejo los trae por fila
  /// (`sync/pull → secciones[].tipo_seccion`, ids servidos) y reenviarlos
  /// hace que el servidor rechace la fila entera — verificado en vivo
  /// 2026-11-02: 7 filas de `proteccion` en error con
  /// "Campo desconocido o no escribible para proteccion: 'tipo_seccion'".
  /// Se usa al persistir el espejo (no contaminar `datos_json`) Y al armar el
  /// wire (descontaminar filas ya persistidas en BD de dispositivos viejos).
  static void sinMetaServidor(Map<String, dynamic> fila) {
    fila
      ..remove('tipo_seccion')
      ..remove('id_edan_localidad')
      ..remove('uuid_edan_localidad');
  }

  /// Detalle HONESTO de un push 200 con `errores > 0`: lista SOLO las filas
  /// fallidas (`estado` distinto de aplicado/creado/omitido) con su mensaje,
  /// más los contadores del servidor. El mensaje viejo (`take(3)`) mostraba
  /// las primeras filas — casi siempre OK — y ocultaba el motivo real.
  static String detallePushParcial(Map<String, dynamic> data) {
    final contadores = 'aplicados=${data['aplicados'] ?? '?'} '
        'conflictos=${data['conflictos'] ?? '?'} '
        'errores=${data['errores'] ?? '?'}';
    final resultados = data['resultados'];
    if (resultados is! List) {
      return 'Push parcial ($contadores): resultados=${resultados ?? 'ausentes'}';
    }
    const ok = {'aplicado', 'creado', 'omitido'};
    final fallidas = resultados
        .whereType<Map>()
        .where((r) => !ok.contains((r['estado'] ?? '').toString()))
        .toList();
    if (fallidas.isEmpty) {
      return 'Push parcial ($contadores): ninguna fila en estado error '
          '(inconsistencia del servidor)';
    }
    final detalle = fallidas.map((r) {
      return '{i=${r['indice']} t=${r['tipo']} estado=${r['estado']} '
          'msg=${r['message']}}';
    }).join(' | ');
    return 'Push parcial ($contadores): $detalle';
  }

  static Future<Map<String, dynamic>> prepararPayloadCompleto(
    String uuid,
    Map<String, Object?> row, {
    DatabaseHelper? dbHelper,
  }) async {
    final helper = dbHelper ?? DatabaseHelper.instance;
    final db = await helper.database;

    // 1) Filas de sección: fuente ÚNICA (`filas_seccion` ∪ snapshot de
    //    `formularios.datos_json`).
    final porTipoBruto = await EdanSeccionesFuente(dbHelper: helper)
        .seccionesConDatos(uuid, formRow: row);

    // 1b) Gate por GRUPO (el grupo manda): una sección solo viaja si su grupo
    // está marcado en la fila (`grup_*` de `formularios`: page01 al crear,
    // planas del servidor al descargar). Si el grupo no está marcado, sus
    // filas NO van aunque existan huérfanas locales, y su `imp` sale false.
    // Excepción legacy: si la localidad nunca registró información de grupos
    // (`grupos_local` vacío: borradores viejos/migración), mandan los datos
    // para no perder información que el usuario sí capturó.
    final tieneInfoGrupos = (await db.query(
      'grupos_local',
      columns: ['grupo'],
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuid],
      limit: 1,
    ))
        .isNotEmpty;
    bool grupoMarcado(String ruta) {
      if (!tieneInfoGrupos) return true;
      final col = EdanSeccionesRegistry.columnaGrupoDeRuta(ruta);
      if (col == null) return true;
      return (row[col] as num?)?.toInt() == 1;
    }

    final porTipo = <String, List<Map<String, dynamic>>>{};
    for (final e in porTipoBruto.entries) {
      if (grupoMarcado(e.key)) porTipo[e.key] = e.value;
    }

    // 2) Las 14 flags de sección: true ⟺ la sección SE EMITE (tiene datos Y
    //    su grupo está marcado). Derivan del MISMO conjunto filtrado, así
    //    flag y datos nunca divergen (regla flag↔fila del servidor).
    final flags =
        EdanSeccionesRegistry.construirFlagsDesdeActivas(porTipo.keys.toList());

    // 3) Cabecera. OJO: el payload /completo NO lleva las 9 flags de grupo
    //    (`grup_poblacion`, `grup_agropecuario`, …) porque el servidor las
    //    deriva del nodo `grupos`; enviarlas sería ignorado (o rechazado).
    final payload = <String, dynamic>{
      'uuid_edan_localidad': uuid,
      'localidad': row['localidad'],
      'id_municipio': row['id_municipio'],
      'id_departamento': row['id_departamento'],
      'id_provincia': row['id_provincia'],
      'id_tipo_evento': row['id_tipo_evento'],
      'id_tipo_localidad': row['id_tipo_localidad'],
      'id_edan_localidad_estado': row['id_edan_localidad_estado'],
      'fecha_llenado': row['fecha_llenado'],
      'fecha_evento': row['fecha_evento'],
      'hora_evento': row['hora_evento'],
      'total_poblacion_afectada': row['total_poblacion_afectada'],
      'total_familias_afectadas': row['total_familias_afectadas'],
      'total_familias_damnificadas': row['total_familias_damnificadas'],
      // LWW (2026-10-16, verificado en vivo): `POST /completo` NUNCA lleva
      // `version` — ni en creación ni sobre existente. La identidad es el
      // uuid y gana el último que llega.
    };
    // Las 14 flags SIEMPRE presentes y explícitas (nunca null).
    for (final desc in EdanSeccionesRegistry.secciones) {
      payload['imp_${desc.rutaV2.replaceAll('-', '_')}'] =
          flags['imp_${desc.rutaV2.replaceAll('-', '_')}'] ?? false;
    }

    // `responsable` / `nombre_alcalde` / `fono_alcalde` NO se envían en el
    // payload de la LOCALIDAD: no son columnas de `edan_localidades` ni están
    // declaradas en `FormularioCompletoUpsert`; pertenecen al EDAN padre
    // (`edan.edan`, schemas `EdanCreate`/`EdanUpdate`). Se conservan en la BD
    // local y en la UI (page13) vía `EdanLocalidad.toJson()`, pero no viajan.

    // Las secciones que tienen datos. Las vacías NO se emiten: si la flag es
    // false, la clave no debe aparecer (regla flag↔fila del servidor).
    for (final desc in EdanSeccionesRegistry.secciones) {
      final tipo = desc.rutaV2;
      final filasTipo = porTipo[tipo] ?? const <Map<String, dynamic>>[];
      if (filasTipo.isEmpty) continue;
      final lista = <Map<String, dynamic>>[];
      // `danos-vivienda` es 1:N en el registro pero 1:1 en el servidor: se
      // escribe como objeto único con `viviendas[]` anidadas y NO debe ser
      // sobrescrito por la asignación final de listas.
      var seccionEscritaComoObjeto = false;
      for (final datos in filasTipo) {
        // §20.10.C: `fotografia` NO viaja en ninguna sección de los POST; es
        // solo el espejo del path que el servidor llena al subir la foto.
        datos.remove('fotografia');
        // `afectado`/`impactado` (check de servicios básicos) y `marcado`
        // (check de grupo etario) son locales: se persisten en `datos_json`
        // para que el checkbox sobreviva el round-trip, pero las tablas del
        // servidor no tienen esas columnas y el POST contestaría 400
        // "campo desconocido o no escribible". Se quitan solo en el wire.
        datos.remove('afectado');
        datos.remove('impactado');
        datos.remove('marcado');
        // Meta-campos que el espejo dejó persistidos en BD en dispositivos
        // anteriores a este fix: fuera del wire siempre (el servidor los
        // rechaza o ignora; proteccion responde 200 con fila en error).
        sinMetaServidor(datos);
        // Contrato impacto por grupo etario: con `id_grupo_etario` presente
        // el servidor RECHAZA `rango` (400 por fila: "Campo desconocido o no
        // escribible para impacto_poblacion: 'rango'") — resuelve el grupo
        // por el id del catálogo. Misma regla que la
        // `EdanImpactoPoblacionService.filaDesdeRow` legacy; sin id, `rango`
        // sigue viajando como resolver. El set exacto 1-4 no se toca.
        if (tipo == 'impacto-poblacion' && datos['id_grupo_etario'] != null) {
          datos.remove('rango');
        }
        // `datos` ya viene decodificado y con `uuid_registro` (Fuente).
        if (desc.tipo == EdanSeccionTipo.unoAUno) {
          // 1:1 → objeto único (no lista).
          if (lista.isEmpty) payload[desc.llaveJson] = datos;
          seccionEscritaComoObjeto = true;
          continue;
        }
        // 1:N → lista.
        if (tipo == 'danos-vivienda') {
          // `danos_vivienda` es 1:1 en el servidor; sus viviendas viajan
          // anidadas bajo `viviendas[]` (§20.1/§20.4).
          final uuidFila = datos['uuid_registro'] as String;
          final vivs = await db.query(
            'viviendas',
            where: 'uuid_dano_vivienda = ?',
            whereArgs: [uuidFila],
          );
          if (vivs.isNotEmpty) {
            // El padre lleva `uuid_registro` (arriba) y cada hija también: el
            // `uuid_registro` es la identidad de cada vivienda. NO se envía
            // `uuid_dano_vivienda` (la relación es por anidamiento) ni
            // `fotografia` (§20.10.C: la llena el servidor al subir la foto).
            datos['viviendas'] = vivs
                .map((v) => {
                      'uuid_registro': v['uuid_registro'],
                      'tipo_dano': v['tipo_dano'],
                      'coordenada_lat': v['coordenada_lat'],
                      'coordenada_lon': v['coordenada_lon'],
                    })
                .toList();
            // §20.4: si tiene hijas, las coords del padre se anulan.
            datos['coordenada_lat'] = null;
            datos['coordenada_lon'] = null;
          }
          // Sin filas en la tabla `viviendas` se conserva lo que ya traía la
          // fuente: el snapshot de cabecera anida `viviendas[]` en el propio
          // objeto (`EdanDanoVivienda.toApiJson`).
          if (lista.isEmpty) payload[desc.llaveJson] = datos;
          seccionEscritaComoObjeto = true;
          continue;
        }
        lista.add(datos);
      }
      if (desc.tipo == EdanSeccionTipo.unoAN && !seccionEscritaComoObjeto) {
        payload[desc.llaveJson] = lista;
      }
    }

    // Tope por catálogo (§20.10.E / §20.11): si el flag de sección es `true`, el
    // servidor exige EXACTAMENTE las 4 filas de `impacto_poblacion`
    // (`id_grupo_etario` 1-4) o las 8 de `proteccion`
    // (`id_grupo_vulnerable_catalogo` 1-8); menos filas → 400. Se completan las
    // faltantes con conteos 0 y `uuid_registro` determinista. Si el flag es
    // `false`, la sección no viaja.
    _completarFilasDeCatalogo(
      payload,
      uuid: uuid,
      flagKey: 'imp_impacto_poblacion',
      llaveJson: 'impacto_poblacion',
      rutaTipo: 'impacto-poblacion',
      idCampo: 'id_grupo_etario',
      ids: const [1, 2, 3, 4],
      defaults: const {'fallecidos': 0, 'heridos': 0, 'desaparecidos': 0},
    );
    _completarFilasDeCatalogo(
      payload,
      uuid: uuid,
      flagKey: 'imp_proteccion',
      llaveJson: 'proteccion',
      rutaTipo: 'proteccion',
      idCampo: 'id_grupo_vulnerable_catalogo',
      ids: const [1, 2, 3, 4, 5, 6, 7, 8],
      defaults: const {'mujeres': 0, 'hombres': 0},
    );

    return payload;
  }

  /// Completa una sección 1:N de catálogo con el set EXACTO de filas que exige
  /// el servidor cuando su flag es `true` (§20.10.E / §20.11): deduplica por
  /// [idCampo], rellena los ids faltantes con [defaults] (conteos 0) y asigna
  /// `uuid_registro` DETERMINISTA a las sintéticas (re-enviar no duplica). Con
  /// flag `false` elimina la sección (regla flag↔fila).
  static void _completarFilasDeCatalogo(
    Map<String, dynamic> payload, {
    required String uuid,
    required String flagKey,
    required String llaveJson,
    required String rutaTipo,
    required String idCampo,
    required List<int> ids,
    Map<String, dynamic> defaults = const {},
  }) {
    if (payload[flagKey] != true) {
      payload.remove(llaveJson);
      return;
    }
    final porId = <int, Map<String, dynamic>>{};
    final existentes = payload[llaveJson];
    if (existentes is List) {
      for (final f in existentes) {
        if (f is! Map) continue;
        final fila = Map<String, dynamic>.from(f);
        final id = _intDeCatalogo(fila[idCampo]);
        if (id == null || !ids.contains(id) || porId.containsKey(id)) continue;
        porId[id] = fila;
      }
    }
    final filas = <Map<String, dynamic>>[];
    for (final id in ids) {
      final fila = porId[id] ?? Map<String, dynamic>.from(defaults);
      fila[idCampo] = id;
      fila.putIfAbsent(
        'uuid_registro',
        () => EdanSeccionesFuente.uuidFilaSintetica(uuid, rutaTipo, id),
      );
      filas.add(fila);
    }
    payload[llaveJson] = filas;
  }

  static int? _intDeCatalogo(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}');
  }

  /// num→double y string numérica→double (el servidor provee varias columnas
  /// numéricas —p. ej. `coordenada_lat/lon` de `viviendas`— como STRING en el
  /// JSON); null si no es parseable. Nunca lanza.
  static double? _doubleDeServidor(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  /// Fotos pendientes de subida (`cola_fotos`) dueñas de una localidad.
  ///
  /// Mismo join que [_pushFotos] (dueña = fila de sección o vivienda de esa
  /// localidad), pero SIN el gate de `estado_sync = 'confirmado'`: el diálogo
  /// de depuración debe mostrar TODAS las fotos pendientes, incluidas las que
  /// aún no pueden subir (para diagnosticar por qué no suben).
  ///
  /// **Estático**: lo usan el diálogo `EdanJsonPreviewDialog` (pestaña POST,
  /// que imprime cada `POST /fotografias` multipart) y los tests, sin
  /// instanciar el motor.
  static Future<List<Map<String, dynamic>>> fotosPendientesDeLocalidad(
    String uuid, {
    DatabaseHelper? dbHelper,
  }) async {
    final helper = dbHelper ?? DatabaseHelper.instance;
    final db = await helper.database;
    return db.rawQuery('''
      SELECT f.* FROM cola_fotos f
      WHERE f.estado IN ('pendiente','subiendo') AND (
        EXISTS (SELECT 1 FROM filas_seccion p
                WHERE p.uuid_registro = f.uuid_registro
                  AND p.uuid_edan_localidad = ?)
        OR EXISTS (SELECT 1 FROM viviendas pv
                   JOIN filas_seccion ps
                     ON ps.uuid_registro = pv.uuid_dano_vivienda
                   WHERE pv.uuid_registro = f.uuid_registro
                     AND ps.uuid_edan_localidad = ?)
      )
      ORDER BY f.intentos ASC
    ''', [uuid, uuid]);
  }

  /// Resuelve el `tipo_entidad` que llevaría cada foto pendiente en su
  /// `POST /fotografias` multipart, SOLO LECTURA (no escribe nada en
  /// `cola_fotos`/`fotografias`, a diferencia de [_resolverTipoEntidad]).
  ///
  /// Espeja la lógica del motor: si la cola ya trae un `tipo_entidad` válido
  /// (el CHECK de 15 valores) se usa tal cual; si no, se deriva por la fila
  /// dueña —vivienda→`'vivienda'`, fila de sección→el nombre de TABLA del
  /// registry (`salud_establecimientos`, `primera_respuesta`…). Devuelve
  /// `null` cuando la dueña aún no existe (la foto no podría subir).
  static Future<String?> resolverTipoEntidadSoloLectura(
    Map<String, Object?> filaCola, {
    DatabaseHelper? dbHelper,
  }) async {
    final tipo = filaCola['tipo_entidad'] as String?;
    if (EdanSeccionesRegistry.esTipoEntidadValido(tipo)) return tipo;
    final uuidReg = filaCola['uuid_registro'] as String?;
    if (uuidReg == null || uuidReg.isEmpty) return null;
    final helper = dbHelper ?? DatabaseHelper.instance;
    final db = await helper.database;
    final viv = await db.query(
      'viviendas',
      columns: ['uuid_registro'],
      where: 'uuid_registro = ?',
      whereArgs: [uuidReg],
      limit: 1,
    );
    if (viv.isNotEmpty) return 'vivienda';
    final fila = await db.query(
      'filas_seccion',
      columns: ['tipo'],
      where: 'uuid_registro = ?',
      whereArgs: [uuidReg],
      limit: 1,
    );
    if (fila.isEmpty) return null;
    return EdanSeccionesRegistry.tipoEntidadDesdeTipo(
        fila.first['tipo'] as String);
  }

  Future<void> _ejecutarAccionSync(EdanColaItem item) async {
    switch (item.tabla) {
      case 'formulario':
        await _pushFormulario(item);
        break;
      case 'filas_seccion':
        await _pushFilaSeccion(item);
        break;
      case 'vivienda':
        await _pushVivienda(item);
        break;
      default:
        throw EdanApiError(
          statusCode: 400,
          detail: 'Tabla desconocida: ${item.tabla}',
        );
    }
  }

  /// Tras un push exitoso actualiza la columna `estado` local (§3.1/§16):
  ///  - cabecera (`formulario`): `formularios.estado_local` → `'enviado'`;
  ///  - fila de sección (`filas_seccion`): `estado_sync` → `'confirmado'`
  ///    (desbloquea la subida de fotos dueñas de esa fila, §16.4).
  /// No se aplica a borrados (`accion='D'`): la fila ya no debe existir.
  Future<void> _marcarPushExitoso(EdanColaItem item) async {
    if (item.accion == 'D') return;
    switch (item.tabla) {
      case 'formulario':
        await _rawUpdate(
          "UPDATE formularios SET estado_local = 'enviado' "
          'WHERE uuid_edan_localidad = ?',
          [item.uuidRegistro],
        );
        break;
      case 'filas_seccion':
        await _rawUpdate(
          "UPDATE filas_seccion SET estado_sync = 'confirmado' "
          'WHERE uuid_registro = ?',
          [item.uuidRegistro],
        );
        break;
    }
  }

  Future<void> _pushFormulario(EdanColaItem item) async {
    // El `D` de un formulario SIEMPRE llama al servidor (solo necesita el
    // uuid): las filas locales ya se borraron y asumir "404 en servidor"
    // sin preguntar dejaba el registro vivo para siempre (bug verificado:
    // borrar tras sync en borrador no propagaba nada).
    if (item.accion == 'D') {
      await _api.eliminarFormulario(item.uuidRegistro);
      return;
    }
    final db = await _db.database;
    final rows = await db.query(
      'formularios',
      where: 'uuid_edan_localidad = ?',
      whereArgs: [item.uuidRegistro],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw EdanApiError(statusCode: 404, detail: 'Formulario no encontrado localmente');
    }
    final row = rows.first;
    final payload = _payloadFormulario(row);

    if (item.accion == 'U') {
      final resp = await _api.actualizarFormulario(item.uuidRegistro, payload);
      await _aplicarIdsRespuesta(
        tabla: 'formularios',
        columnaUuid: 'uuid_edan_localidad',
        uuid: item.uuidRegistro,
        data: resp.data,
        idColumna: 'id_server',
        idClaves: const ['id_edan_localidad'],
      );
    } else {
      final resp = await _api.crearFormulario(payload);
      await _aplicarIdsRespuesta(
        tabla: 'formularios',
        columnaUuid: 'uuid_edan_localidad',
        uuid: item.uuidRegistro,
        data: resp.data,
        idColumna: 'id_server',
        idClaves: const ['id_edan_localidad'],
      );
    }
  }

  /// Guarda el id remoto de una respuesta POST/PUT sobre su fila local.
  /// Best-effort: nunca lanza. LWW: ya no hay `version` que reconciliar.
  Future<void> _aplicarIdsRespuesta({
    required String tabla,
    required String columnaUuid,
    required String uuid,
    required Map<String, dynamic>? data,
    String? idColumna,
    List<String> idClaves = const [],
  }) async {
    if (data == null || data.isEmpty) return;
    try {
      final cols = <String, Object?>{};
      if (idColumna != null) {
        for (final k in idClaves) {
          final id = data[k];
          if (id is num) {
            cols[idColumna] = id.toInt();
            break;
          }
        }
      }
      if (cols.isEmpty) return;
      await _rawUpdate(
        'UPDATE $tabla SET ${cols.keys.map((c) => '$c = ?').join(', ')} '
        'WHERE $columnaUuid = ?',
        [...cols.values, uuid],
      );
    } catch (e) {
      debugPrint('[SyncV2] id POST/PUT no aplicado ($tabla): $e');
    }
  }

  Map<String, dynamic> _payloadFormulario(Map<String, dynamic> row) {
    // Payload de cabecera estricto por el spec vivo de `FormularioUpsert`
    // (`additionalProperties:false`). Ese schema declara SOLO los 16 campos de
    // abajo: NO acepta ningún `imp_*` (ni los 9 de grupo ni las 14 de sección)
    // ni volcar `datos_json`. Enviar claves no declaradas devuelve 422.
    //
    // Los grupos (`grup_*`) los deriva el servidor de las secciones (vía
    // `/formularios/completo` o `POST /localidades/cabecera`, que sí aceptan
    // las flags de grupo); aquí no se traducen ni se envían.
    return {
      'uuid_edan_localidad': row['uuid_edan_localidad'],
      'localidad': row['localidad'],
      'id_municipio': row['id_municipio'],
      'id_departamento': row['id_departamento'],
      'id_provincia': row['id_provincia'],
      'id_tipo_evento': row['id_tipo_evento'],
      'id_tipo_localidad': row['id_tipo_localidad'],
      'id_edan_localidad_estado': row['id_edan_localidad_estado'],
      'fecha_llenado': row['fecha_llenado'],
      'fecha_evento': row['fecha_evento'],
      'hora_evento': row['hora_evento'],
      'total_poblacion_afectada': row['total_poblacion_afectada'],
      'total_familias_afectadas': row['total_familias_afectadas'],
      'total_familias_damnificadas': row['total_familias_damnificadas'],
    };
  }

  Future<void> _pushFilaSeccion(EdanColaItem item) async {
    final db = await _db.database;
    // Coordenadas del DELETE: del payload encolado (la fila local ya se
    // borró) o, en su defecto, de la fila si aún existe. Sin ninguna de las
    // dos no se puede direccionar: 404 local y se purga (filas de versiones
    // viejas sin payload).
    var uuidLocalidad = item.payloadJson?['uuid_edan_localidad'] as String?;
    var tipo = item.payloadJson?['tipo'] as String?;
    final rows = await db.query(
      'filas_seccion',
      where: 'uuid_registro = ?',
      whereArgs: [item.uuidRegistro],
      limit: 1,
    );
    Map<String, Object?>? row;
    if (rows.isNotEmpty) {
      row = rows.first;
      uuidLocalidad ??= row['uuid_edan_localidad'] as String?;
      tipo ??= row['tipo'] as String?;
    }
    if (item.accion == 'D') {
      if (uuidLocalidad == null ||
          uuidLocalidad.isEmpty ||
          tipo == null ||
          tipo.isEmpty) {
        throw EdanApiError(
            statusCode: 404,
            detail: 'Fila de sección sin coordenadas para el DELETE');
      }
      await _api.eliminarSeccion(uuidLocalidad, tipo, item.uuidRegistro);
      return;
    }
    if (rows.isEmpty) {
      throw EdanApiError(statusCode: 404, detail: 'Fila de sección no encontrada');
    }
    row = rows.first;
    final uuidLoc = row['uuid_edan_localidad'] as String;
    final tipoFila = row['tipo'] as String;
    final datos = jsonDecode(row['datos_json'] as String) as Map<String, dynamic>;
    // §20.10.C: `fotografia` no viaja en `POST /secciones/{tipo}`; la llena el
    // servidor al subir la foto (espejo del path).
    datos.remove('fotografia');
    // El `toApiJson()` de los modelos serializa `id_seccion`, no `uuid_registro`.
    // El upsert del POST es por `uuid_registro` (PLAN_APIS_V2 §14/§16): sin este
    // campo el server genera uuid propio y el pull crearía duplicados.
    datos['uuid_registro'] = row['uuid_registro'];

    EdanApiResult<Map<String, dynamic>> respSeccion;
    if (item.accion == 'U') {
      respSeccion = await _api.actualizarSeccion(
          uuidLoc, tipoFila, item.uuidRegistro, datos);
    } else {
      respSeccion = await _api.upsertSeccion(uuidLoc, tipoFila, datos);
    }
    await _aplicarIdsRespuesta(
      tabla: 'filas_seccion',
      columnaUuid: 'uuid_registro',
      uuid: item.uuidRegistro,
      data: respSeccion.data,
    );
  }

  Future<void> _pushVivienda(EdanColaItem item) async {
    final db = await _db.database;
    // Coordenadas del DELETE: del payload encolado (la hija local ya se
    // borró) o, en su defecto, de la fila si aún existe.
    var uuidLocalidad = item.payloadJson?['uuid_edan_localidad'] as String?;
    var uuidDano = item.payloadJson?['uuid_dano_vivienda'] as String?;
    final rows = await db.query(
      'viviendas',
      where: 'uuid_registro = ?',
      whereArgs: [item.uuidRegistro],
      limit: 1,
    );
    Map<String, Object?>? row;
    if (rows.isNotEmpty) {
      row = rows.first;
      uuidDano ??= row['uuid_dano_vivienda'] as String?;
      if (uuidLocalidad == null || uuidLocalidad.isEmpty) {
        try {
          uuidLocalidad = await _uuidLocalidadDeDano(
            row['uuid_dano_vivienda'] as String,
          );
        } catch (_) {}
      }
    }
    if (item.accion == 'D') {
      if (uuidLocalidad == null ||
          uuidLocalidad.isEmpty ||
          uuidDano == null ||
          uuidDano.isEmpty) {
        throw EdanApiError(
            statusCode: 404,
            detail: 'Vivienda sin coordenadas para el DELETE');
      }
      await _api.eliminarVivienda(uuidLocalidad, uuidDano, item.uuidRegistro);
      return;
    }
    if (rows.isEmpty) {
      throw EdanApiError(statusCode: 404, detail: 'Vivienda no encontrada');
    }
    row = rows.first;
    final uuidLoc = await _uuidLocalidadDeDano(
      row['uuid_dano_vivienda'] as String,
    );
    final uuidDanoPadre = row['uuid_dano_vivienda'] as String;
    // Whitelist por el schema `ViviendaUpsert` (PLAN_APIS_V2, §20.10.C): solo
    // campos del contrato. NO se envía `uuid_dano_vivienda` (va en la ruta y
    // `additionalProperties:false` → 422) ni `fotografia` (deprecated: el
    // servidor espeja el path al subir la foto; §20.10.C). Tampoco
    // `fecha_modificacion_local` (nombre solo local; el server usa
    // `fecha_modificacion`) ni `version` en el POST de creación.
    final datos = <String, dynamic>{
      'uuid_registro': row['uuid_registro'],
      'tipo_dano': row['tipo_dano'],
      'coordenada_lat': row['coordenada_lat'],
      'coordenada_lon': row['coordenada_lon'],
    };
    EdanApiResult<Map<String, dynamic>> respViv;
    if (item.accion == 'U') {
      respViv = await _api.actualizarVivienda(
          uuidLoc, uuidDanoPadre, item.uuidRegistro, datos);
    } else {
      respViv =
          await _api.crearVivienda(uuidLoc, uuidDanoPadre, datos);
    }
    await _aplicarIdsRespuesta(
      tabla: 'viviendas',
      columnaUuid: 'uuid_registro',
      uuid: item.uuidRegistro,
      data: respViv.data,
    );
  }

  Future<String> _uuidLocalidadDeDano(String uuidDanoVivienda) async {
    final db = await _db.database;
    final rows = await db.query(
      'filas_seccion',
      columns: ['uuid_edan_localidad'],
      where: 'uuid_registro = ?',
      whereArgs: [uuidDanoVivienda],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw EdanApiError(statusCode: 404, detail: 'Padre danos-vivienda no encontrado');
    }
    return rows.first['uuid_edan_localidad'] as String;
  }

  // ── Fotos ──

  /// Resuelve el `tipo_entidad` que admite `POST /api/v2/edan/fotografias`.
  ///
  /// `edan.fotografias.tipo_entidad` tiene un **CHECK** con los 14 nombres
  /// cortos de sección + `'vivienda'` (EDAN_ESQUEMA_BD §3.7, PLAN
  /// §7/§20.7), pero las páginas del wizard registran la foto con el marcador
  /// local `filas_seccion`. Aquí se traduce por la fila dueña —que ya está
  /// confirmada, porque el gate de `_pushFotos` lo exige— usando el **nombre de
  /// tabla** del registry (`salud_establecimientos`, `primera_respuesta`…), que
  /// NO siempre coincide con la clave JSON (`establecimientos_salud`,
  /// `necesidad_primera_respuesta`).
  ///
  /// Devuelve `null` cuando no se puede resolver (la fila dueña aún no existe):
  /// el llamador deja la foto en cola en vez de enviar un valor que el
  /// servidor rechazaría.
  Future<String?> _resolverTipoEntidad(EdanColaFotoItem foto) async {
    if (EdanSeccionesRegistry.esTipoEntidadValido(foto.tipoEntidad)) {
      return foto.tipoEntidad;
    }
    final uuidReg = foto.uuidRegistro;
    if (uuidReg == null || uuidReg.isEmpty) return null;
    final db = await _db.database;

    // 15º valor del CHECK: la dueña es una vivienda del detalle 1:N.
    final viv = await db.query(
      'viviendas',
      columns: ['uuid_registro'],
      where: 'uuid_registro = ?',
      whereArgs: [uuidReg],
      limit: 1,
    );
    if (viv.isNotEmpty) {
      await _normalizarTipoEntidadLocal(foto.uuidFotografia, 'vivienda');
      return 'vivienda';
    }

    // 14 nombres cortos de sección, derivados de `filas_seccion.tipo`.
    final fila = await db.query(
      'filas_seccion',
      columns: ['tipo'],
      where: 'uuid_registro = ?',
      whereArgs: [uuidReg],
      limit: 1,
    );
    if (fila.isEmpty) return null;
    final tipo =
        EdanSeccionesRegistry.tipoEntidadDesdeTipo(fila.first['tipo'] as String);
    if (tipo == null) return null;
    await _normalizarTipoEntidadLocal(foto.uuidFotografia, tipo);
    return tipo;
  }

  /// Guarda en local el `tipo_entidad` canónico ya resuelto, para que
  /// `fotografias` (el espejo offline que rellena el `pull`) y la cola dejen de
  /// llevar el marcador `filas_seccion`.
  Future<void> _normalizarTipoEntidadLocal(
      String uuidFotografia, String tipo) async {
    await _rawUpdate(
      'UPDATE fotografias SET tipo_entidad = ? WHERE uuid_fotografia = ?',
      [tipo, uuidFotografia],
    );
    await _rawUpdate(
      'UPDATE cola_fotos SET tipo_entidad = ? WHERE uuid_fotografia = ?',
      [tipo, uuidFotografia],
    );
  }

  /// Sube las fotos pendientes por `POST /fotografias`.
  ///
  /// [uuidLocalidad] restringe la barrida a las fotos de UNA localidad (lo usa
  /// [enviarLocalidad] para que el botón "Enviar" no arrastre fotos ajenas);
  /// si es `null` se procesa toda la cola, que es lo que hace [sincronizar].
  Future<EdanSyncResumen> _pushFotos(
    EdanSyncResumen previo, {
    String? uuidLocalidad,
  }) async {
    final db = await _db.database;
    // Auto-reparo: fotos `pending` sin fila en `cola_fotos` (fantasmas por
    // kills/migraciones) se re-encolan solas. Sin esto quedaban invisibles
    // para siempre: ni se subían ni se contaban. SOLO las nunca confirmadas
    // (`ruta_servidor` vacía): una foto bajada del servidor jamás entra a
    // la cola de subida (eso la exponía a la purga de huérfanas y borraba
    // sus bytes recién descargados).
    try {
      final fantasmas = await db.rawQuery('''
        SELECT f.uuid_fotografia AS u, f.ruta_local AS ruta,
               f.tipo_entidad AS tipo, f.uuid_registro AS reg,
               f.sha256 AS sha
        FROM fotografias f
        WHERE f.borrado_logico = 0
          AND (f.upload_state IS NULL OR f.upload_state = 'pending')
          AND f.ruta_local IS NOT NULL AND f.ruta_local != ''
          AND (f.ruta_servidor IS NULL OR f.ruta_servidor = '')
          AND NOT EXISTS (SELECT 1 FROM cola_fotos c
                          WHERE c.uuid_fotografia = f.uuid_fotografia)
      ''');
      for (final g in fantasmas) {
        final u = g['u'] as String?;
        final ruta = g['ruta'] as String?;
        if (u == null || u.isEmpty || ruta == null || ruta.isEmpty) continue;
        try {
          if (!await File(ruta).exists()) continue;
        } catch (_) {
          continue;
        }
        await db.insert(
          'cola_fotos',
          {
            'uuid_fotografia': u,
            'ruta_local': ruta,
            'tipo_entidad': g['tipo'],
            'uuid_registro': g['reg'],
            'sha256': g['sha'],
            'estado': 'pendiente',
            'intentos': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      if (fantasmas.isNotEmpty) {
        debugPrint(
            '[SyncV2] fotos fantasma re-encoladas: ${fantasmas.length}');
      }
    } catch (_) {}
    // Gate por tipo de dueña (§16.4):
    //  - 'vivienda': la foto pertenece a una vivienda del detalle 1:N; se
    //    sube cuando la vivienda existe localmente y su fila padre
    //    (`filas_seccion`) está confirmada (el motor empuja secciones antes
    //    que viviendas/fotos).
    //  - resto (default 'filas_seccion'): la dueña es la propia fila de
    //    sección y debe estar confirmada.
    final filtroLocal = uuidLocalidad == null
        ? ''
        : '''
         AND (
           EXISTS (SELECT 1 FROM filas_seccion p
                   WHERE p.uuid_registro = f.uuid_registro
                     AND p.uuid_edan_localidad = ?)
           OR EXISTS (SELECT 1 FROM viviendas pv
                      JOIN filas_seccion ps ON ps.uuid_registro = pv.uuid_dano_vivienda
                      WHERE pv.uuid_registro = f.uuid_registro
                        AND ps.uuid_edan_localidad = ?)
         )''';
    final args = uuidLocalidad == null
        ? [DateTime.now().toIso8601String()]
        : [DateTime.now().toIso8601String(), uuidLocalidad, uuidLocalidad];
    // Con usuario informado, solo fotos de sus localidades (join a
    // `formularios.id_usuario` por ambas ramas de dueña).
    final u = usuarioId;
    final filtroDueno = u == null
        ? ''
        : 'AND EXISTS (SELECT 1 FROM formularios fl '
            'WHERE fl.uuid_edan_localidad = s.uuid_edan_localidad '
            'AND (fl.id_usuario = $u OR fl.id_usuario IS NULL))';
    final rows = await db.rawQuery('''
      SELECT f.* FROM cola_fotos f
      WHERE f.estado IN ('pendiente','subiendo')
        AND (f.fecha_proximo_intento IS NULL OR f.fecha_proximo_intento <= ?)
        AND (
          CASE f.tipo_entidad
            WHEN 'vivienda' THEN EXISTS (
              SELECT 1 FROM viviendas v
              JOIN filas_seccion s ON s.uuid_registro = v.uuid_dano_vivienda
              WHERE v.uuid_registro = f.uuid_registro
                AND s.estado_sync = 'confirmado'
                ${u == null ? '' : 'AND EXISTS (SELECT 1 FROM formularios fl WHERE fl.uuid_edan_localidad = s.uuid_edan_localidad AND (fl.id_usuario = $u OR fl.id_usuario IS NULL))'}
            )
            ELSE EXISTS (
              SELECT 1 FROM filas_seccion s
              WHERE s.uuid_registro = f.uuid_registro
                AND s.estado_sync = 'confirmado'
                $filtroDueno
            )
          END
        )$filtroLocal
      ORDER BY f.intentos ASC
      LIMIT 50
    ''', args);

    int subidas = previo.fotosSubidas;
    int pendientes = previo.fotosPendientes;
    String? ultimoError = previo.ultimoError;

    for (final raw in rows) {
      final foto = EdanColaFotoItem.fromMap(raw);
      final archivo = File(foto.rutaLocal);
      if (!await archivo.exists()) {
        // El archivo se perdió (limpieza del SO, ruta inválida): no se puede
        // subir nunca. Se purga la cola pero el motivo queda registrado en
        // `fotografias.last_error` para que la UI lo muestre en vez de
        // silencio (arquitectura §26: disco/archivo ausente se informa).
        pendientes++;
        await _rawUpdate('''
          UPDATE fotografias
          SET upload_state = 'failed',
              last_error = 'Archivo local no encontrado'
          WHERE uuid_fotografia = ?
        ''', [foto.uuidFotografia]);
        await _rawDelete(
          'DELETE FROM cola_fotos WHERE uuid_fotografia = ?',
          [foto.uuidFotografia],
        );
        continue;
      }
      try {
        final tipoEntidad = await _resolverTipoEntidad(foto);
        if (tipoEntidad == null) {
          // No se puede cumplir el CHECK de `edan.fotografias`: NO se sube
          // (un `tipo_entidad` inválido sería 422/500) y la foto queda en cola
          // con el motivo, a la espera de que exista su fila dueña.
          pendientes++;
          await _rawUpdate('''
            UPDATE cola_fotos
            SET estado = 'pendiente',
                intentos = intentos + 1,
                fecha_proximo_intento = ?,
                ultimo_error = ?
            WHERE uuid_fotografia = ?
          ''', [
            _backoff(foto.intentos + 1),
            'tipo_entidad no resoluble para la fila ${foto.uuidRegistro}',
            foto.uuidFotografia,
          ]);
          continue;
        }
        final respFoto = await _api.subirFotografia(
          uuidFotografia: foto.uuidFotografia,
          tipoEntidad: tipoEntidad,
          uuidRegistro: foto.uuidRegistro ?? '',
          archivo: archivo,
          sha256: foto.sha256,
        );
        // Reconciliar la confirmación del servidor (arquitectura §19): sin
        // `ruta_servidor` guardada, un borrado posterior de esta foto nunca
        // se propagaría (`_pushBorradosFotos` solo ve filas con ruta).
        await _aplicarConfirmacionFoto(foto.uuidFotografia, respFoto.data);
        await _rawDelete(
          'DELETE FROM cola_fotos WHERE uuid_fotografia = ?',
          [foto.uuidFotografia],
        );
        subidas++;
      } on EdanApiError catch (e) {
        // Sesión expirada: abortar con mensaje accionable (reintentar cada
        // foto sería inútil); la foto queda pendiente para la próxima sesión.
        if (_esSesionExpirada(e)) {
          ultimoError = _mensajeSesionExpirada;
          await _rawUpdate('''
            UPDATE cola_fotos
            SET estado = 'pendiente', ultimo_error = ?
            WHERE uuid_fotografia = ?
          ''', [_mensajeSesionExpirada, foto.uuidFotografia]);
          break;
        }
        // P5 (fotos): 400 (no-imagen) / 403 (ajeno) / 404 (dueña inexistente:
        // la fila aún no llegó → reordenar) / 422 → rechazado, sin backoff.
        if (_esRechazoDefinitivo(e.statusCode)) {
          await _rawUpdate('''
            UPDATE cola_fotos
            SET estado = 'rechazado',
                ultimo_error = ?
            WHERE uuid_fotografia = ?
          ''', [e.detail, foto.uuidFotografia]);
        } else {
          final intentos = foto.intentos + 1;
          await _rawUpdate('''
            UPDATE cola_fotos
            SET estado = 'pendiente',
                intentos = ?,
                fecha_proximo_intento = ?,
                ultimo_error = ?
            WHERE uuid_fotografia = ?
          ''', [intentos, _backoff(intentos), e.detail, foto.uuidFotografia]);
        }
      } on SocketException {
        break;
      }
    }

    // Cierre de visibilidad: fotos en cola cuya dueña aún no está confirmada
    // (o ya no existe). Antes eran invisibles: el badge las contaba pero el
    // resumen salía en ceros ("Sin cambios por enviar" con cambios
    // pendientes). Se suman a `pendientes` para que el mensaje las muestre.
    final bloqueadas = await _contarFotosBloqueadas();
    pendientes += bloqueadas;
    final huerfanas = await _purgarFotosHuerfanas();
    if (kSyncDebugMode && (bloqueadas > 0 || huerfanas > 0)) {
      SyncDebugCollector.instance.addDiagnostico('Fotos en espera', {
        'bloqueadas_duena_sin_confirmar': bloqueadas,
        'huerfanas_purgadas': huerfanas,
      });
    }

    return EdanSyncResumen(
      exito: previo.exito,
      enviados: previo.enviados,
      conflictos: previo.conflictos,
      errores: previo.errores,
      fotosSubidas: subidas,
      fotosPendientes: pendientes,
      fotosDescargadas: previo.fotosDescargadas,
      ultimoError: ultimoError,
      watermark: previo.watermark,
    );
  }

  /// Fotos en cola cuya dueña existe pero aún no está confirmada (el gate no
  /// las deja subir). Se cuentan como pendientes para que el resumen no salga
  /// en ceros con trabajo real esperando.
  Future<int> _contarFotosBloqueadas() async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS c FROM cola_fotos f
      WHERE f.estado IN ('pendiente','subiendo')
        AND (
          EXISTS (SELECT 1 FROM filas_seccion s
                  WHERE s.uuid_registro = f.uuid_registro
                    AND s.estado_sync != 'confirmado')
          OR EXISTS (SELECT 1 FROM viviendas v
                     JOIN filas_seccion s
                       ON s.uuid_registro = v.uuid_dano_vivienda
                     WHERE v.uuid_registro = f.uuid_registro
                       AND s.estado_sync != 'confirmado')
        )
    ''');
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  /// Purga fotos en cola cuya dueña NO existe en ningún lado (ni fila ni
  /// vivienda): sin dueña no se podrán subir jamás. Solo se purgan si no hay
  /// ningún formulario con push pendiente (un guardado en curso aún podría
  /// crear la dueña). Devuelve cuántas purgó. La metadata conserva el motivo
  /// y el archivo se elimina (era basura sin referencia).
  Future<int> _purgarFotosHuerfanas() async {
    final db = await _db.database;
    final huerfanas = await db.rawQuery('''
      SELECT f.uuid_fotografia AS u, f.ruta_local AS ruta
      FROM cola_fotos f
      WHERE f.estado IN ('pendiente','subiendo')
        AND NOT EXISTS (SELECT 1 FROM filas_seccion s
                        WHERE s.uuid_registro = f.uuid_registro)
        AND NOT EXISTS (SELECT 1 FROM viviendas v
                        WHERE v.uuid_registro = f.uuid_registro)
    ''');
    if (huerfanas.isEmpty) return 0;
    final porGuardar = await db.query(
      'formularios',
      columns: ['uuid_edan_localidad'],
      where: 'pendiente_push = 1',
      limit: 1,
    );
    if (porGuardar.isNotEmpty) return 0;
    var n = 0;
    for (final h in huerfanas) {
      final u = h['u'] as String?;
      if (u == null || u.isEmpty) continue;
      await db.delete('cola_fotos',
          where: 'uuid_fotografia = ?', whereArgs: [u]);
      await db.update(
        'fotografias',
        {'last_error': 'Fila dueña inexistente: subida descartada'},
        where: 'uuid_fotografia = ?',
        whereArgs: [u],
      );
      final ruta = h['ruta'] as String?;
      if (ruta != null && ruta.isNotEmpty) {
        try {
          final archivo = File(ruta);
          if (await archivo.exists()) await archivo.delete();
        } catch (_) {}
      }
      n++;
    }
    if (n > 0) {
      debugPrint('[SyncV2] fotos huérfanas purgadas: $n');
    }
    return n;
  }

  /// Guarda la confirmación del servidor tras `POST /fotografias`
  /// (`ruta_archivo`, `sha256`, id + `fila_dueña` con el espejo): sin esto
  /// la fila local queda sin `ruta_servidor` y su borrado posterior jamás
  /// se propagaría. Además aplica el espejo `fotografia` de la dueña y
  /// marca `borrado_logico=1` a las fotos locales anteriores de la misma
  /// dueña (el servidor solo mantiene 1 activa por fila). Nunca lanza
  /// (la subida ya fue exitosa; esto es reconciliación local).
  Future<void> _aplicarConfirmacionFoto(
      String uuidFotografia, Map<String, dynamic>? data) async {
    if (data == null || data.isEmpty) return;
    try {
      final db = await _db.database;
      final cols = <String, Object?>{'upload_state': 'synced'};
      final ruta = data['ruta_archivo'];
      if (ruta is String && ruta.isNotEmpty) cols['ruta_servidor'] = ruta;
      final sha = data['sha256'];
      if (sha is String && sha.isNotEmpty) cols['sha256'] = sha;
      final idFoto = data['id_fotografia'];
      if (idFoto is num) cols['remote_id'] = idFoto.toInt();
      cols['last_error'] = null;
      await db.update(
        'fotografias',
        cols,
        where: 'uuid_fotografia = ?',
        whereArgs: [uuidFotografia],
      );
      // Espejo de la dueña desde `fila_dueña` (LWW 2026-10-16): evita el
      // re-pull que antes se hacía para releer versiones.
      final duena = data['fila_dueña'] ?? data['fila_duena'];
      if (duena is Map) {
        final espejo = (duena['fotografia'] as String?) ?? '';
        final uuidReg = duena['uuid_registro'] as String?;
        if (espejo.isNotEmpty && uuidReg != null && uuidReg.isNotEmpty) {
          await _aplicarEspejoFotoDuena(uuidReg, espejo);
        }
      }
      // 1 activa por fila: las locales anteriores de la misma dueña quedan
      // lógicas (el servidor ya marcó la anterior; el pull confirmará).
      final propia = await db.query(
        'fotografias',
        columns: ['tipo_entidad', 'uuid_registro'],
        where: 'uuid_fotografia = ?',
        whereArgs: [uuidFotografia],
        limit: 1,
      );
      if (propia.isNotEmpty) {
        final tipo = propia.first['tipo_entidad'];
        final reg = propia.first['uuid_registro'];
        await db.update(
          'fotografias',
          {'borrado_logico': 1},
          where: 'uuid_fotografia != ? AND tipo_entidad = ? '
              'AND uuid_registro = ? AND borrado_logico = 0 '
              'AND upload_state = ?',
          whereArgs: [uuidFotografia, tipo, reg, 'synced'],
        );
      }
    } catch (e) {
      debugPrint('[SyncV2] confirmación de foto no aplicada: $e');
    }
  }

  /// Escribe el espejo `fotografia` en la fila dueña: `datos_json.fotografia`
  /// en `filas_seccion`, columna `fotografia` en `viviendas`.
  Future<void> _aplicarEspejoFotoDuena(
      String uuidRegistro, String espejo) async {
    final db = await _db.database;
    final filas = await db.query(
      'filas_seccion',
      columns: ['datos_json'],
      where: 'uuid_registro = ?',
      whereArgs: [uuidRegistro],
      limit: 1,
    );
    if (filas.isNotEmpty) {
      try {
        final datos = jsonDecode(filas.first['datos_json'] as String)
            as Map<String, dynamic>;
        datos['fotografia'] = espejo;
        await db.update(
          'filas_seccion',
          {'datos_json': jsonEncode(datos)},
          where: 'uuid_registro = ?',
          whereArgs: [uuidRegistro],
        );
      } catch (_) {}
      return;
    }
    await db.update(
      'viviendas',
      {'fotografia': espejo},
      where: 'uuid_registro = ?',
      whereArgs: [uuidRegistro],
    );
  }

  /// Propaga al servidor el borrado lógico de fotos ya subidas (§3.5-4).
  ///
  /// Solo afecta a fotos con `ruta_servidor` (fueron subidas); las que estaban
  /// locales se purgaron en `EdanStoreV2.borrarFoto`. Tras un DELETE exitoso
  /// (o 404 = ya inexistente) se elimina el registro local para que el pull
  /// posterior no la resucite. Un fallo transitorio deja el registro y se
  /// reintenta en la próxima sync.
  Future<EdanSyncResumen> _pushBorradosFotos(EdanSyncResumen previo) async {
    final db = await _db.database;
    final rows = await db.query(
      'fotografias',
      where: "borrado_logico = 1 AND ruta_servidor IS NOT NULL "
          "AND ruta_servidor != ''",
    );
    for (final raw in rows) {
      final uuid = raw['uuid_fotografia'] as String;
      try {
        await _api.eliminarFotografia(uuid);
        await db.delete('fotografias',
            where: 'uuid_fotografia = ?', whereArgs: [uuid]);
      } on EdanApiError catch (e) {
        if (e.statusCode == 404) {
          await db.delete('fotografias',
              where: 'uuid_fotografia = ?', whereArgs: [uuid]);
        }
        // Otro error: se deja el registro para reintentar en la próxima sync.
      } on SocketException {
        break;
      }
    }
    return previo;
  }

  // ── Helpers ──

  Future<String> get _idDispositivo async {
    var id = await _db.getConfig(_claveIdDispositivo);
    if (id == null || id.isEmpty) {
      id = EdanUuidHelper.generarIdDispositivo();
      await _db.setConfig(_claveIdDispositivo, id);
    }
    return id;
  }

  Future<String?> get _watermark {
    final u = usuarioId;
    return _db.getConfig(
        u == null ? _claveWatermark : '${_claveWatermark}_$u');
  }

  Future<void> _guardarWatermark(String valor) {
    final u = usuarioId;
    return _db.setConfig(
        u == null ? _claveWatermark : '${_claveWatermark}_$u', valor);
  }

  String _backoff(int intentos) {
    final segundos = Duration(seconds: 2 << (intentos > 10 ? 10 : intentos));
    const maximo = Duration(hours: 1);
    final espera = segundos > maximo ? maximo : segundos;
    return DateTime.now().add(espera).toIso8601String();
  }

  /// P5: `true` si el status NO debe reintentarse solo (dato/regla/permiso).
  /// Solo red/401/5xx usan backoff.
  static bool _esRechazoDefinitivo(int? statusCode) =>
      statusCode == 400 ||
      statusCode == 403 ||
      statusCode == 404 ||
      statusCode == 422;

  /// 401 = sesión expirada/inválida: reintentar es inútil y encola backoffs
  /// eternos. Se aborta la corrida con mensaje accionable (re-login) en vez
  /// de marcar rechazos o reintentar cada ítem.
  static bool _esSesionExpirada(EdanApiError e) => e.statusCode == 401;

  static String get _mensajeSesionExpirada =>
      'Sesión expirada (401): vuelva a iniciar sesión para sincronizar';

  Future<int> _rawUpdate(String sql, [List<dynamic>? args]) async {
    final db = await _db.database;
    return db.rawUpdate(sql, args);
  }

  Future<int> _rawDelete(String sql, [List<dynamic>? args]) async {
    final db = await _db.database;
    return db.rawDelete(sql, args);
  }
}
