import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/edan.dart';
import '../database_helper.dart';
import '../edan_secciones_registry.dart';

/// **Fuente única de verdad de las secciones** de un reporte V2.
///
/// El wizard escribe fila a fila en `filas_seccion`; la cabecera en
/// `formularios` guarda además un *snapshot* del modelo en `datos_json`
/// (`_formularioToRow` → `loc.toJson()`). Hay reportes cuyos datos viven
/// **solo** en ese snapshot y nunca llegaron a `filas_seccion` (los creó el
/// camino legado `POST /documento`, que persistía vía `updateLocalidad`).
///
/// Ese desdoblamiento es la causa de que el JSON de `/completo` marcara las
/// 14 `imp_*` en `false` "sin datos" mientras la tarjeta del listado sí los
/// contaba. Este resolutor une ambas fuentes con una prioridad estricta
/// **por tipo de sección** (nunca mezcla las dos, para no duplicar filas):
///
/// 1. `filas_seccion`  — verdad V2, authoritative.
/// 2. `formularios.datos_json` — rescate del snapshot de cabecera.
///
/// El resultado ya está en la forma que acepta `POST /formularios/completo`
/// (para el caso 2 se reutiliza `EdanLocalidad.toApiJson()`, que aplica las
/// transformaciones propias de cada sección: `_impactoPoblacionApi()`,
/// `_danosViviendaApi()`, `_proteccionApi()`), con `uuid_registro` inyectado.
///
/// Regla que garantiza: **flag `imp_*` en `true` ⟺ al menos una fila** de esa
/// sección en el payload (contrato `FormularioCompletoUpsert`, §20.1).
class EdanSeccionesFuente {
  EdanSeccionesFuente({DatabaseHelper? dbHelper})
      : _db = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _db;

  /// Filas de sección por `rutaV2`, con `uuid_registro` presente en todas.
  ///
  /// [formRow] es la fila de `formularios` ya leída (evita un segundo query
  /// cuando el llamador la tiene a mano; si es `null` se busca por [uuid]).
  /// Con [executor] las lecturas corren dentro de la transacción del llamador
  /// (Etapa 3: sin esto, leer con `_db.database` dentro de un `transaction`
  /// abierto bloquea la conexión — deadlock).
  Future<Map<String, List<Map<String, dynamic>>>> seccionesConDatos(
    String uuid, {
    Map<String, Object?>? formRow,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _db.database;
    final out = <String, List<Map<String, dynamic>>>{};

    // ── 1) filas_seccion (verdad V2) ────────────────────────────────────
    final filas = await db.query(
      'filas_seccion',
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuid],
    );
    for (final f in filas) {
      // Tolerancia: filas viejas del pull pueden traer `tipo` con nombre de
      // TABLA (`danos_agricultura`); se normaliza a ruta para agrupar. El
      // reparo de `_onOpen` + `_aplicarSeccionPull` ya escriben ruta, esto es
      // red de seguridad para datos residuales.
      final tipo =
          EdanSeccionesRegistry.rutaDesdeTabla(f['tipo'] as String);
      final datos = _decodificar(f['datos_json']);
      if (datos == null) continue;
      datos['uuid_registro'] = f['uuid_registro'];
      _normalizarFotografia(datos);
      (out[tipo] ??= []).add(datos);
    }

    // ── 2) snapshot de cabecera (datos_json) para los tipos sin filas V2 ─
    final fila =
        formRow ?? await _leerFormulario(uuid, executor: executor) ?? const <String, Object?>{};
    final snap = snapshotDe(fila);
    if (snap != null) {
      // Un `EdanLocalidad()` recién construido VIENE con objetos por defecto
      // (`necesidadSalud`, `necesidadHumanitaria`, `proteccion` con sus filas,
      // `impactoPoblacion`…), así que "la clave existe" NO implica "hay datos".
      // Se usa la única definición que tiene la app de "sección con contenido":
      // `recalcularFlagsImpacto()`, y se rescata solo si su flag detallada
      // `imp_*` queda en `true`. Evita reactivar secciones vacías (que el
      // servidor castiga con 400 por la regla flag↔fila).
      snap.recalcularFlagsImpacto();
      final api = snap.toApiJson();
      final rutas = rutasConDatosEnSnapshot(snap, api: api);
      for (final desc in EdanSeccionesRegistry.secciones) {
        if (out.containsKey(desc.rutaV2)) continue;
        if (!rutas.contains(desc.rutaV2)) continue;
        final rescatadas = _filasDesde(api[desc.llaveJson]);
        if (rescatadas.isEmpty) continue;
        // Mismo contrato que el guardado V2 (`_guardarFilasTx`): las filas
        // sembradas vacías no se rescatan ni se emiten. El zip por posición
        // entre las filas JSON y la lista del modelo es válido porque
        // `toApiJson` serializa esas listas mapeadas en orden; si la sección
        // tiene una transformación que cambia el largo (protección con
        // filtrado), el zip no aplica y no se filtra — nunca se adivina.
        final itemsModelo = _itemsDeRuta(desc.rutaV2, snap);
        final emitidas = itemsModelo != null &&
                itemsModelo.length == rescatadas.length
            ? <Map<String, dynamic>>[
                for (var i = 0; i < rescatadas.length; i++)
                  if (filaSeccionConDatos(desc.rutaV2, itemsModelo[i]))
                    rescatadas[i],
              ]
            : rescatadas;
        if (emitidas.isEmpty) continue;
        for (var i = 0; i < emitidas.length; i++) {
          final item = emitidas[i];
          // El contrato identifica cada fila por `uuid_registro`; el snapshot
          // solo conoce `id_seccion`. Si no trae ninguno se deriva un uuid
          // DETERMINISTA (no aleatorio: un `/completo` re-empujado no debe
          // duplicar la fila en el servidor).
          item['uuid_registro'] = _idDeFila(item, uuid, desc.rutaV2, i);
          _normalizarFotografia(item);
          (out[desc.rutaV2] ??= []).add(item);
        }
      }
    }

    out.removeWhere((_, v) => v.isEmpty);
    return out;
  }

  /// Rutas v2 que tienen datos reales (unión de las dos fuentes). Es la base
  /// de las 14 flags `imp_*` de sección; los grupos (`grup_*`) se derivan
  /// después con la matriz, aquí solo mandan las secciones.
  Future<List<String>> rutasConDatos(
    String uuid, {
    Map<String, Object?>? formRow,
    DatabaseExecutor? executor,
  }) async =>
      (await seccionesConDatos(uuid, formRow: formRow, executor: executor))
          .keys
          .toList();

  /// Extrae las filas por `rutaV2` de un documento en forma API (el
  /// `GET /formularios/{uuid}/completo`, que devuelve cada sección ya con las
  /// transformaciones de servidor aplicadas: `_impactoPoblacionApi`,
  /// `_danosViviendaApi`…).
  ///
  /// A diferencia de [seccionesConDatos] NO pasa por el modelo Dart: el
  /// documento ya viene en la forma plana que guarda `filas_seccion`, así que
  /// cada sección se lee directo de su clave [EdanSeccionDescriptor.llaveJson]
  /// (1:N como lista, 1:1 como objeto). Cada fila conserva su
  /// `uuid_registro` del servidor, o se deriva uno DETERMINISTA si no trae
  /// (mismo criterio que el rescate de snapshot).
  ///
  /// `danos-vivienda` llega como objeto 1:1 con `viviendas[]` anidadas
  /// (§20.4); aquí se devuelve TAL CUAL y le corresponde al llamador
  /// (`_normalizarDocCompleto`) desanidarlas hacia la tabla `viviendas`.
  static Map<String, List<Map<String, dynamic>>> filasDesdeDocumentoApi(
    Map<String, dynamic> doc,
    String uuid,
  ) {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final desc in EdanSeccionesRegistry.secciones) {
      final filas = _filasDesde(doc[desc.llaveJson]);
      if (filas.isEmpty) continue;
      for (var i = 0; i < filas.length; i++) {
        final item = filas[i];
        item['uuid_registro'] = _idDeFila(item, uuid, desc.rutaV2, i);
        _normalizarFotografia(item);
        (out[desc.rutaV2] ??= []).add(item);
      }
    }
    return out;
  }

  /// Reconstruye el modelo a partir del `datos_json` de la cabecera.
  ///
  /// Devuelve `null` si la fila no trae snapshot o si está corrupto (un blob
  /// ilegible no debe tumbar el sync: simplemente no hay segunda fuente).
  static EdanLocalidad? snapshotDe(Map<String, Object?>? formRow) {
    final crudo = formRow?['datos_json'];
    if (crudo is! String || crudo.isEmpty) return null;
    try {
      final datos = jsonDecode(crudo);
      if (datos is! Map) return null;
      return EdanLocalidad.fromJson(Map<String, dynamic>.from(datos));
    } catch (_) {
      return null;
    }
  }

  /// Rutas v2 que el snapshot de cabecera considera "con datos".
  ///
  /// Un `EdanLocalidad()` recién construido trae objetos/arrays POR DEFECTO
  /// (`necesidadSalud`, `necesidadHumanitaria`, `proteccion` con sus grupos,
  /// `impactoPoblacion`…), así que "la clave existe" NO significa "hay datos".
  /// La única definición que tiene la app de "sección con contenido" es
  /// [EdanLocalidad.recalcularFlagsImpacto], así que se reutiliza: solo se
  /// rescatan las secciones cuyo flag detallado `imp_*` queda en `true`.
  /// Evita reactivar secciones vacías, que el servidor castiga con 400 por la
  /// regla flag↔fila (§20.1).
  static Set<String> rutasConDatosEnSnapshot(
    EdanLocalidad? snap, {
    Map<String, dynamic>? api,
  }) {
    if (snap == null) return const {};
    final documento = api ?? (snap..recalcularFlagsImpacto()).toApiJson();
    return {
      for (final desc in EdanSeccionesRegistry.secciones)
        if (documento['imp_${desc.rutaV2.replaceAll('-', '_')}'] == true)
          desc.rutaV2,
    };
  }

  Future<Map<String, Object?>?> _leerFormulario(String uuid,
      {DatabaseExecutor? executor}) async {
    final db = executor ?? await _db.database;
    final rows = await db.query(
      'formularios',
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Map<String, dynamic>? _decodificar(Object? crudo) {
    if (crudo is! String || crudo.isEmpty) return null;
    try {
      final m = jsonDecode(crudo);
      return m is Map ? Map<String, dynamic>.from(m) : null;
    } catch (_) {
      return null;
    }
  }

  /// Una sección 1:N llega como `List`, una 1:1 como `Map`. Aquí ambas se
  /// uniformizan en lista de filas ya clonadas (para no mutar el snapshot).
  static List<Map<String, dynamic>> _filasDesde(Object? valor) {
    if (valor is List) {
      return valor
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    if (valor is Map) return [Map<String, dynamic>.from(valor)];
    return const [];
  }

  /// Lista del modelo correspondiente a una ruta 1:N, en el MISMO orden en
  /// que `EdanLocalidad.toApiJson()` serializa sus filas (zip por posición
  /// para el filtro de rescate). `null` para rutas 1:1/no listadas.
  static List<dynamic>? _itemsDeRuta(String rutaV2, EdanLocalidad l) {
    switch (rutaV2) {
      case 'impacto-poblacion':
        return l.impactoPoblacion;
      case 'salud-establecimientos':
        return l.establecimientosSalud;
      case 'danos-viales':
        return l.danosViales;
      case 'danos-infra-publica':
        return l.danosInfraPublica;
      case 'servicios-basicos':
        return l.serviciosBasicos;
      case 'unidades-educativas':
        return l.unidadesEducativas;
      case 'danos-vivienda':
        return l.danosVivienda;
      case 'danos-agricultura':
        return l.danosAgricultura;
      case 'danos-pecuarios':
        return l.danosPecuarios;
      case 'infra-productiva':
        return l.infraProductiva;
      case 'proteccion':
        return l.proteccion;
      default:
        return null;
    }
  }

  /// Identificador de fila de un snapshot: `uuid_registro` válido → ese;
  /// `id_seccion` SOLO si ya es uuid válido (un prefijo legacy como `po_…` se
  /// descarta: mandarlo como `uuid_registro` daría 422) → uuid determinista.
  ///
  /// En las secciones de catálogo (impacto = `id_grupo_etario`, protección =
  /// `id_grupo_vulnerable_catalogo`, servicios = `tipo`) el uuid determinista
  /// se deriva del identificador de catálogo, NO de la posición: así
  /// reordenar o filtrar la lista entre dos envíos nunca hace que un mismo
  /// `uuid_registro` cambie de fila (daño/foto "mudados" de un slot del
  /// catálogo a otro) y coincide con el del set exacto sintético
  /// ([uuidFilaSintetica]). Sin identificador de catálogo conocido, cae al
  /// índice (comportamiento histórico para listas libres tipo viales).
  static String _idDeFila(
      Map<String, dynamic> item, String uuid, String tipo, int indice) {
    final directo = item['uuid_registro']?.toString() ?? '';
    if (directo.isNotEmpty && _esUuid(directo)) return directo;
    final legacy = item['id_seccion']?.toString() ?? '';
    if (legacy.isNotEmpty && _esUuid(legacy)) return legacy;
    final cat = _identificadorCatalogo(item, tipo);
    if (cat != null) {
      return _uuidDeterminista('$uuid|$tipo|cat|$cat');
    }
    return _uuidDeterminista('$uuid|$tipo|$indice');
  }

  /// Clave canónica de catálogo de una fila JSON, si la sección la tiene.
  static String? _identificadorCatalogo(
      Map<String, dynamic> item, String tipo) {
    switch (tipo) {
      case 'impacto-poblacion':
        final id = item['id_grupo_etario'];
        return id == null ? null : '$id';
      case 'proteccion':
        final id = item['id_grupo_vulnerable_catalogo'];
        return id == null ? null : '$id';
      case 'servicios-basicos':
        final t = item['tipo']?.toString() ?? '';
        return t.isEmpty ? null : t;
      default:
        return null;
    }
  }

  static bool _esUuid(String v) => RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
        r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(v);

  /// UUID determinista para una fila sintética de catálogo (padding de
  /// `impacto_poblacion`/`proteccion` en `/completo`, §20.10.E). Estable entre
  /// corridas: re-enviar el mismo documento no crea filas duplicadas en el
  /// servidor. La semilla usa el id de catálogo (no el índice) para no chocar
  /// con las filas derivadas por [_idDeFila].
  static String uuidFilaSintetica(String uuid, String tipo, int id) =>
      _uuidDeterminista('$uuid|$tipo|cat|$id');

  /// UUID v4 en formato canónico a partir de sha256([semilla]). Estable entre
  /// corridas, para que re-enviar el mismo snapshot no cree filas duplicadas.
  static String _uuidDeterminista(String semilla) {
    final hex = sha256.convert(utf8.encode(semilla)).toString();
    final b = List<String>.generate(16, (i) => hex.substring(i * 2, i * 2 + 2));
    b[6] = '4${b[6][1]}'; // versión 4
    final variante = 0x80 | (int.parse(b[8], radix: 16) & 0x3f);
    b[8] = variante.toRadixString(16).padLeft(2, '0'); // RFC 4122
    final s = b.join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}'
        '-${s.substring(16, 20)}-${s.substring(20, 32)}';
  }

  /// `POST /completo` acepta `fotografia` solo como **path del servidor**
  /// (`/uploads/...`). Un path local (`/data/...`) rescatado de un snapshot no
  /// debe viajar: se omite la clave y la foto sigue su propio camino de subida
  /// (`fotografias` + cola del motor), igual que hace
  /// `_subirFotosLocalesDelDocumento` en el documento legado.
  static void _normalizarFotografia(Map<String, dynamic> datos) {
    final foto = datos['fotografia']?.toString() ?? '';
    if (foto.isEmpty) return;
    if (foto.startsWith('/uploads/')) return;
    datos.remove('fotografia');
  }
}
