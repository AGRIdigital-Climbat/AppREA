// Humo: ¿el puente respeta `json_schema`? El cliente de la app no lo manda,
// pero el OpenAPI lo documenta ("Schema opcional contra el cual validar
// `json`"). Si lo respeta, se puede obligar la forma exacta del envelope y
// capaz el reintento por JSON inválido desaparece solo.
//
//   dart run tool/smoke_json_schema.dart
library;

import 'dart:convert';

import 'package:rea/config/api_config.dart';
import 'package:rea/services/edan_ia/puente_models.dart';
import 'package:rea/services/edan_ia/puente_service.dart';

const _schema = {
  'type': 'object',
  'properties': {
    'respuesta': {
      'type': 'string',
      'description': 'Lo que se dice, terminado en UNA pregunta.',
    },
    'siguiente_pregunta': {
      'type': ['string', 'null'],
      'description': 'Solo si la querés separar de la respuesta.',
    },
    'parche': {'type': 'object'},
  },
  'required': ['respuesta', 'parche'],
  'additionalProperties': false,
};

void main() async {
  final puente = PuenteService(
    baseUrl: ApiConfig.puenteBaseUrl,
    apiKey: ApiConfig.puenteApiKey,
  );

  for (final usarSchema in [false, true]) {
    final reloj = Stopwatch()..start();
    final res = await puente.enviarStream(
      PuenteRequest(
        instruccion: '''
Sos quien llena un formulario EDAN de Bolivia. Devolvé un objeto JSON con
"respuesta" (lo que le decís a la persona) y "parche" (los datos que dijo).

La persona dijo: "Estamos en Yapacaní, Ichilo, Santa Cruz. Ayer hubo una
inundación fuerte."

Contestale acknowledging lo que dijo y terminá con UNA pregunta sobre lo que
falta de la ficha. No le pidas el municipio ni el departamento: ya los dijo.
''',
        mensajes: const [
          Mensaje('user', 'Estamos en Yapacaní, Ichilo, Santa Cruz.'),
          Mensaje('assistant', 'Anotado, ¿qué pasó?'),
          Mensaje('user', 'Ayer hubo una inundación fuerte.'),
        ],
        formato: 'json',
        jsonSchema: usarSchema ? _schema : null,
        maxTokens: ApiConfig.puenteMaxTokens,
        temperatura: ApiConfig.puenteTemperatura,
        razonamiento: 'off',
        intentosJson: 1,
      ),
      onToken: (_) {},
    );
    reloj.stop();

    // ignore: avoid_print
    print('=== json_schema=$usarSchema');
    // ignore: avoid_print
    print('  ${reloj.elapsedMilliseconds} ms · intentos=${res.intentos} '
        '· avisos=${res.avisos}');
    // ignore: avoid_print
    print('  modelo=${res.modelo} · proveedor=${res.proveedor}');
    // ignore: avoid_print
    print('  claves json=${res.json?.keys.toList()}');
    // ignore: avoid_print
    print('  respuesta=${_corta((res.json?['respuesta'] ?? res.respuesta).toString())}');
    // ignore: avoid_print
    print('  cruda=${_corta(res.respuesta)}');
    // ignore: avoid_print
    print('  pretty=${const JsonEncoder.withIndent(' ').convert(res.json ?? const {})}');
  }
}

String _corta(String s) => s.length <= 300 ? s : '${s.substring(0, 300)}...';
