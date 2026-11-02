import 'package:flutter_test/flutter_test.dart';
import 'package:rea/models/edan.dart';
import 'package:rea/models/id_seccion_helper.dart';

void main() {
  // ─────────────────────────────────────────────────────
  // PROTECCIÓN
  // ─────────────────────────────────────────────────────
  group('PROTECCIÓN: EdanGrupoVulnerable.tieneDatos', () {
    test('vacío → false', () {
      expect(EdanGrupoVulnerable().tieneDatos, isFalse);
    });

    test('solo mujeres > 0 → true', () {
      expect(EdanGrupoVulnerable(mujeres: 1).tieneDatos, isTrue);
    });

    test('solo hombres > 0 → true', () {
      expect(EdanGrupoVulnerable(hombres: 1).tieneDatos, isTrue);
    });

    test('solo apoyoPsicologico = true → true', () {
      expect(EdanGrupoVulnerable(apoyoPsicologico: true).tieneDatos, isTrue);
    });

    test('solo reposicionDocumentos = true → true', () {
      expect(EdanGrupoVulnerable(reposicionDocumentos: true).tieneDatos, isTrue);
    });

    test('solo observaciones no vacía → true', () {
      expect(EdanGrupoVulnerable(observaciones: 'necesita ayuda').tieneDatos, isTrue);
    });

    test('mujeres=0, hombres=0, apoyo=false, repos=false, obs="" → false', () {
      expect(
        EdanGrupoVulnerable(
          mujeres: 0,
          hombres: 0,
          apoyoPsicologico: false,
          reposicionDocumentos: false,
          observaciones: '',
        ).tieneDatos,
        isFalse,
      );
    });

    test('mujeres=0, hombres=0, apoyo=null, repos=null, obs="" → false', () {
      expect(EdanGrupoVulnerable().tieneDatos, isFalse);
    });

    test('apoyoPsicologico=false NO cuenta (es false, no null)', () {
      expect(EdanGrupoVulnerable(apoyoPsicologico: false).tieneDatos, isFalse);
    });

    test('mujeres=0 + observaciones="x" → true', () {
      expect(
        EdanGrupoVulnerable(mujeres: 0, observaciones: 'detalles').tieneDatos,
        isTrue,
      );
    });

    test('hombres=5 + apoyo=false → true (por hombres)', () {
      expect(
        EdanGrupoVulnerable(hombres: 5, apoyoPsicologico: false).tieneDatos,
        isTrue,
      );
    });
  });

  group('PROTECCIÓN: toApiJson()', () {
    test('incluye id_seccion e id_grupo_vulnerable_catalogo', () {
      final g = EdanGrupoVulnerable(
        idSeccion: 'po_123_abc',
        idGrupoVulnerableCatalogo: 3,
        mujeres: 2,
        hombres: 1,
      );
      final json = g.toApiJson(null);
      expect(json['id_seccion'], 'po_123_abc');
      expect(json['id_grupo_vulnerable_catalogo'], 3);
      expect(json['mujeres'], 2);
      expect(json['hombres'], 1);
    });

    test('con grupoCatalogo lo incluye', () {
      final g = EdanGrupoVulnerable(
        idGrupoVulnerableCatalogo: 5,
        mujeres: 10,
      );
      final catalogo = {'id': 5, 'codigo': 'adultos_mayores', 'nombre': 'Adultos mayores'};
      final json = g.toApiJson(catalogo);
      expect(json['grupo'], catalogo);
    });

    test('sin grupoCatalogo NO incluye "grupo"', () {
      final g = EdanGrupoVulnerable(mujeres: 3);
      final json = g.toApiJson(null);
      expect(json.containsKey('grupo'), isFalse);
    });

    test('apoyoPsicologico y reposicionDocumentos se serializan', () {
      final g = EdanGrupoVulnerable(
        apoyoPsicologico: true,
        reposicionDocumentos: true,
        observaciones: 'test',
      );
      final json = g.toApiJson(null);
      expect(json['apoyo_psicologico'], isTrue);
      expect(json['reposicion_documentos'], isTrue);
      expect(json['observaciones'], 'test');
    });

    test('campos null se mantienen null en JSON', () {
      final g = EdanGrupoVulnerable(mujeres: 1);
      final json = g.toApiJson(null);
      expect(json['apoyo_psicologico'], isNull);
      expect(json['reposicion_documentos'], isNull);
    });

    test('NO incluye fotografia', () {
      final g = EdanGrupoVulnerable(mujeres: 5);
      expect(g.toApiJson(null).containsKey('fotografia'), isFalse);
    });
  });

  group('PROTECCIÓN: _proteccionApi() - filtrado por tieneDatos', () {
    test('8 grupos default: solo los vacíos se filtran', () {
      final loc = EdanLocalidad(
        idLocal: 'test-8',
        nombre: 'Loc',
        grupProteccion: true,
      );
      final json = loc.toApiJson();
      final prot = json['proteccion'] as List;
      expect(prot.length, equals(0),
          reason: 'Default 8 grupos vacíos → 0 enviados');
    });

    test('8 grupos: solo el 1ro con datos → solo 1 enviado', () {
      final grupos = List<EdanGrupoVulnerable>.generate(8, (i) =>
          EdanGrupoVulnerable(idSeccion: generarIdSeccion('po')));
      grupos[0].mujeres = 5;
      grupos[0].hombres = 3;

      final loc = EdanLocalidad(
        idLocal: 'test-1of8',
        nombre: 'Loc',
        grupProteccion: true,
        proteccion: grupos,
      );
      final prot = loc.proteccionParaEndpointDedicado();
      expect(prot.length, 1);
      expect(prot[0]['mujeres'], 5);
      expect(prot[0]['hombres'], 3);
      expect(prot[0]['id_grupo_vulnerable_catalogo'], isNull,
          reason: 'Sin catálogo, id_grupo_vulnerable_catalogo no se envía');
    });

    test('8 grupos: 3 con datos + 5 vacíos → solo 3 enviados', () {
      final grupos = List<EdanGrupoVulnerable>.generate(8, (i) =>
          EdanGrupoVulnerable(idSeccion: generarIdSeccion('po')));
      grupos[0].mujeres = 10;
      grupos[2].apoyoPsicologico = true;
      grupos[5].observaciones = 'necesita atención';

      final loc = EdanLocalidad(
        idLocal: 'test-3of8',
        nombre: 'Loc',
        grupProteccion: true,
        proteccion: grupos,
      );
      final prot = loc.proteccionParaEndpointDedicado();
      expect(prot.length, 3);

      final catalogIds = prot.map((e) => e['id_grupo_vulnerable_catalogo']).toList();
      expect(catalogIds, containsAll([null, null, null]),
          reason: 'Los 3 items no tienen catálogo asignado');
    });

    test('8 grupos con catálogo: todos los id_grupo_vulnerable_catalogo presentes', () {
      final grupos = List<EdanGrupoVulnerable>.generate(8, (i) =>
          EdanGrupoVulnerable(
            idSeccion: generarIdSeccion('po'),
            idGrupoVulnerableCatalogo: i + 1,
            mujeres: i + 1,
          ));

      final loc = EdanLocalidad(
        idLocal: 'test-catalog',
        nombre: 'Loc',
        grupProteccion: true,
        proteccion: grupos,
      );
      final prot = loc.proteccionParaEndpointDedicado();
      expect(prot.length, 8);

      for (var i = 0; i < 8; i++) {
        expect(prot[i]['id_grupo_vulnerable_catalogo'], i + 1);
        expect(prot[i]['id_seccion'], isNotNull);
      }
    });

    test('id_seccion preservado por grupo tras filtrado', () {
      final id0 = generarIdSeccion('po');
      final id1 = generarIdSeccion('po');
      final id2 = generarIdSeccion('po');

      final grupos = [
        EdanGrupoVulnerable(idSeccion: id0, mujeres: 1),
        EdanGrupoVulnerable(idSeccion: id1, hombres: 2),
        EdanGrupoVulnerable(idSeccion: id2, observaciones: 'test'),
        EdanGrupoVulnerable(idSeccion: generarIdSeccion('po')),
      ];

      final loc = EdanLocalidad(
        idLocal: 'test-ids',
        nombre: 'Loc',
        grupProteccion: true,
        proteccion: grupos,
      );
      final prot = loc.proteccionParaEndpointDedicado();
      expect(prot.length, 3);

      final sentIds = prot.map((e) => e['id_seccion']).toList();
      expect(sentIds, containsAll([id0, id1, id2]));
    });
  });

  group('PROTECCIÓN: roundtrip fromJson→toJson', () {
    test('preserva id_seccion, catálogo y datos', () {
      const id = 'f9f9f9f9-f9f9-4f9f-8f9f-f9f9f9f9f9f9';
      final original = EdanGrupoVulnerable(
        idSeccion: id,
        idGrupoVulnerableCatalogo: 7,
        mujeres: 12,
        hombres: 8,
        apoyoPsicologico: true,
        reposicionDocumentos: false,
        observaciones: 'Requieren vivienda',
      );
      final json = original.toJson();
      final restored = EdanGrupoVulnerable.fromJson(json);

      expect(restored.idSeccion, id);
      expect(restored.idGrupoVulnerableCatalogo, 7);
      expect(restored.mujeres, 12);
      expect(restored.hombres, 8);
      expect(restored.apoyoPsicologico, isTrue);
      expect(restored.reposicionDocumentos, isFalse);
      expect(restored.observaciones, 'Requieren vivienda');
    });

    test('preserva id_seccion y catálogo en toApiJson→fromJson', () {
      const id = 'e8e8e8e8-e8e8-4e8e-8e8e-e8e8e8e8e8e8';
      final original = EdanGrupoVulnerable(
        idSeccion: id,
        idGrupoVulnerableCatalogo: 4,
        mujeres: 3,
      );
      final apiJson = original.toApiJson({'id': 4, 'nombre': 'Mujeres embarazadas'});
      expect(apiJson['id_seccion'], id);

      final restored = EdanGrupoVulnerable.fromJson(apiJson);
      expect(restored.idSeccion, id);
      expect(restored.idGrupoVulnerableCatalogo, 4);
      expect(restored.mujeres, 3);
    });
  });

  group('PROTECCIÓN: incompletosPorSeccion', () {
    test('grupProteccion=true + 8 vacíos → sección 10 incompleta', () {
      final edan = Edan(
        idDepartamento: 7,
        idProvincia: 701,
        idMunicipio: 70101,
        localidades: [
          EdanLocalidad(
            idLocal: 'loc-prot',
            nombre: 'Barrio',
            grupProteccion: true,
          ),
        ],
        responsable: EdanResponsable(nombre: 'Test', cargo: 'Test'),
      );
      final inc = edan.incompletosPorSeccion(exigirAlcalde: false);
      expect(inc.containsKey('10'), isTrue);
    });

    test('grupProteccion=true + 1 grupo con datos → sección 10 completa', () {
      final grupos = List<EdanGrupoVulnerable>.generate(8, (i) =>
          EdanGrupoVulnerable(idSeccion: generarIdSeccion('po')));
      grupos[0].mujeres = 5;

      final edan = Edan(
        idDepartamento: 7,
        idProvincia: 701,
        idMunicipio: 70101,
        localidades: [
          EdanLocalidad(
            idLocal: 'loc-prot-ok',
            nombre: 'Barrio',
            grupProteccion: true,
            proteccion: grupos,
          ),
        ],
        responsable: EdanResponsable(nombre: 'Test', cargo: 'Test'),
      );
      final inc = edan.incompletosPorSeccion(exigirAlcalde: false);
      expect(inc.containsKey('10'), isFalse);
    });

    test('grupProteccion=false → sección 10 no evaluada', () {
      final edan = Edan(
        idDepartamento: 7,
        idProvincia: 701,
        idMunicipio: 70101,
        localidades: [
          EdanLocalidad(
            idLocal: 'loc-no-prot',
            nombre: 'Barrio',
            grupProteccion: false,
          ),
        ],
        responsable: EdanResponsable(nombre: 'Test', cargo: 'Test'),
      );
      final inc = edan.incompletosPorSeccion(exigirAlcalde: false);
      expect(inc.containsKey('10'), isFalse);
    });
  });

  // ─────────────────────────────────────────────────────
  // SERVICIOS BÁSICOS
  // ─────────────────────────────────────────────────────
  group('SERVICIOS BÁSICOS: tieneDatos', () {
    test('tipo vacío + todo default → false', () {
      expect(EdanServicioBasicoDetalle(tipo: '').tieneDatos, isFalse);
    });

    test('solo tipo NO cuenta como datos', () {
      expect(EdanServicioBasicoDetalle(tipo: 'energia_electrica').tieneDatos, isFalse);
    });

    test('afectado=true → tiene datos (even without danoParcial/danoTotal)', () {
      expect(
        EdanServicioBasicoDetalle(tipo: 'energia_electrica', afectado: true).tieneDatos,
        isTrue,
      );
    });

    test('danoParcial=true → tiene datos', () {
      expect(
        EdanServicioBasicoDetalle(tipo: 'agua_potable', danoParcial: true).tieneDatos,
        isTrue,
      );
    });

    test('danoTotal=true → tiene datos', () {
      expect(
        EdanServicioBasicoDetalle(tipo: 'alcantarillado', danoTotal: true).tieneDatos,
        isTrue,
      );
    });

    test('necesidadesInmediatas no vacía → tiene datos', () {
      expect(
        EdanServicioBasicoDetalle(
          tipo: 'gas_domiciliario',
          necesidadesInmediatas: 'cable cortado',
        ).tieneDatos,
        isTrue,
      );
    });

    test('observaciones no vacía → tiene datos', () {
      expect(
        EdanServicioBasicoDetalle(
          tipo: 'telecomunicaciones',
          observaciones: 'zona afectada',
        ).tieneDatos,
        isTrue,
      );
    });

    test('fotos.isNotEmpty → tiene datos', () {
      expect(
        EdanServicioBasicoDetalle(
          tipo: 'energia_electrica',
          fotos: [EdanFoto(ruta: '/test.jpg')],
        ).tieneDatos,
        isTrue,
      );
    });

    test('coordenadaLat != 0 → tiene datos', () {
      expect(
        EdanServicioBasicoDetalle(
          tipo: 'agua_potable',
          coordenadaLat: -16.5,
        ).tieneDatos,
        isTrue,
      );
    });

    test('coordenadaLon != 0 → tiene datos', () {
      expect(
        EdanServicioBasicoDetalle(
          tipo: 'energia_electrica',
          coordenadaLon: -68.1,
        ).tieneDatos,
        isTrue,
      );
    });

    test('afectado=false + danoParcial=false + danoTotal=false + obs="" → false', () {
      expect(
        EdanServicioBasicoDetalle(
          tipo: 'energia_electrica',
          afectado: false,
          danoParcial: false,
          danoTotal: false,
          observaciones: '',
        ).tieneDatos,
        isFalse,
      );
    });
  });

  group('SERVICIOS BÁSICOS: toApiJson()', () {
    test('incluye todos los campos requeridos', () {
      final item = EdanServicioBasicoDetalle(
        idSeccion: 'sb_001_test',
        tipo: 'energia_electrica',
        afectado: true,
        danoParcial: true,
        danoTotal: false,
        necesidadesInmediatas: 'postes caídos',
        observaciones: 'zona norte',
        coordenadaLat: -16.5045,
        coordenadaLon: -68.1532,
      );
      final json = item.toApiJson();

      expect(json['id_seccion'], 'sb_001_test');
      expect(json['tipo'], 'energia_electrica');
      expect(json['afectado'], true,
          reason: 'el check se persiste en datos_json; '
              '`prepararPayloadCompleto` lo remueve del wire (400 si viaja)');
      expect(json['dano_parcial'], true);
      expect(json['dano_total'], false);
      expect(json['necesidades_inmediatas'], 'postes caídos');
      expect(json['observaciones'], 'zona norte');
      expect(json['coordenada_lat'], closeTo(-16.5045, 0.0001));
      expect(json['coordenada_lon'], closeTo(-68.1532, 0.0001));
    });

    test('SÍ incluye fotografia (backend la espera)', () {
      final item = EdanServicioBasicoDetalle(
        tipo: 'agua_potable',
        danoParcial: true,
      );
      expect(item.toApiJson().containsKey('fotografia'), isTrue);
    });

    test('NO incluye fotos array', () {
      final item = EdanServicioBasicoDetalle(
        tipo: 'alcantarillado',
        danoParcial: true,
        fotos: [EdanFoto(ruta: '/test.jpg')],
      );
      expect(item.toApiJson().containsKey('fotos'), isFalse);
    });

    test('sin idSeccion → incluye id_seccion (null) + fecha_modificacion', () {
      final item = EdanServicioBasicoDetalle(tipo: 'gas_domiciliario', danoParcial: true);
      expect(item.toApiJson().containsKey('id_seccion'), isTrue);
      expect(item.toApiJson().containsKey('fecha_modificacion'), isTrue);
    });
  });

  group('SERVICIOS BÁSICOS: toFotoData()', () {
    test('override coordenadas con las de la foto', () {
      final item = EdanServicioBasicoDetalle(
        idSeccion: 'sb_photo_1',
        tipo: 'energia_electrica',
        coordenadaLat: -16.0,
        coordenadaLon: -68.0,
      );
      final foto = EdanFoto(latitud: -17.5, longitud: -69.2);
      final data = item.toFotoData(foto);

      expect(data['coordenada_lat'], -17.5);
      expect(data['coordenada_lon'], -69.2);
      expect(data['id_seccion'], 'sb_photo_1');
      expect(data['tipo'], 'energia_electrica');
    });

    test('preserva otros campos del toApiJson()', () {
      final item = EdanServicioBasicoDetalle(
        idSeccion: 'sb_photo_2',
        tipo: 'agua_potable',
        afectado: true,
        danoParcial: true,
      );
      final foto = EdanFoto(latitud: 0.0, longitud: 0.0);
      final data = item.toFotoData(foto);

      expect(data['afectado'], isTrue,
          reason: 'toFotoData hereda toApiJson; el motor quita el check '
              'local al armar el POST real');
      expect(data['dano_parcial'], true);
      expect(data['dano_total'], false);
    });
  });

  group('SERVICIOS BÁSICOS: roundtrip fromJson→toJson', () {
    test('preserva todos los campos', () {
      const id = 'a9a9a9a9-a9a9-4a9a-8a9a-a9a9a9a9a9a9';
      final original = EdanServicioBasicoDetalle(
        idSeccion: id,
        tipo: 'telecomunicaciones',
        afectado: true,
        danoParcial: false,
        danoTotal: true,
        necesidadesInmediatas: 'tower down',
        observaciones: 'full outage',
        coordenadaLat: -16.5045,
        coordenadaLon: -68.1532,
      );
      final json = original.toJson();
      final restored = EdanServicioBasicoDetalle.fromJson(json);

      expect(restored.idSeccion, id);
      expect(restored.tipo, 'telecomunicaciones');
      expect(restored.afectado, isTrue);
      expect(restored.danoParcial, isFalse);
      expect(restored.danoTotal, isTrue);
      expect(restored.necesidadesInmediatas, 'tower down');
      expect(restored.observaciones, 'full outage');
      expect(restored.coordenadaLat, closeTo(-16.5045, 0.0001));
      expect(restored.coordenadaLon, closeTo(-68.1532, 0.0001));
    });

    test('fromJson con claves camelCase también funciona', () {
      final json = {
        'id_seccion': 'sb_camel',
        'tipo': 'energia_electrica',
        'afectado': true,
        'danoParcial': true,
        'danoTotal': false,
        'necesidadesInmediatas': 'caído',
        'observaciones': '',
        'coordenadaLat': -16.5,
        'coordenadaLon': -68.1,
      };
      final item = EdanServicioBasicoDetalle.fromJson(json);
      expect(item.danoParcial, isTrue);
      expect(item.necesidadesInmediatas, 'caído');
      expect(item.coordenadaLat, -16.5);
    });
  });

  group('SERVICIOS BÁSICOS: los 5 tipos estándar', () {
    const tipos = [
      'energia_electrica',
      'agua_potable',
      'alcantarillado',
      'gas_domiciliario',
      'telecomunicaciones',
    ];

    for (final tipo in tipos) {
      test('$tipo con danoParcial → tieneDatos', () {
        final item = EdanServicioBasicoDetalle(tipo: tipo, danoParcial: true);
        expect(item.tieneDatos, isTrue);
        expect(item.toApiJson()['tipo'], tipo);
      });

      test('$tipo vacío → NO tieneDatos', () {
        final item = EdanServicioBasicoDetalle(tipo: tipo);
        expect(item.tieneDatos, isFalse);
      });
    }
  });

  group('SERVICIOS BÁSICOS: incompletosPorSeccion', () {
    test('grupServicios=true + todos vacíos → sección 06 incompleta', () {
      final edan = Edan(
        idDepartamento: 7,
        idProvincia: 701,
        idMunicipio: 70101,
        localidades: [
          EdanLocalidad(
            idLocal: 'loc-sb',
            nombre: 'Barrio',
            grupServicios: true,
            serviciosBasicos: [
              EdanServicioBasicoDetalle(tipo: 'energia_electrica'),
              EdanServicioBasicoDetalle(tipo: 'agua_potable'),
            ],
          ),
        ],
        responsable: EdanResponsable(nombre: 'Test', cargo: 'Test'),
      );
      final inc = edan.incompletosPorSeccion(exigirAlcalde: false);
      expect(inc.containsKey('06'), isTrue);
    });

    test('grupServicios=true + 1 con danoParcial → sección 06 completa', () {
      final edan = Edan(
        idDepartamento: 7,
        idProvincia: 701,
        idMunicipio: 70101,
        localidades: [
          EdanLocalidad(
            idLocal: 'loc-sb-ok',
            nombre: 'Barrio',
            grupServicios: true,
            serviciosBasicos: [
              EdanServicioBasicoDetalle(tipo: 'energia_electrica'),
              EdanServicioBasicoDetalle(tipo: 'agua_potable', danoParcial: true),
            ],
          ),
        ],
        responsable: EdanResponsable(nombre: 'Test', cargo: 'Test'),
      );
      final inc = edan.incompletosPorSeccion(exigirAlcalde: false);
      expect(inc.containsKey('06'), isFalse);
    });

    test('grupServicios=false → sección 06 no evaluada', () {
      final edan = Edan(
        idDepartamento: 7,
        idProvincia: 701,
        idMunicipio: 70101,
        localidades: [
          EdanLocalidad(
            idLocal: 'loc-no-sb',
            nombre: 'Barrio',
            grupServicios: false,
          ),
        ],
        responsable: EdanResponsable(nombre: 'Test', cargo: 'Test'),
      );
      final inc = edan.incompletosPorSeccion(exigirAlcalde: false);
      expect(inc.containsKey('06'), isFalse);
    });
  });

  // ─────────────────────────────────────────────────────
  // COMBINACIONES: secciones completas con 1 grupo/dato
  // ─────────────────────────────────────────────────────
  group('COMBINACIÓN: sección con 1 solo grupo con datos + resto vacíos', () {
    test('protección: 1 de 8 con datos + 7 vacíos → solo 1 enviado', () {
      final grupos = List<EdanGrupoVulnerable>.generate(8, (i) =>
          EdanGrupoVulnerable(
            idSeccion: generarIdSeccion('po'),
            idGrupoVulnerableCatalogo: i + 1,
          ));
      grupos[3].mujeres = 10;
      grupos[3].hombres = 5;

      final loc = EdanLocalidad(
        idLocal: 'combo-1',
        nombre: 'Loc',
        grupProteccion: true,
        proteccion: grupos,
      );
      final prot = loc.proteccionParaEndpointDedicado();
      expect(prot.length, 1);
      expect(prot[0]['id_grupo_vulnerable_catalogo'], 4,
          reason: 'Solo el grupo 4 (índice 3) tiene datos');
    });

    test('servicios_basicos: 1 de 5 con dano + 4 vacíos → todos en JSON (servicios no filtra)', () {
      final loc = EdanLocalidad(
        idLocal: 'combo-sb',
        nombre: 'Loc',
        grupServicios: true,
        serviciosBasicos: [
          EdanServicioBasicoDetalle(tipo: 'energia_electrica', danoParcial: true),
          EdanServicioBasicoDetalle(tipo: 'agua_potable'),
          EdanServicioBasicoDetalle(tipo: 'alcantarillado'),
          EdanServicioBasicoDetalle(tipo: 'gas_domiciliario'),
          EdanServicioBasicoDetalle(tipo: 'telecomunicaciones'),
        ],
      );
      final json = loc.toApiJson();
      final sb = json['servicios_basicos'] as List;
      expect(sb.length, 5,
          reason: 'servicios_basicos se envía todo (no filtra por tieneDatos)');
      expect(sb[0]['dano_parcial'], isTrue);
      expect(sb[1]['dano_parcial'], isFalse);
    });

    test('impacto_poblacion: 1 de 4 rangos con datos → solo ese enviado', () {
      final loc = EdanLocalidad(
        idLocal: 'combo-imp',
        nombre: 'Loc',
        grupPoblacion: true,
        impactoPoblacion: [
          EdanImpactoPoblacion(
            idSeccion: generarIdSeccion('im'),
            grupoEtario: 'Niño 0-5',
            fallecidos: 0,
            heridos: 0,
          ),
          EdanImpactoPoblacion(
            idSeccion: generarIdSeccion('im'),
            grupoEtario: 'Escolar 6-18',
            fallecidos: 1,
            heridos: 2,
          ),
          EdanImpactoPoblacion(
            idSeccion: generarIdSeccion('im'),
            grupoEtario: 'Adulto 19-60',
            fallecidos: 0,
            heridos: 0,
          ),
          EdanImpactoPoblacion(
            idSeccion: generarIdSeccion('im'),
            grupoEtario: 'Adulto mayor 60+',
            fallecidos: 0,
            heridos: 0,
          ),
        ],
      );
      final imp = (loc.toApiJson()['impacto_poblacion'] as List);
      expect(imp.length, 1);
      expect(imp[0]['rango'], 'Escolar 6-18');
      expect(imp[0]['fallecidos'], 1);
    });
  });

  group('COMBINACIÓN: localidad completa con TODAS las secciones', () {
    test('payload completo con todos los imp_* + proteccion + servicios', () {
      final protGrupos = List<EdanGrupoVulnerable>.generate(8, (i) =>
          EdanGrupoVulnerable(
            idSeccion: generarIdSeccion('po'),
            idGrupoVulnerableCatalogo: i + 1,
          ));
      protGrupos[0].mujeres = 5;
      protGrupos[0].hombres = 3;
      protGrupos[5].apoyoPsicologico = true;

      final loc = EdanLocalidad(
        idLocal: 'full-loc',
        nombre: 'Barrio Completo',
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
          ),
        ],
        establecimientosSalud: [
          EdanEstablecimientoSalud(
            idSeccion: generarIdSeccion('sv'),
            nombreEstablecimiento: 'Hospital',
          ),
        ],
        serviciosBasicos: [
          EdanServicioBasicoDetalle(
            idSeccion: generarIdSeccion('sb'),
            tipo: 'energia_electrica',
            danoParcial: true,
          ),
          EdanServicioBasicoDetalle(
            idSeccion: generarIdSeccion('sb'),
            tipo: 'agua_potable',
          ),
        ],
        proteccion: protGrupos,
      );

      loc.recalcularFlagsImpacto();  // como hace el guardado real
      final json = loc.toApiJson();

      expect(json['grup_poblacion'], true);
      expect(json['grup_salud'], true);
      expect(json['imp_proteccion'], true);

      expect((json['impacto_poblacion'] as List).length, 1);
      expect((json['establecimientos_salud'] as List).length, 1);
      expect((json['servicios_basicos'] as List).length, 2);
      expect(loc.proteccionParaEndpointDedicado().length, 2,
          reason: 'Solo 2 de 8 grupos con datos');
    });
  });

  group('COMBINACIÓN: localidad con grupProteccion=true pero 0 grupos', () {
    test('proteccion vacía (lista vacía) → 0 items en API', () {
      final loc = EdanLocalidad(
        idLocal: 'empty-prot',
        nombre: 'Loc',
        grupProteccion: true,
        proteccion: [],
      );
      final prot = (loc.toApiJson()['proteccion'] as List);
      expect(prot.length, 0);
    });

    test('incompletosPorSeccion → sección 10 marcada', () {
      final edan = Edan(
        idDepartamento: 7,
        idProvincia: 701,
        idMunicipio: 70101,
        localidades: [
          EdanLocalidad(
            idLocal: 'inc-empty',
            nombre: 'Barrio',
            grupProteccion: true,
            proteccion: [],
          ),
        ],
        responsable: EdanResponsable(nombre: 'R', cargo: 'C'),
      );
      final inc = edan.incompletosPorSeccion(exigirAlcalde: false);
      expect(inc.containsKey('10'), isTrue);
    });
  });

  group('COMBINACIÓN: varias localidades con proteccion mixta', () {
    test('loc1: proteccion con datos, loc2: vacía → proteccion filtrada independiente', () {
      final prot1 = List<EdanGrupoVulnerable>.generate(8, (i) =>
          EdanGrupoVulnerable(idSeccion: generarIdSeccion('po')));
      prot1[0].mujeres = 5;

      final edan = Edan(
        idDepartamento: 7,
        idProvincia: 701,
        idMunicipio: 70101,
        localidades: [
          EdanLocalidad(
            idLocal: 'ml-1',
            nombre: 'Con datos',
            grupProteccion: true,
            proteccion: prot1,
          ),
          EdanLocalidad(
            idLocal: 'ml-2',
            nombre: 'Sin datos',
            grupProteccion: true,
          ),
        ],
        responsable: EdanResponsable(nombre: 'R', cargo: 'C'),
      );
      final protA = edan.localidades[0].proteccionParaEndpointDedicado();
      final protB = edan.localidades[1].proteccionParaEndpointDedicado();

      expect(protA.length, 1,
          reason: 'Loc1 tiene 1 grupo con datos');
      expect(protB.length, 0,
          reason: 'Loc2 tiene 0 grupos con datos');
    });
  });

  group('COMBINACIÓN: deduplicarSecciones preserva proteccion', () {
    test('8 grupos con IDs únicos → deduplicar no elimina ninguno', () {
      final grupos = List<EdanGrupoVulnerable>.generate(8, (i) =>
          EdanGrupoVulnerable(
            idSeccion: generarIdSeccion('po'),
            mujeres: i + 1,
          ));
      final loc = EdanLocalidad(
        idLocal: 'dedup-prot',
        nombre: 'Loc',
        proteccion: grupos,
      );
      expect(loc.proteccion.length, 8);
      loc.deduplicarSecciones();
      expect(loc.proteccion.length, 8);
    });

    test('2 grupos con mismo idSeccion → deduplicar deja 1', () {
      final sameId = 'po_dupe_test';
      final loc = EdanLocalidad(
        idLocal: 'dedup-same',
        nombre: 'Loc',
        proteccion: [
          EdanGrupoVulnerable(idSeccion: sameId, mujeres: 5),
          EdanGrupoVulnerable(idSeccion: sameId, hombres: 3),
        ],
      );
      loc.deduplicarSecciones();
      expect(loc.proteccion.length, 1,
          reason: '2 items con mismo idSeccion → 1 sobrevive');
    });
  });

  group('COMBINACIÓN: stress random proteccion + servicios', () {
    test('20 escenarios: 8 grupos proteccion random + 5 servicios random', () {
      final rng = DateTime.now().millisecondsSinceEpoch;

      for (var t = 0; t < 20; t++) {
        final protGrupos = List<EdanGrupoVulnerable>.generate(8, (i) {
          final g = EdanGrupoVulnerable(
            idSeccion: generarIdSeccion('po'),
            idGrupoVulnerableCatalogo: i + 1,
          );
          if ((rng + t * 7 + i * 13) % 3 == 0) g.mujeres = (rng + t + i) % 20;
          if ((rng + t * 11 + i * 3) % 5 == 0) g.hombres = (rng + t + i) % 15;
          if ((rng + t * 17 + i * 7) % 7 == 0) g.apoyoPsicologico = true;
          return g;
        });

        final servicios = [
          EdanServicioBasicoDetalle(
            tipo: 'energia_electrica',
            danoParcial: (rng + t) % 4 == 0,
            afectado: (rng + t) % 6 == 0,
          ),
          EdanServicioBasicoDetalle(
            tipo: 'agua_potable',
            danoTotal: (rng + t) % 5 == 0,
          ),
          EdanServicioBasicoDetalle(
            tipo: 'alcantarillado',
            observaciones: (rng + t) % 8 == 0 ? 'test' : '',
          ),
          EdanServicioBasicoDetalle(tipo: 'gas_domiciliario'),
          EdanServicioBasicoDetalle(tipo: 'telecomunicaciones'),
        ];

        final loc = EdanLocalidad(
          idLocal: 'stress-$t',
          nombre: 'Loc$t',
          grupProteccion: true,
          grupServicios: true,
          proteccion: protGrupos,
          serviciosBasicos: servicios,
        );

        final json = loc.toApiJson();
        final prot = loc.proteccionParaEndpointDedicado();
        final sb = json['servicios_basicos'] as List;

        expect(prot.length, lessThanOrEqualTo(8));
        expect(sb.length, 5,
            reason: 'servicios_basicos siempre envía los 5 tipos');

        final protConDatos = protGrupos.where((g) => g.tieneDatos).length;
        expect(prot.length, protConDatos,
            reason: 'proteccion filtrada = solo tieneDatos');
      }
    });
  });

  // ─────────────────────────────────────────────────────
  // VERIFICACIÓN DE SCHEMA API vs IMPLEMENTACIÓN
  // ─────────────────────────────────────────────────────
  group('SCHEMA API: proteccion concuerda con contrato', () {
    EdanLocalidad _buildLocalidad({
      required bool grupProteccion,
      required List<EdanGrupoVulnerable> proteccion,
    }) {
      final loc = EdanLocalidad(
        idLocal: 'schema-test',
        tipoLocalidad: 'Barrio',
        nombre: 'Schema Test',
        idTipoLocalidad: 12,
        idDepartamento: 7,
        idProvincia: 701,
        idMunicipio: 70101,
        fechaLlenado: '2026-08-27',
        fechaEvento: '2026-08-27',
        grupPoblacion: false,
        grupSalud: false,
        grupInfraestructura: false,
        grupServicios: false,
        grupEducacion: false,
        grupVivienda: false,
        grupAgropecuario: false,
        grupProteccion: grupProteccion,
        grupNecesidades: false,
        proteccion: proteccion,
      );
      return loc;
    }

    test('toApiJson() produce JSON válido con proteccion[] dentro de localidad', () {
      final loc = _buildLocalidad(
        grupProteccion: true,
        proteccion: List<EdanGrupoVulnerable>.generate(8, (i) =>
            EdanGrupoVulnerable(
              idSeccion: generarIdSeccion('po'),
              idGrupoVulnerableCatalogo: i + 1,
            )),
      );
      loc.proteccion[0].mujeres = 5;
      loc.proteccion[0].hombres = 3;
      loc.proteccion[0].apoyoPsicologico = true;

      loc.recalcularFlagsImpacto();  // como hace el guardado real
      final json = loc.toApiJson();

      expect(json['proteccion'], isA<List>(), reason: 'proteccion debe ser array');
      expect(json['imp_proteccion'], isTrue);

      final prot = loc.proteccionParaEndpointDedicado();
      expect(prot.length, 1, reason: 'solo 1 grupo tieneDatos');

      final item = prot[0];
      expect(item.containsKey('id_seccion'), isTrue, reason: 'id_seccion requerido');
      expect(item['id_seccion'], isA<String>());
      expect(item['id_seccion'].toString().startsWith('po_'), isTrue,
          reason: 'id_seccion debe empezar con po_');
      expect(item.containsKey('id_grupo_vulnerable_catalogo'), isTrue);
      expect(item['id_grupo_vulnerable_catalogo'], 1);
      expect(item['mujeres'], 5);
      expect(item['hombres'], 3);
      expect(item['apoyo_psicologico'], isTrue);
    });

    test('test_payload.json: proteccion item tiene todos los campos del schema', () {
      final item = {
        'id_seccion': '1a0367eo5p6-659den5o6p7q8',
        'id_grupo_vulnerable_catalogo': 1,
        'grupo': {
          'id': 1,
          'codigo': 'adultos_mayores',
          'nombre': 'Adultos mayores',
          'orden': 5,
        },
        'mujeres': 15,
        'hombres': 12,
        'total': 27,
        'apoyo_psicologico': true,
        'reposicion_documentos': false,
        'observaciones': 'Requieren medicamentos',
      };

      expect(item['id_seccion'], isA<String>());
      expect(item['id_grupo_vulnerable_catalogo'], isA<int>());
      expect(item['grupo'], isA<Map>());
      final grupo = item['grupo'] as Map;
      expect(grupo['id'], isA<int>());
      expect(grupo['codigo'], isA<String>());
      expect(grupo['nombre'], isA<String>());
      expect(item['mujeres'], isA<int>());
      expect(item['hombres'], isA<int>());
      expect(item['total'], isA<int>());
      expect(item['apoyo_psicologico'], isA<bool>());
      expect(item['reposicion_documentos'], isA<bool>());
      expect(item['observaciones'], isA<String>());
    });

    test('toApiJson() sin catálogo: grupoCatalogo=null → "grupo" NO está en JSON', () {
      final g = EdanGrupoVulnerable(
        idSeccion: generarIdSeccion('po'),
        idGrupoVulnerableCatalogo: 3,
        mujeres: 2,
        hombres: 1,
      );
      final api = g.toApiJson(null);
      expect(api.containsKey('grupo'), isFalse,
          reason: 'toApiJson(null) no debe incluir grupo');
    });

    test('toApiJson() con catálogo: grupo SÍ está en JSON', () {
      final g = EdanGrupoVulnerable(
        idSeccion: generarIdSeccion('po'),
        idGrupoVulnerableCatalogo: 1,
        mujeres: 5,
        hombres: 3,
      );
      final catalogo = {
        'id': 1,
        'codigo': 'adultos_mayores',
        'nombre': 'Adultos mayores',
        'orden': 5,
      };
      final api = g.toApiJson(catalogo);
      expect(api.containsKey('grupo'), isTrue);
      expect(api['grupo']['id'], 1);
      expect(api['grupo']['nombre'], 'Adultos mayores');
    });

    test('total SÍ se envía desde toApiJson() (endpoints dedicados)', () {
      final g = EdanGrupoVulnerable(
        idSeccion: generarIdSeccion('po'),
        idGrupoVulnerableCatalogo: 1,
        mujeres: 10,
        hombres: 5,
      );
      final api = g.toApiJson(null);
      expect(api.containsKey('total'), isTrue,
          reason: 'En endpoints dedicados el cliente envía total');
      expect(api['total'], 15);
    });

    test('toApiJson() NO incluye fotografia (anti-duplicados)', () {
      final g = EdanGrupoVulnerable(
        idSeccion: generarIdSeccion('po'),
        idGrupoVulnerableCatalogo: 1,
        mujeres: 3,
        hombres: 2,
        observaciones: 'Test',
      );
      final api = g.toApiJson({'id': 1, 'nombre': 'Test'});
      expect(api.containsKey('fotografia'), isFalse);
      expect(api.containsKey('foto'), isFalse);
      expect(api.containsKey('fotos'), isFalse);
    });

    test('campos null se preservan en JSON (tri-state booleans)', () {
      final g = EdanGrupoVulnerable(
        idSeccion: generarIdSeccion('po'),
        idGrupoVulnerableCatalogo: 1,
        mujeres: 1,
        apoyoPsicologico: null,
        reposicionDocumentos: null,
      );
      final api = g.toApiJson(null);
      expect(api['apoyo_psicologico'], isNull);
      expect(api['reposicion_documentos'], isNull);
    });

    test('toJson() (SQLite) incluye nombre_grupo para roundtrip', () {
      final g = EdanGrupoVulnerable(
        idSeccion: generarIdSeccion('po'),
        idGrupoVulnerableCatalogo: 2,
        nombreGrupo: 'Adolescentes',
        mujeres: 3,
        hombres: 2,
      );
      final sqlite = g.toJson();
      expect(sqlite['nombre_grupo'], 'Adolescentes');

      final restored = EdanGrupoVulnerable.fromJson(sqlite);
      expect(restored.nombreGrupo, 'Adolescentes');
      expect(restored.idGrupoVulnerableCatalogo, 2);
      expect(restored.mujeres, 3);
    });

    test('fromJson() lee nombre_grupo de SQLite (clave plana)', () {
      final fromSqlite = EdanGrupoVulnerable.fromJson({
        'id_seccion': 'po_123',
        'nombre_grupo': 'Adultos mayores',
        'id_grupo_vulnerable_catalogo': 5,
        'mujeres': 10,
        'hombres': 8,
        'apoyo_psicologico': true,
        'reposicion_documentos': false,
        'observaciones': 'Test',
      });
      expect(fromSqlite.nombreGrupo, 'Adultos mayores');
      expect(fromSqlite.idGrupoVulnerableCatalogo, 5);
    });

    test('fromJson() lee nombre de grupo anidado (respuesta API)', () {
      final fromApi = EdanGrupoVulnerable.fromJson({
        'id_seccion': 'po_456',
        'id_grupo_vulnerable_catalogo': 3,
        'grupo': {
          'id': 3,
          'codigo': 'adolescentes',
          'nombre': 'Adolescentes',
        },
        'mujeres': 5,
        'hombres': 4,
      });
      expect(fromApi.nombreGrupo, 'Adolescentes');
      expect(fromApi.idGrupoVulnerableCatalogo, 3);
    });

    test('roundtrip completo SQLite: toApiJson preserva todo después de fromJson→toJson', () {
      final original = EdanGrupoVulnerable(
        idSeccion: 'b8b8b8b8-b8b8-4b8b-8b8b-b8b8b8b8b8b8',
        idGrupoVulnerableCatalogo: 4,
        nombreGrupo: 'Mujeres lactantes',
        mujeres: 7,
        hombres: 0,
        apoyoPsicologico: true,
        reposicionDocumentos: false,
        observaciones: 'Necesitan leche',
      );

      final sqlite = original.toJson();
      final restored = EdanGrupoVulnerable.fromJson(sqlite);
      final api = restored.toApiJson({
        'id': 4,
        'codigo': 'mujeres_lactantes',
        'nombre': 'Mujeres lactantes',
      });

      expect(api['id_seccion'], original.idSeccion);
      expect(api['id_grupo_vulnerable_catalogo'], 4);
      expect(api['mujeres'], 7);
      expect(api['hombres'], 0);
      expect(api['apoyo_psicologico'], isTrue);
      expect(api['reposicion_documentos'], isFalse);
      expect(api['observaciones'], 'Necesitan leche');
      expect(api['grupo']['nombre'], 'Mujeres lactantes');
    });

    test('proteccionDesdeCatalogo() setea nombreGrupo desde catálogo', () {
      final catalogo = [
        {'id_grupo_vulnerable': 1, 'nombre': 'Niños 0-5'},
        {'id_grupo_vulnerable': 2, 'nombre': 'Niños 6-12'},
        {'id_grupo_vulnerable': 3, 'nombre': 'Adolescentes'},
      ];
      final grupos = EdanLocalidad.proteccionDesdeCatalogo(catalogo);
      expect(grupos.length, 3);
      expect(grupos[0].nombreGrupo, 'Niños 0-5');
      expect(grupos[1].nombreGrupo, 'Niños 6-12');
      expect(grupos[2].nombreGrupo, 'Adolescentes');
      expect(grupos[0].idGrupoVulnerableCatalogo, 1);
      expect(grupos[1].idGrupoVulnerableCatalogo, 2);
    });

    test('_proteccionPorDefecto() tiene nombreGrupo en los 8 grupos', () {
      final defecto = EdanLocalidad(
        proteccion: null,
      ).proteccion;
      expect(defecto.length, 8);
      for (final g in defecto) {
        expect(g.nombreGrupo, isNotNull, reason: 'nombreGrupo no debe ser null');
        expect(g.nombreGrupo!.isNotEmpty, isTrue, reason: 'nombreGrupo no vacío');
      }
    });

    test('proteccion api: solo 2 de 8 grupos con datos → solo 2 enviados', () {
      final grupos = List<EdanGrupoVulnerable>.generate(8, (i) =>
          EdanGrupoVulnerable(
            idSeccion: generarIdSeccion('po'),
            idGrupoVulnerableCatalogo: i + 1,
            nombreGrupo: 'Grupo ${i + 1}',
          ));
      grupos[2].mujeres = 5;
      grupos[2].hombres = 3;
      grupos[5].mujeres = 10;

      final prot = _buildLocalidad(grupProteccion: true, proteccion: grupos)
          .proteccionParaEndpointDedicado();

      expect(prot.length, 2, reason: 'solo 2 grupos con datos');
      expect(prot[0]['id_grupo_vulnerable_catalogo'], 3,
          reason: 'primer enviado = grupo 3 (Adolescentes)');
      expect(prot[1]['id_grupo_vulnerable_catalogo'], 6,
          reason: 'segundo enviado = grupo 6 (Adultos mayores)');
    });

    test('fromJson→toJson→toApiJson: 8 default groups roundtrip completo', () {
      final original = _buildLocalidad(
        grupProteccion: true,
        proteccion: List<EdanGrupoVulnerable>.generate(8, (i) =>
            EdanGrupoVulnerable(
              idSeccion: generarIdSeccion('po'),
              idGrupoVulnerableCatalogo: i + 1,
              nombreGrupo: 'Grupo $i',
            )),
      );
      original.proteccion[0].mujeres = 5;
      original.proteccion[0].hombres = 3;
      original.proteccion[7].observaciones = 'Enfermedad crónica';

      final sqlite = original.toJson();
      final restored = EdanLocalidad.fromJson(sqlite);

      expect(restored.proteccion.length, 8);
      expect(restored.proteccion[0].mujeres, 5);
      expect(restored.proteccion[0].hombres, 3);
      expect(restored.proteccion[7].observaciones, 'Enfermedad crónica');
      expect(restored.proteccion[0].nombreGrupo, 'Grupo 0');
      expect(restored.proteccion[7].nombreGrupo, 'Grupo 7');

      final api = restored.proteccionParaEndpointDedicado();
      expect(api.length, 2, reason: 'solo 2 con datos');
    });

    test('envío completo: 1 localidad con grupProteccion=true y 3 grupos con datos', () {
      final grupos = List<EdanGrupoVulnerable>.generate(8, (i) =>
          EdanGrupoVulnerable(
            idSeccion: generarIdSeccion('po'),
            idGrupoVulnerableCatalogo: i + 1,
            nombreGrupo: 'Grupo ${i + 1}',
          ));
      grupos[0].mujeres = 5;
      grupos[0].hombres = 3;
      grupos[0].apoyoPsicologico = true;
      grupos[4].mujeres = 10;
      grupos[4].observaciones = 'Embarazadas necesitan control';
      grupos[6].hombres = 2;
      grupos[6].reposicionDocumentos = true;

      final loc = _buildLocalidad(grupProteccion: true, proteccion: grupos);
      final prot = loc.proteccionParaEndpointDedicado();

      expect(prot.length, 3);
      expect(loc.grupProteccion, isTrue);

      for (final item in prot) {
        expect(item['id_seccion'], startsWith('po_'));
        expect(item['id_grupo_vulnerable_catalogo'], isA<int>());
        expect(item.containsKey('fotografia'), isFalse);
        expect(item.containsKey('grupo'), isFalse, reason: 'sin catálogo, grupo null');
      }
    });

    test('consistencia: 8 grupos default con catálogo → envía id_grupo_vulnerable_catalogo', () {
      final grupos = List<EdanGrupoVulnerable>.generate(8, (i) =>
          EdanGrupoVulnerable(
            idSeccion: generarIdSeccion('po'),
            idGrupoVulnerableCatalogo: i + 1,
            nombreGrupo: 'Grupo ${i + 1}',
            mujeres: (i + 1) * 2,
          ));

      final loc = _buildLocalidad(grupProteccion: true, proteccion: grupos);
      final prot = loc.proteccionParaEndpointDedicado();

      expect(prot.length, 8, reason: 'todos tienen mujeres > 0');
      for (var i = 0; i < prot.length; i++) {
        final item = prot[i];
        expect(item['id_grupo_vulnerable_catalogo'], i + 1,
            reason: 'grupo ${i + 1} tiene catálogo ID ${i + 1}');
      }
    });

    test('BUG REAL DEVICE: backfill _proteccionPorDefecto sin catálogo → '
        'reconciliación por índice evita "Field required"', () {
      // Reproduce el fallo del dispositivo: una localidad recuperada con
      // backfill de 8 grupos SIN idGrupoVulnerableCatalogo (null) y el usuario
      // llena datos en el índice 0. Sin reconciliar, el payload se envía SIN
      // id_grupo_vulnerable_catalogo -> servidor rechaza 422.
      final porDefecto = List<EdanGrupoVulnerable>.generate(
        8,
        (i) => EdanGrupoVulnerable(
          idSeccion: generarIdSeccion('po'),
          nombreGrupo: 'Grupo ${i + 1}',
        ),
      );
      expect(porDefecto[0].idGrupoVulnerableCatalogo, isNull,
          reason: 'backfill default NO trae catálogo (escenario del bug)');

      // Catálogo real de 8 items (mismo orden posicional que el backfill).
      const catalogoIds = [1, 2, 3, 4, 5, 6, 7, 8];

      // Reconciliación (equivale a _reconciliarCatalogoProteccion del form):
      for (var i = 0; i < porDefecto.length; i++) {
        if (porDefecto[i].idGrupoVulnerableCatalogo == null) {
          porDefecto[i].idGrupoVulnerableCatalogo = catalogoIds[i];
        }
      }

      // El usuario llena datos en el grupo 0 (mujeres/hombres).
      porDefecto[0].mujeres = 4;
      porDefecto[0].hombres = 6;

      final loc = _buildLocalidad(grupProteccion: true, proteccion: porDefecto);
      final prot = loc.proteccionParaEndpointDedicado();
      expect(prot.length, 1, reason: 'solo grupo 0 tiene datos');
      final item = prot[0];
      expect(item['id_grupo_vulnerable_catalogo'], 1,
          reason: 'tras reconciliar, el payload SÍ lleva id_grupo_vulnerable_catalogo');
      expect(item.containsKey('id_grupo_vulnerable_catalogo'), isTrue,
          reason: 'el campo requerido va presente -> el servidor ya no rechaza');
      expect(item['total'], 10, reason: 'total client-calculado');
    });
  });
}
