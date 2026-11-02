/// Firma de contenido (dirty derivado): paridad payload-DB, transiciones
/// dirty y guardia anti-carrera del confirm.
///
/// Fija el contrato: `firmaDePayload(prepararPayloadCompleto(uuid))` ==nom
/// `firmaContenido(DB)` cuando nada cambió; guardar sin cambios no ensucia;
/// revertir limpia; un save durante el push conserva el dirty.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'package:rea/models/edan.dart';
import 'package:rea/services/api/edan_api_v2.dart';
import 'package:rea/services/database_helper.dart';
import 'package:rea/services/edan/edan_store_v2.dart';
import 'package:rea/services/sync/edan_sync_engine_v2.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  final db = DatabaseHelper.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('edan_firma');
    DatabaseHelper.rutaDePrueba = p.join(dir.path, 'test.db');
  });

  tearDown(() async {
    await db.cerrarParaPrueba();
    DatabaseHelper.rutaDePrueba = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  http.Response _ok([Object? data]) => http.Response(
        jsonEncode({'success': true, if (data != null) 'data': data}),
        200,
        headers: {'content-type': 'application/json'},
      );

  EdanApiV2 _api(MockClient client) => EdanApiV2(
        httpClient: client,
        baseUrl: 'https://api.test/api/v2/edan',
      );

  Future<int> _dirty(String uuid) async {
    final rows = await (await db.database).query('formularios',
        columns: ['pendiente_push'],
        where: 'uuid_edan_localidad = ?',
        whereArgs: [uuid]);
    return (rows.first['pendiente_push'] as num?)?.toInt() ?? -1;
  }

  Future<void> _seedRica(String uuid) async {
    final d = await db.database;
    await d.insert('formularios', {
      'uuid_edan_localidad': uuid,
      'localidad': 'Loc Firma',
      'id_municipio': 70101,
      'total_poblacion_afectada': 10,
      'pendiente_push': 1,
    });
    await d.insert('filas_seccion', {
      'uuid_registro': 'aaaaaaaa-0000-4000-8000-00000000c011',
      'uuid_edan_localidad': uuid,
      'tipo': 'danos-agricultura',
      'datos_json': jsonEncode({
        'uuid_registro': 'aaaaaaaa-0000-4000-8000-00000000c011',
        'tipo_cultivo': 'MAIZ',
        'hectareas_afectadas': 5,
      }),
      'estado_sync': 'pendiente',
    });
    await d.insert('filas_seccion', {
      'uuid_registro': 'bbbbbbbb-0000-4000-8000-00000000d022',
      'uuid_edan_localidad': uuid,
      'tipo': 'danos-vivienda',
      'datos_json': jsonEncode({
        'uuid_registro': 'bbbbbbbb-0000-4000-8000-00000000d022',
        'coordenada_lat': -16.5,
        'coordenada_lon': -68.1,
      }),
      'estado_sync': 'pendiente',
    });
    await d.insert('viviendas', {
      'uuid_registro': 'cccccccc-0000-4000-8000-00000000e033',
      'uuid_dano_vivienda': 'bbbbbbbb-0000-4000-8000-00000000d022',
      'tipo_dano': 'PARCIAL',
      'coordenada_lat': -16.5,
      'coordenada_lon': -68.1,
    });
  }

  Future<void> _seedConChecks(String uuid) async {
    final d = await db.database;
    await d.insert('formularios', {
      'uuid_edan_localidad': uuid,
      'localidad': 'Loc Checks',
      'id_municipio': 70101,
      'total_poblacion_afectada': 10,
      'pendiente_push': 1,
    });
    // Servicios básicos: el check `afectado` vive en `datos_json` (sobrevive
    // el round-trip) pero el wire lo borra (motor 2405-2407). Con la firma
    // leyéndolo, los hashes divergían siempre → `pendiente_push` jamás se
    // limpiaba (badge pegado en 1 + re-PUT en cada sync).
    await d.insert('filas_seccion', {
      'uuid_registro': '11111111-0000-4000-8000-00000000sb01',
      'uuid_edan_localidad': uuid,
      'tipo': 'servicios-basicos',
      'datos_json': jsonEncode({
        'uuid_registro': '11111111-0000-4000-8000-00000000sb01',
        'tipo': 'AGUA',
        'afectado': true,
      }),
      'estado_sync': 'pendiente',
    });
    // Impacto por grupo etario: `marcado` local + `rango` legacy que el wire
    // borra cuando la fila trae `id_grupo_etario` (motor 2414-2416).
    await d.insert('filas_seccion', {
      'uuid_registro': '22222222-0000-4000-8000-00000000im01',
      'uuid_edan_localidad': uuid,
      'tipo': 'impacto-poblacion',
      'datos_json': jsonEncode({
        'uuid_registro': '22222222-0000-4000-8000-00000000im01',
        'id_grupo_etario': 1,
        'marcado': true,
        'rango': '0 a 14 años',
      }),
      'estado_sync': 'pendiente',
    });
  }

  group('paridad firma payload-DB', () {
    test('firmaDePayload == firmaContenido sin cambios', () async {
      const uuid = 'u-par';
      await _seedRica(uuid);
      final database = await db.database;
      final row = (await database.query('formularios',
          where: 'uuid_edan_localidad = ?',
          whereArgs: [uuid])).first;
      final payload = await EdanSyncEngineV2.prepararPayloadCompleto(
          uuid, row,
          dbHelper: db);
      final fPayload = EdanSyncEngineV2.firmaDePayload(payload);
      final fDb =
          await EdanStoreV2.firmaContenido(database, uuid);
      expect(fPayload, fDb,
          reason: 'misma canonicalización en motor y store');
    });

    test('firmaDePayload == firmaContenido con checks locales (afectado/'
        'marcado/rango legacy)', () async {
      const uuid = 'u-par-checks';
      await _seedConChecks(uuid);
      final database = await db.database;
      final row = (await database.query('formularios',
          where: 'uuid_edan_localidad = ?',
          whereArgs: [uuid])).first;
      final payload = await EdanSyncEngineV2.prepararPayloadCompleto(
          uuid, row,
          dbHelper: db);
      final fPayload = EdanSyncEngineV2.firmaDePayload(payload);
      final fDb =
          await EdanStoreV2.firmaContenido(database, uuid);
      expect(fPayload, fDb,
          reason: 'las claves locales que el wire borra tampoco entran a la '
              'firma: sin esto el confirm nunca declaraba limpio y el '
              'contador quedaba pegado en 1');
    });

    test('el check local no mueve la firma; el contenido sí', () async {
      const uuid = 'u-checks-mov';
      await _seedConChecks(uuid);
      final database = await db.database;
      final antes =
          await EdanStoreV2.firmaContenido(database, uuid);
      // Cambiar solo `afectado` no cambia nada que viaje: no ensucia.
      await database.update(
        'filas_seccion',
        {
          'datos_json': jsonEncode({
            'uuid_registro': '11111111-0000-4000-8000-00000000sb01',
            'tipo': 'AGUA',
            'afectado': false,
          })
        },
        where: 'uuid_registro = ?',
        whereArgs: ['11111111-0000-4000-8000-00000000sb01'],
      );
      expect(await EdanStoreV2.firmaContenido(database, uuid), antes);
      // Cambiar un dato que SÍ viaja ensucia.
      await database.update(
        'filas_seccion',
        {
          'datos_json': jsonEncode({
            'uuid_registro': '11111111-0000-4000-8000-00000000sb01',
            'tipo': 'ELECTRICIDAD',
            'afectado': false,
          })
        },
        where: 'uuid_registro = ?',
        whereArgs: ['11111111-0000-4000-8000-00000000sb01'],
      );
      expect(await EdanStoreV2.firmaContenido(database, uuid), isNot(antes));
    });

    test('la fila legacy sin id no rompe la paridad (el padding de catálogo '
        'la descarta en ambos lados)', () async {
      const uuid = 'u-rango-legacy';
      await _seedRica(uuid);
      final database = await db.database;
      // Impacto solo con `rango` (sin `id_grupo_etario`): el set exacto 1-4
      // lo descarta del payload Y de la firma (motor 2521 y réplica del
      // store 3550). La paridad debe sostenerse igual.
      await database.insert('filas_seccion', {
        'uuid_registro': '33333333-0000-4000-8000-00000000im03',
        'uuid_edan_localidad': uuid,
        'tipo': 'impacto-poblacion',
        'datos_json': jsonEncode({
          'uuid_registro': '33333333-0000-4000-8000-00000000im03',
          'rango': '0 a 14 años',
        }),
        'estado_sync': 'pendiente',
      });
      final row = (await database.query('formularios',
          where: 'uuid_edan_localidad = ?',
          whereArgs: [uuid])).first;
      final payload = await EdanSyncEngineV2.prepararPayloadCompleto(
          uuid, row,
          dbHelper: db);
      expect(
          EdanSyncEngineV2.firmaDePayload(payload),
          await EdanStoreV2.firmaContenido(database, uuid));
      // Como la fila no viaja, editar su rango no cambia nada enviado:
      // no ensucia (consistente en ambos lados).
      final antes =
          await EdanStoreV2.firmaContenido(database, uuid);
      await database.update(
        'filas_seccion',
        {
          'datos_json': jsonEncode({
            'uuid_registro': '33333333-0000-4000-8000-00000000im03',
            'rango': '15 a 64 años',
          })
        },
        where: 'uuid_registro = ?',
        whereArgs: ['33333333-0000-4000-8000-00000000im03'],
      );
      expect(await EdanStoreV2.firmaContenido(database, uuid), antes,
          reason: 'la fila sin id no entra al payload ni a la firma');
    });

    test('cualquier cambio en las 14 secciones mueve la firma', () async {
      const uuid = 'u-mueve';
      await _seedRica(uuid);
      final database = await db.database;
      final antes =
          await EdanStoreV2.firmaContenido(database, uuid);
      await database.update(
        'filas_seccion',
        {
          'datos_json': jsonEncode({
            'uuid_registro': 'aaaaaaaa-0000-4000-8000-00000000c011',
            'tipo_cultivo': 'MAIZ',
            'hectareas_afectadas': 9,
          })
        },
        where: 'uuid_registro = ?',
        whereArgs: ['aaaaaaaa-0000-4000-8000-00000000c011'],
      );
      final despues =
          await EdanStoreV2.firmaContenido(database, uuid);
      expect(despues, isNot(antes));
    });

    test('el espejo fotografia no mueve la firma', () async {
      const uuid = 'u-espejo';
      await _seedRica(uuid);
      final database = await db.database;
      final antes =
          await EdanStoreV2.firmaContenido(database, uuid);
      await database.update(
        'filas_seccion',
        {
          'datos_json': jsonEncode({
            'uuid_registro': 'aaaaaaaa-0000-4000-8000-00000000c011',
            'tipo_cultivo': 'MAIZ',
            'hectareas_afectadas': 5,
            'fotografia': '/uploads/nueva.jpg',
          })
        },
        where: 'uuid_registro = ?',
        whereArgs: ['aaaaaaaa-0000-4000-8000-00000000c011'],
      );
      expect(await EdanStoreV2.firmaContenido(database, uuid), antes);
    });
  });

  group('dirty derivado', () {
    test('guardar sin cambios no ensucia; cambiar sí; revertir limpia',
        () async {
      final store = EdanStoreV2(db: db);
      final loc = EdanLocalidad(
        nombre: 'Loc D',
        idTipoEvento: 1,
        uuidEdanLocalidad: 'u-dirty',
      );
      await store.guardarFormulario(loc, usuarioId: 1);
      expect(await _dirty('u-dirty'), 1,
          reason: 'nuevo sin enviar: dirty');

      // Simula confirmación: enviada = actual.
      final database = await db.database;
      final firma =
          await EdanStoreV2.firmaContenido(database, 'u-dirty');
      await database.update(
          'formularios',
          {
            'firma_enviada': firma,
            'firma_contenido': firma,
            'pendiente_push': 0,
          },
          where: 'uuid_edan_localidad = ?',
          whereArgs: ['u-dirty']);

      // Re-guardar idéntico: sigue limpio.
      await store.guardarFormulario(loc, usuarioId: 1);
      expect(await _dirty('u-dirty'), 0,
          reason: 'guardar sin cambios no viaja');

      // Cambio real: ensucia.
      loc.nombre = 'Loc D editada';
      await store.guardarFormulario(loc, usuarioId: 1);
      expect(await _dirty('u-dirty'), 1);

      // Revertir al contenido enviado: limpia solo.
      loc.nombre = 'Loc D';
      await store.guardarFormulario(loc, usuarioId: 1);
      expect(await _dirty('u-dirty'), 0,
          reason: 'volver al estado enviado no tiene nada que mandar');
    });

    test('carrera: save durante el push conserva el dirty', () async {
      const uuid = 'u-race';
      await _seedRica(uuid);
      final client = MockClient((req) async {
        final path = req.url.path;
        if (req.method == 'POST' &&
            path.endsWith('/formularios/completo')) {
          // El usuario guarda MIENTRAS el push vuela.
          await (await db.database).update(
            'formularios',
            {'localidad': 'Editada en carrera'},
            where: 'uuid_edan_localidad = ?',
            whereArgs: [uuid],
          );
          return _ok({'uuid_edan_localidad': uuid});
        }
        if (req.method == 'GET' && path.contains('/completo')) {
          return _ok({'uuid_edan_localidad': uuid});
        }
        if (req.method == 'GET' && path.endsWith('/sync/pull')) {
          return _ok({'watermark': 'wm'});
        }
        if (req.method == 'POST' && path.endsWith('/sync/ack')) {
          return _ok();
        }
        return http.Response('{"success":false}', 404,
            headers: {'content-type': 'application/json'});
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(resumen.exito, isTrue);
      expect(await _dirty(uuid), 1,
          reason: 'el cambio concurrente no se pierde: viaja en el próximo');
    });
  });
}
