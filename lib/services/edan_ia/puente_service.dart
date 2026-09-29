/// Cliente HTTP de la API puente (ver `docs/puente.md`).
///
/// Dos verbos:
///
/// - [enviar]: un turno completo (`POST /puente`, el body ya viene parseado).
/// - [enviarStream]: un turno token a token (`POST /puente/stream`, SSE).
///
/// La clave es la del puente (`API_AUTH_TOKEN`), **no** la del proveedor de
/// Groq: la del proveedor nunca viaja en la app.
///
/// La cadena de respaldos (reintentar, bajar al extractor, subir `max_tokens`)
/// la decide el llamador a partir de [PuenteError.codigo]; este servicio solo
/// traduce el transporte.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'puente_models.dart';

class PuenteService {
  PuenteService({
    required this.baseUrl, // ej. 'https://xxxx.trycloudflare.com'
    required this.apiKey, // API_AUTH_TOKEN. En la app, no la del proveedor
    http.Client? client,
  }) : _http = client ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final http.Client _http;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-API-Key': apiKey,
      };

  Future<PuenteResponse> enviar(PuenteRequest req) async {
    final r = await _http.post(
      Uri.parse('$baseUrl/puente'),
      headers: _headers,
      body: jsonEncode(req.toJson()),
    );
    final cuerpo = _mapaDe(r.body);

    if (r.statusCode != 200) {
      throw PuenteError.fromJson(cuerpo);
    }
    return PuenteResponse.fromJson(cuerpo);
  }

  /// `{}` si el cuerpo no es JSON o está vacío: un 502 con HTML no tiene que
  /// explotar en el parseo, sino quedar como un error sin código.
  static Map<String, dynamic> _mapaDe(String body) {
    if (body.isEmpty) return const {};
    try {
      final j = jsonDecode(body);
      return j is Map ? j.cast<String, dynamic>() : const {};
    } catch (_) {
      return const {};
    }
  }

  /// Un turno en streaming. [onToken] es la prosa visible, [onRazonamiento] el
  /// pensamiento (normalmente lo ocultas). [onJson] dispara UNA vez con el
  /// parche ya parseado: ahí se aplica al borrador.
  ///
  /// Devuelve el envelope final (`done`).
  Future<PuenteResponse> enviarStream(
    PuenteRequest req, {
    required void Function(String) onToken,
    void Function(String)? onRazonamiento,
    void Function(Map<String, dynamic>)? onJson,
  }) async {
    final peticion = http.Request('POST', Uri.parse('$baseUrl/puente/stream'))
      ..headers.addAll(_headers)
      ..body = jsonEncode(req.toJson());

    final respuesta = await _http.send(peticion);
    final cuerpo = await respuesta.stream.transform(utf8.decoder).join();

    if (respuesta.statusCode != 200) {
      // Error temprano: el puente todavía no abrió el stream, así que esto es
      // un status HTTP de verdad y el cuerpo ya viene tipificado.
      final m = cuerpo.isEmpty ? <String, dynamic>{} : jsonDecode(cuerpo);
      throw PuenteError.fromJson(
          m is Map ? m.cast<String, dynamic>() : <String, dynamic>{});
    }

    PuenteResponse? done;
    final StringBuffer respuestaVisible = StringBuffer();

    for (final linea in const LineSplitter().convert(cuerpo)) {
      if (!linea.startsWith('data: ')) continue;
      final bruto = linea.substring(6).trim();
      if (bruto == '[DONE]') break;
      final e = jsonDecode(bruto) as Map<String, dynamic>;

      switch (e['tipo']) {
        case 'token':
          final t = e['texto'] as String? ?? '';
          respuestaVisible.write(t);
          onToken(t);
          break;
        case 'razonamiento':
          onRazonamiento?.call(e['texto'] as String? ?? '');
          break;
        case 'json':
          onJson?.call((e['json'] as Map?)?.cast<String, dynamic>() ?? {});
          break;
        case 'error':
          final err = PuenteError.fromJson(e);
          err.formatoCaidoEnTexto = respuestaVisible.isNotEmpty;
          throw err;
        case 'done':
          done = PuenteResponse.fromJson(e);
          break;
      }
    }

    return done ??
        PuenteResponse(
          respuesta: respuestaVisible.toString(),
          json: null,
          formato: 'texto',
          modelo: '?',
          proveedor: '?',
          intentos: 1,
          tokens: const Tokens(0, 0, 0),
          avisos: const [],
        );
  }
}