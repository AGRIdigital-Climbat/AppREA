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
import 'package:path/path.dart' as p;
import 'package:rea/models/edan.dart';
import 'package:rea/screens/role_screens/resp/edan/edan_boton_sacar_foto.dart';
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
      expect(lista, hasLength(4));
      final porId = {
        for (final f in lista)
          (f['id_grupo_etario'] as num).toInt(): f as Map
      };
      expect(porId[1]!['fallecidos'], 2,
          reason: 'los grupos llenos NO se anulan por el re-lleno de ceros');
      expect(porId[3]!['fallecidos'], 1);
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
              'lista no cambia de dueño el uuid del servidor');
    });
  });
}
