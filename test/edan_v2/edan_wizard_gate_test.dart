/// Regresión de integración del wizard: el botón Siguiente y el swipe.
///
/// Cubre los dos bugs de la "puerta Siguiente", juntos, porque cerrar uno
/// sin el otro deja al usuario encerrado (botón congelado + sin swipe):
///
///  * Bug 1: la página muta datos → `onCambio` → el wizard recalcula los
///    bloqueos y el botón cambia de estado sin reconstruir la lista de
///    páginas.
///  * Bug 2: con bloqueos el `PageView` queda `NeverScrollableScrollPhysics`
///    (el swipe no salta la puerta) y sin bloqueos vuelve a `PageScrollPhysics`.
///
/// La barra superior (`EdanStepIndicator`) sigue con salto libre en los dos
/// casos: es la salida de emergencia del usuario.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rea/config/theme.dart';
import 'package:rea/models/edan.dart';
import 'package:rea/providers/reporte_provider.dart';
import 'package:rea/screens/role_screens/resp/edan/edan_form_wizard.dart';
import 'package:rea/screens/role_screens/resp/edan/edan_navigation_bar.dart';
import 'package:rea/screens/role_screens/resp/edan/edan_step_indicator.dart';

/// [ReporteProvider] sin red ni base de datos: el wizard solo lo consulta
/// para precargar catálogos, que no interesan acá.
class _ReporteStub extends ReporteProvider {
  @override
  Future<void> fetchGruposVulnerablesIfNeeded() async {}

  @override
  Future<void> fetchGruposEtariosIfNeeded() async {}

  @override
  Future<void> loadGeography() async {}

  // page01 lo dispara en post-frame: sin override intentaría red/BD reales.
  @override
  Future<Map<String, int>> fetchAndCacheCatalogs() async => const {};
}

// Sin silenciador de la queja del `CheckboxListTile`: las páginas del wizard
// montan sus bloques sobre `Card` (Material), así que el aviso cosmético del
// framework ya no se emite. Si volviera, estos tests fallan por sí solos.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Localidad con el grupo de necesidades encendido y SIN datos: su página
  /// (11) tiene que arrancar bloqueada.
  EdanLocalidad _localidadNecesidades() => EdanLocalidad(
        nombre: 'L',
        idTipoEvento: 1,
      )..grupNecesidades = true;

  Future<EdanFormWizard> _montar(WidgetTester tester) async {
    final wizard = EdanFormWizard(
      edanAEditar: Edan(localidades: [_localidadNecesidades()]),
    );
    await tester.pumpWidget(
      PaletteScope(
        palette: Palettes.rea,
        child: MaterialApp(
          theme: AppTheme.buildTheme(Palettes.rea),
          home: ChangeNotifierProvider<ReporteProvider>(
            create: (_) => _ReporteStub(),
            child: wizard,
          ),
        ),
      ),
    );
    // Post-frame: snapshot + salto a la primera página incompleta.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return wizard;
  }

  /// Salta a la página 11 usando el indicador superior (salto libre).
  Future<void> _irAPagina11(WidgetTester tester) async {
    await tester.tap(find.byTooltip('4. Necesidades humanitarias'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  PageView _pageView(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView));

  ElevatedButton _botonSiguiente(WidgetTester tester) => tester
      .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Siguiente'));

  testWidgets(
      'bloqueada: Siguiente apagado, swipe cerrado y la barra superior '
      'sigue libre', (tester) async {
    await _montar(tester);
    await _irAPagina11(tester);

    expect(_botonSiguiente(tester).onPressed, isNull,
        reason: 'grupo sin datos ⇒ el botón no deja avanzar');
    final tooltip = tester.widget<Tooltip>(
      find.descendant(
        of: find.byType(EdanNavigationBar),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tooltip.message, isNotEmpty);

    expect(_pageView(tester).physics, isA<NeverScrollableScrollPhysics>(),
        reason: 'Bug 2: con bloqueos el swipe no puede saltar la puerta');

    // El indicador superior sigue libre (decisión de diseño).
    expect(find.byType(EdanStepIndicator), findsOneWidget);

    // El intento de swipe no mueve la página.
    final antes = tester.getCenter(find.byType(PageView));
    await tester.fling(find.byType(PageView), const Offset(-500, 0), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getCenter(find.byType(PageView)), antes,
        reason: 'el PageView no avanzó con el bloqueo puesto');
  });

  testWidgets(
      'Bug 1: al cargar datos el botón se habilita y el swipe se reabre '
      'sin reconstruir la lista de páginas', (tester) async {
    await _montar(tester);
    await _irAPagina11(tester);

    expect(_botonSiguiente(tester).onPressed, isNull);

    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump(); // post-frame de _refrescarBloqueos (coalescido)
    await tester.pump();

    expect(_botonSiguiente(tester).onPressed, isNotNull,
        reason: 'Bug 1: la página avisó con onCambio y el gate se re-evaluó');
    expect(_pageView(tester).physics, isA<PageScrollPhysics>(),
        reason: 'sin bloqueos el swipe vuelve a estar abierto');

    // Avanza con el botón (no con swipe) a la página del responsable.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Siguiente'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Paso 5 de 6'), findsOneWidget,
        reason: 'de la página 11 (paso 4) pasó a la 13 (paso 5)');
  });

  testWidgets('la barra superior salta a otra página aunque haya bloqueos',
      (tester) async {
    await _montar(tester);
    await _irAPagina11(tester);
    expect(_botonSiguiente(tester).onPressed, isNull);

    await tester.tap(find.byTooltip('5. Responsable del formulario'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_botonSiguiente(tester).onPressed, isNotNull,
        reason: 'la página 13 es cabecera: nunca bloquea');
  });
}
