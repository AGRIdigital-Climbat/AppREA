import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../config/api_config.dart';
import '../api_service.dart';
import '../app_logger.dart';
import '../sync_debug_collector.dart';
import '../sync_debug_config.dart';

/// Detalle de un conflicto 409 devuelto por el servidor.
///
/// El spec vivo (PLAN §19.4) devuelve `detail` como objeto con la versión del
/// servidor, la versión enviada por el cliente y el registro completo del
/// servidor.
class EdanApiConflict implements Exception {
  final int statusCode;
  final int versionServidor;
  final int versionCliente;
  final Map<String, dynamic> registroServidor;
  final String message;

  const EdanApiConflict({
    required this.statusCode,
    required this.versionServidor,
    required this.versionCliente,
    required this.registroServidor,
    this.message = 'Conflicto de versiones',
  });

  @override
  String toString() =>
      'EdanApiConflict($statusCode): server v$versionServidor vs client v$versionCliente';
}

/// 409 de `POST /formularios/completo` cuando el documento YA existe
/// (§20.15, 2026-10-16): NO es un conflicto de versiones (ya no existen),
/// es la señal de "usa PUT". El motor lo convierte en PUT y reintenta.
class EdanPostSoloCreacion implements Exception {
  final String detail;

  const EdanPostSoloCreacion(this.detail);

  @override
  String toString() => 'EdanPostSoloCreacion: $detail';

  /// `true` si el detail es el 409 "SOLO creación → use PUT".
  static bool esSenalUsaPut(String detail) {
    final d = detail.toLowerCase();
    return d.contains('solo creaci') || d.contains('use put');
  }
}

/// Error genérico de la API v2 (400, 403, 404, 422, 5xx, red).
class EdanApiError implements Exception {
  final int? statusCode;
  final String detail;
  final dynamic rawBody;

  const EdanApiError({
    this.statusCode,
    required this.detail,
    this.rawBody,
  });

  @override
  String toString() => 'EdanApiError($statusCode): $detail';
}

/// Resultado desempaquetado del envelope `{success, message, data, total}`.
///
/// `resumen` lleva agregados opcionales cuando el endpoint los incluye
/// (p. ej. `GET /formularios/estados` → `{items, resumen, total}`).
class EdanApiResult<T> {
  final bool success;
  final String? message;
  final T? data;
  final int? total;
  final Map<String, dynamic>? resumen;
  final int statusCode;
  final Map<String, dynamic> rawBody;

  const EdanApiResult({
    required this.success,
    this.message,
    this.data,
    this.total,
    this.resumen,
    required this.statusCode,
    required this.rawBody,
  });

  bool get ok => success && statusCode >= 200 && statusCode < 300;
}

/// Cliente de las 21 operaciones nuevas de `/api/v2/edan/*`.
///
/// No maneja estado local; solo traduce llamadas HTTP al envelope v2 y a
/// excepciones tipadas. El motor de sync (`EdanSyncEngineV2`) es el único
/// que debe usar esta clase.
class EdanApiV2 {
  EdanApiV2({
    http.Client? httpClient,
    this.baseUrl = ApiConfig.edanEndpoint,
  }) : _client = httpClient ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  // ── Headers ──

  Map<String, String> _headers({String? idempotencyKey}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final token = ApiService.instance.token;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      headers['Idempotency-Key'] = idempotencyKey;
    }
    return headers;
  }

  // ── Cabecera / formularios ──

  /// Claves que NUNCA viajan en POST (contrato §19-20, LWW 2026-10-16):
  /// ids numéricos, `version` (ya no se envía en ningún método),
  /// `fotografia` (espejo server), `grup_*` (derivados),
  /// `fecha_modificacion` (la fija el server).
  static const _forbiddenPostKeys = {
    'id_seccion',
    'version',
    'fotografia',
    'fecha_modificacion',
  };

  static bool _isForbiddenPostKey(String k) {
    if (_forbiddenPostKeys.contains(k)) return true;
    if (k.startsWith('grup_')) return true;
    if (k.startsWith('id_') && k != 'id_grupo_etario' && k != 'id_grupo_vulnerable_catalogo' && k != 'id_cultivo' && k != 'id_especie') return true;
    // ids de catálogo permitidos explícitos arriba; el resto (id_dano_*,
    // id_servicio_*, id_municipio? no: id_municipio SÍ es escribible en cabecera)
    return false;
  }

  /// Sanea un payload de POST (upsert idempotente por uuid).
  /// Quita ids/version/fotografia/grup_* sin mutar el original.
  /// `id_municipio/id_tipo_evento/...` de cabecera se conservan (ver allowCabeceraIds).
  static Map<String, dynamic> sanitizePostPayload(
    Map<String, dynamic> payload, {
    bool esCabecera = false,
  }) {
    final out = Map<String, dynamic>.from(payload);
    for (final k in List<String>.from(out.keys)) {
      if (k == 'id_municipio' ||
          k == 'id_tipo_evento' ||
          k == 'id_tipo_localidad' ||
          k == 'id_edan_localidad_estado' ||
          k == 'id_departamento' ||
          k == 'id_provincia' ||
          k == 'id_usuario') {
        if (!esCabecera) out.remove(k);
        continue;
      }
      if (_isForbiddenPostKey(k)) out.remove(k);
    }
    return out;
  }

  /// `POST /formularios`
  Future<EdanApiResult<Map<String, dynamic>>> crearFormulario(
    Map<String, dynamic> payload, {
    String? idempotencyKey,
  }) async {
    final res = await _post(
      '$baseUrl/formularios',
      sanitizePostPayload(payload, esCabecera: true),
      idempotencyKey: idempotencyKey,
    );
    return _unpack<Map<String, dynamic>>(res, (d) => d ?? {});
  }

  /// `PUT /formularios/{uuid}` (LWW 2026-10-16: sin `version`; gana el último).
  Future<EdanApiResult<Map<String, dynamic>>> actualizarFormulario(
    String uuid,
    Map<String, dynamic> payload, {
    String? idempotencyKey,
  }) async {
    final res = await _put('$baseUrl/formularios/$uuid', payload,
        idempotencyKey: idempotencyKey);
    return _unpack<Map<String, dynamic>>(res, (d) => d ?? {});
  }

  /// `GET /formularios/{uuid o id}` — ambos valen en path (contrato §19.3).
  /// [useId] solo decide el label del log; la ruta siempre es path, nunca query.
  ///
  /// Forma vigente (2026-10-14): `data = {cabecera, secciones_resumen}`.
  /// Devuelve la cabecera plana con `secciones_resumen` preservado bajo esa
  /// misma clave para no perder el conteo por sección.
  Future<EdanApiResult<Map<String, dynamic>>> obtenerFormulario(
    String uuidOrId, {
    @Deprecated('Sin efecto: uuid e id van siempre en path')
    bool useId = false,
  }) async {
    final res = await _get('$baseUrl/formularios/$uuidOrId');
    return _unpack<Map<String, dynamic>>(res, (d) {
      final doc = d is Map<String, dynamic> ? d : <String, dynamic>{};
      final cab = doc['cabecera'];
      if (cab is Map<String, dynamic>) {
        return <String, dynamic>{
          ...cab,
          if (doc['secciones_resumen'] != null)
            'secciones_resumen': doc['secciones_resumen'],
        };
      }
      if (cab is Map) {
        return <String, dynamic>{
          ...Map<String, dynamic>.from(cab),
          if (doc['secciones_resumen'] != null)
            'secciones_resumen': doc['secciones_resumen'],
        };
      }
      return doc;
    });
  }

  /// `GET /formularios` — documentos completos (`cabecera` + secciones),
  /// paginados (`limit`/`skip`, `todos=false`) y con scope por geografía.
  ///
  /// `modo` (query `modo`): `comprimido` (default del servidor: omite
  /// secciones sin filas) o `completo` (las 14 secciones siempre, igual que
  /// `GET /formularios/{uuid}/completo` sin parámetros).
  Future<EdanApiResult<List<Map<String, dynamic>>>> listarFormularios({
    int skip = 0,
    int limit = 100,
    bool todos = false,
    int? idDepartamento,
    int? idProvincia,
    int? idMunicipio,
    String? localidad,
    String? modo,
  }) async {
    final query = <String, String>{
      'skip': '$skip',
      'limit': '$limit',
      'todos': '$todos',
    };
    if (idDepartamento != null) query['id_departamento'] = '$idDepartamento';
    if (idProvincia != null) query['id_provincia'] = '$idProvincia';
    if (idMunicipio != null) query['id_municipio'] = '$idMunicipio';
    if (localidad != null && localidad.isNotEmpty) {
      query['localidad'] = localidad;
    }
    if (modo != null && modo.isNotEmpty) query['modo'] = modo;
    final uri = Uri.parse('$baseUrl/formularios').replace(queryParameters: query);
    final res = await _get(uri.toString());
    return _unpackList<Map<String, dynamic>>(res, (e) => e as Map<String, dynamic>);
  }

  /// `DELETE /formularios/{uuid}`
  Future<EdanApiResult<void>> eliminarFormulario(String uuid) async {
    final res = await _delete('$baseUrl/formularios/$uuid');
    return _unpackVoid(res);
  }

  // ── Formulario completo (todo-en-uno) ──

  /// `POST /formularios/completo` — **SOLO creación** (§20.15, 2026-10-16).
  /// Guarda cabecera + 14 `imp_*` + las 14 secciones + `viviendas[]` en
  /// **un solo request**. Si el uuid ya existe → **409** (`EdanPostSoloCreacion`:
  /// "usa PUT", no fatal). Para editar use [actualizarFormularioCompleto].
  ///
  /// Contrato (PLAN_APIS_V2_EDAN §20.15):
  /// * **No borra**: las filas ausentes del payload se conservan en el
  ///   servidor. Los borrados van por `eliminarSeccion`/`eliminarVivienda`.
  /// * Las 14 `imp_*` son **obligatorias** (faltante → 400, antes de mirar
  ///   existencia y sin escrituras).
  /// * `grup_*` **no se envían** (el servidor los deriva).
  /// * Regla flag↔fila: flag `true` exige filas (enviadas o existentes) o
  ///   el servidor responde **400 atómico**; filas existentes fuerzan el
  ///   flag a `true`.
  Future<EdanApiResult<Map<String, dynamic>>> crearFormularioCompleto(
    Map<String, dynamic> payload, {
    String? idempotencyKey,
  }) async {
    final res = await _post('$baseUrl/formularios/completo', payload,
        idempotencyKey: idempotencyKey);
    return _unpack<Map<String, dynamic>>(res, (d) => d ?? {});
  }

  /// `PUT /formularios/completo` — **edición** del documento completo
  /// (§20.15, 2026-10-16). Mismo JSON que el POST (uuid obligatorio en el
  /// body). **404** si el uuid no existe (PUT nunca crea); **400** por reglas
  /// estáticas (evaluadas primero); **403** por rol/scope.
  ///
  /// Respuesta `data`: `{hubo_cambios, cambios[], resultados, aplicados,
  /// conflictos: 0, errores, formulario}`. `hubo_cambios:false` = no-op
  /// total (cero escrituras, sin bump de `fecha_modificacion`).
  Future<EdanApiResult<Map<String, dynamic>>> actualizarFormularioCompleto(
    Map<String, dynamic> payload, {
    String? idempotencyKey,
  }) async {
    final res = await _put('$baseUrl/formularios/completo', payload,
        idempotencyKey: idempotencyKey);
    return _unpack<Map<String, dynamic>>(res, (d) => d ?? {});
  }

  /// `GET /formularios/estados` — listado ligero incremental para sync.
  ///
  /// Devuelve solo `id + uuid + estado + pendiente_* + tiene_cambios`
  /// por fila (sin secciones, sin `version` — LWW 2026-10-16). Con `fechaModificacionDesde` el servidor marca
  /// `tiene_cambios=true` en las filas modificadas después de esa fecha, lo
  /// que permite al motor decidir qué documentos bajar con
  /// `GET /formularios/{uuid}/completo`.
  ///
  /// Parámetros: `limit`, `skip`, `todos`, filtros geográficos (uno a la vez:
  /// `id_departamento`, `id_provincia`, `id_municipio`), `id_edanLocalidadEstado`,
  /// `localidad`, `fechaModificacionDesde`.
  Future<EdanApiResult<List<Map<String, dynamic>>>> obtenerEstadosFormularios({
    int limit = 200,
    int skip = 0,
    bool todos = false,
    int? idDepartamento,
    int? idProvincia,
    int? idMunicipio,
    String? localidad,
    int? idEdanLocalidadEstado,
    String? fechaModificacionDesde,
  }) async {
    final query = <String, String>{
      'limit': '$limit',
      'skip': '$skip',
      'todos': '$todos',
    };
    if (idDepartamento != null) query['id_departamento'] = '$idDepartamento';
    if (idProvincia != null) query['id_provincia'] = '$idProvincia';
    if (idMunicipio != null) query['id_municipio'] = '$idMunicipio';
    if (localidad != null && localidad.isNotEmpty) {
      query['localidad'] = localidad;
    }
    if (idEdanLocalidadEstado != null) {
      query['id_edan_localidad_estado'] = '$idEdanLocalidadEstado';
    }
    if (fechaModificacionDesde != null && fechaModificacionDesde.isNotEmpty) {
      query['fecha_modificacion_desde'] = fechaModificacionDesde;
    }
    final uri = Uri.parse('$baseUrl/formularios/estados')
        .replace(queryParameters: query);
    final res = await _get(uri.toString());
    return _unpackList<Map<String, dynamic>>(res, (e) => e as Map<String, dynamic>);
  }

  /// Resumen agregado V2 para indicadores (`{por_estado[], por_grupo[]}`).
  ///
  /// Reutiliza `GET /formularios/estados` con `limit=1`: el `resumen` del
  /// servidor cubre todo el alcance (no solo la página), así el payload es
  /// mínimo. Reemplaza al legacy `GET /localidades/mis-resumen` en el flujo
  /// RESP. Devuelve `null` si el servidor no trae resumen.
  Future<Map<String, dynamic>?> obtenerResumenEstados() async {
    final res = await obtenerEstadosFormularios(limit: 1, todos: false);
    return res.resumen;
  }

  /// `GET /formularios/{uuid o id}/completo[?comprimido=true]` — documento
  /// anidado: `cabecera` (14 `imp_*` + 9 `grup_*` planos) + las 14 secciones
  /// + `fotos[]` (solo activas) + `danos_vivienda.viviendas[]`.
  /// Sin nodo `grupos` desde 2026-10-14 (las planas van sincronizadas).
  ///
  /// `comprimido=true` omite las secciones sin filas (útil para refrescar
  /// badges sin descargar el documento entero).
  Future<EdanApiResult<Map<String, dynamic>>> obtenerFormularioCompleto(
    String uuidOrId, {
    @Deprecated('Sin efecto: uuid e id van siempre en path')
    bool useId = false,
    bool comprimido = false,
  }) async {
    final path = '$baseUrl/formularios/$uuidOrId/completo';
    // Sin `comprimido` NO se agregan query params: `replace(queryParameters: {})
    // emitiría un `?` colgado (`/completo?`), visible en el depurador de sync.
    final uri = Uri.parse(path).replace(
        queryParameters:
            comprimido ? const {'comprimido': 'true'} : null);
    final res = await _get(uri.toString());
    return _unpack<Map<String, dynamic>>(res, (d) => d ?? {});
  }

  // ── Secciones ──

  String _seccionBase(String uuidLocalidad, String tipo) =>
      '$baseUrl/formularios/$uuidLocalidad/secciones/$tipo';

  /// `POST /{uuid_loc}/secciones/{tipo}` (upsert por `uuid_registro`).
  /// [payload] puede ser un mapa o una lista de mapas.
  /// Sanea ids/version/fotografia automáticamente (defensa en profundidad:
  /// el server responde 400 si llegan).
  Future<EdanApiResult<Map<String, dynamic>>> upsertSeccion(
    String uuidLocalidad,
    String tipo,
    dynamic payload, {
    String? idempotencyKey,
  }) async {
    dynamic clean = payload;
    if (payload is Map<String, dynamic>) {
      clean = sanitizePostPayload(payload);
    } else if (payload is Map) {
      clean = sanitizePostPayload(Map<String, dynamic>.from(payload));
    } else if (payload is List) {
      clean = payload
          .map((e) => e is Map
              ? sanitizePostPayload(Map<String, dynamic>.from(e))
              : e)
          .toList();
    }
    final res = await _post(_seccionBase(uuidLocalidad, tipo), clean,
        idempotencyKey: idempotencyKey);
    return _unpack<Map<String, dynamic>>(res, (d) => d ?? {});
  }

  /// `PUT /{uuid_loc}/secciones/{tipo}/{uuid_fila}`
  Future<EdanApiResult<Map<String, dynamic>>> actualizarSeccion(
    String uuidLocalidad,
    String tipo,
    String uuidFila,
    Map<String, dynamic> payload, {
    String? idempotencyKey,
  }) async {
    final res = await _put(
      '${_seccionBase(uuidLocalidad, tipo)}/$uuidFila',
      payload,
      idempotencyKey: idempotencyKey,
    );
    return _unpack<Map<String, dynamic>>(res, (d) => d ?? {});
  }

  /// `GET /{uuid_loc}/secciones/{tipo}` o `/{uuid_fila}`.
  Future<EdanApiResult<List<Map<String, dynamic>>>> obtenerSeccion(
    String uuidLocalidad,
    String tipo, {
    String? uuidFila,
  }) async {
    final path = uuidFila == null
        ? _seccionBase(uuidLocalidad, tipo)
        : '${_seccionBase(uuidLocalidad, tipo)}/$uuidFila';
    final res = await _get(path);
    return _unpackList<Map<String, dynamic>>(res, (e) => e as Map<String, dynamic>);
  }

  /// `DELETE /{uuid_loc}/secciones/{tipo}/{uuid_fila}` (solo 1:N).
  Future<EdanApiResult<void>> eliminarSeccion(
    String uuidLocalidad,
    String tipo,
    String uuidFila,
  ) async {
    final res = await _delete(
      '${_seccionBase(uuidLocalidad, tipo)}/$uuidFila',
    );
    return _unpackVoid(res);
  }

  // ── Viviendas ──

  String _viviendaBase(String uuidLocalidad, String uuidDanoVivienda) =>
      '$baseUrl/formularios/$uuidLocalidad/secciones/danos-vivienda/$uuidDanoVivienda/viviendas';

  /// `POST …/viviendas`
  Future<EdanApiResult<Map<String, dynamic>>> crearVivienda(
    String uuidLocalidad,
    String uuidDanoVivienda,
    Map<String, dynamic> payload, {
    String? idempotencyKey,
  }) async {
    final res = await _post(_viviendaBase(uuidLocalidad, uuidDanoVivienda),
        sanitizePostPayload(payload),
        idempotencyKey: idempotencyKey);
    return _unpack<Map<String, dynamic>>(res, (d) => d ?? {});
  }

  /// `PUT …/viviendas/{uuid_v}`
  Future<EdanApiResult<Map<String, dynamic>>> actualizarVivienda(
    String uuidLocalidad,
    String uuidDanoVivienda,
    String uuidVivienda,
    Map<String, dynamic> payload, {
    String? idempotencyKey,
  }) async {
    final res = await _put(
      '${_viviendaBase(uuidLocalidad, uuidDanoVivienda)}/$uuidVivienda',
      payload,
      idempotencyKey: idempotencyKey,
    );
    return _unpack<Map<String, dynamic>>(res, (d) => d ?? {});
  }

  /// `GET …/viviendas[/{uuid_v}]`
  Future<EdanApiResult<List<Map<String, dynamic>>>> obtenerViviendas(
    String uuidLocalidad,
    String uuidDanoVivienda, {
    String? uuidVivienda,
  }) async {
    final path = uuidVivienda == null
        ? _viviendaBase(uuidLocalidad, uuidDanoVivienda)
        : '${_viviendaBase(uuidLocalidad, uuidDanoVivienda)}/$uuidVivienda';
    final res = await _get(path);
    return _unpackList<Map<String, dynamic>>(res, (e) => e as Map<String, dynamic>);
  }

  /// `DELETE …/viviendas/{uuid_v}`
  Future<EdanApiResult<void>> eliminarVivienda(
    String uuidLocalidad,
    String uuidDanoVivienda,
    String uuidVivienda,
  ) async {
    final res = await _delete(
      '${_viviendaBase(uuidLocalidad, uuidDanoVivienda)}/$uuidVivienda',
    );
    return _unpackVoid(res);
  }

  // ── Fotos ──

  /// `POST /fotografias` multipart.
  Future<EdanApiResult<Map<String, dynamic>>> subirFotografia({
    required String uuidFotografia,
    required String tipoEntidad,
    required String uuidRegistro,
    required File archivo,
    String? sha256,
  }) async {
    final url = '$baseUrl/fotografias';
    final request = http.MultipartRequest('POST', Uri.parse(url))
      ..headers['Authorization'] = _headers()['Authorization'] ?? ''
      ..fields['uuid_fotografia'] = uuidFotografia
      ..fields['tipo_entidad'] = tipoEntidad
      ..fields['uuid_registro'] = uuidRegistro;
    if (sha256 != null && sha256.isNotEmpty) {
      request.fields['sha256'] = sha256;
    }
    request.files.add(await http.MultipartFile.fromPath(
      'archivo',
      archivo.path,
      contentType: _mediaType(archivo.path),
    ));

    final res = await _instrumentedMultipart(
      url,
      'uuid_fotografia=$uuidFotografia · tipo_entidad=$tipoEntidad · '
      'uuid_registro=$uuidRegistro · archivo=${archivo.path}'
      '${sha256 != null && sha256.isNotEmpty ? ' · sha256=$sha256' : ''}',
      [archivo.path],
      () async {
        final streamed = await _client.send(request);
        return http.Response.fromStream(streamed);
      },
    );
    return _unpack<Map<String, dynamic>>(res, (d) => d ?? {});
  }

  /// `GET /fotografias/{uuid}`
  Future<EdanApiResult<Map<String, dynamic>>> obtenerFotografia(String uuid) async {
    final res = await _get('$baseUrl/fotografias/$uuid');
    return _unpack<Map<String, dynamic>>(res, (d) => d ?? {});
  }

  /// `DELETE /fotografias/{uuid}` (borrado lógico server-side).
  Future<EdanApiResult<void>> eliminarFotografia(String uuid) async {
    final res = await _delete('$baseUrl/fotografias/$uuid');
    return _unpackVoid(res);
  }

  /// Descarga los BYTES de una foto del servidor con los endpoints
  /// oficiales: metadatos por `GET /fotografias/{uuid_foto}` y bytes por
  /// URL estática (`host + ruta_archivo`, verificado en vivo 2026-10-15:
  /// HTTP 200 + bytes + `Content-Type: image/png`).
  ///
  /// Se usa en la recuperación de un dispositivo nuevo: el pull trae los
  /// metadatos y aquí se bajan los archivos para `ruta_local` (offline).
  /// Devuelve los bytes o `null` si algo falla (sin red, 404, archivo
  /// ausente). Si [rutaArchivo] viene dada se omite el GET de metadatos.
  ///
  /// [onHttpStatus] informa el status de la descarga de bytes (el motor lo
  /// usa para marcar 404 definitivos y no reintentar cada sync).
  ///
  /// La descarga de bytes lleva timeout de 30 s (sin esto un servidor
  /// colgado dejaba el sync esperando para siempre: no hay `.timeout` en
  /// `_client.get` y el retry solo cubre excepciones, no cuelgues).
  Future<List<int>?> descargarBytesFoto({
    required String uuidFotografia,
    String? rutaArchivo,
    void Function(int statusCode)? onHttpStatus,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    var ruta = rutaArchivo;
    if ((ruta == null || ruta.isEmpty) && uuidFotografia.isNotEmpty) {
      try {
        final meta = await obtenerFotografia(uuidFotografia);
        final r = meta.data?['ruta_archivo'];
        if (r is String && r.isNotEmpty) ruta = r;
      } catch (_) {
        return null;
      }
    }
    if (ruta == null || ruta.isEmpty) return null;
    final base = Uri.parse(ApiConfig.baseUrl);
    final path = ruta.startsWith('/') ? ruta : '/$ruta';
    final url = '${base.scheme}://${base.host}$path';
    try {
      final res = await _get(url, previsto404: true).timeout(timeout);
      onHttpStatus?.call(res.statusCode);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return res.bodyBytes;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Sync ──

  /// `GET /sync/pull?desde=<ISO>&limit=<n>`
  Future<EdanApiResult<Map<String, dynamic>>> pull({
    String? desde,
    int? limit,
  }) async {
    final query = <String, String>{};
    if (desde != null && desde.isNotEmpty) query['desde'] = desde;
    if (limit != null) query['limit'] = '$limit';
    final uri = Uri.parse('$baseUrl/sync/pull').replace(queryParameters: query);
    final res = await _get(uri.toString());
    return _unpack<Map<String, dynamic>>(res, (d) => d ?? {});
  }

  /// `POST /sync/push` (lote ≤200 ítems).
  Future<EdanApiResult<Map<String, dynamic>>> push(
      Map<String, dynamic> payload) async {
    final res = await _post('$baseUrl/sync/push', payload);
    return _unpack<Map<String, dynamic>>(res, (d) => d ?? {});
  }

  /// `POST /sync/ack` {id_dispositivo, watermark}
  Future<EdanApiResult<void>> ack({
    required String idDispositivo,
    required String watermark,
  }) async {
    final res = await _post('$baseUrl/sync/ack', {
      'id_dispositivo': idDispositivo,
      'watermark': watermark,
    });
    return _unpackVoid(res);
  }

  // ── HTTP helpers ──

  Future<http.Response> _get(String url, {bool previsto404 = false}) =>
      _instrumented(
        'GET',
        url,
        null,
        () => _retry(() => _client.get(
              Uri.parse(url),
              headers: _headers(),
            )),
        esperado: previsto404,
      );

  Future<http.Response> _post(String url, dynamic body,
          {String? idempotencyKey}) =>
      _instrumented(
        'POST',
        url,
        body,
        () => _retry(() => _client.post(
              Uri.parse(url),
              headers: _headers(idempotencyKey: idempotencyKey),
              body: jsonEncode(body),
            )),
      );

  Future<http.Response> _put(String url, dynamic body,
          {String? idempotencyKey}) =>
      _instrumented(
        'PUT',
        url,
        body,
        () => _retry(() => _client.put(
              Uri.parse(url),
              headers: _headers(idempotencyKey: idempotencyKey),
              body: jsonEncode(body),
            )),
      );

  Future<http.Response> _delete(String url) => _instrumented(
        'DELETE',
        url,
        null,
        () => _retry(() => _client.delete(
              Uri.parse(url),
              headers: _headers(),
            )),
      );

  /// Envuelve una llamada HTTP y la reporta a [SyncDebugCollector] cuando
  /// [kSyncDebugMode] está activo. **No altera** el resultado ni los errores:
  /// re-lanza tal cual. Cubre toda la superficie V2 (formularios, secciones,
  /// viviendas, fotos JSON, sync pull/push/ack), porque todas pasan por aquí.
  ///
  /// SIEMPRE deja huella completa en [AppLogger] (request y response crudos,
  /// sin recortes) — incluso con [kSyncDebugMode] apagado o en tests que
  /// inyectan un cliente falso.
  ///
  /// [esperado] marca la llamada como "puede fallar con 404 sin que sea un
  /// problema" (descarga de bytes de foto); el 404 se registra en nivel `info`
  /// y fuera del filtro de errores. Cualquier otro >=400 sigue siendo error.
  Future<http.Response> _instrumented(
    String metodo,
    String url,
    dynamic body,
    Future<http.Response> Function() ejecutar, {
    bool esperado = false,
  }) async {
    final sw = Stopwatch()..start();
    final reqTexto =
        body == null ? null : (body is String ? body : jsonEncode(body));
    if (!kSyncDebugMode) {
      try {
        final res = await ejecutar();
        sw.stop();
        AppLogger.instance.api(
          metodo: metodo,
          url: url,
          estado: res.statusCode,
          duracion: sw.elapsed,
          request: reqTexto,
          response: _respuestaCruda(res),
          // Un 404 aquí es previsto: la foto ya no está en el servidor (legacy
          // o eliminada). Se registra igual, pero sin nivel error ni «solo
          // errores» (no hay nada que corregir).
          esErrorEsperado: esperado && res.statusCode == 404,
        );
        return res;
      } catch (e, s) {
        sw.stop();
        AppLogger.instance.api(
          metodo: metodo,
          url: url,
          duracion: sw.elapsed,
          request: reqTexto,
          error: e.toString(),
          stack: s,
        );
        rethrow;
      }
    }
    try {
      final res = await ejecutar();
      sw.stop();
      AppLogger.instance.api(
        metodo: metodo,
        url: url,
        estado: res.statusCode,
        duracion: sw.elapsed,
        request: reqTexto,
        response: _respuestaCruda(res),
        esErrorEsperado: esperado && res.statusCode == 404,
      );
      SyncDebugCollector.instance.add(SyncApiEntry(
        fase: SyncDebugCollector.instance.currentPhase,
        metodo: metodo,
        endpoint: _endpointCorto(metodo, url),
        requestBody: _cuerpoDebug(body),
        responseBody: _respuestaDebug(res),
        statusCode: res.statusCode,
        duracion: sw.elapsed,
      ));
      return res;
    } catch (e, s) {
      sw.stop();
      AppLogger.instance.api(
        metodo: metodo,
        url: url,
        duracion: sw.elapsed,
        request: reqTexto,
        error: e.toString(),
        stack: s,
      );
      SyncDebugCollector.instance.add(SyncApiEntry(
        fase: SyncDebugCollector.instance.currentPhase,
        metodo: metodo,
        endpoint: _endpointCorto(metodo, url),
        requestBody: _cuerpoDebug(body),
        error: e.toString(),
        duracion: sw.elapsed,
      ));
      rethrow;
    }
  }

  /// Cuerpo de respuesta crudo para el log de [AppLogger]: texto íntegro si es
  /// legible; si es binario (descarga de fotos) o descomunal, descriptor con
  /// tamaño y content-type. No se recorta contenido de texto.
  static String _respuestaCruda(http.Response res) {
    final tipo = res.headers['content-type'] ?? '';
    final esTexto = tipo.contains('json') ||
        tipo.contains('text') ||
        tipo.contains('xml') ||
        tipo.contains('html') ||
        tipo.isEmpty;
    if (!esTexto || res.bodyBytes.length > 2 * 1024 * 1024) {
      return '[binario/grande: ${res.bodyBytes.length} bytes, $tipo]';
    }
    return res.body;
  }

  /// Variante multipart (fotos): reporta los campos y el archivo en
  /// [SyncApiEntry.requestBodyRaw]. No altera el resultado ni los errores.
  /// En [AppLogger] queda la respuesta cruda completa y el descriptor de
  /// campos/archivos (nunca los bytes de la imagen).
  Future<http.Response> _instrumentedMultipart(
    String url,
    String resumenCampos,
    List<String> fotos,
    Future<http.Response> Function() ejecutar,
  ) async {
    final sw = Stopwatch()..start();
    if (!kSyncDebugMode) {
      try {
        final res = await ejecutar();
        sw.stop();
        AppLogger.instance.api(
          metodo: 'POST',
          url: url,
          estado: res.statusCode,
          duracion: sw.elapsed,
          request: resumenCampos,
          response: _respuestaCruda(res),
          nota: 'multipart fotos: ${fotos.length}',
        );
        return res;
      } catch (e, s) {
        sw.stop();
        AppLogger.instance.api(
          metodo: 'POST',
          url: url,
          duracion: sw.elapsed,
          request: resumenCampos,
          error: e.toString(),
          stack: s,
          nota: 'multipart fotos: ${fotos.length}',
        );
        rethrow;
      }
    }
    try {
      final res = await ejecutar();
      sw.stop();
      AppLogger.instance.api(
        metodo: 'POST',
        url: url,
        estado: res.statusCode,
        duracion: sw.elapsed,
        request: resumenCampos,
        response: _respuestaCruda(res),
        nota: 'multipart fotos: ${fotos.length}',
      );
      SyncDebugCollector.instance.add(SyncApiEntry(
        fase: SyncDebugCollector.instance.currentPhase,
        metodo: 'POST',
        endpoint: '${_endpointCorto('POST', url)} (multipart)',
        requestBodyRaw: resumenCampos,
        responseBody: _respuestaDebug(res),
        statusCode: res.statusCode,
        fotos: fotos,
        duracion: sw.elapsed,
      ));
      return res;
    } catch (e, s) {
      sw.stop();
      AppLogger.instance.api(
        metodo: 'POST',
        url: url,
        duracion: sw.elapsed,
        request: resumenCampos,
        error: e.toString(),
        stack: s,
        nota: 'multipart fotos: ${fotos.length}',
      );
      SyncDebugCollector.instance.add(SyncApiEntry(
        fase: SyncDebugCollector.instance.currentPhase,
        metodo: 'POST',
        endpoint: '${_endpointCorto('POST', url)} (multipart)',
        requestBodyRaw: resumenCampos,
        fotos: fotos,
        error: e.toString(),
        duracion: sw.elapsed,
      ));
      rethrow;
    }
  }

  /// Ruta legible (sin host) para el panel de depuración. Las URLs absolutas
  /// fuera de `baseUrl` (p. ej. descarga estática de fotos) se muestran tal
  /// cual en vez de concatenarse al prefijo (eso pintaba endpoints
  /// imposibles como `/api/v2/edanhttps://...`).
  String _endpointCorto(String metodo, String url) {
    if (url.startsWith(baseUrl)) {
      return '$metodo /api/v2/edan${url.substring(baseUrl.length)}';
    }
    final uri = Uri.tryParse(url);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return '$metodo ${uri.host}${uri.path}';
    }
    return '$metodo $url';
  }

  Map<String, dynamic>? _cuerpoDebug(dynamic body) {
    if (body is Map<String, dynamic>) return body;
    if (body is Map) return Map<String, dynamic>.from(body);
    return null;
  }

  /// Decodifica el body de respuesta para el panel (tolera no-JSON y vacío).
  Map<String, dynamic>? _respuestaDebug(http.Response res) {
    if (res.body.isEmpty) return null;
    try {
      final d = jsonDecode(res.body);
      if (d is Map<String, dynamic>) return d;
      if (d is Map) return Map<String, dynamic>.from(d);
      return {'_': d};
    } catch (_) {
      final b = res.body;
      return {'_raw': b.length > 4000 ? b.substring(0, 4000) : b};
    }
  }

  Future<http.Response> _retry(Future<http.Response> Function() fn,
      {int maxRetries = 2}) async {
    http.Response? last;
    for (int i = 0; i <= maxRetries; i++) {
      try {
        last = await fn();
        // Reintentables a nivel HTTP: gateway/transitorios + rate-limit/timeout.
        // 400/403/404/409/422 NUNCA se reintentan aquí (los clasifica el motor).
        if (!{502, 503, 504, 429, 408}.contains(last.statusCode)) return last;
      } on SocketException {
        if (i == maxRetries) rethrow;
      } on http.ClientException {
        if (i == maxRetries) rethrow;
      } on TimeoutException {
        if (i == maxRetries) rethrow;
      }
      await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
    }
    return last!;
  }

  // ── Envelope y errores ──

  EdanApiResult<void> _unpackVoid(http.Response response) {
    final result = _unpack<Object?>(response, (_) => null);
    return EdanApiResult<void>(
      success: result.success,
      message: result.message,
      data: null,
      total: result.total,
      statusCode: result.statusCode,
      rawBody: result.rawBody,
    );
  }

  EdanApiResult<T> _unpack<T>(
    http.Response response,
    T Function(dynamic data) mapper,
  ) {
    final body = _decode(response);
    final envelope = body is Map<String, dynamic> ? body : <String, dynamic>{};
    final result = EdanApiResult<T>(
      success: envelope['success'] as bool? ?? response.statusCode < 300,
      message: envelope['message'] as String?,
      data: mapper(envelope['data']),
      total: envelope['total'] as int?,
      statusCode: response.statusCode,
      rawBody: envelope,
    );

    if (response.statusCode == 409) {
      final detail = envelope['detail'];
      if (detail is Map<String, dynamic>) {
        throw EdanApiConflict(
          statusCode: response.statusCode,
          versionServidor: (detail['version_servidor'] as num?)?.toInt() ?? 0,
          versionCliente: (detail['version_cliente'] as num?)?.toInt() ?? 0,
          registroServidor:
              (detail['registro_servidor'] as Map<String, dynamic>?) ?? {},
          message: detail['message'] as String? ?? 'Conflicto de versiones',
        );
      }
      // §20.15: POST /completo sobre existente → 409 string "SOLO creación:
      // use PUT". Señal de ruta, no error fatal.
      if (detail is String && EdanPostSoloCreacion.esSenalUsaPut(detail)) {
        throw EdanPostSoloCreacion(detail);
      }
    }

    if (!result.ok) {
      final detail = envelope['detail'];
      throw EdanApiError(
        statusCode: response.statusCode,
        detail: detail is String
            ? detail
            : detail is Map
                ? jsonEncode(detail)
                : 'Error ${response.statusCode}',
        rawBody: envelope,
      );
    }

    return result;
  }

  EdanApiResult<List<T>> _unpackList<T>(
    dynamic response,
    T Function(dynamic) mapper,
  ) {
    final body = _decode(response);
    final envelope = body is Map<String, dynamic> ? body : <String, dynamic>{};
    final rawData = envelope['data'];
    // Forma vigente (2026-10-14) en listados como `/formularios/estados`:
    // `data = {items[], resumen{}, total}`. La forma vieja (`data` = lista)
    // se sigue aceptando.
    final List<dynamic> list;
    Map<String, dynamic>? resumen;
    int? total = envelope['total'] as int?;
    if (rawData is Map) {
      final items = rawData['items'];
      list = items is List ? items : <dynamic>[];
      final r = rawData['resumen'];
      if (r is Map<String, dynamic>) {
        resumen = r;
      } else if (r is Map) {
        resumen = Map<String, dynamic>.from(r);
      }
      final t = rawData['total'];
      if (t is num) total = t.toInt();
    } else {
      list = rawData is List ? rawData : <dynamic>[];
    }
    final mapped = list.map(mapper).toList();
    final result = EdanApiResult<List<T>>(
      success: envelope['success'] as bool? ?? response.statusCode < 300,
      message: envelope['message'] as String?,
      data: mapped,
      total: total ?? mapped.length,
      resumen: resumen,
      statusCode: response.statusCode,
      rawBody: envelope,
    );

    if (response.statusCode == 409) {
      final detail = envelope['detail'];
      if (detail is Map<String, dynamic>) {
        throw EdanApiConflict(
          statusCode: response.statusCode,
          versionServidor: (detail['version_servidor'] as num?)?.toInt() ?? 0,
          versionCliente: (detail['version_cliente'] as num?)?.toInt() ?? 0,
          registroServidor:
              (detail['registro_servidor'] as Map<String, dynamic>?) ?? {},
          message: detail['message'] as String? ?? 'Conflicto de versiones',
        );
      } else if (detail is Map) {
        final d = Map<String, dynamic>.from(detail);
        throw EdanApiConflict(
          statusCode: response.statusCode,
          versionServidor: (d['version_servidor'] as num?)?.toInt() ?? 0,
          versionCliente: (d['version_cliente'] as num?)?.toInt() ?? 0,
          registroServidor:
              (d['registro_servidor'] as Map<String, dynamic>?) ?? {},
          message: d['message'] as String? ?? 'Conflicto de versiones',
        );
      }
    }

    if (!result.ok) {
      final detail = envelope['detail'];
      throw EdanApiError(
        statusCode: response.statusCode,
        detail: detail is String
            ? detail
            : detail is Map
                ? jsonEncode(detail)
                : 'Error ${response.statusCode}',
        rawBody: envelope,
      );
    }
    return result;
  }

  dynamic _decode(http.Response response) {
    if (response.body.isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(response.body);
    } catch (_) {
      throw EdanApiError(
        statusCode: response.statusCode,
        detail: 'Respuesta no es JSON válido',
        rawBody: response.body,
      );
    }
  }

  MediaType _mediaType(String path) {
    final ext = path.split('.').lastOrNull?.toLowerCase() ?? 'jpg';
    switch (ext) {
      case 'png':
        return MediaType('image', 'png');
      case 'gif':
        return MediaType('image', 'gif');
      case 'webp':
        return MediaType('image', 'webp');
      case 'jpg':
      case 'jpeg':
      default:
        return MediaType('image', 'jpeg');
    }
  }
}
