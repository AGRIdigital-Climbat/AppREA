import 'dart:math';

/// Genera un ID único para una sección del EDAN.
///
/// Formato: `{prefijo}_{timestamp}_{hex}`
/// - `prefijo`: identifica el tipo de sección (sb, sv, dv, etc.)
/// - `timestamp`: segundos desde epoch (evita colisiones entre dispositivos)
/// - `hex`: 8 caracteres hex aleatorios (desambigua creaciones simultáneas)
///
/// Ejemplo: `sb_1693012345_a1b2c3d4`
///
/// IMPORTANTE: Generar una sola vez al crear la sección. NUNCA regenerar al editar.
String generarIdSeccion(String prefijo) {
  final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final random = Random.secure();
  final hex = List.generate(8, (_) => random.nextInt(16).toRadixString(16)).join();
  return '${prefijo}_${ts}_$hex';
}
