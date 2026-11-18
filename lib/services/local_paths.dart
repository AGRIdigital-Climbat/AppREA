import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolve de rutas locales tras el reubicado del contenedor de iOS.
///
/// iOS cambia el UUID de la sandbox (`/…/Application/<UUID>/`) en CADA
/// actualización: los bytes guardados bajo `Documents/` siguen intactos,
/// pero las rutas absolutas persistidas en la BD o en prefs apuntan al UUID
/// viejo y ya no existen. Android mantiene sus rutas estables entre
/// versiones, por eso allí nunca se nota.
///
/// Estos helpers reubican el archivo por NOMBRE en las carpetas conocidas
/// (`report_photos/`, `motor_ia/`, `documentos_edan/`, raíz de Documents).
/// Si la ruta absoluta todavía existe, se devuelve intacta: en Android y en
/// un iOS sin actualización el comportamiento es idéntico al anterior.
class LocalPaths {
  LocalPaths._();

  /// Carpetas relativas a `Documents/` donde la app persiste archivos, en el
  /// orden en que se buscan. La cadena vacía = raíz de Documents.
  static const List<String> _subCarpetas = [
    'report_photos',
    'motor_ia',
    'documentos_edan',
    '',
  ];

  /// Devuelve una ruta absoluta usable para [rutaGuardada], o `null` si los
  /// bytes no aparecen en ninguna parte. Nunca lanza: sin acceso al storage
  /// (p. ej. tests sin plugin) solo se valida [rutaGuardada] tal cual.
  static Future<String?> resolverRutaLocal(String? rutaGuardada) async {
    if (rutaGuardada == null || rutaGuardada.isEmpty) return null;
    try {
      if (await File(rutaGuardada).exists()) return rutaGuardada;
      final docs = (await getApplicationDocumentsDirectory()).path;
      final nombre = p.basename(rutaGuardada);
      if (nombre.isEmpty || nombre == '.' || nombre == '..') return null;
      for (final sub in _subCarpetas) {
        final candidato = sub.isEmpty
            ? File(p.join(docs, nombre))
            : File(p.join(docs, sub, nombre));
        if (await candidato.exists()) return candidato.path;
      }
    } catch (_) {}
    return null;
  }

  /// Nombre de archivo seguro a partir de un nombre vindo del servidor
  /// (`nombre_documento`). Quita separadores de ruta y caracteres de
  /// control —que lanzarían `FileSystemException` o escaparían de la
  /// carpeta— y acota la longitud. Cae a [fallback] si no queda nada.
  static String sanitizarNombreArchivo(
    String? nombre, {
    required String fallback,
  }) {
    var base = (nombre ?? '').trim();
    base = base.replaceAll(RegExp(r'[\\/:\x00-\x1F\x7F]'), '_');
    base = base.replaceAll('..', '_');
    if (base.length > 120) {
      // Conserva la extensión al recortar.
      final ext = p.extension(base);
      base = base.substring(0, 120 - ext.length) + ext;
    }
    return base.isEmpty ? fallback : base;
  }
}
