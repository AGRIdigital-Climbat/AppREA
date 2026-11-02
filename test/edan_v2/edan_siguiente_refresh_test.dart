/// Botón "Siguiente": la regla de bloqueo, página por página, y el refresh
/// ligero con el que la página le avisa al wizard.
///
/// Tres cosas se fijan acá:
///
///  * `bloqueosSiguiente` corre sobre TODAS las claves de `paginasWizard`
///    (tabla-driven): grupo apagado ⇒ vacío, grupo encendido sin datos ⇒
///    bloqueo, con datos ⇒ vacío. Sin precondition `imp*`, que la anularía
///    (imp* se deriva de los datos).
///  * `EdanNavigationBar` pinta apagado + tooltip cuando `onNext` es null y
///    habilitado cuando tiene callback.
///  * La página le avisa al wizard con `onCambio` (Bug 1: el botón quedaba
///    congelado porque el wizard no se re-enteraba de mutaciones hechas en
///    la página).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rea/models/edan.dart';
import 'package:rea/models/edan_registro_v2.dart';
import 'package:rea/screens/role_screens/resp/edan/edan_navigation_bar.dart';
import 'package:rea/screens/role_screens/resp/edan/edan_page11.dart';
import 'package:rea/services/edan_secciones_registry.dart';

/// Localidad con los [grupos] de la página encendidos y sin datos.
EdanLocalidad _locVacia(List<String> grupos) {
  final loc = EdanLocalidad(nombre: 'L', idTipoEvento: 1);
  for (final g in grupos) {
    switch (g) {
      case 'grupPoblacion':
        loc.grupPoblacion = true;
      case 'grupSalud':
        loc.grupSalud = true;
      case 'grupInfraestructura':
        loc.grupInfraestructura = true;
      case 'grupServicios':
        loc.grupServicios = true;
      case 'grupEducacion':
        loc.grupEducacion = true;
      case 'grupVivienda':
        loc.grupVivienda = true;
      case 'grupAgropecuario':
        loc.grupAgropecuario = true;
      case 'grupProteccion':
        loc.grupProteccion = true;
      case 'grupNecesidades':
        loc.grupNecesidades = true;
    }
  }
  return loc;
}

  /// Carga mínimo de datos válidos para que la página [pagina] NO bloquee.
  /// Incluye las 1:1 de la página (p. ej. 03/04): ahora Siguiente exige
  /// ≥1 hija válida (1:N, OR) Y el registro 1:1 completo.
  EdanLocalidad _locConDatos(String pagina) {
  final loc = _locVacia(
      EdanSeccionesRegistry.rutasDePagina(pagina)
          .map(EdanSeccionesRegistry.grupoDeRuta)
          .whereType<String>()
          .toSet()
          .toList());
  switch (pagina) {
    case '03':
      loc.impactoPoblacion = [
        EdanImpactoPoblacion(grupoEtario: 'Niño (a) 0-5 años', fallecidos: 1),
      ];
      // 1:1 de la página: primera respuesta debe ir COMPLETO para avanzar.
      loc.necesidadPrimeraRespuesta!.busqueda = true;
    case '04':
      loc.establecimientosSalud = [
        EdanEstablecimientoSalud(nombreEstablecimiento: 'CASERIO X'),
      ];
      // 1:1 de la página: necesidad de salud completa.
      loc.necesidadSalud!.botiquines = true;
    case '05':
      loc.danosViales = [EdanDanoVial(viaPuente: 'AV. CENTRAL')];
    case '06':
      loc.serviciosBasicos = [EdanServicioBasicoDetalle(tipo: 'agua_potable', afectado: true)];
    case '07':
      loc.unidadesEducativas = [
        EdanDanoUnidadEducativa(nombreEstablecimiento: 'IE SAN MARTIN'),
      ];
    case '08':
      loc.danosVivienda = [
        EdanDanoVivienda()
          ..danoTotal = 5
          ..viviendas = [EdanVivienda()],
      ];
    case '09':
      loc.danosAgricultura = [EdanDanoAgricultura(tipoCultivo: 'MAIZ')];
    case '10':
      loc.proteccion = [
        EdanGrupoVulnerable(idGrupoVulnerableCatalogo: 1, mujeres: 3),
      ];
    case '11':
      loc.necesidadHumanitaria!.alimentos = true;
  }
  return loc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bloqueosSiguiente: TODAS las páginas de paginasWizard', () {
    final claves = EdanSeccionesRegistry.paginasWizard.keys.toList();

    test('la tabla cubre las 12 páginas del wizard', () {
      expect(
        claves,
        containsAll([
          '01', '02', '03', '04', '05', '06', '07', '08', '09', '10', '11',
          '13',
        ]),
      );
    });

    for (final clave in claves) {
      final rutas = EdanSeccionesRegistry.rutasDePagina(clave);
      final grupos = rutas
          .map(EdanSeccionesRegistry.grupoDeRuta)
          .whereType<String>()
          .toSet()
          .toList();

      test('página $clave: sin grupo no exige nada', () {
        expect(
          EdanSeccionesRegistry.bloqueosSiguiente(
              EdanLocalidad(nombre: 'L', idTipoEvento: 1), rutas),
          isEmpty,
          reason: 'cabecera (01/02/13) y grupos apagados no bloquean',
        );
      });

      if (grupos.isEmpty) continue;

      test('página $clave ($grupos): grupo encendido sin datos bloquea', () {
        expect(
          EdanSeccionesRegistry.bloqueosSiguiente(_locVacia(grupos), rutas),
          isNotEmpty,
          reason: 'el botón debe quedar deshabilitado hasta cargar datos',
        );
      });

      test('página $clave: con datos no bloquea', () {
        expect(
          EdanSeccionesRegistry.bloqueosSiguiente(_locConDatos(clave), rutas),
          isEmpty,
          reason: 'página llena (1:N ≥1 hija + 1:1 completo) no bloquea; '
              'sin precondition imp*',
        );
      });
    }
  });

  group('EdanNavigationBar: Siguiente habilitado / deshabilitado', () {
    Widget barra({VoidCallback? onNext, String? nextTooltip}) =>
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: EdanNavigationBar(
              showBack: false,
              isLastPage: false,
              isPreview: false,
              saving: false,
              onBack: () {},
              onNext: onNext,
              nextTooltip: nextTooltip,
            ),
          ),
        );

    testWidgets('onNext null ⇒ apagado con tooltip', (tester) async {
      await tester.pumpWidget(barra(nextTooltip: 'Falta completar'));
      final boton = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Siguiente'));
      expect(boton.onPressed, isNull);
      expect(find.byType(Tooltip), findsOneWidget);
    });

    testWidgets('onNext con callback ⇒ habilitado y navega', (tester) async {
      var tocadas = 0;
      await tester.pumpWidget(barra(onNext: () => tocadas++));
      final boton = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Siguiente'));
      expect(boton.onPressed, isNotNull);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Siguiente'));
      await tester.pump();
      expect(tocadas, 1);
    });

    testWidgets('onNext null ⇒ el toque no avanza', (tester) async {
      var tocadas = 0;
      await tester.pumpWidget(barra(onNext: null, nextTooltip: 'Faltan'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Siguiente'),
          warnIfMissed: false);
      await tester.pump();
      expect(tocadas, 0);
    });
  });

  group('Bug 1: la página notifica al wizard (onCambio)', () {
    // Sin silenciadores: `EdanPage11` mete sus bloques en `Card` (Material),
    // así que la queja cosmética del `CheckboxListTile` ya no se produce. Si
    // reapareciera, estos tests fallan (el binding la registra como error).

    testWidgets('marcar una necesidad dispara onCambio', (tester) async {
      final loc = EdanLocalidad(nombre: 'L', idTipoEvento: 1)..grupNecesidades = true;
      var avisos = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: EdanPage11(localidad: loc, onCambio: () => avisos++),
            ),
          ),
        ),
      );
      expect(avisos, 0, reason: 'el build no notifica por sí solo');

      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();

      expect(loc.necesidadHumanitaria!.alimentos, isTrue);
      expect(avisos, greaterThan(0),
          reason: 'sin este aviso el botón Siguiente queda congelado');
    });

    testWidgets('sin onCambio la página sigue funcionando', (tester) async {
      final loc = EdanLocalidad(nombre: 'L', idTipoEvento: 1)..grupNecesidades = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: EdanPage11(localidad: loc)),
          ),
        ),
      );
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      expect(loc.necesidadHumanitaria!.alimentos, isTrue);
    });
  });
}
