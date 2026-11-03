/// Motor de sync v2 (`EdanSyncEngineV2`) contra SQLite real (ffi) + `MockClient`.
///
/// Fija el contrato de aplicación del pull (arreglos `formularios`/`secciones`/
/// `viviendas`/`fotos`/`tombstones`, LWW, no pisar sucios, watermark solo tras
/// aplicar+ack) y la máquina de estados de la cola (éxito purga,
/// 4xx → pendiente con backoff, sin red → pendiente). LWW: sin `version`,
/// sin 409, gana el último que llega.
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
import 'package:rea/services/edan_secciones_registry.dart';
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
    dir = await Directory.systemTemp.createTemp('edan_sync_engine');
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

  http.Response _err(int status, [String detail = 'error']) => http.Response(
        jsonEncode({'success': false, 'detail': detail}),
        status,
        headers: {'content-type': 'application/json'},
      );

  http.Response _pull(Map<String, dynamic> data) => http.Response(
        jsonEncode({'success': true, 'data': data}),
        200,
        headers: {'content-type': 'application/json'},
      );

  Map<String, dynamic> _pullVacio() => {'watermark': 'wm-1'};

  EdanApiV2 _api(MockClient client) => EdanApiV2(
        httpClient: client,
        baseUrl: 'https://api.test/api/v2/edan',
      );

  Future<void> _seedFormulario(String uuid,
          {String localidad = 'Loc', String? datosJson, int pendientePush = 0}) =>
      db.database.then((d) => d.insert('formularios', {
            'uuid_edan_localidad': uuid,
            'localidad': localidad,
            
            'pendiente_push': pendientePush,
            if (datosJson != null) 'datos_json': datosJson,
          }));

  Future<void> _seedFila(String uuid, String uuidLoc,
          {String tipo = 'danos_agricultura', String datos = '{"n":1}',
          String estado = 'confirmado'}) =>
      db.database.then((d) => d.insert('filas_seccion', {
            'uuid_registro': uuid,
            'uuid_edan_localidad': uuidLoc,
            'tipo': tipo,
            'datos_json': datos,
            
            'estado_sync': estado,
          }));

  Future<void> _seedCola(String tabla, String uuid, String accion,
          {String estado = 'pendiente'}) =>
      db.database.then((d) => d.insert('cola_sincronizacion', {
            'tabla': tabla,
            'uuid_registro': uuid,
            'accion': accion,
            'estado': estado,
            'intentos': 0,
          }));

  Future<int> _colaFotos(String uuid) async {
    final rows = await (await db.database).query('cola_fotos',
        where: 'uuid_fotografia = ?', whereArgs: [uuid]);
    return rows.length;
  }

  group('pull → apply', () {
    test('aplica un formulario limpio (LWW) y avanza watermark tras ack',
        () async {
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull({
            'watermark': 'wm-nuevo',
            'formularios': [
              {
                'uuid_edan_localidad': 'u1',
                'localidad': 'Del servidor',
                
              },
            ],
          });
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        return _err(404, 'ruta no esperada');
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final rows = await (await db.database)
          .query('formularios', where: 'uuid_edan_localidad = ?', whereArgs: ['u1']);
      expect(rows, hasLength(1));
      expect(rows.first['localidad'], 'Del servidor');
      expect(resumen.exito, isTrue);
      expect(await db.getConfig('sync_watermark_v2'), 'wm-nuevo');
    });

    test('NO pisa una fila local sucia (en cola pendiente)', () async {
      await _seedFila('x1', 'loc1', datos: '{"n":1}');
      await _seedCola('filas_seccion', 'x1', 'U');

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull({
            'watermark': 'wm-2',
            'secciones': [
              {
                'uuid_registro': 'x1',
                'uuid_edan_localidad': 'loc1',
                'tipo_seccion': 'danos_agricultura',
                'datos_json': {'n': 999},
                
              },
            ],
          });
        }
        return _ok();
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final rows = await (await db.database)
          .query('filas_seccion', where: 'uuid_registro = ?', whereArgs: ['x1']);
      // Sigue con mi dato local ({"n":1}), sin pisar por el pull.
      expect(rows.first['datos_json'], '{"n":1}');
    });

    test('pull actualiza estado + items de una localidad limpia', () async {
      await _seedFormulario('u-est', localidad: 'Vieja');
      await (await db.database).update(
          'formularios',
          {'id_edan_localidad_estado': 1},
          where: 'uuid_edan_localidad = ?',
          whereArgs: ['u-est']);
      await _seedFila('fila-est', 'u-est', datos: '{"tramo":"Viejo"}');

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull({
            'watermark': 'wm-est',
            'formularios': [
              {
                'uuid_edan_localidad': 'u-est',
                'localidad': 'Nueva',
                'id_edan_localidad_estado': 3,
                
              },
            ],
            'secciones': [
              {
                'uuid_registro': 'fila-est',
                'uuid_edan_localidad': 'u-est',
                'tipo_seccion': 'danos-viales',
                
              },
            ],
          });
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        return _err(404, 'ruta no esperada');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final form = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-est']);
      expect(form.first['id_edan_localidad_estado'], 3,
          reason: 'el estado del servidor debe reflejarse al sincronizar');
      expect(form.first['localidad'], 'Nueva');
      final fila = await (await db.database).query('filas_seccion',
          where: 'uuid_registro = ?', whereArgs: ['fila-est']);
      expect(fila.first['estado_sync'], 'confirmado');
    });

    test('pull: NO contamina datos_json con metacampos del documento del '
        'servidor (tipo_seccion / ids)', () async {
      // Bug 2026-11-02 (log "Escoma"): el espejo guardaba la fila cruda con
      // `tipo_seccion`, `id_edan_localidad` y `uuid_edan_localidad`; al
      // reenviarlas en el PUT el servidor respondía "campo desconocido o no
      // escribible para proteccion" y el Enviar fallaba con Push parcial.
      await _seedFormulario('u-meta', localidad: 'Escoma');
      await _seedFila('f-meta', 'u-meta',
          tipo: 'proteccion', datos: '{"mujeres":1}');

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull({
            'watermark': 'wm-meta',
            'secciones': [
              {
                'uuid_registro': 'f-meta',
                'uuid_edan_localidad': 'u-meta',
                'tipo_seccion': 'proteccion',
                'id_edan_localidad': 343711,
                'mujeres': 4,
                'fecha_modificacion': '2026-11-03T02:24:24.779',
              },
            ],
          });
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        return _err(404, 'ruta no esperada');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final fila = (await (await db.database).query('filas_seccion',
              where: 'uuid_registro = ?', whereArgs: ['f-meta']))
          .first;
      expect(fila['tipo'], 'proteccion',
          reason: 'la columna tipo se normaliza a ruta igual que antes');
      final datos = jsonDecode(fila['datos_json'] as String)
          as Map<String, dynamic>;
      expect(datos.containsKey('tipo_seccion'), isFalse,
          reason: 'reenviar tipo_seccion en el PUT pone la fila en error');
      expect(datos.containsKey('id_edan_localidad'), isFalse);
      expect(datos.containsKey('uuid_edan_localidad'), isFalse);
      expect(datos['mujeres'], 4, reason: 'el contenido real sí persiste');
    });

    test('pull NO toca estado ni items si hay push pendiente', () async {
      await _seedFormulario('u-dirty', localidad: 'Mia', pendientePush: 1);
      await (await db.database).update(
          'formularios',
          {'id_edan_localidad_estado': 1},
          where: 'uuid_edan_localidad = ?',
          whereArgs: ['u-dirty']);
      await _seedFila('fila-dirty', 'u-dirty', datos: '{"n":1}');

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull({
            'watermark': 'wm-dirty',
            'formularios': [
              {
                'uuid_edan_localidad': 'u-dirty',
                'localidad': 'Suya',
                'id_edan_localidad_estado': 6,
                
              },
            ],
            'secciones': [
              {
                'uuid_registro': 'fila-dirty',
                'uuid_edan_localidad': 'u-dirty',
                'tipo_seccion': 'danos_agricultura',
                
              },
            ],
          });
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          return _ok({
            'resultados': [],
            'aplicados': 1,
            'errores': 0,
          });
        }
        if (req.method == 'GET' && req.url.path.contains('/completo')) {
          return _ok({'uuid_edan_localidad': 'u-dirty'});
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      // El pull no pisa lo sucio; el push confirma lo local y relee.
      final fila = await (await db.database).query('filas_seccion',
          where: 'uuid_registro = ?', whereArgs: ['fila-dirty']);
      expect(fila.first['datos_json'], '{"n":1}');
    });

    test('tombstone de formulario borra la fila local', () async {
      await _seedFormulario('u-del');

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull({
            'watermark': 'wm-3',
            'tombstones': [
              {'tabla': 'edan_localidades', 'id_registro': 'u-del'},
            ],
          });
        }
        return _ok();
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final rows = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-del']);
      expect(rows, isEmpty);
    });

    test('foto con borrado_logico elimina el registro local', () async {
      await db.database.then((d) => d.insert('fotografias', {
            'uuid_fotografia': 'f-del',
            'uuid_edan_localidad': 'u1',
            'tipo_entidad': 'danos_agricultura',
            'uuid_registro': 'x1',
            'ruta_local': null,
          }));

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull({
            'watermark': 'wm-4',
            'fotos': [
              {
                'uuid_fotografia': 'f-del',
                'borrado_logico': true,
              },
            ],
          });
        }
        return _ok();
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final rows = await (await db.database).query('fotografias',
          where: 'uuid_fotografia = ?', whereArgs: ['f-del']);
      expect(rows, isEmpty);
    });
  });

  group('pull → errores visibles (nunca exito=true en silencio)', () {
    test('si NINGUNA fila se aplica: exito=false con motivo y sin ack',
        () async {
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull({
            'watermark': 'wm-roto',
            'formularios': [
              // uuid con tipo inválido hace fallar el casteo de la cabecera:
              // simula una fila que la aplicación local rechaza (LWW: sin
              // `version`, el fallo se simula con tipo incorrecto).
              {
                'uuid_edan_localidad': 123,
                'localidad': 'Rota',
                },
            ],
          });
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          fail('no debe hacer ack de un watermark con filas sin aplicar');
        }
        return _err(404, 'ruta no esperada');
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(resumen.exito, isFalse,
          reason: 'fila del servidor no aplicada = sync incompleto (antes '
              'quedaba exito=true y la lista vacía sin aviso)');
      expect(resumen.ultimoError, contains('ninguna se pudo aplicar'));
      expect(await db.getConfig('sync_watermark_v2'), isNull,
          reason: 'sin ack el próximo pull reintenta la fila fallida');
    });

    test('falla PARCIAL: exito=false, filas sanas sí aplican y sin ack',
        () async {
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull({
            'watermark': 'wm-parcial',
            'formularios': [
              {
                'uuid_edan_localidad': 'u-sana',
                'localidad': 'Sana',
                
              },
              {
                'uuid_edan_localidad': 999,
                'localidad': 'Mala',
                },
            ],
          });
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          fail('no debe hacer ack con fallas parciales');
        }
        return _err(404, 'ruta no esperada');
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final sana = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-sana']);
      expect(sana, hasLength(1), reason: 'las filas sanas sí se aplican');
      expect(resumen.exito, isFalse);
      expect(resumen.errores, 1);
      expect(resumen.ultimoError, contains('Pull parcial'));
      expect(await db.getConfig('sync_watermark_v2'), isNull);
    });

    test('pull sin filas nuevas sigue siendo exito (no acusa falsos)',
        () async {
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull({'watermark': 'wm-ok', 'formularios': []});
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        return _err(404, 'no');
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(resumen.exito, isTrue);
      expect(resumen.ultimoError, isNull);
    });
  });

  group('contrato 2026-10-14 (grup_* planas autoritativas)', () {
    test('pull con grup_* planas las persiste sin nodo grupos', () async {
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull({
            'watermark': 'wm-flat',
            'formularios': [
              {
                'uuid_edan_localidad': 'u-flat',
                'localidad': 'Plana',
                
                'id_usuario': 30,
                'grup_poblacion': true,
                'grup_agropecuario': 1,
                'grup_salud': false,
              },
            ],
          });
        }
        return _ok();
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(resumen.exito, isTrue);
      final form = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-flat']);
      expect(form, hasLength(1));
      expect(form.first['grup_poblacion'], 1);
      expect(form.first['grup_agropecuario'], 1);
      expect(form.first['grup_salud'], 0);
      final cache = await (await db.database).query('grupos_local',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-flat']);
      final porGrupo = {
        for (final r in cache) r['grupo'] as String: r['grup_servidor'],
      };
      expect(porGrupo['grupPoblacion'], 1);
      expect(porGrupo['grupAgropecuario'], 1);
    });

    test('estados con envelope {items,resumen} actualiza estado local',
        () async {
      await _seedFormulario('u-est2', localidad: 'Vieja');
      final client = MockClient((req) async {
        if (req.method == 'GET' &&
            req.url.path.endsWith('/formularios/estados')) {
          return _ok({
            'items': [
              {
                'uuid_edan_localidad': 'u-est2',
                'id_edan_localidad': 99,
                'id_edan_localidad_estado': 3,
                
                'grup_vivienda': true,
              },
            ],
            'resumen': {
              'por_estado': [
                {'id_edan_localidad_estado': 3, 'cantidad': 1}
              ],
              'por_grupo': [],
            },
            'total': 1,
          });
        }
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final form = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-est2']);
      expect(form.first['id_edan_localidad_estado'], 3);
      expect(form.first['id_server'], 99);
      expect(form.first['grup_vivienda'], 1,
          reason: 'las planas de estados también alimentan badges');
    });

    test('D con 404 se purga como resuelto (ya no existe)', () async {
      // Fila borrada localmente que nunca se subió: el DELETE da 404.
      await _seedCola('filas_seccion', 'fila-fantasma', 'D');
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        return _err(404, 'no existe');
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final cola = await (await db.database).query('cola_sincronizacion');
      expect(cola, isEmpty,
          reason: 'borrado ya efectivo en servidor: no queda pendiente');
      expect(resumen.enviados, 1);
      expect(resumen.errores, 0);
      expect(resumen.exito, isTrue);
    });

    test('arranque recupera operaciones en subiendo (kill a mitad de sync)',        () async {
      await _seedFormulario('u-rec', localidad: 'Rec', pendientePush: 1);
      await (await db.database).insert('cola_sincronizacion', {
        'tabla': 'filas_seccion',
        'uuid_registro': 'fila-rec',
        'accion': 'D',
        'estado': 'subiendo',
        'intentos': 0,
      });
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          return _ok({'uuid_edan_localidad': 'u-rec'});
        }
        if (req.method == 'GET' && req.url.path.contains('/completo')) {
          return _ok({'uuid_edan_localidad': 'u-rec'});
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      // La corrida liberó el 'subiendo' vencido y lo reprocesó: el D
      // fantasma se purgó (404) y el formulario se envió.
      final cola = await (await db.database).query('cola_sincronizacion');
      expect(cola, isEmpty);
      final f = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-rec']);
      expect(f.first['pendiente_push'], 0);
    });

    test('watermark por usuario no se comparte entre cuentas', () async {
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull({'watermark': 'wm-u30'});
        }
        return _ok();
      });

      await EdanSyncEngineV2(api: _api(client), db: db, usuarioId: 30)
          .sincronizar();

      expect(await db.getConfig('sync_watermark_v2_30'), 'wm-u30');
      expect(await db.getConfig('sync_watermark_v2'), isNull,
          reason: 'la marca global no debe mezclarse con la del usuario');
    });

    test('push con usuario solo envía sus filas', () async {      final database = await db.database;
      await database.insert('formularios', {
        'uuid_edan_localidad': 'u-mia',
        'localidad': 'Mia',
        
        'pendiente_push': 1,
        'id_usuario': 30,
      });
      await database.insert('formularios', {
        'uuid_edan_localidad': 'u-ajena',
        'localidad': 'Ajena',
        
        'pendiente_push': 1,
        'id_usuario': 31,
      });
      final enviados = <String>[];
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          enviados.add(body['uuid_edan_localidad'] as String);
          return _ok({'uuid_edan_localidad': body['uuid_edan_localidad']});
        }
        if (req.method == 'GET' && req.url.path.contains('/completo')) {
          return _ok({'uuid_edan_localidad': 'x'});
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db, usuarioId: 30)
          .sincronizar();

      expect(enviados, ['u-mia'],
          reason: 'la fila de otro usuario espera a su sesión');
      final ajena = await database.query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-ajena']);
      expect(ajena.first['pendiente_push'], 1);
    });

    test('401 aborta con mensaje de sesión expirada', () async {
      final client = MockClient((_) async => _err(401, 'Unauthorized'));

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db, usuarioId: 30)
              .sincronizar();

      expect(resumen.exito, isFalse);
      expect(resumen.ultimoError, contains('Sesión expirada'),
          reason: 'reintentar con token muerto es inútil: pedir re-login');
    });

    test('cola de otro dueño espera a su sesión (no se toca)', () async {
      final database = await db.database;
      await database.insert('formularios', {
        'uuid_edan_localidad': 'u-aj2',
        'localidad': 'Ajena',
        
        'id_usuario': 31,
      });
      await database.insert('filas_seccion', {
        'uuid_registro': 'f-aj2',
        'uuid_edan_localidad': 'u-aj2',
        'tipo': 'danos-vivienda',
        'datos_json': '{}',
        
        'estado_sync': 'confirmado',
      });
      await _seedCola('filas_seccion', 'f-aj2', 'D');
      final client = MockClient((req) async {
        if (req.method == 'DELETE') {
          fail('no debe borrar filas de otro usuario');
        }
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db, usuarioId: 30)
          .sincronizar();

      final cola = await database.query('cola_sincronizacion');
      expect(cola, hasLength(1));
      expect(cola.first['estado'], 'pendiente');
    });

    test('payload omite secciones de grupo apagado aunque haya filas',
        () async {
      final database = await db.database;
      await database.insert('formularios', {
        'uuid_edan_localidad': 'u-gate',
        'localidad': 'Gate',
        
        'pendiente_push': 1,
        'grup_agropecuario': 0,
      });
      // Registro gestionado (el usuario destildó el grupo).
      await database.insert('grupos_local', {
        'uuid_edan_localidad': 'u-gate',
        'grupo': 'grupAgropecuario',
        'seleccion_usuario': 0,
        'grup_servidor': null,
      });
      await _seedFila('fila-gate', 'u-gate', tipo: 'danos-agricultura');
      final row = (await database.query('formularios',
              where: 'uuid_edan_localidad = ?', whereArgs: ['u-gate']))
          .first;

      final payload =
          await EdanSyncEngineV2.prepararPayloadCompleto('u-gate', row);

      expect(payload['imp_danos_agricultura'], isFalse,
          reason: 'sin grupo no hay imp aunque queden filas huérfanas');
      expect(payload.containsKey('danos_agricultura'), isFalse,
          reason: 'lo destildado no viaja');
    });

        test('payload incluye sección de grupo marcado', () async {      final database = await db.database;
      await database.insert('formularios', {
        'uuid_edan_localidad': 'u-gate-ok',
        'localidad': 'GateOk',
        
        'pendiente_push': 1,
        'grup_agropecuario': 1,
      });
      await database.insert('grupos_local', {
        'uuid_edan_localidad': 'u-gate-ok',
        'grupo': 'grupAgropecuario',
        'seleccion_usuario': 1,
        'grup_servidor': null,
      });
      await _seedFila('fila-gate-ok', 'u-gate-ok', tipo: 'danos-agricultura');
      final row = (await database.query('formularios',
              where: 'uuid_edan_localidad = ?', whereArgs: ['u-gate-ok']))
          .first;

      final payload =
          await EdanSyncEngineV2.prepararPayloadCompleto('u-gate-ok', row);

      expect(payload['imp_danos_agricultura'], isTrue);
      expect(payload['danos_agricultura'], isA<List>());
    });
  });

  group('fotos en espera: visibles, nunca "sin cambios" en silencio', () {
    test('dueña sin confirmar se reporta como pendiente (no silencio)',
        () async {
      // Fila existe pero sin confirmar y formulario sin push pendiente:
      // el gate no deja subir. Antes el resumen salía en ceros ("Sin
      // cambios por enviar") aunque el badge marcaba la foto.
      await _seedFormulario('u-blq', localidad: 'Blq', pendientePush: 0);
      await _seedFila('fila-blq', 'u-blq',
          tipo: 'danos-agricultura', estado: 'pendiente');
      await db.database.then((d) => d.insert('cola_fotos', {
            'uuid_fotografia': 'foto-blq',
            'ruta_local': '/no/existe.jpg',
            'tipo_entidad': 'danos_agricultura',
            'uuid_registro': 'fila-blq',
            'estado': 'pendiente',
            'intentos': 0,
          }));
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        return _err(404, 'no');
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(resumen.exito, isTrue);
      expect(resumen.fotosPendientes, 1,
          reason: 'la foto bloqueada por el gate debe verse en el resumen');
    });

    test('foto huérfana sin nada por guardar se purga con motivo', () async {
      // Dueña inexistente y ningún formulario pendiente: jamás se podrá
      // subir. Se purga la cola (el badge se libera) y queda el motivo.
      await _seedFormulario('u-orf', localidad: 'Orf', pendientePush: 0);
      await db.database.then((d) async {
        await d.insert('fotografias', {
          'uuid_fotografia': 'foto-orf',
          'uuid_edan_localidad': 'u-orf',
          'tipo_entidad': 'danos_agricultura',
          'uuid_registro': 'fila-fantasma',
          'ruta_local': '/no/existe.jpg',
        });
        await d.insert('cola_fotos', {
          'uuid_fotografia': 'foto-orf',
          'ruta_local': '/no/existe.jpg',
          'tipo_entidad': 'danos_agricultura',
          'uuid_registro': 'fila-fantasma',
          'estado': 'pendiente',
          'intentos': 0,
        });
      });
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(await _colaFotos('foto-orf'), 0);
      final meta = await (await db.database).query('fotografias',
          where: 'uuid_fotografia = ?', whereArgs: ['foto-orf']);
      expect(meta.first['last_error'], contains('dueña inexistente'));
    });

    test('huérfana espera si hay formularios por guardar', () async {
      // La dueña puede nacer del guardado pendiente (el push falla y queda
      // pendiente): no purgar. Solo se purga cuando ya no hay nada por
      // guardar que pueda crearla.
      await _seedFormulario('u-orf2', localidad: 'Orf2', pendientePush: 1);
      await db.database.then((d) => d.insert('cola_fotos', {
            'uuid_fotografia': 'foto-orf2',
            'ruta_local': '/no/existe2.jpg',
            'tipo_entidad': 'danos_agricultura',
            'uuid_registro': 'fila-futura',
            'estado': 'pendiente',
            'intentos': 0,
          }));
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          return _err(500, 'caída transitoria');
        }
        return _err(404, 'no');
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(await _colaFotos('foto-orf2'), 1,
          reason: 'el guardado sigue pendiente: puede crear la dueña');
      expect(resumen.errores, 1);
    });
  });

    

    

    test('pull con tipo_seccion en forma tabla se guarda en forma ruta',
        () async {
      // Forma VIVA del servidor (verificado 2026-10-15): `tipo_seccion` con
      // guion bajo. Sin normalizar, la fila quedaba invisible para preview,
      // payload y flags (caso Urubo).
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull({
            'watermark': 'wm-tipo',
            'formularios': [
              {
                'uuid_edan_localidad': 'u-tipo',
                'localidad': 'Tipos',
                
              },
            ],
            'secciones': [
              {
                'uuid_registro': 'fila-tipo',
                'uuid_edan_localidad': 'u-tipo',
                'tipo_seccion': 'danos_agricultura',
                
              },
            ],
          });
        }
        return _ok();
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final filas = await (await db.database).query('filas_seccion',
          where: 'uuid_registro = ?', whereArgs: ['fila-tipo']);
      expect(filas, hasLength(1));
      expect(filas.first['tipo'], 'danos-agricultura',
          reason: 'la columna tipo guarda SIEMPRE ruta, como el wizard');
    });

  group('reparo tipo tabla→ruta (caso Urubo en vivo)', () {
    test('rutaDesdeTabla cubre las 14 + passthrough', () {
      for (final d in EdanSeccionesRegistry.secciones) {
        expect(EdanSeccionesRegistry.rutaDesdeTabla(d.tabla), d.rutaV2,
            reason: 'tabla ${d.tabla}');
        expect(EdanSeccionesRegistry.rutaDesdeTabla(d.rutaV2), d.rutaV2,
            reason: 'ruta ${d.rutaV2} idempotente');
      }
      expect(EdanSeccionesRegistry.rutaDesdeTabla('invento'), 'invento',
          reason: 'desconocido no se pierde');
    });

    test('mapaTablaARuta coincide con el registry (paridad)', () {
      for (final d in EdanSeccionesRegistry.secciones) {
        expect(DatabaseHelper.mapaTablaARuta[d.tabla], d.rutaV2,
            reason: 'tabla ${d.tabla} desincronizada del registry');
      }
      expect(DatabaseHelper.mapaTablaARuta, hasLength(14));
    });

    test('repararTiposFilaSeccion renombra solo forma tabla', () async {
      final database = await db.database;
      await database.insert('filas_seccion', {
        'uuid_registro': 'f-vieja',
        'uuid_edan_localidad': 'u-x',
        'tipo': 'danos_agricultura',
        'datos_json': '{}',
        
      });
      await database.insert('filas_seccion', {
        'uuid_registro': 'f-buena',
        'uuid_edan_localidad': 'u-x',
        'tipo': 'danos-viales',
        'datos_json': '{}',
        
      });
      expect(await DatabaseHelper.repararTiposFilaSeccion(database), 1);
      final vieja = await database.query('filas_seccion',
          where: 'uuid_registro = ?', whereArgs: ['f-vieja']);
      expect(vieja.first['tipo'], 'danos-agricultura');
      final buena = await database.query('filas_seccion',
          where: 'uuid_registro = ?', whereArgs: ['f-buena']);
      expect(buena.first['tipo'], 'danos-viales',
          reason: 'la forma ruta no se toca');
      // Idempotente: segunda corrida no toca nada.
      expect(await DatabaseHelper.repararTiposFilaSeccion(database), 0);
    });
  });

  group('reconciliación de respuestas POST/PUT', () {
    test('al subir la foto se guarda ruta_servidor/sha256/synced', () async {
      final arch = File(p.join(dir.path, 'conf.jpg'));
      await arch.writeAsBytes(utf8.encode('img'));

      await _seedFila('fila-conf', 'loc-conf',
          tipo: 'danos-agricultura', estado: 'confirmado');
      await db.database.then((d) async {
        await d.insert('fotografias', {
          'uuid_fotografia': 'foto-conf',
          'uuid_edan_localidad': 'loc-conf',
          'tipo_entidad': 'danos_agricultura',
          'uuid_registro': 'fila-conf',
          'ruta_local': arch.path,
        });
        await d.insert('cola_fotos', {
          'uuid_fotografia': 'foto-conf',
          'ruta_local': arch.path,
          'tipo_entidad': 'danos_agricultura',
          'uuid_registro': 'fila-conf',
          'estado': 'pendiente',
          'intentos': 0,
        });
      });
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' && req.url.path.endsWith('/fotografias')) {
          return _ok({
            'uuid_fotografia': 'foto-conf',
            'ruta_archivo': '/uploads/rec/conf.jpg',
            'sha256': 'shaconf',
          });
        }
        return _err(404, 'no');
      });

      final r =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(r.fotosSubidas, 1);
      final rows = await (await db.database).query('fotografias',
          where: 'uuid_fotografia = ?', whereArgs: ['foto-conf']);
      expect(rows.first['ruta_servidor'], '/uploads/rec/conf.jpg',
          reason: 'sin ruta del servidor, un borrado posterior no se propaga');
      expect(rows.first['sha256'], 'shaconf');
      expect(rows.first['upload_state'], 'synced');
    });

    test('POST /completo reconcilia id_server/grup sin re-GET',
        () async {
      await _seedFormulario('u-post', localidad: 'Loc', pendientePush: 1);
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          return _ok({
            'resultados': [],
            'aplicados': 1,
            'errores': 0,
            'formulario': {
              'uuid_edan_localidad': 'u-post',
              'id_edan_localidad': 777,
              
              'grup_vivienda': true,
            },
          });
        }
        // La relectura falla: la reconciliación debe bastar.
        return _err(404, 'sin relectura');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final f = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-post']);
      expect(f.first['id_server'], 777);
      expect(f.first['grup_vivienda'], 1);
      expect(f.first['pendiente_push'], 0);
    });

    test('C de cola guarda id del servidor', () async {
      await _seedFormulario('u-cu');
      await _seedCola('formulario', 'u-cu', 'C');
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' && req.url.path.endsWith('/formularios')) {
          return _ok({
            'uuid_edan_localidad': 'u-cu',
            'id_edan_localidad': 555,
            
          });
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final f = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-cu']);
      expect(f.first['id_server'], 555);
      expect(f.first['estado_local'], 'enviado');
    });
  });

  group('pull → nodo grupos (v32, §20.2)', () {
    test('cachea grup_* del servidor en grupos_local.grup_servidor', () async {
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull({
            'watermark': 'wm-g1',
            'formularios': [
              {
                'uuid_edan_localidad': 'u-g1',
                'localidad': 'Con grupos',
                
                'grupos': {
                  'grup_poblacion': true,
                  'grup_vivienda': true,
                  'grup_salud': false,
                },
              },
            ],
          });
        }
        return _ok();
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final servidor = await (await db.database).query('grupos_local',
          where: 'uuid_edan_localidad = ? AND grup_servidor IS NOT NULL',
          whereArgs: ['u-g1']);
      final porGrupo = {
        for (final r in servidor) r['grupo'] as String: r['grup_servidor'],
      };
      expect(porGrupo['grupPoblacion'], 1);
      expect(porGrupo['grupVivienda'], 1);
      expect(porGrupo['grupSalud'], 0);
      expect(porGrupo.containsKey('grupInfraestructura'), isFalse,
          reason: 'un grup_* ausente no debe crear fila');
    });

    test('el nodo del servidor NO pisa la selección del usuario', () async {
      // El usuario ya tildó "grupServicios" en page01.
      final database = await db.database;
      await database.insert('grupos_local', {
        'uuid_edan_localidad': 'u-g2',
        'grupo': 'grupServicios',
        'seleccion_usuario': 1,
        'grup_servidor': null,
      });

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull({
            'watermark': 'wm-g2',
            'formularios': [
              {
                'uuid_edan_localidad': 'u-g2',
                
                // El servidor dice que servicios NO está activo.
                'grupos': {'grup_servicios': false, 'grup_poblacion': true},
              },
            ],
          });
        }
        return _ok();
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final servicios = await database.query('grupos_local',
          where: 'uuid_edan_localidad = ? AND grupo = ?',
          whereArgs: ['u-g2', 'grupServicios']);
      expect(servicios, hasLength(1));
      expect(servicios.first['seleccion_usuario'], 1,
          reason: 'la selección del usuario es local y no debe borrarse');
      expect(servicios.first['grup_servidor'], 0,
          reason: 'pero la caché del servidor sí se actualiza');

      final poblacion = await database.query('grupos_local',
          where: 'uuid_edan_localidad = ? AND grupo = ?',
          whereArgs: ['u-g2', 'grupPoblacion']);
      expect(poblacion.first['grup_servidor'], 1);
      expect(poblacion.first['seleccion_usuario'], 0,
          reason: 'el servidor no tildó poblacion, eso no afecta al usuario');
    });

    test('un formulario sin nodo grupos no crea filas en grupos_local', () async {
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull({
            'watermark': 'wm-g3',
            'formularios': [
              {'uuid_edan_localidad': 'u-g3'},
            ],
          });
        }
        return _ok();
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final filas = await (await db.database).query('grupos_local',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-g3']);
      expect(filas, isEmpty);
    });
  });

  group('push → /completo (Fase D)', () {
    test('un formulario con pendiente_push=1 se envía vía POST /completo',
        () async {
      await _seedFormulario('u-c1', localidad: 'Loc C1', pendientePush: 1);

      Map<String, dynamic>? bodyRecibido;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          bodyRecibido = jsonDecode(req.body) as Map<String, dynamic>;
          return _ok({'uuid_edan_localidad': 'u-c1'});
        }
        if (req.method == 'GET' &&
            req.url.path.endsWith('/formularios/u-c1/completo')) {
          return _ok({'uuid_edan_localidad': 'u-c1', 'localidad': 'Loc C1'});
        }
        return _err(404, 'no');
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(resumen.enviados, 1);
      expect(bodyRecibido, isNotNull);
      expect(bodyRecibido!['uuid_edan_localidad'], 'u-c1');
      expect(bodyRecibido!['localidad'], 'Loc C1');
      // Las 14 flags de sección SIEMPRE presentes y explícitas (obligatorias
      // del servidor, `FormularioCompletoUpsert`).
      for (final k in [
        'imp_impacto_poblacion', 'imp_primera_respuesta',
        'imp_salud_establecimientos', 'imp_necesidad_salud',
        'imp_danos_viales', 'imp_danos_infra_publica',
        'imp_servicios_basicos', 'imp_unidades_educativas',
        'imp_danos_vivienda', 'imp_danos_agricultura',
        'imp_danos_pecuarios', 'imp_infra_productiva',
        'imp_proteccion', 'imp_necesidad_humanitaria',
      ]) {
        expect(bodyRecibido!.containsKey(k), isTrue, reason: 'falta $k');
        expect(bodyRecibido![k], isA<bool>(), reason: '$k no es bool');
      }
      // Las 9 flags de grupo NO se envían: el servidor las deriva. OJO:
      // `imp_proteccion` es además el nombre de la sección 1:1, por eso
      // sí está presente (colisión de nombre, no es flag de grupo).
      for (final k in [
        'grup_poblacion', 'grup_salud', 'grup_infraestructura', 'grup_servicios',
        'grup_educacion', 'grup_vivienda', 'grup_agropecuario', 'grup_necesidades',
      ]) {
        expect(bodyRecibido!.containsKey(k), isFalse,
            reason: 'no debe enviar flag de grupo $k');
      }
      // El nodo `grupos` tampoco viaja.
      expect(bodyRecibido!.containsKey('grupos'), isFalse);
    });

    test('tras el POST exitoso limpia pendiente_push y marca enviado',
        () async {
      await _seedFormulario('u-c2', pendientePush: 1);
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          return _ok({'uuid_edan_localidad': 'u-c2'});
        }
        if (req.method == 'GET' &&
            req.url.path.endsWith('/formularios/u-c2/completo')) {
          return _ok({'uuid_edan_localidad': 'u-c2'});
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final f = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-c2']);
      expect(f.first['pendiente_push'], 0);
      expect(f.first['estado_local'], 'enviado');
    });

    test('el payload incluye las filas de sección anidadas', () async {
      await _seedFormulario('u-c3', pendientePush: 1);
      await _seedFila('fila-agro-1', 'u-c3', tipo: 'danos-agricultura');

      Map<String, dynamic>? body;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _ok({'uuid_edan_localidad': 'u-c3'});
        }
        if (req.method == 'GET' &&
            req.url.path.endsWith('/formularios/u-c3/completo')) {
          return _ok({'uuid_edan_localidad': 'u-c3'});
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(body, isNotNull);
      expect(body!['danos_agricultura'], isA<List>());
      final filas = body!['danos_agricultura'] as List;
      expect(filas, hasLength(1));
      expect((filas.first as Map)['uuid_registro'], 'fila-agro-1');
    });

    test('las secciones 1:1 salen como objeto, no lista', () async {
      await _seedFormulario('u-c4', pendientePush: 1);
      await _seedFila('fila-pr-1', 'u-c4', tipo: 'primera-respuesta');

      Map<String, dynamic>? body;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _ok({'uuid_edan_localidad': 'u-c4'});
        }
        if (req.method == 'GET' &&
            req.url.path.endsWith('/formularios/u-c4/completo')) {
          return _ok({'uuid_edan_localidad': 'u-c4'});
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(body!['necesidad_primera_respuesta'], isA<Map<String, dynamic>>(),
          reason: '1:1 debe salir como objeto único');
    });

    test('un 400 del servidor conserva pendiente_push=1', () async {
      await _seedFormulario('u-c5', pendientePush: 1);
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          return _err(400, 'flag sin filas');
        }
        return _err(404, 'no');
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(resumen.errores, 1);
      expect(resumen.exito, isFalse);
      expect(resumen.ultimoError, 'flag sin filas',
          reason: 'el detalle real del servidor se propaga a la UI');
      final f = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-c5']);
      expect(f.first['pendiente_push'], 1,
          reason: 'el fallo no limpia el marcador: se reintenta');
    });

    test('los borrados (D) de la cola se procesan tras el /completo',
        () async {
      await _seedFormulario('u-c6', pendientePush: 1);
      await _seedFila('fila-del', 'u-c6', tipo: 'danos-agricultura');
      await _seedCola('filas_seccion', 'fila-del', 'D');

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          return _ok({'uuid_edan_localidad': 'u-c6'});
        }
        if (req.method == 'GET' &&
            req.url.path.endsWith('/formularios/u-c6/completo')) {
          return _ok({'uuid_edan_localidad': 'u-c6'});
        }
        if (req.method == 'DELETE' &&
            req.url.path.contains('/secciones/danos-agricultura/fila-del')) {
          return _ok();
        }
        return _err(404, 'no');
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(resumen.enviados, 2, reason: '1 (/completo) + 1 (D)');
      final cola = await (await db.database).query('cola_sincronizacion');
      expect(cola, isEmpty);
    });

    test('marca las filas como confirmado tras el /completo exitoso',
        () async {
      await _seedFormulario('u-c7', pendientePush: 1);
      await _seedFila('fila-ok', 'u-c7', tipo: 'danos-agricultura',
          estado: 'pendiente');

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          return _ok({'uuid_edan_localidad': 'u-c7'});
        }
        if (req.method == 'GET' &&
            req.url.path.endsWith('/formularios/u-c7/completo')) {
          return _ok({'uuid_edan_localidad': 'u-c7'});
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final filas = await (await db.database).query('filas_seccion',
          where: 'uuid_registro = ?', whereArgs: ['fila-ok']);
      expect(filas.first['estado_sync'], 'confirmado',
          reason: 'desbloquea la subida de fotos');
    });

    test('la relectura GET /completo se llama tras el POST', () async {
      await _seedFormulario('u-c8', pendientePush: 1);
      var postHecho = false;
      var getHecho = false;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          postHecho = true;
          return _ok({'uuid_edan_localidad': 'u-c8'});
        }
        if (req.method == 'GET' &&
            req.url.path.endsWith('/formularios/u-c8/completo')) {
          getHecho = true;
          return _ok({'uuid_edan_localidad': 'u-c8'});
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(postHecho, isTrue);
      expect(getHecho, isTrue, reason: 'la relectura aplica LWW del servidor');
    });

    test('un formulario sin pendiente_push NO se envía', () async {
      await _seedFormulario('u-c9', pendientePush: 0);

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        return _err(404, 'no');
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(resumen.enviados, 0);
      expect(resumen.exito, isTrue);
    });
  });

  group('prepararPayloadCompleto (payload real /completo)', () {
    test('las 14 flags salen de las filas, no de las flags gruesas de la fila',
        () async {
      // La fila de cabecera tiene TODAS las flags de grupo en false (0).
      await db.database.then((d) => d.insert('formularios', {
            'uuid_edan_localidad': 'u-p1',
            'localidad': 'Loc P1',
            
            'pendiente_push': 1,
            'grup_poblacion': 0,
            'grup_salud': 0,
            'grup_infraestructura': 0,
            'grup_servicios': 0,
            'grup_educacion': 0,
            'grup_vivienda': 0,
            'grup_agropecuario': 0,
            'grup_proteccion': 0,
            'grup_necesidades': 0,
          }));
      final row = (await (await db.database).query('formularios',
              where: 'uuid_edan_localidad = ?', whereArgs: ['u-p1']))
          .first;
      // ...pero sí hay filas reales de agropecuario y vivienda.
      await _seedFila('f-agro', 'u-p1', tipo: 'danos-agricultura');
      await _seedFila('f-viv', 'u-p1', tipo: 'danos-vivienda');

      final payload =
          await EdanSyncEngineV2.prepararPayloadCompleto('u-p1', row);

      expect(payload['imp_danos_agricultura'], isTrue,
          reason: 'flag de sección derivada de las filas');
      expect(payload['imp_danos_vivienda'], isTrue);
      // El resto de las 14 están presentes y en false (siempre explícitas).
      expect(payload['imp_impacto_poblacion'], isFalse);
      expect(payload['imp_necesidad_salud'], isFalse);
      expect(payload['imp_proteccion'], isFalse);
      // Las flags de grupo (salvo la colisión de nombre `imp_proteccion`)
      // NO viajan.
      expect(payload.containsKey('grup_agropecuario'), isFalse);
      expect(payload.containsKey('grup_vivienda'), isFalse);
      expect(payload.containsKey('grup_poblacion'), isFalse);
      expect(payload.containsKey('grupos'), isFalse);
    });

    test('sin filas: las 14 flags siguen presentes en false', () async {
      await _seedFormulario('u-p2', pendientePush: 1);
      final row = (await (await db.database).query('formularios',
              where: 'uuid_edan_localidad = ?', whereArgs: ['u-p2']))
          .first;

      final payload =
          await EdanSyncEngineV2.prepararPayloadCompleto('u-p2', row);

      const detalladas = [
        'imp_impacto_poblacion', 'imp_primera_respuesta',
        'imp_salud_establecimientos', 'imp_necesidad_salud',
        'imp_danos_viales', 'imp_danos_infra_publica',
        'imp_servicios_basicos', 'imp_unidades_educativas',
        'imp_danos_vivienda', 'imp_danos_agricultura',
        'imp_danos_pecuarios', 'imp_infra_productiva',
        'imp_proteccion', 'imp_necesidad_humanitaria',
      ];
      for (final k in detalladas) {
        expect(payload.containsKey(k), isTrue, reason: 'falta $k');
        expect(payload[k], isFalse, reason: '$k debía ser false');
      }
      expect(payload, hasLength(14 + 14),
          reason: '14 claves de cabecera fijas + 14 flags');
    });

    test('danos_vivienda arrastra viviendas[] y anula las coords del padre',
        () async {
      await _seedFormulario('u-p3', pendientePush: 1);
      await _seedFila('f-viv-p3', 'u-p3',
          tipo: 'danos-vivienda',
          datos: '{"comunidad":"X","coordenada_lat":1.5,"coordenada_lon":2.5}');
      await db.database.then((d) => d.insert('viviendas', {
            'uuid_registro': 'v-1',
            'uuid_dano_vivienda': 'f-viv-p3',
            'tipo_dano': 'TOTAL',
            'coordenada_lat': 1.0,
            'coordenada_lon': 2.0,
          }));
      final row = (await (await db.database).query('formularios',
              where: 'uuid_edan_localidad = ?', whereArgs: ['u-p3']))
          .first;

      final payload =
          await EdanSyncEngineV2.prepararPayloadCompleto('u-p3', row);

      expect(payload['danos_vivienda'], isA<Map<String, dynamic>>(),
          reason: '1:1 = objeto único');
      final padre = payload['danos_vivienda'] as Map<String, dynamic>;
      expect(padre['viviendas'], isA<List>());
      expect((padre['viviendas'] as List), hasLength(1));
      expect(padre['coordenada_lat'], isNull,
          reason: '§20.4: con hijas, coords del padre se anulan');
      expect(padre['coordenada_lon'], isNull);
      expect(padre['uuid_registro'], 'f-viv-p3');
    });

    test('impacto_poblacion con flag true se emite con EXACTAMENTE 4 filas '
        '(ids 1-4); las faltantes van en 0 con uuid determinista', () async {
      await _seedFormulario('u-p4', pendientePush: 1);
      // El usuario solo llenó 2 de las 4 filas del catálogo.
      await _seedFila('ip-1', 'u-p4',
          tipo: 'impacto-poblacion',
          datos: '{"id_grupo_etario":1,"fallecidos":2}');
      await _seedFila('ip-3', 'u-p4',
          tipo: 'impacto-poblacion',
          datos: '{"id_grupo_etario":3,"heridos":9}');
      final row = (await (await db.database).query('formularios',
              where: 'uuid_edan_localidad = ?', whereArgs: ['u-p4']))
          .first;

      final payload =
          await EdanSyncEngineV2.prepararPayloadCompleto('u-p4', row);

      expect(payload['imp_impacto_poblacion'], isTrue);
      final filas = payload['impacto_poblacion'] as List;
      expect(filas, hasLength(4), reason: '§20.10.E: tope 4 enforced');
      expect(
          filas.map((f) => (f as Map)['id_grupo_etario']).toList(),
          [1, 2, 3, 4],
          reason: 'una fila por id_grupo_etario del catálogo, ordenada');
      expect((filas[0] as Map)['fallecidos'], 2);
      expect((filas[1] as Map)['fallecidos'], 0,
          reason: 'fila sintética rellenada con ceros');
      final u2 = (filas[1] as Map)['uuid_registro'] as String;
      expect(u2.isNotEmpty, isTrue);

      // Reejecutar produce el MISMO uuid sintético (idempotente: reenviar no
      // duplica en el servidor).
      final payload2 =
          await EdanSyncEngineV2.prepararPayloadCompleto('u-p4', row);
      expect((payload2['impacto_poblacion'] as List)[1], isA<Map>());
      expect(
          ((payload2['impacto_poblacion'] as List)[1] as Map)['uuid_registro'],
          u2);
    });

    test('proteccion con flag true se emite con EXACTAMENTE 8 filas (ids 1-8)',
        () async {
      await _seedFormulario('u-p5', pendientePush: 1);
      await _seedFila('pr-5', 'u-p5',
          tipo: 'proteccion',
          datos: '{"id_grupo_vulnerable_catalogo":5,"mujeres":5}');
      final row = (await (await db.database).query('formularios',
              where: 'uuid_edan_localidad = ?', whereArgs: ['u-p5']))
          .first;

      final payload =
          await EdanSyncEngineV2.prepararPayloadCompleto('u-p5', row);

      expect(payload['imp_proteccion'], isTrue);
      final filas = payload['proteccion'] as List;
      expect(filas, hasLength(8), reason: '§20.10.E: tope 8 enforced');
      expect(
          filas
              .map((f) => (f as Map)['id_grupo_vulnerable_catalogo'])
              .toList(),
          [1, 2, 3, 4, 5, 6, 7, 8]);
      expect((filas[4] as Map)['mujeres'], 5);
    });

    test('impacto_poblacion descarta ids fuera de {1..4} y duplicados', () async {
      await _seedFormulario('u-p6', pendientePush: 1);
      await _seedFila('ip-a', 'u-p6',
          tipo: 'impacto-poblacion',
          datos: '{"id_grupo_etario":1,"heridos":1}');
      await _seedFila('ip-b', 'u-p6',
          tipo: 'impacto-poblacion',
          datos: '{"id_grupo_etario":1,"heridos":99}');
      await _seedFila('ip-c', 'u-p6',
          tipo: 'impacto-poblacion',
          datos: '{"id_grupo_etario":9,"heridos":7}');
      final row = (await (await db.database).query('formularios',
              where: 'uuid_edan_localidad = ?', whereArgs: ['u-p6']))
          .first;

      final payload =
          await EdanSyncEngineV2.prepararPayloadCompleto('u-p6', row);

      final filas = payload['impacto_poblacion'] as List;
      expect(filas, hasLength(4));
      expect(
          filas.map((f) => (f as Map)['id_grupo_etario']).toSet(),
          {1, 2, 3, 4},
          reason: 'id 9 fuera de rango descartado; el id 1 deduplicado');
    });

    test('§20.10.C: fotografia no viaja en NINGUNA sección del /completo '
        '(ni en las viviendas anidadas)', () async {
      await _seedFormulario('u-p7', pendientePush: 1);
      await _seedFila('dv-p7', 'u-p7',
          tipo: 'danos-vivienda',
          datos:
              '{"comunidad":"X","fotografia":"/uploads/reports/1/a.png"}');
      await _seedFila('va-p7', 'u-p7',
          tipo: 'danos-viales',
          datos: '{"tramo":"T","fotografia":"/uploads/reports/1/b.png"}');
      await db.database.then((d) => d.insert('viviendas', {
            'uuid_registro': 'v-p7',
            'uuid_dano_vivienda': 'dv-p7',
            'tipo_dano': 'TOTAL',
            'fotografia': 'local.png',
          }));
      final row = (await (await db.database).query('formularios',
              where: 'uuid_edan_localidad = ?', whereArgs: ['u-p7']))
          .first;

      final payload =
          await EdanSyncEngineV2.prepararPayloadCompleto('u-p7', row);

      expect((payload['danos_viales'] as List).first, isNot(contains('fotografia')));
      final dv = payload['danos_vivienda'] as Map;
      expect(dv.containsKey('fotografia'), isFalse);
      expect(dv['uuid_registro'], 'dv-p7');
      final viv = (dv['viviendas'] as List).first as Map;
      expect(viv.containsKey('fotografia'), isFalse);
      expect(viv.containsKey('uuid_dano_vivienda'), isFalse);
      expect(viv['uuid_registro'], 'v-p7',
          reason: 'cada hija conserva su propio uuid_registro');
    });
  });

  group('push → cola', () {
    test('éxito purga la cola y suma enviado', () async {
      await _seedFormulario('u-push');
      await _seedCola('formulario', 'u-push', 'C');

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' && req.url.path.endsWith('/formularios')) {
          return _ok({'uuid_edan_localidad': 'u-push'});
        }
        return _err(404, 'no');
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(resumen.enviados, 1);
      expect(resumen.exito, isTrue);
      final cola = await (await db.database).query('cola_sincronizacion');
      expect(cola, isEmpty);
    });

    

    test('error 400/403/404/422 es rechazado definitivo (sin backoff)',
        () async {
      await _seedFormulario('u-e');
      await _seedCola('formulario', 'u-e', 'C');

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' && req.url.path.endsWith('/formularios')) {
          return _err(400, 'campo inválido');
        }
        return _err(404, 'no');
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(resumen.errores, 1);
      final cola = await (await db.database).query('cola_sincronizacion');
      expect(cola.first['estado'], 'rechazado',
          reason: '400/403/404/422 verificado en vivo: no reintenta solo, '
              'requiere corrección del dato (§16.2)');
      expect(cola.first['ultimo_error'], contains('campo inválido'));
    });

    test('error 500 vuelve a pendiente con backoff e intentos', () async {
      await _seedFormulario('u-e5');
      await _seedCola('formulario', 'u-e5', 'C');

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' && req.url.path.endsWith('/formularios')) {
          return _err(500, 'caída temporal');
        }
        return _err(404, 'no');
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(resumen.errores, 1);
      final cola = await (await db.database).query('cola_sincronizacion',
          where: 'uuid_registro = ?', whereArgs: ['u-e5']);
      expect(cola.first['estado'], 'pendiente');
      expect(cola.first['intentos'], 1);
      expect(cola.first['fecha_proximo_intento'], isNotNull);
    });

    test('push /completo parcial (resultados con error) no confirma',
        () async {
      await _seedFormulario('u-par', pendientePush: 1);

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          return _ok({
            'resultados': [
              {'indice': 0, 'estado': 'error', 'message': 'flag sin filas'}
            ],
            'aplicados': 0,
            'errores': 1,
          });
        }
        return _err(404, 'no');
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(resumen.errores, 1);
      final form = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-par']);
      expect(form.first['pendiente_push'], 1,
          reason: 'un parcial no es confirmado: reintenta con dato corregido');
    });

    test('tombstone no pisa una localidad sucia (pendiente_push)', () async {
      await _seedFormulario('u-suc', pendientePush: 1);
      await _seedFila('fila-suc', 'u-suc');

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull({
            'watermark': 'wm-2',
            'tombstones': [
              {'tabla': 'edan_localidades', 'id_registro': 'u-suc'}
            ],
          });
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          return _ok({
            'resultados': [],
            'aplicados': 1,
            'errores': 0,
          });
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final form = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-suc']);
      expect(form, hasLength(1),
          reason: 'el push local manda: el tombstone se re-evalúa sin sucio');
    });

    test('checks locales (afectado/marcado) no rompen el confirm del contador',
        () async {
      // Regresión 2026-10-18: el wire borra `afectado`/`marcado`/`rango`
      // legacy pero `firmaContenido` los leía de `datos_json` → firmas
      // divergentes → `limpio=false` eterno → `pendiente_push` nunca se
      // limpiaba (badge "Sincronizar (1 pendientes)" pegado + re-PUT en
      // cada sync, respondiendo "Documento sin cambios").
      await _seedFormulario('u-check',
          localidad: 'Las Lomas', pendientePush: 1);
      await _seedFila(
        'sb-check', 'u-check',
        tipo: 'servicios-basicos',
        datos: jsonEncode({
          'uuid_registro': 'sb-check',
          'tipo': 'AGUA',
          'afectado': true,
        }),
      );
      await _seedFila(
        'im-check', 'u-check',
        tipo: 'impacto-poblacion',
        datos: jsonEncode({
          'uuid_registro': 'im-check',
          'id_grupo_etario': 1,
          'marcado': true,
          'rango': '0 a 14 años',
        }),
      );

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          return _ok({
            'resultados': [],
            'aplicados': 1,
            'errores': 0,
            'mensaje': 'Documento sin cambios',
          });
        }
        return _err(404, 'no');
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(resumen.exito, isTrue);
      expect(resumen.enviados, 1);
      expect(resumen.errores, 0);
      final form = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-check']);
      expect(form.first['pendiente_push'], 0,
          reason: 'el 200 con errores=0 confirma: las firmas coinciden');
      expect(await EdanStoreV2.instance.contarLocalidadesPendientes(), 0,
          reason: 'el badge del contador llega a 0 (misma fuente que la UI)');
    });

    test('sin red deja la fila pendiente y no avanza', () async {
      await _seedFormulario('u-n');
      await _seedCola('formulario', 'u-n', 'C');

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' && req.url.path.endsWith('/formularios')) {
          throw const SocketException('sin red');
        }
        return _err(404, 'no');
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(resumen.enviados, 0);
      final cola = await (await db.database).query('cola_sincronizacion');
      expect(cola.first['estado'], 'pendiente');
    });

    test('push respeta el orden cabecera → secciones', () async {
      await _seedFormulario('u-o');
      await _seedFila('fila-o', 'u-o');
      // Inserto la sección ANTES que la cabecera para probar el orden lógico.
      await _seedCola('filas_seccion', 'fila-o', 'C');
      await _seedCola('formulario', 'u-o', 'C');

      final orden = <String>[];
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST') {
          orden.add(req.url.path);
          return _ok();
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final iForm = orden.indexWhere((path) => path.endsWith('/formularios'));
      final iSeccion =
          orden.indexWhere((path) => path.contains('/secciones/'));
      expect(iForm, greaterThanOrEqualTo(0));
      expect(iSeccion, greaterThanOrEqualTo(0));
      expect(iForm, lessThan(iSeccion));
    });
  });

  group('push → payload contract', () {
    test('formulario envía SOLO los campos del contrato: nada de flags '
        'imp_*/grup_*, ni arrays, ni alcalde (§20.10.E/§20.11)', () async {
      await _seedFormulario(
        'u-pay',
        datosJson: jsonEncode({
          'impacto_poblacion': [
            {'id_seccion': 'g1'}
          ],
          'danos_vivienda': [
            {'id_seccion': 'd1'}
          ],
          'imp_impacto_poblacion': true,
          'imp_danos_pecuarios': true,
          'sincronizado': false,
          'secciones_eliminadas': ['x'],
          'nombre_alcalde': 'Juan',
        }),
      );
      await _seedCola('formulario', 'u-pay', 'C');

      Map<String, dynamic>? body;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' && req.url.path.endsWith('/formularios')) {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _ok({'uuid_edan_localidad': 'u-pay'});
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(body, isNotNull);
      // Campos del contrato de cabecera presentes.
      expect(body!['uuid_edan_localidad'], 'u-pay');
      expect(body!['localidad'], 'Loc');
      // §20.11: `FormularioUpsert` NO declara ninguna flag `imp_*` (ni `grup_*`)
      // y es `additionalProperties:false` → enviarlas provoca 422.
      expect(body!.containsKey('imp_poblacion'), isFalse);
      expect(body!.containsKey('imp_agropecuario'), isFalse);
      expect(body!.containsKey('imp_necesidades'), isFalse);
      expect(body!.containsKey('imp_impacto_poblacion'), isFalse,
          reason: 'flags detalladas ausentes del contrato de cabecera');
      expect(body!.containsKey('imp_danos_pecuarios'), isFalse);
      expect(body!.containsKey('grup_poblacion'), isFalse,
          reason: 'la cabecera no conoce los nombres grup_*');
      // Nada de contaminación de datos_json.
      expect(body!.containsKey('impacto_poblacion'), isFalse,
          reason: 'arrays de secciones no pertenecen a la cabecera');
      expect(body!.containsKey('danos_vivienda'), isFalse);
      expect(body!.containsKey('sincronizado'), isFalse,
          reason: 'campos locales no viajan al server');
      expect(body!.containsKey('secciones_eliminadas'), isFalse);
      expect(body!.containsKey('nombre_alcalde'), isFalse);
    });

    test('sección inyecta uuid_registro en el body del POST (upsert por uuid)',
        () async {
      await _seedFila('fila-pay', 'u-pay',
          datos: '{"id_seccion":"fila-pay","n":1}');
      await _seedCola('filas_seccion', 'fila-pay', 'C');

      Map<String, dynamic>? body;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' && req.url.path.contains('/secciones/')) {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _ok();
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(body, isNotNull);
      expect(body!['uuid_registro'], 'fila-pay',
          reason: 'el upsert del POST es por uuid_registro; sin él el server '
              'genera uuid propio y el pull duplicaría filas');
      expect(body!.containsKey('id_seccion'), isFalse,
          reason: 'POST solo-uuid verificado en vivo 2026-10-13: id_seccion '
              'responde 400 "Campo desconocido o no escribible"');
      expect(body!['n'], 1, reason: 'los campos de datos se preservan');
    });

    test('vivienda POST excluye fecha_modificacion_local (LWW: sin version)', () async {
      await db.database.then((d) async {
        await d.insert('filas_seccion', {
          'uuid_registro': 'dan-pay',
          'uuid_edan_localidad': 'u-pay',
          'tipo': 'danos-vivienda',
          'datos_json': '{}',
          
          'estado_sync': 'confirmado',
        });
        await d.insert('viviendas', {
          'uuid_registro': 'viv-pay',
          'uuid_dano_vivienda': 'dan-pay',
          'tipo_dano': 'TOTAL',
          'coordenada_lat': -16.5,
          'coordenada_lon': -68.1,
          'fotografia': 'x.jpg',
          
          'fecha_modificacion_local': '2026-01-01T00:00:00',
        });
      });
      await _seedCola('vivienda', 'viv-pay', 'C');

      Map<String, dynamic>? body;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' && req.url.path.endsWith('/viviendas')) {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _ok();
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(body, isNotNull);
      expect(body!['uuid_registro'], 'viv-pay');
      expect(body!['tipo_dano'], 'TOTAL');
      expect(body!['coordenada_lat'], -16.5);
      expect(body!['coordenada_lon'], -68.1);
      // §20.10.C: `fotografia` no viaja (la llena el server al subir la foto).
      expect(body!.containsKey('fotografia'), isFalse);
      // La relación padre↔hija va por anidamiento, no por `uuid_dano_vivienda`.
      expect(body!.containsKey('uuid_dano_vivienda'), isFalse);
      expect(body!.containsKey('fecha_modificacion_local'), isFalse,
          reason: 'nombre solo local; el server usa fecha_modificacion');
      expect(body!.containsKey('version'), isFalse,
          reason: 'LWW: version no viaja en el POST de creación');
    });

    test('vivienda PUT tampoco incluye version (LWW)', () async {
      await db.database.then((d) async {
        await d.insert('filas_seccion', {
          'uuid_registro': 'dan-put',
          'uuid_edan_localidad': 'u-put',
          'tipo': 'danos-vivienda',
          'datos_json': '{}',
          
          'estado_sync': 'confirmado',
        });
        await d.insert('viviendas', {
          'uuid_registro': 'viv-put',
          'uuid_dano_vivienda': 'dan-put',
          'tipo_dano': 'PARCIAL',
          'coordenada_lat': -16.6,
          'coordenada_lon': -68.2,
          
          'fecha_modificacion_local': '2026-01-02T00:00:00',
        });
      });
      await _seedCola('vivienda', 'viv-put', 'U');

      Map<String, dynamic>? body;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'PUT' && req.url.path.endsWith('/viviendas/viv-put')) {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _ok();
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(body, isNotNull);
      expect(body!.containsKey('version'), isFalse,
          reason: 'LWW: el PUT tampoco lleva version; gana el último que llega');
      expect(body!.containsKey('fecha_modificacion_local'), isFalse);
    });
  });

  group('fotos', () {
    test('el multipart lleva el tipo_entidad del CHECK (no "filas_seccion")',
        () async {
      // `edan.fotografias.tipo_entidad` tiene CHECK con los 14 nombres cortos
      // de TABLA + 'vivienda' (EDAN_ESQUEMA_BD §3.7). El wizard guarda la foto
      // con el marcador local `filas_seccion`; el motor debe traducirla por la
      // fila dueña. Se prueba con salud-establecimientos, donde el nombre de
      // tabla (`salud_establecimientos`) DIFIERE de la clave JSON
      // (`establecimientos_salud`): si se mandara la clave JSON, el server viola
      // el CHECK igual.
      final arch = File(p.join(dir.path, 'salud.jpg'));
      await arch.writeAsBytes(utf8.encode('img'));

      await _seedFila('fila-te', 'loc-te',
          tipo: 'salud-establecimientos', estado: 'confirmado');
      await db.database.then((d) => d.insert('cola_fotos', {
            'uuid_fotografia': 'foto-te',
            'ruta_local': arch.path,
            'tipo_entidad': 'filas_seccion',
            'uuid_registro': 'fila-te',
            'estado': 'pendiente',
            'intentos': 0,
          }));

      String? enviado;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' && req.url.path.endsWith('/fotografias')) {
          // MockClient entrega el `Request` ya serializado (el multipart con
          // el binario dentro), así que el campo se lee del cuerpo crudo.
          final cuerpo = latin1.decode(req.bodyBytes);
          final m = RegExp('name="tipo_entidad"[^\\r\\n]*\\r?\\n\\r?\\n([^\\r\\n]+)')
              .firstMatch(cuerpo);
          enviado = m?.group(1)?.trim();
          return _ok({'uuid_fotografia': 'foto-te'});
        }
        return _err(404, 'no');
      });

      final r = await EdanSyncEngineV2(api: _api(client), db: db)
          .sincronizar();

      expect(r.fotosSubidas, 1);
      expect(enviado, 'salud_establecimientos',
          reason: 'CHECK de edan.fotografias: nombre corto de tabla');
      expect(enviado, isNot('filas_seccion'));
      expect(enviado, isNot('establecimientos_salud'));
      // Y queda normalizado en local, para no volver a traducirlo.
      final filaDb = await (await db.database).query('cola_fotos',
          columns: ['estado'], where: 'uuid_fotografia = ?',
          whereArgs: ['foto-te']);
      expect(filaDb, isEmpty, reason: 'la cola se purga al subir');
    });

    test('no sube la foto si el tipo_entidad no es resoluble', () async {
      // La dueña existe y está confirmada (pasa el gate), pero su `tipo` no es
      // una de las 14 secciones: no hay forma de cumplir el CHECK. Es mejor
      // dejarla en cola con el motivo que mandar un valor inválido (422/500).
      final arch = File(p.join(dir.path, 'rara.jpg'));
      await arch.writeAsBytes(utf8.encode('img'));

      await _seedFila('fila-rara', 'loc-rara',
          tipo: 'seccion-foranea', estado: 'confirmado');
      await db.database.then((d) => d.insert('cola_fotos', {
            'uuid_fotografia': 'foto-rara',
            'ruta_local': arch.path,
            'tipo_entidad': 'filas_seccion',
            'uuid_registro': 'fila-rara',
            'estado': 'pendiente',
            'intentos': 0,
          }));

      var intentos = 0;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' && req.url.path.endsWith('/fotografias')) {
          intentos++;
          return _ok();
        }
        return _ok();
      });

      final r = await EdanSyncEngineV2(api: _api(client), db: db)
          .sincronizar();

      expect(intentos, 0, reason: 'no se envía un tipo_entidad inválido');
      expect(r.fotosSubidas, 0);
      expect(await _colaFotos('foto-rara'), 1,
          reason: 'queda en cola con el motivo registrado');
    });

    test('solo sube la foto cuando su dueña está confirmada', () async {
      final arch = File(p.join(dir.path, 'foto.jpg'));
      await arch.writeAsBytes(utf8.encode('imagen'));

      await _seedFila('due1', 'loc1', estado: 'pendiente');
      await db.database.then((d) => d.insert('cola_fotos', {
            'uuid_fotografia': 'f-foto',
            'ruta_local': arch.path,
            'tipo_entidad': 'danos_agricultura',
            'uuid_registro': 'due1',
            'estado': 'pendiente',
            'intentos': 0,
          }));

      var subidas = 0;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/fotografias')) {
          subidas++;
          return _ok({'uuid_fotografia': 'f-foto'});
        }
        return _ok();
      });

      final motor = EdanSyncEngineV2(api: _api(client), db: db);

      // Dueña NO confirmada → la foto no sube.
      var r = await motor.sincronizar();
      expect(r.fotosSubidas, 0);
      expect(subidas, 0);
      expect(await _colaFotos('f-foto'), 1);

      // Confirmo la dueña → ahora sí sube y se purga.
      await db.database.then((d) => d.update(
            'filas_seccion',
            {'estado_sync': 'confirmado'},
            where: 'uuid_registro = ?',
            whereArgs: ['due1'],
          ));
      r = await motor.sincronizar();
      expect(r.fotosSubidas, 1);
      expect(subidas, 1);
      expect(await _colaFotos('f-foto'), 0);
    });

    test(
        'gate vivienda: la foto tipo_entidad=vivienda sube solo cuando su '
        'fila padre (danos-vivienda) está confirmada', () async {
      final arch = File(p.join(dir.path, 'foto_viv.jpg'));
      await arch.writeAsBytes(utf8.encode('imagen-viv'));

      // Fila padre danos-vivienda con estado pendiente + su vivienda 1:N.
      await _seedFila('dan-viv', 'loc-viv',
          tipo: 'danos-vivienda', estado: 'pendiente');
      await db.database.then((d) async {
        await d.insert('viviendas', {
          'uuid_registro': 'viv-1',
          'uuid_dano_vivienda': 'dan-viv',
          'tipo_dano': 'TOTAL',
          'coordenada_lat': -16.5,
          'coordenada_lon': -68.1,
          
        });
        await d.insert('cola_fotos', {
          'uuid_fotografia': 'f-viv',
          'ruta_local': arch.path,
          'tipo_entidad': 'vivienda',
          'uuid_registro': 'viv-1',
          'estado': 'pendiente',
          'intentos': 0,
        });
      });

      var subidas = 0;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/fotografias')) {
          subidas++;
          return _ok({'uuid_fotografia': 'f-viv'});
        }
        return _ok();
      });

      final motor = EdanSyncEngineV2(api: _api(client), db: db);

      // Padre pendiente → la foto de la vivienda NO sube.
      var r = await motor.sincronizar();
      expect(r.fotosSubidas, 0);
      expect(subidas, 0);
      expect(await _colaFotos('f-viv'), 1);

      // Confirmo la fila padre danos-vivienda → la foto sí sube y se purga.
      await db.database.then((d) => d.update(
            'filas_seccion',
            {'estado_sync': 'confirmado'},
            where: 'uuid_registro = ?',
            whereArgs: ['dan-viv'],
          ));
      r = await motor.sincronizar();
      expect(r.fotosSubidas, 1);
      expect(subidas, 1);
      expect(await _colaFotos('f-viv'), 0);
    });

    test(
        'varias fotos en secciones distintas: cada una sube cuando su dueña '
        'se confirma y la de la no confirmada queda pendiente', () async {
      final a = File(p.join(dir.path, 'f_a.jpg'));
      final b = File(p.join(dir.path, 'f_b.jpg'));
      await a.writeAsBytes(utf8.encode('a'));
      await b.writeAsBytes(utf8.encode('b'));

      await _seedFila('secA', 'loc1',
          tipo: 'danos_agricultura', estado: 'confirmado');
      await _seedFila('secB', 'loc1',
          tipo: 'danos_vivienda', estado: 'pendiente');

      await db.database.then((d) async {
        await d.insert('cola_fotos', {
          'uuid_fotografia': 'f-a',
          'ruta_local': a.path,
          'tipo_entidad': 'filas_seccion',
          'uuid_registro': 'secA',
          'estado': 'pendiente',
          'intentos': 0,
        });
        await d.insert('cola_fotos', {
          'uuid_fotografia': 'f-b',
          'ruta_local': b.path,
          'tipo_entidad': 'filas_seccion',
          'uuid_registro': 'secB',
          'estado': 'pendiente',
          'intentos': 0,
        });
      });

      var subidas = 0;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/fotografias')) {
          subidas++;
          return _ok();
        }
        return _ok();
      });

      final motor = EdanSyncEngineV2(api: _api(client), db: db);
      final r = await motor.sincronizar();

      // Solo la foto de la sección confirmada sube; la otra espera.
      expect(r.fotosSubidas, 1);
      expect(subidas, 1);
      expect(await _colaFotos('f-a'), 0);
      expect(await _colaFotos('f-b'), 1);

      // Al confirmar secB, la foto restante sube en la siguiente corrida.
      await db.database.then((d) => d.update(
            'filas_seccion',
            {'estado_sync': 'confirmado'},
            where: 'uuid_registro = ?',
            whereArgs: ['secB'],
          ));
      final r2 = await motor.sincronizar();
      expect(r2.fotosSubidas, 1);
      expect(subidas, 2);
      expect(await _colaFotos('f-b'), 0);
    });
  });

  group('estado post-push (columna estado)', () {
    test('push exitoso marca formularios.estado_local=enviado', () async {
      await _seedFormulario('u-env');
      await _seedCola('formulario', 'u-env', 'C');

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' && req.url.path.endsWith('/formularios')) {
          return _ok({'uuid_edan_localidad': 'u-env'});
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final rows = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-env']);
      expect(rows, hasLength(1));
      expect(rows.first['estado_local'], 'enviado',
          reason: 'tras un push exitoso la cabecera queda como ENVIADO');
    });

    test(
        'push exitoso marca filas_seccion.estado_sync=confirmado (desbloquea '
        'fotos)', () async {
      await _seedFila('fila-ok', 'u-env2', estado: 'pendiente');
      await _seedCola('filas_seccion', 'fila-ok', 'C');

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' && req.url.path.contains('/secciones/')) {
          return _ok();
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final rows = await (await db.database).query('filas_seccion',
          where: 'uuid_registro = ?', whereArgs: ['fila-ok']);
      expect(rows, hasLength(1));
      expect(rows.first['estado_sync'], 'confirmado',
          reason: 'una fila confirmada desbloquea la subida de sus fotos');
    });

    test('un borrado (D) NO marca enviado/confirmado', () async {
      await _seedFormulario('u-del');
      await _seedCola('formulario', 'u-del', 'D');

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'DELETE' && req.url.path.endsWith('/formularios/u-del')) {
          return _ok();
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final rows = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-del']);
      // El borrado lógico de la fila local lo hace el pull/tombstone; el push
      // de 'D' solo debe purgar la cola sin tocar estado_local.
      expect(rows.isEmpty || rows.first['estado_local'] != 'enviado', isTrue,
          reason: 'un delete no debe dejar la cabecera como ENVIADO');
    });
  });

  group('recuperación de fotos (dispositivo nuevo)', () {
    test(
        'el pull trae la foto solo con metadatos y la descarga llena '
        'ruta_local con los bytes', () async {
      final dirFotos = await Directory.systemTemp.createTemp('edan_fotos');
      addTearDown(() {
        if (dirFotos.existsSync()) dirFotos.deleteSync(recursive: true);
      });

      const bytesImagen = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46];

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull({
            'watermark': 'wm-recup',
            'fotos': [
              {
                'uuid_fotografia': 'foto-rec-1',
                'uuid_edan_localidad': 'u-rec',
                'tipo_entidad': 'vivienda',
                'uuid_registro': 'viv-rec-1',
                'ruta_archivo': '/uploads/rec/foto1.jpg',
                'sha256':
                    'eb7e0381d519c6a257584ed4a69cf3ae4e4cfc7351cacb301ac646c0df5e8aca',
              },
            ],
          });
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        // Bytes por URL estática (host + ruta_archivo): el MockClient ignora
        // el host, así que basta con matchear el path del archivo.
        if (req.method == 'GET' && req.url.path == '/uploads/rec/foto1.jpg') {
          return http.Response.bytes(bytesImagen, 200,
              headers: {'content-type': 'image/jpeg'});
        }
        return _err(404, 'no');
      });

      final resumen = await EdanSyncEngineV2(
        api: _api(client),
        db: db,
        dirFotos: dirFotos,
      ).sincronizar();

      expect(resumen.exito, isTrue);

      final rows = await (await db.database).query('fotografias',
          where: 'uuid_fotografia = ?', whereArgs: ['foto-rec-1']);
      expect(rows, hasLength(1));
      final rutaLocal = rows.first['ruta_local'] as String?;
      expect(rutaLocal, isNotNull,
          reason: 'tras la descarga la foto debe tener ruta_local');
      expect(rows.first['ruta_servidor'], '/uploads/rec/foto1.jpg');
      expect(resumen.fotosDescargadas, 1);

      final archivo = File(rutaLocal!);
      expect(archivo.existsSync(), isTrue,
          reason: 'los bytes deben haberse escrito en disco');
      expect(await archivo.readAsBytes(), bytesImagen);
    });

    test('sin dirFotos inyectada la descarga se omite y no falla', () async {
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull({
            'watermark': 'wm-nodir',
            'fotos': [
              {
                'uuid_fotografia': 'foto-nodir',
                'uuid_edan_localidad': 'u-nodir',
                'tipo_entidad': 'vivienda',
                'uuid_registro': 'viv-nodir',
                'ruta_archivo': '/uploads/nodir.jpg',
                'sha256': 'def456',
              },
            ],
          });
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        return _err(404, 'no');
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(resumen.exito, isTrue);
      expect(resumen.fotosDescargadas, 0);
      final rows = await (await db.database).query('fotografias',
          where: 'uuid_fotografia = ?', whereArgs: ['foto-nodir']);
      expect(rows, hasLength(1),
          reason: 'el metadato debe aplicarse aunque no se descargue');
      expect(rows.first['ruta_local'], anyOf(isNull, ''),
          reason: 'sin carpeta no se debe intentar la descarga');
    });

    test('descarga 404 marca y no se reintenta en corridas siguientes',
        () async {
      final dirFotos = await Directory.systemTemp.createTemp('edan_fotos404');
      addTearDown(() {
        if (dirFotos.existsSync()) dirFotos.deleteSync(recursive: true);
      });
      var descargas = 0;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          // Como el pull real: sin `desde` trae todo; con watermark solo
          // cambios (la foto ya no viene y el marcador persiste).
          if (req.url.queryParameters['desde']?.isNotEmpty ?? false) {
            return _pull({'watermark': 'wm-404-2'});
          }
          return _pull({
            'watermark': 'wm-404',
            'fotos': [
              {
                'uuid_fotografia': 'foto-404',
                'uuid_edan_localidad': 'u-404',
                'tipo_entidad': 'danos_agricultura',
                'uuid_registro': 'x-404',
                'ruta_archivo': '/uploads/falta.jpg',
              },
            ],
          });
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'GET' && req.url.path == '/uploads/falta.jpg') {
          descargas++;
          return _err(404, 'Not Found');
        }
        return _err(404, 'no');
      });
      Future<EdanSyncResumen> correr() => EdanSyncEngineV2(
            api: _api(client),
            db: db,
            dirFotos: dirFotos,
          ).sincronizar();

      final r1 = await correr();
      expect(r1.exito, isTrue);
      expect(r1.fotosDescargadas, 0);
      expect(descargas, 1);
      final meta = await (await db.database).query('fotografias',
          where: 'uuid_fotografia = ?', whereArgs: ['foto-404']);
      expect(meta.first['last_error'], contains('no-existe-en-servidor'));

      await correr();
      expect(descargas, 1,
          reason: 'archivo inexistente no se martilla en cada sync');
    });
  });

  // ── Botón "Enviar": una sola localidad por las APIs nuevas ───────────────
  group('enviarLocalidad (POST /completo + POST /fotografias)', () {
    test('empuja /completo y despues la foto por /fotografias', () async {
      final arch = File(p.join(dir.path, 'envio.jpg'));
      await arch.writeAsBytes(utf8.encode('bytes'));

      await _seedFormulario('u-env-1', pendientePush: 1);
      await _seedFila('fila-env-1', 'u-env-1',
          tipo: 'danos-agricultura', estado: 'pendiente');
      await db.database.then((d) => d.insert('cola_fotos', {
            'uuid_fotografia': 'foto-env-1',
            'ruta_local': arch.path,
            'tipo_entidad': 'danos_agricultura',
            'uuid_registro': 'fila-env-1',
            'estado': 'pendiente',
            'intentos': 0,
          }));

      final rutas = <String>[];
      final client = MockClient((req) async {
        rutas.add('${req.method} ${req.url.path}');
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          return _ok({'uuid_edan_localidad': 'u-env-1'});
        }
        if (req.method == 'GET' &&
            req.url.path.endsWith('/formularios/u-env-1/completo')) {
          return _ok({'uuid_edan_localidad': 'u-env-1'});
        }
        if (req.method == 'POST' && req.url.path.endsWith('/fotografias')) {
          return _ok({'uuid_fotografia': 'foto-env-1'});
        }
        return _err(404, 'no');
      });

      final ok =
          await EdanSyncEngineV2(api: _api(client), db: db).enviarLocalidad(
        'u-env-1',
      );

      expect(ok, isTrue);
      // Las dos APIs NUEVAS, en orden, y NADA del legado /documento ni /upload.
      expect(rutas.firstWhere((r) => r.contains('/formularios/completo')),
          contains('POST'));
      expect(rutas.last, 'POST /api/v2/edan/fotografias');
      expect(rutas.where((r) => r.contains('upload')), isEmpty,
          reason: 'las fotos no vuelven por POST /upload');
      expect(rutas.where((r) => r.contains('/documento')), isEmpty,
          reason: 'el documento no se envía por EDAN_LOCALIDADES');

      final f = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-env-1']);
      expect(f.first['pendiente_push'], 0);
      expect(f.first['estado_local'], 'enviado');
      final fila = await (await db.database).query('filas_seccion',
          where: 'uuid_registro = ?', whereArgs: ['fila-env-1']);
      expect(fila.first['estado_sync'], 'confirmado');
      expect(await _colaFotos('foto-env-1'), 0,
          reason: 'la cola de fotos se purga al confirmar la subida');
    });

    test('el estado destino se escribe ANTES de armar el payload', () async {
      await _seedFormulario('u-env-2', pendientePush: 1);

      Map<String, dynamic>? body;
      final client = MockClient((req) async {
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _ok({'uuid_edan_localidad': 'u-env-2'});
        }
        if (req.method == 'GET' &&
            req.url.path.endsWith('/formularios/u-env-2/completo')) {
          return _ok({'uuid_edan_localidad': 'u-env-2'});
        }
        return _ok();
      });

      final ok =
          await EdanSyncEngineV2(api: _api(client), db: db).enviarLocalidad(
        'u-env-2',
        idEdanLocalidadEstado: 2, // enviado_ugr
      );

      expect(ok, isTrue);
      expect(body!['id_edan_localidad_estado'], 2,
          reason: 'el servidor recibe el documento ya con el estado nuevo');
    });

    test('un 400 del /completo deja pendiente_push=1 y NO sube fotos',
        () async {
      final arch = File(p.join(dir.path, 'no-sube.jpg'));
      await arch.writeAsBytes(utf8.encode('bytes'));

      await _seedFormulario('u-env-3', pendientePush: 1);
      await _seedFila('fila-env-3', 'u-env-3',
          tipo: 'danos-agricultura', estado: 'confirmado');
      await db.database.then((d) => d.insert('cola_fotos', {
            'uuid_fotografia': 'foto-env-3',
            'ruta_local': arch.path,
            'tipo_entidad': 'danos_agricultura',
            'uuid_registro': 'fila-env-3',
            'estado': 'pendiente',
            'intentos': 0,
          }));

      var fotosSubidas = 0;
      final client = MockClient((req) async {
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          return _err(400, 'flag true sin filas');
        }
        if (req.method == 'POST' && req.url.path.endsWith('/fotografias')) {
          fotosSubidas++;
          return _ok();
        }
        return _err(404, 'no');
      });

      final ok =
          await EdanSyncEngineV2(api: _api(client), db: db).enviarLocalidad(
        'u-env-3',
      );

      expect(ok, isFalse);
      expect(fotosSubidas, 0,
          reason: 'sin documento confirmado no tiene sentido subir la foto');
      final f = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-env-3']);
      expect(f.first['pendiente_push'], 1);
      expect(f.first['pending_submit'], 1,
          reason: 'la intención de envío queda para el próximo sincronizar()');
      expect(await _colaFotos('foto-env-3'), 1,
          reason: 'la foto sigue en cola para el próximo sincronizar()');
    });

    test('fallo con estado destino revierte el estado pero no la intención',
        () async {
      await _seedFormulario('u-env-r', pendientePush: 0);
      await (await db.database).update(
          'formularios',
          {'id_edan_localidad_estado': 1},
          where: 'uuid_edan_localidad = ?',
          whereArgs: ['u-env-r']);
      final client = MockClient((req) async {
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          return _err(400, 'flag true sin filas');
        }
        return _err(404, 'no');
      });

      final ok =
          await EdanSyncEngineV2(api: _api(client), db: db).enviarLocalidad(
        'u-env-r',
        idEdanLocalidadEstado: 2,
      );

      expect(ok, isFalse);
      final f = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-env-r']);
      expect(f.first['id_edan_localidad_estado'], 1,
          reason: 'sin 200 no hay enviado: el servidor sigue en borrador');
      expect(f.first['pendiente_push'], 1);
      expect(f.first['pending_submit'], 1);
      expect(f.first['estado_destino'], 2,
          reason: 'la intención de envío sobrevive al fallo');
    });

    test('Enviar sin red guarda la intención; el sync aplica el destino',
        () async {
      await _seedFormulario('u-env-off', pendientePush: 0);
      await (await db.database).update(
          'formularios',
          {'id_edan_localidad_estado': 1},
          where: 'uuid_edan_localidad = ?',
          whereArgs: ['u-env-off']);
      // 1) Sin red: el envío deja intención sin tocar el estado visible.
      final sinRed = MockClient((_) async {
        throw const SocketException('sin red');
      });
      final okOff =
          await EdanSyncEngineV2(api: _api(sinRed), db: db).enviarLocalidad(
        'u-env-off',
        idEdanLocalidadEstado: 2,
      );
      expect(okOff, isFalse);
      var f = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-env-off']);
      expect(f.first['id_edan_localidad_estado'], 1,
          reason: 'offline no se miente el estado');
      expect(f.first['pending_submit'], 1);
      expect(f.first['estado_destino'], 2);
      expect(f.first['pendiente_push'], 1);

      // 2) Vuelve internet: el sync empuja con el estado destino y confirma.
      Map<String, dynamic>? body;
      final conRed = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _ok({
            'resultados': [],
            'aplicados': 1,
            'errores': 0,
            'formulario': {'uuid_edan_localidad': 'u-env-off'},
          });
        }
        if (req.method == 'GET' && req.url.path.contains('/completo')) {
          return _ok({'uuid_edan_localidad': 'u-env-off'});
        }
        return _err(404, 'no');
      });
      final resumen =
          await EdanSyncEngineV2(api: _api(conRed), db: db).sincronizar();

      expect(resumen.exito, isTrue);
      expect(body?['id_edan_localidad_estado'], 2,
          reason: 'el payload lleva el destino, no el borrador');
      f = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-env-off']);
      expect(f.first['id_edan_localidad_estado'], 2);
      expect(f.first['pending_submit'], 0);
      expect(f.first['estado_destino'], isNull);
      expect(f.first['pendiente_push'], 0);
    });

    test('éxito con estado destino confirma y limpia la intención', () async {
      await _seedFormulario('u-env-ok', pendientePush: 1);
      final client = MockClient((req) async {
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          return _ok({'uuid_edan_localidad': 'u-env-ok'});
        }
        if (req.method == 'GET' && req.url.path.contains('/completo')) {
          return _ok({'uuid_edan_localidad': 'u-env-ok'});
        }
        return _err(404, 'no');
      });

      final ok =
          await EdanSyncEngineV2(api: _api(client), db: db).enviarLocalidad(
        'u-env-ok',
        idEdanLocalidadEstado: 2,
      );

      expect(ok, isTrue);
      final f = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-env-ok']);
      expect(f.first['pendiente_push'], 0);
      expect(f.first['pending_submit'], 0);
    });

    test('400 flag huérfana se autocorrige y reintenta una vez (Prueba10)',
        () async {
      await _seedFormulario('u-huerf', pendientePush: 1);
      final cuerpos = <Map<String, dynamic>>[];
      var llamadas = 0;
      final client = MockClient((req) async {
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          llamadas++;
          final body =
              jsonDecode(req.body) as Map<String, dynamic>;
          cuerpos.add(body);
          if (llamadas == 1) {
            return _err(400,
                'El flag imp_danos_agricultura=true pero la sección danos_agricultura no trae filas');
          }
          return _ok({
            'resultados': [],
            'aplicados': 1,
            'errores': 0,
          });
        }
        if (req.method == 'GET' && req.url.path.contains('/completo')) {
          return _ok({'uuid_edan_localidad': 'u-huerf'});
        }
        return _err(404, 'no');
      });

      final ok =
          await EdanSyncEngineV2(api: _api(client), db: db).enviarLocalidad(
        'u-huerf',
      );

      expect(ok, isTrue, reason: 'el reintento corregido confirma');
      expect(llamadas, 2);
      expect(cuerpos[1]['imp_danos_agricultura'], isFalse);
      expect(cuerpos[1].containsKey('danos_agricultura'), isFalse,
          reason: 'sección huérfana fuera del reintento (upsert no borra)');
    });

    test('sin fila en formularios no inventa un envío', () async {
      var llamadas = 0;
      final client = MockClient((req) async {
        llamadas++;
        return _ok();
      });

      final ok =
          await EdanSyncEngineV2(api: _api(client), db: db).enviarLocalidad(
        'u-no-existe',
      );

      expect(ok, isFalse);
      expect(llamadas, 0, reason: 'nada que enviar: no se habla con el server');
    });

    test('solo sube las fotos de ESA localidad (no arrastra las ajenas)',
        () async {
      final archA = File(p.join(dir.path, 'a.jpg'));
      await archA.writeAsBytes(utf8.encode('A'));
      final archB = File(p.join(dir.path, 'b.jpg'));
      await archB.writeAsBytes(utf8.encode('B'));

      await _seedFormulario('u-env-A', pendientePush: 1);
      await _seedFormulario('u-env-B', pendientePush: 0);
      await _seedFila('fila-A', 'u-env-A', estado: 'confirmado');
      await _seedFila('fila-B', 'u-env-B', estado: 'confirmado');
      for (final e in [
        ('foto-a', 'fila-A', archA.path),
        ('foto-b', 'fila-B', archB.path),
      ]) {
        await db.database.then((d) => d.insert('cola_fotos', {
              'uuid_fotografia': e.$1,
              'ruta_local': e.$3,
              'tipo_entidad': 'danos_agricultura',
              'uuid_registro': e.$2,
              'estado': 'pendiente',
              'intentos': 0,
            }));
      }

      final client = MockClient((req) async {
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          return _ok({'uuid_edan_localidad': 'u-env-A'});
        }
        if (req.method == 'GET' && req.url.path.contains('/completo')) {
          return _ok({'uuid_edan_localidad': 'u-env-A'});
        }
        if (req.method == 'POST' && req.url.path.endsWith('/fotografias')) {
          return _ok();
        }
        return _err(404, 'no');
      });

      final ok =
          await EdanSyncEngineV2(api: _api(client), db: db).enviarLocalidad(
        'u-env-A',
      );

      expect(ok, isTrue);
      expect(await _colaFotos('foto-a'), 0,
          reason: 'la foto de la localidad enviada se purga');
      expect(await _colaFotos('foto-b'), 1,
          reason: 'la foto de OTRA localidad no debe subirse en este envío');
    });
  });

  group('borrar tras sync en borrador no resucita al reingresar', () {    test('pull lo trae + D viaja + queda limpio', () async {
      // Escenario reportado: se sincronizó en borrador, se borró del
      // celular y al volver a entrar el registro volvía. El pull de la
      // misma corrida trae el registro (el servidor aún lo tiene) pero NO
      // debe resucitarlo; el D pendiente debe propagar el DELETE.
      final database = await db.database;
      await database.insert('formularios', {
        'uuid_edan_localidad': 'u-bor',
        'localidad': 'Bor',
        
        'pendiente_push': 0,
        'id_server': 325668,
        'id_edan_localidad_estado': 1,
      });
      await database.insert('filas_seccion', {
        'uuid_registro': 'f-bor',
        'uuid_edan_localidad': 'u-bor',
        'tipo': 'danos-agricultura',
        'datos_json': '{"tipo_cultivo":"Maíz"}',
        
        'estado_sync': 'confirmado',
      });

      await EdanStoreV2(db: db).eliminarLocalidad('u-bor');
      Future<int> contar(String tabla) async => (await database.query(tabla,
              where: 'uuid_edan_localidad = ?', whereArgs: ['u-bor']))
          .length;
      expect(await contar('formularios'), 0,
          reason: 'tras borrar no se lista en el equipo');

      var deletes = 0;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull({
            'watermark': 'wm-bor',
            'formularios': [
              {
                'uuid_edan_localidad': 'u-bor',
                'id_edan_localidad': 325668,
                'localidad': 'Bor',
                'id_edan_localidad_estado': 1,
                
              },
            ],
            'secciones': [
              {
                'uuid_registro': 'f-bor',
                'uuid_edan_localidad': 'u-bor',
                'tipo_seccion': 'danos_agricultura',
                
              },
            ],
          });
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'DELETE' &&
            req.url.path.endsWith('/formularios/u-bor')) {
          deletes++;
          return _ok();
        }
        return _err(404, 'no');
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(deletes, 1,
          reason: 'el D pendiente debe propagar el DELETE al servidor');
      expect(resumen.exito, isTrue);
      expect(await contar('formularios'), 0,
          reason: 'el pull no resucita lo que tiene D pendiente');
      expect(await contar('filas_seccion'), 0);
      expect(await database.query('cola_sincronizacion'), isEmpty);
      expect(await EdanStoreV2(db: db).listarFormularios(), isEmpty);
    });
  });

  group('LWW sin version (2026-10-16)', () {
    test('(a) POST /completo NO envía version aunque exista id_server',
        () async {
      final database = await db.database;
      await database.insert('formularios', {
        'uuid_edan_localidad': 'u-lww-a',
        'localidad': 'LWW',
        'pendiente_push': 1,
        'id_server': 777,
      });
      Map<String, dynamic>? body;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _ok({'uuid_edan_localidad': 'u-lww-a'});
        }
        if (req.method == 'GET' && req.url.path.contains('/completo')) {
          return _ok({'uuid_edan_localidad': 'u-lww-a'});
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(body, isNotNull);
      expect(body!.containsKey('version'), isFalse,
          reason: 'LWW: el POST nunca lleva version, ni en creación ni con id_server');
    });

    test('(b) PUT de sección NO envía version', () async {
      await _seedFila('fila-put-sec', 'u-put-sec',
          tipo: 'danos-agricultura', datos: '{"tipo_cultivo":"Maíz"}');
      await _seedCola('filas_seccion', 'fila-put-sec', 'U');
      Map<String, dynamic>? body;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'PUT' &&
            req.url.path.contains('/secciones/danos-agricultura/fila-put-sec')) {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _ok({'uuid_registro': 'fila-put-sec'});
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(body, isNotNull);
      expect(body!.containsKey('version'), isFalse,
          reason: 'LWW: el PUT de sección tampoco lleva version');
    });

    test('(b) PUT de vivienda NO envía version', () async {
      await db.database.then((d) async {
        await d.insert('filas_seccion', {
          'uuid_registro': 'dan-lww-b',
          'uuid_edan_localidad': 'u-lww-b',
          'tipo': 'danos-vivienda',
          'datos_json': '{}',
          'estado_sync': 'confirmado',
        });
        await d.insert('viviendas', {
          'uuid_registro': 'viv-lww-b',
          'uuid_dano_vivienda': 'dan-lww-b',
          'tipo_dano': 'TOTAL',
        });
      });
      await _seedCola('vivienda', 'viv-lww-b', 'U');
      Map<String, dynamic>? body;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'PUT' && req.url.path.endsWith('/viviendas/viv-lww-b')) {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _ok({'uuid_registro': 'viv-lww-b'});
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(body, isNotNull);
      expect(body!.containsKey('version'), isFalse,
          reason: 'LWW: el PUT de vivienda tampoco lleva version');
    });

    test('(c) respuesta sin version confirma igual (pendiente_push=0, id_server)',
        () async {
      await _seedFormulario('u-lww-c', localidad: 'C', pendientePush: 1);
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' &&
            req.url.path.endsWith('/formularios/completo')) {
          return _ok({
            'resultados': [],
            'aplicados': 1,
            'errores': 0,
            'formulario': {
              'uuid_edan_localidad': 'u-lww-c',
              'id_edan_localidad': 555,
            },
          });
        }
        if (req.method == 'GET' && req.url.path.contains('/completo')) {
          return _ok({'uuid_edan_localidad': 'u-lww-c'});
        }
        return _err(404, 'no');
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(resumen.exito, isTrue);
      expect(resumen.conflictos, 0,
          reason: 'LWW: conflictos siempre 0');
      final f = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-lww-c']);
      expect(f.first['pendiente_push'], 0);
      expect(f.first['id_server'], 555,
          reason: 'id_server adoptado sin version en la respuesta');
    });

    test('(d) espejo fotografia de fila_dueña se aplica tras subir foto',
        () async {
      final arch = File(p.join(dir.path, 'lww.jpg'));
      await arch.writeAsBytes(utf8.encode('img'));
      await _seedFila('fila-lww-d', 'loc-lww-d',
          tipo: 'danos-agricultura',
          datos: '{"tipo_cultivo":"Maíz"}',
          estado: 'confirmado');
      await db.database.then((d) async {
        await d.insert('fotografias', {
          'uuid_fotografia': 'foto-lww-d',
          'uuid_edan_localidad': 'loc-lww-d',
          'tipo_entidad': 'danos_agricultura',
          'uuid_registro': 'fila-lww-d',
          'ruta_local': arch.path,
        });
        await d.insert('cola_fotos', {
          'uuid_fotografia': 'foto-lww-d',
          'ruta_local': arch.path,
          'tipo_entidad': 'danos_agricultura',
          'uuid_registro': 'fila-lww-d',
          'estado': 'pendiente',
          'intentos': 0,
        });
      });
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' && req.url.path.endsWith('/fotografias')) {
          return _ok({
            'uuid_fotografia': 'foto-lww-d',
            'ruta_archivo': '/uploads/lww.jpg',
            'sha256': 'sha-lww',
            'fila_dueña': {
              'uuid_registro': 'fila-lww-d',
              'fotografia': '/uploads/lww.jpg',
            },
          });
        }
        return _err(404, 'no');
      });

      final r =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(r.fotosSubidas, 1);
      final fila = await (await db.database).query('filas_seccion',
          where: 'uuid_registro = ?', whereArgs: ['fila-lww-d']);
      final datos =
          jsonDecode(fila.first['datos_json'] as String) as Map<String, dynamic>;
      expect(datos['fotografia'], '/uploads/lww.jpg',
          reason: 'espejo de la dueña aplicado sin re-pull');
    });
  });

  group('estados §20.15 (solo true descarga)', () {
    const wm = '2026-10-16T10:00:00.000000';

    MockClient _clienteEstados({
      required List<Map<String, dynamic>> items,
      Map<String, dynamic>? doc,
      void Function(Uri url)? onEstados,
    }) {
      return MockClient((req) async {
        final path = req.url.path;
        if (req.method == 'GET' && path.endsWith('/formularios/estados')) {
          onEstados?.call(req.url);
          return _ok({
            'items': items,
            'resumen': {},
            'total': items.length,
          });
        }
        if (req.method == 'GET' && path.contains('/completo')) {
          return _ok(doc ?? {});
        }
        if (req.method == 'GET' && path.endsWith('/sync/pull')) {
          // Watermark real del pull (máximo del servidor) ≥ fecha del doc.
          return _pull({'watermark': '2026-10-16T12:00:00.000000'});
        }
        if (req.method == 'POST' && path.endsWith('/sync/ack')) {
          return _ok();
        }
        return _err(404, 'ruta no esperada');
      });
    }

    Map<String, dynamic> _doc(String uuid, String fm) => {
          'cabecera': {
            'uuid_edan_localidad': uuid,
            'localidad': 'Web Nueva',
            'id_edan_localidad_estado': 1,
            'fecha_modificacion': fm,
          },
          'danos_agricultura': [
            {
              'uuid_registro': 'aaaaaaaa-0000-4000-8000-00000000c011',
              'uuid_edan_localidad': uuid,
              'tipo_cultivo': 'MAIZ',
            }
          ],
          'fotos': [
            {
              'uuid_fotografia': 'aaaaaaaa-0000-4000-8000-00000000c031',
              'uuid_edan_localidad': uuid,
              'tipo_entidad': 'danos_agricultura',
              'uuid_registro': 'aaaaaaaa-0000-4000-8000-00000000c011',
              'ruta_archivo': '/uploads/web.jpg',
              'borrado_logico': false,
            }
          ],
        };

    test('false no baja nada ni toca la BD', () async {
      await db.setConfig('sync_watermark_v2', wm);
      var completos = 0;
      final client = MockClient((req) async {
        final path = req.url.path;
        if (req.method == 'GET' && path.endsWith('/formularios/estados')) {
          return _ok({
            'items': [
              {
                'uuid_edan_localidad': 'u-falso',
                'localidad': 'X',
                'fecha_modificacion': '2026-10-16T11:00:00.000000',
                'tiene_cambios': false,
              }
            ],
            'resumen': {},
            'total': 1,
          });
        }
        if (req.method == 'GET' && path.contains('/completo')) {
          completos++;
          return _ok({});
        }
        if (req.method == 'GET' && path.endsWith('/sync/pull')) {
          return _pull({'watermark': 'wm-pull'});
        }
        if (req.method == 'POST' && path.endsWith('/sync/ack')) {
          return _ok();
        }
        return _err(404, 'ruta no esperada');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(completos, 0, reason: 'false no descarga documento');
      final rows = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-falso']);
      expect(rows, isEmpty);
    });

    test('true con uuid nuevo inserta doc + foto y asienta watermark',
        () async {
      await db.setConfig('sync_watermark_v2', wm);
      const fm = '2026-10-16T11:30:00.000000';
      String? pullDesde;
      final client = MockClient((req) async {
        final path = req.url.path;
        if (req.method == 'GET' && path.endsWith('/formularios/estados')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'items': [
                  {
                    'uuid_edan_localidad': 'u-web',
                    'localidad': 'Web Nueva',
                    'fecha_modificacion': fm,
                    'tiene_cambios': true,
                }
                ],
                'resumen': {},
                'total': 1,
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.method == 'GET' && path.contains('/completo')) {
          return http.Response(
            jsonEncode({'success': true, 'data': _doc('u-web', fm)}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.method == 'GET' && path.endsWith('/sync/pull')) {
          pullDesde = req.url.queryParameters['desde'];
          // Watermark real del pull (máximo del servidor) ≥ fecha del doc.
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {'watermark': '2026-10-16T12:00:00.000000'}
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.method == 'POST' && path.endsWith('/sync/ack')) {
          return http.Response('{"success":true}',
              200, headers: {'content-type': 'application/json'});
        }
        return http.Response('{"success":false,"detail":"x"}', 404,
            headers: {'content-type': 'application/json'});
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final forms = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-web']);
      expect(forms, hasLength(1));
      expect(forms.first['localidad'], 'Web Nueva');
      final filas = await (await db.database).query('filas_seccion',
          where: 'uuid_registro = ?',
          whereArgs: ['aaaaaaaa-0000-4000-8000-00000000c011']);
      expect(filas, hasLength(1));
      final fotos = await (await db.database).query('fotografias',
          where: 'uuid_fotografia = ?',
          whereArgs: ['aaaaaaaa-0000-4000-8000-00000000c031']);
      expect(fotos, hasLength(1),
          reason: 'metadatos de foto del doc nuevo quedan locales');
      expect(pullDesde, fm,
          reason: 'el pull usa desde=fm asentada por estados');
      expect(await db.getConfig('sync_watermark_v2'),
          '2026-10-16T12:00:00.000000',
          reason: 'estados asienta fm y el pull posterior avanza al máximo');
    });

    test('true con sucio local no pisa (gana el PUT posterior)', () async {
      await db.setConfig('sync_watermark_v2', wm);
      await _seedFormulario('u-mia', localidad: 'Mia', pendientePush: 1);
      var completos = 0;
      final client = MockClient((req) async {
        final path = req.url.path;
        if (req.method == 'GET' && path.endsWith('/formularios/estados')) {
          return _ok({
            'items': [
              {
                'uuid_edan_localidad': 'u-mia',
                'localidad': 'Suya',
                'fecha_modificacion': '2026-10-16T12:00:00.000000',
                'tiene_cambios': true,
              }
            ],
            'resumen': {},
            'total': 1,
          });
        }
        if (req.method == 'GET' && path.contains('/completo')) {
          completos++;
          return _ok({});
        }
        if (req.method == 'GET' && path.endsWith('/sync/pull')) {
          return _pull({'watermark': 'wm-pull'});
        }
        if (req.method == 'POST' && path.endsWith('/sync/ack')) {
          return _ok();
        }
        if (req.method == 'POST' && path.endsWith('/formularios/completo')) {
          return _err(400, 'fuera de alcance');
        }
        return _err(404, 'ruta no esperada');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(completos, 0, reason: 'sucio no se pisa con el doc del servidor');
      final rows = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-mia']);
      expect(rows.first['localidad'], 'Mia');
    });

    test('pide todos=true + watermark en la misma llamada', () async {
      await db.setConfig('sync_watermark_v2', wm);
      Uri? vista;
      final client = _clienteEstados(
        items: const [],
        onEstados: (url) => vista = url,
      );

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(vista, isNotNull);
      expect(vista!.queryParameters['todos'], 'true');
      expect(vista!.queryParameters['fecha_modificacion_desde'], wm);
    });

    test('flags pendiente_* del servidor no crashean esquema limpio',
        () async {
      // Regresión 2026-10-16 (caso Ghgg en vivo): el servidor manda
      // `pendiente_actualizacion`/`pendiente_eliminacion` y esas columnas NO
      // existen en el esquema limpio. El sync debe ignorarlas, no explotar.
      await db.setConfig('sync_watermark_v2', wm);
      final client = MockClient((req) async {
        final path = req.url.path;
        if (req.method == 'GET' && path.endsWith('/formularios/estados')) {
          return _ok({
            'items': [
              {
                'uuid_edan_localidad': 'u-flags',
                'id_edan_localidad': 343077,
                'localidad': 'Ghgg',
                'id_edan_localidad_estado': 2,
                'pendiente_actualizacion': false,
                'pendiente_eliminacion': false,
                'fecha_modificacion': '2026-10-15T14:45:28.195504',
                'tiene_cambios': true,
              }
            ],
            'resumen': {},
            'total': 1,
          });
        }
        if (req.method == 'GET' && path.contains('/completo')) {
          return _ok({
            'cabecera': {
              'uuid_edan_localidad': 'u-flags',
              'id_edan_localidad': 343077,
              'localidad': 'Ghgg',
              'id_edan_localidad_estado': 2,
              'fecha_modificacion': '2026-10-15T14:45:28.195504',
            },
          });
        }
        if (req.method == 'GET' && path.endsWith('/sync/pull')) {
          return _pull({'watermark': '2026-10-16T12:00:00.000000'});
        }
        if (req.method == 'POST' && path.endsWith('/sync/ack')) {
          return _ok();
        }
        return _err(404, 'ruta no esperada');
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(resumen.exito, isTrue);
      final rows = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-flags']);
      expect(rows, hasLength(1));
      expect(rows.first['id_server'], 343077);
      expect(rows.first['localidad'], 'Ghgg');
    });
  });

  group('nodos §20.16 (autor y nombres disgregados)', () {
    Map<String, dynamic> _filaNodos() => {
          'uuid_edan_localidad': 'u-nodo',
          'localidad': 'Loc Nodo',
          'id_municipio': 70101,
          'id_usuario': 30,
          'usuario': {
            'id_usuario': 30,
            'usuario': '7051296',
            'nombre': 'Luis Miguel Quenta Herrera',
            'id_rol': 7,
            'rol': {'id_rol': 7, 'nombre': 'RESP'},
          },
          'municipio': {
            'id': 70101,
            'codigo_ine': '070101',
            'nombre': 'Santa Cruz de la Sierra',
            'departamento': {
              'id': 7,
              'codigo_ine': '07',
              'nombre': 'Santa Cruz',
            },
            'provincia': {
              'id': 701,
              'codigo_ine': '0701',
              'nombre': 'Andrés Ibáñez',
            },
          },
          'tipo_evento': {'id_tipo_evento': 32, 'nombre': 'Derrumbes'},
          'tipo_localidad': {'id_tipo_localidad': 3, 'nombre': 'Comunidad'},
          'estado_localidad': {
            'id_edan_localidad_estado': 2,
            'nombre': 'Enviado UGR',
          },
          'edan': null,
        };

    test('pull guarda autor y nombres en columnas espejo', () async {
      final client = MockClient((req) async {
        final path = req.url.path;
        if (req.method == 'GET' && path.endsWith('/sync/pull')) {
          return _pull({
            'watermark': 'wm-n',
            'formularios': [_filaNodos()],
          });
        }
        if (req.method == 'POST' && path.endsWith('/sync/ack')) {
          return _ok();
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final rows = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-nodo']);
      expect(rows, hasLength(1));
      final r = rows.first;
      expect(r['usuario_nombre'], 'Luis Miguel Quenta Herrera');
      expect(r['usuario_login'], '7051296');
      expect(r['id_rol'], 7);
      expect(r['usuario_rol'], 'RESP');
      expect(r['municipio_nombre'], 'Santa Cruz de la Sierra');
      expect(r['municipio_codigo'], '070101');
      expect(r['departamento_nombre'], 'Santa Cruz');
      expect(r['provincia_nombre'], 'Andrés Ibáñez');
      expect(r['tipo_evento_nombre'], 'Derrumbes');
      expect(r['tipo_localidad_nombre'], 'Comunidad');
      expect(r['estado_nombre'], 'Enviado UGR');
      expect(r['id_edan'], isNull,
          reason: 'edan null en creaciones no crashea ni inventa');
    });

    test('el modelo hidrata el autor para la UI', () async {
      final client = MockClient((req) async {
        final path = req.url.path;
        if (req.method == 'GET' && path.endsWith('/sync/pull')) {
          return _pull({
            'watermark': 'wm-n2',
            'formularios': [_filaNodos()],
          });
        }
        if (req.method == 'POST' && path.endsWith('/sync/ack')) {
          return _ok();
        }
        return _err(404, 'no');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final locs = await EdanStoreV2(db: db)
          .listarReportes(usuarioId: 30);
      final loc =
          locs.firstWhere((l) => l.uuidEdanLocalidad == 'u-nodo');
      expect(loc.usuario?.nombre, 'Luis Miguel Quenta Herrera');
      expect(loc.usuario?.usuario, '7051296');
      expect(loc.usuario?.rol?.nombre, 'RESP');
      expect(loc.municipioNombre, 'Santa Cruz de la Sierra');
      expect(loc.tipoEventoNombre, 'Derrumbes');
    });

    test('re-guardar preserva los espejos del servidor', () async {
      final store = EdanStoreV2(db: db);
      final database = await db.database;
      await database.insert('formularios', {
        'uuid_edan_localidad': 'u-esp',
        'localidad': 'Loc',
        'usuario_nombre': 'Autora Real',
        'municipio_nombre': 'Sucre',
      });
      final loc = (await store.listarReportes(usuarioId: null))
          .firstWhere((l) => l.uuidEdanLocalidad == 'u-esp');
      await store.guardarFormulario(loc, usuarioId: 1);

      final rows = await database.query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-esp']);
      expect(rows.first['usuario_nombre'], 'Autora Real',
          reason: 'el REPLACE del wizard no borra espejos');
      expect(rows.first['municipio_nombre'], 'Sucre');
    });

    test('payload /completo es subconjunto del schema (46, sin extras)',
        () async {
      const schema46 = {
        'uuid_edan_localidad',
        'localidad',
        'id_municipio',
        'id_departamento',
        'id_provincia',
        'id_tipo_evento',
        'id_tipo_localidad',
        'id_edan_localidad_estado',
        'fecha_llenado',
        'fecha_evento',
        'hora_evento',
        'total_poblacion_afectada',
        'total_familias_afectadas',
        'total_familias_damnificadas',
        'id_usuario',
        'pendiente_actualizacion',
        'pendiente_eliminacion',
        'fecha_modificacion',
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
        'impacto_poblacion',
        'establecimientos_salud',
        'danos_viales',
        'danos_infra_publica',
        'servicios_basicos',
        'unidades_educativas',
        'danos_vivienda',
        'danos_agricultura',
        'danos_pecuarios',
        'infra_productiva',
        'proteccion',
        'necesidad_primera_respuesta',
        'necesidad_salud',
        'necesidad_humanitaria',
      };
      await _seedFormulario('u-sub');
      await _seedFila('f-sub', 'u-sub');
      final database = await db.database;
      final row = (await database.query('formularios',
          where: 'uuid_edan_localidad = ?',
          whereArgs: ['u-sub'])).first;
      final payload = await EdanSyncEngineV2.prepararPayloadCompleto(
          'u-sub', row,
          dbHelper: db);
      final extras = payload.keys.toSet().difference(schema46);
      expect(extras, isEmpty,
          reason: 'cero claves fuera del schema (riesgo 422)');
      expect(payload['uuid_edan_localidad'], 'u-sub');
    });
  });

  group('push → reconciliación sin re-GET (2026-10-18)', () {
    test('PUT 200 con `formulario` embebido: NO se emite GET /completo y la '
        'fila queda confirmada', () async {
      await _seedFormulario('u-mirror', localidad: 'Lm', pendientePush: 1,
          datosJson: '{}');
      await _seedFila('fila-mirror', 'u-mirror', estado: 'pendiente');
      var getsCompletos = 0;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if ((req.method == 'PUT' || req.method == 'POST') &&
            req.url.path.endsWith('/formularios/completo')) {
          // El servidor responde con el documento completo embebido (como en
          // vivo, 2026-10-18): no debe hacer falta ningún re-GET.
          return _ok({
            'hubo_cambios': false,
            'cambios': [],
            'aplicados': 0,
            'errores': 0,
            'formulario': {
              'cabecera': {
                'uuid_edan_localidad': 'u-mirror',
                'localidad': 'Lm',
                'id_edan_localidad_estado': 1,
                'imp_danos_agricultura': true,
                'grup_agropecuario': true,
              },
              'danos_agricultura': [
                {
                  'uuid_registro': 'fila-mirror',
                  'id_dano_agricultura': 900,
                  'tipo_cultivo': 'MAIZ',
                  'fallecidos': 0,
                },
              ],
              'fotos': [],
            },
          });
        }
        if (req.method == 'GET' && req.url.path.contains('/completo')) {
          getsCompletos++;
          return _err(500, 'no debe pedirse');
        }
        return _ok();
      });

      final resumen = await EdanSyncEngineV2(api: _api(client), db: db)
          .sincronizar();

      expect(getsCompletos, 0,
          reason: 'el espejo embebido en el 200 elimina el re-GET');
      expect(resumen.exito, isTrue);
      final fila = await (await db.database).query('filas_seccion',
          where: 'uuid_registro = ?', whereArgs: ['fila-mirror']);
      expect(fila.first['estado_sync'], 'confirmado');
      // El espejo corre ANTES del confirm y `_normalizarDocCompleto` tiene
      // el guard `_esLocalidadSucia` (pendiente_push=1 → retorna temprano):
      // es no-op mientras el formulario está sucio, igual que el re-GET
      // viejo (misma posición en el flujo). Lo que el push SÍ debe lograr
      // es confirmar filas y limpiar el pendiente.
      final form = await (await db.database).query('formularios',
          columns: ['pendiente_push'],
          where: 'uuid_edan_localidad = ?',
          whereArgs: ['u-mirror']);
      expect(form.first['pendiente_push'], 0,
          reason: 'la recepción confirmada con 200 limpia el pendiente');
    });

    test('PUT 200 SIN documento embebido + re-GET que muere en red: la '
        'confirmación NO revienta (best-effort de verdad)', () async {
      await _seedFormulario('u-fallback', localidad: 'Lf', pendientePush: 1,
          datosJson: '{}');
      await _seedFila('fila-fallback', 'u-fallback', estado: 'pendiente');
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull(_pullVacio());
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        if ((req.method == 'PUT' || req.method == 'POST') &&
            req.url.path.endsWith('/formularios/completo')) {
          return _ok({'hubo_cambios': false, 'errores': 0});
        }
        if (req.method == 'GET' && req.url.path.contains('/completo')) {
          throw http.ClientException('Failed host lookup (simulada)');
        }
        return _ok();
      });

      final resumen = await EdanSyncEngineV2(api: _api(client), db: db)
          .sincronizar();

      expect(resumen.exito, isTrue,
          reason: 'el 200 ya confirmó la recepción: una caída de red en la '
              'relectura no puede revertirla');
      final fila = await (await db.database).query('filas_seccion',
          where: 'uuid_registro = ?', whereArgs: ['fila-fallback']);
      expect(fila.first['estado_sync'], 'confirmado');
    });

    test('URL de relectura sin `?` colgado cuando no va comprimida',
        () async {
      Uri? capturada;
      final client = MockClient((req) async {
        capturada = req.url;
        return _ok({
          'cabecera': {'uuid_edan_localidad': 'u-url'},
          'fotos': [],
        });
      });
      await _api(client).obtenerFormularioCompleto('u-url');
      expect(capturada!.query, isEmpty,
          reason: '`Uri.replace(queryParameters: {})` emitía `/completo?`');
      expect(capturada!.path, endsWith('/formularios/u-url/completo'));
    });
  });

  group('tombstones del pull no bloquean el ack (bug 2026-11-03)', () {
    test('tombstone con id numérico y uuid sintético: la sync limpia termina '
        'exitosa y el watermark avanza', () async {
      // Réplica del registro_20261103_052515 del usuario (app limpia): el
      // servidor manda para siempre los tombstones de los borrados viejos
      // (incluidos ids sintéticos de diagnóstico). Antes: `as String?` con
      // id numérico lanzaba TypeError → "Pull parcial: 1 de 28" → ack:false →
      // alerta "Primera sincronización incompleta" PERMANENTE en cada sync.
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull({
            'watermark': 'wm-tomb',
            'formularios': [
              {'uuid_edan_localidad': 'u-tomb', 'localidad': 'Limpia'},
            ],
            'tombstones': [
              {'tabla': 'fotografias', 'id_registro': 123},
              {
                'tabla': 'edan_localidades',
                'id_registro': 'aaaaaaaa-1111-4222-8333-ccccccccccc1',
              },
            ],
          });
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        return _err(404, 'ruta no esperada');
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      expect(resumen.exito, isTrue,
          reason: 'un tombstone no aplicable es basura inofensiva: jamas '
              'puede dejar la primera sync en "incompleta"');
      expect(resumen.ultimoError, isNull);
      final rows = await (await db.database)
          .query('formularios',
              where: 'uuid_edan_localidad = ?', whereArgs: ['u-tomb']);
      expect(rows, hasLength(1), reason: 'el contenido sí se aplicó');
      expect(await db.getConfig('sync_watermark_v2'), 'wm-tomb',
          reason: 'el watermark se acks: los tombstones basura no volverán');
    });
  });

  group('viviendas del pull con coords STRING (bug 2026-11-03)', () {
    test('coordenadas como string del servidor: se aplican como double y la '
        'sync ackea el watermark', () async {
      // Snackbar capturado en el registro del usuario: "type 'String' is not
      // a subtype of type 'num?'" — el servidor devuelve `coordenada_lat/lon`
      // de `viviendas` como STRING. El `as num?` lanzaba TypeError: esa 1
      // vivienda era el "Pull parcial: 1 de 28" de la app limpia y, sin ack,
      // la alerta "incompleta" se repetía en cada sync para siempre.
      await _seedFormulario('u-viv-str');
      await _seedFila('viv-padre', 'u-viv-str', tipo: 'danos-vivienda');
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull({
            'watermark': 'wm-vivstr',
            'viviendas': [
              {
                'uuid_registro': 'hija-str',
                'uuid_dano_vivienda': 'viv-padre',
                'uuid_edan_localidad': 'u-viv-str',
                'tipo_dano': 'parcial',
                'coordenada_lat': '-16.5096056',
                'coordenada_lon': '-68.1057141',
                'fotografia': '/uploads/x.jpg',
                'fecha_modificacion': '2026-11-03T05:20:00',
              },
            ],
          });
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        return _err(404, 'ruta no esperada');
      });

      final resumen =
          await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();
      expect(resumen.exito, isTrue,
          reason: 'coords string no pueden lanzar TypeError ni bloquear el ack');
      final v = (await (await db.database)
              .query('viviendas',
                  where: 'uuid_registro = ?', whereArgs: ['hija-str']))
          .first;
      expect(v['coordenada_lat'], closeTo(-16.5096056, 1e-9));
      expect(v['coordenada_lon'], closeTo(-68.1057141, 1e-9));
      expect(v['tipo_dano'], 'PARCIAL');
      expect(await db.getConfig('sync_watermark_v2'), 'wm-vivstr',
          reason: 'el watermark avanza: la alerta "incompleta" ya no vuelve');
    });
  });

  group('detallePushParcial (mensaje honesto del 200 con errores)', () {
    test('lista SOLO las filas fallidas con su mensaje y los contadores', () {
      // Réplica de la respuesta real de Escoma (2026-11-02): los primeros
      // resultados son OK y el motivo está al final (proteccion tipo_seccion).
      final data = {
        'aplicados': 5,
        'conflictos': 0,
        'errores': 2,
        'resultados': [
          {'indice': 0, 'tipo': 'impacto_poblacion', 'estado': 'aplicado', 'message': 'OK'},
          {'indice': 1, 'tipo': 'impacto_poblacion', 'estado': 'aplicado', 'message': 'OK'},
          {
            'indice': 2,
            'tipo': 'proteccion',
            'estado': 'error',
            'message': "Campo desconocido o no escribible para proteccion: 'tipo_seccion'",
          },
          {
            'indice': 3,
            'tipo': 'proteccion',
            'estado': 'error',
            'message': "Campo desconocido o no escribible para proteccion: 'tipo_seccion'",
          },
        ],
      };
      final msg = EdanSyncEngineV2.detallePushParcial(data);
      expect(msg, contains('tipo_seccion'),
          reason: 'el motivo real debe aparecer (el take(3) viejo lo ocultaba)');
      expect(msg, contains('i=2'));
      expect(msg, contains('i=3'));
      expect(msg, contains('errores=2'));
      expect(msg, isNot(contains('i=0')),
          reason: 'las filas aplicado OK no se listan como si fallaran');
      expect(msg, isNot(contains('i=1')));
    });

    test('errores>0 sin fila fallida: lo dice explícitamente', () {
      final msg = EdanSyncEngineV2.detallePushParcial({
        'aplicados': 2,
        'conflictos': 0,
        'errores': 2,
        'resultados': [
          {'indice': 0, 'estado': 'aplicado', 'message': 'OK'},
          {'indice': 1, 'estado': 'creado', 'message': 'OK'},
        ],
      });
      expect(msg, contains('ninguna fila en estado error'));
      expect(msg, contains('errores=2'));
    });

    test('resultados ausentes: no revienta, muestra los contadores', () {
      final msg = EdanSyncEngineV2.detallePushParcial({'errores': 7});
      expect(msg, contains('Push parcial'));
      expect(msg, contains('errores=7'));
    });
  });

  group('foto del pull: dueña resuelta y preservada (bug 2026-11-02)', () {
    test('fotos[] sin `uuid_edan_localidad` (solo id numérico): se resuelve '
        'la dueña y la galería ve la foto (flujo UGR: fotos descargadas)',
        () async {
      await _seedFormulario('u-foto-pull', localidad: 'Escoma');
      final d0 = await db.database;
      // El formulario ya sincronizado: id_server es la PK numérica que el
      // servidor usa para identificar al dueño en `fotos`.
      await d0.update(
          'formularios',
          {
            'id_server': 343711,
            'id_usuario': 55,
            'id_municipio': 20701,
          },
          where: 'uuid_edan_localidad = ?',
          whereArgs: ['u-foto-pull']);
      // Dueña de la foto: padre `danos-vivienda` + hija (como en el documento
      // real de Escoma: la foto apunta al uuid de la HIJA).
      await _seedFila('padre-viv', 'u-foto-pull', tipo: 'danos-vivienda');
      final d = await db.database;
      await d.insert('viviendas', {
        'uuid_registro': '1d65cb56-9775-462c-abb0-5c2152b41f51',
        'uuid_dano_vivienda': 'padre-viv',
        'tipo_dano': 'PARCIAL',
      });

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull({
            'watermark': 'wm-foto',
            'fotos': [
              {
                'uuid_fotografia': '1978d46d-3508-44d4-bf3a-22eceda1db08',
                'id_edan_localidad': 343711,
                'tipo_entidad': 'vivienda',
                'uuid_registro': '1d65cb56-9775-462c-abb0-5c2152b41f51',
                'ruta_archivo': '/uploads/reports/020701/x.jpg',
                'borrado_logico': false,
                'fecha_modificacion': '2026-11-02T21:53:32',
              },
            ],
          });
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
          return _ok();
        }
        return _err(404, 'ruta no esperada');
      });

      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final foto = (await d.query('fotografias',
              where: 'uuid_fotografia = ?',
              whereArgs: ['1978d46d-3508-44d4-bf3a-22eceda1db08']))
          .first;
      expect(foto['uuid_edan_localidad'], 'u-foto-pull',
          reason: 'el REPLACE con "" dejaba la foto invisible para siempre en '
              'la galería (JOIN con formularios)');
      expect(foto['ruta_servidor'], '/uploads/reports/020701/x.jpg');

      final store = EdanStoreV2(db: db);
      final porUsuario =
          await store.listarFotosGaleria(usuarioId: 55);
      expect(porUsuario.map((f) => f.uuidFotografia),
          contains('1978d46d-3508-44d4-bf3a-22eceda1db08'),
          reason: 'galería RESP (fotos propias)');
      final porMunicipio =
          await store.listarFotosGaleriaPorMunicipio(idMunicipio: 20701);
      expect(porMunicipio.map((f) => f.uuidFotografia),
          contains('1978d46d-3508-44d4-bf3a-22eceda1db08'),
          reason: 'galería UGR (alcance municipio) — el mismo JOIN');
    });

    test('foto ya enlazada: un pull sin datos resolubles NO la desenlaza',
        () async {
      await _seedFormulario('u-keep-foto');
      final d = await db.database;
      await d.insert('fotografias', {
        'uuid_fotografia': 'foto-keep',
        'uuid_edan_localidad': 'u-keep-foto',
        'tipo_entidad': 'cabecera',
        'uuid_registro': 'fantasma-x',
        'ruta_servidor': '/uploads/a.jpg',
        // ruta_local poblada: la fase de descarga del sync la ignora y el
        // test se limita a la preservación del enlace.
        'ruta_local': '/data/files/a.jpg',
        'borrado_logico': 0,
      });

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
          return _pull({
            'watermark': 'wm-keep',
            'fotos': [
              {
                'uuid_fotografia': 'foto-keep',
                'ruta_archivo': '/uploads/a.jpg',
                'borrado_logico': false,
              },
            ],
          });
        }
        return _ok();
      });
      await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

      final foto = (await d.query('fotografias',
              where: 'uuid_fotografia = ?', whereArgs: ['foto-keep']))
          .first;
      expect(foto['uuid_edan_localidad'], 'u-keep-foto',
          reason: 'sin uuid en el pull, sin id_server y sin dueña local: '
              'preservar el enlace existente (antes lo pisaba con "")');
    });
  });
}

