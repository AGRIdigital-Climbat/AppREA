/// Tándem demográfico de page01 (2026-10-18): 'En población' y 'Necesidades
/// en protección' se marcan y desmarcan JUNTOS; al desmarcar, el tándem
/// vacía/purga ambas secciones (regla `grup* true ⇒ manda datos`: un grupo
/// desactivado no puede dejar filas vivas en el POST). El resto de los
/// checkboxes sigue independiente.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rea/models/edan.dart';
import 'package:rea/providers/reporte_provider.dart';
import 'package:rea/screens/role_screens/resp/edan/edan_page01.dart';

class _StubProvider extends ReporteProvider {
  @override
  Future<void> fetchGruposVulnerablesIfNeeded() async {}

  @override
  Future<void> fetchGruposEtariosIfNeeded() async {}

  @override
  Future<void> loadGeography() async {}

  @override
  Future<Map<String, int>> fetchAndCacheCatalogs() async => const {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<EdanLocalidad> montar(WidgetTester tester,
      {bool saludAntes = false}) async {
    final loc = EdanLocalidad(nombre: 'L', idTipoEvento: 1)
      ..grupSalud = saludAntes;
    var avisos = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ReporteProvider>(
          create: (_) => _StubProvider(),
          child: Scaffold(
            body: SingleChildScrollView(
              child: EdanPage01(
                localidad: loc,
                onImpactosCambio: () => avisos++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(avisos, 0, reason: 'el build no notifica por sí solo');
    return loc;
  }

  testWidgets('marcar "En población" marca protección y siembra ambas',
      (tester) async {
    final loc = await montar(tester);
    await tester.ensureVisible(find.text('En población'));
    await tester.tap(find.text('En población'));
    await tester.pump();

    expect(loc.grupPoblacion, isTrue);
    expect(loc.grupProteccion, isTrue,
        reason: 'tándem: la hermana se marca sola');
    expect(loc.impactoPoblacion, hasLength(1));
    expect(loc.impactoPoblacion.first.gruposEtarios, hasLength(4));
    expect(loc.proteccion, hasLength(8),
        reason: 'semilla de page10 aunque el catálogo esté vacío (defaults)');
    expect(find.text('Necesidades en protección'), findsOneWidget);
    // El checkbox de protección se pinta marcado (ambos al unísono).
    final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
    expect(
      checkboxes.where((c) => c.value == true).length,
      greaterThanOrEqualTo(2),
    );
  });

  testWidgets('desmarcar "En protección" desmarca población Y vacía los '
      'datos de ambas', (tester) async {
    final loc = await montar(tester);
    await tester.ensureVisible(find.text('En población'));
    await tester.tap(find.text('En población'));
    await tester.pump();
    loc.impactoPoblacion.first.gruposEtarios.first
      ..marcado = true
      ..fallecidos = 3;
    loc.proteccion.first.mujeres = 5;

    await tester.ensureVisible(find.text('Necesidades en protección'));
    await tester.tap(find.text('Necesidades en protección'));
    await tester.pump();

    expect(loc.grupPoblacion, isFalse,
        reason: 'tándem también al desmarcar desde la hermana');
    expect(loc.grupProteccion, isFalse);
    expect(loc.impactoPoblacion, isEmpty,
        reason: 'vaciarSecciones de la hermana: sin grup no puede quedar '
            'fila viva que viaje en el POST');
    expect(loc.proteccion, isEmpty);
  });

  testWidgets('marcar desde "Necesidades en protección" propaga a población',
      (tester) async {
    final loc = await montar(tester);
    await tester.ensureVisible(find.text('Necesidades en protección'));
    await tester.tap(find.text('Necesidades en protección'));
    await tester.pump();
    expect(loc.grupProteccion, isTrue);
    expect(loc.grupPoblacion, isTrue);
    expect(loc.proteccion, hasLength(8));
    expect(loc.impactoPoblacion, hasLength(1));
  });

  testWidgets('otros grupos siguen independientes: "En salud" no toca el '
      'tándem', (tester) async {
    final loc = await montar(tester);
    await tester.ensureVisible(find.text('En salud'));
    await tester.tap(find.text('En salud'));
    await tester.pump();
    expect(loc.grupSalud, isTrue);
    expect(loc.grupPoblacion, isFalse);
    expect(loc.grupProteccion, isFalse);
  });
}
