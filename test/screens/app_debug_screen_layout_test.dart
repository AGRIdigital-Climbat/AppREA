import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rea/screens/app_debug_screen.dart';
import 'package:rea/services/app_logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Prueba de maquetación: la pantalla de registro debe caber sin desbordes
/// en un teléfono angosto (360 dp). En debug, cualquier overflow registra un
/// FlutterError y `takeException` lo destapa.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('app_debug_layout');
    AppLogger.rutaDePrueba = p.join(dir.path, 'layout_logs.db');
    await AppLogger.instance.inicializar();

    // Entradas representativas: títulos largos, bodies enormes, stacks.
    AppLogger.instance.api(
      metodo: 'POST',
      url: 'https://api.climbat.net/api/v2/edan/formularios/completo',
      estado: 200,
      request: '{"uuid_edan_localidad":"8f14e45f-ceea-467f-a1c0-0d5e6d2f9b11",'
          '"imp_impacto_poblacion":true,"impacto_poblacion":[{"id_grupo_etario":1'
          ',"fallecidos":0,"heridos":2}]}',
      response: '{"success":true,"message":"OK","data":{"id_edan_localidad":343'
          '463,"secciones":{"danos_vivienda":{"viviendas":[{"tipo_dano":"Total"}'
          ']}}}}',
      duracion: const Duration(milliseconds: 842),
    );
    AppLogger.instance.error(
      titulo: 'Error asíncrono global: SocketException: Failed host lookup',
      exception: 'SocketException',
      stack: StackTrace.current,
    );
    AppLogger.instance.nav(
      titulo: 'push → ugr_localidades_tab (municipio 70101 Santa Cruz de la '
          'Sierra, departamento Santa Cruz, Bolivia)',
      pantalla: 'UgrLocalidadesTab',
    );
    AppLogger.instance.sync(
      titulo: 'Enviar EDAN: FALLÓ',
      detalle: 'uuid=8f14e45f-ceea-467f-a1c0-0d5e6d2f9b11 destino_estado=2 '
          'error=400 Faltan flags de sección en POST /formularios/completo '
          '(se envían las 14 con true/false): [imp_danos_viales]',
      nivel: AppLogLevel.error,
    );
    await AppLogger.instance.esperarFlush();
  });

  tearDown(() async {
    await AppLogger.instance.apagarParaPrueba();
    AppLogger.rutaDePrueba = null;
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  testWidgets('no desborda en 360 dp, expande y abre menú sin errores',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // La carga desde SQLite es IO real: corre fuera del fake-async del test.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const MaterialApp(home: AppDebugScreen()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await tester.pump();

      // Panel, filtros y lista pintados.
      expect(find.text('Registro de la app'), findsOneWidget);
      expect(find.text('SOLO ERRORES'), findsOneWidget);
      expect(find.textContaining('Enviar EDAN: FALLÓ'), findsWidgets);

      // Expandir la primera tarjeta (toca el título de la cabecera).
      await tester.tap(find.textContaining('POST /edan/formularios/completo')
          .first);
      await tester.pump();
      expect(find.text('REQUEST'), findsWidgets);

      // Menú de exportar/limpiar.
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Descargar .txt'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    expect(tester.takeException(), isNull);
  });
}
