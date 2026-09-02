import 'dart:math';

/// Genera un ID único para una sección del EDAN en formato espec v2.
///
/// Formato: `{timestamp_base32}-{uuid_short}` (~24 caracteres)
/// - `timestamp_base32`: milisegundos desde epoch en base32 (~10 chars)
/// - `uuid_short`: 13 caracteres hexadecimales aleatorios (desambigua
///   creaciones simultáneas)
///
/// Ejemplo: `1a0357323cb-659d0c9c3d415`
///
/// IMPORTANTE: Generar una sola vez al crear la sección. NUNCA regenerar al
/// editar. El servidor lo usa únicamente como clave de UPSERT, nunca lo genera.
String generarIdSeccion(String prefijo) {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final timestampBase32 = ts.toRadixString(32);
  final uuidShort = _randomHex(13);
  return '$timestampBase32-$uuidShort';
}

/// Helpers por sección: cada uno genera el `id_seccion` de UNA sección
/// concreta usando SIEMPRE el mismo prefijo (legible y consistente). Úsalos al
/// crear ítems NUEVOS de esa sección; NUNCA al serializar para GET/PUT (ahí se
/// reutiliza el id ya existente del ítem).
String nuevoIdImpactoPoblacion() => generarIdSeccion('im');
String nuevoIdSaludEstablecimiento() => generarIdSeccion('es');
String nuevoIdDanoVial() => generarIdSeccion('sv');
String nuevoIdDanoInfraPublica() => generarIdSeccion('di');
String nuevoIdServicioBasico() => generarIdSeccion('sb');
String nuevoIdUnidadEducativa() => generarIdSeccion('ue');
String nuevoIdDanoVivienda() => generarIdSeccion('dv');
String nuevoIdDanoAgricultura() => generarIdSeccion('ag');
String nuevoIdDanoPecuario() => generarIdSeccion('pc');
String nuevoIdInfraProductiva() => generarIdSeccion('ip');
String nuevoIdProteccion() => generarIdSeccion('po');

/// Genera un UUID v4 estándar (36 caracteres) para `id_local`.
///
/// El `id_local` es la identidad estable e inmutable de una localidad,
/// generada UNA vez al crear el documento y usada como clave de dedupe del
/// servidor. Nunca debe regenerarse.
String generarIdLocal() {
  final r = Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

String _randomHex(int length) {
  final random = Random.secure();
  return List.generate(
      length, (_) => random.nextInt(16).toRadixString(16)).join();
}
