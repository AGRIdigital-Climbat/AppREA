// Test del contrato documento "todo-en-uno" v2 (`/localidades/{id}/documento`).
// Ejecutar: cd REA; flutter test test/sync_payload_test.dart
//
// El backend devuelve y acepta el MISMO shape simétrico (SIEMPRE COMPACTO):
//   - Cabecera + 22 flags `imp_*` + solo secciones con datos.
//   - 11 secciones SIEMPRE array (1:N), 3 SIEMPRE objeto (1:1).
//   - LWW por `fecha_modificacion`.
// Este test valida que `construirDocumento` (serializador "JSON nace de
// SQLite/modelo") produce exactamente ese contrato y que `parsearDocumento`
// + `aplicarPull` lo consumen de vuelta.

import 'package:flutter_test/flutter_test.dart';
import 'package:rea/models/edan.dart';
import 'package:rea/services/edan/edan_documento_service.dart';

/// Crea una localidad con TODAS las secciones (1:N y 1:1) + la cabecera.
EdanLocalidad _localidadCompleta() {
  return EdanLocalidad(
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

    // 1. IMPACTO POBLACIONAL (4 grupos etarios con IDs únicos)
    impactoPoblacion: [
      EdanImpactoPoblacion(
        idSeccion: '1a035f7g9h2-659d33de4f8i6',
        grupoEtario: 'Total',
        fallecidos: 10,
        heridos: 25,
        desaparecidos: 3,
        gruposEtarios: [
          EdanGrupoEtario(
            idSeccion: '1a035g8h0i3-659d44ef5g9j7',
            rango: 'Niño (a) 0-5 años',
            fallecidos: 2,
            heridos: 3,
            desaparecidos: 0,
            observaciones: 'Niños pequeños',
            marcado: true,
          ),
          EdanGrupoEtario(
            idSeccion: '1a036h9i1j4-659d55fg6h0k8',
            rango: 'Escolar de 6-18 años',
            fallecidos: 0,
            heridos: 5,
            desaparecidos: 0,
            observaciones: '',
            marcado: true,
          ),
          EdanGrupoEtario(
            idSeccion: '1a037i0j2k5-659d66gh7i1l9',
            rango: 'Adulto de 19-60 años',
            fallecidos: 5,
            heridos: 12,
            desaparecidos: 2,
            observaciones: 'Atrapados en edificios',
            marcado: true,
          ),
          EdanGrupoEtario(
            idSeccion: '1a038j1k3l6-659d77hi8j2m0',
            rango: 'Adulto mayor de 60 años adelante',
            fallecidos: 3,
            heridos: 5,
            desaparecidos: 1,
            observaciones: '',
            marcado: true,
          ),
        ],
      ),
    ],

    // 2. SERVICIOS BÁSICOS (2 ítems con IDs únicos)
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

    // 3. DAÑOS PECUARIOS (1 ítem con ID único)
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

    // 4. PROTECCIÓN (2 grupos con IDs únicos; se rellenan a 8 al parsear)
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
}

void main() {
  group('CONTRATO DOCUMENTO `/documento` (todo-en-uno v2)', () {
    test('construirDocumento produce shape simétrico y COMPACTO con 22 flags',
        () async {
      final localidad = _localidadCompleta();

      // Serializador del contrato: el JSON nace del modelo/SQLite.
      final doc = await EdanDocumentoService.instance.construirDocumento(localidad);

      // --- Cabecera: id_local es la clave de dedupe / id_edan_localidad opcional.
      expect(doc['id_local'], 'sync-test-001');
      expect(doc['localidad'], 'Test Sync Completo');
      expect(doc['id_municipio'], 70101);

      // --- Los 22 flags `imp_*` SIEMPRE presentes (verdad por datos).
      const flags = <String>[
        'imp_poblacion',
        'imp_salud',
        'imp_infraestructura',
        'imp_servicios',
        'imp_educacion',
        'imp_vivienda',
        'imp_agropecuario',
        'imp_proteccion',
        'imp_necesidades',
        'imp_impacto_poblacion',
        'imp_salud_establecimientos',
        'imp_danos_viales',
        'imp_danos_infra_publica',
        'imp_servicios_basicos',
        'imp_unidades_educativas',
        'imp_danos_vivienda',
        'imp_danos_agricultura',
        'imp_danos_pecuarios',
        'imp_infra_productiva',
        'imp_primera_respuesta',
        'imp_necesidad_salud',
        'imp_necesidad_humanitaria',
      ];
      expect(flags.length, 22);
      for (final f in flags) {
        expect(doc.containsKey(f), isTrue, reason: 'flag $f debe existir');
        expect(doc[f], isA<bool>());
      }

      // --- No reenvía claves locales de sync (el servidor es autoritativo).
      expect(doc.containsKey('pendiente_actualizacion'), isFalse);
      expect(doc.containsKey('pendiente_eliminacion'), isFalse);
      expect(doc.containsKey('sincronizado'), isFalse);

      // --- 11 secciones SIEMPRE array; las vacías se omiten (COMPACTO).
      for (final key in EdanDocumentoService.seccionesArray) {
        final v = doc[key];
        if (v == null) continue; // vacía → omitida
        expect(v, isA<List>(), reason: '$key debe ser array');
      }

      // --- impactO_poblacion con los 4 grupos y IDs únicos.
      final impactoList = (doc['impacto_poblacion'] as List);
      expect(impactoList.length, 4, reason: 'Debe haber 4 grupos etarios');
      final ids =
          impactoList.map((i) => (i as Map)['id_seccion'] as String).toList();
      expect(ids.toSet().length, 4, reason: 'IDs de grupo etario UÑICOS');

      // --- 3 secciones 1:1 SIEMPRE objeto único (nunca array >1 / 400).
      for (final key in EdanDocumentoService.seccionesObjeto) {
        final v = doc[key];
        expect(v, isA<Map>(), reason: '$key debe ser OBJETO único (1:1)');
      }

      // --- servicios_basicos mantiene observaciones.
      final servicio1 = (doc['servicios_basicos'] as List).first as Map;
      expect(servicio1['observaciones'],
          equals('3 postes caídos en calle principal'));

      // --- Compacto: las secciones SIN datos NO viajan.
      expect(doc.containsKey('danos_viales'), isFalse,
          reason: 'danos_viales sin datos no debe viajar');
      expect(doc.containsKey('establecimientos_salud'), isFalse);
    });

    test('parsearDocumento consume el mismo shape (round-trip) preservando '
        'id_local y las 1:1', () async {
      final localidad = _localidadCompleta();
      final doc = await EdanDocumentoService.instance.construirDocumento(localidad);

      final server = EdanDocumentoService.parsearDocumento(doc);

      // Clave de persistencia y cabecera se conservan.
      expect(server.idLocal, 'sync-test-001');
      expect(server.nombre, 'Test Sync Completo');
      expect(server.idMunicipio, 70101);

      // 1:N con datos vuelven.
      expect(server.impactoPoblacion.length, 4);
      expect(server.serviciosBasicos.length, 2);
      expect(server.danosPecuarios.length, 1);
      expect(server.proteccion.length, greaterThanOrEqualTo(8));

      // 1:1 vuelven como objeto y conservan datos.
      expect(server.necesidadPrimeraRespuesta?.salvamento, isTrue);
      expect(server.necesidadSalud?.numeroPersonas, 6);
      expect(server.necesidadHumanitaria?.alimentos, isTrue);
    });

    test('esMasNueva (LWW top-level) y aplicarPull', () {
      expect(EdanDocumentoService.esMasNueva('2026-08-26T10:00:00',
              '2026-08-25T10:00:00'),
          isTrue);
      expect(EdanDocumentoService.esMasNueva('2026-08-25T10:00:00',
              '2026-08-26T10:00:00'),
          isFalse);
      expect(EdanDocumentoService.esMasNueva(null, '2026-08-26'), isFalse);
      expect(EdanDocumentoService.esMasNueva('2026-08-26', null), isTrue);

      final local = _localidadCompleta()
        ..fechaModificacion = '2026-08-27T00:00:00';
      final server = _localidadCompleta()
        ..fechaModificacion = '2026-08-20T00:00:00'
        ..idServer = 999;

      // Local más nueva → aplicarPull NO pisa al local.
      final res = EdanDocumentoService.aplicarPull(local, server);
      expect(res.fechaModificacion, '2026-08-27T00:00:00');
      expect(res.idLocal, 'sync-test-001');
    });
  });
}