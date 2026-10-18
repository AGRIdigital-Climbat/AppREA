/// Normalización del `GET /formularios/{uuid}/completo` hacia las tablas
/// fila-a-fila (`_normalizarDocCompleto`).
///
/// Fija el contrato que resuelve el bug "tengo datos y el JSON/preview dice
/// que no": el documento anidado del servidor (cabecera + nodo `grupos` + las
/// 14 secciones + `fotos[]`) debe poblar `filas_seccion`/`viviendas`/
/// `fotografias` —la MISMA fuente que lee `prepararPayloadCompleto`— y dejar
/// el documento CRUDO en `formularios.datos_json_servidor` (v34). Sin esta
/// normalización, las filas vivían solo en el snapshot `datos_json` y el
/// payload salía vacío.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:rea/services/api/edan_api_v2.dart';
import 'package:rea/services/database_helper.dart';
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
    dir = await Directory.systemTemp.createTemp('edan_get_completo_norm');
    DatabaseHelper.rutaDePrueba = p.join(dir.path, 'test.db');
  });

  tearDown(() async {
    await db.cerrarParaPrueba();
    DatabaseHelper.rutaDePrueba = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  EdanApiV2 _api(MockClient client) => EdanApiV2(
        httpClient: client,
        baseUrl: 'https://api.test/api/v2/edan',
      );

  /// Documento `/completo` realista: cabecera + nodo `grupos` (9 `grup_*`) +
  /// tres secciones (1:N `danos_agricultura`, 1:1 `danos_vivienda` con
  /// `viviendas[]` anidadas y 1:1 `necesidad_salud`) + `fotos[]`.
  Map<String, dynamic> _doc() => {
        'uuid_edan_localidad': 'u-n1',
        'id_edan_localidad': 777,
        'localidad': 'LOC_NORM',
        'grupos': {
          'grup_agropecuario': true,
          'grup_vivienda': true,
          'grup_salud': true,
        },
        'imp_danos_agricultura': true,
        'imp_danos_vivienda': true,
        'imp_necesidad_salud': true,
        'danos_agricultura': [
          {'uuid_registro': 'aaaaaaaa-1111-4111-8111-111111111111', 'cultivo': 'Maiz', 'hectareas': 3},
        ],
        'danos_vivienda': {
          'uuid_registro': 'bbbbbbbb-2222-4222-8222-222222222222',
          'tipo_dano': 'PARCIAL',
          'viviendas': [
            {
              'uuid_registro': 'cccccccc-3333-4333-8333-333333333333',
              'uuid_dano_vivienda': 'bbbbbbbb-2222-4222-8222-222222222222',
              'tipo_dano': 'PARCIAL',
              'coordenada_lat': -16.5,
              'coordenada_lon': -68.1,
            },
          ],
        },
        'necesidad_salud': {'uuid_registro': 'dddddddd-4444-4444-8444-444444444444', 'centros': 2},
        'fotos': [
          {
            'uuid_fotografia': 'foto-1',
            'tipo_entidad': 'danos_agricultura',
            'uuid_registro': 'aaaaaaaa-1111-4111-8111-111111111111',
            'ruta_archivo': '/uploads/x/foto1.jpg',
            'borrado_logico': false,
            'sha256': 'abc123',
          },
        ],
      };

  group('aplicarDocumentoCompleto → normalización', () {
    test('puebla filas_seccion, viviendas, fotografias, grupos y la caché '
        'datos_json_servidor', () async {
      final doc = _doc();
      await EdanSyncEngineV2(api: _api(MockClient((_) async {
        throw StateError('no debe llamar a la red');
      })), db: db).aplicarDocumentoCompleto(doc);

      final database = await db.database;

      // 1) La cabecera guarda el documento CRUDO en datos_json_servidor (v34).
      final form = await database.query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-n1']);
      expect(form, hasLength(1));
      expect(form.first['datos_json_servidor'], jsonEncode(doc),
          reason: 'la pestaña GET lee la caché del doc crudo');
      expect(form.first['id_server'], 777);

      // 2) Las secciones anidadas → filas_seccion (la verdad local del POST).
      final filas = await database.query('filas_seccion',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-n1']);
      final porTipo = {
        for (final f in filas) f['tipo'] as String: f['uuid_registro']
      };
      expect(porTipo['danos-agricultura'], 'aaaaaaaa-1111-4111-8111-111111111111');
      expect(porTipo['necesidad-salud'], 'dddddddd-4444-4444-8444-444444444444');
      expect(porTipo['danos-vivienda'], 'bbbbbbbb-2222-4222-8222-222222222222');
      // El padre danos-vivienda NO conserva las hijas anidadas (viven en la
      // tabla `viviendas`, igual que las relee `prepararPayloadCompleto`).
      final padre = filas.firstWhere((f) => f['tipo'] == 'danos-vivienda');
      expect(jsonDecode(padre['datos_json'] as String),
          isNot(contains('viviendas')));

      // 3) `danos_vivienda.viviendas[]` → tabla `viviendas`.
      final vivs = await database.query('viviendas',
          where: 'uuid_dano_vivienda = ?', whereArgs: ['bbbbbbbb-2222-4222-8222-222222222222']);
      expect(vivs, hasLength(1));
      expect(vivs.first['uuid_registro'], 'cccccccc-3333-4333-8333-333333333333');
      expect(vivs.first['coordenada_lat'], -16.5);

      // 4) `fotos[]` → tabla `fotografias`.
      final fotos = await database.query('fotografias',
          where: 'uuid_fotografia = ?', whereArgs: ['foto-1']);
      expect(fotos, hasLength(1));
      expect(fotos.first['ruta_servidor'], '/uploads/x/foto1.jpg');
      expect(fotos.first['tipo_entidad'], 'danos_agricultura');

      // 5) Nodo `grupos` → caché grup_servidor (badges del listado).
      final grupos = await database.query('grupos_local',
          where: 'uuid_edan_localidad = ? AND grup_servidor = 1',
          whereArgs: ['u-n1']);
      expect(
        grupos.map((g) => g['grupo']).toSet(),
        containsAll(['grupAgropecuario', 'grupVivienda', 'grupSalud']),
      );
    });

    test('el payload /completo YA ve las filas normalizadas (bug resuelto)',
        () async {
      final doc = _doc();
      await EdanSyncEngineV2(
        api: _api(MockClient((_) async => http.Response('{}', 500))),
        db: db,
      ).aplicarDocumentoCompleto(doc);

      final database = await db.database;
      final row = (await database.query('formularios',
              where: 'uuid_edan_localidad = ?', whereArgs: ['u-n1']))
          .first;
      final payload = await EdanSyncEngineV2.prepararPayloadCompleto(
        'u-n1',
        row,
        dbHelper: db,
      );

      // Antes del fix, `imp_danos_agricultura` salía en false con la sección
      // vacía (las filas vivían solo en datos_json). Ahora sale true CON datos.
      expect(payload['imp_danos_agricultura'], isTrue);
      expect(payload['imp_danos_vivienda'], isTrue);
      expect(payload['imp_necesidad_salud'], isTrue);
      expect(payload['imp_impacto_poblacion'], isFalse);

      expect(payload['danos_agricultura'], isA<List>());
      expect((payload['danos_agricultura'] as List).first['cultivo'], 'Maiz');

      // 1:1 → objeto único con viviendas[] anidadas y coords del padre nulas.
      final viv = payload['danos_vivienda'] as Map<String, dynamic>;
      expect(viv['coordenada_lat'], isNull,
          reason: '§20.4: con hijas, las coords del padre se anulan');
      expect((viv['viviendas'] as List).first['uuid_registro'], 'cccccccc-3333-4333-8333-333333333333');

      expect(payload['necesidad_salud'], isA<Map<String, dynamic>>(),
          reason: 'sección 1:1 sale como objeto, no lista');
    });

    test('NO toca una localidad sucia (pendiente_push=1)', () async {
      final database = await db.database;
      await database.insert('formularios', {
        'uuid_edan_localidad': 'u-n2',
        'localidad': 'SUCIA',
        'pendiente_push': 1,
      });

      await EdanSyncEngineV2(
        api: _api(MockClient((_) async => http.Response('{}', 500))),
        db: db,
      ).aplicarDocumentoCompleto({
        'uuid_edan_localidad': 'u-n2',
        'localidad': 'DEL_SERVER',
        'danos_agricultura': [
          {'uuid_registro': 'f-agro-2', 'cultivo': 'Cebada'}
        ],
      });

      final filas = await database.query('filas_seccion',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-n2']);
      expect(filas, isEmpty,
          reason: 'un borrador en edición no se pisa con el pull');
      final form = (await database.query('formularios',
              where: 'uuid_edan_localidad = ?', whereArgs: ['u-n2']))
          .first;
      expect(form['localidad'], 'SUCIA');
      expect(form['datos_json_servidor'], isNull);
    });
  });
}