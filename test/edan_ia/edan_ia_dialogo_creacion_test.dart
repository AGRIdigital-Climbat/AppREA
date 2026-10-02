/// El diálogo del `+`: qué ofrece, qué devuelve y cómo se ve en pantallas
/// bajas.
///
/// Es la primera pantalla de la creación de una ficha, así que se prueba como
/// la ve la persona: pocas opciones claras, un solo toque, y nada que se
/// desborde en el celular chico. Los avisos de layout que aparecieron en la
/// prueba de campo ("RenderFlex overflowed") salen acá como test, no en el
/// dispositivo.
///
/// La opción de hablar se muestra solo con internet, porque sin conexión el
/// asistente no entiende nada: ofrecerla es prometer algo que no va a pasar.
/// Por eso los tests fijan el veredicto de red con `hayInternet` y no tocan la
/// plataforma.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rea/config/theme.dart';
import 'package:rea/screens/role_screens/resp/edan/edan_ia_elegir_creacion.dart';

/// Guarda lo que devolvió el diálogo. Es un objeto y no una variable suelta
/// para que el closure del botón pueda escribirla después de un `await`.
class _Eleccion {
  EdanModoCreacion? valor;
}

/// Monta la app con un botón que abre el diálogo, y abre el diálogo.
Future<_Eleccion> _abrir(
  WidgetTester tester, {
  bool hayInternet = true,
  double textScale = 1.0,
  Size? tamanoPantalla,
}) async {
  final eleccion = _Eleccion();

  if (tamanoPantalla != null) {
    tester.view.physicalSize = tamanoPantalla;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  await tester.pumpWidget(
    PaletteScope(
      palette: Palettes.rea,
      child: MaterialApp(
        theme: AppTheme.buildTheme(Palettes.rea),
        // `textScaler` es el mecanismo real de accesibilidad del sistema, no un
        // ajuste de tema: reproduce lo que pasa con la fuente del usuario
        // agrandada.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  eleccion.valor = await pedirModoCreacionEdan(
                    context,
                    hayInternet: hayInternet,
                  );
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
  return eleccion;
}

void main() {
  group('diálogo de creación', () {
    testWidgets('ofrece las dos formas de llenar la ficha', (tester) async {
      await _abrir(tester);

      expect(find.text('Nueva ficha EDAN'), findsOneWidget);
      expect(find.text('Llenar hablando'), findsOneWidget);
      expect(find.text('Usar el formulario'), findsOneWidget);
    });

    testWidgets('no empuja ninguna opción', (tester) async {
      await _abrir(tester);

      // Sin "Recomendado": el diálogo no tiene que empujar una opción, la
      // persona elige.
      expect(find.textContaining('Recomendado'), findsNothing);

      // Y sin párrafos: el botón dice qué hace y listo.
      expect(find.textContaining('Contá lo que pasó por chat'), findsNothing);
      expect(find.textContaining('Elegí cómo querés completarla'), findsNothing);
      expect(
        find.textContaining('Queda guardada en el celular'),
        findsNothing,
      );
    });

    testWidgets('el fondo del diálogo es blanco', (tester) async {
      await _abrir(tester);

      final dialogo = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(dialogo.backgroundColor, Colors.white);
      expect(dialogo.surfaceTintColor, Colors.white);
    });

    testWidgets('tocar "Llenar hablando" devuelve asistente IA', (tester) async {
      final eleccion = await _abrir(tester);

      await tester.tap(find.text('Llenar hablando'));
      await tester.pumpAndSettle();

      expect(eleccion.valor, EdanModoCreacion.asistenteIa);
    });

    testWidgets('tocar el formulario devuelve wizard', (tester) async {
      final eleccion = await _abrir(tester);

      await tester.tap(find.text('Usar el formulario'));
      await tester.pumpAndSettle();

      expect(eleccion.valor, EdanModoCreacion.wizard);
    });

    testWidgets('cancelar no elige nada', (tester) async {
      final eleccion = await _abrir(tester);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(eleccion.valor, isNull);
    });

    testWidgets('sin internet no ofrece el asistente', (tester) async {
      await _abrir(tester, hayInternet: false);

      // El formulario es local y siempre funciona: no puede desaparecer.
      expect(find.text('Usar el formulario'), findsOneWidget);
      expect(find.text('Llenar hablando'), findsNothing);
    });

    testWidgets('sin internet el diálogo no se descuadra', (tester) async {
      await _abrir(
        tester,
        hayInternet: false,
        tamanoPantalla: const Size(320, 480),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Usar el formulario'), findsOneWidget);
    });

    testWidgets('no se desborda en un celular chico', (tester) async {
      // 320x480 es el piso razonable; con el teclado abierto o en equipos de
      // gama baja el alto útil baja más.
      await _abrir(tester, tamanoPantalla: const Size(320, 480));

      // Si algo no entra, Flutter deja el RenderFlex marcado y este test falla.
      expect(tester.takeException(), isNull);
      expect(find.text('Llenar hablando'), findsOneWidget);
      expect(find.text('Usar el formulario'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
    });

    testWidgets('no se desborda con fuente grande (accesibilidad)',
        (tester) async {
      await _abrir(
        tester,
        tamanoPantalla: const Size(320, 640),
        textScale: 1.6,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Llenar hablando'), findsOneWidget);
      expect(find.text('Usar el formulario'), findsOneWidget);
    });
  });
}
