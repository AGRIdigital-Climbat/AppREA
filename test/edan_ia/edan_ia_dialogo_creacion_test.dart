/// El diálogo del `+`: qué ofrece, qué devuelve y cómo se ve en pantallas
/// bajas.
///
/// Es la primera pantalla de la creación de una ficha, así que se prueba como
/// la ve la persona: dos opciones claras, un solo toque, y nada que se desborde
/// en el celular chico. Los avisos de layout que aparecieron en la prueba de
/// campo ("RenderFlex overflowed") salen acá como test, no en el dispositivo.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rea/config/theme.dart';
import 'package:rea/screens/role_screens/resp/edan/edan_ia_elegir_creacion.dart';

/// Monta el diálogo dentro de una app con la paleta de REA.
Future<EdanModoCreacion?> _abrir(WidgetTester tester) async {
  EdanModoCreacion? elegido;

  await tester.pumpWidget(
    PaletteScope(
      palette: Palettes.rea,
      child: MaterialApp(
        theme: AppTheme.buildTheme(Palettes.rea),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  elegido = await pedirModoCreacionEdan(context);
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return elegido;
}

void main() {
  group('diálogo de creación', () {
    testWidgets('ofrece las dos formas de llenar la ficha', (tester) async {
      await _abrir(tester);

      expect(find.text('Nueva ficha EDAN'), findsOneWidget);
      expect(find.text('Llenar hablando'), findsOneWidget);
      expect(find.text('Usar el formulario'), findsOneWidget);
    });

    testWidgets('la opción recomendada es la que habla', (tester) async {
      await _abrir(tester);

      expect(find.text('Recomendado'), findsOneWidget);
      // La insignia tiene que estar pegada a la opción del asistente, no al
      // formulario: si se cruzan, la persona elige mal sin querer.
      final insignia = tester.getCenter(find.text('Recomendado'));
      final ia = tester.getCenter(find.text('Llenar hablando'));
      expect((insignia.dy - ia.dy).abs(), lessThan(40));
    });

    testWidgets('explica que la ficha queda en el celular', (tester) async {
      await _abrir(tester);

      expect(
        find.textContaining('Queda guardada en el celular'),
        findsOneWidget,
      );
    });

    testWidgets('tocar "Llenar hablando" devuelve asistente IA', (tester) async {
      EdanModoCreacion? elegido;
      await tester.pumpWidget(
        PaletteScope(
          palette: Palettes.rea,
          child: MaterialApp(
            theme: AppTheme.buildTheme(Palettes.rea),
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    elegido = await pedirModoCreacionEdan(context);
                  },
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Llenar hablando'));
      await tester.pumpAndSettle();

      expect(elegido, EdanModoCreacion.asistenteIa);
    });

    testWidgets('tocar el formulario devuelve wizard', (tester) async {
      EdanModoCreacion? elegido;
      await tester.pumpWidget(
        PaletteScope(
          palette: Palettes.rea,
          child: MaterialApp(
            theme: AppTheme.buildTheme(Palettes.rea),
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    elegido = await pedirModoCreacionEdan(context);
                  },
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Usar el formulario'));
      await tester.pumpAndSettle();

      expect(elegido, EdanModoCreacion.wizard);
    });

    testWidgets('cancelar no elige nada', (tester) async {
      EdanModoCreacion? elegido;
      await tester.pumpWidget(
        PaletteScope(
          palette: Palettes.rea,
          child: MaterialApp(
            theme: AppTheme.buildTheme(Palettes.rea),
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    elegido = await pedirModoCreacionEdan(context);
                  },
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(elegido, isNull);
    });

    testWidgets('no se desborda en un celular chico', (tester) async {
      // 320x480 es el piso razonable; con el teclado abierto o en equipos de
      // gama baja el alto útil baja más.
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _abrir(tester);

      // Si algo no entra, Flutter deja el RenderFlex marcado y este test falla.
      expect(tester.takeException(), isNull);
      expect(find.text('Llenar hablando'), findsOneWidget);
      expect(find.text('Usar el formulario'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
    });

    testWidgets('no se desborda con fuente grande (accesibilidad)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // `textScaler` es el mecanismo real de accesibilidad del sistema, no un
      // ajuste de tema: reproduce lo que pasa con la fuente del usuario agrandada.
      await tester.pumpWidget(
        PaletteScope(
          palette: Palettes.rea,
          child: MaterialApp(
            theme: AppTheme.buildTheme(Palettes.rea),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.6),
              ),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => pedirModoCreacionEdan(context),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
