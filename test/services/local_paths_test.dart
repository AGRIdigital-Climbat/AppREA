import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rea/services/local_paths.dart';

/// Regression iOS (revisión 2026-11-18): las rutas absolutas persistidas
/// envejecen cuando iOS cambia el UUID del contenedor en una actualización,
/// y los nombres de archivo vindos del servidor no pueden escapar de la
/// carpeta de destino.
void main() {
  group('LocalPaths.sanitizarNombreArchivo', () {
    test('neutraliza separadores de ruta del nombre vindado', () {
      expect(
        LocalPaths.sanitizarNombreArchivo(
          'informes/../../Windows/system.pdf',
          fallback: 'fallback.pdf',
        ),
        isNot(contains('/')),
      );
      expect(
        LocalPaths.sanitizarNombreArchivo(
          'informes/../../Windows/system.pdf',
          fallback: 'fallback.pdf',
        ),
        isNot(contains('..')),
      );
    });

    test('cae al fallback con nombres vacíos', () {
      expect(
          LocalPaths.sanitizarNombreArchivo('', fallback: 'documento_9.pdf'),
          'documento_9.pdf');
      expect(LocalPaths.sanitizarNombreArchivo(null,
          fallback: 'documento_9.pdf'), 'documento_9.pdf');
      expect(LocalPaths.sanitizarNombreArchivo('   ',
          fallback: 'documento_9.pdf'), 'documento_9.pdf');
    });

    test('conserva la extensión al recortar nombres largos', () {
      final largo = 'a' * 300;
      final corto = LocalPaths.sanitizarNombreArchivo(largo,
          fallback: 'f.pdf');
      expect(corto.length, lessThanOrEqualTo(120));
      final conExt = LocalPaths.sanitizarNombreArchivo('${'b' * 300}.pdf',
          fallback: 'f.pdf');
      expect(conExt.endsWith('.pdf'), isTrue);
      expect(conExt.length, lessThanOrEqualTo(120));
    });

    test('deja intactos los nombres normales', () {
      expect(
          LocalPaths.sanitizarNombreArchivo('EDAN 2026-10 Informe.pdf',
              fallback: 'f.pdf'), 'EDAN 2026-10 Informe.pdf');
    });
  });

  group('LocalPaths.resolverRutaLocal', () {
    test('null/vacío → null', () async {
      expect(await LocalPaths.resolverRutaLocal(null), isNull);
      expect(await LocalPaths.resolverRutaLocal(''), isNull);
    });

    test('ruta vigente se devuelve intacta (comportamiento Android)',
        () async {
      final tmp = await Directory.systemTemp.createTemp('lp_ok');
      try {
        final f = File('${tmp.path}/foto.jpg')..writeAsBytesSync([1, 2, 3]);
        expect(await LocalPaths.resolverRutaLocal(f.path), f.path);
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('sin acceso a Documents (tests) degrada a null sin lanzar',
        () async {
      // path_provider no tiene implementación en flutter test: el resolver
      // debe devolver null (nunca romper el sync por una ruta vieja).
      expect(
          await LocalPaths.resolverRutaLocal(
              '/var/Containers/Data/Application/OLD/Documents/report_photos/x.jpg'),
          isNull);
    });
  });
}
