/// Cliente API v2 (`EdanApiV2`) contra un `MockClient`: sin red ni token.
///
/// Cubre el desempaquetado del envelope `{success,message,data,total}`, el
/// mapeo de 4xx → `EdanApiError`, los reintentos ante 502/503/504 (y su
/// ausencia ante 4xx), y el multipart de fotos. LWW: sin `version` en el
/// wire ni 409 que resolver.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rea/services/api/edan_api_v2.dart';

const _base = 'https://api.test/api/v2/edan';

Map<String, dynamic> _env({
  bool success = true,
  String? message,
  dynamic data,
  int? total,
}) =>
    {
      'success': success,
      if (message != null) 'message': message,
      if (data != null) 'data': data,
      if (total != null) 'total': total,
    };

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  EdanApiV2 api(MockClient client) => EdanApiV2(httpClient: client, baseUrl: _base);

  group('envelope', () {
    test('crearFormulario desempaqueta data y total', () async {
      late http.Request visto;
      final client = MockClient((req) async {
        visto = req;
        return _json(_env(data: {'uuid_edan_localidad': 'u1'}, total: 1), 201);
      });
      final res = await api(client).crearFormulario({'localidad': 'X'});
      expect(res.ok, isTrue);
      expect(res.statusCode, 201);
      expect(res.data?['uuid_edan_localidad'], 'u1');
      expect(res.total, 1);
      expect(visto.method, 'POST');
      expect(visto.url.path, endsWith('/formularios'));
    });

    test('listarFormularios desempaqueta la lista', () async {
      final client = MockClient((_) async =>
          _json(_env(data: [
            {'uuid_edan_localidad': 'a'},
            {'uuid_edan_localidad': 'b'},
          ], total: 2)));
      final res = await api(client).listarFormularios();
      expect(res.ok, isTrue);
      expect(res.data, hasLength(2));
      expect(res.total, 2);
    });

    test('obtenerFormulario usa path /formularios/{uuid o id} (contrato §19.3)',
        () async {
      late Uri visto;
      final client = MockClient((req) async {
        visto = req.url;
        return _json(_env(data: {'uuid_edan_localidad': 'u9'}));
      });
      await api(client).obtenerFormulario('123', useId: true);
      expect(visto.path, endsWith('/formularios/123'),
          reason: 'uuid e id van en path, nunca en query ?id=');
      expect(visto.queryParameters.containsKey('id'), isFalse);
    });

    test('pull arma los query params desde/limit', () async {
      late Uri visto;
      final client = MockClient((req) async {
        visto = req.url;
        return _json(_env(data: {'watermark': 'w1'}));
      });
      await api(client).pull(desde: '2026-01-01T00:00:00', limit: 50);
      expect(visto.path, endsWith('/sync/pull'));
      expect(visto.queryParameters['desde'], '2026-01-01T00:00:00');
      expect(visto.queryParameters['limit'], '50');
    });

    test('ack envía id_dispositivo y watermark', () async {
      late Map<String, dynamic> cuerpo;
      final client = MockClient((req) async {
        cuerpo = jsonDecode(req.body) as Map<String, dynamic>;
        return _json(_env());
      });
      final res = await api(client)
          .ack(idDispositivo: 'dev1', watermark: 'w9');
      expect(res.ok, isTrue);
      expect(cuerpo['id_dispositivo'], 'dev1');
      expect(cuerpo['watermark'], 'w9');
    });
  });

  group('contrato 2026-10-14 (sin nodo grupos)', () {
    test('obtenerFormulario desempaqueta {cabecera, secciones_resumen}',
        () async {
      final client = MockClient((_) async => _json(_env(data: {
            'cabecera': {
              'uuid_edan_localidad': 'u-cab',
              'id_edan_localidad': 7,
              'grup_poblacion': true,
            },
            'secciones_resumen': {'danos_agricultura': 2},
          })));
      final res = await api(client).obtenerFormulario('u-cab');
      expect(res.ok, isTrue);
      expect(res.data?['uuid_edan_localidad'], 'u-cab');
      expect(res.data?['id_edan_localidad'], 7);
      expect(res.data?['grup_poblacion'], isTrue);
      expect(res.data?['secciones_resumen'], {'danos_agricultura': 2});
    });

    test('obtenerEstadosFormularios desempaqueta {items, resumen, total}',
        () async {
      final client = MockClient((_) async => _json(_env(data: {
            'items': [
              {
                'uuid_edan_localidad': 'u-e1',
                'id_edan_localidad_estado': 3,
                'grup_vivienda': true,
              },
            ],
            'resumen': {
              'por_estado': [
                {'id_edan_localidad_estado': 3, 'cantidad': 1}
              ],
              'por_grupo': [
                {'grupo': 'grup_vivienda', 'cantidad': 1}
              ],
            },
            'total': 1,
          })));
      final res = await api(client).obtenerEstadosFormularios(todos: true);
      expect(res.ok, isTrue);
      expect(res.data, hasLength(1));
      expect(res.data?.first['uuid_edan_localidad'], 'u-e1');
      expect(res.total, 1);
      final resumen = res.resumen;
      expect(resumen, isNotNull);
      expect((resumen!['por_estado'] as List), hasLength(1));
      expect((resumen['por_grupo'] as List), hasLength(1));
    });

    test('obtenerResumenEstados devuelve el resumen sin las filas', () async {
      late Uri visto;
      final client = MockClient((req) async {
        visto = req.url;
        return _json(_env(data: {
          'items': [
            {'uuid_edan_localidad': 'u-e1'}
          ],
          'resumen': {
            'por_estado': [],
            'por_grupo': [],
          },
          'total': 1,
        }));
      });
      final resumen = await api(client).obtenerResumenEstados();
      expect(resumen, isNotNull);
      expect(resumen!['por_estado'], isA<List>());
      expect(visto.queryParameters['limit'], '1',
          reason: 'el resumen cubre todo el alcance: payload mínimo');
    });

    test('sanitizePostPayload prohíbe fotografia/version/grup_/ids', () {      final out = EdanApiV2.sanitizePostPayload({
        'uuid_edan_localidad': 'u1',
        'localidad': 'X',
        'fotografia': '/uploads/a.jpg',
        'version': 3,
        'grup_poblacion': true,
        'id_seccion': 'abc',
        'id_dano_agricultura': 5,
        'id_municipio': 70101,
      }, esCabecera: true);
      expect(out['uuid_edan_localidad'], 'u1');
      expect(out['localidad'], 'X');
      expect(out.containsKey('fotografia'), isFalse,
          reason: 'la foto viaja solo por POST /fotografias multipart');
      expect(out.containsKey('version'), isFalse);
      expect(out.containsKey('grup_poblacion'), isFalse);
      expect(out.containsKey('id_seccion'), isFalse);
      expect(out.containsKey('id_dano_agricultura'), isFalse);
      expect(out['id_municipio'], 70101,
          reason: 'los ids de cabecera sí son escribibles');
    });
  });

  group('errores (LWW: sin conflicto)', () {
    test('payloads sin version viajan sin version (LWW)', () async {
      // POST /completo nunca lleva version, aunque el formulario exista.
      late Map<String, dynamic> vistoCompleto;
      var client = MockClient((req) async {
        vistoCompleto = jsonDecode(req.body) as Map<String, dynamic>;
        return _json(_env(data: {'uuid_edan_localidad': 'u1'}), 201);
      });
      await api(client).crearFormularioCompleto({
        'uuid_edan_localidad': 'u1',
        'localidad': 'X',
      });
      expect(vistoCompleto.containsKey('version'), isFalse,
          reason: 'LWW: el POST /completo nunca lleva version');

      // PUT tampoco la exige: viaja tal cual se le pasa (el motor no la pone).
      late Map<String, dynamic> vistoPut;
      client = MockClient((req) async {
        vistoPut = jsonDecode(req.body) as Map<String, dynamic>;
        return _json(_env(data: {'uuid_edan_localidad': 'u1'}));
      });
      await api(client).actualizarSeccion(
          'u1', 'danos-agricultura', 'f1', {'tipo_cultivo': 'Maíz'});
      expect(vistoPut.containsKey('version'), isFalse);
    });

    test('respuesta sin version se parsea bien (LWW)', () async {
      final client = MockClient((_) async => _json(_env(data: {
            'uuid_edan_localidad': 'u1',
            'id_edan_localidad': 777,
            'localidad': 'X',
          })));
      final res = await api(client).obtenerFormulario('u1');
      expect(res.ok, isTrue);
      expect(res.data?['uuid_edan_localidad'], 'u1');
      expect(res.data?['id_edan_localidad'], 777);
      expect(res.data?.containsKey('version'), isFalse,
          reason: 'el servidor real ya no devuelve version');
    });

    test('404 lanza EdanApiError con el detail', () async {
      final client = MockClient(
          (_) async => _json(_env(success: false, message: 'no'), 404));
      expect(
        () => api(client).obtenerFormulario('nope'),
        throwsA(isA<EdanApiError>()
            .having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('respuesta no-JSON lanza EdanApiError', () async {
      final client = MockClient((_) async => http.Response('html roto', 200));
      expect(
        () => api(client).obtenerFormulario('u1'),
        throwsA(isA<EdanApiError>().having(
            (e) => e.detail, 'detail', contains('JSON'))),
      );
    });
  });

  group('reintentos', () {
    test('503 se reintenta hasta 200', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        if (calls < 3) return http.Response('up', 503);
        return _json(_env(data: {'ok': true}));
      });
      final res = await api(client).obtenerFormulario('u1');
      expect(res.ok, isTrue);
      expect(calls, 3);
    });

    test('400 NO se reintenta (una sola llamada)', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return _json(_env(success: false), 400);
      });
      await expectLater(
        api(client).obtenerFormulario('u1'),
        throwsA(isA<EdanApiError>()),
      );
      expect(calls, 1);
    });
  });

  group('fotos', () {
    test('subirFotografia es multipart e incluye los campos', () async {
      final dir = await Directory.systemTemp.createTemp('edan_api_foto');
      final file = File('${dir.path}/foto.jpg');
      await file.writeAsBytes(utf8.encode('contenido-imagen'));

      late http.Request visto;
      final client = MockClient((req) async {
        visto = req;
        return _json(_env(data: {'uuid_fotografia': 'f1'}), 201);
      });

      final res = await api(client).subirFotografia(
        uuidFotografia: 'f1',
        tipoEntidad: 'danos_agricultura',
        uuidRegistro: 'u1',
        archivo: file,
      );
      expect(res.ok, isTrue);
      expect(visto.method, 'POST');
      expect(visto.url.path, endsWith('/fotografias'));
      final cuerpo = utf8.decode(visto.bodyBytes, allowMalformed: true);
      expect(cuerpo, contains('f1'));
      expect(cuerpo, contains('danos_agricultura'));

      await dir.delete(recursive: true);
    });

    test('eliminarFotografia hace DELETE por uuid', () async {
      late http.Request visto;
      final client = MockClient((req) async {
        visto = req;
        return _json(_env());
      });
      final res = await api(client).eliminarFotografia('f1');
      expect(res.ok, isTrue);
      expect(visto.method, 'DELETE');
      expect(visto.url.path, endsWith('/fotografias/f1'));
    });

    test('descargarBytesFoto usa metadata + URL estática (verificado vivo)',
        () async {
      final vistos = <String>[];
      final client = MockClient((req) async {
        vistos.add('${req.method} ${req.url.path}');
        if (req.url.path.endsWith('/fotografias/f9')) {
          return _json(_env(data: {
            'uuid_fotografia': 'f9',
            'ruta_archivo': '/uploads/x/f9.png',
          }));
        }
        if (req.url.path == '/uploads/x/f9.png') {
          return http.Response.bytes([10, 20, 30], 200,
              headers: {'content-type': 'image/png'});
        }
        return _json({'success': false, 'detail': 'no'}, 404);
      });
      final bytes = await api(client)
          .descargarBytesFoto(uuidFotografia: 'f9');
      expect(bytes, [10, 20, 30]);
      expect(
          vistos.any((v) => v.contains('/fotografias/f9')), isTrue,
          reason: 'primero metadatos por GET /fotografias/{uuid}');
      expect(vistos.any((v) => v.endsWith('/uploads/x/f9.png')), isTrue,
          reason: 'luego bytes por host + ruta_archivo');
    });

    test('descargarBytesFoto con ruta conocida omite el GET de metadatos',
        () async {
      var gets = 0;
      final client = MockClient((req) async {
        gets++;
        return http.Response.bytes([7], 200);
      });
      final bytes = await api(client).descargarBytesFoto(
        uuidFotografia: 'f9',
        rutaArchivo: '/uploads/x/f9.jpg',
      );
      expect(bytes, [7]);
      expect(gets, 1, reason: 'una sola llamada: directo a los bytes');
    });

    test('descargarBytesFoto devuelve null si el archivo no existe',
        () async {
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/fotografias/fx')) {
          return _json(_env(data: {'uuid_fotografia': 'fx'}));
        }
        return _json({'success': false, 'detail': 'no'}, 404);
      });
      expect(
          await api(client).descargarBytesFoto(uuidFotografia: 'fx'),
          isNull);
    });
  });
}
