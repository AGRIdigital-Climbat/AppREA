// Pruebas del contrato de identidad de fila:
//   - Al deserializar NUNCA se genera id; `uuidFilaDe` prefiere `uuid_registro`
//     válido y descarta `id_seccion` legacy con prefijo (mandarlo daría 422).
//   - `deduplicarSecciones` evita arrays 1:N duplicados (regla 3 -> NO 6).
// Ejecutar: cd REA; flutter test test/id_seccion_no_duplicacion_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:rea/models/edan.dart';
import 'package:rea/services/edan/edan_proteccion_service.dart';
import 'package:rea/services/edan/edan_servicios_basicos_service.dart';

EdanGrupoVulnerable _grupo({
  String? id,
  int catalogId = 1,
  int mujeres = 0,
  int hombres = 0,
  bool? apoyo,
  String obs = '',
}) {
  return EdanGrupoVulnerable(
    idSeccion: (id == null || id.isEmpty) ? null : id,
    idGrupoVulnerableCatalogo: catalogId,
    mujeres: mujeres,
    hombres: hombres,
    apoyoPsicologico: apoyo,
    reposicionDocumentos: null,
    observaciones: obs,
  );
}

void main() {
  group('uuidFilaDe: nunca genera id al deserializar', () {
    test('uuid_registro válido manda sobre id_seccion legacy', () {
      expect(
          uuidFilaDe({
            'uuid_registro': 'c3484037-9523-4aa7-e6b7-57a9fe67b953',
            'id_seccion': '1k2ma9o87-d0601a819c58d',
          }),
          'c3484037-9523-4aa7-e6b7-57a9fe67b953');
    });

    test('id_seccion legacy con prefijo se descarta (daría 422)', () {
      expect(uuidFilaDe({'id_seccion': 'po_abc123'}), isNull);
      expect(uuidFilaDe({'id_seccion': '1k2ma9o87-d0601a819c58d'}), isNull);
    });

    test('uuid válido en id_seccion se conserva', () {
      const u = 'aaaaaaaa-1111-4111-8111-111111111111';
      expect(uuidFilaDe({'id_seccion': u}), u);
    });

    test('sin id devuelve null y JAMAS genera uno nuevo', () {
      expect(uuidFilaDe({}), isNull);
      expect(uuidFilaDe({'id_seccion': ''}), isNull);
    });
  });

  group('deduplicarSecciones: la regla 3 NO debe volverse 6', () {
    test('elimina filas duplicadas exactas con el mismo id_seccion', () {
      final l = EdanLocalidad(
        idLocal: 'dup-001',
        proteccion: [
          _grupo(id: 'g1', catalogId: 1, mujeres: 2, hombres: 1),
          _grupo(id: 'g1', catalogId: 1, mujeres: 2, hombres: 1),
          _grupo(id: 'g2', catalogId: 2, mujeres: 5),
        ],
      );
      l.deduplicarSecciones();
      expect(l.proteccion.length, 2);
      expect({for (final g in l.proteccion) g.idSeccion}, {'g1', 'g2'});
    });

    test('descarta fila SIN id duplicada por contenido con otra SIN id', () {
      final l = EdanLocalidad(
        idLocal: 'dup-002',
        proteccion: [
          _grupo(id: null, catalogId: 1, mujeres: 2, hombres: 1),
          // Copia llegada en el pull, también sin id, mismo contenido:
          _grupo(id: null, catalogId: 1, mujeres: 2, hombres: 1),
        ],
      );
      l.deduplicarSecciones();
      expect(l.proteccion.length, 1);
    });

    test('conserva filas legítimas con distinto contenido', () {
      final l = EdanLocalidad(
        idLocal: 'dup-003',
        proteccion: [
          _grupo(id: 'g1', catalogId: 1, mujeres: 2),
          _grupo(id: 'g2', catalogId: 2, hombres: 3),
          _grupo(id: 'g3', catalogId: 3, mujeres: 1, apoyo: true),
        ],
      );
      l.deduplicarSecciones();
      expect(l.proteccion.length, 3);
    });
  });

  group('asignarIdSeccionSiFalta: id_seccion SOLO al guardar', () {
    test('asigna id a ítem con datos que no tiene id', () {
      final l = EdanLocalidad(
        idLocal: 'gen-001',
        proteccion: [
          _grupo(id: null, catalogId: 1, mujeres: 2, hombres: 1),
        ],
      );
      final servicio = EdanProteccionService();
      servicio.asignarIdSeccionSiFalta(l, 'po');
      final id = l.proteccion.first.idSeccion;
      expect(id, isNotNull);
      expect(id, isNotEmpty);
    });

    test('NO asigna id a ítems sin datos (catálogo vacío)', () {
      final l = EdanLocalidad(
        idLocal: 'gen-002',
        proteccion: [
          _grupo(id: null, catalogId: 1), // sin datos
        ],
      );
      final servicio = EdanProteccionService();
      servicio.asignarIdSeccionSiFalta(l, 'po');
      expect(l.proteccion.first.idSeccion, isNull);
    });

    test('conserva id existente y no genera uno nuevo', () {
      final l = EdanLocalidad(
        idLocal: 'gen-003',
        proteccion: [
          _grupo(id: 'existente-1', catalogId: 1, mujeres: 4),
        ],
      );
      final servicio = EdanProteccionService();
      servicio.asignarIdSeccionSiFalta(l, 'po');
      expect(l.proteccion.first.idSeccion, 'existente-1');
    });

    test('asigna id a servicios básicos con datos creados sin id en la UI', () {
      final l = EdanLocalidad(
        idLocal: 'gen-004',
        serviciosBasicos: [
          // Creado por la UI sin id (edan_page06) y con datos:
          EdanServicioBasicoDetalle(
            tipo: 'energia_electrica',
            necesidadesInmediatas: 'Corte total',
          ),
          // Catálogo sin datos, no debe recibir id:
          EdanServicioBasicoDetalle(tipo: 'agua_potable'),
        ],
      );
      final servicio = EdanServiciosBasicosService();
      servicio.asignarIdSeccionSiFalta(l, 'sb');
      expect(l.serviciosBasicos[0].idSeccion, isNotNull);
      expect(l.serviciosBasicos[0].idSeccion, isNotEmpty);
      expect(l.serviciosBasicos[1].idSeccion, isNull);
    });
  });
}
