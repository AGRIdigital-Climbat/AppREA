/// Franja de progreso del UGR (rol 6): prioridad histórico del municipio >
/// motor V2 (primera descarga de reportes propios y sync) > catálogos.
/// Solo testea presentación y visibilidad; el progreso real lo publican
/// `EdanSyncService` y `EdanStoreV2` (notifiers globales).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rea/providers/reporte_provider.dart';
import 'package:rea/services/edan/edan_store_v2.dart';
import 'package:rea/services/edan_sync_service.dart';
import 'package:rea/widgets/ugr_progress_franja.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final rp = ReporteProvider();

  late ValueNotifier<bool> municipioFlag;
  late ValueNotifier<String> faseMunicipio;
  late ValueNotifier<int> totalMunicipio;
  late ValueNotifier<int> hechasMunicipio;
  late ValueNotifier<bool> storeSync;
  late ValueNotifier<String> faseSync;
  late ValueNotifier<int> fotosTotal;
  late ValueNotifier<int> fotosHechas;

  setUp(() {
    municipioFlag = EdanSyncService.instance.sincronizandoMunicipio;
    faseMunicipio = EdanSyncService.instance.faseMunicipio;
    totalMunicipio = EdanSyncService.instance.municipioTotal;
    hechasMunicipio = EdanSyncService.instance.municipioHechas;
    storeSync = EdanStoreV2.instance.sincronizandoNotifier;
    faseSync = EdanStoreV2.instance.faseSync;
    fotosTotal = EdanStoreV2.instance.descargaFotosTotal;
    fotosHechas = EdanStoreV2.instance.descargaFotosHechas;
  });

  tearDown(() {
    municipioFlag.value = false;
    faseMunicipio.value = '';
    totalMunicipio.value = 0;
    hechasMunicipio.value = 0;
    storeSync.value = false;
    faseSync.value = '';
    fotosTotal.value = 0;
    fotosHechas.value = 0;
  });

  Future<void> montar(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              UgrProgressFranja(rp: rp),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('sin actividad: la franja no pinta nada', (tester) async {
    await montar(tester);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('histórico del municipio: GET en vuelo muestra spinner con fase',
      (tester) async {
    municipioFlag.value = true;
    faseMunicipio.value = 'Consultando EDANs del municipio...';
    await montar(tester);
    expect(find.text('Consultando EDANs del municipio...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('histórico del municipio: X de Y con barra y %', (tester) async {
    municipioFlag.value = true;
    faseMunicipio.value = 'Guardando histórico del municipio';
    totalMunicipio.value = 10;
    hechasMunicipio.value = 4;
    await montar(tester);
    expect(
      find.text('Guardando histórico del municipio 4 de 10'),
      findsOneWidget,
    );
    expect(find.text('40%'), findsOneWidget);
    final barra = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator));
    expect(barra.value, closeTo(0.4, 0.001));
  });

  testWidgets('motor V2: fase de sync con puntos suspensivos', (tester) async {
    storeSync.value = true;
    faseSync.value = 'Subiendo cambios';
    await montar(tester);
    expect(find.text('Subiendo cambios...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('motor V2: fotos X de Y con barra y %', (tester) async {
    storeSync.value = true;
    faseSync.value = 'Descargando fotos';
    fotosTotal.value = 2;
    fotosHechas.value = 1;
    await montar(tester);
    expect(find.text('Descargando fotos 1 de 2...'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('prioridad: municipio manda sobre el motor cuando ambos corren',
      (tester) async {
    municipioFlag.value = true;
    totalMunicipio.value = 5;
    hechasMunicipio.value = 1;
    storeSync.value = true;
    faseSync.value = 'Subiendo cambios';
    await montar(tester);
    expect(
      find.text('Guardando histórico del municipio 1 de 5'),
      findsOneWidget,
    );
    expect(find.text('Subiendo cambios...'), findsNothing);
  });
}
