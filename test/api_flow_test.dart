import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:rea/models/edan.dart';
import 'package:rea/models/id_seccion_helper.dart';

/// Uniformiza una sección del payload en lista de filas: las 1:N ya vienen
/// como `List`; las **1:1** (`danos_vivienda`, y en el contrato también
/// `necesidad_salud`/`necesidad_primera_respuesta`/`necesidad_humanitaria`)
/// vienen como **objeto único**.
List<Map<String, dynamic>> _filasDe(Object? v) => v is List
    ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
    : v is Map
        ? [Map<String, dynamic>.from(v)]
        : const [];

void main() {
  group('API flow: toApiJson() incluye fotografia (contrato /documento)', () {
    test('EdanEstablecimientoSalud.toApiJson() incluye fotografia', () {
      final item = EdanEstablecimientoSalud(
        idSeccion: generarIdSeccion('sv'),
        nombreEstablecimiento: 'Hospital Test',
        comunidad: 'Barrio Test',
        nivelAtencion: 'Primer nivel',
        fotografia: '/uploads/existing.jpg',
        coordenadaLat: -16.5,
        coordenadaLon: -68.1,
      );
      final json = item.toApiJson();
      expect(json.containsKey('fotografia'), isTrue,
          reason: 'toApiJson() es el payload de /documento y debe llevar la foto');
      expect(json['fotografia'], equals('/uploads/existing.jpg'));
      expect(json['coordenada_lat'], equals(-16.5));
      expect(json['coordenada_lon'], equals(-68.1));
      expect(json['id_seccion'], isNotNull);
    });

    test('EdanDanoVial.toApiJson() incluye fotografia', () {
      final item = EdanDanoVial(
        idSeccion: generarIdSeccion('dv'),
        viaPuente: 'Vía',
        tramo: 'Tramo 5',
        danoParcial: true,
        danoTotal: false,
        fotografia: '/uploads/vial.jpg',
        coordenadaLat: -16.3,
        coordenadaLon: -67.8,
      );
      final json = item.toApiJson();
      expect(json.containsKey('fotografia'), isTrue);
      expect(json['via'], isTrue);
      expect(json['puente'], isFalse);
      expect(json['coordenada_lat'], equals(-16.3));
    });

    test('EdanDanoInfraPublica.toApiJson() incluye fotografia', () {
      final item = EdanDanoInfraPublica(
        idSeccion: generarIdSeccion('di'),
        comunidad: 'Barrio Test',
        tipoEstructura: 'Edificio público',
        fotografia: '/uploads/infra.jpg',
        coordenadaLat: -16.0,
        coordenadaLon: -67.7,
      );
      final json = item.toApiJson();
      expect(json.containsKey('fotografia'), isTrue);
      expect(json['tipo_estructura'], equals('Edificio público'));
    });

    test('EdanServicioBasicoDetalle.toApiJson() incluye fotografia', () {
      final item = EdanServicioBasicoDetalle(
        idSeccion: generarIdSeccion('sb'),
        tipo: 'energia_electrica',
        danoParcial: true,
        fotografia: '/uploads/serv.jpg',
        coordenadaLat: -15.6,
        coordenadaLon: -67.3,
      );
      final json = item.toApiJson();
      expect(json.containsKey('fotografia'), isTrue);
      expect(json['tipo'], equals('energia_electrica'));
    });

    test('EdanDanoUnidadEducativa.toApiJson() incluye fotografia', () {
      final item = EdanDanoUnidadEducativa(
        idSeccion: generarIdSeccion('ue'),
        nombreEstablecimiento: 'UE Bolivia',
        fotografia: '/uploads/ue.jpg',
        coordenadaLat: -15.9,
        coordenadaLon: -67.2,
      );
      final json = item.toApiJson();
      expect(json.containsKey('fotografia'), isTrue);
      expect(json['nombre_establecimiento'], equals('UE Bolivia'));
    });

    test('EdanDanoVivienda.toApiJson() incluye fotografia', () {
      final item = EdanDanoVivienda(
        idSeccion: generarIdSeccion('vv'),
        comunidad: 'Barrio Test',
        danoParcial: 5,
        danoTotal: 2,
        fotografia: '/uploads/viv.jpg',
        coordenadaLat: -16.2,
        coordenadaLon: -67.4,
      );
      final json = item.toApiJson();
      expect(json.containsKey('fotografia'), isTrue);
      expect(json['dano_parcial'], equals(5));
      expect(json['dano_total'], equals(2));
    });

    test('EdanDanoAgricultura.toApiJson() incluye fotografia', () {
      final item = EdanDanoAgricultura(
        idSeccion: generarIdSeccion('da'),
        tipoCultivo: 'Papa',
        hectareasAfectadas: 10,
        fotografia: '/uploads/agri.jpg',
        coordenadaLat: -16.1,
        coordenadaLon: -67.5,
      );
      final json = item.toApiJson();
      expect(json.containsKey('fotografia'), isTrue);
      expect(json['tipo_cultivo'], equals('Papa'));
    });

    test('EdanDanoPecuario.toApiJson() incluye fotografia', () {
      final item = EdanDanoPecuario(
        idSeccion: generarIdSeccion('dp'),
        especie: 'Bovino',
        animalesAfectados: 8,
        fotografia: '/uploads/pec.jpg',
        coordenadaLat: -15.9,
        coordenadaLon: -67.9,
      );
      final json = item.toApiJson();
      expect(json.containsKey('fotografia'), isTrue);
      expect(json['especie'], equals('Bovino'));
    });

    test('EdanInfraProductiva.toApiJson() incluye fotografia', () {
      final item = EdanInfraProductiva(
        idSeccion: generarIdSeccion('ip'),
        tipo: 'Taller',
        danoParcial: 0,
        danoTotal: 1,
        fotografia: '/uploads/ip.jpg',
        coordenadaLat: -15.6,
        coordenadaLon: -67.1,
      );
      final json = item.toApiJson();
      expect(json.containsKey('fotografia'), isTrue);
      expect(json['tipo'], equals('Taller'));
    });
  });

  group('API flow: toFotoData() incluye coordenadas de la foto', () {
    test('EstablecimientoSalud: coords de foto sobreescriben coords de sección', () {
      final item = EdanEstablecimientoSalud(
        idSeccion: generarIdSeccion('sv'),
        nombreEstablecimiento: 'Hospital',
        coordenadaLat: -16.0,
        coordenadaLon: -68.0,
      );
      final foto = EdanFoto(
        ruta: '/photos/hospital.jpg',
        latitud: -16.999,
        longitud: -68.999,
      );
      final fotoData = item.toFotoData(foto);
      expect(fotoData['coordenada_lat'], equals(-16.999),
          reason: 'Coordenadas de la foto deben sobreescribir las de la sección');
      expect(fotoData['coordenada_lon'], equals(-68.999));
      expect(fotoData.containsKey('fotografia'), isTrue,
          reason: 'toFotoData hereda toApiJson(): lleva la foto de la sección');
      expect(fotoData['nombre_establecimiento'], equals('Hospital'));
    });

    test('DanoVial: coords de foto sobreescriben', () {
      final item = EdanDanoVial(
        idSeccion: generarIdSeccion('dv'),
        viaPuente: 'Puente',
        coordenadaLat: -16.0,
        coordenadaLon: -68.0,
      );
      final foto = EdanFoto(
        ruta: '/photos/puente.jpg',
        latitud: -17.123,
        longitud: -69.456,
      );
      final fotoData = item.toFotoData(foto);
      expect(fotoData['coordenada_lat'], equals(-17.123));
      expect(fotoData['coordenada_lon'], equals(-69.456));
      expect(fotoData['via'], isFalse);
      expect(fotoData['puente'], isTrue);
    });

    test('ServicioBasico: coords de foto sobreescriben', () {
      final item = EdanServicioBasicoDetalle(
        idSeccion: generarIdSeccion('sb'),
        tipo: 'agua_potable',
        coordenadaLat: -16.0,
        coordenadaLon: -68.0,
      );
      final foto = EdanFoto(
        ruta: '/photos/agua.jpg',
        latitud: -15.555,
        longitud: -67.777,
      );
      final fotoData = item.toFotoData(foto);
      expect(fotoData['coordenada_lat'], equals(-15.555));
      expect(fotoData['coordenada_lon'], equals(-67.777));
    });

    test('DanosVivienda: coords de foto sobreescriben', () {
      final item = EdanDanoVivienda(
        idSeccion: generarIdSeccion('vv'),
        comunidad: 'Test',
        coordenadaLat: -16.0,
        coordenadaLon: -68.0,
      );
      final foto = EdanFoto(
        ruta: '/photos/viv.jpg',
        latitud: -16.888,
        longitud: -68.333,
      );
      final fotoData = item.toFotoData(foto);
      expect(fotoData['coordenada_lat'], equals(-16.888));
      expect(fotoData['coordenada_lon'], equals(-68.333));
    });
  });

  group('API flow: deduplicarSecciones()', () {
    test('deduplicarSecciones elimina duplicados por idSeccion', () {
      final id1 = generarIdSeccion('sv');
      final loc = EdanLocalidad(
        idLocal: 'test-dedup',
        nombre: 'Test',
        establecimientosSalud: [
          EdanEstablecimientoSalud(
            idSeccion: id1,
            nombreEstablecimiento: 'Hospital A',
          ),
          EdanEstablecimientoSalud(
            idSeccion: id1,
            nombreEstablecimiento: 'Hospital A DUPLICADO',
          ),
          EdanEstablecimientoSalud(
            idSeccion: generarIdSeccion('sv'),
            nombreEstablecimiento: 'Hospital B',
          ),
        ],
      );
      expect(loc.establecimientosSalud.length, equals(3));
      loc.deduplicarSecciones();
      expect(loc.establecimientosSalud.length, equals(2),
          reason: 'Debe eliminar el duplicado con mismo idSeccion');
      expect(loc.establecimientosSalud[0].nombreEstablecimiento, equals('Hospital A'));
      expect(loc.establecimientosSalud[1].nombreEstablecimiento, equals('Hospital B'));
    });

    test('deduplicarSecciones preserva items con idSeccion diferente', () {
      final loc = EdanLocalidad(
        idLocal: 'test-dedup2',
        nombre: 'Test',
        danosViales: [
          EdanDanoVial(
            idSeccion: generarIdSeccion('dv'),
            viaPuente: 'Vía',
            tramo: 'Tramo 1',
          ),
          EdanDanoVial(
            idSeccion: generarIdSeccion('dv'),
            viaPuente: 'Puente',
            tramo: 'Tramo 2',
          ),
        ],
      );
      loc.deduplicarSecciones();
      expect(loc.danosViales.length, equals(2),
          reason: 'Items con idSeccion diferente NO se eliminan');
    });

    test('deduplicarSecciones funciona con TODAS las secciones 1:N', () {
      final loc = EdanLocalidad(
        idLocal: 'test-all',
        nombre: 'Test All',
        establecimientosSalud: [
          EdanEstablecimientoSalud(idSeccion: 'sv_1', nombreEstablecimiento: 'A'),
          EdanEstablecimientoSalud(idSeccion: 'sv_1', nombreEstablecimiento: 'A dup'),
        ],
        danosViales: [
          EdanDanoVial(idSeccion: 'dv_1', viaPuente: 'Vía', tramo: 'T1'),
          EdanDanoVial(idSeccion: 'dv_1', viaPuente: 'Vía', tramo: 'T1 dup'),
        ],
        danosInfraPublica: [
          EdanDanoInfraPublica(idSeccion: 'di_1', comunidad: 'C1'),
          EdanDanoInfraPublica(idSeccion: 'di_1', comunidad: 'C1 dup'),
        ],
        serviciosBasicos: [
          EdanServicioBasicoDetalle(idSeccion: 'sb_1', tipo: 'energia_electrica'),
          EdanServicioBasicoDetalle(idSeccion: 'sb_1', tipo: 'energia_electrica'),
        ],
        unidadesEducativas: [
          EdanDanoUnidadEducativa(idSeccion: 'ue_1', nombreEstablecimiento: 'UE1'),
          EdanDanoUnidadEducativa(idSeccion: 'ue_1', nombreEstablecimiento: 'UE1 dup'),
        ],
        danosVivienda: [
          EdanDanoVivienda(idSeccion: 'vv_1', comunidad: 'V1'),
          EdanDanoVivienda(idSeccion: 'vv_1', comunidad: 'V1 dup'),
        ],
        danosAgricultura: [
          EdanDanoAgricultura(idSeccion: 'da_1', tipoCultivo: 'Papa'),
          EdanDanoAgricultura(idSeccion: 'da_1', tipoCultivo: 'Papa dup'),
        ],
        danosPecuarios: [
          EdanDanoPecuario(idSeccion: 'dp_1', especie: 'Bovino'),
          EdanDanoPecuario(idSeccion: 'dp_1', especie: 'Bovino dup'),
        ],
        infraProductiva: [
          EdanInfraProductiva(idSeccion: 'ip_1', tipo: 'Taller'),
          EdanInfraProductiva(idSeccion: 'ip_1', tipo: 'Taller dup'),
        ],
        proteccion: [
          EdanGrupoVulnerable(idSeccion: 'po_1', mujeres: 5, hombres: 3),
          EdanGrupoVulnerable(idSeccion: 'po_1', mujeres: 99, hombres: 99),
        ],
        impactoPoblacion: [
          EdanImpactoPoblacion(
            idSeccion: 'im_1',
            grupoEtario: 'Niño',
            fallecidos: 1,
          ),
          EdanImpactoPoblacion(
            idSeccion: 'im_1',
            grupoEtario: 'Niño dup',
            fallecidos: 99,
          ),
        ],
      );
      loc.deduplicarSecciones();
      expect(loc.establecimientosSalud.length, equals(1));
      expect(loc.danosViales.length, equals(1));
      expect(loc.danosInfraPublica.length, equals(1));
      expect(loc.serviciosBasicos.length, equals(1));
      expect(loc.unidadesEducativas.length, equals(1));
      expect(loc.danosVivienda.length, equals(1));
      expect(loc.danosAgricultura.length, equals(1));
      expect(loc.danosPecuarios.length, equals(1));
      expect(loc.infraProductiva.length, equals(1));
      expect(loc.proteccion.length, equals(1));
      expect(loc.impactoPoblacion.length, equals(1));
    });
  });

  group('API flow: fromJson() roundtrip preserva idSeccion', () {
    test('roundtrip completo preserva todos los idSeccion', () {
      final idSv = '11111111-1111-4111-8111-111111111111';
      final idDv = '22222222-2222-4222-8222-222222222222';
      final idDi = '33333333-3333-4333-8333-333333333333';
      final idSb = '44444444-4444-4444-8444-444444444444';
      final idUe = '55555555-5555-4555-8555-555555555555';
      final idVv = '66666666-6666-4666-8666-666666666666';
      final idDa = '77777777-7777-4777-8777-777777777777';
      final idDp = '88888888-8888-4888-8888-888888888888';
      final idIp = '99999999-9999-4999-8999-999999999999';
      final idPo = 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';
      final idIm = 'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb';

      final original = EdanLocalidad(
        idLocal: 'test-roundtrip',
        nombre: 'Test Roundtrip',
        idDepartamento: 7,
        idProvincia: 701,
        idMunicipio: 70101,
        establecimientosSalud: [
          EdanEstablecimientoSalud(idSeccion: idSv, nombreEstablecimiento: 'Hospital'),
        ],
        danosViales: [
          EdanDanoVial(idSeccion: idDv, viaPuente: 'Vía', tramo: 'T1'),
        ],
        danosInfraPublica: [
          EdanDanoInfraPublica(idSeccion: idDi, comunidad: 'C1'),
        ],
        serviciosBasicos: [
          EdanServicioBasicoDetalle(idSeccion: idSb, tipo: 'energia_electrica'),
        ],
        unidadesEducativas: [
          EdanDanoUnidadEducativa(idSeccion: idUe, nombreEstablecimiento: 'UE1'),
        ],
        danosVivienda: [
          EdanDanoVivienda(idSeccion: idVv, comunidad: 'V1'),
        ],
        danosAgricultura: [
          EdanDanoAgricultura(idSeccion: idDa, tipoCultivo: 'Papa'),
        ],
        danosPecuarios: [
          EdanDanoPecuario(idSeccion: idDp, especie: 'Bovino'),
        ],
        infraProductiva: [
          EdanInfraProductiva(idSeccion: idIp, tipo: 'Taller'),
        ],
        proteccion: [
          EdanGrupoVulnerable(idSeccion: idPo, mujeres: 5, hombres: 3),
        ],
        impactoPoblacion: [
          EdanImpactoPoblacion(idSeccion: idIm, grupoEtario: 'Niño', fallecidos: 1),
        ],
      );

      final jsonStr = jsonEncode(original.toJson());
      final restored = EdanLocalidad.fromJson(
          Map<String, dynamic>.from(jsonDecode(jsonStr) as Map));

      expect(restored.establecimientosSalud.first.idSeccion, equals(idSv));
      expect(restored.danosViales.first.idSeccion, equals(idDv));
      expect(restored.danosInfraPublica.first.idSeccion, equals(idDi));
      expect(restored.serviciosBasicos.first.idSeccion, equals(idSb));
      expect(restored.unidadesEducativas.first.idSeccion, equals(idUe));
      expect(restored.danosVivienda.first.idSeccion, equals(idVv));
      expect(restored.danosAgricultura.first.idSeccion, equals(idDa));
      expect(restored.danosPecuarios.first.idSeccion, equals(idDp));
      expect(restored.infraProductiva.first.idSeccion, equals(idIp));
      expect(restored.proteccion.first.idSeccion, equals(idPo));
      expect(restored.impactoPoblacion.first.idSeccion, equals(idIm));
    });
  });

  group('API flow: localidad completa JSON estructura', () {
    test('toApiJson() produce JSON válido con todas las secciones', () {
      final loc = EdanLocalidad(
        idLocal: 'test-full',
        idUsuario: 43,
        idTipoLocalidad: 12,
        tipoLocalidad: 'Barrio',
        idDepartamento: 7,
        idProvincia: 701,
        idMunicipio: 70101,
        nombre: 'Barrio Test',
        fechaLlenado: '2026-08-27',
        fechaEvento: '2026-08-27',
        horaEvento: '14:30:00',
        totalPoblacionAfectada: 100,
        totalFamiliasAfectadas: 25,
        totalFamiliasDamnificadas: 8,
        grupPoblacion: true,
        grupSalud: true,
        grupInfraestructura: true,
        grupServicios: true,
        grupEducacion: true,
        grupVivienda: true,
        grupAgropecuario: true,
        grupProteccion: true,
        grupNecesidades: true,
        impactoPoblacion: [
          EdanImpactoPoblacion(
            idSeccion: generarIdSeccion('im'),
            grupoEtario: 'Niño',
            fallecidos: 1,
            heridos: 3,
          ),
        ],
        establecimientosSalud: [
          EdanEstablecimientoSalud(
            idSeccion: generarIdSeccion('sv'),
            nombreEstablecimiento: 'Hospital',
            comunidad: 'Barrio',
            coordenadaLat: -16.5,
            coordenadaLon: -68.1,
          ),
        ],
        danosViales: [
          EdanDanoVial(
            idSeccion: generarIdSeccion('dv'),
            viaPuente: 'Vía',
            tramo: 'Tramo 5',
            coordenadaLat: -16.3,
            coordenadaLon: -67.8,
          ),
        ],
        danosInfraPublica: [
          EdanDanoInfraPublica(
            idSeccion: generarIdSeccion('di'),
            comunidad: 'Barrio',
            tipoEstructura: 'Edificio',
            coordenadaLat: -16.0,
            coordenadaLon: -67.7,
          ),
        ],
        serviciosBasicos: [
          EdanServicioBasicoDetalle(
            idSeccion: generarIdSeccion('sb'),
            tipo: 'energia_electrica',
            danoParcial: true,
            coordenadaLat: -15.6,
            coordenadaLon: -67.3,
          ),
        ],
        unidadesEducativas: [
          EdanDanoUnidadEducativa(
            idSeccion: generarIdSeccion('ue'),
            nombreEstablecimiento: 'UE Bolivia',
            estudiantes: 40,
            coordenadaLat: -15.9,
            coordenadaLon: -67.2,
          ),
        ],
        danosVivienda: [
          EdanDanoVivienda(
            idSeccion: generarIdSeccion('vv'),
            comunidad: 'Barrio',
            danoParcial: 5,
            danoTotal: 2,
            coordenadaLat: -16.2,
            coordenadaLon: -67.4,
          ),
        ],
        danosAgricultura: [
          EdanDanoAgricultura(
            idSeccion: generarIdSeccion('da'),
            tipoCultivo: 'Papa',
            hectareasAfectadas: 10,
            coordenadaLat: -16.1,
            coordenadaLon: -67.5,
          ),
        ],
        danosPecuarios: [
          EdanDanoPecuario(
            idSeccion: generarIdSeccion('dp'),
            especie: 'Bovino',
            animalesAfectados: 8,
            coordenadaLat: -15.9,
            coordenadaLon: -67.9,
          ),
        ],
        infraProductiva: [
          EdanInfraProductiva(
            idSeccion: generarIdSeccion('ip'),
            tipo: 'Taller',
            danoParcial: 0,
            danoTotal: 1,
            coordenadaLat: -15.6,
            coordenadaLon: -67.1,
          ),
        ],
        proteccion: [
          EdanGrupoVulnerable(
            idSeccion: generarIdSeccion('po'),
            idGrupoVulnerableCatalogo: 1,
            mujeres: 5,
            hombres: 3,
          ),
        ],
      );

      loc.recalcularFlagsImpacto();  // como hace el guardado real
      final json = loc.toApiJson();
      expect(json['id_local'], equals('test-full'));
      expect(json['id_usuario'], equals(43));
      expect(json['localidad'], equals('Barrio Test'));
      expect(json['grup_poblacion'], isTrue);
      expect(json['imp_proteccion'], isTrue);

      expect((json['impacto_poblacion'] as List).length, equals(1));
      expect((json['establecimientos_salud'] as List).length, equals(1));
      expect((json['danos_viales'] as List).length, equals(1));
      expect((json['danos_infra_publica'] as List).length, equals(1));
      expect((json['servicios_basicos'] as List).length, equals(1));
      expect((json['unidades_educativas'] as List).length, equals(1));
      // `danos_vivienda` es **1:1** en el contrato (Fase C): viaja como objeto
      // único con sus `viviendas[]` anidadas, nunca como lista.
      expect(json['danos_vivienda'], isA<Map>(),
          reason: 'danos_vivienda es 1:1 => objeto, no lista');
      expect((json['danos_vivienda'] as Map)['viviendas'], isA<List>());
      expect((json['danos_agricultura'] as List).length, equals(1));
      expect((json['danos_pecuarios'] as List).length, equals(1));
      expect((json['infra_productiva'] as List).length, equals(1));
      expect((json['proteccion'] as List), isNotEmpty,
          reason: '/documento incluye proteccion: construccion de foto la sube desde aca');

      // Cada seccion lleva su fotografia en el payload. `danos_vivienda` es
      // 1:1 (objeto único), por eso se uniformiza con `_filasDe`.
      for (final seccionKey in [
        'establecimientos_salud', 'danos_viales', 'danos_infra_publica',
        'servicios_basicos', 'unidades_educativas', 'danos_vivienda',
        'danos_agricultura', 'danos_pecuarios', 'infra_productiva',
      ]) {
        for (final item in _filasDe(json[seccionKey])) {
          expect(item.containsKey('fotografia'), isTrue,
              reason: '$seccionKey debe incluir fotografia');
          expect(item.containsKey('coordenada_lat'), isTrue,
              reason: '$seccionKey debe incluir coordenada_lat');
          expect(item.containsKey('coordenada_lon'), isTrue,
              reason: '$seccionKey debe incluir coordenada_lon');
        }
      }

      // Verificar proteccion vía endpoint dedicado
      final prot = loc.proteccionParaEndpointDedicado();
      expect(prot.length, equals(1));
      expect(prot.first['id_grupo_vulnerable_catalogo'], equals(1));
      expect((prot.first as Map).containsKey('fotografia'), isFalse);
    });
  });

  group('API flow: proteccion con tieneDatos', () {
    test('_proteccionApi filtra grupos sin datos', () {
      final loc = EdanLocalidad(
        idLocal: 'test-prot',
        nombre: 'Test',
        grupProteccion: true,
        proteccion: [
          EdanGrupoVulnerable(
            idSeccion: generarIdSeccion('po'),
            idGrupoVulnerableCatalogo: 1,
            mujeres: 5,
            hombres: 3,
          ),
          EdanGrupoVulnerable(
            idSeccion: generarIdSeccion('po'),
            idGrupoVulnerableCatalogo: 2,
            mujeres: 0,
            hombres: 0,
          ),
          EdanGrupoVulnerable(
            idSeccion: generarIdSeccion('po'),
            idGrupoVulnerableCatalogo: 3,
            mujeres: 0,
            hombres: 0,
            apoyoPsicologico: true,
          ),
          EdanGrupoVulnerable(
            idSeccion: generarIdSeccion('po'),
            idGrupoVulnerableCatalogo: 4,
            mujeres: 0,
            hombres: 0,
            reposicionDocumentos: true,
          ),
          EdanGrupoVulnerable(
            idSeccion: generarIdSeccion('po'),
            idGrupoVulnerableCatalogo: 5,
            mujeres: 0,
            hombres: 0,
            observaciones: 'Requieren atención',
          ),
        ],
      );

      final proteccion = loc.proteccionParaEndpointDedicado();
      expect(proteccion.length, equals(4),
          reason: 'Solo 4 de 5 grupos tienen tieneDatos=true');
    });

    test('todos los EdanGrupoVulnerable.tieneDatos correctamente', () {
      expect(
          EdanGrupoVulnerable(mujeres: 5, hombres: 0).tieneDatos, isTrue);
      expect(
          EdanGrupoVulnerable(mujeres: 0, hombres: 3).tieneDatos, isTrue);
      expect(
          EdanGrupoVulnerable(mujeres: 0, hombres: 0, apoyoPsicologico: true)
              .tieneDatos,
          isTrue);
      expect(
          EdanGrupoVulnerable(
                  mujeres: 0, hombres: 0, reposicionDocumentos: true)
              .tieneDatos,
          isTrue);
      expect(
          EdanGrupoVulnerable(
                  mujeres: 0,
                  hombres: 0,
                  observaciones: 'Test')
              .tieneDatos,
          isTrue);
      expect(
          EdanGrupoVulnerable(mujeres: 0, hombres: 0).tieneDatos, isFalse);
    });
  });

  group('API flow: impacto_poblacion con grupos etarios', () {
    test('impacto_poblacion expande sub-grupos correctamente', () {
      final loc = EdanLocalidad(
        idLocal: 'test-impact',
        nombre: 'Test',
        grupPoblacion: true,
        impactoPoblacion: [
          EdanImpactoPoblacion(
            idSeccion: generarIdSeccion('im'),
            grupoEtario: 'Global',
            gruposEtarios: [
              EdanGrupoEtario(
                idSeccion: generarIdSeccion('im'),
                rango: 'Niño 0-5',
                fallecidos: 1,
                heridos: 2,
              ),
              EdanGrupoEtario(
                idSeccion: generarIdSeccion('im'),
                rango: 'Adulto 19-60',
                fallecidos: 0,
                heridos: 5,
              ),
            ],
          ),
        ],
      );

      final json = loc.toApiJson();
      final impacto = json['impacto_poblacion'] as List;
      expect(impacto.length, equals(2));
      expect(impacto[0]['rango'], equals('Niño 0-5'));
      expect(impacto[1]['rango'], equals('Adulto 19-60'));

      // Cada grupo tiene su propio id_seccion
      expect(impacto[0]['id_seccion'], isNot(equals(impacto[1]['id_seccion'])),
          reason: 'Cada grupo etario debe tener id_seccion único');
    });

    test('impacto_poblacion con datos globales (sin sub-grupos)', () {
      final loc = EdanLocalidad(
        idLocal: 'test-impact-global',
        nombre: 'Test',
        grupPoblacion: true,
        impactoPoblacion: [
          EdanImpactoPoblacion(
            idSeccion: generarIdSeccion('im'),
            grupoEtario: 'Niño 0-5',
            fallecidos: 2,
            heridos: 3,
            desaparecidos: 0,
          ),
        ],
      );

      final json = loc.toApiJson();
      final impacto = json['impacto_poblacion'] as List;
      expect(impacto.length, equals(1));
      expect(impacto[0]['rango'], equals('Niño 0-5'));
      expect(impacto[0]['fallecidos'], equals(2));
    });
  });

  group('API flow: incompletosPorSeccion', () {
    test('detecta secciones incompletas correctamente', () {
      final edan = Edan(
        idDepartamento: 7,
        idProvincia: 701,
        idMunicipio: 70101,
        localidades: [
          EdanLocalidad(
            idLocal: 'test-inc',
            nombre: 'Test',
            grupPoblacion: true,
            grupProteccion: true,
            impactoPoblacion: [],
            proteccion: [
              EdanGrupoVulnerable(mujeres: 0, hombres: 0),
            ],
          ),
        ],
        responsable: EdanResponsable(),
      );

      final incompletos = edan.incompletosPorSeccion(exigirAlcalde: false);
      expect(incompletos.containsKey('03'), isTrue,
          reason: 'Sección 03 (población) debe estar incompleta');
      expect(incompletos.containsKey('10'), isTrue,
          reason: 'Sección 10 (protección) debe estar incompleta');
    });

    test('secciones completas no aparecen en incompletos', () {
      final edan = Edan(
        idDepartamento: 7,
        idProvincia: 701,
        idMunicipio: 70101,
        localidades: [
          EdanLocalidad(
            idLocal: 'test-comp',
            nombre: 'Test',
            grupPoblacion: true,
            impactoPoblacion: [
              EdanImpactoPoblacion(
                grupoEtario: 'Niño',
                fallecidos: 1,
              ),
            ],
          ),
        ],
        responsable: EdanResponsable(
          nombre: 'Test',
          cargo: 'Responsable',
        ),
      );

      final incompletos = edan.incompletosPorSeccion(exigirAlcalde: false);
      expect(incompletos.containsKey('03'), isFalse,
          reason: 'Sección 03 debe estar completa');
    });
  });

  group('API flow: edge cases de coordenadas', () {
    test('coordenadas 0.0 se preservan en toApiJson()', () {
      final item = EdanEstablecimientoSalud(
        idSeccion: generarIdSeccion('sv'),
        coordenadaLat: 0.0,
        coordenadaLon: 0.0,
      );
      final json = item.toApiJson();
      expect(json['coordenada_lat'], equals(0.0));
      expect(json['coordenada_lon'], equals(0.0));
    });

    test('coordenadas negativas (Bolivia) se preservan', () {
      final item = EdanDanoVial(
        idSeccion: generarIdSeccion('dv'),
        viaPuente: 'Vía',
        coordenadaLat: -16.5045,
        coordenadaLon: -68.1532,
      );
      final json = item.toApiJson();
      expect(json['coordenada_lat'], closeTo(-16.5045, 0.0001));
      expect(json['coordenada_lon'], closeTo(-68.1532, 0.0001));
    });

    test('toFotoData() override con coordenadas exactas de la foto', () {
      final item = EdanDanoInfraPublica(
        idSeccion: generarIdSeccion('di'),
        comunidad: 'Test',
        tipoEstructura: 'Edificio',
        coordenadaLat: -16.0,
        coordenadaLon: -68.0,
      );
      final foto = EdanFoto(
        ruta: '/photos/test.jpg',
        latitud: -17.123456789,
        longitud: -69.987654321,
      );
      final fotoData = item.toFotoData(foto);
      expect(fotoData['coordenada_lat'], equals(-17.123456789));
      expect(fotoData['coordenada_lon'], equals(-69.987654321));
    });
  });

  group('API flow: dano_vial via/puente booleanos', () {
    test('viaPuente "Vía" se convierte a via=true, puente=false', () {
      final item = EdanDanoVial(
        idSeccion: generarIdSeccion('dv'),
        viaPuente: 'Vía',
        tramo: 'T1',
      );
      final json = item.toApiJson();
      expect(json['via'], isTrue);
      expect(json['puente'], isFalse);
    });

    test('viaPuente "Puente" se convierte a via=false, puente=true', () {
      final item = EdanDanoVial(
        idSeccion: generarIdSeccion('dv'),
        viaPuente: 'Puente',
        tramo: 'T1',
      );
      final json = item.toApiJson();
      expect(json['via'], isFalse);
      expect(json['puente'], isTrue);
    });

    test('viaPuente vacío se convierte a via=false, puente=false', () {
      final item = EdanDanoVial(
        idSeccion: generarIdSeccion('dv'),
        viaPuente: '',
        tramo: 'T1',
      );
      final json = item.toApiJson();
      expect(json['via'], isFalse);
      expect(json['puente'], isFalse);
    });
  });

  group('API flow: dano_vivienda int fields', () {
    test('danoParcial y danoTotal son int, no bool', () {
      final item = EdanDanoVivienda(
        idSeccion: generarIdSeccion('vv'),
        comunidad: 'Test',
        danoParcial: 17,
        danoTotal: 3,
      );
      final json = item.toApiJson();
      expect(json['dano_parcial'], equals(17));
      expect(json['dano_total'], equals(3));
      expect(json['dano_parcial'], isA<int>());
      expect(json['dano_total'], isA<int>());
    });
  });

  group('API flow: servicios_basicos tieneDatos', () {
    test('solo tipo sin más NO tiene datos', () {
      final item = EdanServicioBasicoDetalle(tipo: 'energia_electrica');
      expect(item.tieneDatos, isFalse);
    });

    test('afectado=true SIN danoParcial/total SÍ tiene datos', () {
      final item = EdanServicioBasicoDetalle(
        tipo: 'energia_electrica',
        afectado: true,
      );
      expect(item.tieneDatos, isTrue);
    });

    test('danoParcial=true tiene datos', () {
      final item = EdanServicioBasicoDetalle(
        tipo: 'agua_potable',
        danoParcial: true,
      );
      expect(item.tieneDatos, isTrue);
    });

    test('danoTotal=true tiene datos', () {
      final item = EdanServicioBasicoDetalle(
        tipo: 'alcantarillado',
        danoTotal: true,
      );
      expect(item.tieneDatos, isTrue);
    });

    test('solo observaciones tiene datos', () {
      final item = EdanServicioBasicoDetalle(
        tipo: 'gas_domiciliario',
        observaciones: 'postes caídos',
      );
      expect(item.tieneDatos, isTrue);
    });

    test('solo coordenadas tiene datos', () {
      final item = EdanServicioBasicoDetalle(
        tipo: 'telecomunicaciones',
        coordenadaLat: -16.5,
        coordenadaLon: -68.1,
      );
      expect(item.tieneDatos, isTrue);
    });

    test('solo necesidadesInmediatas tiene datos', () {
      final item = EdanServicioBasicoDetalle(
        tipo: 'energia_electrica',
        necesidadesInmediatas: 'cable cortado',
      );
      expect(item.tieneDatos, isTrue);
    });

    test('servicio con todo vacío no tiene datos', () {
      final item = EdanServicioBasicoDetalle(tipo: '');
      expect(item.tieneDatos, isFalse);
    });

    test('toApiJson() incluye id_seccion cuando tiene', () {
      final item = EdanServicioBasicoDetalle(
        idSeccion: 'sb_123_abc',
        tipo: 'energia_electrica',
        danoParcial: true,
      );
      final json = item.toApiJson();
      expect(json['id_seccion'], 'sb_123_abc');
      expect(json['tipo'], 'energia_electrica');
      expect(json['dano_parcial'], true);
    });

    test('toApiJson() incluye fotografia', () {
      final item = EdanServicioBasicoDetalle(
        tipo: 'agua_potable',
        danoParcial: true,
      );
      expect(item.toApiJson().containsKey('fotografia'), isTrue);
    });

    test('toFotoData() override coordenadas con las de la foto', () {
      final item = EdanServicioBasicoDetalle(
        idSeccion: 'sb_456_def',
        tipo: 'alcantarillado',
        coordenadaLat: -16.0,
        coordenadaLon: -68.0,
      );
      final foto = EdanFoto(
        latitud: -17.5,
        longitud: -69.2,
      );
      final data = item.toFotoData(foto);
      expect(data['coordenada_lat'], -17.5);
      expect(data['coordenada_lon'], -69.2);
      expect(data['id_seccion'], 'sb_456_def');
    });

    test('4 items: 2 con datos + 2 vacíos → tieneDatos correcto', () {
      final items = [
        EdanServicioBasicoDetalle(tipo: 'energia_electrica', danoParcial: true),
        EdanServicioBasicoDetalle(tipo: 'agua_potable'),
        EdanServicioBasicoDetalle(tipo: 'alcantarillado', danoTotal: true),
        EdanServicioBasicoDetalle(tipo: 'telecomunicaciones'),
      ];
      expect(items[0].tieneDatos, isTrue);
      expect(items[1].tieneDatos, isFalse);
      expect(items[2].tieneDatos, isTrue);
      expect(items[3].tieneDatos, isFalse);
      expect(items.where((s) => s.tieneDatos).length, 2);
    });

    test('roundtrip fromJson→toJson preserva todos los campos', () {
      const id = 'c9c9c9c9-c9c9-4c9c-8c9c-c9c9c9c9c9c9';
      final original = EdanServicioBasicoDetalle(
        idSeccion: id,
        tipo: 'energia_electrica',
        afectado: true,
        danoParcial: true,
        danoTotal: false,
        necesidadesInmediatas: 'postes caídos',
        observaciones: 'zona urbana',
        coordenadaLat: -16.5045,
        coordenadaLon: -68.1532,
      );
      final json = original.toJson();
      final restored = EdanServicioBasicoDetalle.fromJson(json);
      expect(restored.idSeccion, id);
      expect(restored.tipo, 'energia_electrica');
      expect(restored.afectado, isTrue);
      expect(restored.danoParcial, isTrue);
      expect(restored.danoTotal, isFalse);
      expect(restored.necesidadesInmediatas, 'postes caídos');
      expect(restored.observaciones, 'zona urbana');
      expect(restored.coordenadaLat, -16.5045);
      expect(restored.coordenadaLon, -68.1532);
    });
  });

  group('API flow: random multi-sección stress test', () {
    test('10 localidades random con todas las secciones', () {
      final rng = Random(99);
      final sectores = ['sv', 'dv', 'di', 'sb', 'ue', 'vv', 'da', 'dp', 'ip'];

      for (var i = 0; i < 10; i++) {
        final nSecciones = rng.nextInt(5) + 2;
        final sectoresUsados = sectores.toList()..shuffle(rng);
        final activos = sectoresUsados.take(nSecciones).toSet();

        final loc = EdanLocalidad(
          idLocal: 'test-rand-$i',
          nombre: 'Localidad $i',
          grupPoblacion: true,
          grupSalud: activos.contains('sv'),
          grupInfraestructura: activos.contains('dv') || activos.contains('di'),
          grupServicios: activos.contains('sb'),
          grupEducacion: activos.contains('ue'),
          grupVivienda: activos.contains('vv'),
          grupAgropecuario: activos.contains('da') || activos.contains('dp') || activos.contains('ip'),
          grupProteccion: true,
          establecimientosSalud: activos.contains('sv')
              ? List.generate(
                  rng.nextInt(3) + 1,
                  (j) => EdanEstablecimientoSalud(
                    idSeccion: generarIdSeccion('sv'),
                    nombreEstablecimiento: 'Salud $j',
                    coordenadaLat: -16.0 - rng.nextDouble(),
                    coordenadaLon: -68.0 - rng.nextDouble(),
                  ),
                )
              : [],
          danosViales: activos.contains('dv')
              ? List.generate(
                  rng.nextInt(2) + 1,
                  (j) => EdanDanoVial(
                    idSeccion: generarIdSeccion('dv'),
                    viaPuente: rng.nextBool() ? 'Vía' : 'Puente',
                    tramo: 'Tramo $j',
                    coordenadaLat: -16.0 - rng.nextDouble(),
                    coordenadaLon: -68.0 - rng.nextDouble(),
                  ),
                )
              : [],
          danosInfraPublica: activos.contains('di')
              ? List.generate(
                  rng.nextInt(2) + 1,
                  (j) => EdanDanoInfraPublica(
                    idSeccion: generarIdSeccion('di'),
                    comunidad: 'Barrio $j',
                    tipoEstructura: 'Edificio',
                    coordenadaLat: -16.0 - rng.nextDouble(),
                    coordenadaLon: -68.0 - rng.nextDouble(),
                  ),
                )
              : [],
          serviciosBasicos: activos.contains('sb')
              ? List.generate(
                  5,
                  (j) => EdanServicioBasicoDetalle(
                    idSeccion: generarIdSeccion('sb'),
                    tipo: ['energia_electrica', 'agua_potable', 'alcantarillado', 'gas_domiciliario', 'telecomunicaciones'][j],
                    danoParcial: rng.nextBool(),
                    coordenadaLat: -16.0 - rng.nextDouble(),
                    coordenadaLon: -68.0 - rng.nextDouble(),
                  ),
                )
              : [],
          unidadesEducativas: activos.contains('ue')
              ? List.generate(
                  rng.nextInt(2) + 1,
                  (j) => EdanDanoUnidadEducativa(
                    idSeccion: generarIdSeccion('ue'),
                    nombreEstablecimiento: 'UE $j',
                    estudiantes: rng.nextInt(100),
                    coordenadaLat: -16.0 - rng.nextDouble(),
                    coordenadaLon: -68.0 - rng.nextDouble(),
                  ),
                )
              : [],
          danosVivienda: activos.contains('vv')
              ? List.generate(
                  rng.nextInt(3) + 1,
                  (j) => EdanDanoVivienda(
                    idSeccion: generarIdSeccion('vv'),
                    comunidad: 'Barrio $j',
                    danoParcial: rng.nextInt(20),
                    danoTotal: rng.nextInt(10),
                    coordenadaLat: -16.0 - rng.nextDouble(),
                    coordenadaLon: -68.0 - rng.nextDouble(),
                  ),
                )
              : [],
          danosAgricultura: activos.contains('da')
              ? List.generate(
                  rng.nextInt(2) + 1,
                  (j) => EdanDanoAgricultura(
                    idSeccion: generarIdSeccion('da'),
                    tipoCultivo: ['Papa', 'Maíz', 'Trigo'][j % 3],
                    hectareasAfectadas: rng.nextInt(50),
                    coordenadaLat: -16.0 - rng.nextDouble(),
                    coordenadaLon: -68.0 - rng.nextDouble(),
                  ),
                )
              : [],
          danosPecuarios: activos.contains('dp')
              ? List.generate(
                  rng.nextInt(2) + 1,
                  (j) => EdanDanoPecuario(
                    idSeccion: generarIdSeccion('dp'),
                    especie: ['Bovino', 'Ovino', 'Porcino'][j % 3],
                    animalesAfectados: rng.nextInt(20),
                    coordenadaLat: -16.0 - rng.nextDouble(),
                    coordenadaLon: -68.0 - rng.nextDouble(),
                  ),
                )
              : [],
          infraProductiva: activos.contains('ip')
              ? List.generate(
                  rng.nextInt(2) + 1,
                  (j) => EdanInfraProductiva(
                    idSeccion: generarIdSeccion('ip'),
                    tipo: ['Taller', 'Almacén', 'Fábrica'][j % 3],
                    danoParcial: rng.nextInt(5),
                    danoTotal: rng.nextInt(3),
                    coordenadaLat: -16.0 - rng.nextDouble(),
                    coordenadaLon: -68.0 - rng.nextDouble(),
                  ),
                )
              : [],
          proteccion: List.generate(
            3,
            (j) => EdanGrupoVulnerable(
              idSeccion: generarIdSeccion('po'),
              idGrupoVulnerableCatalogo: j + 1,
              mujeres: rng.nextInt(20),
              hombres: rng.nextInt(15),
            ),
          ),
        );

        final json = loc.toApiJson();
        final jsonStr = jsonEncode(json);
        expect(jsonStr.isNotEmpty, isTrue);

        // Cada seccion lleva su fotografia en el payload. `danos_vivienda` es
        // 1:1 (objeto único), así que se uniformiza con `_filasDe`.
        for (final key in [
          'establecimientos_salud', 'danos_viales', 'danos_infra_publica',
          'servicios_basicos', 'unidades_educativas', 'danos_vivienda',
          'danos_agricultura', 'danos_pecuarios', 'infra_productiva',
        ]) {
          for (final item in _filasDe(json[key])) {
            expect(item.containsKey('fotografia'), isTrue,
                reason: 'Localidad $i: $key debe incluir fotografia');
          }
        }

        // Verificar roundtrip
        final restored = EdanLocalidad.fromJson(
            Map<String, dynamic>.from(jsonDecode(jsonStr) as Map));
        expect(restored.nombre, equals(loc.nombre));
        expect(restored.establecimientosSalud.length,
            equals(loc.establecimientosSalud.length));
        expect(restored.danosViales.length, equals(loc.danosViales.length));
        expect(restored.danosInfraPublica.length,
            equals(loc.danosInfraPublica.length));
        expect(restored.serviciosBasicos.length,
            equals(loc.serviciosBasicos.length));
        expect(restored.unidadesEducativas.length,
            equals(loc.unidadesEducativas.length));
        // `danos_vivienda` es 1:1: el payload lleva UN objeto, así que el
        // roundtrip no puede devolver N filas (colapsa a la primera).
        expect(restored.danosVivienda.length,
            equals(loc.danosVivienda.isEmpty ? 0 : 1));
        expect(restored.danosAgricultura.length,
            equals(loc.danosAgricultura.length));
        expect(restored.danosPecuarios.length, equals(loc.danosPecuarios.length));
        expect(restored.infraProductiva.length,
            equals(loc.infraProductiva.length));
      }
    });
  });
}
