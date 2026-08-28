import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:rea/models/edan.dart';
import 'package:rea/models/id_seccion_helper.dart';

void main() {
  group('Secciones combinadas: Población + Protección + Random', () {
    final rng = Random(42);

    EdanGrupoVulnerable _makeGrupo(int catalogId, {
      int mujeres = 0,
      int hombres = 0,
      bool? apoyo,
      bool? reposicion,
      String obs = '',
    }) {
      return EdanGrupoVulnerable(
        idSeccion: generarIdSeccion('po'),
        idGrupoVulnerableCatalogo: catalogId,
        mujeres: mujeres,
        hombres: hombres,
        apoyoPsicologico: apoyo,
        reposicionDocumentos: reposicion,
        observaciones: obs,
      );
    }

    EdanImpactoPoblacion _makePoblacion({
      required String rango,
      int fallecidos = 0,
      int heridos = 0,
      int desaparecidos = 0,
      String obs = '',
    }) {
      return EdanImpactoPoblacion(
        idSeccion: generarIdSeccion('im'),
        grupoEtario: rango,
        fallecidos: fallecidos,
        heridos: heridos,
        desaparecidos: desaparecidos,
        observaciones: obs,
        gruposEtarios: [
          EdanGrupoEtario(
            idSeccion: generarIdSeccion('im'),
            rango: rango,
            fallecidos: fallecidos,
            heridos: heridos,
            desaparecidos: desaparecidos,
            observaciones: obs,
          ),
        ],
      );
    }

    EdanEstablecimientoSalud _makeEstSalud(String nombre, {String nivel = 'Primer nivel'}) {
      return EdanEstablecimientoSalud(
        idSeccion: generarIdSeccion('sv'),
        nombreEstablecimiento: nombre,
        comunidad: 'Barrio Test',
        nivelAtencion: nivel,
        danoParcial: rng.nextBool(),
        medicosAfectados: rng.nextInt(5),
        enfermerasAfectados: rng.nextInt(3),
        otrosAfectados: rng.nextInt(4),
        coordenadaLat: -16.5 + rng.nextDouble(),
        coordenadaLon: -68.1 + rng.nextDouble(),
      );
    }

    EdanDanoVial _makeDanoVial(String via) {
      return EdanDanoVial(
        idSeccion: generarIdSeccion('dv'),
        viaPuente: via,
        tramo: 'Tramo ${rng.nextInt(10)}',
        danoParcial: rng.nextBool(),
        danoTotal: rng.nextBool(),
        coordenadaLat: -16.5 + rng.nextDouble(),
        coordenadaLon: -68.1 + rng.nextDouble(),
      );
    }

    EdanDanoInfraPublica _makeInfra(String tipo) {
      return EdanDanoInfraPublica(
        idSeccion: generarIdSeccion('di'),
        comunidad: 'Barrio Test',
        tipoEstructura: tipo,
        danoParcial: rng.nextBool(),
        danoTotal: rng.nextBool(),
        coordenadaLat: -16.5 + rng.nextDouble(),
        coordenadaLon: -68.1 + rng.nextDouble(),
      );
    }

    EdanServicioBasicoDetalle _makeServicio(String tipo) {
      return EdanServicioBasicoDetalle(
        idSeccion: generarIdSeccion('sb'),
        tipo: tipo,
        danoParcial: rng.nextBool(),
        danoTotal: rng.nextBool(),
        coordenadaLat: -16.5 + rng.nextDouble(),
        coordenadaLon: -68.1 + rng.nextDouble(),
      );
    }

    EdanDanoUnidadEducativa _makeUnidadEdu(String nombre) {
      return EdanDanoUnidadEducativa(
        idSeccion: generarIdSeccion('ue'),
        nombreEstablecimiento: nombre,
        estudiantes: rng.nextInt(200),
        profesores: rng.nextInt(20),
        administrativos: rng.nextInt(10),
        coordenadaLat: -16.5 + rng.nextDouble(),
        coordenadaLon: -68.1 + rng.nextDouble(),
      );
    }

    EdanDanoVivienda _makeVivienda() {
      return EdanDanoVivienda(
        idSeccion: generarIdSeccion('vv'),
        comunidad: 'Barrio Test',
        danoParcial: rng.nextInt(20),
        danoTotal: rng.nextInt(10),
        coordenadaLat: -16.5 + rng.nextDouble(),
        coordenadaLon: -68.1 + rng.nextDouble(),
      );
    }

    EdanDanoAgricultura _makeAgri(String cultivo) {
      return EdanDanoAgricultura(
        idSeccion: generarIdSeccion('da'),
        tipoCultivo: cultivo,
        hectareasAfectadas: rng.nextInt(50),
        hectareasPerdidas: rng.nextInt(20),
        coordenadaLat: -16.5 + rng.nextDouble(),
        coordenadaLon: -68.1 + rng.nextDouble(),
      );
    }

    EdanDanoPecuario _makePecuario(String especie) {
      return EdanDanoPecuario(
        idSeccion: generarIdSeccion('dp'),
        especie: especie,
        animalesAfectados: rng.nextInt(30),
        animalesMuertos: rng.nextInt(5),
        coordenadaLat: -16.5 + rng.nextDouble(),
        coordenadaLon: -68.1 + rng.nextDouble(),
      );
    }

    EdanInfraProductiva _makeInfraProd(String tipo) {
      return EdanInfraProductiva(
        idSeccion: generarIdSeccion('ip'),
        tipo: tipo,
        danoParcial: rng.nextInt(10),
        danoTotal: rng.nextInt(5),
        coordenadaLat: -16.5 + rng.nextDouble(),
        coordenadaLon: -68.1 + rng.nextDouble(),
      );
    }

    Map<String, bool> _randomImpacts(Random rng) {
      return {
        'poblacion': true,
        'proteccion': true,
        'salud': rng.nextBool(),
        'infraestructura': rng.nextBool(),
        'servicios': rng.nextBool(),
        'educacion': rng.nextBool(),
        'vivienda': rng.nextBool(),
        'agropecuario': rng.nextBool(),
        'necesidades': rng.nextBool(),
      };
    }

    EdanLocalidad _buildLocalidad(Map<String, bool> imp, {String idLocal = 'test-loc'}) {
      final proteccion = [
        _makeGrupo(1, mujeres: imp['proteccion']! ? 5 : 0, hombres: imp['proteccion']! ? 3 : 0, apoyo: true),
        _makeGrupo(2, mujeres: imp['proteccion']! ? 2 : 0),
        _makeGrupo(3),
        _makeGrupo(4),
        _makeGrupo(5),
        _makeGrupo(6),
        _makeGrupo(7),
        _makeGrupo(8),
      ];

      return EdanLocalidad(
        idLocal: idLocal,
        tipoLocalidad: 'Barrio',
        idTipoLocalidad: 12,
        nombre: 'Test Localidad',
        idDepartamento: 7,
        idProvincia: 701,
        idMunicipio: 70101,
        fechaLlenado: '2026-08-27',
        fechaEvento: '2026-08-27',
        horaEvento: '14:30:00',
        totalPoblacionAfectada: 100,
        totalFamiliasAfectadas: 25,
        totalFamiliasDamnificadas: 8,
        impPoblacion: imp['poblacion']!,
        impSalud: imp['salud']!,
        impInfraestructura: imp['infraestructura']!,
        impServicios: imp['servicios']!,
        impEducacion: imp['educacion']!,
        impVivienda: imp['vivienda']!,
        impAgropecuario: imp['agropecuario']!,
        impProteccion: imp['proteccion']!,
        impNecesidades: imp['necesidades']!,
        impactoPoblacion: imp['poblacion']!
            ? [
                _makePoblacion(rango: 'Niño (a) 0-5 años', fallecidos: 1, heridos: 3),
                _makePoblacion(rango: 'Escolar de 6-18 años', heridos: 5),
                _makePoblacion(rango: 'Adulto de 19-60 años', fallecidos: 2, heridos: 8, desaparecidos: 1),
                _makePoblacion(rango: 'Adulto mayor de 60 años adelante', fallecidos: 1, heridos: 2),
              ]
            : [],
        establecimientosSalud: imp['salud']!
            ? [_makeEstSalud('Hospital Test'), _makeEstSalud('Centro Salud')]
            : [],
        necesidadSalud: imp['salud']! ? EdanNecesidadSalud(numeroPersonas: 6) : null,
        danosViales: imp['infraestructura']!
            ? [_makeDanoVial('Vía'), _makeDanoVial('Puente')]
            : [],
        danosInfraPublica: imp['infraestructura']!
            ? [_makeInfra('Edificio público'), _makeInfra('Puente peatonal')]
            : [],
        serviciosBasicos: imp['servicios']!
            ? [
                _makeServicio('energia_electrica'),
                _makeServicio('agua_potable'),
                _makeServicio('alcantarillado'),
                _makeServicio('gas_domiciliario'),
                _makeServicio('telecomunicaciones'),
              ]
            : [],
        unidadesEducativas: imp['educacion']!
            ? [_makeUnidadEdu('UE Juan XXIII'), _makeUnidadEdu('UE Bolivia')]
            : [],
        danosVivienda: imp['vivienda']!
            ? [_makeVivienda(), _makeVivienda()]
            : [],
        danosAgricultura: imp['agropecuario']!
            ? [_makeAgri('Papa'), _makeAgri('Maíz')]
            : [],
        danosPecuarios: imp['agropecuario']!
            ? [_makePecuario('Bovino'), _makePecuario('Ovino')]
            : [],
        infraProductiva: imp['agropecuario']!
            ? [_makeInfraProd('Taller'), _makeInfraProd('Almacén')]
            : [],
        proteccion: proteccion,
        necesidadHumanitaria: imp['necesidades']!
            ? EdanNecesidadHumanitaria(alimentos: true, refugioVivienda: true)
            : null,
      );
    }

    test('1 localidad: solo Población + Protección (impactos base)', () {
      final imp = {
        'poblacion': true,
        'salud': false,
        'infraestructura': false,
        'servicios': false,
        'educacion': false,
        'vivienda': false,
        'agropecuario': false,
        'proteccion': true,
        'necesidades': false,
      };
      final loc = _buildLocalidad(imp);
      final json = loc.toApiJson();

      print('\n=== ESCENARIO 1: Solo Población + Protección ===');

      expect(json['imp_poblacion'], true);
      expect(json['imp_proteccion'], true);
      expect(json['imp_salud'], false);
      expect(json['imp_infraestructura'], false);
      expect(json['imp_servicios'], false);
      expect(json['imp_educacion'], false);
      expect(json['imp_vivienda'], false);
      expect(json['imp_agropecuario'], false);
      expect(json['imp_necesidades'], false);

      final impacto = json['impacto_poblacion'] as List;
      print('impacto_poblacion: ${impacto.length} items');
      expect(impacto.length, 4, reason: '4 grupos etarios');

      final idsImpacto = impacto.map((e) => e['id_seccion'] as String).toList();
      expect(idsImpacto.toSet().length, idsImpacto.length, reason: 'IDs de impacto únicos');

      final proteccion = loc.proteccionParaEndpointDedicado();
      print('proteccion: ${proteccion.length} items (solo los con tieneDatos)');
      expect(proteccion.length, 2, reason: 'Solo 2 grupos con datos (mujeres>0)');

      for (final g in proteccion) {
        expect(g['id_seccion'], isNotNull);
        expect(g['id_grupo_vulnerable_catalogo'], isNotNull);
        expect(g['mujeres'] + g['hombres'], greaterThan(0));
      }

      expect(json['establecimientos_salud'], isEmpty);
      expect(json['danos_viales'], isEmpty);
      expect(json['danos_infra_publica'], isEmpty);
      expect(json['servicios_basicos'], isEmpty);
      expect(json['unidades_educativas'], isEmpty);
      expect(json['danos_vivienda'], isEmpty);
      expect(json['danos_agricultura'], isEmpty);
      expect(json['danos_pecuarios'], isEmpty);
      expect(json['infra_productiva'], isEmpty);

      print('✅ Payload OK: ${JsonEncoder.withIndent('  ', null).convert(json).length} chars');
    });

    test('2 localidades: Población + Protección + Salud + Infraestructura', () {
      final imp1 = {
        'poblacion': true, 'salud': true, 'infraestructura': true,
        'servicios': false, 'educacion': false, 'vivienda': false,
        'agropecuario': false, 'proteccion': true, 'necesidades': false,
      };
      final imp2 = {
        'poblacion': true, 'salud': true, 'infraestructura': false,
        'servicios': false, 'educacion': false, 'vivienda': false,
        'agropecuario': false, 'proteccion': true, 'necesidades': false,
      };

      final loc1 = _buildLocalidad(imp1, idLocal: 'loc-001');
      final loc2 = _buildLocalidad(imp2, idLocal: 'loc-002');

      final payload = {
        'localidades': [loc1.toApiJson(), loc2.toApiJson()],
      };

      print('\n=== ESCENARIO 2: 2 localidades con Población+Protección+Salud+Infra ===');

      final localidades = payload['localidades'] as List;
      final l1 = localidades[0] as Map<String, dynamic>;
      final l2 = localidades[1] as Map<String, dynamic>;

      expect(l1['imp_salud'], true);
      expect(l1['imp_infraestructura'], true);
      expect(l2['imp_salud'], true);
      expect(l2['imp_infraestructura'], false);

      final est1 = l1['establecimientos_salud'] as List;
      print('loc1 establecimientos: ${est1.length}');
      expect(est1.length, 2);

      final est2 = l2['establecimientos_salud'] as List;
      print('loc2 establecimientos: ${est2.length}');
      expect(est2.length, 2);

      final vias1 = l1['danos_viales'] as List;
      print('loc1 daños viales: ${vias1.length}');
      expect(vias1.length, 2);

      final vias2 = l2['danos_viales'] as List;
      print('loc2 daños viales: ${vias2.length}');
      expect(vias2.length, 0);

      final prot1 = loc1.proteccionParaEndpointDedicado();
      final prot2 = loc2.proteccionParaEndpointDedicado();
      print('loc1 proteccion: ${prot1.length} | loc2 proteccion: ${prot2.length}');
      expect(prot1.length, 2, reason: 'Solo grupos con tieneDatos');
      expect(prot2.length, 2);

      final idsProt1 = prot1.map((e) => e['id_seccion'] as String).toList();
      final idsProt2 = prot2.map((e) => e['id_seccion'] as String).toList();
      final allProtIds = [...idsProt1, ...idsProt2];
      expect(allProtIds.toSet().length, allProtIds.length,
          reason: 'Todos los IDs de protección deben ser únicos entre localidades');

      print('✅ Payload OK para 2 localidades');
    });

    test('Verificar que IDs de sección son únicos entre TODAS las secciones', () {
      final imp = {
        'poblacion': true, 'salud': true, 'infraestructura': true,
        'servicios': true, 'educacion': true, 'vivienda': true,
        'agropecuario': true, 'proteccion': true, 'necesidades': true,
      };
      final loc = _buildLocalidad(imp);
      final json = loc.toApiJson();

      print('\n=== VERIFICACIÓN GLOBAL DE IDs ÚNICOS ===');

      final allIds = <String>[];

      for (final item in json['impacto_poblacion'] as List) {
        final id = item['id_seccion'];
        if (id != null) allIds.add('poblacion:$id');
      }
      for (final item in json['establecimientos_salud'] as List) {
        final id = item['id_seccion'];
        if (id != null) allIds.add('salud:$id');
      }
      for (final item in json['danos_viales'] as List) {
        final id = item['id_seccion'];
        if (id != null) allIds.add('vial:$id');
      }
      for (final item in json['danos_infra_publica'] as List) {
        final id = item['id_seccion'];
        if (id != null) allIds.add('infra:$id');
      }
      for (final item in json['servicios_basicos'] as List) {
        final id = item['id_seccion'];
        if (id != null) allIds.add('servicio:$id');
      }
      for (final item in json['unidades_educativas'] as List) {
        final id = item['id_seccion'];
        if (id != null) allIds.add('edu:$id');
      }
      for (final item in json['danos_vivienda'] as List) {
        final id = item['id_seccion'];
        if (id != null) allIds.add('vivienda:$id');
      }
      for (final item in json['danos_agricultura'] as List) {
        final id = item['id_seccion'];
        if (id != null) allIds.add('agri:$id');
      }
      for (final item in json['danos_pecuarios'] as List) {
        final id = item['id_seccion'];
        if (id != null) allIds.add('pecuario:$id');
      }
      for (final item in json['infra_productiva'] as List) {
        final id = item['id_seccion'];
        if (id != null) allIds.add('iprod:$id');
      }
      for (final item in loc.proteccionParaEndpointDedicado()) {
        final id = item['id_seccion'];
        if (id != null) allIds.add('protec:$id');
      }
      final npr = json['necesidad_primera_respuesta'];
      if (npr is Map && npr['id_seccion'] != null) {
        allIds.add('npr:${npr['id_seccion']}');
      }
      final nh = json['necesidad_humanitaria'];
      if (nh is Map && nh['id_seccion'] != null) {
        allIds.add('nh:${nh['id_seccion']}');
      }

      print('Total IDs: ${allIds.length}');
      final uniqueIds = allIds.toSet();
      print('IDs únicos: ${uniqueIds.length}');

      final seen = <String>{};
      final duplicados = <String>{};
      for (final id in allIds) {
        if (!seen.add(id)) {
          duplicados.add(id);
        }
      }
      print('Total IDs: ${allIds.length}');
      print('IDs únicos: ${seen.length}');
      if (duplicados.isNotEmpty) {
        for (final d in duplicados) {
          print('  ⚠️  DUPLICADO: $d');
        }
      }
      expect(duplicados, isEmpty, reason: 'No debe haber IDs duplicados entre secciones');
      print('✅ Todos los IDs son únicos');
    });

    test('deduplicarSecciones no elimina items válidos', () {
      final imp = {
        'poblacion': true, 'salud': true, 'infraestructura': false,
        'servicios': false, 'educacion': false, 'vivienda': false,
        'agropecuario': false, 'proteccion': true, 'necesidades': false,
      };
      final loc = _buildLocalidad(imp);

      final antesEst = loc.establecimientosSalud.length;
      final antesProt = loc.proteccion.length;

      print('\n=== ANTES de deduplicar ===');
      print('establecimientosSalud: $antesEst');
      print('proteccion: $antesProt');

      loc.deduplicarSecciones();

      final despuesEst = loc.establecimientosSalud.length;
      final despuesProt = loc.proteccion.length;

      print('DESPUÉS de deduplicar:');
      print('establecimientosSalud: $despuesEst');
      print('proteccion: $despuesProt');

      expect(despuesEst, antesEst,
          reason: 'deduplicar NO debe eliminar establecimientos válidos');
      expect(despuesProt, antesProt,
          reason: 'deduplicar NO debe eliminar grupos de protección');
    });

    test('deduplicarSecciones SÍ elimina duplicados reales', () {
      final imp = {
        'poblacion': true, 'salud': false, 'infraestructura': false,
        'servicios': false, 'educacion': false, 'vivienda': false,
        'agropecuario': false, 'proteccion': true, 'necesidades': false,
      };
      final loc = _buildLocalidad(imp);

      final idDuplicado = generarIdSeccion('sv');
      loc.establecimientosSalud = [
        EdanEstablecimientoSalud(idSeccion: idDuplicado, nombreEstablecimiento: 'Original'),
        EdanEstablecimientoSalud(idSeccion: idDuplicado, nombreEstablecimiento: 'Duplicado'),
      ];

      print('\n=== Duplicado real ===');
      print('Antes: ${loc.establecimientosSalud.length} items');

      loc.deduplicarSecciones();

      print('Después: ${loc.establecimientosSalud.length} items');
      expect(loc.establecimientosSalud.length, 1,
          reason: 'Un duplicado con el mismo idSeccion debe eliminarse');
    });

    test('Población + Protección: incompletosPorSeccion retorna solo secciones activas', () {
      final imp = {
        'poblacion': true, 'salud': false, 'infraestructura': false,
        'servicios': false, 'educacion': false, 'vivienda': false,
        'agropecuario': false, 'proteccion': true, 'necesidades': false,
      };
      final loc = _buildLocalidad(imp);

      final edan = Edan(
        idDepartamento: 7,
        idProvincia: 701,
        idMunicipio: 70101,
        idTipoEvento: 5,
        tipoEventoNombre: 'Inundación',
        fechaLlenado: '2026-08-27',
        fechaEvento: '2026-08-27',
        localidades: [loc],
      );

      final incompletos = edan.incompletosPorSeccion(exigirAlcalde: false);

      print('\n=== INCOMPLETOS (Población + Protección) ===');
      incompletos.forEach((k, v) => print('  Sección $k: $v'));

      expect(incompletos.containsKey('04'), false, reason: 'Salud no activa, no debe existir');
      expect(incompletos.containsKey('05'), false, reason: 'Infra no activa, no debe existir');
      expect(incompletos.containsKey('06'), false, reason: 'Servicios no activo, no debe existir');
      expect(incompletos.containsKey('07'), false, reason: 'Educación no activa, no debe existir');
      expect(incompletos.containsKey('08'), false, reason: 'Vivienda no activa, no debe existir');
      expect(incompletos.containsKey('09'), false, reason: 'Agropecuario no activo, no debe existir');
      expect(incompletos.containsKey('11'), false, reason: 'Necesidades no activo, no debe existir');

      expect(incompletos.containsKey('10'), false,
          reason: 'Protección tiene 2 grupos con datos → NO incompleta');

      print('✅ Solo secciones activas evaluadas, protección completa');
    });

    test('Protección vacía (impProteccion=true pero sin datos): incompleta', () {
      final loc = _buildLocalidad({
        'poblacion': true, 'salud': false, 'infraestructura': false,
        'servicios': false, 'educacion': false, 'vivienda': false,
        'agropecuario': false, 'proteccion': true, 'necesidades': false,
      });

      for (final g in loc.proteccion) {
        g.mujeres = 0;
        g.hombres = 0;
        g.apoyoPsicologico = null;
        g.reposicionDocumentos = null;
        g.observaciones = '';
      }

      final edan = Edan(
        idDepartamento: 7, idProvincia: 701, idMunicipio: 70101,
        idTipoEvento: 5, tipoEventoNombre: 'Inundación',
        fechaLlenado: '2026-08-27', fechaEvento: '2026-08-27',
        localidades: [loc],
      );

      final incompletos = edan.incompletosPorSeccion(exigirAlcalde: false);

      print('\n=== Protección vacía: incompletos ===');
      incompletos.forEach((k, v) => print('  Sección $k: $v'));

      expect(incompletos.containsKey('10'), true,
          reason: 'Protección activa pero TODOS los grupos vacíos → INCOMPLETA');
      print('✅ Protección vacía detectada como incompleta');
    });

    test('Sección 10 (Protección): solo 1 de 8 grupos con datos → completa y se envía', () {
      final loc = _buildLocalidad({
        'poblacion': true, 'salud': false, 'infraestructura': false,
        'servicios': false, 'educacion': false, 'vivienda': false,
        'agropecuario': false, 'proteccion': true, 'necesidades': false,
      });

      for (final g in loc.proteccion) {
        g.mujeres = 0;
        g.hombres = 0;
        g.apoyoPsicologico = null;
        g.reposicionDocumentos = null;
        g.observaciones = '';
      }

      loc.proteccion[0].mujeres = 5;
      loc.proteccion[0].hombres = 3;

      final edan = Edan(
        idDepartamento: 7, idProvincia: 701, idMunicipio: 70101,
        idTipoEvento: 5, tipoEventoNombre: 'Inundación',
        fechaLlenado: '2026-08-27', fechaEvento: '2026-08-27',
        localidades: [loc],
      );

      final incompletos = edan.incompletosPorSeccion(exigirAlcalde: false);
      expect(incompletos.containsKey('10'), false,
          reason: '1 grupo con datos → protección COMPLETA');

      final proteccion = loc.proteccionParaEndpointDedicado();
      print('\n=== 1 de 8 grupos con datos ===');
      print('proteccion enviada: ${proteccion.length} items');

      expect(proteccion.length, 1, reason: 'Solo 1 grupo tiene tieneDatos=true');
      expect(proteccion[0]['mujeres'], 5);
      expect(proteccion[0]['hombres'], 3);
      expect(proteccion[0]['id_grupo_vulnerable_catalogo'], 1);

      print('✅ 1 grupo con datos → enviado OK, otros 7 filtrados');
    });

    test('Protección con apoyo psicológico=true y zeros → tieneDatos=true', () {
      final loc = _buildLocalidad({
        'poblacion': false, 'salud': false, 'infraestructura': false,
        'servicios': false, 'educacion': false, 'vivienda': false,
        'agropecuario': false, 'proteccion': true, 'necesidades': false,
      });

      for (final g in loc.proteccion) {
        g.mujeres = 0;
        g.hombres = 0;
        g.apoyoPsicologico = null;
        g.reposicionDocumentos = null;
        g.observaciones = '';
      }

      loc.proteccion[2].apoyoPsicologico = true;
      loc.proteccion[3].reposicionDocumentos = true;
      loc.proteccion[4].observaciones = 'Necesitan apoyo';

      final proteccion = loc.proteccionParaEndpointDedicado();

      print('\n=== Protección: apoyo reposición/obs ===');
      print('proteccion enviada: ${proteccion.length} items');

      expect(proteccion.length, 3, reason: '3 grupos con tieneDatos por apoyo/repos/obs');

      final ids = proteccion.map((e) => e['id_grupo_vulnerable_catalogo']).toList();
      expect(ids, containsAll([3, 4, 5]));
      print('✅ Grupos por apoyo reposición y observaciones detectados');
    });

    test('Payload completo de 1 localidad con TODAS las secciones activas', () {
      final imp = {
        'poblacion': true, 'salud': true, 'infraestructura': true,
        'servicios': true, 'educacion': true, 'vivienda': true,
        'agropecuario': true, 'proteccion': true, 'necesidades': true,
      };
      final loc = _buildLocalidad(imp);
      final json = loc.toApiJson();
      json['id_usuario'] = 43;

      final payload = {'localidades': [json]};

      print('\n=== ESCENARIO COMPLETO: TODAS las secciones ===');
      print('impacto_poblacion: ${(json['impacto_poblacion'] as List).length}');
      print('establecimientos_salud: ${(json['establecimientos_salud'] as List).length}');
      print('danos_viales: ${(json['danos_viales'] as List).length}');
      print('danos_infra_publica: ${(json['danos_infra_publica'] as List).length}');
      print('servicios_basicos: ${(json['servicios_basicos'] as List).length}');
      print('unidades_educativas: ${(json['unidades_educativas'] as List).length}');
      print('danos_vivienda: ${(json['danos_vivienda'] as List).length}');
      print('danos_agricultura: ${(json['danos_agricultura'] as List).length}');
      print('danos_pecuarios: ${(json['danos_pecuarios'] as List).length}');
      print('infra_productiva: ${(json['infra_productiva'] as List).length}');
      print('proteccion (dedicado): ${loc.proteccionParaEndpointDedicado().length}');

      expect(json['imp_poblacion'], true);
      expect(json['imp_salud'], true);
      expect(json['imp_infraestructura'], true);
      expect(json['imp_servicios'], true);
      expect(json['imp_educacion'], true);
      expect(json['imp_vivienda'], true);
      expect(json['imp_agropecuario'], true);
      expect(json['imp_proteccion'], true);
      expect(json['imp_necesidades'], true);

      expect((json['impacto_poblacion'] as List).length, 4);
      expect((json['establecimientos_salud'] as List).length, 2);
      expect((json['danos_viales'] as List).length, 2);
      expect((json['danos_infra_publica'] as List).length, 2);
      expect((json['servicios_basicos'] as List).length, 5);
      expect((json['unidades_educativas'] as List).length, 2);
      expect((json['danos_vivienda'] as List).length, 2);
      expect((json['danos_agricultura'] as List).length, 2);
      expect((json['danos_pecuarios'] as List).length, 2);
      expect((json['infra_productiva'] as List).length, 2);
      expect(loc.proteccionParaEndpointDedicado().length, 2);

      expect(json['necesidad_primera_respuesta'], isNotNull);
      expect(json['necesidad_humanitaria'], isNotNull);

      final pretty = JsonEncoder.withIndent('  ').convert(payload);
      print('\nPayload JSON ($pretty chars):');
      print(pretty.length > 2000 ? '${pretty.substring(0, 2000)}...' : pretty);
      print('\n✅ PAYLOAD COMPLETO VALIDADO');
    });

    test('5 iteraciones random con secciones combinadas', () {
      print('\n=== 5 ESCENARIOS RANDOM ===');

      for (var i = 0; i < 5; i++) {
        final imp = _randomImpacts(Random(i));
        final loc = _buildLocalidad(imp, idLocal: 'random-$i');
        final json = loc.toApiJson();

        print('\n--- Escenario ${i + 1} ---');
        print('  Impacts: ${imp.entries.where((e) => e.value).map((e) => e.key).join(", ")}');

        final impacto = json['impacto_poblacion'] as List;
        final est = json['establecimientos_salud'] as List;
        final vias = json['danos_viales'] as List;
        final diip = json['danos_infra_publica'] as List;
        final sb = json['servicios_basicos'] as List;
        final ue = json['unidades_educativas'] as List;
        final vv = json['danos_vivienda'] as List;
        final da = json['danos_agricultura'] as List;
        final dp = json['danos_pecuarios'] as List;
        final ip = json['infra_productiva'] as List;
        final prot = loc.proteccionParaEndpointDedicado();

        print('  impacto_poblacion: ${impacto.length} | establecimientos: ${est.length} '
            '| vías: ${vias.length} | infra: ${diip.length} '
            '| servicios: ${sb.length} | educación: ${ue.length} '
            '| vivienda: ${vv.length} | agri: ${da.length} '
            '| pecuario: ${dp.length} | infra_prod: ${ip.length} '
            '| protección: ${prot.length}');

        expect(impacto.length, imp['poblacion']! ? 4 : 0);
        expect(est.length, imp['salud']! ? 2 : 0);
        expect(vias.length, imp['infraestructura']! ? 2 : 0);
        expect(diip.length, imp['infraestructura']! ? 2 : 0);
        expect(sb.length, imp['servicios']! ? 5 : 0);
        expect(ue.length, imp['educacion']! ? 2 : 0);
        expect(vv.length, imp['vivienda']! ? 2 : 0);
        expect(da.length, imp['agropecuario']! ? 2 : 0);
        expect(dp.length, imp['agropecuario']! ? 2 : 0);
        expect(ip.length, imp['agropecuario']! ? 2 : 0);
        expect(prot.length, 2, reason: 'Protección siempre activa, 2 con datos');

        final idsImpacto = impacto.map((e) => e['id_seccion'] as String).toList();
        expect(idsImpacto.toSet().length, idsImpacto.length,
            reason: 'Escenario ${i + 1}: IDs de impacto duplicados');
      }

      print('\n✅ Todos los escenarios random validados');
    });
  });
}
