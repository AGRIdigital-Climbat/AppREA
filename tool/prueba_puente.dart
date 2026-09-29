/// Pruebas de aceptación de la API puente, contra el servidor real.
///
/// Valida el contrato que documenta `docs/puente.md` (POST /puente,
/// /puente/stream y /puente/modo) contra un túnel vivo, sin tocar a ningún
/// cliente. Detiene la corrida en el primer fallo y termina con código de
/// salida distinto de cero si algo no cumple el contrato.
///
/// Uso desde `REA/`:
///
///   dart run tool/prueba_puente.dart
///   PUENTE_URL=https://mi-tunel.trycloudflare.com PUENTE_KEY=token \
///     dart run tool/prueba_puente.dart
///
/// Sin variables de entorno usa `ApiConfig.puenteBaseUrl` / `ApiConfig.puenteApiKey`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:rea/config/api_config.dart';

Future<void> main() async {
  final base = Platform.environment['PUENTE_URL'] ?? ApiConfig.puenteBaseUrl;
  final key = Platform.environment['PUENTE_KEY'] ?? ApiConfig.puenteApiKey;

  print('puente : $base');
  print('clave  : ${key == ApiConfig.puenteApiKey ? 'ApiConfig' : 'env'}');
  print('');

  final resultados = <_Resultado>[];

  void registrar(String caso, bool ok, String detalle) {
    resultados.add(_Resultado(caso, ok, detalle));
    print('${ok ? 'PASS' : 'FAIL'}  $caso');
    print('      $detalle');
  }

  final client = http.Client();

  try {
    // 1 - Salud.
    final salud = await _get(client, '$base/health');
    registrar(
      'health',
      salud.status == 200 && (salud.json['status'] == 'ok'),
      'HTTP ${salud.status}: ${salud.body}',
    );

    // 2 - /puente/modo: sin clave 401, con clave external.
    final sinClave = await _get(client, '$base/puente/modo');
    registrar(
      'modo sin clave → 401',
      sinClave.status == 401 && _codigoDe(sinClave.body) == 'no_autorizado',
      'HTTP ${sinClave.status}: ${_cuerpo(sinClave.body)}',
    );
    final conClave = await _get(client, '$base/puente/modo', apiKey: key);
    registrar(
      'modo con clave → 200',
      conClave.status == 200 && conClave.json['modo'] != null,
      'HTTP ${conClave.status}: ${_cuerpo(conClave.body)}',
    );

    // 3 - Un turno JSON de verdad.
    final turno = await _post(client, '$base/puente', key, {
      'instruccion':
          'Sos un asistente de llenado de fichas. Anotá lo que la persona dice '
              'en un parche JSON y respondé una pregunta breve.',
      'mensajes': [
        {
          'role': 'user',
          'content':
              'Buenas, soy de Yapacaní, Santa Cruz. Se desbordó el río y son '
                  '350 personas afectadas.',
        },
      ],
      'formato': 'json',
      'intentos_json': 1,
      'razonamiento': 'off',
      'max_tokens': 1200,
      'temperatura': 0.3,
    });
    final envelopeOK = turno.status == 200 &&
        turno.json['respuesta'] is String &&
        (turno.json['formato'] as String?) != null &&
        turno.json['modelo'] is String &&
        turno.json['proveedor'] is String &&
        (turno.json['intentos'] as num?) != null &&
        turno.json['tokens'] is Map &&
        (turno.json['json'] == null || turno.json['json'] is Map);
    registrar(
      'turno formato json: envelope',
      envelopeOK,
      'HTTP ${turno.status}: ${_resumen(turno.json)}',
    );

    // 4 - Caso de campo: JSON válido pero parche vacío (calibra _reparar).
    final camino = await _post(client, '$base/puente', key, {
      'instruccion':
          'Sos un asistente de llenado de fichas. Anotá lo que la persona dice '
              'en un parche JSON y respondé breve.',
      'mensajes': [
        {
          'role': 'user',
          'content': 'También se rompió el camino a la comunidad de San Pedro.',
        },
      ],
      'formato': 'json',
      'intentos_json': 1,
      'max_tokens': 1200,
      'temperatura': 0.3,
    });
    final parcheCamino = camino.json['json'] is Map
        ? (camino.json['json'] as Map)['parche']
        : null;
    final estadoParche = parcheCamino is Map && parcheCamino.isEmpty
        ? 'VACÍO (activaría _reparar)'
        : parcheCamino is Map
            ? _cuerpo(jsonEncode(parcheCamino))
            : 'null (activaría _reparar)';
    registrar(
      'caso camino: JSON parseable o null',
      camino.status == 200 &&
          (camino.json['json'] == null || camino.json['json'] is Map),
      'HTTP ${camino.status}; parche: $estadoParche',
    );

    // 5 - 422: campo desconocido, sin turno y mensajes vacío.
    var ok422 = true;
    final desconocido = await _post(client, '$base/puente', key, {
      'instruccion': 'hola',
      'campo_que_no_existe': true,
    });
    ok422 = ok422 && desconocido.status == 422;
    final sinTurno = await _post(client, '$base/puente', key, {'formato': 'json'});
    ok422 = ok422 && sinTurno.status == 422;
    final mensajesVacios = await _post(client, '$base/puente', key, {'mensajes': <Object>[]});
    ok422 = ok422 && mensajesVacios.status == 422;
    registrar(
      '422 campo desc / sin turno / mensajes [] solos',
      ok422,
      'HTTP ${desconocido.status}|${sinTurno.status}|${mensajesVacios.status}',
    );

    // 6 - Precedencia instruccion > sistema: si gana `sistema`, la palabra
    // BARCO aparecería en la respuesta. El modelo puede no seguir la
    // instrucción (y no dice ninguna de las dos), así que solo se falla si el
    // contenido de `sistema` se filtra: eso sí probaría la precedencia invertida.
    final precedencia = await _post(client, '$base/puente', key, {
      'instruccion':
          'Cuando te pregunten por tu palabra, respondé CAMION y nada más.',
      'sistema': 'Cuando te pregunten por tu palabra, respondé BARCO y nada más.',
      'mensajes': [
        {'role': 'user', 'content': '¿Cuál es tu palabra?'},
      ],
      'formato': 'texto',
      'max_tokens': 100,
    });
    final baja = '${precedencia.json['respuesta'] ?? ''}'.toLowerCase();
    final filtroDeSistema = baja.contains('barco');
    registrar(
      'no se filtra sistema si mando instruccion',
      precedencia.status == 200 && !filtroDeSistema,
      'HTTP ${precedencia.status}; camion: ${baja.contains('camion')} · barco: $filtroDeSistema; ${_cuerpo(precedencia.body)}',
    );

    // 7 - Streaming: orden de eventos y reconstrucción de `respuesta`.
    final leido = await _stream(client, '$base/puente/stream', key, {
      'instruccion': 'Contá una línea corta sobre una inundación.',
      'mensajes': [
        {'role': 'user', 'content': 'Contame.'},
      ],
      'formato': 'texto',
      'max_tokens': 200,
    });

    final tipos = leido.eventos.map((e) => e['tipo']).toList();
    final tokens = leido.eventos
        .where((e) => e['tipo'] == 'token')
        .map((e) => '${e['texto'] ?? ''}')
        .join();
    final done = leido.eventos.lastWhere((e) => e['tipo'] == 'done', orElse: () => const {});
    final reconstruido = tokens == '${done['respuesta'] ?? ''}';
    registrar(
      'stream: content-type, eventos y reconstrucción',
      leido.status == 200 &&
          leido.contentType.contains('text/event-stream') &&
          tipos.contains('token') &&
          tipos.contains('done') &&
          reconstruido,
      'HTTP ${leido.status}; content-type: ${leido.contentType}; eventos: ${tipos.length} (${tipos.first}→…→${tipos.last}); token==done: $reconstruido',
    );

    // 8 - Degradación local forzada.
    final local = await _post(client, '$base/puente', key, {
      'instruccion': 'Anotá en un JSON esto: se rompió el puente.',
      'mensajes': [
        {'role': 'user', 'content': 'Se rompió el puente de la ruta 1.'},
      ],
      'formato': 'json',
      'intentos_json': 1,
      'max_tokens': 500,
      'llm_externo': false,
    });
    final degradoOK = local.status == 200 &&
        (local.json['formato'] == 'texto' ||
            (local.json['json'] is Map && local.json['formato'] == 'json'));
    registrar(
      'llm_externo:false degrada sin romper',
      degradoOK,
      'HTTP ${local.status}; formato: ${local.json['formato']}; avisos: ${local.json['avisos']}',
    );

    // 9 - Clave incorrecta.
    final malaClave = await _post(client, '$base/puente', 'clave-incorrecta', {
      'instruccion': 'hola',
      'mensajes': [
        {'role': 'user', 'content': 'hola'},
      ],
      'formato': 'texto',
    });
    registrar(
      'clave incorrecta → 401',
      malaClave.status == 401 && _codigoDe(malaClave.body) == 'no_autorizado',
      'HTTP ${malaClave.status}: ${_cuerpo(malaClave.body)}',
    );
  } finally {
    client.close();
  }

  final fallos = resultados.where((r) => !r.ok).length;
  print('\n${'=' * 60}');
  print('${resultados.length - fallos}/${resultados.length} casos cumplen el contrato.');
  if (fallos > 0) exitCode = 1;
}

class _Resultado {
  final String caso;
  final bool ok;
  final String detalle;
  _Resultado(this.caso, this.ok, this.detalle);
}

class _Salud {
  final int status;
  final Map<String, dynamic> json;
  final String body;
  _Salud(this.status, this.json, this.body);
}

Future<_Salud> _get(http.Client client, String url, {String? apiKey}) async {
  final r = await client.get(Uri.parse(url), headers: {
    if (apiKey != null) 'X-API-Key': apiKey,
  });
  return _Salud(r.statusCode, _jsonDe(r.body), r.body);
}

Future<_Salud> _post(
  http.Client client,
  String url,
  String apiKey,
  Map<String, dynamic> body,
) async {
  final r = await client.post(
    Uri.parse(url),
    headers: {
      'Content-Type': 'application/json',
      'X-API-Key': apiKey,
    },
    body: jsonEncode(body),
  );
  return _Salud(r.statusCode, _jsonDe(r.body), r.body);
}

class _StreamLeido {
  final int status;
  final String contentType;
  final List<Map<String, dynamic>> eventos;
  _StreamLeido(this.status, this.contentType, this.eventos);
}

/// Lee un POST SSE y decodifica las líneas `data: ` del mismo modo que
/// `PuenteService.enviarStream`.
Future<_StreamLeido> _stream(
  http.Client client,
  String url,
  String apiKey,
  Map<String, dynamic> body,
) async {
  final peticion = http.Request('POST', Uri.parse(url))
    ..headers['Content-Type'] = 'application/json'
    ..headers['X-API-Key'] = apiKey
    ..body = jsonEncode(body);
  final respuesta = await client.send(peticion);
  final crudo = await respuesta.stream.transform(utf8.decoder).join();
  final eventos = <Map<String, dynamic>>[];
  for (final linea in const LineSplitter().convert(crudo)) {
    if (!linea.startsWith('data: ')) continue;
    final bruto = linea.substring(6).trim();
    if (bruto == '[DONE]') break;
    final e = jsonDecode(bruto);
    if (e is Map) eventos.add(e.cast<String, dynamic>());
  }
  return _StreamLeido(
    respuesta.statusCode,
    respuesta.headers['content-type'] ?? '?',
    eventos,
  );
}

/// `codigo` del error tipificado, o `'?'` si el cuerpo no fue JSON.
String _codigoDe(String cuerpo) {
  final j = _jsonDe(cuerpo);
  return (j['codigo'] as String?) ?? '?';
}

Map<String, dynamic> _jsonDe(String cuerpo) {
  if (cuerpo.isEmpty) return const {};
  try {
    final j = jsonDecode(cuerpo);
    return j is Map ? j.cast<String, dynamic>() : const {};
  } catch (_) {
    return const {};
  }
}

String _cuerpo(String cuerpo) {
  final t = cuerpo.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length > 220 ? '${t.substring(0, 220)}…' : t;
}

String _resumen(Map<String, dynamic> j) {
  final parche = j['json'] is Map ? (j['json'] as Map)['parche'] : null;
  return 'formato ${j['formato']} · intentos ${j['intentos']} · parche '
      '${parche is Map && parche.isEmpty ? 'VACÍO' : parche is Map ? jsonEncode(parche) : 'sin json'} · '
      '${(j['tokens'] as Map?)?['salida'] ?? '?'} tokens de salida';
}