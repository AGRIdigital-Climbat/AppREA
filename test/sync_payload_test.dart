// Test completo: toApiJson() para sincronización
// Ejecutar: cd REA; flutter test test/sync_payload_test.dart

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:rea/models/edan.dart';

void main() {
  group('SYNC PAYLOAD TEST', () {
    test('JSON completo para POST /edan/localidades/sync', () {
      // Crear localidad con TODAS las secciones
      final localidad = EdanLocalidad(
        idLocal: 'sync-test-001',
        idTipoLocalidad: 2,
        idTipoEvento: 5,
        idDepartamento: 7,
        idProvincia: 701,
        idMunicipio: 70101,
        nombre: 'Test Sync Completo',
        fechaLlenado: '2026-08-25',
        fechaEvento: '2026-08-25',
        horaEvento: '14:30:00',
        totalPoblacionAfectada: 150,
        totalFamiliasAfectadas: 30,
        totalFamiliasDamnificadas: 10,
        impPoblacion: true,
        impSalud: true,
        impInfraestructura: true,
        impServicios: true,
        impEducacion: false,
        impVivienda: false,
        impAgropecuario: false,
        impProteccion: true,
        impNecesidades: true,
        
        // 1. IMPACTO POBLACIONAL (con IDs únicos por grupo)
        impactoPoblacion: [
          EdanImpactoPoblacion(
            idSeccion: '1a035f7g9h2-659d33de4f8i6',  // ID padre (fallback)
            grupoEtario: 'Total',
            fallecidos: 10,
            heridos: 25,
            desaparecidos: 3,
            gruposEtarios: [
              EdanGrupoEtario(
                idSeccion: '1a035g8h0i3-659d44ef5g9j7',  // ← ID único #1
                rango: 'Niño (a) 0-5 años',
                fallecidos: 2,
                heridos: 3,
                desaparecidos: 0,
                observaciones: 'Niños pequeños',
              ),
              EdanGrupoEtario(
                idSeccion: '1a036h9i1j4-659d55fg6h0k8',  // ← ID único #2
                rango: 'Escolar de 6-18 años',
                fallecidos: 0,
                heridos: 5,
                desaparecidos: 0,
                observaciones: '',
              ),
              EdanGrupoEtario(
                idSeccion: '1a037i0j2k5-659d66gh7i1l9',  // ← ID único #3
                rango: 'Adulto de 19-60 años',
                fallecidos: 5,
                heridos: 12,
                desaparecidos: 2,
                observaciones: 'Atrapados en edificios',
              ),
              EdanGrupoEtario(
                idSeccion: '1a038j1k3l6-659d77hi8j2m0',  // ← ID único #4
                rango: 'Adulto mayor de 60 años adelante',
                fallecidos: 3,
                heridos: 5,
                desaparecidos: 1,
                observaciones: '',
              ),
            ],
          ),
        ],
        
        // 2. SERVICIOS BÁSICOS (5 ítems con IDs únicos)
        serviciosBasicos: [
          EdanServicioBasicoDetalle(
            idSeccion: '1a035a2b4cd-659d1a8f9c3d1',
            tipo: 'energia_electrica',
            danoParcial: true,
            danoTotal: false,
            necesidadesInmediatas: 'Reparación de postes',
            observaciones: '3 postes caídos en calle principal',
            fotografia: null,
            coordenadaLat: -16.5045,
            coordenadaLon: -68.1532,
          ),
          EdanServicioBasicoDetalle(
            idSeccion: '1a035b3c5de-659d1f9a0b4e2',
            tipo: 'agua_potable',
            danoParcial: false,
            danoTotal: false,
            necesidadesInmediatas: '',
            observaciones: 'Sin daños',
            fotografia: null,
            coordenadaLat: -16.51,
            coordenadaLon: -68.16,
          ),
        ],
        
        // 3. DAÑOS PECUARIOS (con ID único)
        danosPecuarios: [
          EdanDanoPecuario(
            idSeccion: '1a035e6f8g1-659d2ecd3e7h5',
            especie: 'Bovino',
            idEspecie: 1,
            raza: 'Holstein',
            animalesAfectados: 25,
            animalesMuertos: 3,
            necesidadesInmediatas: 'Vacunas',
            fotografia: null,
            coordenadaLat: -16.5,
            coordenadaLon: -68.1,
          ),
        ],
        
        // 4. PROTECCIÓN (8 grupos con IDs únicos)
        proteccion: [
          EdanGrupoVulnerable(
            idSeccion: '1a0367eo5p6-659den5o6p7q8',
            idGrupoVulnerableCatalogo: 1,
            mujeres: 15,
            hombres: 12,
            observaciones: 'Requieren medicamentos',
          ),
          EdanGrupoVulnerable(
            idSeccion: '1a0368fp6q7-659dfo6p7q8r9',
            idGrupoVulnerableCatalogo: 2,
            mujeres: 8,
            hombres: 5,
            observaciones: '',
          ),
        ],
        
        // 5. SECCIONES 1:1
        necesidadPrimeraRespuesta: EdanNecesidadPrimeraRespuesta(
          busqueda: false,
          salvamento: true,
          evacuacion: false,
          observaciones: 'Rescate en curso',
        ),
        
        necesidadSalud: EdanNecesidadSalud(
          numeroPersonas: 6,
          otrasNecesidades: 'Medicamentos',
          observaciones: 'Atención primaria',
        ),
        
        necesidadHumanitaria: EdanNecesidadHumanitaria(
          alimentos: true,
          refugioVivienda: true,
          obsAlimentos: 'Raciones',
          obsRefugioVivienda: 'Techos',
        ),
      );
      
      // Generar payload para sync
      final apiJson = localidad.toApiJson();
      apiJson['id_usuario'] = 30;
      
      final payload = {'localidades': [apiJson]};
      
      // === VERIFICACIONES CRÍTICAS ===
      
      print('\n${'='*80}');
      print('VERIFICACIÓN DE IDs ÚNICOS EN impactO_poblacion');
      print('${'='*80}');
      
      final impactoList = (apiJson['impacto_poblacion'] as List);
      print('Total grupos etarios: ${impactoList.length}');
      
      final ids = impactoList.map((i) => i['id_seccion'] as String).toList();
      print('IDs encontrados: $ids');
      
      // Verificar que hay 4 IDs únicos
      expect(impactoList.length, 4, reason: 'Debe haber 4 grupos etarios');
      expect(ids.length, 4, reason: 'Cada grupo debe tener id_seccion');
      expect(ids.toSet().length, 4, reason: 'Todos los IDs deben ser ÚNICOS (no duplicados)');
      
      // Verificar que NINGÚN ID se repite
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          expect(ids[i], isNot(equals(ids[j])), 
            reason: 'ID duplicado: posición $i y $j tienen el mismo id_seccion');
        }
      }
      
      print('\n${'='*80}');
      print('VERIFICACIÓN DE SERVICIOS BÁSICOS');
      print('${'='*80}');
      
      final serviciosList = (apiJson['servicios_basicos'] as List);
      print('Total servicios: ${serviciosList.length}');
      
      final servicio1 = serviciosList[0] as Map<String, dynamic>;
      print('Servicio 1:');
      print('  id_seccion: ${servicio1['id_seccion']}');
      print('  tipo: ${servicio1['tipo']}');
      print('  observaciones: ${servicio1['observaciones']}');  // ← ESTE CAMPO ES CRÍTICO
      
      expect(servicio1['observaciones'], isNotNull, reason: 'observaciones debe existir');
      expect(servicio1['observaciones'], equals('3 postes caídos en calle principal'));
      
      print('\n${'='*80}');
      print('VERIFICACIÓN DE PROTECCIÓN');
      print('${'='*80}');
      
      final proteccionList = localidad.proteccionParaEndpointDedicado();
      print('Total grupos vulnerables: ${proteccionList.length}');

      final grupo1 = proteccionList[0];
      print('Grupo 1:');
      print('  id_seccion: ${grupo1['id_seccion']}');
      print('  id_grupo_vulnerable_catalogo: ${grupo1['id_grupo_vulnerable_catalogo']}');
      print('  grupo: ${grupo1['grupo']} (null es OK según OpenAPI)');
      print('  observaciones: ${grupo1['observaciones']}');
      
      // grupo es OPCIONAL según OpenAPI (puede ser null)
      // Lo crítico es que id_grupo_vulnerable_catalogo SÍ exista
      expect(grupo1['id_grupo_vulnerable_catalogo'], equals(1), 
        reason: 'id_grupo_vulnerable_catalogo debe existir');
      expect(grupo1['observaciones'], equals('Requieren medicamentos'));
      
      print('\n${'='*80}');
      print('RESUMEN');
      print('${'='*80}');
      print('✓ impacto_poblacion: ${ids.length} IDs ÚNICOS (sin duplicados)');
      print('✓ servicios_basicos: observaciones INCLUIDO');
      print('✓ proteccion: grupo catálogo INCLUIDO');
      print('✓ JSON payload: ${JsonEncoder.withIndent('  ').convert(payload).length} caracteres');
      print('\n✅ PAYLOAD LISTO PARA POST /api/v1/edan/localidades/sync');
    });
  });
}
