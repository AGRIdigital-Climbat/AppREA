import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../models/edan.dart';
import '../../models/edan_registro_v2.dart';
import '../../models/usuario.dart';
import '../database_helper.dart';
import 'edan_store.dart';
import 'edan_secciones_fuente.dart';
import 'edan_uuid_helper.dart';
import '../edan_secciones_registry.dart';

/// Implementación V2 de [EdanStore]. Persiste en el schema v30:
/// - `formularios`: cabecera + `datos_json` completo de la localidad.
/// - `filas_seccion`, `viviendas`, `fotografias`: tablas preparadas para el sync
///   incremental (en Fase 4 se descompone el JSON en filas).
/// - `cola_sincronizacion` / `cola_fotos`: colas de envío.
///
/// Fase 2 (schema + store local): CRUD de cabecera y fotos funcional;
/// descomposición por sección y motor de sync se completan en Fases 4-5.
class EdanStoreV2 implements EdanStore {
  EdanStoreV2({DatabaseHelper? db}) : _db = db ?? DatabaseHelper.instance;

  /// Instancia compartida por las pantallas RESP (inyección en el wizard y en
  /// el botón de sync). UGR/IA usan `EdanStoreLegacy` y no la tocan.
  static final EdanStoreV2 instance = EdanStoreV2();

  final DatabaseHelper _db;
  final _pendientesController = StreamController<int>.broadcast();

  /// Contadores expuestos para la UI (badges del botón sync / banner del
  /// dashboard). Se actualizan en cada [_notifyPendientes].
  final ValueNotifier<int> pendientesNotifier = ValueNotifier(0);

  /// `true` mientras el motor V2 ([EdanSyncEngineV2.sincronizar]) corre una
  /// corrida. Lo togglean las pantallas (p.ej. `resp_screen`) al invocar el
  /// motor; el store solo lo expone para que el botón/banner lo escuchen.
  final ValueNotifier<bool> sincronizandoNotifier = ValueNotifier(false);

  /// Se incrementa cada vez que termina la primera descarga (login en equipo
  /// nuevo). `resp_screen` lo escucha para refrescar las pestañas: sin esto
  /// la lista cargaba vacía al inicio y nunca se enteraba de que los datos
  /// ya habían bajado en segundo plano.
  final ValueNotifier<int> primeraDescarga = ValueNotifier(0);

  /// Se incrementa cada vez que los catálogos de red terminan de cargarse
  /// (ver `ReporteProvider._cargarRedEnSegundoPlano`). Las pestañas lo
  /// escuchan para recargar los nombres resueltos por catálogo sin depender
  /// de que el arranque haya terminado antes de montarse.
  final ValueNotifier<int> catalogosVersion = ValueNotifier(0);

  void avisarCatalogos() => catalogosVersion.value++;

  /// Versión de los DATOS visibles (formularios/filas/viviendas/estados).
  /// Se incrementa en cada mutación local (guardar, borrar, purga) y cuando
  /// el sync aplica contenido del servidor. Las listas lo escuchan para
  /// recargarse: sin esto, un formulario recién guardado no aparecía hasta
  /// pull-to-refresh manual (el guardado solo avisaba al badge pendientes).
  /// Dedicado (no se reutiliza `pendientesNotifier` para no recargar en cada
  /// tick del sync).
  final ValueNotifier<int> datosVersion = ValueNotifier(0);

  /// Publica que los datos cambiaron (ver [datosVersion]). Nunca lanza.
  void datosCambiados() {
    try {
      datosVersion.value++;
    } catch (_) {}
  }

  /// Progreso de descarga de bytes de fotos (`_descargarFotosPendientes`):
  /// total a bajar y cuántas van. La UI los escucha para la barra de
  /// progreso de la descarga inicial (puede haber muchas fotos).
  final ValueNotifier<int> descargaFotosTotal = ValueNotifier(0);
  final ValueNotifier<int> descargaFotosHechas = ValueNotifier(0);

  /// Fase textual de la corrida de sync en curso (`''` = ninguna). La franja
  /// de progreso la muestra durante CUALQUIER sincronización, incluida la
  /// primera descarga del login: 'Revisando cambios', 'Descargando datos',
  /// 'Descargando fotos', 'Subiendo cambios', 'Subiendo fotos'.
  final ValueNotifier<String> faseSync = ValueNotifier('');

  /// Motivo de la última primera-descarga fallida (`null` = la última fue OK
  /// o aún no corrió). La UI lo muestra para que el fallo no sea silencioso.
  String? ultimoErrorPrimeraDescarga;

  // ── Formularios ──

  @override
  Future<EdanLocalidad?> cargarFormulario(String uuidEdanLocalidad) async {
    final db = await _db.database;
    final rows = await db.query(
      'formularios',
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuidEdanLocalidad],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _localidadFromRow(rows.first);
  }

  @override
  Future<List<EdanLocalidad>> listarFormularios(
      {int? usuarioId, int? idMunicipio}) async {
    final db = await _db.database;
    final condiciones = <String>[];
    final whereArgs = <Object?>[];
    if (usuarioId != null) {
      condiciones.add('id_usuario = ?');
      whereArgs.add(usuarioId);
    }
    if (idMunicipio != null) {
      condiciones.add('id_municipio = ?');
      whereArgs.add(idMunicipio);
    }
    final rows = await db.query(
      'formularios',
      where: condiciones.isEmpty ? null : condiciones.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'fecha_modificacion DESC',
    );
    final lista = rows.map(_localidadFromRow).toList();
    // El pull guarda filas pero NO escribe los flags; se derivan aquí para que
    // badges y visibilidad reflejen los datos reales (bug Urubo).
    // Importante: derivarFlagsDesdeFilas retorna el modelo actualizado (no solo
    // escribe en DB), porque _localidadFromRow construye desde datos_json que
    // está vacío en fresh install.
    final resultado = <EdanLocalidad>[];
    for (final loc in lista) {
      final uuid = loc.uuidEdanLocalidad;
      if (uuid != null && uuid.isNotEmpty) {
        // Blindaje: una fila corrupta NO debe vaciar la lista completa
        // (la UI hace catch silencioso y mostraba "sin datos").
        try {
          final derivada = await derivarFlagsDesdeFilas(uuid);
          resultado.add(derivada ?? loc);
        } catch (_) {
          resultado.add(loc);
        }
      } else {
        resultado.add(loc);
      }
    }
    return resultado;
  }

  /// Listado unificado para las pantallas RESP (Etapa 5: fuente única).
  ///
  /// Lee `formularios` (verdad V2) + las filas legacy de `localidades_offline`
  /// que AÚN no tienen fila V2 (borradores del asistente IA o de versiones
  /// viejas), deduplicando por `uuid == id_local`. Orden descendente por
  /// `fecha_modificacion`. Los flags se hidratan después con
  /// `aplicarFlagsDesdeSeccionesActivas` (vía V2 cuando hay fila).
  Future<List<EdanLocalidad>> listarReportes({int? usuarioId}) async {
    final v2 = await listarFormularios(usuarioId: usuarioId);
    final vistos =
        v2.map((l) => l.uuidEdanLocalidad ?? l.idLocal ?? '').toSet();
    final db = await _db.database;
    final maps = await db.query(
      'localidades_offline',
      where: usuarioId != null
          ? 'usuario_id = ? AND pendiente_eliminacion = 0'
          : 'pendiente_eliminacion = 0',
      whereArgs: usuarioId != null ? [usuarioId] : null,
      orderBy: 'fecha_creacion DESC',
    );
    final legado = maps
        .map((m) => _db.localidadFromRow(m))
        .where((l) => !vistos.contains(l.idLocal ?? ''))
        .toList();
    final todos = [...v2, ...legado];
    todos.sort((a, b) =>
        (b.fechaModificacion ?? '').compareTo(a.fechaModificacion ?? ''));
    return todos;
  }

  /// Contadores del Inicio calculados SOLO de SQLite (offline-first).
  ///
  /// `por_estado` trae los 6 estados disgregados (id 1-6 → cantidad) y
  /// `total` su suma. Incluye el legado `localidades_offline` que aún no
  /// tiene fila V2 (dedup por `id_local == uuid_edan_localidad`), así el
  /// conteo coincide exactamente con la lista de Reportes.
  Future<({Map<int, int> porEstado, int total})> resumenLocal(
      {int? usuarioId}) async {
    final db = await _db.database;
    final porEstado = <int, int>{};
    var total = 0;
    void acumular(int est, int c) {
      porEstado[est] = (porEstado[est] ?? 0) + c;
      total += c;
    }

    // V2: `formularios`. El estado ausente se trata como borrador (id 1),
    // igual que la UI (`UgrLocalidadEstado.borrador`).
    final whereV2 = usuarioId != null ? 'id_usuario = ?' : null;
    final argsV2 = usuarioId != null ? [usuarioId] : null;
    final v2 = await db.rawQuery('''
      SELECT COALESCE(id_edan_localidad_estado, 1) AS est, COUNT(*) AS c
      FROM formularios
      ${whereV2 != null ? 'WHERE $whereV2' : ''}
      GROUP BY est
    ''', argsV2);
    for (final r in v2) {
      acumular((r['est'] as num).toInt(), (r['c'] as num).toInt());
    }

    // Legado: `localidades_offline` sin contraparte V2.
    final whereL = usuarioId != null
        ? 'usuario_id = ? AND pendiente_eliminacion = 0'
        : 'pendiente_eliminacion = 0';
    final argsL = usuarioId != null ? [usuarioId] : null;
    final leg = await db.rawQuery('''
      SELECT COALESCE(id_edan_localidad_estado, 1) AS est, COUNT(*) AS c
      FROM localidades_offline
      WHERE $whereL
        AND id_local NOT IN (SELECT uuid_edan_localidad FROM formularios)
      GROUP BY est
    ''', argsL);
    for (final r in leg) {
      acumular((r['est'] as num).toInt(), (r['c'] as num).toInt());
    }

    return (porEstado: porEstado, total: total);
  }

  @override
  Future<void> guardarFormulario(
    EdanLocalidad loc, {
    required int usuarioId,
    List<String>? seccionesActivas,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await _guardarFormularioTx(txn, loc,
          usuarioId: usuarioId, seccionesActivas: seccionesActivas);
    });
    final uuid = loc.uuidEdanLocalidad;
    if (uuid != null && uuid.isNotEmpty) {
      // Dirty derivado de la firma: si el contenido no cambió, no viaja.
      await recargarFirma(uuid, sincronizada: false);
    }
    _notifyPendientes();
  }

  /// Guarda cabecera + filas en una sola transacción (Etapa 3: todo o nada —
  /// un kill a mitad de `_guardar` ya no deja cabecera sin filas).
  ///
  /// Con [purgarInactivas] (guardados completos del wizard) se purgan las
  /// filas de las rutas que dejaron de estar activas: el grupo manda y lo
  /// destildado no viaja, así que tampoco debe quedar en SQLite.
  @override
  Future<void> guardarTodo(
    EdanLocalidad loc, {
    required int usuarioId,
    List<String>? seccionesActivas,
    required List<String> tipos,
    bool purgarInactivas = false,
  }) async {
    _ensureUuid(loc);
    final db = await _db.database;
    await db.transaction((txn) async {
      await _guardarFormularioTx(txn, loc,
          usuarioId: usuarioId, seccionesActivas: seccionesActivas);
      final uuid = loc.uuidEdanLocalidad;
      if (uuid != null && uuid.isNotEmpty && tipos.isNotEmpty) {
        await _guardarFilasTx(txn, uuid, tipos, loc, guardarCabecera: false);
      }
    });
    if (purgarInactivas) {
      final uuid = loc.uuidEdanLocalidad;
      // Solo purga determinista: activas explícitas (page01). Sin activas
      // (guardado parcial) no se toca nada para no borrar secciones que el
      // modelo simplemente no cargó.
      final activas = seccionesActivas;
      if (uuid != null && uuid.isNotEmpty && activas != null) {
        final inactivas = EdanSeccionesRegistry.rutasV2Todas()
            .where((t) => !activas.contains(t))
            .toList();
        if (inactivas.isNotEmpty) {
          await purgarSecciones(uuid, inactivas);
        }
      }
    }
    final uuidFin = loc.uuidEdanLocalidad;
    if (uuidFin != null && uuidFin.isNotEmpty) {
      // Dirty derivado de TODA la localidad (cabecera + 14 secciones +
      // viviendas): lo no modificado no viaja.
      await recargarFirma(uuidFin, sincronizada: false);
    }
    _notifyPendientes();
  }

  /// Núcleo transaccional de [guardarFormulario]: opera sobre [ex] (la
  /// transacción abierta por el llamador), nunca sobre `_db.database`.
  Future<void> _guardarFormularioTx(
    DatabaseExecutor ex,
    EdanLocalidad loc, {
    required int usuarioId,
    List<String>? seccionesActivas,
  }) async {
    _ensureUuid(loc);
    loc.idUsuario = usuarioId;
    loc.idLocal = loc.uuidEdanLocalidad;

    // Si no se pasan seccionesActivas, preserva las ya persistidas para no
    // perder la activación de grupos (p.ej. grupAgropecuario → 3 rutas) al
    // re-guardar la cabecera desde guardarFilas.
    List<String>? activas = seccionesActivas;
    if (activas == null) {
      final previas = await ex.query(
        'formularios',
        columns: ['secciones_activas_json'],
        where: 'uuid_edan_localidad = ?',
        whereArgs: [loc.uuidEdanLocalidad],
        limit: 1,
      );
      if (previas.isNotEmpty) {
        final raw = previas.first['secciones_activas_json'];
        if (raw is List) {
          activas = [for (final e in raw) '$e'];
        } else if (raw is String && raw.isNotEmpty) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is List) {
              activas = decoded.map((e) => e.toString()).toList();
            }
          } catch (_) {
            // Auxiliar corrupto: se ignora y manda el parámetro.
          }
        }
      }
    }
    // Gap 3: preservar caché GET y —Etapa 3— `estado_local` y
    // `sync_state`. Re-guardar un `enviado`/`synced` no debe degradarlo a
    // `borrador`/`pending_create` (arquitectura §6: negocio ≠ sync).
    final previa = await ex.query(
      'formularios',
      columns: [
        'datos_json_servidor',
        'estado_local',
        'sync_state',
        'pending_submit',
        'estado_destino',
        'firma_enviada',
        'usuario_nombre',
        'usuario_login',
        'id_rol',
        'usuario_rol',
        'estado_nombre',
        'tipo_evento_nombre',
        'tipo_localidad_nombre',
        'departamento_nombre',
        'departamento_codigo',
        'provincia_nombre',
        'provincia_codigo',
        'municipio_nombre',
        'municipio_codigo',
        'id_edan',
        'edan_codigo',
      ],
      where: 'uuid_edan_localidad = ?',
      whereArgs: [loc.uuidEdanLocalidad],
      limit: 1,
    );
    final esNuevo = previa.isEmpty;
    final datosServidorPrevio =
        esNuevo ? null : previa.first['datos_json_servidor'] as String?;
    final estadoPrevio = esNuevo
        ? 'borrador'
        : (previa.first['estado_local'] as String? ?? 'borrador');
    var syncPrevio = esNuevo
        ? 'pending_create'
        : (previa.first['sync_state'] as String? ?? 'pending_create');
    // Un re-guardado con cambios sobre algo ya confirmado pasa a
    // `pending_update`; los demás estados (conflict/failed) se conservan para
    // que la UI los resuelva.
    if (!esNuevo && syncPrevio == 'synced') syncPrevio = 'pending_update';
    final pendingSubmitPrevio =
        esNuevo ? 0 : (previa.first['pending_submit'] as int? ?? 0);
    // La intención de envío sobrevive a los re-guardados: si el usuario editó
    // después de pulsar "Enviar" sin red, el destino sigue pendiente.
    final destinoPrevio = esNuevo
        ? null
        : (previa.first['estado_destino'] as num?)?.toInt();

    // Regla grup-manda: si el llamador declara las secciones activas
    // (page01), los 9 `grup` del modelo Y de las columnas reflejan EXACTAMENTE
    // esa selección — ni más por filas huérfanas, ni menos por snapshot
    // viejo. Sin activas explícitas no se tocan (guardados parciales).
    if (seccionesActivas != null) {
      final g = EdanSeccionesRegistry.gruposDesdeActivas(seccionesActivas);
      loc
        ..grupPoblacion = g.contains('grupPoblacion')
        ..grupSalud = g.contains('grupSalud')
        ..grupInfraestructura = g.contains('grupInfraestructura')
        ..grupServicios = g.contains('grupServicios')
        ..grupEducacion = g.contains('grupEducacion')
        ..grupVivienda = g.contains('grupVivienda')
        ..grupAgropecuario = g.contains('grupAgropecuario')
        ..grupProteccion = g.contains('grupProteccion')
        ..grupNecesidades = g.contains('grupNecesidades');
    }

    final row = _formularioToRow(
      loc,
      seccionesActivas: activas ?? const [],
      estadoLocal: estadoPrevio,
      syncState: syncPrevio,
      pendingSubmit: pendingSubmitPrevio,
      estadoDestino: destinoPrevio,
    );
    if (datosServidorPrevio != null) {
      row['datos_json_servidor'] = datosServidorPrevio;
    }
    // La firma enviada es la referencia del dirty derivado: un re-guardado
    // (REPLACE) no debe borrarla o todo re-guardado nacería sucio aunque el
    // contenido sea idéntico al ya confirmado.
    if (!esNuevo) {
      final enviadaPrevia = previa.first['firma_enviada'] as String?;
      if (enviadaPrevia != null) row['firma_enviada'] = enviadaPrevia;
    }
    // Espejos del servidor (autor, nombres, edan): el wizard no los escribe;
    // el REPLACE no debe borrarlos (misma clase de bug que firma_enviada).
    // Solo el pull/`GET /completo` los actualiza.
    if (!esNuevo) {
      const espejos = [
        'usuario_nombre',
        'usuario_login',
        'id_rol',
        'usuario_rol',
        'estado_nombre',
        'tipo_evento_nombre',
        'tipo_localidad_nombre',
        'departamento_nombre',
        'departamento_codigo',
        'provincia_nombre',
        'provincia_codigo',
        'municipio_nombre',
        'municipio_codigo',
        'id_edan',
        'edan_codigo',
      ];
      for (final c in espejos) {
        final v = previa.first[c];
        if (v != null) row[c] = v;
      }
    }
    // UNIQUE parcial `uq_formularios_id_server`: si otro uuid ya tiene este
    // `id_server`, se suelta ANTES del insert. (Después sería tarde: el
    // `REPLACE` borraría la otra fila en vez de fallar.) Sin `id_server` el
    // próximo push va por POST→409→PUT y se autocura.
    if (row['id_server'] != null) {
      final dueno = await ex.query(
        'formularios',
        columns: ['uuid_edan_localidad'],
        where: 'id_server = ? AND uuid_edan_localidad != ?',
        whereArgs: [row['id_server'], loc.uuidEdanLocalidad],
        limit: 1,
      );
      if (dueno.isNotEmpty) {
        debugPrint('[EdanStoreV2] id_server ${row['id_server']} en uso por '
            '${dueno.first['uuid_edan_localidad']}: se suelta');
        loc.idServer = null;
        row['id_server'] = null;
      }
    }
    try {
      await ex.insert(
        'formularios',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } on DatabaseException catch (e) {
      // Carrera residual (dos escrituras simultáneas): mismo tratamiento.
      if (e.toString().contains('UNIQUE') &&
          row['id_server'] != null) {
        debugPrint('[EdanStoreV2] id_server duplicado en carrera: $e');
        loc.idServer = null;
        row['id_server'] = null;
        await ex.insert(
          'formularios',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } else {
        rethrow;
      }
    }
    // La fuente de verdad de "qué secciones existen" es la tabla auxiliar
    // v31, no `secciones_activas_json`. Si el llamador pasó las secciones
    // activas (el wizard las deriva de los grupos de page01), se persisten
    // ahí con origen 'usuario'.
    if (seccionesActivas != null && seccionesActivas.isNotEmpty) {
      final validas = seccionesActivas
          .where((s) => EdanSeccionesRegistry.grupoDeRuta(s) != null)
          .toList();
      if (validas.isNotEmpty) {
        await _activarSeccionesTx(ex, loc.uuidEdanLocalidad!, validas);
      }
      // La selección de grupos (v32) se deriva de las mismas secciones para
      // que ambas tablas cuenten siempre la misma historia.
      await _guardarSeleccionGruposTx(
        ex,
        loc.uuidEdanLocalidad!,
        EdanSeccionesRegistry.gruposDesdeActivas(validas),
      );
    }
    // Y la vista derivada se recalcula como la unión con lo que tiene datos.
    await _sincronizarVistaSeccionesActivasTx(ex, loc.uuidEdanLocalidad!);
    // §5.2/Fase D: guardar local ⇒ marcar `pendiente_push=1`. El motor empuja
    // el formulario COMPLETO (cabecera + 14 `imp_*` + secciones + viviendas)
    // vía `POST /formularios/completo` en una sola llamada, no por ítem.
    // La cola solo queda para `accion='D'` (borrados), que el endpoint
    // `/completo` no maneja porque es upsert sin borrado.
    await ex.update(
      'formularios',
      {'pendiente_push': 1},
      where: 'uuid_edan_localidad = ?',
      whereArgs: [loc.uuidEdanLocalidad],
    );
  }

  @override
  Future<void> marcarEnviado(String uuidEdanLocalidad) async {
    final db = await _db.database;
    await db.update(
      'formularios',
      {
        'estado_local': 'enviado',
        'fecha_modificacion': DateTime.now().toIso8601String(),
      },
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuidEdanLocalidad],
    );
    _notifyPendientes();
    datosCambiados();
  }

  @override
  Future<void> marcarEnvioPendiente(
      String uuidEdanLocalidad, int idEstadoDestino) async {
    final db = await _db.database;
    await db.update(
      'formularios',
      {
        'pending_submit': 1,
        'estado_destino': idEstadoDestino,
        'pendiente_push': 1,
      },
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuidEdanLocalidad],
    );
    _notifyPendientes();
    // El banner "Envío pendiente" de la tarjeta depende de esto.
    datosCambiados();
  }

  @override
  Future<void> marcarBorradoFormulario(String uuidEdanLocalidad) async {
    final db = await _db.database;
    // `viviendas` no tiene `uuid_edan_localidad`: su dueña es la fila
    // `danos_vivienda` (`uuid_dano_vivienda`). Se borra por subconsulta ANTES de
    // borrar las filas, porque si no la subconsulta quedaría vacía.
    await db.delete(
      'viviendas',
      where: 'uuid_dano_vivienda IN ('
          'SELECT uuid_registro FROM filas_seccion '
          'WHERE uuid_edan_localidad = ?)',
      whereArgs: [uuidEdanLocalidad],
    );
    await db.delete(
      'fotografias',
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuidEdanLocalidad],
    );
    await db.delete(
      'filas_seccion',
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuidEdanLocalidad],
    );
    await db.delete(
      'formularios',
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuidEdanLocalidad],
    );
    await db.delete(
      'secciones_grupos_local',
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuidEdanLocalidad],
    );
    await db.delete(
      'grupos_local',
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuidEdanLocalidad],
    );
    _notifyPendientes();
    // La tarjeta desaparece de la lista.
    datosCambiados();
  }

  @override
  Future<void> eliminarLocalidad(String uuidEdanLocalidad) async {
    final db = await _db.database;
    // Fuente de verdad: ¿existe en el servidor? Solo entonces hay algo que
    // informarle (vía `D`); si nunca se sincronizó, el borrado es local.
    final form = await db.query(
      'formularios',
      columns: ['id_server'],
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuidEdanLocalidad],
      limit: 1,
    );
    final sincronizado =
        form.isNotEmpty && form.first['id_server'] != null;

    // Uuids propios para purgar sus colas (filas + hijas + fotos).
    final filas = await db.query(
      'filas_seccion',
      columns: ['uuid_registro'],
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuidEdanLocalidad],
    );
    final uuidsFila = {
      for (final f in filas)
        if (f['uuid_registro'] is String) f['uuid_registro'] as String,
    };
    final hijas = uuidsFila.isEmpty
        ? const <Map<String, Object?>>[]
        : await db.query(
            'viviendas',
            columns: ['uuid_registro'],
            where: 'uuid_dano_vivienda IN '
                '(${List.filled(uuidsFila.length, '?').join(',')})',
            whereArgs: uuidsFila.toList(),
          );
    final uuidsHija = {
      for (final h in hijas)
        if (h['uuid_registro'] is String) h['uuid_registro'] as String,
    };
    // Archivos locales de sus fotos (se borran del disco siempre).
    final fotos = await db.query(
      'fotografias',
      columns: ['ruta_local'],
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuidEdanLocalidad],
    );
    for (final foto in fotos) {
      final ruta = foto['ruta_local'] as String?;
      if (ruta == null || ruta.isEmpty) continue;
      try {
        final archivo = File(ruta);
        if (await archivo.exists()) await archivo.delete();
      } catch (_) {}
    }

    // Purga de colas por uuid de fila/dueña (`cola_fotos` se clavea por
    // `uuid_registro` de la dueña, NO por `uuid_fotografia`: purgar por el
    // id de foto no borraría nada y el contador quedaría marcado).
    final todos = <String>{uuidEdanLocalidad, ...uuidsFila, ...uuidsHija};
    for (final u in todos) {
      await db.delete(
        'cola_sincronizacion',
        where: 'uuid_registro = ?',
        whereArgs: [u],
      );
      await db.delete(
        'cola_fotos',
        where: 'uuid_registro = ?',
        whereArgs: [u],
      );
    }
    await db.delete(
      'viviendas',
      where: 'uuid_dano_vivienda IN ('
          'SELECT uuid_registro FROM filas_seccion '
          'WHERE uuid_edan_localidad = ?)',
      whereArgs: [uuidEdanLocalidad],
    );
    await db.delete(
      'fotografias',
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuidEdanLocalidad],
    );
    await db.delete(
      'filas_seccion',
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuidEdanLocalidad],
    );
    await db.delete(
      'formularios',
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuidEdanLocalidad],
    );
    await db.delete(
      'secciones_grupos_local',
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuidEdanLocalidad],
    );
    await db.delete(
      'grupos_local',
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuidEdanLocalidad],
    );
    if (sincronizado) {
      // Propagar al servidor en el próximo sync (404 = ya no existe → el
      // motor lo purga solo).
      await encolar(
        tabla: 'formulario',
        uuidRegistro: uuidEdanLocalidad,
        accion: 'D',
      );
    }
    _notifyPendientes();
    datosCambiados();
  }

  // ── Secciones / filas ──

  @override
  Future<void> guardarFilas(
    String uuidEdanLocalidad,
    List<String> tipos,
    EdanLocalidad loc,
  ) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await _guardarFilasTx(txn, uuidEdanLocalidad, tipos, loc);
    });
    await recargarFirma(uuidEdanLocalidad, sincronizada: false);
    _notifyPendientes();
  }

  /// Núcleo transaccional de [guardarFilas] sobre [ex]. Con
  /// [guardarCabecera] repite el `guardarFormulario` final (lo usa la vía
  /// pública; [guardarTodo] ya guardó la cabecera y lo omite).
  Future<void> _guardarFilasTx(
    DatabaseExecutor ex,
    String uuidEdanLocalidad,
    List<String> tipos,
    EdanLocalidad loc, {
    bool guardarCabecera = true,
  }) async {
    final now = DateTime.now().toIso8601String();

    for (final tipo in tipos) {
      final desc = EdanSeccionesRegistry.porRuta(tipo);
      if (desc == null) {
        // Ruta inexistente (p. ej. 'necesidad-primera-respuesta' en vez de
        // 'primera-respuesta'): antes se saltaba en silencio y los datos no
        // se guardaban. Se avisa para cazar el llamador.
        debugPrint('[EdanStoreV2] ruta de sección desconocida: $tipo');
        continue;
      }

      final datos = _extraerSeccion(loc, desc.llaveJson);
      if (datos == null) continue;

      // Gap 3/2: leer las filas previas de ESTE tipo de una sola vez para
      // decidir si el upsert es creación (`C`) o actualización (`U`), y (b)
      // reconciliar las bajas: filas que ya no están en el modelo se eliminan
      // localmente y, si ya estaban sincronizadas, se encola su `D` para el
      // servidor.
      final previas = await ex.query(
        'filas_seccion',
        columns: ['uuid_registro', 'estado_sync', 'remote_id'],
        where: 'tipo = ? AND uuid_edan_localidad = ?',
        whereArgs: [tipo, uuidEdanLocalidad],
      );
      final previasPorUuid = <String, Map<String, Object?>>{
        for (final p in previas)
          if (p['uuid_registro'] != null)
            p['uuid_registro'] as String: p,
      };

      final uuidsActuales = <String>{};

      Future<void> registrarFila(dynamic item) async {
        // El `uuid_registro` nace al persistir: se conserva si ya es uuid
        // válido, y se genera si falta o trae un id legacy con prefijo
        // (mandarlo daría 422 en el servidor).
        final previo = item.idSeccion as String?;
        if (previo == null ||
            previo.isEmpty ||
            !EdanUuidHelper.esUuidValido(previo)) {
          item.idSeccion = EdanUuidHelper.generarUuidRegistro();
        }
        final uuid = item.idSeccion as String;
        uuidsActuales.add(uuid);
        // `toApiJson` es el contrato de la fila; si una clase aún no lo
        // tiene, se usa `toJson` antes que tumbar el guardado entero
        // (NoSuchMethodError como el de `EdanImpactoPoblacion` en vivo).
        Map<String, dynamic> datosApi;
        try {
          datosApi =
              Map<String, dynamic>.from(item.toApiJson() as Map);
        } on NoSuchMethodError {
          debugPrint('[EdanStoreV2] $tipo sin toApiJson: usa toJson');
          datosApi = Map<String, dynamic>.from(item.toJson() as Map);
        }
        await ex.insert(
          'filas_seccion',
          {
            'uuid_registro': uuid,
            'uuid_edan_localidad': uuidEdanLocalidad,
            'tipo': tipo,
            'datos_json': jsonEncode(sanearJson(datosApi)),
            'fecha_modificacion_local': now,
            'estado_sync': 'pendiente',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        // Fase D: NO se encola `C`/`U` por fila. El motor empuja el
        // formulario completo vía `/completo`; la cola solo queda para `D`.
      }

      if (desc.tipo == EdanSeccionTipo.unoAN) {
        if (tipo == 'impacto-poblacion') {
          // El servidor espera una fila POR grupo etario con su
          // `id_grupo_etario` (§20.10.E, mismo contrato que
          // `_impactoPoblacionApi` y el servicio legacy). El modelo de page03
          // es UN wrapper con los grupos anidados: se expande aquí. Las filas
          // con id usan el uuid sintético determinista del catálogo (igual que
          // `_padCatalogoTx` y que el motor): re-guardar no duplica y el
          // padding solo rellena los ids que faltan. Un grupo sin datos reales
          // no se persiste ("solo va lo llenado").
          for (final wrapper in datos as List<dynamic>) {
            if (wrapper is! EdanImpactoPoblacion) continue;
            var guardados = 0;
            for (final g in wrapper.gruposEtarios) {
              if (!filaSeccionConDatos('impacto-poblacion', g)) continue;
              final id = g.idGrupoEtario;
              if (id == null) {
                await registrarFila(g);
                guardados++;
                continue;
              }
              final uuid = EdanSeccionesFuente.uuidFilaSintetica(
                  uuidEdanLocalidad, 'impacto-poblacion', id);
              g.idSeccion = uuid;
              await ex.insert(
                'filas_seccion',
                {
                  'uuid_registro': uuid,
                  'uuid_edan_localidad': uuidEdanLocalidad,
                  'tipo': tipo,
                  'datos_json': jsonEncode(sanearJson(g.toApiJson())),
                  'fecha_modificacion_local': now,
                  'estado_sync': 'pendiente',
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              uuidsActuales.add(uuid);
              guardados++;
            }
            if (guardados == 0 && wrapper.tieneDatosGlobales) {
              // Legacy: datos globales del wrapper sin grupos anidados llenos
              // (importaciones v1). Se persiste el wrapper tal cual; si su
              // `grupoEtario` resuelve id, viaja con él.
              await registrarFila(wrapper);
            }
          }
        } else {
          for (final item in datos as List<dynamic>) {
            // Contrato "solo lo llenado" (flag↔fila §20.1): las filas sembradas
            // vacías (las 5 de servicios de page01/page06, los defaults de
            // protección) NO se persisten. Los catálogos (impacto 4, protección
            // 8) completan el set exacto abajo con `_padCatalogoTx` solo si su
            // flag es true — y el flag solo es true si hay alguna fila llena.
            if (!filaSeccionConDatos(tipo, item)) continue;
            await registrarFila(item);
            // Detalle 1:N de viviendas bajo una fila `danos_vivienda` (Fase 6/7).
            if (item is EdanDanoVivienda) {
              await _sincronizarViviendasDeFilaTx(ex, item,
                  uuidEdanLocalidad: uuidEdanLocalidad);
            }
          }
        }
      } else if (filaSeccionConDatos(tipo, datos)) {
        // 1:1 con el mismo contrato que 1:N: el registro por defecto vacío
        // (constructor init `necesidad*` con todos los campos en blanco) no
        // se persiste ni se emite; si antes había fila y ahora quedó vacío,
        // Gap 2 la purga y encola su `D`.
        await registrarFila(datos);
      }

      // §20.10.E/§20.11: `impacto-poblacion` y `proteccion` son catálogo. Si su
      // flag `imp_*` está true, el servidor exige el SET EXACTO (4 grupos
      // etarios / 8 grupos vulnerables). Aquí se persisten las filas faltantes
      // con `uuid_registro` DETERMINISTA (idempotente: mismo uuid que arma el
      // padding del push, así el `REPLACE` no duplica y el payload sigue
      // exacto). Sin esto SQLite solo traía las filas que el usuario llenó.
      await _padCatalogoTx(
        ex,
        uuidEdanLocalidad,
        tipo: 'impacto-poblacion',
        flag: _flagImpDeRuta('impacto-poblacion', loc),
        idCampo: 'id_grupo_etario',
        ids: const [1, 2, 3, 4],
        rutaTipo: 'impacto-poblacion',
        defaults: const {'fallecidos': 0, 'heridos': 0, 'desaparecidos': 0},
      ).then(uuidsActuales.addAll);
      await _padCatalogoTx(
        ex,
        uuidEdanLocalidad,
        tipo: 'proteccion',
        flag: _flagImpDeRuta('proteccion', loc),
        idCampo: 'id_grupo_vulnerable_catalogo',
        ids: const [1, 2, 3, 4, 5, 6, 7, 8],
        rutaTipo: 'proteccion',
        defaults: const {'mujeres': 0, 'hombres': 0},
        // Slots ya cubiertos por una fila con datos del modelo (posible
        // huérfana legacy fusionada con la sintética del padding): no se
        // blindan, Gap-2 purga la perdedora y el id queda con una sola fila.
        claimedIds: {
          for (final g in loc.proteccion)
            if (filaSeccionConDatos('proteccion', g) &&
                g.idGrupoVulnerable != null)
              g.idGrupoVulnerable!,
        },
      ).then(uuidsActuales.addAll);

      // Gap 2 (reconciliación de bajas): eliminar las filas de ESTE tipo que
      // ya no están en el modelo. Si estaban sincronizadas (confirmadas o con
      // `remote_id`) se encola su `D` para que el motor las borre en el
      // servidor; si nunca se sincronizaron solo se purga la copia local.
      // Esto corrige que una fila borrada reapareciera al recargar el borrador.
      for (final uuid
          in previasPorUuid.keys.toSet().difference(uuidsActuales)) {
        final previa = previasPorUuid[uuid]!;
        final sincronizada = previa['estado_sync'] == 'confirmado' ||
            previa['remote_id'] != null;
        await ex.delete(
          'filas_seccion',
          where: 'uuid_registro = ?',
          whereArgs: [uuid],
        );
        await ex.delete(
          'cola_sincronizacion',
          where: 'tabla = ? AND uuid_registro = ?',
          whereArgs: ['filas_seccion', uuid],
        );
        if (sincronizada) {
          await _encolarTx(
            ex,
            tabla: 'filas_seccion',
            uuidRegistro: uuid,
            accion: 'D',
            payload: {
              'uuid_edan_localidad': uuidEdanLocalidad,
              'tipo': tipo,
            },
          );
        }
      }
    }

    // Persistir la localidad actualizada (ahora con UUIDs en las filas), en la
    // misma transacción — salvo que el llamador ya guardó la cabecera.
    if (guardarCabecera) {
      await _guardarFormularioTx(ex, loc, usuarioId: loc.idUsuario ?? 0);
    }
  }

  /// Núcleo transaccional de viviendas 1:N de una fila `danos_vivienda`.
  Future<void> _sincronizarViviendasDeFilaTx(
    DatabaseExecutor ex,
    EdanDanoVivienda fila, {
    required String uuidEdanLocalidad,
  }) async {
    final uuidFila = fila.idSeccion;
    if (uuidFila == null || uuidFila.isEmpty) return;

    final previas = await ex.query(
      'viviendas',
      columns: ['uuid_registro'],
      where: 'uuid_dano_vivienda = ?',
      whereArgs: [uuidFila],
    );
    final uuidsPrevios = previas
        .map((r) => r['uuid_registro'] as String?)
        .whereType<String>()
        .toSet();

    // Guarda anti-pérdida: si el modelo NO hidrató el 1:N (borrador anterior
    // a la tabla `viviendas`, o sección importada sin pasar por
    // `cargarSecciones`), NO se derivan bajas. Sin esta guarda, re-guardar
    // borraba TODAS las viviendas del servidor, porque `uuidsActuales`
    // quedaba vacío por el simple hecho de no haberse cargado.
    if (fila.viviendas.isEmpty && uuidsPrevios.isNotEmpty &&
        !fila.viviendasCargadas) {
      return;
    }

    final uuidsActuales = <String>{};
    for (final viv in fila.viviendas) {
      viv.uuidDanoVivienda = uuidFila;
      await _guardarViviendaTx(ex, viv); // asigna uuidRegistro si falta
      uuidsActuales.add(viv.uuidRegistro!);
      // Fase D: NO se encola `C`/`U` por vivienda. El motor empuja el
      // formulario completo vía `/completo`; la cola solo queda para `D`.
    }

    // Bajas: purga el upsert pendiente y encola solo el borrado.
    for (final uuid in uuidsPrevios.difference(uuidsActuales)) {
      await _eliminarViviendaTx(ex, uuid);
      await ex.delete(
        'cola_sincronizacion',
        where: 'tabla = ? AND uuid_registro = ?',
        whereArgs: ['vivienda', uuid],
      );
      await _encolarTx(
        ex,
        tabla: 'vivienda',
        uuidRegistro: uuid,
        accion: 'D',
        payload: {
          'uuid_edan_localidad': uuidEdanLocalidad,
          'uuid_dano_vivienda': uuidFila,
        },
      );
    }
  }

  dynamic _extraerSeccion(EdanLocalidad loc, String llaveJson) {
    switch (llaveJson) {
      case 'impacto_poblacion':
        return loc.impactoPoblacion;
      case 'establecimientos_salud':
        return loc.establecimientosSalud;
      case 'danos_viales':
        return loc.danosViales;
      case 'danos_infra_publica':
        return loc.danosInfraPublica;
      case 'servicios_basicos':
        return loc.serviciosBasicos;
      case 'unidades_educativas':
        return loc.unidadesEducativas;
      case 'danos_vivienda':
        return loc.danosVivienda;
      case 'danos_agricultura':
        return loc.danosAgricultura;
      case 'danos_pecuarios':
        return loc.danosPecuarios;
      case 'infra_productiva':
        return loc.infraProductiva;
      case 'proteccion':
        return loc.proteccion;
      case 'necesidad_primera_respuesta':
        return loc.necesidadPrimeraRespuesta;
      case 'necesidad_salud':
        return loc.necesidadSalud;
      case 'necesidad_humanitaria':
        return loc.necesidadHumanitaria;
      default:
        return null;
    }
  }

  @override
  Future<void> cargarSecciones(EdanLocalidad loc,
      {List<String>? tipos}) async {
    // El uuid puede faltar en el modelo de un borrador reabierto (si su
    // datos_json se guardó antes de asignarlo); se usa `idLocal` como respaldo
    // porque en V2 ambos coinciden (`_localidadFromRow` fuerza
    // idLocal = uuidEdanLocalidad y `_ensureUuid` reutiliza el idLocal).
    final uuid = loc.uuidEdanLocalidad ?? loc.idLocal;
    if (uuid == null || uuid.isEmpty) return;
    final db = await _db.database;
    final tiposQuery = tipos ?? EdanSeccionesRegistry.rutasV2Todas();

    // Segunda fuente: el snapshot de cabecera (`formularios.datos_json`).
    // Hay reportes cuyos datos nunca llegaron a `filas_seccion`; sin este
    // rescate, la vista previa los mostraba vacíos ("Sección no marcada,
    // actualmente sin datos") aunque la tarjeta del listado sí los contaba.
    Map<String, Object?>? filaCabecera;
    final cab = await db.query(
      'formularios',
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (cab.isNotEmpty) filaCabecera = cab.first;
    final snap = EdanSeccionesFuente.snapshotDe(filaCabecera);
    // Mismo criterio que el payload `/completo`: solo se rescatan secciones
    // que el snapshot realmente tiene con datos (los objetos por defecto de
    // `EdanLocalidad()` no cuentan).
    final rutasSnap = EdanSeccionesFuente.rutasConDatosEnSnapshot(snap);

    for (final tipo in tiposQuery) {
      final desc = EdanSeccionesRegistry.porRuta(tipo);
      if (desc == null) continue;

      // Tolerancia: por si quedó alguna fila con `tipo` en forma tabla
      // (nombre exacto del descriptor), se buscan ambas formas. El reparo +
      // ingest normalizado ya escriben ruta; esto cubre datos residuales.
      final rows = await db.query(
        'filas_seccion',
        where: 'uuid_edan_localidad = ? AND tipo IN (?, ?)',
        whereArgs: [uuid, tipo, desc.tabla],
      );

      final rescatar = rutasSnap.contains(tipo);

      if (desc.tipo == EdanSeccionTipo.unoAN) {
        if (rows.isEmpty) {
          // Sin filas V2: se rescata del snapshot y, si tampoco ahí hay
          // datos, NO se pisa lo que ya trae el modelo (antes
          // `_asignarListaSeccion(loc, [])` vaciaba el array y la sección
          // desaparecía del preview).
          if (rescatar) _rescatarListaDesdeSnapshot(loc, desc, snap);
          continue;
        }
        if (tipo == 'impacto-poblacion') {
          // Inverso de la expansión de `_guardarFilasTx`: las filas son una
          // por grupo etario; page03 y `recalcularImpDesdeListas` consumen UN
          // wrapper con los grupos anidados y los totales sumados.
          final wrapper = await _colapsarImpactoDesdeFilas(rows);
          if (wrapper != null) loc.impactoPoblacion = [wrapper];
          continue;
        }
        final lista = <Object>[];
        for (final r in rows) {
          // Fila corrupta (datos_json ilegible): se omite esa fila, no se
          // tumba la reapertura entera del borrador.
          final dec = decodificarSeguro(r['datos_json']);
          if (dec == null) continue;
          final item = _parseSeccion(tipo, dec);
          if (item != null) lista.add(item);
        }
        _asignarListaSeccion(loc, desc.llaveJson, lista);
        // `danos-vivienda` tiene un 1:N HIJO (`viviendas`) en su propia tabla.
        // Sin hidratarlo, al reabrir un borrador page08 mostraba 0/0 y, peor,
        // re-guardar derivaba los totales solo de la lista nueva y encolaba un
        // borrado (`D`) de las viviendas del servidor.
        if (tipo == 'danos-vivienda') {
          await _hidratarViviendas(lista.cast<EdanDanoVivienda>());
        }
        // `proteccion`: el `datos_json` sale de `toApiJson`, que NUNCA llevó
        // `nombre_grupo` (el servidor rechaza campos extra); al reabrir, la
        // fila hidratada llega sin enunciado y page10 pintaba checks sin
        // texto. El nombre se surte por id desde el catálogo cacheado en
        // SQLite (`catalogo_grupo_vulnerable`, bajado por login/Perfil).
        if (tipo == 'proteccion') {
          await _surtirNombresCatalogoVulnerable(
              lista.cast<EdanGrupoVulnerable>());
          // Borradores contaminados por guardados previos al contrato pueden
          // tener más de 8 filas en `filas_seccion` (defaults legacy sin id
          // + sintéticas de padding, o duplicadas por pull). Fusionar por id
          // deja la lista de edición en exactamente 8 (más extras con datos
          // no catalogables); las ganadas por cero quedan fuera de
          // `uuidsActuales` en el próximo guardado y Gap-2 las purga.
          loc.proteccion = EdanGrupoVulnerable.completarSet8(
              lista.cast<EdanGrupoVulnerable>());
        }
      } else if (rows.isNotEmpty) {
        final dec = decodificarSeguro(rows.first['datos_json']);
        if (dec != null) {
          final item = _parseSeccion(tipo, dec);
          if (item != null) _asignarObjetoSeccion(loc, desc.llaveJson, item);
        }
      } else if (rescatar && snap != null && _extraerSeccion(loc, desc.llaveJson) == null) {
        // 1:1 sin fila V2 y sin objeto en el modelo: se toma del snapshot.
        _asignarObjetoSeccion(
            loc, desc.llaveJson, _extraerSeccion(snap, desc.llaveJson));
      }
    }
  }

  /// Copia a [loc] la lista 1:N de [desc] desde el snapshot de cabecera, solo
  /// si el modelo aún no la tiene cargada.
  void _rescatarListaDesdeSnapshot(
    EdanLocalidad loc,
    EdanSeccionDescriptor desc,
    EdanLocalidad? snap,
  ) {
    if (snap == null) return;
    final desdeSnap = _extraerSeccion(snap, desc.llaveJson);
    if (desdeSnap is! List || desdeSnap.isEmpty) return;
    final actual = _extraerSeccion(loc, desc.llaveJson);
    // El modelo ya trae datos (p. ej. del GET en línea): no se pisa.
    if (actual is List && actual.isNotEmpty) return;
    _asignarListaSeccion(loc, desc.llaveJson, desdeSnap.cast<Object>());
    // El snapshot ya anida `viviendas[]` (EdanDanoVivienda.toJson las
    // incluye), así que no hace falta ir a la tabla `viviendas`.
    if (desc.rutaV2 == 'danos-vivienda') {
      for (final v in desdeSnap.cast<EdanDanoVivienda>()) {
        if (v.viviendas.isNotEmpty) v.viviendasCargadas = true;
      }
    }
  }

  /// Carga desde la tabla `viviendas` el detalle 1:N de cada
  /// [EdanDanoVivienda] y lo marca como hidratado.
  Future<void> _hidratarViviendas(List<EdanDanoVivienda> danos) async {
    for (final dano in danos) {
      final uuid = dano.idSeccion;
      dano.viviendas = uuid == null || uuid.isEmpty
          ? <EdanVivienda>[]
          : await cargarViviendas(uuid);
      dano.viviendasCargadas = true;
    }
  }

  /// Reconstruye el wrapper de page03 (`EdanImpactoPoblacion` con grupos
  /// anidados y totales sumados) a partir de las filas POR GRUPO ETARIO de
  /// `filas_seccion`. `null` si ninguna fila decodifica.
  ///
  /// Lee el JSON crudo (la fila de un grupo trae `rango`, no `grupo_etario`)
  /// con [EdanGrupoEtario.fromJson], que ya resuelve `id_grupo_etario` y el
  /// `marcado` por totales. El `id_seccion` de cada grupo queda el del JSON
  /// (= uuid sintético del catálogo al expandir), así un re-guardar repone
  /// las mismas filas sin duplicar.
  ///
  /// Las filas de padding (defaults sin nombre) toman su enunciado del
  /// catálogo cacheado en SQLite (`catalogo_grupo_etario`); el mapa canónico
  /// [_rangoEtarioPorId] queda como último respaldo si el catálogo aún no
  /// fue descargado en este dispositivo.
  Future<EdanImpactoPoblacion?> _colapsarImpactoDesdeFilas(
      List<Map<String, Object?>> rows) async {
    Map<int, String>? nombrePorId;
    Future<Map<int, String>> catalogoNombres() async {
      if (nombrePorId != null) return nombrePorId!;
      try {
        final filas = await _db.getGruposEtariosLocal();
        nombrePorId = <int, String>{
          for (final c in filas)
            if (c['id_grupo_etario'] is num &&
                (c['nombre']?.toString().trim().isNotEmpty ?? false))
              (c['id_grupo_etario'] as num).toInt(): c['nombre'].toString(),
        };
      } catch (e) {
        debugPrint('[EdanStoreV2] catálogo grupos etarios no disponible: $e');
        nombrePorId = const {};
      }
      return nombrePorId!;
    }

    final grupos = <EdanGrupoEtario>[];
    for (final r in rows) {
      final dec = decodificarSeguro(r['datos_json']);
      if (dec == null) continue;
      // La fila de un grupo trae `rango`; el wrapper legacy, `grupo_etario`.
      if (!dec.containsKey('rango') && dec['grupo_etario'] != null) {
        dec['rango'] = dec['grupo_etario'];
      }
      final g = EdanGrupoEtario.fromJson(dec);
      if (g.rango.isEmpty && g.idGrupoEtario != null) {
        final nombres = await catalogoNombres();
        g.rango = nombres[g.idGrupoEtario!] ??
            _rangoEtarioPorId(g.idGrupoEtario!) ??
            '';
      }
      if (g.rango.isEmpty && g.idGrupoEtario == null) continue;
      grupos.add(g);
    }
    if (grupos.isEmpty) return null;
    // Contaminación de guardados previos: puede convivir el wrapper 'Total'
    // sin id con las filas reales por id. Habiendo filas con id, un 'Total'
    // vacío es basura y se descarta; si trae números se conserva como extra
    // para no esconder datos. Luego: set EXACTO de 4 (huecos en 0), igual
    // que el POST (§20.10.E).
    final hayConId = grupos.any((g) => g.idGrupoEtario != null);
    grupos.removeWhere((g) =>
        g.idGrupoEtario == null &&
        !g.tieneDatos &&
        (hayConId || g.rango.trim() == 'Total'));
    final completos = EdanGrupoEtario.completarSet4(grupos);
    var tf = 0, th = 0, td = 0;
    for (final g in completos) {
      tf += g.fallecidos;
      th += g.heridos;
      td += g.desaparecidos;
    }
    return EdanImpactoPoblacion(
      grupoEtario: 'Total',
      fallecidos: tf,
      heridos: th,
      desaparecidos: td,
      gruposEtarios: completos,
    );
  }

  /// Completa `nombreGrupo` de las filas de protección hidratadas desde el
  /// catálogo local (`catalogo_grupo_vulnerable`). No inventa nombres si el
  /// catálogo todavía no fue bajado: page10 los asienta en su post-frame con
  /// `fetchGruposVulnerablesIfNeeded`.
  Future<void> _surtirNombresCatalogoVulnerable(
      List<EdanGrupoVulnerable> grupos) async {
    final faltaAlguno = grupos.any((g) =>
        (g.nombreGrupo?.trim().isNotEmpty ?? false) == false &&
        g.idGrupoVulnerableCatalogo != null);
    if (!faltaAlguno) return;
    try {
      final catalogo = await _db.getGruposVulnerablesLocal();
      final nombrePorId = <int, String>{
        for (final c in catalogo)
          if (c['id_grupo_vulnerable'] is num &&
              (c['nombre']?.toString().trim().isNotEmpty ?? false))
            (c['id_grupo_vulnerable'] as num).toInt(): c['nombre'].toString(),
      };
      for (final g in grupos) {
        if ((g.nombreGrupo?.trim().isNotEmpty ?? false) == false &&
            g.idGrupoVulnerableCatalogo != null) {
          g.nombreGrupo = nombrePorId[g.idGrupoVulnerableCatalogo!];
        }
      }
    } catch (e) {
      debugPrint('[EdanStoreV2] catálogo grupos vulnerables no disponible: $e');
    }
  }

  /// Nombre canónico del catálogo `grupo_etario` (ids 1-4, misma semilla que
  /// los defaults de [EdanImpactoPoblacion]).
  static String? _rangoEtarioPorId(int id) {
    switch (id) {
      case 1:
        return 'Niño (a) 0-5 años';
      case 2:
        return 'Escolar de 6-18 años';
      case 3:
        return 'Adulto de 19-60 años';
      case 4:
        return 'Adulto mayor de 60 años adelante';
      default:
        return null;
    }
  }

  Object? _parseSeccion(String tipo, Map<String, dynamic> json) {
    switch (tipo) {
      case 'impacto-poblacion':
        return EdanImpactoPoblacion.fromJson(json);
      case 'salud-establecimientos':
        return EdanEstablecimientoSalud.fromJson(json);
      case 'danos-viales':
        return EdanDanoVial.fromJson(json);
      case 'danos-infra-publica':
        return EdanDanoInfraPublica.fromJson(json);
      case 'servicios-basicos':
        return EdanServicioBasicoDetalle.fromJson(json);
      case 'unidades-educativas':
        return EdanDanoUnidadEducativa.fromJson(json);
      case 'danos-vivienda':
        return EdanDanoVivienda.fromJson(json);
      case 'danos-agricultura':
        return EdanDanoAgricultura.fromJson(json);
      case 'danos-pecuarios':
        return EdanDanoPecuario.fromJson(json);
      case 'infra-productiva':
        return EdanInfraProductiva.fromJson(json);
      case 'proteccion':
        return EdanGrupoVulnerable.fromJson(json);
      case 'primera-respuesta':
        return EdanNecesidadPrimeraRespuesta.fromJson(json);
      case 'necesidad-salud':
        return EdanNecesidadSalud.fromJson(json);
      case 'necesidad-humanitaria':
        return EdanNecesidadHumanitaria.fromJson(json);
      default:
        return null;
    }
  }

  void _asignarListaSeccion(EdanLocalidad loc, String llaveJson, List<Object> lista) {
    switch (llaveJson) {
      case 'impacto_poblacion':
        loc.impactoPoblacion = lista.cast<EdanImpactoPoblacion>();
        break;
      case 'establecimientos_salud':
        loc.establecimientosSalud = lista.cast<EdanEstablecimientoSalud>();
        break;
      case 'danos_viales':
        loc.danosViales = lista.cast<EdanDanoVial>();
        break;
      case 'danos_infra_publica':
        loc.danosInfraPublica = lista.cast<EdanDanoInfraPublica>();
        break;
      case 'servicios_basicos':
        loc.serviciosBasicos = lista.cast<EdanServicioBasicoDetalle>();
        break;
      case 'unidades_educativas':
        loc.unidadesEducativas = lista.cast<EdanDanoUnidadEducativa>();
        break;
      case 'danos_vivienda':
        loc.danosVivienda = lista.cast<EdanDanoVivienda>();
        break;
      case 'danos_agricultura':
        loc.danosAgricultura = lista.cast<EdanDanoAgricultura>();
        break;
      case 'danos_pecuarios':
        loc.danosPecuarios = lista.cast<EdanDanoPecuario>();
        break;
      case 'infra_productiva':
        loc.infraProductiva = lista.cast<EdanInfraProductiva>();
        break;
      case 'proteccion':
        loc.proteccion = lista.cast<EdanGrupoVulnerable>();
        break;
    }
  }

  void _asignarObjetoSeccion(EdanLocalidad loc, String llaveJson, Object? item) {
    switch (llaveJson) {
      case 'necesidad_primera_respuesta':
        if (item is EdanNecesidadPrimeraRespuesta) {
          loc.necesidadPrimeraRespuesta = item;
        }
        break;
      case 'necesidad_salud':
        if (item is EdanNecesidadSalud) {
          loc.necesidadSalud = item;
        }
        break;
      case 'necesidad_humanitaria':
        if (item is EdanNecesidadHumanitaria) {
          loc.necesidadHumanitaria = item;
        }
        break;
    }
  }

  @override
  /// Elimina una fila de `filas_seccion` propagando la baja al servidor.
  ///
  /// Antes solo borraba la copia local: la fila reaparecía al recargar y, si
  /// el usuario guardaba de nuevo, el Gap 2 la volvía a reencolar como alta.
  /// Ahora replica la semántica de Gap 2 de [guardarFilas]: si la fila estaba
  /// sincronizada (confirmada o con `remote_id`) se encola su `D` para que
  /// el motor la borre en el servidor; si nunca se sincronizó solo se purga
  /// localmente, incluyendo su upsert pendiente.
  @override
  Future<void> eliminarFila(String tipo, String uuidRegistro) async {
    final db = await _db.database;
    final previa = await db.query(
      'filas_seccion',
      columns: ['estado_sync', 'remote_id', 'uuid_edan_localidad'],
      where: 'tipo = ? AND uuid_registro = ?',
      whereArgs: [tipo, uuidRegistro],
      limit: 1,
    );
    final sincronizada = previa.isNotEmpty &&
        (previa.first['estado_sync'] == 'confirmado' ||
            previa.first['remote_id'] != null);
    final uuidLoc = previa.isEmpty
        ? null
        : previa.first['uuid_edan_localidad'] as String?;

    await db.delete(
      'filas_seccion',
      where: 'tipo = ? AND uuid_registro = ?',
      whereArgs: [tipo, uuidRegistro],
    );
    // Las fotos de la fila no deben quedar huérfanas en cola (badge
    // atascado + "sin cambios" eternos): se purgan con la fila.
    await _purgarFotosDeFila(db, uuidRegistro);
    // Purga el upsert pendiente para que no se suba un registro ya borrado.
    await db.delete(
      'cola_sincronizacion',
      where: 'tabla = ? AND uuid_registro = ?',
      whereArgs: ['filas_seccion', uuidRegistro],
    );
    if (sincronizada) {
      await encolar(
        tabla: 'filas_seccion',
        uuidRegistro: uuidRegistro,
        accion: 'D',
        // Coordenadas para el DELETE sin la fila local (si no, el motor no
        // puede llamar al servidor y el borrado jamás viajaría).
        payload: uuidLoc == null
            ? null
            : {'uuid_edan_localidad': uuidLoc, 'tipo': tipo},
      );
    }
    // El borrado cambia el documento: el dirty se deriva de la firma (el `D`
    // viaja por su cola aunque el doc quede limpio).
    if (uuidLoc != null && uuidLoc.isNotEmpty) {
      await recargarFirma(uuidLoc, sincronizada: false);
    }
    _notifyPendientes();
  }

  /// Purga las fotos de una fila eliminada: saca su subida de la cola y,
  /// si ya estaban subidas, marca borrado lógico para propagarlo (misma
  /// semántica que [borrarFoto]); si no, elimina el registro. El archivo
  /// local se borra siempre. Nunca lanza.
  Future<void> _purgarFotosDeFila(
      DatabaseExecutor db, String uuidRegistro) async {
    try {
      final fotos = await db.query(
        'fotografias',
        columns: ['uuid_fotografia', 'ruta_local', 'ruta_servidor'],
        where: 'uuid_registro = ? AND borrado_logico = 0',
        whereArgs: [uuidRegistro],
      );
      for (final foto in fotos) {
        final uf = foto['uuid_fotografia'] as String?;
        if (uf == null || uf.isEmpty) continue;
        await db.delete('cola_fotos',
            where: 'uuid_fotografia = ?', whereArgs: [uf]);
        final rutaServidor = foto['ruta_servidor'] as String?;
        if (rutaServidor != null && rutaServidor.isNotEmpty) {
          await db.update(
            'fotografias',
            {
              'borrado_logico': 1,
              'fecha_modificacion': DateTime.now().toIso8601String(),
            },
            where: 'uuid_fotografia = ?',
            whereArgs: [uf],
          );
        } else {
          await db.delete('fotografias',
              where: 'uuid_fotografia = ?', whereArgs: [uf]);
        }
        final rutaLocal = foto['ruta_local'] as String?;
        if (rutaLocal != null && rutaLocal.isNotEmpty) {
          try {
            final archivo = File(rutaLocal);
            if (await archivo.exists()) await archivo.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  @override
  Future<void> purgarSecciones(
      String uuidEdanLocalidad, List<String> rutas) async {
    final db = await _db.database;
    for (final ruta in rutas) {
      final desc = EdanSeccionesRegistry.porRuta(ruta);
      if (desc == null) continue;
      final filas = await db.query(
        'filas_seccion',
        columns: ['uuid_registro', 'estado_sync', 'remote_id'],
        where: 'uuid_edan_localidad = ? AND tipo IN (?, ?)',
        whereArgs: [uuidEdanLocalidad, ruta, desc.tabla],
      );
      for (final f in filas) {
        final u = f['uuid_registro'] as String?;
        if (u == null || u.isEmpty) continue;
        final sincronizada = f['estado_sync'] == 'confirmado' ||
            f['remote_id'] != null;
        // Hijas `viviendas` del detalle 1:N (mismo criterio de bajas que
        // `_guardarViviendasTx`: se encola su `D`). La señal es el padre
        // confirmado (el doc viaja anidado): `viviendas` no tiene `remote_id`
        // en el esquema limpio y su `estado_sync` no lo mueve el pull.
        if (ruta == 'danos-vivienda') {
          final hijas = await db.query(
            'viviendas',
            columns: ['uuid_registro'],
            where: 'uuid_dano_vivienda = ?',
            whereArgs: [u],
          );
          // Padre confirmado ⇒ el servidor tiene el doc con sus hijas
          // conocidas al pushear. Una hija posterior no pusheada genera un
          // DELETE de más que el servidor responde 404 y se purga: sin
          // pérdida, converge igual.
          final hijaSincronizada = f['estado_sync'] == 'confirmado';
          for (final h in hijas) {
            final uh = h['uuid_registro'] as String?;
            if (uh == null || uh.isEmpty) continue;
            await _purgarFotosDeFila(db, uh);
            await db.delete('viviendas',
                where: 'uuid_registro = ?', whereArgs: [uh]);
            await db.delete('cola_sincronizacion',
                where: "tabla = 'vivienda' AND uuid_registro = ?",
                whereArgs: [uh]);
            if (hijaSincronizada) {
              await encolar(
                tabla: 'vivienda',
                uuidRegistro: uh,
                accion: 'D',
                payload: {
                  'uuid_edan_localidad': uuidEdanLocalidad,
                  'uuid_dano_vivienda': u,
                },
              );
            }
          }
        }
        // Fotos de la fila (misma semántica que al borrar un ítem).
        await _purgarFotosDeFila(db, u);
        await db.delete(
          'filas_seccion',
          where: 'uuid_registro = ?',
          whereArgs: [u],
        );
        // Purga el upsert pendiente para que no se suba un registro borrado.
        await db.delete(
          'cola_sincronizacion',
          where: "tabla = 'filas_seccion' AND uuid_registro = ?",
          whereArgs: [u],
        );
        if (sincronizada) {
          await encolar(
            tabla: 'filas_seccion',
            uuidRegistro: u,
            accion: 'D',
            payload: {
              'uuid_edan_localidad': uuidEdanLocalidad,
              'tipo': ruta,
            },
          );
        }
      }
    }
    // La purga cambia el documento: dirty derivado de la firma.
    await recargarFirma(uuidEdanLocalidad, sincronizada: false);
    _notifyPendientes();
  }

  // ── Secciones activas (tabla auxiliar v31) ──
  //
  // La fuente de verdad es `secciones_grupos_local`, que registra POR QUÉ una
  // sección está activa: 'usuario' (checkbox de page01) o 'datos' (tiene filas
  // reales). `formularios.secciones_activas_json` queda como vista derivada
  // para no romper el sync engine, pero ya no decide nada.

  /// Rutas v2 que tienen al menos una fila persistida. Es la "verdad en los
  /// datos": una sección con contenido debe seguir visible aunque el usuario
  /// haya desmarcado su grupo.
  ///
  /// Delega en [EdanSeccionesFuente] para que sea EXACTAMENTE el mismo
  /// conjunto que decide el payload `/completo` y sus 14 flags `imp_*`: así
  /// badge, vista previa, wizard y JSON de depuración no pueden divergir.
  @override
  Future<List<String>> rutasConDatos(String uuidEdanLocalidad) =>
      EdanSeccionesFuente(dbHelper: _db).rutasConDatos(uuidEdanLocalidad);

  @override
  Future<void> activarSecciones(
    String uuidEdanLocalidad,
    List<String> tipos, {
    String origen = 'usuario',
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await _activarSeccionesTx(txn, uuidEdanLocalidad, tipos, origen: origen);
    });
    _notifyPendientes();
  }

  /// Núcleo transaccional de [activarSecciones] sobre [ex].
  Future<void> _activarSeccionesTx(
    DatabaseExecutor ex,
    String uuidEdanLocalidad,
    List<String> tipos, {
    String origen = 'usuario',
  }) async {
    for (final tipo in tipos) {
      final grupo = EdanSeccionesRegistry.grupoDeRuta(tipo);
      if (grupo == null) continue; // ruta fuera de la matriz: se ignora
      await ex.insert(
        'secciones_grupos_local',
        {
          'uuid_edan_localidad': uuidEdanLocalidad,
          'seccion': tipo,
          'grupo': grupo,
          'origen': origen,
          'activa': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await _sincronizarVistaSeccionesActivasTx(ex, uuidEdanLocalidad);
  }

  @override
  Future<void> desactivarSecciones(
    String uuidEdanLocalidad,
    List<String> tipos,
  ) async {
    if (tipos.isEmpty) return;
    final db = await _db.database;
    // Solo se apaga la activación de ORIGEN 'usuario'. Una sección que quedó
    // activa por tener datos no se puede ocultar desde los checkboxes: la
    // verdad está en los datos.
    await db.update(
      'secciones_grupos_local',
      {'activa': 0},
      where: 'uuid_edan_localidad = ? AND seccion IN '
          '(${List.filled(tipos.length, '?').join(',')})',
      whereArgs: [uuidEdanLocalidad, ...tipos],
    );
    await _sincronizarVistaSeccionesActivas(uuidEdanLocalidad);
  }

  /// Secciones activas = lo que el usuario tildó **∪** lo que tiene datos.
  @override
  Future<List<String>> leerSeccionesActivas(String uuidEdanLocalidad) =>
      _resolverSeccionesActivas(uuidEdanLocalidad);

  Future<List<String>> _resolverSeccionesActivas(String uuid) async {
    final db = await _db.database;
    return _resolverSeccionesActivasTx(db, uuid);
  }

  /// Núcleo de lectura de [_resolverSeccionesActivas] sobre [ex] (válido
  /// dentro de una transacción: solo lee).
  Future<List<String>> _resolverSeccionesActivasTx(
      DatabaseExecutor ex, String uuid) async {
    final rows = await ex.query(
      'secciones_grupos_local',
      columns: ['seccion'],
      where: 'uuid_edan_localidad = ? AND activa = 1',
      whereArgs: [uuid],
    );
    final activas = rows.map((r) => r['seccion'] as String).toSet();
    activas.addAll(await EdanSeccionesFuente(dbHelper: _db)
        .rutasConDatos(uuid, executor: ex));
    final conocidas =
        EdanSeccionesRegistry.secciones.map((s) => s.rutaV2).toSet();
    return activas.where(conocidas.contains).toList();
  }

  /// Grupos (checkboxes de page01) tildados para una localidad.
  ///
  /// Preferencia: la **selección explícita** persistida en `grupos_local` (v32)
  /// cuando existe; si no, la derivación inversa de la matriz a partir de las
  /// secciones realmente activas (caminos antiguos y backfill).
  Future<Set<String>> gruposActivos(String uuidEdanLocalidad) async {
    final explicita = await leerSeleccionGrupos(uuidEdanLocalidad);
    if (explicita.isNotEmpty) return explicita;
    final activas = await _resolverSeccionesActivas(uuidEdanLocalidad);
    return EdanSeccionesRegistry.gruposDesdeActivas(activas);
  }

  // ── Grupos (tabla auxiliar v32) ──
  //
  // `grupos_local` guarda DOS verdades distintas (PLAN_APP_EDAN_OFFLINE_V2 §4.2):
  //   · `seleccion_usuario` — lo que tildó el usuario en page01. Gobierna qué
  //     secciones se muestran al crear/editar.
  //   · `grup_servidor`     — caché del nodo `grupos` del GET /completo (y del
  //     pull). Es el OR de las secciones miembro que calcula el servidor; solo
  //     lectura.

  /// Persiste la selección de grupos del usuario. Se deriva de las secciones
  /// activas para que quede siempre consistente con la matriz.
  @override
  Future<void> guardarSeleccionGrupos(
    String uuidEdanLocalidad,
    Set<String> grupos,
  ) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await _guardarSeleccionGruposTx(txn, uuidEdanLocalidad, grupos);
    });
  }

  /// Núcleo transaccional de [guardarSeleccionGrupos] sobre [ex].
  Future<void> _guardarSeleccionGruposTx(
    DatabaseExecutor ex,
    String uuidEdanLocalidad,
    Set<String> grupos,
  ) async {
    final conocidos = EdanSeccionesRegistry.grupos.toSet();
    await ex.delete(
      'grupos_local',
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuidEdanLocalidad],
    );
    for (final g in conocidos) {
      await ex.insert(
        'grupos_local',
        {
          'uuid_edan_localidad': uuidEdanLocalidad,
          'grupo': g,
          'seleccion_usuario': grupos.contains(g) ? 1 : 0,
          'grup_servidor': null,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Grupos que el usuario tildó en page01 (origen: `seleccion_usuario`).
  @override
  Future<Set<String>> leerSeleccionGrupos(String uuidEdanLocalidad) async {
    final db = await _db.database;
    final rows = await db.query(
      'grupos_local',
      columns: ['grupo'],
      where: 'uuid_edan_localidad = ? AND seleccion_usuario = 1',
      whereArgs: [uuidEdanLocalidad],
    );
    return rows.map((r) => r['grupo'] as String).toSet();
  }

  /// Guarda la caché del nodo `grupos` que devolvió el servidor (el OR de las
  /// secciones miembro). **No toca `seleccion_usuario`**: esa columna es local
  /// y el servidor no la conoce. Se hace `INSERT OR IGNORE` + `UPDATE` de la
  /// sola columna del servidor porque `ConflictAlgorithm.replace` borraría la
  /// fila entera y perdería lo que tildó el usuario.
  @override
  Future<void> guardarGruposServidor(
    String uuidEdanLocalidad,
    Map<String, bool> grupos,
  ) async {
    if (grupos.isEmpty) return;
    final db = await _db.database;
    for (final e in grupos.entries) {
      await db.insert(
        'grupos_local',
        {
          'uuid_edan_localidad': uuidEdanLocalidad,
          'grupo': e.key,
          'seleccion_usuario': 0,
          'grup_servidor': null,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await db.update(
        'grupos_local',
        {'grup_servidor': e.value ? 1 : 0},
        where: 'uuid_edan_localidad = ? AND grupo = ?',
        whereArgs: [uuidEdanLocalidad, e.key],
      );
    }
  }

  /// Caché del nodo `grupos` del servidor (vacía si todavía no se leyó).
  @override
  Future<Map<String, bool>> leerGruposServidor(String uuidEdanLocalidad) async {
    final db = await _db.database;
    final rows = await db.query(
      'grupos_local',
      columns: ['grupo', 'grup_servidor'],
      where: 'uuid_edan_localidad = ? AND grup_servidor IS NOT NULL',
      whereArgs: [uuidEdanLocalidad],
    );
    return {
      for (final r in rows)
        r['grupo'] as String: (r['grup_servidor'] as int?) == 1,
    };
  }

  /// Pinta la caché del nodo `grupos` sobre el modelo (OR con lo que ya trae).
  ///
  /// Regla de negocio: si el servidor dice `grup_agropecuario=true`, el badge
  /// y la vista deben mostrarlo aunque el snapshot local no traiga las filas
  /// (primera descarga resumida, caso Urubo). Sin esto, badges y preview
  /// ocultaban secciones con datos en el servidor.
  Future<void> aplicarGruposServidorAlModelo(EdanLocalidad loc) async {
    final uuid = loc.uuidEdanLocalidad ?? loc.idLocal;
    if (uuid == null || uuid.isEmpty) return;
    final cache = await leerGruposServidor(uuid);
    if (cache.isEmpty) return;
    if (cache['grupPoblacion'] == true) loc.grupPoblacion = true;
    if (cache['grupSalud'] == true) loc.grupSalud = true;
    if (cache['grupInfraestructura'] == true) loc.grupInfraestructura = true;
    if (cache['grupServicios'] == true) loc.grupServicios = true;
    if (cache['grupEducacion'] == true) loc.grupEducacion = true;
    if (cache['grupVivienda'] == true) loc.grupVivienda = true;
    if (cache['grupAgropecuario'] == true) loc.grupAgropecuario = true;
    if (cache['grupProteccion'] == true) loc.grupProteccion = true;
    if (cache['grupNecesidades'] == true) loc.grupNecesidades = true;
  }

  /// Backfill UNA VEZ de `grup_*` para filas legacy sin información de
  /// grupos: si NO hay ninguna fila en `grupos_local` para el uuid (ni
  /// selección de usuario ni caché de servidor) pero SÍ hay filas de
  /// sección, se encienden los grupos miembro. Sin esto, al dejar de
  /// re-derivar grupos en cada lectura, los borradores viejos quedarían con
  /// badges apagados aunque tengan datos. Solo enciende columnas en 0,
  /// nunca apaga; idempotente (segunda corrida: 0 reparadas).
  Future<int> repararGruposLegacy() async {
    final db = await _db.database;
    final forms = await db.query('formularios');
    var tocadas = 0;
    for (final f in forms) {
      final uuid = f['uuid_edan_localidad'] as String?;
      if (uuid == null || uuid.isEmpty) continue;
      final info = await db.query(
        'grupos_local',
        columns: ['grupo'],
        where: 'uuid_edan_localidad = ?',
        whereArgs: [uuid],
        limit: 1,
      );
      if (info.isNotEmpty) continue;
      final filas = await db.query(
        'filas_seccion',
        columns: ['tipo'],
        where: 'uuid_edan_localidad = ?',
        whereArgs: [uuid],
      );
      if (filas.isEmpty) continue;
      final rutas = <String>{};
      for (final r in filas) {
        final t = r['tipo'] as String?;
        if (t == null || t.isEmpty) continue;
        rutas.add(EdanSeccionesRegistry.rutaDesdeTabla(t));
      }
      final grupos = EdanSeccionesRegistry.gruposDesdeActivas(rutas);
      final cols = <String, Object?>{};
      for (final g in grupos) {
        final col = EdanSeccionesRegistry.columnaDeGrupo(g);
        if ((f[col] as num?)?.toInt() != 1) cols[col] = 1;
      }
      if (cols.isEmpty) continue;
      await db.update(
        'formularios',
        cols,
        where: 'uuid_edan_localidad = ?',
        whereArgs: [uuid],
      );
      tocadas++;
    }
    return tocadas;
  }
  ///
  /// Regla "grup manda": los `grup_*` de la COLUMNA (page01 / planas del
  /// servidor) NO se tocan aquí — re-derivarlos de filas re-encendería un
  /// grupo destildado y pelearía con la selección del usuario. Solo se
  /// derivan los `imp_*` del modelo devuelto (la UI los combina con los
  /// `grup` de columnas). Idempotente y sin escrituras.
  /// Retorna el modelo con los flags derivados (útil para la UI tras el pull).
  Future<EdanLocalidad?> derivarFlagsDesdeFilas(String uuid) async {
    final loc = await cargarFormulario(uuid);
    if (loc == null) return null;
    final db = await _db.database;
    final rows = await db.query('filas_seccion',
        columns: ['tipo'], where: 'uuid_edan_localidad = ?', whereArgs: [uuid]);
    final tipos = {
      for (final r in rows)
        if (r['tipo'] is String && (r['tipo'] as String).isNotEmpty)
          EdanSeccionesRegistry.rutaDesdeTabla(r['tipo'] as String),
    };
    // Reset todos a false, luego encender los que tienen fila.
    for (final desc in EdanSeccionesRegistry.secciones) {
      _setImp(loc, 'imp_${desc.rutaV2.replaceAll('-', '_')}', false);
    }
    for (final t in tipos) {
      final desc = EdanSeccionesRegistry.porRuta(t);
      if (desc == null) continue;
      _setImp(loc, 'imp_${desc.rutaV2.replaceAll('-', '_')}', true);
    }
    // NO recalcularGruposDesdeImpacto() ni UPDATE de `grup_*`: los grupos
    // los gobiernan page01 (creación) y las planas del servidor (descarga).
    // (Antes se reescribían aquí en cada lectura del listado.)
    return loc;
  }

  static void _setImp(EdanLocalidad loc, String impKey, bool value) {
    switch (impKey) {
      case 'imp_impacto_poblacion':
        loc.impImpactoPoblacion = value;
        break;
      case 'imp_primera_respuesta':
        loc.impPrimeraRespuesta = value;
        break;
      case 'imp_salud_establecimientos':
        loc.impSaludEstablecimientos = value;
        break;
      case 'imp_necesidad_salud':
        loc.impNecesidadSalud = value;
        break;
      case 'imp_danos_viales':
        loc.impDanosViales = value;
        break;
      case 'imp_danos_infra_publica':
        loc.impDanosInfraPublica = value;
        break;
      case 'imp_servicios_basicos':
        loc.impServiciosBasicos = value;
        break;
      case 'imp_unidades_educativas':
        loc.impUnidadesEducativas = value;
        break;
      case 'imp_danos_vivienda':
        loc.impDanosVivienda = value;
        break;
      case 'imp_danos_agricultura':
        loc.impDanosAgricultura = value;
        break;
      case 'imp_danos_pecuarios':
        loc.impDanosPecuarios = value;
        break;
      case 'imp_infra_productiva':
        loc.impInfraProductiva = value;
        break;
      case 'imp_proteccion':
        loc.impProteccion = value;
        break;
      case 'imp_necesidad_humanitaria':
        loc.impNecesidadHumanitaria = value;
        break;
      default:
        break;
    }
  }

  /// `secciones_activas_json` es VISTA DERIVADA de la auxiliar. Se recalcula
  /// aquí para que el sync engine (que la sigue leyendo) vea siempre el
  /// mismo conjunto que decide la UI.
  Future<void> _sincronizarVistaSeccionesActivas(String uuid) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await _sincronizarVistaSeccionesActivasTx(txn, uuid);
    });
  }

  /// Núcleo transaccional de [_sincronizarVistaSeccionesActivas] sobre [ex].
  Future<void> _sincronizarVistaSeccionesActivasTx(
      DatabaseExecutor ex, String uuid) async {
    final activas = await _resolverSeccionesActivasTx(ex, uuid);
    await ex.update(
      'formularios',
      {'secciones_activas_json': jsonEncode(activas)},
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuid],
    );
    // Espejo en `localidad_secciones_activas` (tabla legacy): el listado de
    // la pestaña Reportes (`resp_dashboard_tab.dart`) y la vista previa leen
    // de ahí vía
    // `EdanLocalidadesEnvioV2Service.aplicarFlagsDesdeSeccionesActivas`. Sin
    // este espejo, los badges del listado no reflejan lo marcado en page01.
    // (Se retira en Etapa 5, cuando el listado lea `formularios`.)
    await ex.delete(
      'localidad_secciones_activas',
      where: 'id_local = ?',
      whereArgs: [uuid],
    );
    for (final s in activas) {
      await ex.insert(
        'localidad_secciones_activas',
        {'id_local': uuid, 'seccion': s, 'activa': 1},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Registra + encola las fotos que quedaron solo en memoria
  /// (`item.fotos` sin `uuidFotografia`), p. ej. del paso final del asistente
  /// IA. La ruta de sección da el `tipo_entidad` canónico; el uuid de la fila
  /// ya existe porque `guardarTodo` corrió antes (mismo `idSeccion`).
  Future<void> registrarFotosEnMemoria(EdanLocalidad loc) async {
    for (final desc in EdanSeccionesRegistry.secciones) {
      final datos = _extraerSeccion(loc, desc.llaveJson);
      if (datos == null) continue;
      final items = desc.tipo == EdanSeccionTipo.unoAN
          ? (datos as List<dynamic>).whereType<EdanFotoHolder>()
          : [datos].whereType<EdanFotoHolder>();
      final tipo =
          EdanSeccionesRegistry.tipoEntidadDeRuta(desc.rutaV2);
      if (tipo == null) continue;
      for (final item in items) {
        final pendientes =
            item.fotos.where((f) => f.uuidFotografia == null).toList();
        if (pendientes.isEmpty) continue;
        var uuid = item.idSeccion;
        if (uuid == null || uuid.isEmpty) {
          uuid = EdanUuidHelper.generarUuidRegistro();
          item.idSeccion = uuid;
        }
        for (final foto in pendientes) {
          try {
            await registrarFoto(foto, tipo, uuid);
            await encolarFoto(foto);
          } catch (_) {
            // Una foto sin archivo o sin dueña no bloquea el resto.
          }
        }
      }
    }
  }

  /// Migración única v1.2.0 → V2 (diseño limpio, sin convivencia).
  ///
  /// Por cada fila de `localidades_offline` SIN contraparte en `formularios`:
  /// parsea el `datos_json` legacy, normaliza identidad y secciones, y persiste
  /// con [guardarTodo] + [registrarFotosEnMemoria]. Idempotente (las filas ya
  /// migradas se omiten por `uuid == id_local`). Devuelve cuántas migró.
  ///
  /// Reglas de normalización (compat v1.2.0):
  ///  * `id_local` uuid válido → se reutiliza como `uuid_edan_localidad`
  ///    (dedup con el listado); si no es uuid → uuid fresco y se ELIMINA la
  ///    fila legacy para no duplicar (v1.2.0 siempre generó uuid v4, así que
  ///    esto solo cubre datos prehistóricos).
  ///  * `id_seccion` con prefijo legacy (`po_`, `dv_`, …) → `null` (al guardar
  ///    nacen `uuid_registro` frescos; mandar el prefijo daría 422). Los uuid
  ///    válidos se conservan.
  ///  * `danos_vivienda` N filas → 1 padre (primera: comunidad/necesidades/
  ///    foto) + resto volcado a `observaciones` (el server acepta máx 1).
  ///  * Secciones a persistir = las que `recalcularFlagsImpacto()` marca con
  ///    contenido (objetos 1:1 por defecto vacíos no generan filas).
  Future<int> migrarLegadoV1({int? usuarioId}) async {
    final db = await _db.database;
    final forms = await db.query('formularios',
        columns: ['uuid_edan_localidad']);
    final vistos =
        forms.map((f) => f['uuid_edan_localidad'] as String?).toSet();
    final maps = await db.query(
      'localidades_offline',
      where: 'pendiente_eliminacion = 0',
    );
    var migrados = 0;
    for (final m in maps) {
      final idLocal = m['id_local'] as String?;
      if (idLocal == null || idLocal.isEmpty || vistos.contains(idLocal)) {
        continue;
      }
      EdanLocalidad loc;
      try {
        final datos = jsonDecode(m['datos_json'] as String);
        loc = EdanLocalidad.fromJson(Map<String, dynamic>.from(datos as Map));
      } catch (_) {
        continue; // snapshot corrupto: no tumba la migración
      }
      final uuidValido = EdanUuidHelper.esUuidValido(idLocal);
      loc
        ..idLocal = uuidValido ? idLocal : null
        ..uuidEdanLocalidad = uuidValido ? idLocal : null
        ..idUsuario = loc.idUsuario ?? usuarioId;
      _normalizarIdsLegado(loc);
      _colapsarDanosViviendaLegado(loc);
      loc.recalcularFlagsImpacto();
      final tipos = _rutasConContenido(loc);
      try {
        await guardarTodo(
          loc,
          usuarioId: loc.idUsuario ?? usuarioId ?? 0,
          seccionesActivas: EdanSeccionesRegistry.gruposDesdeActivas(tipos)
              .expand(EdanSeccionesRegistry.rutasDeGrupo)
              .toList(),
          tipos: tipos,
        );
        await registrarFotosEnMemoria(loc);
      } catch (_) {
        continue;
      }
      if (!uuidValido) {
        // Sin uuid reutilizable la fila legacy quedaría duplicada en el
        // listado unificado: se elimina (ya vive en V2 con uuid fresco).
        await db.delete('localidades_offline',
            where: 'id_local = ?', whereArgs: [idLocal]);
      }
      migrados++;
    }
    return migrados;
  }

  /// Limpia `id_seccion` no-uuid (prefijos legacy) en todas las secciones y
  /// viviendas para que al persistir nazcan `uuid_registro` frescos.
  void _normalizarIdsLegado(EdanLocalidad loc) {
    void fix(dynamic item) {
      try {
        final actual = (item as dynamic).idSeccion as String?;
        if (actual != null &&
            actual.isNotEmpty &&
            !EdanUuidHelper.esUuidValido(actual)) {
          (item as dynamic).idSeccion = null;
        }
      } catch (_) {}
    }

    for (final desc in EdanSeccionesRegistry.secciones) {
      final datos = _extraerSeccion(loc, desc.llaveJson);
      if (datos == null) continue;
      if (datos is List) {
        for (final item in datos) {
          fix(item);
          if (item is EdanDanoVivienda) {
            for (final v in item.viviendas) {
              if (v.uuidRegistro != null &&
                  v.uuidRegistro!.isNotEmpty &&
                  !EdanUuidHelper.esUuidValido(v.uuidRegistro)) {
                v.uuidRegistro = null;
              }
            }
          }
        }
      } else {
        fix(datos);
      }
    }
  }

  /// v1.2.0 guardaba N filas de `danos_vivienda` (una por comunidad); el
  /// contrato nuevo acepta máx 1 (más → 400). Colapso sin pérdida silenciosa:
  /// la primera es el padre y el resto se vuelca a `observaciones`.
  void _colapsarDanosViviendaLegado(EdanLocalidad loc) {
    final lista = loc.danosVivienda;
    if (lista.length <= 1) return;
    final padre = lista.first;
    final resto = lista
        .sublist(1)
        .map((d) =>
            '• ${d.comunidad} (T:${d.danoTotal}/P:${d.danoParcial})'
            '${d.observaciones.isNotEmpty ? ' — ${d.observaciones}' : ''}')
        .join('\n');
    padre.observaciones = [
      if (padre.observaciones.isNotEmpty) padre.observaciones,
      'Comunidades migradas de v1.2.0:\n$resto',
    ].join('\n');
    loc.danosVivienda = [padre];
  }

  /// Rutas con contenido real según los flags recalculados del modelo.
  static List<String> _rutasConContenido(EdanLocalidad loc) {
    const rutas = [
      'impacto-poblacion',
      'primera-respuesta',
      'salud-establecimientos',
      'necesidad-salud',
      'danos-viales',
      'danos-infra-publica',
      'servicios-basicos',
      'unidades-educativas',
      'danos-vivienda',
      'danos-agricultura',
      'danos-pecuarios',
      'infra-productiva',
      'proteccion',
      'necesidad-humanitaria',
    ];
    return [for (final r in rutas) if (_flagDeRuta(loc, r)) r];
  }

  static bool _flagDeRuta(EdanLocalidad loc, String ruta) {
    switch (ruta) {
      case 'impacto-poblacion':
        return loc.impImpactoPoblacion;
      case 'primera-respuesta':
        return loc.impPrimeraRespuesta;
      case 'salud-establecimientos':
        return loc.impSaludEstablecimientos;
      case 'necesidad-salud':
        return loc.impNecesidadSalud;
      case 'danos-viales':
        return loc.impDanosViales;
      case 'danos-infra-publica':
        return loc.impDanosInfraPublica;
      case 'servicios-basicos':
        return loc.impServiciosBasicos;
      case 'unidades-educativas':
        return loc.impUnidadesEducativas;
      case 'danos-vivienda':
        return loc.impDanosVivienda;
      case 'danos-agricultura':
        return loc.impDanosAgricultura;
      case 'danos-pecuarios':
        return loc.impDanosPecuarios;
      case 'infra-productiva':
        return loc.impInfraProductiva;
      case 'proteccion':
        return loc.impProteccion;
      case 'necesidad-humanitaria':
        return loc.impNecesidadHumanitaria;
      default:
        return false;
    }
  }

  // ── Viviendas ──

  @override
  Future<List<EdanVivienda>> cargarViviendas(String uuidDanoVivienda) async {
    final db = await _db.database;
    final rows = await db.query(
      'viviendas',
      where: 'uuid_dano_vivienda = ?',
      whereArgs: [uuidDanoVivienda],
      orderBy: 'fecha_modificacion_local DESC',
    );
    return rows.map(EdanVivienda.fromJson).toList();
  }

  @override
  Future<void> guardarVivienda(EdanVivienda vivienda) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await _guardarViviendaTx(txn, vivienda);
    });
    _notifyPendientes();
  }

  /// `true` si el flag `imp_*` de una ruta está encendido en el modelo
  /// (así el padding solo corre cuando la sección cuenta).
  static bool _flagImpDeRuta(String rutaV2, EdanLocalidad loc) {
    switch (rutaV2) {
      case 'impacto-poblacion':
        return loc.impImpactoPoblacion;
      case 'proteccion':
        return loc.impProteccion;
    }
    return false;
  }

  /// Padding de catálogo al guardar en SQLite: si [flag], completa el SET
  /// EXACTO de [ids] (faltantes con [defaults]) usando `uuidFilaSintetica`
  /// (determinista: mismo uuid que el padding del push → el `REPLACE` no
  /// duplica). Devuelve los uuids del set completo (para que la reconciliación
  /// de bajas no los borre: no están en el modelo). Nunca lanza.
  Future<Set<String>> _padCatalogoTx(
    DatabaseExecutor ex,
    String uuidEdanLocalidad, {
    required String tipo,
    required bool flag,
    required String idCampo,
    required List<int> ids,
    required String rutaTipo,
    required Map<String, dynamic> defaults,
    // Ids cuyo slot ya fue cubierto en este guardado por una fila del modelo
    // CON datos (fusión `completarSet8`/expansión por id al hidratar). Sus
    // filas viejas en BD (p. ej. la sintética en ceros del mismo id, o legacy
    // duplicada) NO se protegen: Gap-2 las purga y el slot queda único.
    Set<int> claimedIds = const {},
  }) async {
    if (!flag) return {};
    final out = <String>{};
    try {
      final filas = await ex.query(
        'filas_seccion',
        columns: ['uuid_registro', 'datos_json'],
        where: 'uuid_edan_localidad = ? AND tipo = ?',
        whereArgs: [uuidEdanLocalidad, tipo],
      );
      final porId = <int, Map<String, dynamic>>{};
      for (final f in filas) {
        final dec = decodificarSeguro(f['datos_json']);
        if (dec == null) continue;
        final id = _intDeFirma(dec[idCampo]);
        if (id == null || !ids.contains(id) || porId.containsKey(id)) continue;
        porId[id] = dec;
        final u = f['uuid_registro'] as String?;
        // Un id reclamado por una fila con datos no se blinda: su fila
        // perdedora debe ser purgada por Gap-2.
        if (u != null && !claimedIds.contains(id)) out.add(u);
      }
      final now = DateTime.now().toIso8601String();
      for (final id in ids) {
        if (porId.containsKey(id) || claimedIds.contains(id)) continue;
        final datos =
            Map<String, dynamic>.from(defaults)..[idCampo] = id;
        final uuid = EdanSeccionesFuente.uuidFilaSintetica(
            uuidEdanLocalidad, rutaTipo, id);
        datos['uuid_registro'] = uuid;
        datos['fecha_modificacion'] = now;
        out.add(uuid);
        await ex.insert(
          'filas_seccion',
          {
            'uuid_registro': uuid,
            'uuid_edan_localidad': uuidEdanLocalidad,
            'tipo': tipo,
            'datos_json': jsonEncode(sanearJson(datos)),
            'fecha_modificacion_local': now,
            'estado_sync': 'pendiente',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } catch (e) {
      debugPrint('[EdanStoreV2] padding de catálogo $tipo falló: $e');
    }
    return out;
  }

  /// Núcleo transaccional de [guardarVivienda] sobre [ex].
  Future<void> _guardarViviendaTx(
      DatabaseExecutor ex, EdanVivienda vivienda) async {
    final previo = vivienda.uuidRegistro;
    if (previo == null ||
        previo.isEmpty ||
        !EdanUuidHelper.esUuidValido(previo)) {
      vivienda.uuidRegistro = EdanUuidHelper.generarUuidRegistro();
    }
    vivienda.fechaModificacionLocal ??=
        DateTime.now().toIso8601String();
    // CHECK `tipo_dano IN ('TOTAL','PARCIAL')`: el enum ya lo garantiza,
    // pero si el modelo trae un valor fuera de rango se cae a PARCIAL en
    // vez de abortar la transacción completa.
    final tipo = vivienda.tipoDano.name.toUpperCase().trim();
    if (tipo != 'TOTAL' && tipo != 'PARCIAL') {
      vivienda.tipoDano = EdanViviendaTipo.parcial;
    }
    await ex.insert(
      'viviendas',
      sanearJson(vivienda.toJson()) as Map<String, dynamic>,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> eliminarVivienda(String uuidVivienda) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await _eliminarViviendaTx(txn, uuidVivienda);
    });
    _notifyPendientes();
  }

  /// Núcleo transaccional de [eliminarVivienda] sobre [ex].
  Future<void> _eliminarViviendaTx(
      DatabaseExecutor ex, String uuidVivienda) async {
    await ex.delete(
      'viviendas',
      where: 'uuid_registro = ?',
      whereArgs: [uuidVivienda],
    );
  }

  // ── Fotos ──

  @override
  Future<void> registrarFoto(
    EdanFoto foto,
    String tipoEntidad,
    String uuidRegistro,
  ) async {
    foto.uuidFotografia ??= EdanUuidHelper.generarUuidFotografia();
    foto.uuidRegistro = uuidRegistro;
    if (foto.ruta.isNotEmpty && (foto.sha256 == null || foto.sha256!.isEmpty)) {
      foto.sha256 = await EdanUuidHelper.sha256Archivo(foto.ruta);
    }

    final db = await _db.database;
    // Etapa 4: el `tipo_entidad` se normaliza al CHECK del servidor. Si llega
    // el marcador local inválido, se deriva de la fila dueña (sección →
    // tabla, vivienda → 'vivienda'); si no hay dueña, se rechaza en local
    // antes de que el server lo haga con 400.
    var tipo = tipoEntidad;
    if (!EdanSeccionesRegistry.esTipoEntidadValido(tipo)) {
      tipo = await _derivarTipoEntidad(db, uuidRegistro) ?? '';
    }
    if (!EdanSeccionesRegistry.esTipoEntidadValido(tipo)) {
      throw StateError(
          'tipo_entidad irresoluble para la fila $uuidRegistro '
          '(llegó "$tipoEntidad"): sincronice primero su fila');
    }
    foto.tipoEntidad = tipo;
    // La cabecera es necesaria para obtener uuid_edan_localidad.
    final form = await db.query(
      'formularios',
      columns: ['uuid_edan_localidad'],
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuidRegistro],
      limit: 1,
    );
    String? uuidEdanLocalidad;
    if (form.isNotEmpty) {
      uuidEdanLocalidad = form.first['uuid_edan_localidad'] as String?;
    }
    // Fallback: buscar en filas_seccion.
    if (uuidEdanLocalidad == null || uuidEdanLocalidad.isEmpty) {
      final fila = await db.query(
        'filas_seccion',
        columns: ['uuid_edan_localidad'],
        where: 'uuid_registro = ?',
        whereArgs: [uuidRegistro],
        limit: 1,
      );
      if (fila.isNotEmpty) {
        uuidEdanLocalidad = fila.first['uuid_edan_localidad'] as String?;
      }
    }

    await db.insert(
      'fotografias',
      {
        'uuid_fotografia': foto.uuidFotografia,
        'uuid_edan_localidad': uuidEdanLocalidad ?? '',
        'tipo_entidad': tipo,
        'uuid_registro': uuidRegistro,
        'ruta_local': foto.ruta,
        'sha256': foto.sha256,
        'borrado_logico': 0,
        'fecha_modificacion': DateTime.now().toIso8601String(),
        'file_name': _nombreArchivo(foto.ruta),
        'mime_type': _mimeDeExtension(foto.ruta),
        'size_bytes': await _tamanoArchivo(foto.ruta),
        'upload_state': 'pending',
        'is_deleted': 0,
        'last_error': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // LWW 1-activa-por-fila (2026-10-16 §7.5): la dueña queda con una sola
    // foto activa. Las anteriores locales se retiran: si nunca se subieron
    // se purgan (nada que propagar); si ya están en el servidor quedan con
    // `borrado_logico=1` y `_pushBorradosFotos` propaga el DELETE.
    await _retirarFotosAnterioresDuena(
        db, tipo, uuidRegistro, foto.uuidFotografia);
    _notifyPendientes();
  }

  /// Retira las fotos activas anteriores de una dueña al registrar su
  /// reemplazo. Nunca lanza.
  Future<void> _retirarFotosAnterioresDuena(
    DatabaseExecutor db,
    String tipoEntidad,
    String uuidRegistro,
    String? exceptoUuid,
  ) async {
    try {
      final previas = await db.query(
        'fotografias',
        columns: ['uuid_fotografia', 'ruta_local', 'ruta_servidor'],
        where: 'uuid_fotografia != ? AND tipo_entidad = ? '
            'AND uuid_registro = ? AND borrado_logico = 0',
        whereArgs: [exceptoUuid ?? '', tipoEntidad, uuidRegistro],
      );
      for (final p in previas) {
        final uuid = p['uuid_fotografia'] as String?;
        if (uuid == null || uuid.isEmpty) continue;
        final rutaServidor = p['ruta_servidor'] as String?;
        final subida = rutaServidor != null && rutaServidor.isNotEmpty;
        if (subida) {
          await db.update(
            'fotografias',
            {
              'borrado_logico': 1,
              'fecha_modificacion': DateTime.now().toIso8601String(),
            },
            where: 'uuid_fotografia = ?',
            whereArgs: [uuid],
          );
        } else {
          await db.delete('cola_fotos',
              where: 'uuid_fotografia = ?', whereArgs: [uuid]);
          await db.delete('fotografias',
              where: 'uuid_fotografia = ?', whereArgs: [uuid]);
        }
        final ruta = p['ruta_local'] as String?;
        if (ruta != null && ruta.isNotEmpty) {
          try {
            final f = File(ruta);
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Deriva el `tipo_entidad` canónico desde la fila dueña en SQLite
  /// (vivienda → `'vivienda'`, sección → nombre de tabla). `null` si la dueña
  /// aún no existe localmente.
  Future<String?> _derivarTipoEntidad(
      DatabaseExecutor db, String uuidRegistro) async {
    final viv = await db.query(
      'viviendas',
      columns: ['uuid_registro'],
      where: 'uuid_registro = ?',
      whereArgs: [uuidRegistro],
      limit: 1,
    );
    if (viv.isNotEmpty) return 'vivienda';
    final fila = await db.query(
      'filas_seccion',
      columns: ['tipo'],
      where: 'uuid_registro = ?',
      whereArgs: [uuidRegistro],
      limit: 1,
    );
    if (fila.isEmpty) return null;
    return EdanSeccionesRegistry.tipoEntidadDesdeTipo(
        fila.first['tipo'] as String);
  }

  static String? _nombreArchivo(String ruta) {
    if (ruta.isEmpty) return null;
    final nombre = ruta.split(RegExp(r'[/\\]')).lastOrNull;
    return (nombre == null || nombre.isEmpty) ? null : nombre;
  }

  static String _mimeDeExtension(String ruta) {
    final nombre = _nombreArchivo(ruta) ?? '';
    final ext = nombre.contains('.') ? nombre.split('.').last.toLowerCase() : 'jpg';
    return switch (ext) {
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
  }

  static Future<int?> _tamanoArchivo(String ruta) async {
    try {
      final f = File(ruta);
      if (await f.exists()) return await f.length();
    } catch (_) {}
    return null;
  }

  @override
  Future<void> borrarFoto(String uuidFotografia) async {
    final db = await _db.database;
    // La ruta local se lee antes de purgar la cola de subida.
    final previa = await db.query(
      'fotografias',
      columns: ['ruta_local'],
      where: 'uuid_fotografia = ?',
      whereArgs: [uuidFotografia],
      limit: 1,
    );
    await db.update(
      'fotografias',
      {
        'borrado_logico': 1,
        'fecha_modificacion': DateTime.now().toIso8601String(),
      },
      where: 'uuid_fotografia = ?',
      whereArgs: [uuidFotografia],
    );
    // Si aún no se había subido, se cancela la subida pendiente.
    await db.delete(
      'cola_fotos',
      where: 'uuid_fotografia = ?',
      whereArgs: [uuidFotografia],
    );
    // Borra el archivo local para no dejar huérfanos en disco.
    if (previa.isNotEmpty) {
      final ruta = previa.first['ruta_local'] as String?;
      if (ruta != null && ruta.isNotEmpty) {
        try {
          final f = File(ruta);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
    _notifyPendientes();
  }

  @override
  Future<List<EdanFoto>> cargarFotosDeEntidad(
      String tipoEntidad, String uuidRegistro) async {
    if (uuidRegistro.isEmpty) return const [];
    final db = await _db.database;
    // Etapa 4: el marcador local `'filas_seccion'` ya no se persiste (el
    // CHECK lo rechaza); las fotos guardan el `tipo_entidad` canónico. Para
    // no perder la hidratación de fotos viejas ni exigir la ruta en cada
    // lector, ese marcador equivale a "la dueña con este uuid".
    final rows = EdanSeccionesRegistry.esTipoEntidadValido(tipoEntidad)
        ? await db.query(
            'fotografias',
            where:
                'tipo_entidad = ? AND uuid_registro = ? AND borrado_logico = 0',
            whereArgs: [tipoEntidad, uuidRegistro],
            orderBy: 'fecha_modificacion DESC',
          )
        : await db.query(
            'fotografias',
            where: 'uuid_registro = ? AND borrado_logico = 0',
            whereArgs: [uuidRegistro],
            orderBy: 'fecha_modificacion DESC',
          );
    return rows
        .map((r) => EdanFoto(
              uuidFotografia: r['uuid_fotografia'] as String?,
              ruta: (r['ruta_local'] as String?) ?? '',
              tipoEntidad: r['tipo_entidad'] as String?,
              uuidRegistro: r['uuid_registro'] as String?,
              sha256: r['sha256'] as String?,
            ))
        .toList();
  }

  // ── Sync ──
  @override
  Future<EdanEnvioResultado> enviarFormulario(String uuidEdanLocalidad) async {
    // Fase 4: integrar con EdanApiV2 + cola.
    throw UnimplementedError('EdanStoreV2.enviarFormulario en Fase 4');
  }

  @override
  Future<void> procesarColaDeletes() async {
    // Fase 4.
  }

  @override
  Stream<int> get pendientesStream => _pendientesController.stream;

  @override
  void dispose() {
    _pendientesController.close();
  }

  // ── Helpers ──

  void _ensureUuid(EdanLocalidad loc) {
    if (loc.uuidEdanLocalidad == null || loc.uuidEdanLocalidad!.isEmpty) {
      // Si la localidad ya tiene id local (fila en localidades_offline),
      // se reutiliza como uuid para que `formularios.uuid_edan_localidad`
      // coincida con `localidades_offline.id_local` y el borrador pueda
      // reabrirse cargando sus filas V2. Si no es uuid válido se genera uno
      // nuevo (un id legacy con prefijo daría 422 como identidad).
      final idLocal = loc.idLocal;
      loc.uuidEdanLocalidad =
          (idLocal != null && idLocal.isNotEmpty && EdanUuidHelper.esUuidValido(idLocal))
              ? idLocal
              : EdanUuidHelper.generarUuidEdanLocalidad();
    }
  }

  EdanLocalidad _localidadFromRow(Map<String, dynamic> row) {
    // `datos_json` corrupto (kill a mitad de REPLACE) no puede vaciar la
    // lista ni tumbar el guardado: se degrada a modelo vacío + columnas.
    final datosJson = row['datos_json'];
    final snap = decodificarSeguro(datosJson);
    final loc = snap != null
        ? EdanLocalidad.fromJson(snap)
        : EdanLocalidad();
    loc.uuidEdanLocalidad = row['uuid_edan_localidad'] as String?;
    loc.idLocal = loc.uuidEdanLocalidad;
    loc.idServer = (row['id_server'] as num?)?.toInt();
    loc.idUsuario = (row['id_usuario'] as num?)?.toInt();
    loc.idTipoLocalidad = (row['id_tipo_localidad'] as num?)?.toInt();
    loc.idTipoEvento = (row['id_tipo_evento'] as num?)?.toInt();
    loc.idDepartamento = (row['id_departamento'] as num?)?.toInt();
    loc.idProvincia = (row['id_provincia'] as num?)?.toInt();
    loc.idMunicipio = (row['id_municipio'] as num?)?.toInt();
    loc.idEdanLocalidadEstado =
        (row['id_edan_localidad_estado'] as num?)?.toInt();
    // El enum lo lee TODA la UI (filtros, badges, _puedeEnviar, contadores).
    // La columna es la verdad del servidor (la escribe el pull/estados); el
    // snapshot `datos_json` queda como fallback cuando aún no hay estado, y
    // sin estado en ningún lado es borrador (igual que el servidor, id=1).
    if (loc.idEdanLocalidadEstado != null) {
      loc.estadoLocalidad =
          UgrLocalidadEstadoX.fromId(loc.idEdanLocalidadEstado);
    } else {
      loc.estadoLocalidad ??= UgrLocalidadEstado.borrador;
    }
    loc.nombre = (row['localidad'] as String?) ?? loc.nombre;
    loc.fechaLlenado = row['fecha_llenado'] as String?;
    loc.fechaEvento = row['fecha_evento'] as String?;
    loc.horaEvento = row['hora_evento'] as String?;
    loc.totalPoblacionAfectada =
        (row['total_poblacion_afectada'] as num?)?.toInt() ?? 0;
    loc.totalFamiliasAfectadas =
        (row['total_familias_afectadas'] as num?)?.toInt() ?? 0;
    loc.totalFamiliasDamnificadas =
        (row['total_familias_damnificadas'] as num?)?.toInt() ?? 0;
    // Autor real del servidor (§20.16: nodo `usuario` disgregado a columnas
    // por `_columnasNodos`). Sin esto la UI mostraba al logueado en vez del
    // autor. Fallback: lo que traiga `datos_json`.
    final nombreAutor = row['usuario_nombre'] as String?;
    if (nombreAutor != null && nombreAutor.isNotEmpty) {
      final idAutor =
          (row['id_usuario'] as num?)?.toInt() ?? loc.idUsuario ?? 0;
      final idRol = (row['id_rol'] as num?)?.toInt() ?? 0;
      final nombreRol = row['usuario_rol'] as String?;
      loc.usuario = Usuario(
        idUsuario: idAutor,
        usuario: (row['usuario_login'] as String?) ?? '',
        nombre: nombreAutor,
        idRol: idRol,
        rol: nombreRol == null || nombreRol.isEmpty
            ? null
            : Rol(idRol: idRol, nombre: nombreRol),
      );
    }
    // Nombres espejo del servidor (geo/evento/tipo/estado/edan): sin
    // catálogo offline igual se muestran. No pisan lo resuelto del modelo
    // si ya viene con valor (el tab los completa por catálogo).
    if ((loc.departamentoNombre == null || loc.departamentoNombre!.isEmpty) &&
        row['departamento_nombre'] is String) {
      loc.departamentoNombre = row['departamento_nombre'] as String;
    }
    if ((loc.provinciaNombre == null || loc.provinciaNombre!.isEmpty) &&
        row['provincia_nombre'] is String) {
      loc.provinciaNombre = row['provincia_nombre'] as String;
    }
    if ((loc.municipioNombre == null || loc.municipioNombre!.isEmpty) &&
        row['municipio_nombre'] is String) {
      loc.municipioNombre = row['municipio_nombre'] as String;
    }
    if ((loc.tipoEventoNombre == null || loc.tipoEventoNombre!.isEmpty) &&
        row['tipo_evento_nombre'] is String) {
      loc.tipoEventoNombre = row['tipo_evento_nombre'] as String;
    }
    if (loc.tipoLocalidad.isEmpty && row['tipo_localidad_nombre'] is String) {
      loc.tipoLocalidad = row['tipo_localidad_nombre'] as String;
    }
    final idEdan = (row['id_edan'] as num?)?.toInt();
    if (idEdan != null) loc.idEdan = idEdan;
    // Flags de GRUPO (grup_*): desde 2026-10-14 el servidor las trae planas y
    // sincronizadas (invariante `grup=OR(imp)` verificado en vivo); se leen
    // directo con fallback a lo derivado de filas (`derivarFlagsDesdeFilas`).
    loc.grupPoblacion = (row['grup_poblacion'] as num?)?.toInt() == 1;
    loc.grupSalud = (row['grup_salud'] as num?)?.toInt() == 1;
    loc.grupInfraestructura = (row['grup_infraestructura'] as num?)?.toInt() == 1;
    loc.grupServicios = (row['grup_servicios'] as num?)?.toInt() == 1;
    loc.grupEducacion = (row['grup_educacion'] as num?)?.toInt() == 1;
    loc.grupVivienda = (row['grup_vivienda'] as num?)?.toInt() == 1;
    loc.grupAgropecuario = (row['grup_agropecuario'] as num?)?.toInt() == 1;
    loc.grupProteccion = (row['grup_proteccion'] as num?)?.toInt() == 1;
    loc.grupNecesidades = (row['grup_necesidades'] as num?)?.toInt() == 1;
    // Estado de sync sobre el snapshot: lo pendiente en SQLite manda sobre
    // lo que diga el snapshot viejo (el wizard marca en memoria pero la
    // fuente durable es la columna).
    if ((row['pendiente_push'] as num?)?.toInt() == 1) {
      loc.sincronizado = false;
      loc.pendienteActualizacion = true;
    }
    loc.envioPendiente = (row['pending_submit'] as num?)?.toInt() == 1;
    return loc;
  }

  Map<String, dynamic> _formularioToRow(
    EdanLocalidad loc, {
    List<String>? seccionesActivas,
    String estadoLocal = 'borrador',
    String syncState = 'pending_create',
    int pendingSubmit = 0,
    int? estadoDestino,
  }) {
    final now = DateTime.now().toIso8601String();
    loc.fechaModificacion = now;
    return {
      'uuid_edan_localidad': loc.uuidEdanLocalidad,
      'id_server': loc.idServer,
      'localidad': loc.nombre,
      'id_municipio': loc.idMunicipio,
      'id_departamento': loc.idDepartamento,
      'id_provincia': loc.idProvincia,
      'id_tipo_evento': loc.idTipoEvento,
      'id_tipo_localidad': loc.idTipoLocalidad,
      'id_edan_localidad_estado': loc.idEdanLocalidadEstado,
      'fecha_llenado': loc.fechaLlenado,
      'fecha_evento': loc.fechaEvento,
      'hora_evento': loc.horaEvento,
      'total_poblacion_afectada': loc.totalPoblacionAfectada,
      'total_familias_afectadas': loc.totalFamiliasAfectadas,
      'total_familias_damnificadas': loc.totalFamiliasDamnificadas,
      'grup_poblacion': loc.grupPoblacion ? 1 : 0,
      'grup_salud': loc.grupSalud ? 1 : 0,
      'grup_infraestructura': loc.grupInfraestructura ? 1 : 0,
      'grup_servicios': loc.grupServicios ? 1 : 0,
      'grup_educacion': loc.grupEducacion ? 1 : 0,
      'grup_vivienda': loc.grupVivienda ? 1 : 0,
      'grup_agropecuario': loc.grupAgropecuario ? 1 : 0,
      'grup_proteccion': loc.grupProteccion ? 1 : 0,
      'grup_necesidades': loc.grupNecesidades ? 1 : 0,
      // NOTA: los 14 flags de sección NO son columnas de `formularios` (la
      // fuente de verdad es la auxiliar `localidad_secciones_activas`); aquí
      // solo se persisten los 9 `grup_*`, que sí existen en el esquema.
      'secciones_activas_json': jsonEncode(seccionesActivas ?? const []),
      'fecha_modificacion': now,
      // Etapa 3: el llamador preserva los valores previos (nunca se degradan
      // en un re-guardado). Solo `marcarEnviado` y el motor los transicionan.
      'estado_local': estadoLocal,
      'sync_state': syncState,
      'pending_submit': pendingSubmit,
      'estado_destino': estadoDestino,
      'id_usuario': loc.idUsuario,
      'datos_json': jsonEncode(sanearJson(loc.toJson())),
      // Blindaje: todo insert nace sucio; `recargarFirma` al cierre del
      // guardado lo deriva exacto (limpio si no hubo cambio real).
      'pendiente_push': 1,
    };
  }

  // ── Cola de sincronización ──

  /// Inserta o reemplaza un ítem en `cola_sincronizacion` (Etapa 1/3: con
  /// `operation_uuid` + `idempotency_key` estables por ítem para correlacionar
  /// reintentos; `depends_on` reserva la dependencia entre operaciones).
  ///
  /// [payload] guarda coordenadas para ejecutar un `D` sin la fila local
  /// (p. ej. `{uuid_edan_localidad, tipo}`): sin ellas, un borrado cuya fila
  /// ya no existe no puede llamar al servidor y el DELETE jamás viajaría.
  Future<void> encolar({
    required String tabla,
    required String uuidRegistro,
    required String accion,
    String estado = 'pendiente',
    String? dependsOn,
    DatabaseExecutor? executor,
    Map<String, dynamic>? payload,
  }) async {
    final op = const Uuid().v4();
    final row = {
      'tabla': tabla,
      'uuid_registro': uuidRegistro,
      'accion': accion,
      'estado': estado,
      'intentos': 0,
      'fecha_proximo_intento': null,
      'ultimo_error': null,
      'operation_uuid': op,
      'idempotency_key': op,
      'depends_on': dependsOn,
      'payload_json': payload == null ? null : jsonEncode(payload),
    };
    if (executor != null) {
      await executor.insert(
        'cola_sincronizacion',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return;
    }
    final db = await _db.database;
    await db.insert(
      'cola_sincronizacion',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notifyPendientes();
  }

  /// Núcleo transaccional de [encolar] sobre [ex] (no notifica; el llamador
  /// lo hace al confirmar la transacción).
  Future<void> _encolarTx(
    DatabaseExecutor ex, {
    required String tabla,
    required String uuidRegistro,
    required String accion,
    String estado = 'pendiente',
    String? dependsOn,
    Map<String, dynamic>? payload,
  }) async {
    final op = const Uuid().v4();
    await ex.insert(
      'cola_sincronizacion',
      {
        'tabla': tabla,
        'uuid_registro': uuidRegistro,
        'accion': accion,
        'estado': estado,
        'intentos': 0,
        'fecha_proximo_intento': null,
        'ultimo_error': null,
        'operation_uuid': op,
        'idempotency_key': op,
        'depends_on': dependsOn,
        'payload_json': payload == null ? null : jsonEncode(payload),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Encola una foto para subir cuando su dueña esté confirmada.
  @override
  Future<void> encolarFoto(EdanFoto foto) async {
    final db = await _db.database;
    await db.insert(
      'cola_fotos',
      {
        'uuid_fotografia': foto.uuidFotografia,
        'ruta_local': foto.ruta,
        'tipo_entidad': foto.tipoEntidad,
        'uuid_registro': foto.uuidRegistro,
        'sha256': foto.sha256,
        'estado': 'pendiente',
        'intentos': 0,
        'fecha_proximo_intento': null,
        'ultimo_error': null,
        'file_name': _nombreArchivo(foto.ruta),
        'mime_type': _mimeDeExtension(foto.ruta),
        'size_bytes': await _tamanoArchivo(foto.ruta),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notifyPendientes();
  }

  /// Lista ítems de `cola_sincronizacion` ordenados por prioridad de envío.
  Future<List<EdanColaItem>> listarColaSync({
    String? estado,
    int limit = 200,
  }) async {
    final db = await _db.database;
    final where = estado != null ? 'estado = ?' : null;
    final whereArgs = estado != null ? [estado] : null;
    final rows = await db.query(
      'cola_sincronizacion',
      where: where,
      whereArgs: whereArgs,
      orderBy: '''
        CASE tabla
          WHEN 'formulario' THEN 0
          WHEN 'filas_seccion' THEN 1
          WHEN 'vivienda' THEN 2
          ELSE 3
        END,
        fecha_registro ASC
      ''',
      limit: limit,
    );
    return rows.map(EdanColaItem.fromMap).toList();
  }

  /// Lista fotos pendientes de subir.
  Future<List<EdanColaFotoItem>> listarColaFotos({
    String? estado,
    int limit = 50,
  }) async {
    final db = await _db.database;
    final where = estado != null ? 'estado = ?' : null;
    final whereArgs = estado != null ? [estado] : null;
    final rows = await db.query(
      'cola_fotos',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'intentos ASC, fecha_proximo_intento ASC',
      limit: limit,
    );
    return rows.map(EdanColaFotoItem.fromMap).toList();
  }

  /// Actualiza estado y metadata de un ítem de sync.
  Future<void> actualizarEstadoColaSync(
    int id, {
    required String estado,
    int? intentos,
    String? ultimoError,
    String? fechaProximoIntento,
  }) async {
    final db = await _db.database;
    final values = <String, dynamic>{'estado': estado};
    if (intentos != null) values['intentos'] = intentos;
    if (ultimoError != null) values['ultimo_error'] = ultimoError;
    if (fechaProximoIntento != null) {
      values['fecha_proximo_intento'] = fechaProximoIntento;
    }
    await db.update(
      'cola_sincronizacion',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
    _notifyPendientes();
  }

  /// Actualiza estado y metadata de un ítem de foto.
  Future<void> actualizarEstadoColaFoto(
    String uuidFotografia, {
    required String estado,
    int? intentos,
    String? ultimoError,
    String? fechaProximoIntento,
  }) async {
    final db = await _db.database;
    final values = <String, dynamic>{'estado': estado};
    if (intentos != null) values['intentos'] = intentos;
    if (ultimoError != null) values['ultimo_error'] = ultimoError;
    if (fechaProximoIntento != null) {
      values['fecha_proximo_intento'] = fechaProximoIntento;
    }
    await db.update(
      'cola_fotos',
      values,
      where: 'uuid_fotografia = ?',
      whereArgs: [uuidFotografia],
    );
    _notifyPendientes();
  }

  /// Elimina un ítem confirmado de `cola_sincronizacion`.
  Future<void> purgarColaSync(int id) async {
    final db = await _db.database;
    await db.delete('cola_sincronizacion', where: 'id = ?', whereArgs: [id]);
    _notifyPendientes();
  }

  /// Elimina un ítem confirmado de `cola_fotos`.
  Future<void> purgarColaFoto(String uuidFotografia) async {
    final db = await _db.database;
    await db.delete(
      'cola_fotos',
      where: 'uuid_fotografia = ?',
      whereArgs: [uuidFotografia],
    );
    _notifyPendientes();
  }

  /// Elimina de las colas V2 todo ítem pendiente de esta localidad.
  ///
  /// Se usa tras un envío inmediato "todo-en-uno" (que ya subió el documento,
  /// las secciones y las fotos) para que el motor de sync no las vuelva a
  /// empujar —evita reenvíos duplicados—. Cubre la
  /// cabecera (`formulario`), las filas (`filas_seccion`), las viviendas
  /// (`vivienda`, ligadas por `uuid_dano_vivienda`) y las fotos (`cola_fotos`,
  /// ligadas por el `uuid_registro` de la fila o vivienda dueña).
  Future<void> purgarColaDeFormulario(String uuidEdanLocalidad) async {
    final db = await _db.database;
    const filasSub =
        'SELECT uuid_registro FROM filas_seccion WHERE uuid_edan_localidad = ?';
    const vivSub =
        'SELECT uuid_registro FROM viviendas WHERE uuid_dano_vivienda IN ($filasSub)';
    const where = 'uuid_registro = ? '
        'OR uuid_registro IN ($filasSub) '
        'OR uuid_registro IN ($vivSub)';
    final args = <Object?>[
      uuidEdanLocalidad,
      uuidEdanLocalidad,
      uuidEdanLocalidad,
    ];
    await db.delete('cola_sincronizacion', where: where, whereArgs: args);
    await db.delete('cola_fotos', where: where, whereArgs: args);
    _notifyPendientes();
  }

  /// Devuelve la cantidad de ítems sync pendientes (incluye subiendo y reintentando).
  ///
  /// Suma la cola (`C`/`U`/`D` pendientes) MÁS los formularios con
  /// `pendiente_push=1` (Fase D: el motor los empuja directo por
  /// `/completo` sin pasar por la cola). Sin esto, un formulario editado
  /// no sumaba al badge aunque el sync sí lo iba a subir.
  Future<int> contarPendientesSync() async {
    final db = await _db.database;
    final cola = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM cola_sincronizacion WHERE estado IN ('pendiente','subiendo')",
    );
    final forms = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM formularios WHERE pendiente_push = 1',
    );
    return ((cola.first['c'] as num?)?.toInt() ?? 0) +
        ((forms.first['c'] as num?)?.toInt() ?? 0);
  }

  /// Devuelve la cantidad de fotos pendientes.
  Future<int> contarPendientesFotos() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM cola_fotos WHERE estado IN ('pendiente','subiendo')",
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  /// Localidades distintas con trabajo pendiente (lo que muestra el badge).
  ///
  /// El badge contaba OPERACIONES (1 formulario + 1 foto + 1 borrado = 3 con
  /// solo 2 localidades) y no cuadraba con "Total localidades". Ahora agrupa
  /// por localidad dueña: formularios con `pendiente_push`, ítems de cola y
  /// fotos resueltos a su `uuid_edan_localidad`. Lo irresoluble (p. ej. `D`
  /// de un formulario ya borrado localmente) suma 1 cada uno: es trabajo
  /// real pendiente.
  Future<int> contarLocalidadesPendientes() async {
    final db = await _db.database;
    final uuids = <String>{};
    var sueltos = 0;

    final forms = await db.query(
      'formularios',
      columns: ['uuid_edan_localidad'],
      where: 'pendiente_push = 1',
    );
    for (final f in forms) {
      final u = f['uuid_edan_localidad'] as String?;
      if (u != null && u.isNotEmpty) uuids.add(u);
    }

    final cola = await db.query(
      'cola_sincronizacion',
      columns: ['tabla', 'uuid_registro'],
      where: "estado IN ('pendiente','subiendo')",
    );
    for (final c in cola) {
      final dueno = await _uuidLocalidadDe(
        db,
        (c['tabla'] as String?) ?? '',
        (c['uuid_registro'] as String?) ?? '',
      );
      if (dueno != null) {
        uuids.add(dueno);
      } else {
        sueltos++;
      }
    }

    final fotos = await db.query(
      'cola_fotos',
      columns: ['uuid_registro'],
      where: "estado IN ('pendiente','subiendo')",
    );
    for (final f in fotos) {
      final r = (f['uuid_registro'] as String?) ?? '';
      final dueno =
          await _uuidLocalidadDeFila(db, r) ?? await _uuidLocalidadDeVivienda(db, r);
      if (dueno != null) {
        uuids.add(dueno);
      } else {
        sueltos++;
      }
    }
    return uuids.length + sueltos;
  }

  /// Resuelve el `uuid_edan_localidad` dueño de un ítem de cola. `null` si no
  /// se puede resolver (fila borrada localmente: el `D` igual debe viajar).
  Future<String?> _uuidLocalidadDe(
    DatabaseExecutor db,
    String tabla,
    String uuidRegistro,
  ) async {
    if (uuidRegistro.isEmpty) return null;
    switch (tabla) {
      case 'formulario':
        final r = await db.query(
          'formularios',
          columns: ['uuid_edan_localidad'],
          where: 'uuid_edan_localidad = ?',
          whereArgs: [uuidRegistro],
          limit: 1,
        );
        return r.isNotEmpty ? uuidRegistro : null;
      case 'filas_seccion':
        return _uuidLocalidadDeFila(db, uuidRegistro);
      case 'vivienda':
        return _uuidLocalidadDeVivienda(db, uuidRegistro);
      default:
        return null;
    }
  }

  Future<String?> _uuidLocalidadDeFila(
      DatabaseExecutor db, String uuidRegistro) async {
    if (uuidRegistro.isEmpty) return null;
    final r = await db.query(
      'filas_seccion',
      columns: ['uuid_edan_localidad'],
      where: 'uuid_registro = ?',
      whereArgs: [uuidRegistro],
      limit: 1,
    );
    if (r.isEmpty) return null;
    return r.first['uuid_edan_localidad'] as String?;
  }

  Future<String?> _uuidLocalidadDeVivienda(
      DatabaseExecutor db, String uuidRegistro) async {
    if (uuidRegistro.isEmpty) return null;
    final r = await db.rawQuery(
      'SELECT s.uuid_edan_localidad AS u FROM filas_seccion s '
      'JOIN viviendas v ON v.uuid_dano_vivienda = s.uuid_registro '
      'WHERE v.uuid_registro = ? LIMIT 1',
      [uuidRegistro],
    );
    if (r.isEmpty) return null;
    return r.first['u'] as String?;
  }

  /// Recalcula y publica [pendientesNotifier]. La UI
  /// (botón sync, badges) lo llama tras cada corrida del motor o al cambiar de
  /// pestaña para mantener el contador fresco.
  ///
  /// El badge publica LOCALIDADES con trabajo pendiente (cuadra con "Total
  /// localidades"), no operaciones sueltas.
  Future<void> refrescarPendientes() async {
    await _notifyPendientes();
  }

  // ── Firma de contenido (dirty derivado, §20.15 + robustez) ──

  /// Claves que NUNCA entran a la firma: espejo de foto (lo llena el
  /// servidor), timestamps (los mueve el servidor/la BD, no el usuario) y
  /// los checks locales `afectado`/`impactado`/`marcado` (se persisten en
  /// `datos_json` para sobrevivir el round-trip pero el wire los BORRA —
  /// el servidor no tiene esas columnas: `prepararPayloadCompleto` los
  /// remueve). Sin excluirlos aquí, `firmaDePayload(payload)` y
  /// `firmaContenido(DB)` divergían para cualquier fila con check →
  /// `limpio=false` eterno → `pendiente_push` nunca se limpiaba (badge
  /// pegado en 1 + re-PUT en cada sync, reportado 2026-10-18).
  static const _clavesFueraDeFirma = {
    'fotografia',
    'fecha_modificacion',
    'fecha_modificacion_local',
    'afectado',
    'impactado',
    'marcado',
  };

  /// Canónico estable para firmar: claves ordenadas, listas de mapas
  /// ordenadas por su forma (el orden no es contenido), números integrales
  /// normalizados (`5.0 ≡ 5`). SIN colapsar vacíos (local-vs-local debe
  /// distinguir `null` de `0` salvo que el servidor los unifique, caso en
  /// que un no-op lo asienta).
  static String _canonFirma(dynamic v) {
    if (v is Map) {
      final keys = v.keys.map((e) => e.toString()).toList()..sort();
      return '{${keys.map((k) => '$k:${_canonFirma(v[k])}').join(',')}}';
    }
    if (v is List) {
      final items = v.map(_canonFirma).toList()..sort();
      return '[${items.join(',')}]';
    }
    if (v is double && v == v.truncateToDouble()) {
      return v.toInt().toString();
    }
    return jsonEncode(v);
  }

  /// Firma sha256 de un documento normalizado
  /// `{cabecera, secciones:{tipo:[filas]}, viviendas:[...]}`.
  static String firmaDeNormalizado(Map<String, dynamic> normalizado) {
    final cab = normalizado['cabecera'];
    final cabMap = cab is Map<String, dynamic>
        ? cab
        : (cab is Map ? Map<String, dynamic>.from(cab) : <String, dynamic>{});
    final secciones = normalizado['secciones'];
    final secMap = secciones is Map<String, dynamic>
        ? secciones
        : (secciones is Map
            ? Map<String, dynamic>.from(secciones)
            : <String, dynamic>{});
    final viv = normalizado['viviendas'];
    final canon = {
      'cabecera': {
        for (final k in _clavesCabeceraFirma)
          if (cabMap.containsKey(k)) k: cabMap[k],
      },
      'secciones': {
        for (final e in secMap.entries) e.key: _filasParaFirma(e.value),
      },
      'viviendas': _filasParaFirma(viv),
    };
    return sha256.convert(utf8.encode(_canonFirma(canon))).toString();
  }

  /// Claves de cabecera que viajan en `/completo` (las que deciden cambio).
  static const _clavesCabeceraFirma = [
    'uuid_edan_localidad',
    'localidad',
    'id_municipio',
    'id_departamento',
    'id_provincia',
    'id_tipo_evento',
    'id_tipo_localidad',
    'id_edan_localidad_estado',
    'fecha_llenado',
    'fecha_evento',
    'hora_evento',
    'total_poblacion_afectada',
    'total_familias_afectadas',
    'total_familias_damnificadas',
    'imp_impacto_poblacion',
    'imp_primera_respuesta',
    'imp_salud_establecimientos',
    'imp_necesidad_salud',
    'imp_danos_viales',
    'imp_danos_infra_publica',
    'imp_servicios_basicos',
    'imp_unidades_educativas',
    'imp_danos_vivienda',
    'imp_danos_agricultura',
    'imp_danos_pecuarios',
    'imp_infra_productiva',
    'imp_proteccion',
    'imp_necesidad_humanitaria',
  ];

  /// Filas canónicas para firma: objeto 1:1 → lista de 1; se quitan espejos
  /// y timestamps en TODOS los niveles; `viviendas[]` anidadas se excluyen
  /// (se firman aparte desde su tabla).
  static List<Map<String, dynamic>> _filasParaFirma(dynamic valor) {
    final lista = valor is List
        ? valor
        : (valor is Map ? [valor] : const []);
    return [
      for (final m in lista.whereType<Map>())
        _filaParaFirma(Map<String, dynamic>.from(m)),
    ];
  }

  static Map<String, dynamic> _filaParaFirma(Map<String, dynamic> fila) {
    final out = <String, dynamic>{};
    fila.forEach((k, v) {
      if (_clavesFueraDeFirma.contains(k)) return;
      // `rango` es contenido wire SOLO como resolver legacy (sin id): el
      // payload lo borra cuando la fila trae `id_grupo_etario` (motor
      // 2414-2416). Misma regla aquí para que las dos firmas coincidan.
      if (k == 'rango' && fila['id_grupo_etario'] != null) return;
      if (k == 'viviendas') return;
      if (v is Map) {
        out[k] = _filaParaFirma(Map<String, dynamic>.from(v));
        return;
      }
      if (v is List) {
        out[k] = v
            .map((e) => e is Map
                ? _filaParaFirma(Map<String, dynamic>.from(e))
                : e)
            .toList();
        return;
      }
      out[k] = v;
    });
    return out;
  }

  /// Firma del contenido actual en SQLite (cabecera + filas + viviendas).
  /// Las fotos NO entran (tienen su propio canal) y el espejo `fotografia`
  /// tampoco (es eco del servidor).
  ///
  /// Réplica EXACTA de lo que [prepararPayloadCompleto del motor] enviaría
  /// (misma Fuente, mismo gate por grupo, mismo whitelist de viviendas,
  /// mismo padding de catálogo): así `firmaDePayload(payload)` coincide con
  /// esta firma cuando el contenido no cambió. El test de paridad lo fija.
  static Future<String> firmaContenido(
    DatabaseExecutor db,
    String uuidEdanLocalidad, {
    Map<String, Object?>? formRow,
  }) async {
    final rows = formRow != null
        ? [formRow]
        : await db.query(
            'formularios',
            where: 'uuid_edan_localidad = ?',
            whereArgs: [uuidEdanLocalidad],
            limit: 1,
          );
    if (rows.isEmpty) return '';
    final row = Map<String, dynamic>.from(rows.first as Map);
    final bruto = await EdanSeccionesFuente()
        .seccionesConDatos(uuidEdanLocalidad,
            formRow: Map<String, Object?>.from(row), executor: db);
    // Gate por grupo (réplica del motor): sin info de grupos, todo pasa.
    final tieneInfo = (await db.query(
      'grupos_local',
      columns: ['grupo'],
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuidEdanLocalidad],
      limit: 1,
    ))
        .isNotEmpty;
    bool marcado(String ruta) {
      if (!tieneInfo) return true;
      final col = EdanSeccionesRegistry.columnaGrupoDeRuta(ruta);
      if (col == null) return true;
      return (row[col] as num?)?.toInt() == 1;
    }

    final porTipo = <String, List<Map<String, dynamic>>>{};
    for (final e in bruto.entries) {
      if (marcado(e.key)) porTipo[e.key] = e.value;
    }
    final flags = EdanSeccionesRegistry.construirFlagsDesdeActivas(
        porTipo.keys.toList());
    final cab = <String, dynamic>{
      for (final k in _clavesCabeceraNoImp)
        if (row.containsKey(k)) k: row[k],
      for (final d in EdanSeccionesRegistry.secciones)
        'imp_${d.rutaV2.replaceAll('-', '_')}':
            flags['imp_${d.rutaV2.replaceAll('-', '_')}'] ?? false,
    };
    // Secciones en forma payload (llaveJson; 1:1 colapsa igual por el
    // canonicalizador): filas sin `fotografia`, padre vivienda con hijas
    // whitelisteadas y coords anuladas (§20.4), padding de catálogo.
    final secciones = <String, dynamic>{};
    final viviendas = <Map<String, dynamic>>[];
    for (final d in EdanSeccionesRegistry.secciones) {
      final filas = porTipo[d.rutaV2] ?? const <Map<String, dynamic>>[];
      if (filas.isEmpty) continue;
      if (d.rutaV2 == 'danos-vivienda') {
        final lista = <Map<String, dynamic>>[];
        for (final f in filas) {
          final padre = Map<String, dynamic>.from(f)..remove('fotografia');
          final hijas = await db.query(
            'viviendas',
            columns: [
              'uuid_registro',
              'tipo_dano',
              'coordenada_lat',
              'coordenada_lon',
            ],
            where: 'uuid_dano_vivienda = ?',
            whereArgs: [padre['uuid_registro']],
          );
          if (hijas.isNotEmpty) {
            padre['coordenada_lat'] = null;
            padre['coordenada_lon'] = null;
            viviendas.addAll(hijas.map(
                (v) => Map<String, dynamic>.from(v as Map)));
          }
          lista.add(padre);
        }
        if (lista.isNotEmpty) secciones[d.llaveJson] = lista;
        continue;
      }
      secciones[d.llaveJson] =
          filas.map((f) => Map<String, dynamic>.from(f)).toList();
    }
    _padCatalogoParaFirma(
        secciones,
        uuidEdanLocalidad,
        (flags['imp_impacto_poblacion'] ?? false) == true,
        'impacto_poblacion',
        'impacto-poblacion',
        'id_grupo_etario',
        const [1, 2, 3, 4],
        const {'fallecidos': 0, 'heridos': 0, 'desaparecidos': 0});
    _padCatalogoParaFirma(
        secciones,
        uuidEdanLocalidad,
        (flags['imp_proteccion'] ?? false) == true,
        'proteccion',
        'proteccion',
        'id_grupo_vulnerable_catalogo',
        const [1, 2, 3, 4, 5, 6, 7, 8],
        const {'mujeres': 0, 'hombres': 0});
    return firmaDeNormalizado({
      'cabecera': cab,
      'secciones': secciones,
      'viviendas': viviendas,
    });
  }

  /// Claves escalares de cabecera que viajan (sin las 14 `imp_*`, que se
  /// derivan aparte).
  static const _clavesCabeceraNoImp = [
    'uuid_edan_localidad',
    'localidad',
    'id_municipio',
    'id_departamento',
    'id_provincia',
    'id_tipo_evento',
    'id_tipo_localidad',
    'id_edan_localidad_estado',
    'fecha_llenado',
    'fecha_evento',
    'hora_evento',
    'total_poblacion_afectada',
    'total_familias_afectadas',
    'total_familias_damnificadas',
  ];

  /// Réplica de `_completarFilasDeCatalogo` del motor para la firma: con
  /// flag `true`, set exacto por id (faltantes con defaults y uuid
  /// determinista); con `false`, la sección no existe.
  static void _padCatalogoParaFirma(
    Map<String, dynamic> secciones,
    String uuid,
    bool flag,
    String llaveJson,
    String rutaTipo,
    String idCampo,
    List<int> ids,
    Map<String, dynamic> defaults,
  ) {
    if (!flag) {
      secciones.remove(llaveJson);
      return;
    }
    final porId = <int, Map<String, dynamic>>{};
    final existentes = secciones[llaveJson];
    if (existentes is List) {
      for (final f in existentes) {
        if (f is! Map) continue;
        final fila = Map<String, dynamic>.from(f);
        final id = _intDeFirma(fila[idCampo]);
        if (id == null || !ids.contains(id) || porId.containsKey(id)) {
          continue;
        }
        porId[id] = fila;
      }
    }
    final filas = <Map<String, dynamic>>[];
    for (final id in ids) {
      final fila =
          porId[id] ?? Map<String, dynamic>.from(defaults);
      fila[idCampo] = id;
      fila.putIfAbsent(
        'uuid_registro',
        () => EdanSeccionesFuente.uuidFilaSintetica(uuid, rutaTipo, id),
      );
      filas.add(fila);
    }
    secciones[llaveJson] = filas;
  }

  static int? _intDeFirma(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}');
  }

  /// Firma de un payload `/completo` (misma canonicalización que
  /// [firmaContenido]: el confirm la usa como `firma_enviada` sin ventana
  /// de carrera, porque deriva del MISMO snapshot que se envió).
  static String firmaDePayload(Map<String, dynamic> payload) {
    final secciones = <String, dynamic>{};
    final viviendas = <Map<String, dynamic>>[];
    for (final e in payload.entries) {
      final k = e.key;
      if (k == 'uuid_edan_localidad' ||
          _clavesCabeceraFirma.contains(k) && !k.startsWith('imp_')) {
        continue;
      }
      if (k == 'danos_vivienda' || k == 'danos-vivienda') {
        final lista = e.value is List
            ? e.value as List
            : (e.value is Map ? [e.value] : const []);
        for (final p in lista.whereType<Map>()) {
          final padre = Map<String, dynamic>.from(p);
          final hijas = padre.remove('viviendas');
          if (padre.isNotEmpty &&
              (padre['uuid_registro'] != null ||
                  padre.values.any((v) => v != null))) {
            (secciones[k] ??= []).add(padre);
          }
          if (hijas is List) {
            viviendas.addAll(hijas.whereType<Map>().map(
                (v) => Map<String, dynamic>.from(v)));
          }
        }
        continue;
      }
      if (e.value is List || e.value is Map) secciones[k] = e.value;
    }
    final imp = <String, dynamic>{};
    for (final llave in secciones.keys) {
      final ruta = EdanSeccionesRegistry.rutaDesdeTabla(llave);
      if (ruta.isEmpty) continue;
      imp['imp_${ruta.replaceAll('-', '_')}'] = true;
    }
    return firmaDeNormalizado({
      'cabecera': {...payload, ...imp},
      'secciones': secciones,
      'viviendas': viviendas,
    });
  }

  /// Recalcula el dirty derivado: `pendiente_push = (firma_actual !=
  /// firma_enviada)`. Si [sincronizada] (contenido vino del servidor o se
  /// acaba de confirmar), se asienta `firma_enviada=firma` y queda limpio.
  /// Nunca limpia un dirty real: si el contenido difiere de lo enviado,
  /// queda en 1 aunque alguien lo hubiera puesto en 0. La intención de
  /// envío (`pending_submit`/`estado_destino`) también ensucia: hay algo
  /// que viajar aunque el contenido coincida.
  ///
  /// Nunca lanza: corre post-commit y un fallo suyo NO debe convertir un
  /// guardado exitoso en `false` (falso "no guardó" con dato sí guardado).
  /// Ante cualquier error deja `pendiente_push=1` (dirección segura: viaja
  /// de más, nunca de menos) y lo registra.
  Future<void> recargarFirma(String uuidEdanLocalidad,
      {required bool sincronizada}) async {
    try {
      await _recargarFirmaTx(uuidEdanLocalidad, sincronizada: sincronizada);
      // Todo cambio de dirty implica cambio visible: las listas recargan.
      datosCambiados();
    } catch (e) {
      debugPrint('[EdanStoreV2] recargarFirma falló ($uuidEdanLocalidad): $e');
      try {
        final db = await _db.database;
        await db.update(
          'formularios',
          {'pendiente_push': 1},
          where: 'uuid_edan_localidad = ?',
          whereArgs: [uuidEdanLocalidad],
        );
        await refrescarPendientes();
      } catch (_) {}
    }
  }

  /// Sanea un valor para `jsonEncode`: `NaN/Infinity` (GPS real del equipo)
  /// → `null`, `DateTime` → ISO. Sin esto, una coordenada mala aborta la
  /// transacción completa y el wizard dice "no guardó" con todo válido.
  static dynamic sanearJson(dynamic v) {
    if (v is double && (v.isNaN || v.isInfinite)) return null;
    if (v is DateTime) return v.toIso8601String();
    if (v is Map) {
      return {
        for (final e in v.entries) '${e.key}': sanearJson(e.value),
      };
    }
    if (v is List) return [for (final e in v) sanearJson(e)];
    return v;
  }

  /// `jsonDecode` que nunca lanza: `null` ante nulo/vacío/corrupto.
  static Map<String, dynamic>? decodificarSeguro(Object? crudo) {
    try {
      if (crudo == null) return null;
      if (crudo is Map<String, dynamic>) {
        return Map<String, dynamic>.from(crudo);
      }
      if (crudo is Map) return Map<String, dynamic>.from(crudo);
      if (crudo is String) {
        if (crudo.isEmpty) return null;
        final d = jsonDecode(crudo);
        if (d is Map<String, dynamic>) return d;
        if (d is Map) return Map<String, dynamic>.from(d);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _recargarFirmaTx(String uuidEdanLocalidad,
      {required bool sincronizada}) async {
    final db = await _db.database;
    if (sincronizada) {
      final firma = await firmaContenido(db, uuidEdanLocalidad);
      await db.update(
        'formularios',
        {
          'firma_contenido': firma,
          'firma_enviada': firma,
          'pendiente_push': 0,
        },
        where: 'uuid_edan_localidad = ?',
        whereArgs: [uuidEdanLocalidad],
      );
    } else {
      final prev = await db.query(
        'formularios',
        columns: [
          'firma_enviada',
          'pending_submit',
          'estado_destino',
        ],
        where: 'uuid_edan_localidad = ?',
        whereArgs: [uuidEdanLocalidad],
        limit: 1,
      );
      if (prev.isEmpty) return;
      final firma = await firmaContenido(db, uuidEdanLocalidad);
      final enviada = prev.first['firma_enviada'] as String?;
      final conIntencion = (prev.first['pending_submit'] as num?)?.toInt() ==
              1 ||
          prev.first['estado_destino'] != null;
      final sucio =
          (enviada == null || enviada.isEmpty || enviada != firma) ||
                  conIntencion
              ? 1
              : 0;
      await db.update(
        'formularios',
        {'firma_contenido': firma, 'pendiente_push': sucio},
        where: 'uuid_edan_localidad = ?',
        whereArgs: [uuidEdanLocalidad],
      );
    }
    await refrescarPendientes();
  }

  /// Carga la fila de fotografías por uuid.
  Future<EdanFoto?> cargarFoto(String uuidFotografia) async {
    final db = await _db.database;
    final rows = await db.query(
      'fotografias',
      where: 'uuid_fotografia = ?',
      whereArgs: [uuidFotografia],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return EdanFoto(
      uuidFotografia: r['uuid_fotografia'] as String?,
      ruta: r['ruta_local'] as String? ?? '',
      tipoEntidad: r['tipo_entidad'] as String?,
      uuidRegistro: r['uuid_registro'] as String?,
      sha256: r['sha256'] as String?,
    );
  }

  // ── Galería (rol 7) ───────────────────────────────────────────────────────

  /// Fotos de las localidades del usuario (tabla `fotografias` + cabecera de
  /// su localidad desde `formularios`), para la pestaña Galería del rol 7.
  ///
  /// Solo fotos vivas (`borrado_logico = 0` e `is_deleted = 0`) del usuario
  /// pedido — coherente con el alcance de `listarFormularios`. Orden:
  /// localidad alfabética, fotos más recientes primero dentro de cada una.
  Future<List<EdanFotoGaleria>> listarFotosGaleria({
    required int usuarioId,
  }) {
    // El autor no se selecciona: todas las fotos son del propio usuario.
    return _fotosGaleria(
      filtroLocalidad: 'fo.id_usuario = ?',
      valor: usuarioId,
      conAutor: false,
    );
  }

  /// Igual que [listarFotosGaleria] pero con alcance de MUNICIPIO (Galería
  /// del UGR rol 6): fotos de todos los responsables del municipio, con el
  /// nombre del autor (`usuario_nombre`, fallback `usuario_login`) para
  /// distinguirlas.
  Future<List<EdanFotoGaleria>> listarFotosGaleriaPorMunicipio({
    required int idMunicipio,
  }) {
    return _fotosGaleria(
      filtroLocalidad: 'fo.id_municipio = ?',
      valor: idMunicipio,
      conAutor: true,
    );
  }

  Future<List<EdanFotoGaleria>> _fotosGaleria({
    required String filtroLocalidad,
    required Object? valor,
    required bool conAutor,
  }) async {
    final db = await _db.database;
    final filas = conAutor
        ? '''
             te.nombre                   AS tipo_evento_nombre,
             COALESCE(fo.usuario_nombre, fo.usuario_login) AS nombre_autor,
             fs.datos_json               AS fila_datos_json,
             v.coordenada_lat            AS vivienda_lat,
             v.coordenada_lon            AS vivienda_lon'''
        : '''
             te.nombre                   AS tipo_evento_nombre,
             fs.datos_json               AS fila_datos_json,
             v.coordenada_lat            AS vivienda_lat,
             v.coordenada_lon            AS vivienda_lon''';
    final rows = await db.rawQuery(
      '''
      SELECT f.uuid_fotografia,
             f.uuid_edan_localidad,
             f.tipo_entidad,
             f.uuid_registro,
             f.ruta_local,
             f.ruta_servidor,
             f.fecha_modificacion,
             fo.localidad                AS nombre_localidad,
             fo.id_edan_localidad_estado AS id_estado_localidad,
$filas
      FROM fotografias f
      JOIN formularios fo
        ON fo.uuid_edan_localidad = f.uuid_edan_localidad
      LEFT JOIN filas_seccion fs
        ON fs.uuid_registro = f.uuid_registro
      LEFT JOIN viviendas v
        ON v.uuid_registro = f.uuid_registro
      LEFT JOIN catalogo_tipos_evento te
        ON te.id_tipo_evento = fo.id_tipo_evento
      WHERE f.borrado_logico = 0
        AND f.is_deleted = 0
        AND $filtroLocalidad
      ORDER BY fo.localidad COLLATE NOCASE ASC, f.fecha_modificacion DESC
      ''',
      [valor],
    );
    return rows.map((r) {
      final coord = _coordenadasFoto(
        r['fila_datos_json'],
        r['vivienda_lat'],
        r['vivienda_lon'],
      );
      return EdanFotoGaleria(
        uuidFotografia: r['uuid_fotografia'] as String,
        uuidEdanLocalidad: r['uuid_edan_localidad'] as String,
        nombreLocalidad: (r['nombre_localidad'] as String?) ?? '',
        idEstadoLocalidad: (r['id_estado_localidad'] as int?) ?? 1,
        tipoEntidad: r['tipo_entidad'] as String?,
        uuidRegistro: r['uuid_registro'] as String?,
        rutaLocal: r['ruta_local'] as String?,
        rutaServidor: r['ruta_servidor'] as String?,
        fechaModificacion: r['fecha_modificacion'] as String?,
        coordenadaLat: coord[0],
        coordenadaLon: coord[1],
        tipoEventoNombre: r['tipo_evento_nombre'] as String?,
        nombreAutor: conAutor ? r['nombre_autor'] as String? : null,
      );
    }).toList();
  }

  /// Coordenadas de la foto = coordenadas de su fila dueña.
  ///
  /// Fuente 1: `filas_seccion.datos_json` (`coordenada_lat/lon`, donde el
  /// wizard deja la captura GPS de la foto — `toFotoData`). Fuente 2 (fallback
  /// y foto de vivienda): columnas `coordenada_lat/lon` de `viviendas`.
  /// Parsing en Dart (no `json_extract` de SQLite) para no depender de JSON1
  /// en Android 8/9. Acepta variantes snake y camel; null si no hay par.
  static List<double?> _coordenadasFoto(
    Object? filaDatosJson,
    Object? viviendaLat,
    Object? viviendaLon,
  ) {
    if (filaDatosJson is String && filaDatosJson.trim().isNotEmpty) {
      try {
        final j = jsonDecode(filaDatosJson);
        if (j is Map) {
          final lat = _aDouble(j['coordenada_lat'] ?? j['coordenadaLat']);
          final lon = _aDouble(j['coordenada_lon'] ?? j['coordenadaLon']);
          if (lat != null && lon != null) return [lat, lon];
        }
      } catch (_) {}
    }
    final vlat = _aDouble(viviendaLat);
    final vlon = _aDouble(viviendaLon);
    if (vlat != null && vlon != null) return [vlat, vlon];
    return [null, null];
  }

  static double? _aDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String && v.isNotEmpty) return double.tryParse(v);
    return null;
  }

  /// Guarda la ruta local de una foto ya descargada (botón «Descargar» de la
  /// Galería). Mismos campos que limpia el motor al descargar en sync.
  Future<void> setFotoRutaLocal(
    String uuidFotografia,
    String rutaLocal,
  ) async {
    final db = await _db.database;
    await db.update(
      'fotografias',
      {
        'ruta_local': rutaLocal,
        'last_error': null,
        'intentos_descarga': 0,
        'fecha_proximo_intento': null,
      },
      where: 'uuid_fotografia = ?',
      whereArgs: [uuidFotografia],
    );
  }

  Future<void> _notifyPendientes() async {
    try {
      final p = await contarLocalidadesPendientes();
      _pendientesController.add(p);
      pendientesNotifier.value = p;
    } catch (_) {
      _pendientesController.add(0);
      pendientesNotifier.value = 0;
    }
  }
}

/// Una foto de la pestaña Galería del rol 7: fila viva de `fotografias` con
/// los datos de su localidad (nombre + estado) traídos por JOIN.
class EdanFotoGaleria {
  final String uuidFotografia;
  final String uuidEdanLocalidad;
  final String nombreLocalidad;

  /// `id_edan_localidad_estado` de la localidad (1-6).
  final int idEstadoLocalidad;

  /// Tabla corta dueña de la foto (`danos_viales`, `vivienda`, `cabecera`…).
  final String? tipoEntidad;

  /// Fila/sección a la que pertenece (para el pie del visor).
  final String? uuidRegistro;

  /// Archivo local en `report_photos/` (null si aún no se bajó).
  final String? rutaLocal;

  /// Path del servidor (`/uploads/reports/…`); permite ver/bajar en remoto.
  final String? rutaServidor;

  final String? fechaModificacion;

  /// Coordenadas de la fila DUEÑA de la foto: el wizard escribe la captura
  /// GPS de la foto en la fila como `coordenada_lat/lon` (`toFotoData`) — o
  /// en las columnas de la vivienda cuando la foto cuelga de una (`viviendas.
  /// coordenada_lat/lon`). Foto y coordenada van siempre juntas.
  final double? coordenadaLat;
  final double? coordenadaLon;

  /// Nombre del tipo de evento de la localidad (catálogo local, por JOIN con
  /// `catalogo_tipos_evento`). Null si el catálogo aún no bajó.
  final String? tipoEventoNombre;

  /// Responsable de la localidad (`usuario_nombre`, con fallback a
  /// `usuario_login`). Solo lo trae la variante por municipio (Galería del
  /// UGR, que ve fotos de TODOS los responsables); la del propio usuario es
  /// null porque el autor siempre es él mismo.
  final String? nombreAutor;

  const EdanFotoGaleria({
    required this.uuidFotografia,
    required this.uuidEdanLocalidad,
    required this.nombreLocalidad,
    required this.idEstadoLocalidad,
    this.tipoEntidad,
    this.uuidRegistro,
    this.rutaLocal,
    this.rutaServidor,
    this.fechaModificacion,
    this.coordenadaLat,
    this.coordenadaLon,
    this.tipoEventoNombre,
    this.nombreAutor,
  });

  /// '−17.78352, −63.18214' con 5 decimales (~1 m) o null si no hay par.
  String? get coordenadaTexto {
    final la = coordenadaLat;
    final lo = coordenadaLon;
    if (la == null || lo == null) return null;
    return '${la.toStringAsFixed(5)}, ${lo.toStringAsFixed(5)}';
  }

  /// True si el archivo local existe de verdad (no basta con la ruta: iOS
  /// reubica el contenedor entre versiones y la ruta absoluta envejece).
  bool get tieneArchivoLocal {
    final r = rutaLocal;
    if (r == null || r.isEmpty) return false;
    try {
      return File(r).existsSync();
    } catch (_) {
      return false;
    }
  }

  bool get tieneRemoto => (rutaServidor ?? '').isNotEmpty;
}
