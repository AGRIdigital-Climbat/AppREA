/// El transporte del puente, con `MockClient`: sin red ni token.
///
/// Se prueban dos cosas: que pide y manda lo que dice el contrato (`/puente`,
/// `/puente/stream`, `X-API-Key`, snake_case) y que traduce cada fallo a
/// [PuenteError]. La cadena de respaldos (reintentar, extraer) es del provider,
/// no de este servicio, y se prueba en `edan_ia_borrador_provider_test.dart`.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rea/services/edan_ia/puente_models.dart';
import 'package:rea/services/edan_ia/puente_service.dart';

PuenteService _servicio(MockClient cliente) =>
    PuenteService(baseUrl: 'https://test.puente', apiKey: 'llave', client: cliente);

/// El cuerpo SSE de un turno del puente, en bytes UTF-8.
///
/// `http.Response(String, ...)` codifica en Latin-1 y rompe los acentos; el
/// servicio decodifica UTF-8, así que el fixture debe ir como bytes.
http.Response _sse(List<Map<String, dynamic>> eventos) => http.Response.bytes(
      utf8.encode([
        for (final e in eventos) 'data: ${jsonEncode(e)}',
        'data: [DONE]',
      ].join('\n')),
      200,
    );

final _done = {
  'tipo': 'done',
  'respuesta': 'Lamento lo de Yapacaní.',
  'json': {
    'parche': {'municipio': 'Yapacaní'},
  },
  'formato': 'json',
  'modelo': 'openai/gpt-oss-20b',
  'proveedor': 'Groq-adrian',
  'intentos': 1,
  'tokens': {'entrada': 5, 'salida': 3, 'razonamiento': 0},
  'avisos': <String>[],
};

final _request = PuenteRequest(
  instruccion: 'inst',
  mensajes: const [Mensaje('user', 'hola')],
  formato: 'json',
  maxTokens: 1200,
  temperatura: 0.3,
);

void main() {
  group('enviar (POST /puente)', () {
    test('200: parsea el envelope y manda la clave y snake_case', () async {
      http.Request? visto;
      final cliente = MockClient((req) async {
        visto = req;
        return http.Response(jsonEncode(_done), 200);
      });

      final res = await _servicio(cliente).enviar(_request);

      expect(visto!.url.path, '/puente');
      expect(visto!.headers['X-API-Key'], 'llave');
      final body = jsonDecode(visto!.body) as Map<String, dynamic>;
      expect(body['instruccion'], 'inst');
      expect(body['max_tokens'], 1200);
      expect(body.containsKey('llm_externo'), isFalse);
      expect(res.parche, {'municipio': 'Yapacaní'});
    });

    test('401 no_autorizado se traduce a PuenteError', () async {
      final cliente = MockClient((_) async => http.Response(
            jsonEncode({
              'tipo': 'error',
              'codigo': 'no_autorizado',
              'mensaje': 'Falta o es invalida la cabecera X-API-Key.',
              'reintentable': false,
              'esperar_ms': null,
            }),
            401,
          ));

      expect(
        () => _servicio(cliente).enviar(_request),
        throwsA(isA<PuenteError>()
            .having((e) => e.codigo, 'codigo', 'no_autorizado')),
      );
    });

    test('cuerpo no JSON en error cae en proveedor_caido', () async {
      final cliente = MockClient((_) async => http.Response('nope', 503));
      expect(
        () => _servicio(cliente).enviar(_request),
        throwsA(isA<PuenteError>()
            .having((e) => e.codigo, 'codigo', 'proveedor_caido')),
      );
    });

    test('200 con cuerpo vacío no rompe', () async {
      final cliente = MockClient((_) async => http.Response('', 200));
      final res = await _servicio(cliente).enviar(_request);
      expect(res.respuesta, '');
      expect(res.formato, 'texto');
    });
  });

  group('enviarStream (POST /puente/stream)', () {
    test('eventos en orden, onJson una vez y done autoritativo', () async {
      http.Request? visto;
      final tokens = <String>[];
      final jsones = <Map<String, dynamic>>[];
      final cliente = MockClient((req) async {
        visto = req;
        return _sse([
          {'tipo': 'token', 'texto': 'Lamento'},
          {'tipo': 'token', 'texto': ' lo de Yapacaní.'},
          {'tipo': 'json', 'json': _done['json']},
          _done,
        ]);
      });

      final res = await _servicio(cliente).enviarStream(
        _request,
        onToken: tokens.add,
        onJson: jsones.add,
      );

      expect(visto!.url.path, '/puente/stream');
      expect(tokens.join(), 'Lamento lo de Yapacaní.');
      expect(jsones, hasLength(1));
      expect(jsones.single['parche'], {'municipio': 'Yapacaní'});
      expect(res.respuesta, 'Lamento lo de Yapacaní.');
      expect(res.formato, 'json');
      expect(res.modelo, 'openai/gpt-oss-20b');
    });

    test('un reintento no reenvía prosa: done.respuesta es autoritativo', () async {
      final seen = <String>[];
      final cliente = MockClient((_) async => _sse([
            {
              'tipo': 'done',
              'respuesta': '{"parche":{}}',
              'json': null,
              'formato': 'json',
              'modelo': 'm',
              'proveedor': 'p',
              'intentos': 2,
              'tokens': {'entrada': 0, 'salida': 0},
              'avisos': <String>['reintento_por_json_invalido'],
            },
          ]));

      final res = await _servicio(cliente)
          .enviarStream(_request, onToken: (t) => seen.add(t));

      // Con intentos>1 el puente no emite eventos token (§5): el servicio no
      // inventa prosa, y `done.respuesta` es la que manda.
      expect(seen, isEmpty);
      expect(res.intentos, 2);
      expect(res.respuesta, '{"parche":{}}');
      expect(res.parche, isNull);
    });

    test('error temprano (HTTP 401) lanza PuenteError sin tocar onToken', () async {
      final cliente = MockClient((_) async => http.Response(
            jsonEncode({'codigo': 'no_autorizado', 'reintentable': false}),
            401,
          ));

      expect(
        () => _servicio(cliente).enviarStream(_request, onToken: (_) {}),
        throwsA(isA<PuenteError>()
            .having((e) => e.codigo, 'codigo', 'no_autorizado')),
      );
    });

    test('evento error a mitad de stream marca formatoCaidoEnTexto', () async {
      final cliente = MockClient((_) async => _sse([
            {'tipo': 'token', 'texto': 'empezó a hablar'},
            {
              'tipo': 'error',
              'codigo': 'json_invalido',
              'reintentable': false,
            },
          ]));

      await expectLater(
        () => _servicio(cliente)
            .enviarStream(_request, onToken: (_) {}),
        throwsA(isA<PuenteError>()
            .having((e) => e.formatoCaidoEnTexto, 'formatoCaidoEnTexto', isTrue)
            .having((e) => e.hayQueExtraer, 'hayQueExtraer', isTrue)),
      );
    });

    test('sin evento done devuelve lo acumulado como texto', () async {
      final cliente = MockClient((_) async => _sse([
            {'tipo': 'token', 'texto': 'solo texto'},
          ]));

      final res = await _servicio(cliente)
          .enviarStream(_request, onToken: (_) {});
      expect(res.respuesta, 'solo texto');
      expect(res.formato, 'texto');
    });
  });
}