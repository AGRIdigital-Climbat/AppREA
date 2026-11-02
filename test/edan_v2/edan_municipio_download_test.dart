/// `EdanSyncEngineV2.descargarMunicipio` — descarga V2 del municipio completo
/// (mapa rol 6). Fija el contrato: pagina `GET /formularios?id_municipio=
/// &todos=false&modo=completo` (documentos COMPLETOS con `cabecera`, sin
/// `GET /formularios/{uuid}/completo` por uuid) y aplica con diff LOCAL por
/// `fecha_modificacion` (sin watermark); NO pisa sucios; NO toca el watermark
/// personal ni hace ack; un error de página no aborta lo ya bajado; el
/// resultado queda en `formularios` con `id_municipio` + filas de sección (las
/// coordenadas que pinta el mapa).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
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
    dir = await Directory.systemTemp.createTemp('edan_municipio_download');
    DatabaseHelper.rutaDePrueba = p.join(dir.path, 'test.db');
  });

  tearDown(() async {
    await db.cerrarParaPrueba();
    DatabaseHelper.rutaDePrueba = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  http.Response _pagina(List<Map<String, dynamic>> items, int total) =>
      http.Response(
        jsonEncode({
          'success': true,
          'data': {'items': items, 'total': total},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );

  http.Response _noEncontrado() =>
      http.Response(jsonEncode({'success': false, 'detail': 404}), 404,
          headers: {'content-type': 'application/json'});

  EdanApiV2 _api(MockClient client) => EdanApiV2(
        httpClient: client,
        baseUrl: 'https://api.test/api/v2/edan',
      );

  /// Documento de municipio EN LA FORMA DEL SERVIDOR (cabecera anidada +
  /// secciones al nivel superior) con una fila de agricultura que trae
  /// coordenadas (la fuente de puntos del mapa).
  Map<String, dynamic> _doc(String uuid, String fm) => {
        'cabecera': {
          'uuid_edan_localidad': uuid,
          'localidad': 'LOC_$uuid',
          'id_municipio': 70101,
          'id_usuario': 55,
          'fecha_modificacion': fm,
          'imp_danos_agricultura': true,
          'grup_agropecuario': true,
        },
        'danos_agricultura': [
          {
            'uuid_registro': 'fila-$uuid',
            'cultivo': 'Maiz',
            'coordenada_lat': -16.5,
            'coordenada_lon': -68.1,
          },
        ],
      };

  Future<void> _seedFormulario(String uuid,
          {int municipio = 70101,
          String fm = 'fm-local',
          int pendientePush = 0}) =>
      db.database.then((d) => d.insert('formularios', {
            'uuid_edan_localidad': uuid,
            'localidad': 'LOCAL_$uuid',
            'id_municipio': municipio,
            'fecha_modificacion': fm,
            'pendiente_push': pendientePush,
          }));

  group('descargarMunicipio · diff por fecha_modificacion', () {
    test('baja solo los uuid nuevos/modificados vía GET /formularios con '
        'modo=completo y los deja listados por idMunicipio con filas '
        '(coordenadas) hidratables', () async {
      // m-2 ya está local con la MISMA fm del servidor → no se baja.
      await _seedFormulario('m-2', fm: 'fm-b');

      final rutas = <String>[];
      String? municipioParam;
      String? modoParam;
      String? todosParam;
      String? skipParam;
      final client = MockClient((req) async {
        rutas.add('${req.method} ${req.url.path}');
        if (req.method == 'GET' && req.url.path.endsWith('/formularios')) {
          municipioParam = req.url.queryParameters['id_municipio'];
          modoParam = req.url.queryParameters['modo'];
          todosParam = req.url.queryParameters['todos'];
          skipParam = req.url.queryParameters['skip'];
          return _pagina([_doc('m-1', 'fm-a'), _doc('m-2', 'fm-b')], 2);
        }
        return _noEncontrado();
      });

      final res = await EdanSyncEngineV2(api: _api(client), db: db)
          .descargarMunicipio(70101);

      expect(municipioParam, '70101',
          reason: 'el filtro geográfico V2 va en la query de /formularios');
      expect(modoParam, 'completo',
          reason: 'paridad con el /completo viejo: 14 secciones siempre');
      expect(todosParam, 'false', reason: 'paginado, sin traer todo sin límite');
      expect(skipParam, '0');
      expect(rutas, ['GET /api/v2/edan/formularios'],
          reason: 'UNA sola llamada por página; sin /estados ni /completo');
      expect(res.exito, isTrue);
      expect(res.total, 2);
      expect(res.descargados, 1);
      expect(res.omitidos, 1, reason: 'm-2 con fm idéntica no se baja');
      expect(res.errores, 0);

      // El store municipal (la fuente del mapa) devuelve TODO el municipio:
      // el doc bajado (otro usuario) Y el que ya estaba local.
      final store = EdanStoreV2(db: db);
      final listados = await store.listarFormularios(idMunicipio: 70101);
      expect(
        listados.map((l) => l.uuidEdanLocalidad).toSet(),
        {'m-1', 'm-2'},
        reason: 'el mapa debe ver todo el municipio, no solo lo propio',
      );

      // La fila de m-1 quedó con sus coordenadas en filas_seccion (la fuente
      // de puntos del mapa vía cargarSecciones).
      final filas = await (await db.database).query('filas_seccion',
          where: 'uuid_edan_localidad = ?', whereArgs: ['m-1']);
      expect(filas, hasLength(1));
      expect(filas.first['tipo'], 'danos-agricultura');
      final datos = jsonDecode(filas.first['datos_json'] as String) as Map;
      expect(datos['coordenada_lat'], -16.5);
      expect(datos['coordenada_lon'], -68.1);
    });

    test('NO pisa un doc local sucio (pendiente_push=1) aunque el servidor '
        'traiga otra fecha', () async {
      await _seedFormulario('m-3', fm: 'fm-local', pendientePush: 1);

      final rutas = <String>[];
      final client = MockClient((req) async {
        rutas.add('${req.method} ${req.url.path}');
        if (req.method == 'GET' && req.url.path.endsWith('/formularios')) {
          return _pagina([_doc('m-3', 'fm-servidor')], 1);
        }
        return _noEncontrado();
      });

      final res = await EdanSyncEngineV2(api: _api(client), db: db)
          .descargarMunicipio(70101);

      expect(res.descargados, 0);
      expect(res.omitidos, 1);
      expect(rutas, ['GET /api/v2/edan/formularios'],
          reason: 'sucio: una sola página pedida y nada más');

      final rows = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['m-3']);
      expect(rows.first['fecha_modificacion'], 'fm-local',
          reason: 'el PUT local pendiente gana (LWW)');
      expect(rows.first['localidad'], 'LOCAL_m-3');
    });

    test('un error de red en la segunda página NO pierde la primera '
        '(200 docs ya bajados se conservan)', () async {
      final pagina1 = [for (var i = 0; i < 200; i++) _doc('e-$i', 'fm-$i')];
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/formularios')) {
          final skip = int.parse(req.url.queryParameters['skip'] ?? '0');
          if (skip == 0) return _pagina(pagina1, 250);
          throw const SocketException('sin red');
        }
        return _noEncontrado();
      });

      final res = await EdanSyncEngineV2(api: _api(client), db: db)
          .descargarMunicipio(70101);

      expect(res.exito, isFalse);
      expect(res.descargados, 200,
          reason: 'lo de la página 1 queda aplicado (parcial = sigue)');
      expect(res.errores, 1);
      expect(res.ultimoError, contains('sin red'));

      final count = await (await db.database).rawQuery(
          'SELECT COUNT(*) AS n FROM formularios WHERE id_municipio = 70101');
      expect(count.first['n'], 200);
    });

    test('pagina el listado (250 items → 2 páginas, todos procesados)', () async {
      final items = [
        for (var i = 0; i < 250; i++) _doc('p-$i', 'fm-$i'),
      ];
      final skips = <String>[];
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/formularios')) {
          final skip = int.parse(req.url.queryParameters['skip'] ?? '0');
          final limit = int.parse(req.url.queryParameters['limit'] ?? '200');
          skips.add('$skip');
          final fin = (skip + limit).clamp(0, items.length);
          return _pagina(skip >= items.length ? [] : items.sublist(skip, fin),
              items.length);
        }
        return _noEncontrado();
      });

      final res = await EdanSyncEngineV2(api: _api(client), db: db)
          .descargarMunicipio(70101);

      expect(skips, ['0', '200'], reason: 'dos páginas: 200 + 50');
      expect(res.total, 250);
      expect(res.descargados, 250);
      expect(res.errores, 0);
      final count = await (await db.database).rawQuery(
          'SELECT COUNT(*) AS n FROM formularios WHERE id_municipio = 70101');
      expect(count.first['n'], 250);
    });

    test('NO toca el watermark personal ni hace ack', () async {
      await db.setConfig('sync_watermark_v2', 'wm-personal');
      // El mock responde 404 a TODO lo que no sea GET /formularios: si la
      // descarga intentara un ack u otra llamada, `errores > 0` y el test
      // falla por `exito`.
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/formularios')) {
          return _pagina([_doc('m-6', 'fm-a')], 1);
        }
        return _noEncontrado();
      });

      final res = await EdanSyncEngineV2(api: _api(client), db: db)
          .descargarMunicipio(70101);

      expect(res.descargados, 1);
      expect(res.exito, isTrue,
          reason: 'ninguna llamada fuera de GET /formularios');
      expect(await db.getConfig('sync_watermark_v2'), 'wm-personal',
          reason: 'la descarga del municipio es orthogonal al sync personal');
    });

    test('idMunicipio inválido no toca la red', () async {
      final client = MockClient((_) async {
        throw StateError('no debe llamar a la red');
      });

      final res =
          await EdanSyncEngineV2(api: _api(client), db: db).descargarMunicipio(0);

      expect(res.exito, isFalse);
      expect(res.ultimoError, contains('idMunicipio'));
    });
  });
}
