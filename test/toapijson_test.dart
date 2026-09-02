// Test del toApiJson() de EdanLocalidad
// Ejecutar: cd REA; flutter test test/toapijson_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:rea/models/edan.dart';

void main() {
  group('toApiJson() tests', () {
    test('impacto_poblacion incluye id_seccion POR GRUPO', () {
      final localidad = EdanLocalidad(
        idLocal: 'test-001',
        idTipoLocalidad: 2,
        idTipoEvento: 5,
        idDepartamento: 7,
        idProvincia: 701,
        idMunicipio: 70101,
        nombre: 'Test Localidad',
        fechaLlenado: '2026-08-25',
        fechaEvento: '2026-08-25',
        horaEvento: '14:30:00',
        impactoPoblacion: [
          EdanImpactoPoblacion(
            idSeccion: '1a035f7g9h2-659d33de4f8i6',  // ID del padre (solo fallback)
            grupoEtario: 'Global',
            fallecidos: 2,
            heridos: 5,
            desaparecidos: 0,
            observaciones: 'Test observaciones',
            gruposEtarios: [
              EdanGrupoEtario(
                idSeccion: '1a035g8h0i3-659d44ef5g9j7',  // ID único para este rango
                rango: 'Niño (a) 0-5 años',
                fallecidos: 2,
                heridos: 3,
                desaparecidos: 0,
                observaciones: 'Niños pequeños',
              ),
              EdanGrupoEtario(
                idSeccion: '1a036h9i1j4-659d55fg6h0k8',  // ID único diferente para este rango
                rango: 'Adulto de 19-60 años',
                fallecidos: 0,
                heridos: 2,
                desaparecidos: 0,
                observaciones: '',
              ),
            ],
          ),
        ],
      );

      final json = localidad.toApiJson();
      final impactoList = json['impacto_poblacion'] as List;

      print('=== impacto_poblacion JSON ===');
      print(impactoList);

      // Verificar que hay 2 items (grupos_etarios con datos)
      expect(impactoList.length, 2, reason: 'Debe tener 2 grupos etarios con datos');

      // Verificar PRIMER item: debe tener SU PROPIO id_seccion
      final item1 = impactoList[0] as Map<String, dynamic>;
      print('\nItem 1:');
      print(item1);
      expect(item1['id_seccion'], equals('1a035g8h0i3-659d44ef5g9j7'),
          reason: 'Primer grupo debe tener SU PROPIO id_seccion único');
      expect(item1['rango'], equals('Niño (a) 0-5 años'));
      expect(item1['fallecidos'], equals(2));
      expect(item1['heridos'], equals(3));
      expect(item1['observaciones'], equals('Niños pequeños'));

      // Verificar SEGUNDO item: debe tener SU PROPIO id_seccion (DIFERENTE del primero)
      final item2 = impactoList[1] as Map<String, dynamic>;
      print('\nItem 2:');
      print(item2);
      expect(item2['id_seccion'], equals('1a036h9i1j4-659d55fg6h0k8'),
          reason: 'Segundo grupo debe tener SU PROPIO id_seccion único (NO compartir)');
      expect(item2['rango'], equals('Adulto de 19-60 años'));
      expect(item2['heridos'], equals(2));
      
      // CRÍTICO: Verificar que los IDs SON DIFERENTES (no duplicados)
      expect(item1['id_seccion'], isNot(equals(item2['id_seccion'])),
          reason: 'Cada grupo etario debe tener id_seccion ÚNICO - NO compartir');
    });

    test('servicios_basicos incluye observaciones', () {
      final localidad = EdanLocalidad(
        idLocal: 'test-002',
        idTipoLocalidad: 2,
        idTipoEvento: 5,
        idDepartamento: 7,
        idProvincia: 701,
        idMunicipio: 70101,
        nombre: 'Test Servicios',
        serviciosBasicos: [
          EdanServicioBasicoDetalle(
            idSeccion: '1a035a2b4cd-659d1a8f9c3d1',
            tipo: 'energia_electrica',
            danoParcial: true,
            danoTotal: false,
            necesidadesInmediatas: 'Postes caidos',
            observaciones: '3 postes en calle principal', // ESTE CAMPO
            fotografia: '/uploads/test.jpg',
            coordenadaLat: -16.5045,
            coordenadaLon: -68.1532,
          ),
        ],
      );

      final json = localidad.toApiJson();
      final serviciosList = json['servicios_basicos'] as List;

      print('\n=== servicios_basicos JSON ===');
      print(serviciosList);

      expect(serviciosList.length, 1);
      final item = serviciosList[0] as Map<String, dynamic>;
      print('\nServicio item:');
      print(item);
      
      expect(item['id_seccion'], equals('1a035a2b4cd-659d1a8f9c3d1'));
      expect(item['tipo'], equals('energia_electrica'));
      expect(item['observaciones'], equals('3 postes en calle principal'));
      expect(item.containsKey('fotografia'), isFalse,
          reason: 'toApiJson() NO debe incluir fotografia (se sube vía con-foto)');
      expect(item['coordenada_lat'], equals(-16.5045));
      expect(item['coordenada_lon'], equals(-68.1532));
    });

    test('proteccion pasa grupo catálogo', () {
      final catalogoGrupo = {
        'id': 1,
        'codigo': 'adultos_mayores',
        'nombre': 'Adultos mayores',
        'orden': 5,
      };

      final localidad = EdanLocalidad(
        idLocal: 'test-003',
        idTipoLocalidad: 2,
        nombre: 'Test Proteccion',
        proteccion: [
          EdanGrupoVulnerable(
            idSeccion: '1a0367eo5p6-659den5o6p7q8',
            idGrupoVulnerableCatalogo: 1,
            mujeres: 15,
            hombres: 12,
            observaciones: 'Requieren medicamentos',
          ),
        ],
      );

      // Usar toApiJson con el catálogo
      final proteccionApi = localidad.proteccion
          .map((p) => p.toApiJson(catalogoGrupo))
          .toList();

      print('\n=== proteccion JSON ===');
      print(proteccionApi);

      final item = proteccionApi[0];
      print('\nProteccion item:');
      print(item);

      expect(item['id_seccion'], equals('1a0367eo5p6-659den5o6p7q8'));
      expect(item['id_grupo_vulnerable_catalogo'], equals(1));
      expect(item['grupo'], isNotNull, reason: 'Debe incluir objeto grupo');
      expect(item['grupo']['nombre'], equals('Adultos mayores'));
      expect(item['observaciones'], equals('Requieren medicamentos'));
    });
  });

  group('flags imp_* 1:1 por sección', () {
    test('toJson emite los 13 flags nuevos', () {
      final localidad = EdanLocalidad(
        impImpactoPoblacion: true,
        impSaludEstablecimientos: true,
        impDanosViales: true,
        impDanosInfraPublica: true,
        impServiciosBasicos: true,
        impUnidadesEducativas: true,
        impDanosVivienda: true,
        impDanosAgricultura: true,
        impDanosPecuarios: true,
        impInfraProductiva: true,
        impPrimeraRespuesta: true,
        impNecesidadSalud: true,
        impNecesidadHumanitaria: true,
      );

      final json = localidad.toJson();

      expect(json['imp_impacto_poblacion'], isTrue);
      expect(json['imp_salud_establecimientos'], isTrue);
      expect(json['imp_danos_viales'], isTrue);
      expect(json['imp_danos_infra_publica'], isTrue);
      expect(json['imp_servicios_basicos'], isTrue);
      expect(json['imp_unidades_educativas'], isTrue);
      expect(json['imp_danos_vivienda'], isTrue);
      expect(json['imp_danos_agricultura'], isTrue);
      expect(json['imp_danos_pecuarios'], isTrue);
      expect(json['imp_infra_productiva'], isTrue);
      expect(json['imp_primera_respuesta'], isTrue);
      expect(json['imp_necesidad_salud'], isTrue);
      expect(json['imp_necesidad_humanitaria'], isTrue);
    });

    test('round-trip fromJson preserva los 13 flags', () {
      final json = {
        'id_local': 'test-flags-001',
        'localidad': 'Comunidad Ejemplo',
        'imp_impacto_poblacion': true,
        'imp_salud_establecimientos': false,
        'imp_danos_viales': true,
        'imp_danos_infra_publica': false,
        'imp_servicios_basicos': true,
        'imp_unidades_educativas': false,
        'imp_danos_vivienda': true,
        'imp_danos_agricultura': false,
        'imp_danos_pecuarios': true,
        'imp_infra_productiva': false,
        'imp_primera_respuesta': true,
        'imp_necesidad_salud': false,
        'imp_necesidad_humanitaria': true,
      };

      final localidad = EdanLocalidad.fromJson(json);

      expect(localidad.impImpactoPoblacion, isTrue);
      expect(localidad.impSaludEstablecimientos, isFalse);
      expect(localidad.impDanosViales, isTrue);
      expect(localidad.impDanosInfraPublica, isFalse);
      expect(localidad.impServiciosBasicos, isTrue);
      expect(localidad.impUnidadesEducativas, isFalse);
      expect(localidad.impDanosVivienda, isTrue);
      expect(localidad.impDanosAgricultura, isFalse);
      expect(localidad.impDanosPecuarios, isTrue);
      expect(localidad.impInfraProductiva, isFalse);
      expect(localidad.impPrimeraRespuesta, isTrue);
      expect(localidad.impNecesidadSalud, isFalse);
      expect(localidad.impNecesidadHumanitaria, isTrue);
    });

    test('recalcularFlagsImpacto deriva los flags de las secciones con datos', () {
      final localidad = EdanLocalidad();
      localidad.establecimientosSalud = [
        EdanEstablecimientoSalud(
          idSeccion: 'es-1',
          nombreEstablecimiento: 'Centro de salud',
          danoTotal: true,
        ),
      ];
      localidad.danosViales = [
        EdanDanoVial(
          idSeccion: 'dv-1',
          viaPuente: 'Puente principal',
          danoParcial: true,
        ),
      ];
      localidad.necesidadSalud = EdanNecesidadSalud(numeroPersonas: 40);
      localidad.necesidadHumanitaria = EdanNecesidadHumanitaria(alimentos: true);

      localidad.recalcularFlagsImpacto();

      expect(localidad.impSaludEstablecimientos, isTrue);
      expect(localidad.impDanosViales, isTrue);
      expect(localidad.impNecesidadSalud, isTrue);
      expect(localidad.impNecesidadHumanitaria, isTrue);
      expect(localidad.impDanosInfraPublica, isFalse);
      expect(localidad.impServiciosBasicos, isFalse);
      expect(localidad.impDanosVivienda, isFalse);
      expect(localidad.impUnidadesEducativas, isFalse);
    });
  });
}
