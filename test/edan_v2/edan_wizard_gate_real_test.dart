/// Flujo real RESP: wizard con store V2 + SQLite, marca grupo en page01 y
/// verifica que el Siguiente de la página de datos quede bloqueado.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:rea/config/theme.dart';
import 'package:rea/models/edan.dart';
import 'package:rea/providers/reporte_provider.dart';
import 'package:rea/screens/role_screens/resp/edan/edan_form_wizard.dart';
import 'package:rea/screens/role_screens/resp/edan/edan_navigation_bar.dart';
import 'package:rea/screens/role_screens/resp/edan/edan_page01.dart';
import 'package:rea/services/database_helper.dart';
import 'package:rea/services/edan/edan_store_v2.dart';
import 'package:rea/widgets/custom_text_field.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _ReporteStub extends ReporteProvider {
  @override
  Future<void> fetchGruposVulnerablesIfNeeded() async {}

  @override
  Future<void> fetchGruposEtariosIfNeeded() async {}

  @override
  Future<void> loadGeography() async {}

  // page01 lo dispara en post-frame: sin override intentaría red y BD reales
  // (deja handles de SQLite colgando y el tearDown no puede borrar el temp).
  @override
  Future<Map<String, int>> fetchAndCacheCatalogs() async => const {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  final db = DatabaseHelper.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('edan_gate_real');
    DatabaseHelper.rutaDePrueba = p.join(dir.path, 'test.db');
  });

  tearDown(() async {
    await db.cerrarParaPrueba();
    DatabaseHelper.rutaDePrueba = null;
    if (!dir.existsSync()) return;
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {
      // Windows + sqflite ffi pueden sostener el handle del .db unos ms tras
      // el close: reintenta una vez y, si sigue trabado, deja el temp (lo
      // limpia el SO); no debe fallar el test por higiene del directorio.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  ElevatedButton boton(WidgetTester t) => t
      .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Siguiente'));

  Future<void> montar(WidgetTester tester, {EdanLocalidad? conLocalidad}) async {
    // Tamaño de celular: la superficie por defecto de los tests (800x600)
    // deja fuera de pantalla la lista de impactos de page01.
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.toString().contains('ListTile background color')) return;
      prev?.call(d);
    };
    addTearDown(() => FlutterError.onError = prev);

    await tester.pumpWidget(
      PaletteScope(
        palette: Palettes.rea,
        child: MaterialApp(
          theme: AppTheme.buildTheme(Palettes.rea),
          home: ChangeNotifierProvider<ReporteProvider>(
            create: (_) => _ReporteStub(),
            child: EdanFormWizard(
              edanAEditar: conLocalidad == null
                  ? null
                  : Edan(localidades: [conLocalidad]),
              storeV2: EdanStoreV2(db: db),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Modelo de formulario nuevo con TODOS los asteriscos de page01/02
  /// llenos (sin ningún grupo marcado).
  EdanLocalidad _prellenado({String nombre = 'L', bool salud = false}) =>
      EdanLocalidad(
        nombre: nombre,
        idTipoEvento: 1,
        tipoEventoNombre: 'Inundación',
        tipoLocalidad: 'Comunidad',
        fechaEvento: '2026-10-01',
        horaEvento: '09:00',
        totalPoblacionAfectada: 10,
        totalFamiliasAfectadas: 10,
        totalFamiliasDamnificadas: 10,
      )..grupSalud = salud;

  testWidgets('nuevo formulario: page01 sin check no deja salir; marcado '
      '"En población" abre 01→02 y la página 03 queda bloqueada',
      (tester) async {
    await montar(tester, conLocalidad: _prellenado());

    await tester.tap(find.byTooltip('2. Datos generales'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(EdanPage01), findsOneWidget);

    // Campos asteriscados llenos, pero NINGUNA casilla marcada: el formulario
    // se arma en page01 → Siguiente apagado con ese único faltante.
    expect(boton(tester).onPressed, isNull,
        reason: 'sin al menos un grupo marcado no se avanza de page01');
    final tooltip = tester.widget<Tooltip>(
      find.descendant(
        of: find.byType(EdanNavigationBar),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tooltip.message, contains('categoría'));

    // Marca "En población".
    expect(find.text('En población'), findsOneWidget);
    await tester.ensureVisible(find.text('En población'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('En población'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Ahora page01 pasa (campos + check).
    expect(boton(tester).onPressed, isNotNull,
        reason: 'campos llenos y un check ⇒ Siguiente habilitado');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Siguiente'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Paso 3 de 6'), findsOneWidget);

    // Page02 con los 3 totales > 0: habilitado.
    expect(boton(tester).onPressed, isNotNull);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Siguiente'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Paso 4 de 6'), findsOneWidget,
        reason: 'llegó a la página 03 (Impacto en la población)');
    expect(
      find.descendant(
        of: find.byType(EdanNavigationBar),
        matching: find.byType(Tooltip),
      ),
      findsOneWidget,
      reason: 'hay tooltip de bloqueo',
    );
    expect(boton(tester).onPressed, isNull,
        reason: 'grupo marcado SIN datos ⇒ Siguiente apagado en page03');
  });

  testWidgets('page01: escribir el nombre habilita Siguiente al instante '
      '(onCambio page01 → _refrescarBloqueos)', (tester) async {
    // Todo lleno MENOS nombre; un check marcado (salud) para que ese sea el
    // único faltante y el tooltip diga exactamente lo que falta.
    await montar(tester, conLocalidad: _prellenado(nombre: '', salud: true));

    await tester.tap(find.byTooltip('2. Datos generales'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(boton(tester).onPressed, isNull,
        reason: 'nombre vacío ⇒ bloqueado aunque el resto esté lleno');
    final tooltip = tester.widget<Tooltip>(
      find.descendant(
        of: find.byType(EdanNavigationBar),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tooltip.message, contains('nombre del lugar'));

    await tester.enterText(
      find.descendant(
        of: find.byType(EdanPage01),
        matching: find.byType(CustomTextField),
      ).first,
      'Villa Nueva',
    );
    // post-frame coalescido de _refrescarBloqueos.
    await tester.pump();
    await tester.pump();

    expect(boton(tester).onPressed, isNotNull,
        reason: 'sin notificar al wizard el botón quedaría congelado '
            'hasta un rebuild ajeno');
  });

  testWidgets('reabrir borrador guardado: la página 03 existe y sigue '
      'bloqueada', (tester) async {
    final store = EdanStoreV2(db: db);
    const uuid = 'uuid-borrador-gate';
    final guardada = EdanLocalidad(
      nombre: 'L',
      idTipoEvento: 1,
      uuidEdanLocalidad: uuid,
      // Con 01 y 02 completas, el auto-salto del snapshot ('primera página
      // incompleta') aterriza en la 03: la página que este test quiere ver.
      totalPoblacionAfectada: 10,
    )..grupPoblacion = true;
    // OJO: dentro de `testWidgets` el body corre en FakeAsync; los futures
    // reales de sqflite (aislado/port del motor ffi) NO completan a menos
    // que se los envuelva en `tester.runAsync`. Un `await` pelado cuelga
    // el test hasta el timeout de 10 min.
    await tester.runAsync(() => store.guardarTodo(
          guardada,
          usuarioId: 1,
          seccionesActivas: const ['impacto-poblacion', 'primera-respuesta'],
          tipos: const [],
        ));

    final cargada =
        await tester.runAsync(() => store.cargarFormulario(uuid));
    expect(cargada, isNotNull);
    expect(cargada!.grupPoblacion, isTrue,
        reason: 'el flag grup sobrevive al guardado/reapertura');

    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.toString().contains('ListTile background color')) return;
      prev?.call(d);
    };
    addTearDown(() => FlutterError.onError = prev);

    // El wizard dispara `_prepararSnapshot()` desde initState (consulta real
    // a `secciones_grupos_local`). Si el pump queda fuera de `runAsync`, la
    // consulta termina INFLIGHT al cerrar el test: FakeAsync reporta "Timer
    // is still pending" y el tearDown de la BD deja el error "database
    // already closed". Se monta y se deja respirar la sync dentro de
    // `runAsync`, con la BD aún abierta.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        PaletteScope(
          palette: Palettes.rea,
          child: MaterialApp(
            theme: AppTheme.buildTheme(Palettes.rea),
            home: ChangeNotifierProvider<ReporteProvider>(
              create: (_) => _ReporteStub(),
              child: EdanFormWizard(
                edanAEditar: Edan(localidades: [cargada]),
                storeV2: store,
              ),
            ),
          ),
        ),
      );
      // Deja completar la sync async del snapshot (usa la BD real).
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    // Drena los timers FAKES que esa sync disparó (setState del snapshot y
    // el animateToPage de `_irAPrimeraPaginaIncompleta`, 300 ms).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // La página 03 existe en el indicador superior.
    expect(find.byTooltip('4. Impacto en la población'), findsOneWidget,
        reason: 'la sección se pinta al reabrir');

    await tester.tap(find.byTooltip('4. Impacto en la población'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(boton(tester).onPressed, isNull,
        reason: 'reabierto SIN datos ⇒ Siguiente apagado');
  });
}
