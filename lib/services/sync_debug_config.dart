/// Flag global para habilitar/deshabilitar el panel de depuración visual
/// de sincronización.
///
/// Cuando es `true`:
///   - Cada llamada API del sync se captura en [SyncDebugCollector]
///   - Aparece un ícono de debug en el AppBar de resp_screen
///   - Se puede ver cada request, response, fotos, errores
///
/// Cuando es `false`:
///   - El sync funciona normalmente sin UI debug
///   - No se captura nada
///   - No aparece el ícono de debug
const bool kSyncDebugMode = true;

/// Reemplaza el esquema+host de cualquier URL http(s) por el literal `PATH`,
/// conservando solo la ruta. Uso: panel de depuración, copiar entradas y
/// reportes compartidos — el dominio nunca sale del dispositivo en capturas
/// ni archivos exportados (se cuidan las APIs).
String enmascararUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) {
    return 'PATH';
  }
  final ruta = uri.path.isEmpty ? '/' : uri.path;
  return 'PATH$ruta';
}

/// Barrido suave para textos libres (request/response/errores/bodies JSON):
/// toda URL http(s) que aparezca queda como `PATH/<ruta>` (sin host ni
/// query). Los caminos siguen legibles para depurar.
String scrubUrls(String texto) => texto.replaceAllMapped(
      RegExp(r'''https?://[^\s"']+'''),
      (m) => enmascararUrl(m.group(0)!),
    );

/// Modelo de una entrada de depuración para una llamada API individual.
class SyncApiEntry {
  /// Fase del sync (ej: "Fase 0", "Fase 2 - Cabecera", "Fase 5 - Upload").
  final String fase;

  /// Método HTTP ("GET", "POST", "DELETE").
  final String metodo;

  /// Endpoint completo (ej: "POST /edan/localidades/cabecera").
  final String endpoint;

  /// JSON enviado (request body). Null para multipart o GET sin body.
  final Map<String, dynamic>? requestBody;

  /// Texto del request body para multipart (fields + files info).
  final String? requestBodyRaw;

  /// JSON recibido (response body). Null para binario (fotos) o errores de parse.
  final Map<String, dynamic>? responseBody;

  /// HTTP status code (200, 201, 400, 404, 500, etc.).
  final int? statusCode;

  /// Paths de fotos involucradas en esta llamada.
  final List<String> fotos;

  /// Duración de la llamada HTTP.
  final Duration? duracion;

  /// Timestamp de cuándo ocurrió.
  final DateTime timestamp;

  /// Mensaje de error si falló.
  final String? error;

  /// ID de la localidad procesada.
  final String? localidadId;

  /// Nombre de la sección (ej: "impacto-poblacion").
  final String? seccion;

  /// Número de intento (0 = primero, 1 = primer retry, etc.).
  final int? intento;

  /// Detalle estructurado de diagnóstico local por ítem (no es una llamada
  /// API real). Se usa para mostrar, por localidad y por sección, qué se va a
  /// sincronizar (nuevas vs ya sincronizadas), el endpoint y el JSON a enviar,
  /// y el estado de fotos. Cuando se setea, [metodo]=='DIAGNÓSTICO'.
  final Map<String, dynamic>? detalleDiagnostico;

  SyncApiEntry({
    required this.fase,
    required this.metodo,
    required this.endpoint,
    this.requestBody,
    this.requestBodyRaw,
    this.responseBody,
    this.statusCode,
    this.fotos = const [],
    this.duracion,
    DateTime? timestamp,
    this.error,
    this.localidadId,
    this.seccion,
    this.intento,
    this.detalleDiagnostico,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Si la llamada fue exitosa (2xx).
  bool get isOk => statusCode != null && statusCode! >= 200 && statusCode! < 300;

  /// Si la llamada falló (no 2xx).
  bool get isError => error != null || (statusCode != null && (statusCode! < 200 || statusCode! >= 300));

  /// Icono según el estado.
  String get statusIcon {
    if (error != null) return '✗';
    if (statusCode == null) return '?';
    if (isOk) return '✓';
    return '✗';
  }

  /// Color del badge según estado (para uso en UI).
  String get statusColor {
    if (error != null) return 'red';
    if (statusCode == null) return 'grey';
    if (statusCode! >= 200 && statusCode! < 300) return 'green';
    if (statusCode! >= 400 && statusCode! < 500) return 'orange';
    return 'red';
  }

  /// Resumen corto para mostrar en la tarjeta colapsada.
  String get resumen {
    final dur = duracion != null ? '${duracion!.inMilliseconds}ms' : '?';
    final status = statusCode != null ? '$statusCode' : (error ?? '?');
    final fotosInfo = fotos.isNotEmpty ? ' | ${fotos.length} fotos' : '';
    return '$metodo $status | $dur$fotosInfo';
  }
}
