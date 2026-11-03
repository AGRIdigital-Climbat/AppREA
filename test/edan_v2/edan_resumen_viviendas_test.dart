/// Vista previa 1:N de viviendas (2026-11-02): el resumen de "Impacto en
/// viviendas" debe mostrar CADA hija con su daño, sus coordenadas y SU propia
/// foto. En el flujo V2 la foto vive en la hija (no en el padre); antes el
/// resumen solo pintaba al padre y la foto de la vivienda no aparecía en
/// "Resumen y envío" (caso del usuario: registro "Escoma").
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rea/config/theme.dart';
import 'package:rea/models/edan.dart';
import 'package:rea/models/edan_registro_v2.dart';
import 'package:rea/screens/role_screens/resp/edan/edan_resumen_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('edan_resumen_viv');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> montar(WidgetTester tester, EdanLocalidad l) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildTheme(Palettes.rea),
        home: PaletteScope(
          palette: Palettes.rea,
          child: Scaffold(
            body: SingleChildScrollView(
              child: EdanResumenPage(
                localidad: l,
                seccionesCompletas:
                    EdanResumenPage.calcularSeccionesCompletas(l),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  EdanLocalidad locConHija(EdanVivienda hija) {
    final padre = EdanDanoVivienda(
      idSeccion: 'b4341e9a-7e91-4d48-b93b-761c4855d6e1',
      comunidad: 'Escoma',
      viviendas: [hija],
    );
    return EdanLocalidad(nombre: 'Escoma', idTipoEvento: 40)
      ..grupVivienda = true
      ..impDanosVivienda = true
      ..danosVivienda = [padre];
  }

  testWidgets('hija con foto: el resumen pinta "Vivienda 1", su daño y SU '
      'propia foto (antes no aparecía ninguna)', (tester) async {
    // Archivo local REAL: la miniatura resuelve por disco (sin red) y el
    // decodificador falla controlado por el errorBuilder — irrelevante para
    // las aserciones, que van por los textos.
    final foto = File(p.join(dir.path, 'vivienda.jpg'));
    foto.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
    await montar(tester, locConHija(EdanVivienda(
      uuidRegistro: '1d65cb56-9775-462c-abb0-5c2152b41f51',
      tipoDano: EdanViviendaTipo.total,
      coordenadaLat: -16.5096056,
      coordenadaLon: -68.1057141,
      fotografia: foto.path,
    )));

    expect(find.text('Vivienda 1'), findsOneWidget);
    expect(find.text('TOTAL'), findsOneWidget);
    // El padre NO lleva foto en el flujo V2; sin el fix esta etiqueta no
    // existía y la foto de la hija era invisible en el resumen.
    expect(find.text('Fotografía de respaldo'), findsOneWidget);
    // Coordenadas de la hija (GrillaFotos las pinta junto a la foto).
    expect(find.textContaining('-16.50961'), findsOneWidget);
    // Contadores del padre derivados de la hija (aparecen también en el bloque
    // "total vivienda" de abajo: por eso findsWidgets).
    expect(find.text('Daño total'), findsWidgets);
  });

  testWidgets('hija sin foto pero con coords: pinta la línea "Coordenadas" y '
      'no inventa una foto', (tester) async {
    await montar(tester, locConHija(EdanVivienda(
      tipoDano: EdanViviendaTipo.parcial,
      coordenadaLat: -16.5,
      coordenadaLon: -68.1,
    )));

    expect(find.text('Vivienda 1'), findsOneWidget);
    expect(find.text('PARCIAL'), findsOneWidget);
    expect(find.text('Fotografía de respaldo'), findsNothing);
    expect(find.text('Coordenadas'), findsOneWidget);
    // Derivación del contador por hija (padre + bloque "total vivienda").
    expect(find.text('Daño parcial'), findsWidgets);
  });
}
