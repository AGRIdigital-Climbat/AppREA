/// Contrato de filas por sección (2026-10-17):
///
///  * "Solo lo llenado": las filas sembradas vacías (page06 sembró 5
///    servicios, page10/`EdanLocalidad` trae 8 protección por defecto) NO se
///    persisten en `filas_seccion` ni viajan en `/completo`. Las 1:1 vacías
///    tampoco.
///  * Catálogos 4/8 (impacto, protección): si el usuario llenó al menos un
///    grupo, el POST lleva el SET EXACTO — los grupos con datos conservan sus
///    valores y los demás se completan con 0, con uuid determinista por id de
///    catálogo (re-empujar no duplica ni cambia de dueño).
///  * Impacto se persiste EXPANDIDO (una fila por grupo etario con su
///    `id_grupo_etario`, contrato §20.10.E) y se colapsa al hidratar (page03
///    consume el wrapper con grupos anidados).
///  * Foto: dueña = `uuid_registro` válido; un id legacy con prefijo se
///    regenera (`asegurarUuidRegistro`), consistente con `registrarFila`.
///  * Borrador contaminado con filas vacías confirmadas: re-guardar las purga
///    locales y encola su `D` (Gap 2) → desaparecen del servidor.
///  * Rescate de snapshot: solo rescata filas llenas y la identidad del
///    catálogo es independiente del orden de la lista.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:rea/models/edan.dart';
import 'package:rea/screens/role_screens/resp/edan/edan_boton_sacar_foto.dart';
import 'package:rea/services/api/edan_api_v2.dart';
import 'package:rea/services/database_helper.dart';
import 'package:rea/services/edan/edan_secciones_fuente.dart';
import 'package:rea/services/edan/edan_store_v2.dart';
import 'package:rea/services/edan/edan_uuid_helper.dart';
import 'package:rea/services/sync/edan_sync_engine_v2.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  final db = DatabaseHelper.instance;
  final store = EdanStoreV2(db: db);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('edan_contrato');
    DatabaseHelper.rutaDePrueba = p.join(dir.path, 'test.db');
  });

  tearDown(() async {
    await db.cerrarParaPrueba();
    DatabaseHelper.rutaDePrueba = null;
    if (dir.existsSync()) {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {
        Future.delayed(const Duration(milliseconds: 250), () {
          if (dir.existsSync()) {
            try {
              dir.deleteSync(recursive: true);
            } catch (_) {}
          }
        });
      }
    }
  });

  Future<List<Map<String, Object?>>> filasDe(String uuid, String tipo) async =>
      (await db.database).query(
        'filas_seccion',
        where: 'uuid_edan_localidad = ? AND tipo = ?',
        whereArgs: [uuid, tipo],
      );

  Future<Map<String, dynamic>> payloadDe(String uuid) async {
    final formRow = (await (await db.database)
            .query('formularios',
                where: 'uuid_edan_localidad = ?', whereArgs: [uuid]))
        .first;
    return EdanSyncEngineV2.prepararPayloadCompleto(uuid, formRow,
        dbHelper: db);
  }

  List<EdanServicioBasicoDetalle> _semillaServicios() => [
        EdanServicioBasicoDetalle(tipo: 'energia_electrica'),
        EdanServicioBasicoDetalle(tipo: 'agua_potable'),
        EdanServicioBasicoDetalle(tipo: 'alcantarillado'),
        EdanServicioBasicoDetalle(tipo: 'gas_domiciliario'),
        EdanServicioBasicoDetalle(tipo: 'telecomunicaciones'),
      ];

  EdanLocalidad _loc({String uuid = 'u-1'}) =>
      EdanLocalidad(nombre: 'L', idTipoEvento: 1, uuidEdanLocalidad: uuid);

  group('servicios-basicos: solo lo llenado persiste y viaja', () {
    test('5 sembradas, energía llena + foto → 1 fila, payload 1 fila, '
        'foto dueña del uuid de esa fila', () async {
      final loc = _loc();
      // Como en la app: page01 marcó el grupo (el gate del motor lo exige).
      loc.grupServicios = true;
      final servicios = _semillaServicios();
      servicios[0]
        ..afectado = true
        ..danoParcial = true
        ..necesidadesInmediatas = 'Afectación de energía';
      loc.serviciosBasicos = servicios;
      final e = EdanBotonSacarFoto.asegurarUuidRegistro(servicios[0]);
      loc.recalcularImpDesdeListas();
      await store.guardarTodo(
        loc,
        usuarioId: 1,
        seccionesActivas: const ['servicios-basicos'],
        tipos: const ['servicios-basicos'],
      );
      // La foto llega después del primer guardado (flujo real page06: sheet →
      // store.registrarFoto con el uuid del ítem).
      await store.registrarFoto(
          EdanFoto(ruta: '', latitud: -16.5, longitud: -68.1),
          'servicios_basicos',
          e);

      final filas = await filasDe('u-1', 'servicios-basicos');
      expect(filas, hasLength(1),
          reason: 'las 4 sembradas vacías NO se persisten');
      final dec = jsonDecode(filas.single['datos_json'] as String) as Map;
      expect(dec['tipo'], 'energia_electrica');
      expect(filas.single['uuid_registro'], e);

      final payload = await payloadDe('u-1');
      expect(payload['imp_servicios_basicos'], isTrue);
      final lista = payload['servicios_basicos'] as List;
      expect(lista, hasLength(1));
      expect((lista.single as Map)['tipo'], 'energia_electrica');
      expect(lista.single['uuid_registro'], e,
          reason: 'la fila del POST es la misma identidad que la foto');

      final fotos = await (await db.database).query('fotografias');
      expect(fotos.single['uuid_registro'], e,
          reason: 'la foto cuelga de la fila llena (d552945f del reporte)');
      expect(fotos.single['tipo_entidad'], 'servicios_basicos');
    });

    test('ninguna llena → sección entera no persiste ni viaja', () async {
      final loc = _loc()..serviciosBasicos = _semillaServicios();
      await store.guardarTodo(
        loc,
        usuarioId: 1,
        seccionesActivas: const ['servicios-basicos'],
        tipos: const ['servicios-basicos'],
      );
      expect(await filasDe('u-1', 'servicios-basicos'), isEmpty);
      final payload = await payloadDe('u-1');
      expect(payload['imp_servicios_basicos'], isFalse);
      expect(payload.containsKey('servicios_basicos'), isFalse,
          reason: 'flag false ⟹ la clave no aparece (regla flag↔fila)');
    });
  });

  group('impacto-población: set EXACTO 4, 0 rellenan, datos conservan', () {
    EdanLocalidad _locImpacto() {
      final loc = _loc()..grupPoblacion = true;
      loc.impactoPoblacion = [
        EdanImpactoPoblacion(
          grupoEtario: 'Total',
          fallecidos: 3,
          gruposEtarios: [
            EdanGrupoEtario(
                rango: 'Niño (a) 0-5 años',
                idGrupoEtarioCatalogo: 1,
                fallecidos: 2,
                marcado: true),
            EdanGrupoEtario(
                rango: 'Escolar de 6-18 años', idGrupoEtarioCatalogo: 2),
            EdanGrupoEtario(
                rango: 'Adulto de 19-60 años',
                idGrupoEtarioCatalogo: 3,
                fallecidos: 1,
                marcado: true),
            EdanGrupoEtario(
                rango: 'Adulto mayor de 60 años adelante',
                idGrupoEtarioCatalogo: 4),
          ],
        ),
      ];
      loc.recalcularImpDesdeListas();
      return loc;
    }

    test('guardar expande por id: 4 filas exactas, id1=2 id3=1 id2/id4=0, '
        'uuid sintético por catálogo', () async {
      await store.guardarTodo(
        _locImpacto(),
        usuarioId: 1,
        seccionesActivas: const ['impacto-poblacion'],
        tipos: const ['impacto-poblacion'],
      );
      final filas = await filasDe('u-1', 'impacto-poblacion');
      expect(filas, hasLength(4));
      final porId = <int, Map>{};
      for (final f in filas) {
        final dec = jsonDecode(f['datos_json'] as String) as Map;
        porId[(dec['id_grupo_etario'] as num).toInt()] = dec;
        expect(f['uuid_registro'],
            EdanSeccionesFuente.uuidFilaSintetica(
                'u-1', 'impacto-poblacion', (dec['id_grupo_etario'] as num).toInt()),
            reason: 'identidad determinista = padding del motor');
      }
      expect(porId.keys.toSet(), {1, 2, 3, 4});
      expect(porId[1]!['fallecidos'], 2);
      expect(porId[3]!['fallecidos'], 1);
      expect(porId[2]!['fallecidos'], 0);
      expect(porId[4]!['fallecidos'], 0);
    });

    test('payload /completo lleva las 4 con los valores reales', () async {
      await store.guardarTodo(
        _locImpacto(),
        usuarioId: 1,
        seccionesActivas: const ['impacto-poblacion'],
        tipos: const ['impacto-poblacion'],
      );
      final payload = await payloadDe('u-1');
      expect(payload['imp_impacto_poblacion'], isTrue);
      final lista = payload['impacto_poblacion'] as List;
      expect(lista, hasLength(4),
          reason: 'set EXACTO 1-4 exigido por el servidor');
      final porId = {
        for (final f in lista)
          (f['id_grupo_etario'] as num).toInt(): f as Map
      };
      expect(porId[1]!['fallecidos'], 2,
          reason: 'los grupos llenos NO se anulan por el re-lleno de ceros');
      expect(porId[3]!['fallecidos'], 1);
      for (final f in lista) {
        expect(f.containsKey('rango'), isFalse,
            reason: 'con `id_grupo_etario` el servidor rechaza `rango` '
                '(400 por fila: "campo desconocido o no escribible")');
      }
    });

    test('grupo marcado SIN números sobrevive el round-trip y `marcado` no '
        'viaja en el POST', () async {
      final loc = _loc()..grupPoblacion = true;
      loc.impactoPoblacion = [
        EdanImpactoPoblacion(
          grupoEtario: 'Total',
          fallecidos: 2,
          gruposEtarios: [
            EdanGrupoEtario(
                rango: 'Niño (a) 0-5 años',
                idGrupoEtarioCatalogo: 1,
                fallecidos: 2,
                marcado: true),
            EdanGrupoEtario(
                rango: 'Escolar de 6-18 años',
                idGrupoEtarioCatalogo: 2,
                marcado: true), // marcado, sin números
            EdanGrupoEtario(rango: 'Adulto de 19-60 años', idGrupoEtarioCatalogo: 3),
            EdanGrupoEtario(
                rango: 'Adulto mayor de 60 años adelante',
                idGrupoEtarioCatalogo: 4),
          ],
        ),
      ];
      loc.recalcularImpDesdeListas();
      await store.guardarTodo(
        loc,
        usuarioId: 1,
        seccionesActivas: const ['impacto-poblacion'],
        tipos: const ['impacto-poblacion'],
      );

      final rec = _loc();
      await store.cargarSecciones(rec, tipos: const ['impacto-poblacion']);
      final w = rec.impactoPoblacion.first;
      expect(w.gruposEtarios, hasLength(4));
      expect(w.gruposEtarios.firstWhere((g) => g.idGrupoEtario == 2).marcado,
          isTrue,
          reason: 'el check del grupo sobrevive reabrir (bug servicios, '
              'misma clase acá)');
      expect(w.gruposEtarios.firstWhere((g) => g.idGrupoEtario == 4).marcado,
          isFalse);

      final payload = await payloadDe('u-1');
      for (final f in payload['impacto_poblacion'] as List) {
        expect((f as Map).containsKey('marcado'), isFalse,
            reason: 'la tabla del servidor no tiene `marcado`: el motor lo '
                'quita (400 "campo desconocido" si viajara)');
      }
    });

    test('hidratar colapsa al wrapper de page03 y re-guardar no duplica',
        () async {
      await store.guardarTodo(
        _locImpacto(),
        usuarioId: 1,
        seccionesActivas: const ['impacto-poblacion'],
        tipos: const ['impacto-poblacion'],
      );
      final recargada = _loc();
      await store.cargarSecciones(recargada,
          tipos: const ['impacto-poblacion']);
      expect(recargada.impactoPoblacion, hasLength(1),
          reason: 'page03 consume UN wrapper con grupos anidados');
      final w = recargada.impactoPoblacion.first;
      expect(w.grupoEtario, 'Total');
      expect(w.fallecidos, 3, reason: 'totales = suma de los grupos');
      expect(w.gruposEtarios, hasLength(4));
      final g1 = w.gruposEtarios.firstWhere((g) => g.idGrupoEtario == 1);
      expect(g1.fallecidos, 2);
      expect(g1.marcado, isTrue);
      final g2 = w.gruposEtarios.firstWhere((g) => g.idGrupoEtario == 2);
      expect(g2.marcado, isFalse,
          reason: 'el padding cero no se muestra como grupo marcado');

      // Espeja al wizard: `_guardar` recalcula los `imp_*` antes de persistir.
      recargada.recalcularImpDesdeListas();
      await store.guardarTodo(
        recargada,
        usuarioId: 1,
        seccionesActivas: const ['impacto-poblacion'],
        tipos: const ['impacto-poblacion'],
      );
      final filas = await filasDe('u-1', 'impacto-poblacion');
      expect(filas, hasLength(4), reason: 'idempotente: sin duplicados');
      expect(
        filas
            .map((f) =>
                (jsonDecode(f['datos_json'] as String) as Map)['fallecidos'])
            .where((v) => (v as num) > 0)
            .fold<num>(0, (a, b) => a + b),
        3,
        reason: 'los valores siguen intactos tras el round-trip',
      );
    });

    test('la fila de padding toma el rango del catálogo cacheado '
        '(`catalogo_grupo_etario`, no del mapa canónico)', () async {
      await db.saveGruposEtarios([
        for (var i = 1; i <= 4; i++)
          {
            'id_grupo_etario': i,
            'codigo': 'GE$i',
            'nombre': 'CATALOGO $i',
            'orden': i,
            'activo': 1,
          },
      ]);
      await store.guardarTodo(
        _locImpacto(),
        usuarioId: 1,
        seccionesActivas: const ['impacto-poblacion'],
        tipos: const ['impacto-poblacion'],
      );
      final rec = _loc();
      await store.cargarSecciones(rec, tipos: const ['impacto-poblacion']);
      final w = rec.impactoPoblacion.first;
      final g2 = w.gruposEtarios.firstWhere((g) => g.idGrupoEtario == 2);
      expect(g2.rango, 'CATALOGO 2',
          reason: 'el catálogo manda sobre el mapa de respaldo');
      final g1 = w.gruposEtarios.firstWhere((g) => g.idGrupoEtario == 1);
      expect(g1.rango, 'Niño (a) 0-5 años',
          reason: 'la fila con datos conserva el rango propio persistido');
    });

    test('envoltura legacy (totales globales sin grupos marcados) sigue '
        'guardando su fila resuelta por nombre', () async {
      final loc = _loc()
        ..impactoPoblacion = [
          EdanImpactoPoblacion(
            grupoEtario: 'Niño (a) 0-5 años',
            fallecidos: 1,
            gruposEtarios: [],
          ),
        ];
      loc.recalcularImpDesdeListas();
      await store.guardarTodo(
        loc,
        usuarioId: 1,
        seccionesActivas: const ['impacto-poblacion'],
        tipos: const ['impacto-poblacion'],
      );
      final filas = await filasDe('u-1', 'impacto-poblacion');
      expect(filas, hasLength(4));
      final ids = filas
          .map((f) => (jsonDecode(f['datos_json'] as String) as Map)['id_grupo_etario'])
          .toSet();
      expect(ids, {1, 2, 3, 4});
    });
  });

  group('protección: set EXACTO 8 con 0 rellenos', () {
    test('hidratar trae el enunciado del catálogo cacheado (no hardcodeado)',
        () async {
      await db.saveGruposVulnerables([
        for (var i = 1; i <= 8; i++)
          {
            'id_grupo_vulnerable': i,
            'codigo': 'GV$i',
            'nombre': 'GRUPO OFICIAL $i',
            'orden': i,
            'activo': 1,
          },
      ]);
      final loc = _loc()..grupProteccion = true;
      loc.proteccion[2].mujeres = 4; // 'Adolescentes' resuelve id 3
      loc.recalcularImpDesdeListas();
      await store.guardarTodo(
        loc,
        usuarioId: 1,
        seccionesActivas: const ['proteccion'],
        tipos: const ['proteccion'],
      );

      final rec = _loc();
      await store.cargarSecciones(rec, tipos: const ['proteccion']);
      final g3 = rec.proteccion
          .firstWhere((g) => g.idGrupoVulnerableCatalogo == 3);
      expect(g3.mujeres, 4);
      expect(g3.nombreGrupo, 'GRUPO OFICIAL 3',
          reason: 'el texto sale de `catalogo_grupo_vulnerable`, no de '
              'constantes de la app');
    });

    test('sin catálogo cacheado, la normalización pone los nombres canónicos '
        '(y page10 los corrige con el real cuando baja)', () async {
      final loc = _loc()..grupProteccion = true;
      loc.proteccion[0].mujeres = 1;
      loc.recalcularImpDesdeListas();
      await store.guardarTodo(
        loc,
        usuarioId: 1,
        seccionesActivas: const ['proteccion'],
        tipos: const ['proteccion'],
      );
      final rec = _loc();
      await store.cargarSecciones(rec, tipos: const ['proteccion']);
      expect(rec.proteccion, hasLength(8),
          reason: 'el guardado normaliza solo lo lleno + padding, e hidratar '
              'completa el set con su enunciado canónico');
      expect(
          rec.proteccion.map((g) => g.nombreGrupo).toList(),
          [
            'Niñas y niños 0-5 años',
            'Niñas y niños 6-12 años',
            'Adolescentes',
            'Mujeres lactantes',
            'Mujeres embarazadas',
            'Adultos mayores',
            'Personas con discapacidad',
            'Personas con enfermedad crónica',
          ],
          reason: 'los 8 slots nunca quedan sin enunciado, con o sin catálogo');
    });

    test('defaults vacíos no persisten; 2 llenos → 8 filas exactas', () async {
      final locVacia = _loc();
      await store.guardarTodo(
        locVacia,
        usuarioId: 1,
        seccionesActivas: const ['proteccion'],
        tipos: const ['proteccion'],
      );
      expect(await filasDe('u-1', 'proteccion'), isEmpty,
          reason: 'los 8 por defecto del modelo NO contaminan');

      final loc = _loc()..grupProteccion = true;
      loc.proteccion[0].mujeres = 3;
      loc.proteccion[4].hombres = 2;
      loc.recalcularImpDesdeListas();
      await store.guardarTodo(
        loc,
        usuarioId: 1,
        seccionesActivas: const ['proteccion'],
        tipos: const ['proteccion'],
      );
      final filas = await filasDe('u-1', 'proteccion');
      expect(filas, hasLength(8));
      final porId = <int, Map>{
        for (final f in filas)
          ((jsonDecode(f['datos_json'] as String) as Map)['id_grupo_vulnerable_catalogo']
                  as num)
              .toInt(): jsonDecode(f['datos_json'] as String) as Map
      };
      expect(porId.keys.toSet(), {1, 2, 3, 4, 5, 6, 7, 8});
      expect(porId[1]!['mujeres'], 3);
      expect(porId[5]!['hombres'], 2);
      expect(porId[2]!['mujeres'], 0);
      final payload = await payloadDe('u-1');
      expect(payload['proteccion'] as List, hasLength(8));
    });
  });

  group('1:1: el registro vacío no persiste ni viaja', () {
    test('necesidad-salud vacío → 0 filas; lleno → 1', () async {
      final loc = _loc();
      await store.guardarTodo(
        loc,
        usuarioId: 1,
        seccionesActivas: const ['necesidad-salud'],
        tipos: const ['necesidad-salud'],
      );
      expect(await filasDe('u-1', 'necesidad-salud'), isEmpty);

      loc.necesidadSalud!.botiquines = true;
      await store.guardarTodo(
        loc,
        usuarioId: 1,
        seccionesActivas: const ['necesidad-salud'],
        tipos: const ['necesidad-salud'],
      );
      expect(await filasDe('u-1', 'necesidad-salud'), hasLength(1));
    });
  });

  group('purge de borrador contaminado (Gap 2 encola D)', () {
    test('5 filas previas (4 confirmadas vacías) → 1 fila + 4 D', () async {
      const e = '11111111-2222-3333-4444-555555555555';
      final database = await db.database;
      final loc = _loc()
        ..grupServicios = true
        ..serviciosBasicos = _semillaServicios();
      loc.serviciosBasicos[0]
        ..idSeccion = e
        ..afectado = true
        ..danoTotal = true;
      loc.recalcularImpDesdeListas();
      await store.guardarTodo(
        loc,
        usuarioId: 1,
        seccionesActivas: const ['servicios-basicos'],
        tipos: const [],
      );
      // Simula el estado del bug: las 5 filas ya estaban en `filas_seccion`
      // y 4 se confirmaron en el servidor (el caso del reporte del usuario).
      for (var i = 1; i < 5; i++) {
        await database.insert('filas_seccion', {
          'uuid_registro': '0000000${i}-0000-4000-8000-000000000000',
          'uuid_edan_localidad': 'u-1',
          'tipo': 'servicios-basicos',
          'datos_json': jsonEncode({
            'id_seccion': '0000000${i}-0000-4000-8000-000000000000',
            'tipo': loc.serviciosBasicos[i].tipo,
            'dano_parcial': false,
            'dano_total': false,
            'necesidades_inmediatas': '',
            'observaciones': '',
          }),
          'fecha_modificacion_local': DateTime.now().toIso8601String(),
          'estado_sync': 'confirmado',
          'remote_id': 330000 + i,
        });
      }

      await store.guardarTodo(
        loc,
        usuarioId: 1,
        seccionesActivas: const ['servicios-basicos'],
        tipos: const ['servicios-basicos'],
      );

      final filas = await filasDe('u-1', 'servicios-basicos');
      expect(filas, hasLength(1),
          reason: 'la re-guarda purga las vacías locales');
      expect(filas.single['uuid_registro'], e);
      final d = await database.query(
        'cola_sincronizacion',
        where: "tabla = 'filas_seccion' AND accion = 'D'",
      );
      expect(d, hasLength(4),
          reason: 'las 4 confirmadas encolan su borrado para el servidor');
    });
  });

  group('identidad de foto: uuid válido obligatorio', () {
    test('asegurarUuidRegistro regenera el id legacy prefijado', () {
      final item = EdanServicioBasicoDetalle(tipo: 'energia_electrica')
        ..idSeccion = 'sb_1a2b3c';
      final out = EdanBotonSacarFoto.asegurarUuidRegistro(item);
      expect(out, isNot('sb_1a2b3c'),
          reason: 'registrarFila descartaría `sb_...` y la foto quedaría '
              'huérfana; se regenera ya');
      expect(EdanUuidHelper.esUuidValido(out), isTrue);
      expect(item.idSeccion, out, reason: 'el modelo queda con el uuid nuevo');

      final ok = EdanServicioBasicoDetalle(
          tipo: 'agua_potable', idSeccion: out);
      expect(EdanBotonSacarFoto.asegurarUuidRegistro(ok), out,
          reason: 'un uuid vigente se conserva: NUNCA se regenera al editar');
    });
  });

  group('rescate de snapshot: solo llenas e identidad estable al catálogo',
      () {
    Future<Map<String, Object?>> guardadoDe(Map<String, dynamic> snapJson,
        {String uuid = 'u-9'}) async {
      final database = await db.database;
      // Cabecera por el camino normal (sin grupos: `grupos_local` vacío ⇒ el
      // gate por grupo no filtra en el payload) y luego se pisa el snapshot.
      await store.guardarTodo(_loc(uuid: uuid),
          usuarioId: 1, seccionesActivas: const [], tipos: const []);
      await database.update(
        'formularios',
        {'datos_json': jsonEncode(snapJson)},
        where: 'uuid_edan_localidad = ?',
        whereArgs: [uuid],
      );
      return (await database.query('formularios',
              where: 'uuid_edan_localidad = ?', whereArgs: [uuid]))
          .first;
    }

    test('solo la fila con datos se rescata; su uuid no depende del orden',
        () async {
      final loc = _loc(uuid: 'u-9')..serviciosBasicos = _semillaServicios();
      loc.serviciosBasicos[0].necesidadesInmediatas = 'corte';
      final normal = await guardadoDe(jsonDecode(jsonEncode(loc.toJson()))
          as Map<String, dynamic>);
      final fuente = EdanSeccionesFuente(dbHelper: db);
      final primero = await fuente.seccionesConDatos('u-9',
          formRow: normal);

      // Mismo snapshot con los servicios en orden inverso.
      final snap = jsonDecode(jsonEncode(loc.toJson())) as Map<String, dynamic>;
      final lista = (snap['servicios_basicos'] as List).reversed.toList();
      snap['servicios_basicos'] = lista;
      final invertido = await guardadoDe(snap);
      final segundo = await fuente.seccionesConDatos('u-9',
          formRow: invertido);

      List rescatadas(Map<String, List<Map<String, dynamic>>> m) =>
          m['servicios-basicos'] ?? const [];
      expect(rescatadas(primero), hasLength(1),
          reason: 'las 4 vacías sembradas del snapshot tampoco viajan');
      expect(rescatadas(segundo), hasLength(1));
      expect((rescatadas(primero).single as Map)['tipo'],
          'energia_electrica');
      expect(rescatadas(segundo).single['uuid_registro'],
          rescatadas(primero).single['uuid_registro'],
          reason: 'identidad por catálogo, no por posición: reordenar la '
              'lista no cambia de dueño el uuid_registro');
    });
  });

  group('normalización de borrador contaminado (protección duplicada)', () {
    const nombres = [
      'Niñas y niños 0-5 años',
      'Niñas y niños 6-12 años',
      'Adolescentes',
      'Mujeres lactantes',
      'Mujeres embarazadas',
      'Adultos mayores',
      'Personas con discapacidad',
      'Personas con enfermedad crónica',
    ];

    test('16 filas locales (8 legacy sin id + 8 sintéticas) → hidratar 8, '
        'guardar deja 8 únicos y encola el D de la sintética perdida',
        () async {
      final database = await db.database;
      // Cabecera (para el formulario); sin filas todavía.
      await store.guardarTodo(_loc(),
          usuarioId: 1, seccionesActivas: const [], tipos: const []);
      // 8 filas LEGACY como las que dejaban los guardados viejos: sin
      // `id_grupo_vulnerable_catalogo`, con nombre canónico. Una con datos
      // (Adolescentes → id 3).
      for (var i = 0; i < 8; i++) {
        final u = '1000000${i + 1}-0000-4000-8000-000000000000';
        await database.insert('filas_seccion', {
          'uuid_registro': u,
          'uuid_edan_localidad': 'u-1',
          'tipo': 'proteccion',
          'datos_json': jsonEncode({
            'id_seccion': u,
            'nombre_grupo': nombres[i],
            'mujeres': i == 2 ? 4 : 0,
            'hombres': 0,
          }),
          'fecha_modificacion_local': DateTime.now().toIso8601String(),
          'estado_sync': 'pendiente',
        });
      }
      // 8 filas SINTÉTICAS del padding, con id, en ceros, ya confirmadas.
      for (var id = 1; id <= 8; id++) {
        final u =
            EdanSeccionesFuente.uuidFilaSintetica('u-1', 'proteccion', id);
        await database.insert(
          'filas_seccion',
          {
            'uuid_registro': u,
            'uuid_edan_localidad': 'u-1',
            'tipo': 'proteccion',
            'datos_json': jsonEncode({
              'id_grupo_vulnerable_catalogo': id,
              'mujeres': 0,
              'hombres': 0,
            }),
            'fecha_modificacion_local': DateTime.now().toIso8601String(),
            'estado_sync': 'confirmado',
            'remote_id': 1160 + id,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      final rec = _loc();
      await store.cargarSecciones(rec, tipos: const ['proteccion']);
      expect(rec.proteccion, hasLength(8),
          reason: 'la edición muestra 8 exactos, no los 16 crudos');
      expect(rec.proteccion.firstWhere((g) => g.idGrupoVulnerable == 3).mujeres,
          4,
          reason: 'en el choque de id 3 gana la fila con datos');

      rec.recalcularImpDesdeListas();
      await store.guardarTodo(
        rec,
        usuarioId: 1,
        seccionesActivas: const ['proteccion'],
        tipos: const ['proteccion'],
      );
      final filas = await filasDe('u-1', 'proteccion');
      expect(filas, hasLength(8),
          reason: 'gap-2 purga las huérfanas: un slot = una fila');
      final ids = filas
          .map((f) => ((jsonDecode(f['datos_json'] as String)
                  as Map<String, dynamic>)['id_grupo_vulnerable_catalogo']
              as num)
          .toInt())
          .toList();
      expect(ids.toSet(), {1, 2, 3, 4, 5, 6, 7, 8});
      final d = await database.query('cola_sincronizacion',
          where: "tabla = 'filas_seccion' AND accion = 'D'");
      expect(d, hasLength(1),
          reason: 'solo la sintética confirmada de id 3 (perdedora) encola D');
      expect(
        d.single['uuid_registro'],
        EdanSeccionesFuente.uuidFilaSintetica('u-1', 'proteccion', 3),
      );
    });

    test('impacto: el wrapper "Total" vacío del guardado viejo se descarta '
        'al hidratar; si trae números se conserva como extra', () async {
      final database = await db.database;
      await store.guardarTodo(_loc(),
          usuarioId: 1, seccionesActivas: const [], tipos: const []);
      Future<void> insertar(String u, Map<String, dynamic> dec,
          {String estado = 'pendiente'}) async {
        await database.insert(
          'filas_seccion',
          {
            'uuid_registro': u,
            'uuid_edan_localidad': 'u-1',
            'tipo': 'impacto-poblacion',
            'datos_json': jsonEncode(dec),
            'fecha_modificacion_local': DateTime.now().toIso8601String(),
            'estado_sync': estado,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await insertar('a0000000-0000-4000-8000-000000000001',
          {'grupo_etario': 'Total', 'fallecidos': 0, 'heridos': 0, 'desaparecidos': 0});
      for (var id = 1; id <= 4; id++) {
        await insertar(
            EdanSeccionesFuente.uuidFilaSintetica(
                'u-1', 'impacto-poblacion', id),
            {
              'id_grupo_etario': id,
              'fallecidos': 0,
              'heridos': 0,
              'desaparecidos': 0,
            });
      }

      final rec = _loc();
      await store.cargarSecciones(rec, tipos: const ['impacto-poblacion']);
      expect(rec.impactoPoblacion.first.gruposEtarios, hasLength(4),
          reason: 'el wrapper "Total" sin datos es basura de la expansión '
              'anterior y no debe aparecer como quinto grupo');

      // Ahora con el wrapper TRAE datos: se conserva (no se esconden números).
      await insertar('a0000000-0000-4000-8000-000000000001',
          {'grupo_etario': 'Total', 'fallecidos': 7, 'heridos': 0, 'desaparecidos': 0});
      final rec2 = _loc();
      await store.cargarSecciones(rec2, tipos: const ['impacto-poblacion']);
      expect(rec2.impactoPoblacion.first.gruposEtarios, hasLength(5),
          reason: '4 del catálogo + el extra con datos, visible no perdido');
    });
  });

  group('servicios-basicos: el check "afectado" sobrevive el round-trip', () {
    test('marcado SIN más datos: persiste en datos_json, hidrata marcado, '
        'sobrevive el segundo guardado y NO viaja en el POST', () async {
      final loc = _loc()..grupServicios = true;
      loc.serviciosBasicos = [
        EdanServicioBasicoDetalle(tipo: 'energia_electrica', afectado: true),
      ];
      loc.recalcularImpDesdeListas();
      await store.guardarTodo(
        loc,
        usuarioId: 1,
        seccionesActivas: const ['servicios-basicos'],
        tipos: const ['servicios-basicos'],
      );

      var filas = await filasDe('u-1', 'servicios-basicos');
      expect(filas, hasLength(1));
      final dec = jsonDecode(filas.single['datos_json'] as String) as Map;
      expect(dec['afectado'], isTrue,
          reason: 'el check se guarda en local (datos_json)');

      final rec = _loc();
      await store.cargarSecciones(rec, tipos: const ['servicios-basicos']);
      expect(rec.serviciosBasicos.single.afectado, isTrue,
          reason: 'reabrir muestra el check marcado (el bug reportado)');

      rec.recalcularImpDesdeListas();
      await store.guardarTodo(
        rec,
        usuarioId: 1,
        seccionesActivas: const ['servicios-basicos'],
        tipos: const ['servicios-basicos'],
      );
      filas = await filasDe('u-1', 'servicios-basicos');
      expect(filas, hasLength(1),
          reason: 'la fila check-only no la purga el filtro de filas vacías');

      final payload = await payloadDe('u-1');
      final row = (payload['servicios_basicos'] as List).single as Map;
      expect(row.containsKey('afectado'), isFalse,
          reason: 'el servidor no tiene la columna: el motor la quita '
              '(400 "campo desconocido" si viajara)');
      expect(row['tipo'], 'energia_electrica');
      expect(row['dano_parcial'], false);
    });

    test('BD guardada antes del fix (sin la clave, con datos): el check se '
        'deriva del contenido', () async {
      await store.guardarTodo(_loc(),
          usuarioId: 1, seccionesActivas: const [], tipos: const []);
      const u = 'd552945f-3384-4485-bab6-95220943b8d0';
      final database = await db.database;
      await database.insert('filas_seccion', {
        'uuid_registro': u,
        'uuid_edan_localidad': 'u-1',
        'tipo': 'servicios-basicos',
        'datos_json': jsonEncode({
          'id_seccion': u,
          'tipo': 'energia_electrica',
          'dano_parcial': true,
          'dano_total': false,
          'necesidades_inmediatas': 'Afectación de energía ',
          'observaciones': '',
        }),
        'fecha_modificacion_local': DateTime.now().toIso8601String(),
        'estado_sync': 'pendiente',
      });

      final rec = _loc();
      await store.cargarSecciones(rec, tipos: const ['servicios-basicos']);
      final s = rec.serviciosBasicos.single;
      expect(s.afectado, isTrue,
          reason: 'caso reportado: daño/necesidades presentes ⇒ afectado');
      expect(s.danoParcial, isTrue);
    });

    test('fila legacy en ceros absolutos (contaminación de la siembra): '
        'sigue desmarcada y se purga al guardar', () async {
      await store.guardarTodo(_loc(),
          usuarioId: 1, seccionesActivas: const [], tipos: const []);
      const u = 'e552945f-3384-4485-bab6-95220943b8d1';
      final database = await db.database;
      await database.insert('filas_seccion', {
        'uuid_registro': u,
        'uuid_edan_localidad': 'u-1',
        'tipo': 'servicios-basicos',
        'datos_json': jsonEncode({
          'id_seccion': u,
          'tipo': 'agua_potable',
          'dano_parcial': false,
          'dano_total': false,
          'necesidades_inmediatas': '',
          'observaciones': '',
        }),
        'fecha_modificacion_local': DateTime.now().toIso8601String(),
        'estado_sync': 'pendiente',
      });

      final rec = _loc();
      await store.cargarSecciones(rec, tipos: const ['servicios-basicos']);
      expect(rec.serviciosBasicos.single.afectado, isFalse,
          reason: 'sin clave y sin contenido no se revive la duplicidad');
      rec.recalcularImpDesdeListas();
      await store.guardarTodo(
        rec,
        usuarioId: 1,
        seccionesActivas: const ['servicios-basicos'],
        tipos: const ['servicios-basicos'],
      );
      expect(await filasDe('u-1', 'servicios-basicos'), isEmpty,
          reason: 'Gap-2 la purga en el primer guardado');
    });

    test('download por /completo: una fila que existe en el servidor vuelve '
        'marcada (allí la existencia ES el marcado)', () async {
      await EdanSyncEngineV2(
        api: EdanApiV2(
          httpClient: MockClient((_) async =>
              throw StateError('aplicarDocumentoCompleto no toca la red')),
          baseUrl: 'https://api.test/api/v2/edan',
        ),
        db: db,
      ).aplicarDocumentoCompleto({
        'uuid_edan_localidad': 'u-2',
        'id_edan_localidad': 55,
        'localidad': 'Las Lomas',
        'grupos': {'grup_servicios': true},
        'imp_servicios_basicos': true,
        'servicios_basicos': [
          {
            'uuid_registro': 'f0000000-0000-4000-8000-000000000001',
            'id_edan_localidad': 55,
            'tipo': 'gas_domiciliario',
            'dano_parcial': false,
            'dano_total': false,
            'necesidades_inmediatas': '',
            'observaciones': '',
          },
        ],
      });

      final rec = EdanLocalidad(
          nombre: 'L', idTipoEvento: 1, uuidEdanLocalidad: 'u-2');
      await store.cargarSecciones(rec, tipos: const ['servicios-basicos']);
      expect(rec.serviciosBasicos.single.afectado, isTrue,
          reason: 'servicio traido del servidor ⇒ el checkbox nace marcado');
    });
  });
}
