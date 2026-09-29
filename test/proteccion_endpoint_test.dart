import 'package:flutter_test/flutter_test.dart';
import 'package:rea/models/edan.dart';
import 'package:rea/models/id_seccion_helper.dart';

void main() {
  // ─────────────────────────────────────────────────────
  // SERIALIZACIÓN: toApiJson() con total
  // ─────────────────────────────────────────────────────
  group('toApiJson() incluye total calculado', () {
    test('total = mujeres + hombres', () {
      final g = EdanGrupoVulnerable(mujeres: 10, hombres: 8);
      final json = g.toApiJson(null);
      expect(json['total'], 18);
    });

    test('total = 0 cuando ambos 0', () {
      final g = EdanGrupoVulnerable(mujeres: 0, hombres: 0);
      final json = g.toApiJson(null);
      expect(json['total'], 0);
    });

    test('total presente siempre (no es condicional)', () {
      final g = EdanGrupoVulnerable();
      final json = g.toApiJson(null);
      expect(json.containsKey('total'), isTrue);
      expect(json['total'], 0);
    });

    test('total se actualiza al cambiar mujeres/hombres', () {
      final g = EdanGrupoVulnerable(mujeres: 5, hombres: 3);
      expect(g.toApiJson(null)['total'], 8);
      g.mujeres = 20;
      expect(g.toApiJson(null)['total'], 23);
    });

    test('toApiJson sin grupo anidado cuando null', () {
      final g = EdanGrupoVulnerable(
        idSeccion: 'po_test_001',
        idGrupoVulnerableCatalogo: 1,
        mujeres: 5,
        hombres: 3,
      );
      final json = g.toApiJson(null);
      expect(json.containsKey('grupo'), isFalse);
      expect(json['id_seccion'], 'po_test_001');
      expect(json['id_grupo_vulnerable_catalogo'], 1);
      expect(json['total'], 8);
    });

    test('toApiJson con grupo anidado cuando se provee catálogo', () {
      final g = EdanGrupoVulnerable(
        idSeccion: 'po_test_002',
        idGrupoVulnerableCatalogo: 2,
        mujeres: 3,
        hombres: 1,
      );
      final catalogo = {'id': 2, 'nombre': 'Mujeres embarazadas'};
      final json = g.toApiJson(catalogo);
      expect(json['grupo'], catalogo);
      expect(json['total'], 4);
    });

    test('campos tri-state preservados en toApiJson', () {
      final g = EdanGrupoVulnerable(
        apoyoPsicologico: true,
        reposicionDocumentos: false,
      );
      final json = g.toApiJson(null);
      expect(json['apoyo_psicologico'], true);
      expect(json['reposicion_documentos'], false);
    });

    test('campos tri-state null presentes con valor null', () {
      final g = EdanGrupoVulnerable();
      final json = g.toApiJson(null);
      expect(json.containsKey('apoyo_psicologico'), isTrue);
      expect(json['apoyo_psicologico'], isNull);
      expect(json.containsKey('reposicion_documentos'), isTrue);
      expect(json['reposicion_documentos'], isNull);
    });
  });

  // ─────────────────────────────────────────────────────
  // _proteccionApi() retorna vacío (endpoints dedicados)
  // ─────────────────────────────────────────────────────
  group('proteccion dentro del payload de /documento', () {
    test('localidad con 8 grupos con datos → proteccion con los 8', () {
      final loc = EdanLocalidad(
        proteccion: List.generate(
          8,
          (i) => EdanGrupoVulnerable(
            idSeccion: 'po_$i',
            idGrupoVulnerableCatalogo: i + 1,
            mujeres: 5,
            hombres: 3,
          ),
        ),
      );
      final json = loc.toApiJson();
      final proteccion = json['proteccion'] as List;
      expect(proteccion.length, 8,
          reason: '/documento es la via real de subida: debe llevar proteccion');
    });

    test('localidad sin grupos → proteccionApi vacío', () {
      final loc = EdanLocalidad();
      final json = loc.toApiJson();
      final proteccion = json['proteccion'] as List;
      expect(proteccion, isEmpty);
    });
  });

  // ─────────────────────────────────────────────────────
  // proteccionParaEndpointDedicado()
  // ─────────────────────────────────────────────────────
  group('proteccionParaEndpointDedicado()', () {
    test('retorna solo grupos con tieneDatos', () {
      final loc = EdanLocalidad(proteccion: [
        EdanGrupoVulnerable(
            idSeccion: 'po_1', idGrupoVulnerableCatalogo: 1, mujeres: 5),
        EdanGrupoVulnerable(idSeccion: 'po_2', idGrupoVulnerableCatalogo: 2),
        EdanGrupoVulnerable(
            idSeccion: 'po_3', idGrupoVulnerableCatalogo: 3, hombres: 10),
        EdanGrupoVulnerable(idSeccion: 'po_4', idGrupoVulnerableCatalogo: 4),
      ]);
      final result = loc.proteccionParaEndpointDedicado();
      expect(result.length, 2);
      expect(result[0]['id_seccion'], 'po_1');
      expect(result[0]['total'], 5);
      expect(result[1]['id_seccion'], 'po_3');
      expect(result[1]['total'], 10);
    });

    test('8 grupos default con datos → 8 items', () {
      final loc = EdanLocalidad(
        proteccion: List.generate(
          8,
          (i) => EdanGrupoVulnerable(
            idSeccion: 'po_$i',
            idGrupoVulnerableCatalogo: i + 1,
            mujeres: 1,
          ),
        ),
      );
      final result = loc.proteccionParaEndpointDedicado();
      expect(result.length, 8);
    });

    test('todos vacíos → lista vacía', () {
      final loc = EdanLocalidad(
        proteccion: List.generate(8, (i) => EdanGrupoVulnerable(idSeccion: 'po_$i')),
      );
      final result = loc.proteccionParaEndpointDedicado();
      expect(result, isEmpty);
    });

    test('solo observaciones → tieneDatos=true → incluido', () {
      final loc = EdanLocalidad(proteccion: [
        EdanGrupoVulnerable(
            idSeccion: 'po_obs',
            idGrupoVulnerableCatalogo: 5,
            observaciones: 'Necesita apoyo'),
      ]);
      final result = loc.proteccionParaEndpointDedicado();
      expect(result.length, 1);
      expect(result[0]['observaciones'], 'Necesita apoyo');
    });

    test('solo apoyoPsicologico=true → tieneDatos=true → incluido', () {
      final loc = EdanLocalidad(proteccion: [
        EdanGrupoVulnerable(
            idSeccion: 'po_apoyo',
            idGrupoVulnerableCatalogo: 6,
            apoyoPsicologico: true),
      ]);
      final result = loc.proteccionParaEndpointDedicado();
      expect(result.length, 1);
      expect(result[0]['apoyo_psicologico'], true);
    });

    test('apoyoPsicologico=false no activa tieneDatos', () {
      final loc = EdanLocalidad(proteccion: [
        EdanGrupoVulnerable(
            idSeccion: 'po_no',
            idGrupoVulnerableCatalogo: 7,
            apoyoPsicologico: false),
      ]);
      final result = loc.proteccionParaEndpointDedicado();
      expect(result, isEmpty);
    });

    test('schema correcto para ProteccionCreate (sin grupo anidado)', () {
      final loc = EdanLocalidad(proteccion: [
        EdanGrupoVulnerable(
          idSeccion: 'po_schema_001',
          idGrupoVulnerableCatalogo: 1,
          mujeres: 15,
          hombres: 12,
          apoyoPsicologico: true,
          reposicionDocumentos: false,
          observaciones: 'Requieren medicamentos',
        ),
      ]);
      final result = loc.proteccionParaEndpointDedicado();
      expect(result.length, 1);
      final json = result[0];

      expect(json['id_seccion'], 'po_schema_001');
      expect(json['id_grupo_vulnerable_catalogo'], 1);
      expect(json['mujeres'], 15);
      expect(json['hombres'], 12);
      expect(json['total'], 27);
      expect(json['apoyo_psicologico'], true);
      expect(json['reposicion_documentos'], false);
      expect(json['observaciones'], 'Requieren medicamentos');
      expect(json.containsKey('grupo'), isFalse);
    });
  });

  // ─────────────────────────────────────────────────────
  // Roundtrip: toApiJson → fromJson → proteccionParaEndpointDedicado
  // ─────────────────────────────────────────────────────
  group('Roundtrip serialización', () {
    test('toJson/fromJson preserva nombre_grupo', () {
      final original = EdanGrupoVulnerable(
        idSeccion: 'po_rt_001',
        idGrupoVulnerableCatalogo: 3,
        nombreGrupo: 'Niños 0-5 años',
        mujeres: 7,
        hombres: 5,
        apoyoPsicologico: true,
        observaciones: 'Test roundtrip',
      );

      final json = original.toJson();
      expect(json['nombre_grupo'], 'Niños 0-5 años');
      expect(json.containsKey('total'), isFalse,
          reason: 'toJson() no incluye total (es getter calculado)');

      final restored = EdanGrupoVulnerable.fromJson(json);
      expect(restored.idSeccion, 'po_rt_001');
      expect(restored.idGrupoVulnerableCatalogo, 3);
      expect(restored.nombreGrupo, 'Niños 0-5 años');
      expect(restored.mujeres, 7);
      expect(restored.hombres, 5);
      expect(restored.total, 12,
          reason: 'total se calcula como mujeres + hombres');
      expect(restored.apoyoPsicologico, isTrue);
      expect(restored.observaciones, 'Test roundtrip');
    });

    test('localidad roundtrip: 8 grupos preservan idSeccion', () {
      final grupos = List.generate(
        8,
        (i) => EdanGrupoVulnerable(
          idSeccion: 'po_grp_$i',
          idGrupoVulnerableCatalogo: i + 1,
          mujeres: i * 2,
          hombres: i,
          nombreGrupo: 'Grupo $i',
        ),
      );

      final loc = EdanLocalidad(proteccion: grupos);
      final json = loc.toJson();

      final restored = EdanLocalidad.fromJson(json);
      expect(restored.proteccion.length, 8);
      for (var i = 0; i < 8; i++) {
        expect(restored.proteccion[i].idSeccion, 'po_grp_$i');
        expect(restored.proteccion[i].mujeres, i * 2);
        expect(restored.proteccion[i].hombres, i);
        expect(restored.proteccion[i].total, i * 3);
      }
    });
  });

  // ─────────────────────────────────────────────────────
  // Escenario: envío completo con endpoints dedicados
  // ─────────────────────────────────────────────────────
  group('Escenario envío completo', () {
    test('localidad crea 8 grupos, solo 3 con datos → 3 enviados', () {
      final loc = EdanLocalidad(
        nombre: 'Villa Esperanza',
        idMunicipio: 70101,
        proteccion: [
          EdanGrupoVulnerable(
              idSeccion: 'po_1', idGrupoVulnerableCatalogo: 1, mujeres: 10, hombres: 8),
          EdanGrupoVulnerable(idSeccion: 'po_2', idGrupoVulnerableCatalogo: 2),
          EdanGrupoVulnerable(
              idSeccion: 'po_3', idGrupoVulnerableCatalogo: 3, mujeres: 5),
          EdanGrupoVulnerable(idSeccion: 'po_4', idGrupoVulnerableCatalogo: 4),
          EdanGrupoVulnerable(
              idSeccion: 'po_5', idGrupoVulnerableCatalogo: 5, hombres: 3),
          EdanGrupoVulnerable(idSeccion: 'po_6', idGrupoVulnerableCatalogo: 6),
          EdanGrupoVulnerable(idSeccion: 'po_7', idGrupoVulnerableCatalogo: 7),
          EdanGrupoVulnerable(idSeccion: 'po_8', idGrupoVulnerableCatalogo: 8),
        ],
      );

      final apiJson = loc.toApiJson();
      expect((apiJson['proteccion'] as List).length, 3,
          reason: '/documento lleva los grupos con datos (los vacíos se filtran)');

      final dedicados = loc.proteccionParaEndpointDedicado();
      expect(dedicados.length, 3,
          reason: 'Solo 3 grupos con datos para endpoints dedicados');

      expect(dedicados[0]['id_grupo_vulnerable_catalogo'], 1);
      expect(dedicados[0]['total'], 18);
      expect(dedicados[1]['id_grupo_vulnerable_catalogo'], 3);
      expect(dedicados[1]['total'], 5);
      expect(dedicados[2]['id_grupo_vulnerable_catalogo'], 5);
      expect(dedicados[2]['total'], 3);
    });

    test('reenvío: mismo idSeccion → UPSERT no duplica', () {
      final loc = EdanLocalidad(proteccion: [
        EdanGrupoVulnerable(
          idSeccion: 'po_upsert_001',
          idGrupoVulnerableCatalogo: 1,
          mujeres: 10,
          hombres: 8,
        ),
      ]);

      final r1 = loc.proteccionParaEndpointDedicado();
      expect(r1.length, 1);
      expect(r1[0]['id_seccion'], 'po_upsert_001');

      loc.proteccion[0].mujeres = 20;
      final r2 = loc.proteccionParaEndpointDedicado();
      expect(r2.length, 1);
      expect(r2[0]['id_seccion'], 'po_upsert_001');
      expect(r2[0]['total'], 28);
    });

    test('edición: agregar datos a grupo vacío → ahora incluido', () {
      final loc = EdanLocalidad(proteccion: [
        EdanGrupoVulnerable(
            idSeccion: 'po_edit', idGrupoVulnerableCatalogo: 1),
      ]);
      expect(loc.proteccionParaEndpointDedicado(), isEmpty);

      loc.proteccion[0].mujeres = 5;
      expect(loc.proteccionParaEndpointDedicado().length, 1);
    });

    test('edición: limpiar datos de grupo → ya no incluido', () {
      final loc = EdanLocalidad(proteccion: [
        EdanGrupoVulnerable(
            idSeccion: 'po_clear',
            idGrupoVulnerableCatalogo: 1,
            mujeres: 5,
            observaciones: 'algo'),
      ]);
      expect(loc.proteccionParaEndpointDedicado().length, 1);

      loc.proteccion[0].mujeres = 0;
      loc.proteccion[0].observaciones = '';
      expect(loc.proteccionParaEndpointDedicado(), isEmpty);
    });
  });

  // ─────────────────────────────────────────────────────
  // Catálogo de 8 grupos
  // ─────────────────────────────────────────────────────
  group('Catálogo de 8 grupos vulnerables', () {
    const catalogo = [
      {'id_grupo_vulnerable': 1, 'nombre': 'Adultos mayores'},
      {'id_grupo_vulnerable': 2, 'nombre': 'Mujeres embarazadas'},
      {'id_grupo_vulnerable': 3, 'nombre': 'Niños 0-5 años'},
      {'id_grupo_vulnerable': 4, 'nombre': 'Niños 6-12 años'},
      {'id_grupo_vulnerable': 5, 'nombre': 'Adolescentes'},
      {'id_grupo_vulnerable': 6, 'nombre': 'Personas con discapacidad'},
      {'id_grupo_vulnerable': 7, 'nombre': 'Personas enfermas crónicas'},
      {'id_grupo_vulnerable': 8, 'nombre': 'Otros grupos vulnerables'},
    ];

    test('proteccionDesdeCatalogo crea 8 con id_seccion po_ prefix', () {
      final grupos = EdanLocalidad.proteccionDesdeCatalogo(catalogo);
      expect(grupos.length, 8);
      for (final g in grupos) {
        expect(g.idSeccion, startsWith('po_'));
        expect(g.idGrupoVulnerableCatalogo, greaterThanOrEqualTo(1));
        expect(g.idGrupoVulnerableCatalogo, lessThanOrEqualTo(8));
      }
    });

    test('proteccionDesdeCatalogo crea 8 con nombreGrupo del catálogo', () {
      final grupos = EdanLocalidad.proteccionDesdeCatalogo(catalogo);
      expect(grupos[0].nombreGrupo, 'Adultos mayores');
      expect(grupos[1].nombreGrupo, 'Mujeres embarazadas');
      expect(grupos[2].nombreGrupo, 'Niños 0-5 años');
      expect(grupos[7].nombreGrupo, 'Otros grupos vulnerables');
    });

    test('proteccionDesdeCatalogo: todos vacíos → 0 enviados', () {
      final grupos = EdanLocalidad.proteccionDesdeCatalogo(catalogo);
      final loc = EdanLocalidad(proteccion: grupos);
      expect(loc.proteccionParaEndpointDedicado(), isEmpty);
    });

    test('proteccionDesdeCatalogo: 2 con datos → 2 enviados', () {
      final grupos = EdanLocalidad.proteccionDesdeCatalogo(catalogo);
      grupos[0].mujeres = 10;
      grupos[0].hombres = 8;
      grupos[5].apoyoPsicologico = true;
      final loc = EdanLocalidad(proteccion: grupos);
      final result = loc.proteccionParaEndpointDedicado();
      expect(result.length, 2);
      expect(result[0]['id_grupo_vulnerable_catalogo'], 1);
      expect(result[0]['total'], 18);
      expect(result[1]['id_grupo_vulnerable_catalogo'], 6);
    });
  });

  // ─────────────────────────────────────────────────────
  // id_seccion uniqueness
  // ─────────────────────────────────────────────────────
  group('id_seccion uniqueness para endpoints dedicados', () {
    test('cada grupo tiene idSeccion único', () {
      final grupos = List.generate(
        8,
        (i) => EdanGrupoVulnerable(
          idSeccion: generarIdSeccion('po'),
          idGrupoVulnerableCatalogo: i + 1,
          mujeres: i + 1,
        ),
      );
      final ids = grupos.map((g) => g.idSeccion).toSet();
      expect(ids.length, 8, reason: 'Todos los idSeccion deben ser únicos');
    });

    test('ids empiezan con po_ prefix', () {
      final grupos = List.generate(
        8,
        (i) => EdanGrupoVulnerable(
          idSeccion: generarIdSeccion('po'),
          idGrupoVulnerableCatalogo: i + 1,
          mujeres: 1,
        ),
      );
      for (final g in grupos) {
        expect(g.idSeccion, startsWith('po_'));
      }
    });
  });

  // ─────────────────────────────────────────────────────
  // fromJson lee nombre_grupo de SQLite
  // ─────────────────────────────────────────────────────
  group('fromJson() nombre_grupo persistence', () {
    test('lee nombre_grupo directo (SQLite)', () {
      final json = {
        'id_seccion': 'po_sqlite_001',
        'nombre_grupo': 'Adultos mayores',
        'id_grupo_vulnerable_catalogo': 1,
        'mujeres': 5,
        'hombres': 3,
      };
      final g = EdanGrupoVulnerable.fromJson(json);
      expect(g.nombreGrupo, 'Adultos mayores');
    });

    test('lee grupo.nombre (API response)', () {
      final json = {
        'id_seccion': 'po_api_001',
        'grupo': {'nombre': 'Mujeres embarazadas'},
        'id_grupo_vulnerable_catalogo': 2,
        'mujeres': 5,
      };
      final g = EdanGrupoVulnerable.fromJson(json);
      expect(g.nombreGrupo, 'Mujeres embarazadas');
    });

    test('grupo.nombre tiene prioridad sobre nombre_grupo', () {
      final json = {
        'nombre_grupo': 'De SQLite',
        'grupo': {'nombre': 'De API'},
        'id_grupo_vulnerable_catalogo': 3,
      };
      final g = EdanGrupoVulnerable.fromJson(json);
      expect(g.nombreGrupo, 'De API');
    });
  });
}
