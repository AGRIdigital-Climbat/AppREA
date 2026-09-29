import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rea/config/theme.dart';
import 'package:rea/widgets/tutorial_guide.dart';

/// Abre la guía con configuración equivalente a la producción del wizard.
void _abrirGuia(BuildContext context) {
  TutorialGuide.of(context)
    ..setPersonajeImagen('assets/images/imagen1.png')
    ..setTamanoPersonajeFactor(0.35)
    ..setTitulo('Sección de prueba')
    ..setConsejos(const ['Ayuda para llenar la sección.'])
    ..setPosicion(TutorialPosition.bottomRight)
    ..setDireccion(TutorialDirection.left)
    ..setVisibilidad(const Duration(seconds: 8))
    ..show();
}

Widget _app() {
  return MaterialApp(
    home: PaletteScope(
      palette: Palettes.rea,
      child: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => _abrirGuia(context),
              child: const Text('Abrir guía'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('modo imagen: el personaje es un Image sin errores',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Abrir guía'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.textContaining('Sección de prueba'), findsOneWidget);
    // La guía pinta la imagen del personaje + su silueta de sombra (2 Image).
    expect(find.byType(Image), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
  testWidgets('abre la guía sin errores y la cierra por tap fuera',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Abrir guía'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.textContaining('Sección de prueba'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Tap fuera (esquina superior izquierda) cierra la guía.
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Sección de prueba'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cierra con el botón X', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Abrir guía'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    await tester.tap(find.byTooltip('Cerrar guía'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Sección de prueba'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('se auto-oculta tras la duración configurada', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Abrir guía'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.textContaining('Sección de prueba'), findsOneWidget);

    await tester.pump(const Duration(seconds: 9));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Sección de prueba'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('abrir/cerrar varias veces no cierra la pantalla subyacente',
      (tester) async {
    await tester.pumpWidget(_app());

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Abrir guía'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.textContaining('Sección de prueba'),
          findsOneWidget);

      await tester.tap(find.byTooltip('Cerrar guía'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('Sección de prueba'),
          findsNothing);
      // La pantalla desde la que se abrió debe seguir viva.
      expect(find.text('Abrir guía'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}