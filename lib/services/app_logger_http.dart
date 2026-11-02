import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_logger.dart';

/// Capa de HTTP con registro automático.
///
/// Es un espejo de las funciones de nivel `http.get/post/put/delete/patch`
/// (`package:http`), pero cada llamada queda registrada en [AppLogger] con:
///   * método y URL completa,
///   * headers enviados,
///   * body del request COMPLETO,
///   * status y body de la respuesta COMPLETOS,
///   * duración,
///   * excepción con stack si la llamada falla.
///
/// Los cuerpos binarios (fotos descargadas, por ejemplo) no se vuelcan como
/// texto (sería ilegible y gigante): se guarda su descriptor (tamaño y
/// content-type). Todo lo demás se guarda íntegro, sin recortes.
class LogHttp {
  LogHttp._();

  static Future<http.Response> get(
    Object url, {
    Map<String, String>? headers,
    bool esErrorEsperado = false,
  }) {
    return _run('GET', url,
        headers: headers,
        esErrorEsperado: esErrorEsperado,
        ejecutar: () => http.get(_asUri(url), headers: headers));
  }

  static Future<http.Response> post(
    Object url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    bool esErrorEsperado = false,
  }) {
    return _run(
      'POST',
      url,
      headers: headers,
      requestBody: body,
      esErrorEsperado: esErrorEsperado,
      ejecutar: () => http.post(_asUri(url),
          headers: headers, body: body, encoding: encoding),
    );
  }

  static Future<http.Response> put(
    Object url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    bool esErrorEsperado = false,
  }) {
    return _run(
      'PUT',
      url,
      headers: headers,
      requestBody: body,
      esErrorEsperado: esErrorEsperado,
      ejecutar: () => http.put(_asUri(url),
          headers: headers, body: body, encoding: encoding),
    );
  }

  static Future<http.Response> delete(
    Object url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    bool esErrorEsperado = false,
  }) {
    return _run(
      'DELETE',
      url,
      headers: headers,
      requestBody: body,
      esErrorEsperado: esErrorEsperado,
      ejecutar: () => http.delete(_asUri(url),
          headers: headers, body: body, encoding: encoding),
    );
  }

  static Future<http.Response> patch(
    Object url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    bool esErrorEsperado = false,
  }) {
    return _run(
      'PATCH',
      url,
      headers: headers,
      requestBody: body,
      esErrorEsperado: esErrorEsperado,
      ejecutar: () => http.patch(_asUri(url),
          headers: headers, body: body, encoding: encoding),
    );
  }

  /// Envía un [http.MultipartRequest] registrando campos, archivos (nombre,
  /// tamaño, content-type — nunca los bytes) y la respuesta completa.
  static Future<http.StreamedResponse> sendMultipart(
    http.MultipartRequest request,
  ) async {
    final sw = Stopwatch()..start();
    final descriptor = _descriptorMultipart(request);
    try {
      final streamed = await request.send();
      sw.stop();
      final response = await http.Response.fromStream(streamed);
      AppLogger.instance.api(
        metodo: request.method,
        url: request.url.toString(),
        estado: response.statusCode,
        duracion: sw.elapsed,
        request: descriptor,
        response: _descripcionRespuesta(response),
        nota: 'multipart',
      );
      // Re-empaquetar: ya consumimos el stream, así que devolvemos una
      // respuesta equivalente construida desde el Response ya leído.
      return http.StreamedResponse(
        Stream.value(response.bodyBytes),
        response.statusCode,
        contentLength: response.bodyBytes.length,
        request: request,
        headers: response.headers,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (e, s) {
      sw.stop();
      AppLogger.instance.api(
        metodo: request.method,
        url: request.url.toString(),
        duracion: sw.elapsed,
        request: descriptor,
        error: e.toString(),
        stack: s,
      );
      rethrow;
    }
  }

  // ── internals ──────────────────────────────────────────────────────────────

  static Uri _asUri(Object url) => url is Uri ? url : Uri.parse('$url');

  static Future<http.Response> _run(
    String metodo,
    Object url, {
    Map<String, String>? headers,
    Object? requestBody,
    bool esErrorEsperado = false,
    required Future<http.Response> Function() ejecutar,
  }) async {
    final sw = Stopwatch()..start();
    final uri = _asUri(url);
    final reqTexto = _descripcionRequest(requestBody, headers);
    try {
      final res = await ejecutar();
      sw.stop();
      // [esErrorEsperado] solo exime el 404 (el recurso ya no está en el
      // servidor: foto legacy o eliminada). Un 5xx u otro >=400 sigue
      // registrándose como error.
      AppLogger.instance.api(
        metodo: metodo,
        url: uri.toString(),
        estado: res.statusCode,
        duracion: sw.elapsed,
        request: reqTexto,
        response: _descripcionRespuesta(res),
        esErrorEsperado: esErrorEsperado && res.statusCode == 404,
      );
      return res;
    } catch (e, s) {
      sw.stop();
      AppLogger.instance.api(
        metodo: metodo,
        url: uri.toString(),
        duracion: sw.elapsed,
        request: reqTexto,
        error: e.toString(),
        stack: s,
      );
      rethrow;
    }
  }

  static String? _descripcionRequest(
    Object? body,
    Map<String, String>? headers,
  ) {
    if (body == null && (headers == null || headers.isEmpty)) return null;
    final partes = <String>[];
    if (headers != null && headers.isNotEmpty) {
      partes.add('HEADERS: ${jsonEncode(headers)}');
    }
    if (body != null) {
      final texto = body is String ? body : jsonEncode(body);
      partes.add('BODY: $texto');
    }
    return partes.join('\n');
  }

  static String _descripcionRespuesta(http.Response res) {
    final tipo = res.headers['content-type'] ?? '';
    final esBinario = !tipo.contains('json') &&
        !tipo.contains('text') &&
        !tipo.contains('xml') &&
        !tipo.contains('html') &&
        res.bodyBytes.isNotEmpty &&
        _hueleBinario(res.bodyBytes);
    if (esBinario) {
      return '[binario: ${res.bodyBytes.length} bytes, $tipo]';
    }
    return res.body;
  }

  static bool _hueleBinario(List<int> bytes) {
    // Si una fracción grande de los primeros bytes no es texto imprimible,
    // se trata como binario (evita volcar imágenes a la BD de logs).
    final n = bytes.length < 512 ? bytes.length : 512;
    if (n == 0) return false;
    var raros = 0;
    for (var i = 0; i < n; i++) {
      final b = bytes[i];
      final imprimible =
          b == 0x09 || b == 0x0A || b == 0x0D || (b >= 0x20 && b <= 0x7E);
      if (!imprimible) raros++;
    }
    return raros > n ~/ 10;
  }

  static String _descriptorMultipart(http.MultipartRequest request) {
    final sb = StringBuffer();
    sb.writeln('HEADERS: ${jsonEncode(request.headers)}');
    if (request.fields.isNotEmpty) {
      sb.writeln('FIELDS: ${jsonEncode(request.fields)}');
    }
    for (final f in request.files) {
      sb.writeln(
        'FILE: campo=${f.field} nombre=${f.filename} '
        'tam=${f.length} bytes '
        'tipo=${f.contentType}',
      );
    }
    return sb.toString();
  }
}
