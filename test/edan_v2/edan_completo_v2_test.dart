/// Fase F — pruebas de la reescritura sobre `/formularios/completo`.
///
/// Cubre lo que cambió en las fases A–C:
///  * matriz grupo × secciones (ida/vuelta y cobertura de las 14 rutas);
///  * rutas del cliente API (`/formularios/` en secciones/viviendas + `/completo`);
///  * payload: `responsable` y `danos_vivienda` como **objeto único** 1:1 con
///    `viviendas[]` anidadas y coordenadas del padre anuladas;
///  * `grupos_local` (v32): selección del usuario vs caché del servidor;
///  * migración v32 (backfill de grupos + columna `pendiente_push`);
///  * purga de `grupos_local` al borrar el formulario.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:rea/models/edan.dart';
import 'package:rea/models/edan_registro_v2.dart';
import 'package:rea/services/api/edan_api_v2.dart';
import 'package:rea/services/database_helper.dart';
import 'package:rea/services/edan/edan_localidades_envio_v2_service.dart';
import 'package:rea/services/edan/edan_store_v2.dart';
import 'package:rea/services/sync/edan_sync_engine_v2.dart';
import 'package:rea/services/edan_secciones_registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _base = 'https://api.test/api/v2/edan';

Map<String, dynamic> _env({dynamic data, bool success = true}) => {
      'success': success,
      if (data != null) 'data': data,
    };

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  // ─────────────────────────────────────────────────────────────────────
  // 1. Matriz grupo × secciones (fuente única de verdad)
  // ─────────────────────────────────────────────────────────────────────
  group('matriz grupo × secciones', () {
    test('cada grupo activa exactamente las rutas documentadas', () {
      expect(EdanSeccionesRegistry.rutasDeGrupo('grupPoblacion'),
          ['impacto-poblacion', 'primera-respuesta']);
      expect(EdanSeccionesRegistry.rutasDeGrupo('grupSalud'),
          ['salud-establecimientos', 'necesidad-salud']);
      expect(EdanSeccionesRegistry.rutasDeGrupo('grupInfraestructura'),
          ['danos-viales', 'danos-infra-publica']);
      expect(EdanSeccionesRegistry.rutasDeGrupo('grupServicios'),
          ['servicios-basicos']);
      expect(EdanSeccionesRegistry.rutasDeGrupo('grupEducacion'),
          ['unidades-educativas']);
      expect(EdanSeccionesRegistry.rutasDeGrupo('grupVivienda'),
          ['danos-vivienda']);
      expect(EdanSeccionesRegistry.rutasDeGrupo('grupAgropecuario'),
          ['danos-agricultura', 'danos-pecuarios', 'infra-productiva']);
      expect(EdanSeccionesRegistry.rutasDeGrupo('grupProteccion'),
          ['proteccion']);
      expect(EdanSeccionesRegistry.rutasDeGrupo('grupNecesidades'),
          ['necesidad-humanitaria']);
    });

    test('las 14 rutas del registro cubren exactamente la matriz', () {
      final deLaMatriz = EdanSeccionesRegistry.matrizGrupoSecciones.values
          .expand((e) => e)
          .toSet();
      final delRegistro =
          EdanSeccionesRegistry.secciones.map((s) => s.rutaV2).toSet();
      expect(delRegistro, deLaMatriz,
          reason: 'la matriz y el registro deben listar las mismas 14 rutas');
      expect(delRegistro, hasLength(14));
    });

    test('tipo_entidad = los 15 valores del CHECK (verificado en vivo)', () {
      // 2026-10-14: cada valor se probó contra POST /fotografias real —
      // válido responde 404 (dueña inexistente), inválido 400. Tres valores
      // estaban mal (`danos_pecuarios`, `necesidad_salud`,
      // `necesidad_humanitaria`) y daban 400 en fotos de esas secciones.
      const esperados = {
        'impacto-poblacion': 'impacto_poblacion',
        'salud-establecimientos': 'salud_establecimientos',
        'necesidad-salud': 'salud_necesidades',
        'danos-viales': 'danos_viales',
        'danos-infra-publica': 'danos_infra_publica',
        'servicios-basicos': 'servicios_basicos',
        'unidades-educativas': 'unidades_educativas',
        'danos-vivienda': 'danos_vivienda',
        'danos-agricultura': 'danos_agricultura',
        'danos-pecuarios': 'danos_pecuario',
        'infra-productiva': 'infra_productiva',
        'proteccion': 'proteccion',
        'primera-respuesta': 'primera_respuesta',
        'necesidad-humanitaria': 'necesidades_humanitarias',
      };
      expect(esperados, hasLength(14));
      for (final e in esperados.entries) {
        expect(EdanSeccionesRegistry.tipoEntidadDeRuta(e.key), e.value,
            reason: 'ruta ${e.key} debe resolver al nombre corto de tabla');
      }
      // …+ 'vivienda' = los 15 del CHECK; el marcador local nunca es válido.
      for (final v in [...esperados.values, 'vivienda']) {
        expect(EdanSeccionesRegistry.esTipoEntidadValido(v), isTrue);
      }
      expect(EdanSeccionesRegistry.esTipoEntidadValido('filas_seccion'),
          isFalse);
      expect(EdanSeccionesRegistry.esTipoEntidadValido(null), isFalse);
    });

    test('grupoDeRuta es la inversa de rutasDeGrupo para las 14 rutas', () {
      for (final entry in EdanSeccionesRegistry.matrizGrupoSecciones.entries) {
        for (final ruta in entry.value) {
          expect(EdanSeccionesRegistry.grupoDeRuta(ruta), entry.key,
              reason: 'ruta $ruta debe pertenecer a ${entry.key}');
        }
      }
    });

    test('ida y vuelta: rutasDesdeGrupos(gruposDesdeActivas(r)) ⊇ r', () {
      // Escenario del usuario: tildar "población" y "agropecuario".
      final marcados = {'grupPoblacion', 'grupAgropecuario'};
      final rutas = EdanSeccionesRegistry.rutasDesdeGrupos(marcados);
      expect(rutas, hasLength(5)); // 2 + 3
      final deVuelta = EdanSeccionesRegistry.gruposDesdeActivas(rutas);
      expect(deVuelta, marcados,
          reason: 'el viaje de ida y vuelta debe ser exacto');
    });

    test('gruposDesdeActivas no acopla grupPoblacion con grupProteccion', () {
      final soloProteccion =
          EdanSeccionesRegistry.gruposDesdeActivas(['proteccion']);
      expect(soloProteccion, {'grupProteccion'});
      expect(soloProteccion.contains('grupPoblacion'), isFalse,
          reason: 'el acoplamiento destructivo fue eliminado (B5)');
    });

    test('necesidad-salud NO enciende grup_necesidades (corrección de regresión)',
        () {
      final flags = EdanSeccionesRegistry.construirFlagsDesdeActivas(
          ['necesidad-salud']);
      expect(flags['imp_necesidad_salud'], isTrue);
      expect(flags['grup_salud'], isTrue);
      expect(flags['grup_necesidades'], isFalse,
          reason: 'grup_necesidades solo viene de necesidad-humanitaria');
    });

    test('construirFlagsDesdeActivas entrega 14 imp_* + 9 grup_* = 23', () {
      final flags = EdanSeccionesRegistry.construirFlagsDesdeActivas([]);
      expect(flags, hasLength(23));
      expect(flags.keys.where((k) => k.startsWith('imp_')), hasLength(14),
          reason: '14 banderas de SECCION (las del POST /completo)');
      expect(flags.keys.where((k) => k.startsWith('grup_')), hasLength(9),
          reason: '9 banderas de GRUPO (page01, nunca se envian)');
      expect(flags.values.every((v) => v == false), isTrue,
          reason: 'sin secciones activas todos los flags quedan en false');
    });

    test('la colision historica de proteccion queda separada', () {
      // Antes el grupo Proteccion y la seccion 14 compartian la clave
      // `imp_proteccion`, asi que `construirFlagsDesdeActivas` escribia 23
      // valores pero solo quedaban 22 claves (el bucle de grupos sobrescribia
      // la del bucle de secciones). Con `grup_proteccion` cada clave significa
      // una sola cosa.
      final flags = EdanSeccionesRegistry.construirFlagsDesdeActivas(
          ['proteccion']);
      expect(flags.containsKey('imp_proteccion'), isTrue,
          reason: 'flag de SECCION 14');
      expect(flags.containsKey('grup_proteccion'), isTrue,
          reason: 'flag de GRUPO de page01');
      expect(flags['imp_proteccion'], isTrue);
      expect(flags['grup_proteccion'], isTrue);
      // Y encender otra seccion no debe tocar la de proteccion.
      final otra = EdanSeccionesRegistry.construirFlagsDesdeActivas(
          ['danos-viales']);
      expect(otra['imp_proteccion'], isFalse);
      expect(otra['grup_proteccion'], isFalse);
      expect(otra['imp_danos_viales'], isTrue);
      expect(otra['grup_infraestructura'], isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // 2. Cliente API: rutas y /completo
  // ─────────────────────────────────────────────────────────────────────
  group('EdanApiV2 · rutas', () {
    EdanApiV2 api(MockClient client) =>
        EdanApiV2(httpClient: client, baseUrl: _base);

    test('las rutas de secciones llevan el segmento /formularios/', () async {
      late Uri visto;
      final client = MockClient((req) async {
        visto = req.url;
        return _json(_env(data: <String, dynamic>{}));
      });
      await api(client).upsertSeccion('loc-1', 'danos-viales', {});
      expect(visto.path,
          endsWith('/formularios/loc-1/secciones/danos-viales'),
          reason: 'sin /formularios/ el motor apuntaba a una ruta inexistente');
    });

    test('el PUT de sección también lleva /formularios/', () async {
      late Uri visto;
      final client = MockClient((req) async {
        visto = req.url;
        return _json(_env(data: {}));
      });
      await api(client).actualizarSeccion('loc-1', 'proteccion', 'f-1', {});
      expect(visto.path, endsWith('/formularios/loc-1/secciones/proteccion/f-1'));
    });

    test('las rutas de viviendas llevan /formularios/ y danos-vivienda', () async {
      late Uri visto;
      final client = MockClient((req) async {
        visto = req.url;
        return _json(_env(data: {}));
      });
      await api(client).crearVivienda('loc-1', 'dv-1', {'uuid_registro': 'v1'});
      expect(
        visto.path,
        endsWith('/formularios/loc-1/secciones/danos-vivienda/dv-1/viviendas'),
      );
    });

    test('DELETE de sección (el camino de borrados) usa la ruta correcta',
        () async {
      late http.Request visto;
      final client = MockClient((req) async {
        visto = req;
        return _json(_env());
      });
      await api(client).eliminarSeccion('loc-1', 'danos-viales', 'f-1');
      expect(visto.method, 'DELETE');
      expect(visto.url.path,
          endsWith('/formularios/loc-1/secciones/danos-viales/f-1'));
    });
  });

  group('EdanApiV2 · /formularios/completo', () {
    EdanApiV2 api(MockClient client) =>
        EdanApiV2(httpClient: client, baseUrl: _base);

    test('crearFormularioCompleto hace POST al endpoint correcto', () async {
      late http.Request visto;
      final client = MockClient((req) async {
        visto = req;
        return _json(_env(data: {
          'resultados': [],
          'formulario': {'uuid_edan_localidad': 'u1'},
        }), 201);
      });
      final res = await api(client).crearFormularioCompleto({
        'uuid_edan_localidad': 'u1',
        'grup_poblacion': true,
      });
      expect(res.ok, isTrue);
      expect(visto.method, 'POST');
      expect(visto.url.path, endsWith('/formularios/completo'));
      final cuerpo = jsonDecode(visto.body) as Map<String, dynamic>;
      expect(cuerpo['uuid_edan_localidad'], 'u1');
      expect(cuerpo['grup_poblacion'], isTrue);
    });

    test('obtenerFormularioCompleto hace GET /{uuid}/completo', () async {
      late Uri visto;
      final client = MockClient((req) async {
        visto = req.url;
        return _json(_env(data: {'uuid_edan_localidad': 'u1'}));
      });
      await api(client).obtenerFormularioCompleto('u1');
      expect(visto.path, endsWith('/formularios/u1/completo'));
      expect(visto.queryParameters.containsKey('comprimido'), isFalse);
    });

    test('obtenerFormularioCompleto comprimido añade ?comprimido=true',
        () async {
      late Uri visto;
      final client = MockClient((req) async {
        visto = req.url;
        return _json(_env(data: {}));
      });
      await api(client).obtenerFormularioCompleto('u1', comprimido: true);
      expect(visto.queryParameters['comprimido'], 'true');
    });

    test('un 400 atómico del servidor se propaga como EdanApiError', () async {
      final client = MockClient((_) async => _json({
            'success': false,
            'detail': 'grup_poblacion=true pero no hay filas de impacto-poblacion',
          }, 400));
      expect(
        () => api(client).crearFormularioCompleto({'uuid_edan_localidad': 'u1'}),
        throwsA(isA<EdanApiError>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.detail, 'detail', contains('grup_poblacion'))),
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // 3. Payload: responsable + danos_vivienda 1:1
  // ─────────────────────────────────────────────────────────────────────
  group('EdanLocalidad.toApiJson · /completo', () {
    EdanVivienda viv(String uuid, EdanViviendaTipo tipo) => EdanVivienda(
          uuidRegistro: uuid,
          uuidDanoVivienda: 'dv-1',
          tipoDano: tipo,
          coordenadaLat: -17.5,
          coordenadaLon: -66.1,
        );

    test('danos_vivienda sale como OBJETO ÚNICO (no lista)', () {
      final loc = EdanLocalidad(
        uuidEdanLocalidad: 'u1',
        nombre: 'El Carmen',
        danosVivienda: [
          EdanDanoVivienda(
            idSeccion: 'dv-1',
            comunidad: 'El Carmen',
            viviendas: [
              viv('v1', EdanViviendaTipo.total),
              viv('v2', EdanViviendaTipo.parcial),
            ],
          ),
        ],
      );
      final payload = loc.toApiJson();
      expect(payload['danos_vivienda'], isA<Map<String, dynamic>>(),
          reason: 'el spec define danos_vivienda como 1:1 (objeto único)');
    });

    test('el objeto 1:1 anuda viviendas[] y deriva los contadores', () {
      final loc = EdanLocalidad(
        uuidEdanLocalidad: 'u1',
        danosVivienda: [
          EdanDanoVivienda(
            idSeccion: 'dv-1',
            danoTotal: 99, // manuales, deben ignorarse
            danoParcial: 88,
            viviendas: [
              viv('v1', EdanViviendaTipo.total),
              viv('v2', EdanViviendaTipo.total),
              viv('v3', EdanViviendaTipo.parcial),
            ],
          ),
        ],
      );
      final dv = loc.toApiJson()['danos_vivienda'] as Map<String, dynamic>;
      expect(dv['viviendas'], isA<List>());
      expect((dv['viviendas'] as List), hasLength(3));
      expect(dv['dano_total'], 2, reason: 'derivado de viviendas[]');
      expect(dv['dano_parcial'], 1, reason: 'derivado de viviendas[]');
    });

    test('si la fila tiene hijas, las coordenadas del padre se anulan (§20.4)',
        () {
      final loc = EdanLocalidad(
        uuidEdanLocalidad: 'u1',
        danosVivienda: [
          EdanDanoVivienda(
            idSeccion: 'dv-1',
            coordenadaLat: -17.1,
            coordenadaLon: -66.2,
            viviendas: [viv('v1', EdanViviendaTipo.total)],
          ),
        ],
      );
      final dv = loc.toApiJson()['danos_vivienda'] as Map<String, dynamic>;
      expect(dv['coordenada_lat'], isNull);
      expect(dv['coordenada_lon'], isNull);
      final hija = (dv['viviendas'] as List).first as Map<String, dynamic>;
      expect(hija['coordenada_lat'], -17.5,
          reason: 'las coords viven en cada vivienda hija');
    });

    test('fila legacy sin hijas conserva sus coordenadas (§20.4)', () {
      final loc = EdanLocalidad(
        uuidEdanLocalidad: 'u1',
        danosVivienda: [
          EdanDanoVivienda(
            idSeccion: 'dv-1',
            danoTotal: 17,
            danoParcial: 42,
            coordenadaLat: -17.1,
            coordenadaLon: -66.2,
          ),
        ],
      );
      final dv = loc.toApiJson()['danos_vivienda'] as Map<String, dynamic>;
      expect(dv['coordenada_lat'], -17.1);
      expect(dv['coordenada_lon'], -66.2);
      expect(dv['dano_total'], 17, reason: 'sin detalle se conservan los manuales');
      expect((dv['viviendas'] as List), isEmpty);
    });

    test('sin filas, danos_vivienda sale null (no lista vacía)', () {
      final loc = EdanLocalidad(uuidEdanLocalidad: 'u1', nombre: 'X');
      expect(loc.toApiJson()['danos_vivienda'], isNull);
    });

    test('responsable NO viaja en la forma API de la LOCALIDAD (es del EDAN '
        'padre); sí se conserva en la forma local', () {
      final loc = EdanLocalidad(
        uuidEdanLocalidad: 'u1',
        nombre: 'X',
        responsable: EdanResponsable(
          nombre: 'Ana',
          cargo: 'Alcaldesa',
          fono: '70000000',
          correo: 'ana@municipio.gob.bo',
        ),
      );
      // API: no es columna de edan_localidades ni del FormularioCompletoUpsert.
      expect(loc.toApiJson().containsKey('responsable'), isFalse);
      expect(loc.toApiJson().containsKey('nombre_alcalde'), isFalse);
      expect(loc.toApiJson().containsKey('fono_alcalde'), isFalse);
      // Local (persistencia/UI page13): se conserva.
      final local = loc.toJson()['responsable'] as Map<String, dynamic>;
      expect(local['nombre'], 'Ana');
      expect(local['cargo'], 'Alcaldesa');
      expect(local['fono'], '70000000');
      expect(local['correo'], 'ana@municipio.gob.bo');
    });

    test('responsable vacío NO viaja (no ensuciar el payload)', () {
      final loc = EdanLocalidad(uuidEdanLocalidad: 'u1', nombre: 'X');
      expect(loc.toApiJson().containsKey('responsable'), isFalse);
      expect(loc.responsable?.hayDatos, isFalse);
    });

    test('las 14 secciones 1:N viajan como lista y las 1:1 como objeto', () {
      final loc = EdanLocalidad(
        uuidEdanLocalidad: 'u1',
        nombre: 'X',
        grupPoblacion: true,
        grupSalud: true,
        grupVivienda: true,
        grupNecesidades: true,
        impactoPoblacion: [EdanImpactoPoblacion()],
        establecimientosSalud: [EdanEstablecimientoSalud()],
        danosViales: [EdanDanoVial()],
        necesidadSalud: EdanNecesidadSalud(),
        necesidadHumanitaria: EdanNecesidadHumanitaria(),
        danosVivienda: [EdanDanoVivienda(idSeccion: 'dv-1')],
      );
      final p = loc.toApiJson();
      // 1:N → lista
      expect(p['impacto_poblacion'], isA<List>());
      expect(p['establecimientos_salud'], isA<List>());
      expect(p['danos_viales'], isA<List>());
      // 1:1 → objeto
      expect(p['necesidad_salud'], isA<Map<String, dynamic>>());
      expect(p['necesidad_humanitaria'], isA<Map<String, dynamic>>());
      expect(p['danos_vivienda'], isA<Map<String, dynamic>>());
    });

    test('los 14 imp_* siempre están presentes (obligatorios del servidor)', () {
      final p = EdanLocalidad(uuidEdanLocalidad: 'u1', nombre: 'X').toApiJson();
      const esperados = [
        'imp_impacto_poblacion',
        'imp_primera_respuesta',
        'imp_salud_establecimientos',
        'imp_necesidad_salud',
        'imp_danos_viales',
        'imp_danos_infra_publica',
        'imp_servicios_basicos',
        'imp_unidades_educativas',
        'imp_danos_vivienda',
        'imp_danos_agricultura',
        'imp_danos_pecuarios',
        'imp_infra_productiva',
        'imp_proteccion',
        'imp_necesidad_humanitaria',
      ];
      for (final f in esperados) {
        expect(p.containsKey(f), isTrue, reason: '$f es obligatoria (400 si falta)');
        expect(p[f], isFalse);
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // 4–6. SQLite: grupos_local, migración v32 y purga
  // ─────────────────────────────────────────────────────────────────────
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EdanStoreV2 · grupos_local (v32)', () {
    late Directory dir;
    final db = DatabaseHelper.instance;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('edan_grupos');
      DatabaseHelper.rutaDePrueba = p.join(dir.path, 'test.db');
    });

    tearDown(() async {
      await db.cerrarParaPrueba();
      DatabaseHelper.rutaDePrueba = null;
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    Future<EdanStoreV2> store() async {
      await db.database;
      return EdanStoreV2(db: db);
    }

    test('guardarSeleccionGrupos → leerSeleccionGrupos roundtrip', () async {
      final s = await store();
      await s.guardarSeleccionGrupos('loc-1', {'grupPoblacion', 'grupVivienda'});
      final leidos = await s.leerSeleccionGrupos('loc-1');
      expect(leidos, {'grupPoblacion', 'grupVivienda'});
    });

    test('guardarSeleccionGrupos pisa la selección anterior (replace)', () async {
      final s = await store();
      await s.guardarSeleccionGrupos('loc-1', {'grupPoblacion'});
      await s.guardarSeleccionGrupos('loc-1', {'grupSalud'});
      expect(await s.leerSeleccionGrupos('loc-1'), {'grupSalud'});
      // Los 9 grupos quedan persistidos (marcados o no).
      final filas = await (await db.database).query('grupos_local',
          where: 'uuid_edan_localidad = ?', whereArgs: ['loc-1']);
      expect(filas, hasLength(9));
    });

    test('guardarGruposServidor no toca la selección del usuario', () async {
      final s = await store();
      await s.guardarSeleccionGrupos('loc-1', {'grupPoblacion'});
      await s.guardarGruposServidor('loc-1', {
        'grupPoblacion': true,
        'grupSalud': false,
      });
      expect(await s.leerSeleccionGrupos('loc-1'), {'grupPoblacion'},
          reason: 'la caché del servidor no debe pisar lo que tildó el usuario');
      final servidor = await s.leerGruposServidor('loc-1');
      expect(servidor['grupPoblacion'], isTrue);
      expect(servidor['grupSalud'], isFalse);
      expect(servidor, hasLength(2),
          reason: 'solo los grupos cacheados del servidor (ids locales)');
    });

    test('guardarGruposServidor preserva seleccion_usuario en filas existentes',
        () async {
      // Regresión del bug propio: `ConflictAlgorithm.replace` borraba la fila
      // entera y perdía la selección del usuario al cachear el nodo servidor.
      final s = await store();
      await s.guardarSeleccionGrupos('loc-4', {'grupServicios'});
      expect(await s.leerSeleccionGrupos('loc-4'), {'grupServicios'});

      await s.guardarGruposServidor('loc-4', {
        'grupServicios': false, // el servidor dice que no está activo
      });

      expect(await s.leerSeleccionGrupos('loc-4'), {'grupServicios'},
          reason: 'la selección local sobrevive a la caché del servidor');
      expect((await s.leerGruposServidor('loc-4'))['grupServicios'], isFalse);
    });

    test('leerGruposServidor está vacío antes de la primera lectura', () async {
      final s = await store();
      expect(await s.leerGruposServidor('loc-1'), isEmpty);
    });

    test('gruposActivos prefiere la selección explícita', () async {
      final s = await store();
      await s.guardarSeleccionGrupos('loc-1', {'grupServicios'});
      expect(await s.gruposActivos('loc-1'), {'grupServicios'});
    });

    test('gruposActivos cae a la derivación inversa sin selección explícita',
        () async {
      final s = await store();
      // Solo secciones activas (camino legacy / backfill).
      await s.activarSecciones('loc-2', ['danos-vivienda', 'proteccion']);
      expect(await s.gruposActivos('loc-2'), {'grupVivienda', 'grupProteccion'});
    });

    test('marcarBorradoFormulario limpia grupos_local', () async {
      final s = await store();
      await s.guardarFormulario(
        EdanLocalidad(
          uuidEdanLocalidad: 'loc-9',
          nombre: 'Borrar',
          grupPoblacion: true,
        ),
        usuarioId: 7,
        seccionesActivas: ['impacto-poblacion', 'primera-respuesta'],
      );
      expect(await s.leerSeleccionGrupos('loc-9'), {'grupPoblacion'});

      await s.marcarBorradoFormulario('loc-9');

      expect(await s.leerSeleccionGrupos('loc-9'), isEmpty);
      expect(await s.leerGruposServidor('loc-9'), isEmpty);
      final restos = await (await db.database).query('grupos_local',
          where: 'uuid_edan_localidad = ?', whereArgs: ['loc-9']);
      expect(restos, isEmpty);
    });

    test('activarSecciones espeja en localidad_secciones_activas (badges)',
        () async {
      // Regresión: el listado RESP lee de `localidad_secciones_activas`
      // (legacy) vía `aplicarFlagsDesdeSeccionesActivas`. Sin el espejo, los
      // badges del listado no reflejan lo marcado en page01.
      final s = await store();
      await s.activarSecciones('loc-mirror', [
        'danos-vivienda',
        'danos-agricultura',
      ]);

      final legacy = await (await db.database).query(
        'localidad_secciones_activas',
        where: 'id_local = ? AND activa = 1',
        whereArgs: ['loc-mirror'],
      );
      expect(legacy.map((r) => r['seccion']).toSet(),
          {'danos-vivienda', 'danos-agricultura'});
    });

    test(
        'preview ve grupAgropecuario con filas V2 y tabla legacy vacía '
        '(regresión: sección 09 oculta)', () async {
      // Reproduce el bug reportado: reporte V2 con datos de agricultura en
      // `filas_seccion` pero SIN filas en la tabla legacy
      // `localidad_secciones_activas`. Antes, `aplicarFlagsDesdeSeccionesActivas`
      // (sin unión) leía la legacy vacía → `grupAgropecuario=false` →
      // `EdanResumenPage` ocultaba la sección 09 aunque el badge la mostraba.
      final s = await store();
      // 1. Formulario V2 (sin pasar seccionesActivas para NO poblar la legacy).
      await s.guardarFormulario(
        EdanLocalidad(uuidEdanLocalidad: 'loc-prev', nombre: 'Agro'),
        usuarioId: 7,
      );
      // 2. Dato real de agricultura en filas_seccion.
      await s.guardarFilas('loc-prev', ['danos-agricultura'], EdanLocalidad(
        uuidEdanLocalidad: 'loc-prev',
        nombre: 'Agro',
        danosAgricultura: [
          EdanDanoAgricultura(
            idSeccion: 'a1',
            tipoCultivo: 'Maíz',
            hectareasAfectadas: 5,
          ),
        ],
      ));
      // 3. Garantizar que la legacy esté vacía (el escenario del bug).
      await (await db.database).delete(
        'localidad_secciones_activas',
        where: 'id_local = ?',
        whereArgs: ['loc-prev'],
      );

      final loc = EdanLocalidad(idLocal: 'loc-prev', nombre: 'Agro');
      await EdanLocalidadesEnvioV2Service().aplicarFlagsDesdeSeccionesActivas(
          loc); // sin unionConGuardados, como el preview

      expect(loc.impDanosAgricultura, isTrue,
          reason: 'el flag detallado debe salir de filas_seccion (V2)');
      expect(loc.grupAgropecuario, isTrue,
          reason: 'el flag grueso debe derivarse de la matriz grupo→secciones');
    });

    test('el payload /completo es V2-aware (reemplaza al /documento)', () async {
      // Mismo escenario que el preview: reporte V2 con datos en
      // `filas_seccion` y la tabla legacy `localidad_secciones_activas`
      // vacía. El serializador `/documento` fue retirado; ahora la única
      // fuente es `EdanSeccionesFuente`, así que la regresión se comprueba
      // contra el payload que realmente se envía.
      final s = await store();
      await s.guardarFormulario(
        EdanLocalidad(uuidEdanLocalidad: 'loc-doc', nombre: 'Agro'),
        usuarioId: 7,
      );
      await s.guardarFilas('loc-doc', ['danos-agricultura'], EdanLocalidad(
        uuidEdanLocalidad: 'loc-doc',
        nombre: 'Agro',
        danosAgricultura: [
          EdanDanoAgricultura(idSeccion: 'a1', tipoCultivo: 'Maíz'),
        ],
      ));
      await (await db.database).delete(
        'localidad_secciones_activas',
        where: 'id_local = ?',
        whereArgs: ['loc-doc'],
      );

      final fila = (await (await db.database).query('formularios',
              where: 'uuid_edan_localidad = ?',
              whereArgs: ['loc-doc'],
              limit: 1))
          .first;
      final payload = await EdanSyncEngineV2.prepararPayloadCompleto(
          'loc-doc', fila);

      expect(payload['imp_danos_agricultura'], isTrue,
          reason: 'flag de SECCION debe salir de filas_seccion (V2)');
      expect(payload['danos_agricultura'], allOf(isA<List>(), hasLength(1)));
      expect(payload['imp_danos_vivienda'], isFalse);
      // El grupo (`grup_*`) no viaja en el POST: lo deriva el servidor.
      expect(payload.containsKey('grup_agropecuario'), isFalse);
    });
  });

  group('esquema limpio v40', () {
    late Directory dir;
    final db = DatabaseHelper.instance;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('edan_mig32');
      DatabaseHelper.rutaDePrueba = p.join(dir.path, 'test.db');
    });

    tearDown(() async {
      await db.cerrarParaPrueba();
      DatabaseHelper.rutaDePrueba = null;
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('la tabla grupos_local y la columna pendiente_push existen', () async {
      final database = await db.database;
      final tablas = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='grupos_local'");
      expect(tablas, hasLength(1));

      final cols = await database.rawQuery('PRAGMA table_info(formularios)');
      expect(cols.map((c) => c['name']), contains('pendiente_push'));
    });

    test('pendiente_push nace en 0', () async {
      final database = await db.database;
      await database.insert('formularios', {
        'uuid_edan_localidad': 'loc-32',
        'localidad': 'X',
        'pendiente_push': 0,
      });
      final fila = await database.query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['loc-32']);
      expect(fila.first['pendiente_push'], 0);
    });

    test('v40 alinea con DROP+CREATE limpio (sin migraciones ALTER)', () async {
      // 1. Crear una BD "vieja" a mano (con columna `version`) y cerrarla.
      final ruta = p.join(dir.path, 'test.db');
      final v31 = await openDatabase(
        ruta,
        version: 31,
        onCreate: (d, _) async {
          await d.execute('''
            CREATE TABLE formularios (
              uuid_edan_localidad TEXT PRIMARY KEY,
              localidad TEXT NOT NULL DEFAULT '',
              secciones_activas_json TEXT NOT NULL DEFAULT '{}',
              version INTEGER NOT NULL DEFAULT 0,
              estado_local TEXT NOT NULL DEFAULT 'borrador'
            )
          ''');
          await d.execute('''
            CREATE TABLE filas_seccion (
              uuid_registro TEXT PRIMARY KEY,
              uuid_edan_localidad TEXT NOT NULL,
              tipo TEXT NOT NULL,
              datos_json TEXT NOT NULL,
              version INTEGER NOT NULL DEFAULT 0,
              estado_sync TEXT NOT NULL DEFAULT 'confirmado'
            )
          ''');
        },
      );
      await v31.insert('formularios', {'uuid_edan_localidad': 'loc-bf'});
      await v31.close();

      // 2. Abrir con DatabaseHelper (v40): DROP+CREATE limpio de las 6
      // tablas V2 con el esquema final (sin `version`, con firma e
      // intentos). Diseño limpio: sin cadena ALTER.
      final database = await db.database;

      final cols = await database.rawQuery('PRAGMA table_info(formularios)');
      final nombres = cols.map((c) => c['name']).toSet();
      expect(nombres, contains('pendiente_push'),
          reason: 'el esquema v40 trae pendiente_push');
      expect(nombres, containsAll(['firma_contenido', 'firma_enviada']),
          reason: 'v40 trae firma');
      expect(nombres, isNot(contains('version')),
          reason: 'LWW: sin columna version');
      expect(nombres, isNot(contains('server_version')));
      expect(nombres, isNot(contains('server_snapshot')));
      final filasCols =
          await database.rawQuery('PRAGMA table_info(filas_seccion)');
      final filasNombres = filasCols.map((c) => c['name']).toSet();
      expect(filasNombres, isNot(contains('version')),
          reason: 'LWW: filas sin version');
      // Lo no sincronizado se pierde en el alineamiento (sincronizar antes
      // de instalar): la fila vieja ya no está.
      final viejas = await database.query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['loc-bf']);
      expect(viejas, isEmpty,
          reason: 'v40 recrea limpio: sin restos del esquema viejo');
    });

    test('v40 sin version/server_version/server_snapshot', () async {
      final database = await db.database;
      final cols = await database.rawQuery('PRAGMA table_info(formularios)');
      final nombres = cols.map((c) => c['name']).toSet();
      expect(
          nombres,
          containsAll([
            'sync_state',
            'pending_submit',
            'is_deleted',
            'datos_json_servidor',
          ]));
      expect(nombres, isNot(contains('version')),
          reason: 'LWW: sin columna version');
      expect(nombres, isNot(contains('server_version')),
          reason: 'LWW: sin columna server_version');
      expect(nombres, isNot(contains('server_snapshot')),
          reason: 'LWW: sin columna server_snapshot');
      final idx = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND name='uq_formularios_id_server'");
      expect(idx, hasLength(1),
          reason: 'remote_id con UNIQUE parcial (id_server no duplica)');
    });

    test('v40 extiende filas/viviendas/fotos/colas sin romper defaults',
        () async {
      final database = await db.database;
      Future<Set<String?>> columnas(String tabla) async {
        final cols = await database.rawQuery('PRAGMA table_info($tabla)');
        return cols.map((c) => c['name'] as String?).toSet();
      }

      expect(await columnas('filas_seccion'),
          containsAll(['remote_id', 'is_deleted', 'estado_sync']));
      expect(await columnas('viviendas'),
          containsAll(['estado_sync', 'is_deleted']));
      expect(
          await columnas('fotografias'),
          containsAll([
            'remote_id',
            'file_name',
            'mime_type',
            'size_bytes',
            'upload_state',
            'is_deleted',
            'created_at',
            'last_error',
            'intentos_descarga',
            'fecha_proximo_intento',
          ]));
      expect(await columnas('cola_sincronizacion'),
          containsAll(['operation_uuid', 'idempotency_key', 'depends_on', 'payload_json']));
      expect(await columnas('cola_fotos'),
          containsAll(['file_name', 'mime_type', 'size_bytes', 'created_at']));

      // Defaults: insert mínimo respeta el contrato local.
      await database.insert('formularios', {
        'uuid_edan_localidad': 'loc-35',
        'localidad': 'Y',
      });
      final fila = await database.query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['loc-35']);
      expect(fila.first['sync_state'], 'pending_create');
      expect(fila.first['pending_submit'], 0);
      expect(fila.first['is_deleted'], 0);
    });

    test('v38/v39 agregan firma e intentos sin pérdida', () async {
      final database = await db.database;
      Future<Set<String?>> columnas(String tabla) async {
        final cols = await database.rawQuery('PRAGMA table_info($tabla)');
        return cols.map((c) => c['name'] as String?).toSet();
      }

      expect(await columnas('formularios'),
          containsAll(['firma_contenido', 'firma_enviada']));
      expect(await columnas('fotografias'),
          containsAll(['intentos_descarga', 'fecha_proximo_intento']));
    });
  });
}