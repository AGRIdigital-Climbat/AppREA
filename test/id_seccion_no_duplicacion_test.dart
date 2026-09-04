// Pruebas del contrato de `id_seccion` (DOCUMENTO_V2_SYNC.md):
//   - `id_seccion` se genera SOLO al guardar (asignarIdSeccionSiFalta), jamás en
//     deserialización (requireIdSeccion) ni en la capa visual.
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
  group('requireIdSeccion: nunca genera id al deserializar', () {
    test('con id presente lo conserva', () {
      expect(requireIdSeccion('abc-123', 'po'), 'abc-123');
    });

    test('sin id devuelve null y JAMAS genera uno nuevo', () {
      expect(requireIdSeccion(null, 'po'), isNull);
      expect(requireIdSeccion('', 'po'), isNull);
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
