/// Contrato de los modelos del puente, sin red: serialización y deserialización.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rea/services/edan_ia/puente_models.dart';

void main() {
  group('PuenteRequest.toJson', () {
    test('traduce a snake_case y omite los null', () {
      final j = PuenteRequest(
        instruccion: 'inst',
        mensajes: const [Mensaje('user', 'hola')],
        formato: 'json',
        maxTokens: 1200,
        temperatura: 0.3,
        razonamiento: 'off',
      ).toJson();

      expect(j['instruccion'], 'inst');
      expect(j['mensajes'], [
        {'role': 'user', 'content': 'hola'},
      ]);
      expect(j['formato'], 'json');
      expect(j['max_tokens'], 1200);
      expect(j['temperatura'], 0.3);
      expect(j['razonamiento'], 'off');
      expect(j.containsKey('json_schema'), isFalse);
      expect(j.containsKey('stop'), isFalse);
      // `llm_externo` null no se manda: el modo global sortea el proveedor.
      expect(j.containsKey('llm_externo'), isFalse);
    });

    test('llm_externo false se manda explícito (forzar local)', () {
      final j = PuenteRequest(llmExterno: false).toJson();
      expect(j['llm_externo'], isFalse);
    });

    test('configura intentos y json_schema', () {
      final j = PuenteRequest(
        intentosJson: 2,
        jsonSchema: {'type': 'object'},
      ).toJson();
      expect(j['intentos_json'], 2);
      expect(j['json_schema'], {'type': 'object'});
    });
  });

  group('PuenteResponse.fromJson', () {
    test('lee el envelope completo', () {
      final r = PuenteResponse.fromJson({
        'respuesta': 'Lamento lo de Yapacaní.',
        'json': {
          'parche': {'municipio': 'Yapacaní'},
        },
        'formato': 'json',
        'modelo': 'openai/gpt-oss-20b',
        'proveedor': 'Groq-adrian',
        'intentos': 2,
        'tokens': {'entrada': 10, 'salida': 20, 'razonamiento': 5},
        'avisos': ['reintento_por_json_invalido'],
      });

      expect(r.respuesta, 'Lamento lo de Yapacaní.');
      expect(r.formato, 'json');
      expect(r.modelo, 'openai/gpt-oss-20b');
      expect(r.intentos, 2);
      expect(r.tokens.entrada, 10);
      expect(r.tokens.razonamiento, 5);
      expect(r.avisos, ['reintento_por_json_invalido']);
      expect(r.parche, {'municipio': 'Yapacaní'});
    });

    test('parche es null si no vino (respuesta_no_string), sin romper', () {
      final r = PuenteResponse.fromJson({
        'respuesta': 'texto',
        'formato': 'json',
        'modelo': 'm',
        'proveedor': 'p',
      });
      expect(r.parche, isNull);
      expect(r.intentos, 1);
      expect(r.tokens.salida, 0);
      expect(r.avisos, isEmpty);
    });

    test('respuesta vacía se tolera', () {
      final r = PuenteResponse.fromJson({});
      expect(r.respuesta, '');
      expect(r.formato, 'texto');
    });
  });

  group('PuenteError', () {
    test('lee campos y defaults', () {
      final e = PuenteError.fromJson({
        'codigo': 'rate_limit',
        'mensaje': 'límite',
        'reintentable': true,
        'esperar_ms': 12000,
        'detalle': {},
      });
      expect(e.codigo, 'rate_limit');
      expect(e.reintentable, isTrue);
      expect(e.esperarMs, 12000);
      expect(e.hayQueExtraer, isFalse);
    });

    test('json_invalido es el que manda al extractor', () {
      final e = PuenteError.fromJson({'codigo': 'json_invalido'});
      expect(e.hayQueExtraer, isTrue);
    });

    test('formatoCaidoEnTexto (200 con texto) también baja al extractor', () {
      final e = PuenteError.fromJson({'codigo': 'x'});
      e.formatoCaidoEnTexto = true;
      expect(e.hayQueExtraer, isTrue);
    });

    test('cuerpo sin codigo cae en proveedor_caido', () {
      expect(PuenteError.fromJson({}).codigo, 'proveedor_caido');
    });
  });
}