/// page10 (Necesidades en protección): los enunciados de los checkboxes se
/// pueblan desde el CATÁLOGO de grupos vulnerables. La hidratación desde
/// `filas_seccion` llega sin `nombre_grupo` (el `toApiJson` no lo envía: el
/// servidor rechaza campos extra), y el parche del post-frame debe resolver
/// id→nombre con el catálogo descargado (`fetchGruposVulnerablesIfNeeded`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rea/models/edan.dart';
import 'package:rea/models/reporte.dart';
import 'package:rea/providers/reporte_provider.dart';
import 'package:rea/screens/role_screens/resp/edan/edan_page10.dart';

class _CatalogoStub extends ReporteProvider {
  final List<GrupoVulnerableCatalogo> catalogo;

  _CatalogoStub(this.catalogo);

  @override
  Future<void> fetchGruposVulnerablesIfNeeded() async {}

  @override
  List<GrupoVulnerableCatalogo> get gruposVulnerables => catalogo;
}

/// Nombres canónicos de los 8 defaults de `EdanLocalidad._proteccionPorDefecto`
/// (los que trae el modelo sembrado sin catálogo).
const _kNombresCanon = [
  'Niñas y niños 0-5 años',
  'Niñas y niños 6-12 años',
  'Adolescentes',
  'Mujeres lactantes',
  'Mujeres embarazadas',
  'Adultos mayores',
  'Personas con discapacidad',
  'Personas con enfermedad crónica',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Ya no se silencia ninguna queja del `CheckboxListTile`: las páginas del
  // wizard usan `Card` (Material) como fondo del bloque, así que el aviso
  // "ListTile background color or ink splashes may be invisible" no se produce.
  // Si volviera a aparecer, estos tests fallan solos.

  final stubDistinto = _CatalogoStub([
    for (var i = 1; i <= 8; i++)
      GrupoVulnerableCatalogo(
        idGrupoVulnerable: i,
        codigo: 'GV$i',
        nombre: 'Enunciado del catálogo $i',
      ),
  ]);

  testWidgets('filas hidratadas sin nombre muestran el enunciado del catálogo',
      (tester) async {
    // Como `cargarSecciones` sin catálogo en BD: id presente, nombre null.
    final loc = EdanLocalidad(nombre: 'L', idTipoEvento: 1)
      ..grupProteccion = true
      ..proteccion = [
        for (var i = 1; i <= 8; i++)
          EdanGrupoVulnerable(
            idSeccion: '0000000$i-0000-4000-8000-00000000000$i',
            idGrupoVulnerableCatalogo: i,
          ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ReporteProvider>(
          create: (_) => stubDistinto,
          child: Scaffold(
            body: SingleChildScrollView(
              child: EdanPage10(localidad: loc),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Enunciado del catálogo 1'), findsOneWidget);
    expect(find.text('Enunciado del catálogo 8'), findsOneWidget);
    expect(find.text('Grupo vulnerable'), findsNothing,
        reason: 'ningún checkbox queda con el texto genérico de relleno');

    // El check sigue funcionando: marcar despliega los campos del grupo.
    await tester.tap(find.byType(CheckboxListTile).at(2));
    await tester.pump();
    expect(find.text('N° Mujeres'), findsWidgets);
    // Y el id ya venía puesto: no se toca.
    expect(loc.proteccion[2].idGrupoVulnerableCatalogo, 3);
    expect(loc.proteccion[2].nombreGrupo, 'Enunciado del catálogo 3');
  });

  testWidgets('modelo con defaults sembrados: id se empareja por nombre y '
      'el catálogo autoritativo pinta el enunciado',
      (tester) async {
    final loc = EdanLocalidad(nombre: 'L', idTipoEvento: 1)
      ..grupProteccion = true;
    // `EdanLocalidad()` trae los 8 defaults con nombre canónico y sin id.
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ReporteProvider>(
          create: (_) => _CatalogoStub([
            for (var i = 0; i < 8; i++)
              GrupoVulnerableCatalogo(
                idGrupoVulnerable: i + 1,
                codigo: 'GV${i + 1}',
                nombre: _kNombresCanon[i],
              ),
          ]),
          child: Scaffold(
            body: SingleChildScrollView(
              child: EdanPage10(localidad: loc),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      loc.proteccion.every((g) => g.idGrupoVulnerableCatalogo != null),
      isTrue,
      reason: 'nombre→id sigue remediándose (por nombre normalizado)',
    );
    expect(find.text('Adolescentes'), findsOneWidget);
    expect(loc.proteccion[2].idGrupoVulnerableCatalogo, 3);
  });

  testWidgets('modelo contaminado (duplicados legacy + sintéticos): page10 '
      'muestra exactamente los 8 del catálogo', (tester) async {
    // Simula la hidratación cruda de un borrador contaminado: 8 filas legacy
    // (nombre canónico, sin id) + 8 sintéticas (id, sin nombre) = 16.
    final loc = EdanLocalidad(nombre: 'L', idTipoEvento: 1)
      ..grupProteccion = true;
    loc.proteccion = [
      for (final n in _kNombresCanon) EdanGrupoVulnerable(nombreGrupo: n),
      for (var i = 1; i <= 8; i++)
        EdanGrupoVulnerable(idGrupoVulnerableCatalogo: i),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ReporteProvider>(
          create: (_) => _CatalogoStub([
            for (var i = 0; i < 8; i++)
              GrupoVulnerableCatalogo(
                idGrupoVulnerable: i + 1,
                codigo: 'GV${i + 1}',
                nombre: _kNombresCanon[i],
              ),
          ]),
          child: Scaffold(
            body: SingleChildScrollView(
              child: EdanPage10(localidad: loc),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(CheckboxListTile), findsNWidgets(8),
        reason: 'initState normaliza por id: 16 crudos → 8 visibles');
    expect(find.text('Adolescentes'), findsOneWidget);
    // Y el modelo quedó escrito normalizado (8), no solo la vista.
    expect(loc.proteccion, hasLength(8));
    expect(loc.proteccion.every((g) => g.idGrupoVulnerable != null), isTrue);
  });
}
