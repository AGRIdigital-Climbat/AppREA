/// Regla de visualización de catálogos (2026-10-18): en resumen/preview se
/// ven SIEMPRE los 4 grupos etarios y los 8 grupos vulnerables, rellenos con
/// 0 donde no hay datos (espejo visual del set exacto §20.10.E/§20.11 que
/// exige el POST). Cubre `EdanGrupoEtario.completarSet4`,
/// `EdanGrupoVulnerable.completarSet8` y el render de `EdanResumenPage`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rea/config/theme.dart';
import 'package:rea/models/edan.dart';
import 'package:rea/screens/role_screens/resp/edan/edan_resumen_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('completarSet4', () {
    test('vacío → los 4 canónicos en ceros, en orden de catálogo', () {
      final r = EdanGrupoEtario.completarSet4([]);
      expect(r.map((g) => g.idGrupoEtario), [1, 2, 3, 4]);
      expect(r.map((g) => g.rango[0]), ['N', 'E', 'A', 'A']);
      expect(r.every((g) => g.fallecidos == 0 && g.heridos == 0), isTrue);
    });

    test('fusiona por id, conserva nombres propios y los extras no caben al final',
        () {
      final r = EdanGrupoEtario.completarSet4([
        EdanGrupoEtario(
            rango: 'NOMBRE CATALOGO 2',
            idGrupoEtarioCatalogo: 2,
            heridos: 5),
        EdanGrupoEtario(rango: 'Rango raro', fallecidos: 1), // sin id
      ]);
      expect(r.length, 5); // 4 slots + 1 extra
      expect(r[1].rango, 'NOMBRE CATALOGO 2');
      expect(r[1].heridos, 5);
      expect(r[0].fallecidos, 0);
      expect(r.last.rango, 'Rango raro');
    });
  });

  group('completarSet8', () {
    test('defaults con un grupo lleno → 8 visibles, nombre por id de respaldo',
        () {
      final l = EdanLocalidad(nombre: 'L', idTipoEvento: 1);
      final completos = EdanGrupoVulnerable.completarSet8(l.proteccion);
      expect(completos, hasLength(8));
      expect(completos.every((g) => g.idGrupoVulnerable != null), isTrue);
      // Fila hidratada típica: id puesto, nombre nulo → el canónico lo cubre.
      final sinNombre = [
        EdanGrupoVulnerable(idGrupoVulnerableCatalogo: 3, mujeres: 4),
      ];
      final r = EdanGrupoVulnerable.completarSet8(sinNombre);
      expect(r, hasLength(8));
      expect(r[2].nombreGrupo, 'Adolescentes');
      expect(r[2].mujeres, 4);
      expect(r[7].nombreGrupo, 'Personas con enfermedad crónica');
      expect(r[7].total, 0);
    });
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
    await tester.pump();
  }

  testWidgets('resumen: los 4 grupos etarios con los vacíos en 0',
      (tester) async {
    final l = EdanLocalidad(nombre: 'L', idTipoEvento: 1)
      ..grupPoblacion = true;
    l.impactoPoblacion = [
      EdanImpactoPoblacion(
        grupoEtario: 'Total',
        fallecidos: 2,
        heridos: 1,
        gruposEtarios: [
          EdanGrupoEtario(
              rango: 'Niño (a) 0-5 años',
              idGrupoEtarioCatalogo: 1,
              fallecidos: 2,
              marcado: true),
          EdanGrupoEtario(
              rango: 'Escolar de 6-18 años', idGrupoEtarioCatalogo: 2),
          EdanGrupoEtario(
              rango: 'Adulto de 19-60 años',
              idGrupoEtarioCatalogo: 3,
              heridos: 1,
              marcado: true),
          EdanGrupoEtario(
              rango: 'Adulto mayor de 60 años adelante',
              idGrupoEtarioCatalogo: 4),
        ],
      ),
    ];
    l.recalcularImpDesdeListas();
    await montar(tester, l);

    // Los cuatro rangos visibles...
    expect(find.text('Rango', skipOffstage: false), findsNWidgets(4));
    expect(find.textContaining('Escolar de 6-18 años'), findsOneWidget);
    expect(find.textContaining('Adulto mayor de 60 años adelante'),
        findsOneWidget);
    // ...y los vacíos con sus tres cifras en 0 (4 cards x 3 = 12 ceros +
    // los del bloque total). Basta con verificar los '0' en la sección:
    expect(find.text('0'), findsAtLeastNWidgets(6));
  });

  testWidgets('resumen legacy plano: filas por rango + slots faltantes en 0',
      (tester) async {
    final l = EdanLocalidad(nombre: 'L', idTipoEvento: 1)
      ..grupPoblacion = true;
    l.impactoPoblacion = [
      EdanImpactoPoblacion(
        grupoEtario: 'Niño (a) 0-5 años',
        fallecidos: 3,
        gruposEtarios: [],
      ),
      EdanImpactoPoblacion(
        grupoEtario: 'Escolar de 6-18 años',
        heridos: 2,
        gruposEtarios: [],
      ),
    ];
    l.recalcularImpDesdeListas();
    await montar(tester, l);
    expect(find.text('Rango', skipOffstage: false), findsNWidgets(4));
    expect(find.textContaining('Adulto de 19-60 años'), findsOneWidget);
    expect(find.textContaining('Adulto mayor de 60 años adelante'),
        findsOneWidget);
  });

  testWidgets('resumen: los 8 grupos vulnerables, vacíos en 0 y apoyos',
      (tester) async {
    final l = EdanLocalidad(nombre: 'L', idTipoEvento: 1)
      ..grupProteccion = true;
    l.proteccion[2].mujeres = 4; // Adolescentes
    l.recalcularImpDesdeListas();
    await montar(tester, l);

    expect(find.text('Grupo', skipOffstage: false), findsNWidgets(8));
    expect(find.textContaining('Adolescentes'), findsOneWidget);
    expect(find.textContaining('Personas con enfermedad crónica'),
        findsOneWidget);
    // Apoyos siempre visibles: — = sin respuesta.
    expect(find.text('—', skipOffstage: false), findsAtLeastNWidgets(14));
    expect(find.text('Grupo vulnerable'), findsNothing,
        reason: 'ningún enunciado queda sin resolver');
  });
}
