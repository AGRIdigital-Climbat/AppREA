/// Ciclo de vida de fotos V2 (Fase 5): registro con `uuid_fotografia` propio,
/// encolado en `cola_fotos`, borrado persistente (lógico + purga de cola +
/// archivo) y propagación del borrado al servidor (`_pushBorradosFotos`).
///
/// Fija el contrato de §3.5/§16.3: cambiar la foto reemplaza el uuid (no
/// duplica); el borrado de una foto ya subida hace `DELETE /fotografias/{uuid}`
/// y limpia el registro local (404 incluido = idempotente); un 5xx conserva el
/// registro para reintentar.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
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
    dir = await Directory.systemTemp.createTemp('edan_foto_lifecycle');
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

  http.Response _err(int status) => http.Response(
        jsonEncode({'success': false, 'detail': 'err'}),
        status,
        headers: {'content-type': 'application/json'},
      );

  EdanApiV2 _api(MockClient client) => EdanApiV2(
        httpClient: client,
        baseUrl: 'https://api.test/api/v2/edan',
      );

  Future<EdanStoreV2> _store() async {
    await db.database;
    return EdanStoreV2(db: db);
  }

  Future<List<Map<String, Object?>>> _filasFoto(String uuid) async =>
      (await db.database).query('fotografias',
          where: 'uuid_fotografia = ?', whereArgs: [uuid]);

  Future<int> _colaFotos(String uuid) async {
    final rows = await (await db.database).query('cola_fotos',
        where: 'uuid_fotografia = ?', whereArgs: [uuid]);
    return rows.length;
  }

  /// Dueña mínima para derivar el `tipo_entidad` canónico (Etapa 4: el
  /// marcador `'filas_seccion'` ya no se persiste; se deriva de la fila).
  Future<void> _seedDuena({
    String loc = 'loc-1',
    String fila = 'fila-1',
    String tipo = 'danos-viales',
  }) async {
    final d = await db.database;
    await d.insert('formularios', {
      'uuid_edan_localidad': loc,
      'localidad': 'L',
      });
    await d.insert('filas_seccion', {
      'uuid_registro': fila,
      'uuid_edan_localidad': loc,
      'tipo': tipo,
      'datos_json': '{}',
    });
  }

  group('EdanStoreV2 · fotos', () {
    test('registrarFoto asigna uuid propio y persiste la fila', () async {
      final store = await _store();
      await _seedDuena();
      final foto = EdanFoto(
        ruta: p.join(dir.path, 'no-existe.jpg'),
        latitud: 1,
        longitud: 2,
        precision: 3,
      );
      expect(foto.uuidFotografia, isNull);

      await store.registrarFoto(foto, 'filas_seccion', 'fila-1');

      expect(foto.uuidFotografia, isNotNull);
      expect(foto.uuidFotografia, isNotEmpty);
      expect(foto.tipoEntidad, 'danos_viales',
          reason: 'el marcador local se deriva a la tabla canónica');
      expect(foto.uuidRegistro, 'fila-1');

      final rows = await _filasFoto(foto.uuidFotografia!);
      expect(rows, hasLength(1));
      expect(rows.first['uuid_registro'], 'fila-1');
      expect(rows.first['tipo_entidad'], 'danos_viales');
      expect(rows.first['borrado_logico'], 0);
    });

    test('registrarFoto resuelve uuid_edan_localidad desde la cabecera',
        () async {
      final store = await _store();
      await _seedDuena();
      final foto =
          EdanFoto(ruta: 'x.jpg', latitud: 0, longitud: 0, precision: 0);

      await store.registrarFoto(foto, 'danos_viales', 'fila-1');

      final rows = await _filasFoto(foto.uuidFotografia!);
      expect(rows.first['uuid_edan_localidad'], 'loc-1');
    });

    test('encolarFoto inserta en cola_fotos como pendiente', () async {
      final store = await _store();
      final foto = EdanFoto(
        ruta: 'x.jpg',
        latitud: 0,
        longitud: 0,
        precision: 0,
        uuidFotografia: 'f-cola',
        tipoEntidad: 'filas_seccion',
        uuidRegistro: 'fila-1',
      );

      await store.encolarFoto(foto);

      final items = await store.listarColaFotos();
      expect(items, hasLength(1));
      expect(items.first.uuidFotografia, 'f-cola');
      expect(items.first.estado, 'pendiente');
    });

    test(
        'foto de vivienda 1:N se registra y encola con tipo_entidad=vivienda '
        '(dueña = uuid de la vivienda, no de la fila)', () async {
      final store = await _store();
      // Réplica del contrato que usa EdanPage08._fotoVivienda tras P4.
      final foto = EdanFoto(
        ruta: p.join(dir.path, 'viv.jpg'),
        latitud: -16.5,
        longitud: -68.1,
        precision: 5,
      );

      await store.registrarFoto(foto, 'vivienda', 'viv-uuid-1');
      await store.encolarFoto(foto);

      expect(foto.tipoEntidad, 'vivienda');
      expect(foto.uuidRegistro, 'viv-uuid-1');

      final fotografias = await _filasFoto(foto.uuidFotografia!);
      expect(fotografias, hasLength(1));
      expect(fotografias.first['tipo_entidad'], 'vivienda');
      expect(fotografias.first['uuid_registro'], 'viv-uuid-1');

      final items = await store.listarColaFotos();
      expect(items, hasLength(1));
      expect(items.first.uuidFotografia, foto.uuidFotografia);
      expect(items.first.estado, 'pendiente');
    });

    test(
        'borrarFoto marca borrado_logico, purga la cola y borra el archivo',
        () async {
      final store = await _store();
      await _seedDuena();
      final archivo = File(p.join(dir.path, 'foto.jpg'));
      await archivo.writeAsBytes([1, 2, 3]);
      final foto = EdanFoto(
        ruta: archivo.path,
        latitud: 0,
        longitud: 0,
        precision: 0,
        uuidFotografia: 'f-del',
      );
      await store.registrarFoto(foto, 'filas_seccion', 'fila-1');
      await store.encolarFoto(foto);

      await store.borrarFoto('f-del');

      final rows = await _filasFoto('f-del');
      expect(rows, hasLength(1), reason: 'el registro se conserva con borrado lógico');
      expect(rows.first['borrado_logico'], 1);

      final cola = await (await db.database).query('cola_fotos',
          where: 'uuid_fotografia = ?', whereArgs: ['f-del']);
      expect(cola, isEmpty, reason: 'la subida pendiente se cancela');
      expect(archivo.existsSync(), isFalse, reason: 'el archivo local se borra');
    });

    test('cambiar la foto (borrar previa + registrar nueva) reemplaza el uuid',
        () async {
      final store = await _store();
      await _seedDuena();
      final previa = EdanFoto(
        ruta: 'a.jpg',
        latitud: 0,
        longitud: 0,
        precision: 0,
        uuidFotografia: 'f-previa',
      );
      await store.registrarFoto(previa, 'filas_seccion', 'fila-1');

      // Flujo de capturarFoto: borra la previa y registra la nueva.
      await store.borrarFoto('f-previa');
      final nueva = EdanFoto(
        ruta: 'b.jpg',
        latitud: 0,
        longitud: 0,
        precision: 0,
      );
      await store.registrarFoto(nueva, 'filas_seccion', 'fila-1');

      final previas = await _filasFoto('f-previa');
      expect(previas.first['borrado_logico'], 1);
      final nuevas = await _filasFoto(nueva.uuidFotografia!);
      expect(nuevas, hasLength(1));
      expect(nueva.uuidFotografia, isNot('f-previa'));
    });
  });

  group('engine · _pushBorradosFotos', () {
    Future<void> seedFotoSubida(String uuid) => db.database.then((d) => d.insert(
          'fotografias',
          {
            'uuid_fotografia': uuid,
            'uuid_edan_localidad': 'loc',
            'tipo_entidad': 'filas_seccion',
            'uuid_registro': 'fila',
            'ruta_local': null,
            'ruta_servidor': 'https://cdn/f.jpg',
            'borrado_logico': 1,
          },
        ));

    test('DELETE exitoso elimina el registro local', () async {
      await seedFotoSubida('f-borrada');
      String? deletePath;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _ok({'watermark': 'wm'});
        }
        if (req.method == 'DELETE') {
          deletePath = req.url.path;
          return _ok();
        }
        return _ok();
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(deletePath, contains('/fotografias/f-borrada'));
      expect(await _filasFoto('f-borrada'), isEmpty);
    });

    test('404 también limpia el registro local (idempotente)', () async {
      await seedFotoSubida('f-404');
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _ok({'watermark': 'wm'});
        }
        if (req.method == 'DELETE') return _err(404);
        return _ok();
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(await _filasFoto('f-404'), isEmpty);
    });

    test('error transitorio (500) conserva el registro para reintentar',
        () async {
      await seedFotoSubida('f-500');
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _ok({'watermark': 'wm'});
        }
        if (req.method == 'DELETE') return _err(500);
        return _ok();
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final rows = await _filasFoto('f-500');
      expect(rows, hasLength(1));
      expect(rows.first['borrado_logico'], 1);
    });

    test('una foto local sin ruta_servidor no genera DELETE', () async {
      // Aún no subida: el borrado lo gestiona el store, no el engine.
      await db.database.then((d) => d.insert('fotografias', {
            'uuid_fotografia': 'f-local',
            'uuid_edan_localidad': 'loc',
            'tipo_entidad': 'filas_seccion',
            'uuid_registro': 'fila',
            'ruta_local': null,
            'ruta_servidor': null,
            'borrado_logico': 1,
          }));
      var deletes = 0;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _ok({'watermark': 'wm'});
        }
        if (req.method == 'DELETE') {
          deletes++;
          return _ok();
        }
        return _ok();
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(deletes, 0);
      expect(await _filasFoto('f-local'), hasLength(1));
    });
  });

  group('descarga robusta + fantasmas (2026-10-16)', () {
    const fotoBytes = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46];
    // sha256 de fotoBytes.
    const fotoSha =
        'eb7e0381d519c6a257584ed4a69cf3ae4e4cfc7351cacb301ac646c0df5e8aca';

    Future<Directory> _dirFotos() =>
        Directory.systemTemp.createTemp('edan_fotos_rob');

    MockClient _clienteDescarga({
      int fotoStatus = 200,
      List<int>? bytes,
      void Function()? onBytes,
    }) {
      return MockClient((req) async {
        final path = req.url.path;
        if (req.method == 'GET' && path.endsWith('/sync/pull')) {
          return _ok({'watermark': 'wm-d'});
        }
        if (req.method == 'POST' && path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'GET' && path == '/uploads/d.jpg') {
          onBytes?.call();
          if (fotoStatus != 200) return _err(fotoStatus);
          return http.Response.bytes(bytes ?? fotoBytes, 200,
              headers: {'content-type': 'image/jpeg'});
        }
        return _err(404);
      });
    }

    Future<void> _seedDescarga(String uuid) async {
      final d = await db.database;
      await d.insert('fotografias', {
        'uuid_fotografia': uuid,
        'uuid_edan_localidad': 'loc-d',
        'tipo_entidad': 'danos_agricultura',
        'uuid_registro': 'fila-d',
        'ruta_servidor': '/uploads/d.jpg',
        'sha256': fotoSha,
        'borrado_logico': 0,
        'upload_state': 'pending',
      });
    }

    test('REPLACE del pull preserva ruta_local (no re-descarga)', () async {
      final dirFotos = await _dirFotos();
      addTearDown(() {
        if (dirFotos.existsSync()) dirFotos.deleteSync(recursive: true);
      });
      await _seedDescarga('f-pres');
      var bajas = 0;
      final client = _clienteDescarga(onBytes: () => bajas++);
      Future<void> correr() => EdanSyncEngineV2(
            api: _api(client),
            db: db,
            dirFotos: dirFotos,
          ).sincronizar();

      await correr();
      expect(bajas, 1);
      await correr();
      expect(bajas, 1,
          reason: 'ruta_local preservada: el pull no la borra ni re-baja');
    });

    test('sha distinto no guarda archivo y suma intento', () async {
      final dirFotos = await _dirFotos();
      addTearDown(() {
        if (dirFotos.existsSync()) dirFotos.deleteSync(recursive: true);
      });
      await _seedDescarga('f-sha');
      final client = _clienteDescarga(bytes: [1, 2, 3]);

      await EdanSyncEngineV2(
        api: _api(client),
        db: db,
        dirFotos: dirFotos,
      ).sincronizar();

      final rows = await _filasFoto('f-sha');
      expect(rows.first['ruta_local'], anyOf(isNull, ''));
      expect(rows.first['intentos_descarga'], 1);
      expect(rows.first['last_error'], contains('sha256'));
    });

    test('al 3er fallo queda failed visible y no reintenta', () async {
      final dirFotos = await _dirFotos();
      addTearDown(() {
        if (dirFotos.existsSync()) dirFotos.deleteSync(recursive: true);
      });
      await _seedDescarga('f-fail');
      var bajas = 0;
      final client = _clienteDescarga(
          fotoStatus: 500, onBytes: () => bajas++);
      Future<void> correr() => EdanSyncEngineV2(
            api: _api(client),
            db: db,
            dirFotos: dirFotos,
          ).sincronizar();

      // Forzar intentos sin esperar backoff.
      for (var i = 0; i < 3; i++) {
        await (await db.database).update(
            'fotografias', {'fecha_proximo_intento': null},
            where: 'uuid_fotografia = ?', whereArgs: ['f-fail']);
        await correr();
      }

      final rows = await _filasFoto('f-fail');
      expect(rows.first['intentos_descarga'], 3);
      expect(rows.first['last_error'], contains('3 intentos'));
      final antes = bajas;
      await correr();
      expect(bajas, antes,
          reason: 'con tope alcanzado no martilla al servidor');
    });

    test('fantasma pending sin cola se re-encola y sube', () async {
      await _seedDuena(loc: 'loc-g', fila: 'fila-g', tipo: 'danos-agricultura');
      await (await db.database).update(
          'filas_seccion', {'estado_sync': 'confirmado'},
          where: 'uuid_registro = ?', whereArgs: ['fila-g']);
      final arch = File(p.join(dir.path, 'g.jpg'));
      await arch.writeAsBytes([7, 7, 7]);
      await (await db.database).insert('fotografias', {
        'uuid_fotografia': 'f-ghost',
        'uuid_edan_localidad': 'loc-g',
        'tipo_entidad': 'danos_agricultura',
        'uuid_registro': 'fila-g',
        'ruta_local': arch.path,
        'ruta_servidor': null,
        'borrado_logico': 0,
        'upload_state': 'pending',
      });
      var subidas = 0;
      final client = MockClient((req) async {
        final path = req.url.path;
        if (req.method == 'GET' && path.endsWith('/sync/pull')) {
          return _ok({'watermark': 'wm'});
        }
        if (req.method == 'POST' && path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' && path.endsWith('/fotografias')) {
          subidas++;
          return _ok({
            'uuid_fotografia': 'f-ghost',
            'ruta_archivo': '/uploads/g.jpg',
            'fila_dueña': {
              'uuid_registro': 'fila-g',
              'fotografia': '/uploads/g.jpg',
            },
          });
        }
        return _err(404);
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(subidas, 1,
          reason: 'el fantasma se re-encola solo y sube');
      final rows = await _filasFoto('f-ghost');
      expect(rows.first['ruta_servidor'], '/uploads/g.jpg');
    });

    test('foto bajada no entra a cola de subida', () async {
      await (await db.database).insert('fotografias', {
        'uuid_fotografia': 'f-down',
        'uuid_edan_localidad': 'loc-d',
        'tipo_entidad': 'danos_agricultura',
        'uuid_registro': 'fila-d',
        'ruta_local': null,
        'ruta_servidor': '/uploads/d.jpg',
        'borrado_logico': 0,
        'upload_state': 'synced',
      });
      final client = _clienteDescarga();

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(await _colaFotos('f-down'), 0,
          reason: 'lo bajado no se re-encola para subir');
    });
  });

  group('LWW 1-activa-por-fila (2026-10-16)', () {
    Future<String> _archivo(String nombre) async {
      final f = File(p.join(dir.path, nombre));
      await f.writeAsBytes([1, 2, 3]);
      return f.path;
    }

    Future<EdanFoto> _nueva(String ruta) async => EdanFoto(
          ruta: ruta,
          latitud: 0,
          longitud: 0,
          precision: 0,
        );

    test('registrarFoto purga la anterior nunca subida', () async {
      final store = await _store();
      await _seedDuena();
      final a = await _nueva(await _archivo('a.jpg'));
      await store.registrarFoto(a, 'danos_viales', 'fila-1');
      final b = await _nueva(await _archivo('b.jpg'));
      await store.registrarFoto(b, 'danos_viales', 'fila-1');

      expect(await _filasFoto(a.uuidFotografia!), isEmpty,
          reason: 'la anterior sin subir se purga, no se marca');
      expect(await File(a.ruta).exists(), isFalse);
      expect(await _filasFoto(b.uuidFotografia!), hasLength(1));
    });

    test('registrarFoto marca borrado_logico a la anterior ya subida',
        () async {
      final store = await _store();
      await _seedDuena();
      final a = await _nueva(await _archivo('a2.jpg'));
      await store.registrarFoto(a, 'danos_viales', 'fila-1');
      // Simula subida confirmada de A.
      await (await db.database).update(
        'fotografias',
        {'ruta_servidor': 'https://cdn/a.jpg', 'upload_state': 'synced'},
        where: 'uuid_fotografia = ?',
        whereArgs: [a.uuidFotografia],
      );
      final b = await _nueva(await _archivo('b2.jpg'));
      await store.registrarFoto(b, 'danos_viales', 'fila-1');

      final rowsA = await _filasFoto(a.uuidFotografia!);
      expect(rowsA, hasLength(1));
      expect(rowsA.first['borrado_logico'], 1,
          reason: 'subida → DELETE se propaga, no purga directa');
      expect(await File(a.ruta).exists(), isFalse);
    });

    test('pull retira la sincronizada anterior y respeta la pendiente',
        () async {
      final d = await db.database;
      await _seedDuena(loc: 'loc-9', fila: 'fila-9', tipo: 'danos-agricultura');
      final vieja = await File(p.join(dir.path, 'vieja.jpg'))
        ..writeAsBytes([9]);
      await d.insert('fotografias', {
        'uuid_fotografia': 'f-vieja',
        'uuid_edan_localidad': 'loc-9',
        'tipo_entidad': 'danos_agricultura',
        'uuid_registro': 'fila-9',
        'ruta_local': vieja.path,
        'ruta_servidor': 'https://cdn/vieja.jpg',
        'borrado_logico': 0,
        'upload_state': 'synced',
      });
      // Pendiente local del mismo dueño: NO se toca (ganará al subir).
      await d.insert('fotografias', {
        'uuid_fotografia': 'f-pend',
        'uuid_edan_localidad': 'loc-9',
        'tipo_entidad': 'danos_agricultura',
        'uuid_registro': 'fila-9',
        'ruta_local': null,
        'ruta_servidor': null,
        'borrado_logico': 0,
        'upload_state': 'pending',
      });
      final client = MockClient((req) async {
        final path = req.url.path;
        if (req.method == 'GET' && path.endsWith('/sync/pull')) {
          return _ok({
            'watermark': 'wm',
            'formularios': [],
            'secciones': [],
            'viviendas': [],
            'fotos': [
              {
                'uuid_fotografia': 'f-nueva',
                'uuid_edan_localidad': 'loc-9',
                'tipo_entidad': 'danos_agricultura',
                'uuid_registro': 'fila-9',
                'ruta_archivo': 'https://cdn/nueva.jpg',
                'borrado_logico': false,
              }
            ],
            'tombstones': [],
          });
        }
        return _ok();
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(await _filasFoto('f-nueva'), hasLength(1));
      expect(await _filasFoto('f-vieja'), isEmpty,
          reason: 'reemplazo desde otro equipo se retira local');
      expect(await vieja.exists(), isFalse);
      expect(await _filasFoto('f-pend'), hasLength(1),
          reason: 'la pendiente local sobrevive al pull');
    });
  });
}