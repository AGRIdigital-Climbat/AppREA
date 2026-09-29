import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../config/api_config.dart';
import '../../models/ai/asistente_chat_message.dart';

class RagChatResponse {
  final String texto;

  const RagChatResponse({required this.texto});
}

class AsistenteIAService {
  static final AsistenteIAService instance = AsistenteIAService._();
  AsistenteIAService._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String? _apiKey;

  Future<void> init() async {
    _apiKey = await _storage.read(key: 'rag_api_key');
    _apiKey ??= ApiConfig.ragApiKey;
  }

  Future<void> setApiKey(String key) async {
    _apiKey = key;
    await _storage.write(key: 'rag_api_key', value: key);
  }

  String? get apiKey => _apiKey;
  bool get hasApiKey => _apiKey != null && _apiKey!.isNotEmpty;

  Map<String, String> _buildHeaders() {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (hasApiKey) {
      headers['X-API-Key'] = _apiKey!;
    }
    return headers;
  }

  Map<String, dynamic> _buildBody(
    String pregunta,
    int? grupoId,
    String? termino,
  ) {
    final tieneGrupo = grupoId != null && grupoId > 0;
    final body = <String, dynamic>{
      'pregunta': pregunta,
      'max_tokens': 700,
    };
    if (tieneGrupo) {
      body['grupo_id'] = grupoId;
      if (termino != null && termino.isNotEmpty) {
        body['termino'] = termino;
      }
    } else {
      body['limite'] = 15;
    }
    return body;
  }

  Stream<String> chatStream({
    required String pregunta,
    int? grupoId,
    String? termino,
    void Function(List<AsistenteFuente> fuentes)? onFuentes,
    void Function(Map<String, AsistenteCita> citas)? onCitas,
  }) async* {
    final body = jsonEncode(_buildBody(pregunta, grupoId, termino));

    final request =
        http.Request('POST', Uri.parse('${ApiConfig.ragBaseUrl}/chat'))
          ..headers.addAll(_buildHeaders())
          ..body = body;

    final streamed = await request.send().timeout(
      const Duration(seconds: 60),
      onTimeout: () =>
          throw Exception('Timeout conectando con el motor IA (60s)'),
    );

    if (streamed.statusCode >= 300) {
      final resp = await streamed.stream.bytesToString();
      throw Exception(
        'Error MotorIA ${streamed.statusCode}: ${_extraerDetail(resp)}',
      );
    }

    var buffer = '';
    await for (final chunk in streamed.stream.transform(utf8.decoder)) {
      buffer += chunk;
      while (true) {
        final idx = buffer.indexOf('\n');
        if (idx < 0) break;
        final linea = buffer.substring(0, idx).trim();
        buffer = buffer.substring(idx + 1);
        if (!linea.startsWith('data:')) continue;
        final payload = linea.substring(5).trim();
        if (payload.isEmpty) continue;
        try {
          final json = jsonDecode(payload) as Map<String, dynamic>;
          final type = json['type'] as String?;
          if (type == 'token') {
            final content = json['content'] as String?;
            if (content != null && content.isNotEmpty) {
              yield content;
            }
          } else if (type == 'done') {
            final fuentes = (json['fuentes'] as List<dynamic>? ?? [])
                .map((e) =>
                    AsistenteFuente.fromJson(Map<String, dynamic>.from(e)))
                .toList();
            final citas = (json['citas'] as Map<String, dynamic>? ?? {})
                .map(
                  (k, v) => MapEntry(
                    k,
                    AsistenteCita.fromJson(Map<String, dynamic>.from(v)),
                  ),
                );
            onFuentes?.call(fuentes);
            onCitas?.call(citas);
            return;
          }
        } catch (_) {}
      }
    }
  }

  Future<RagChatResponse> chat({
    required String pregunta,
    int? grupoId,
    String? termino,
  }) async {
    final body = jsonEncode(_buildBody(pregunta, grupoId, termino));

    final response = await http
        .post(
          Uri.parse('${ApiConfig.ragBaseUrl}/chat'),
          headers: _buildHeaders(),
          body: body,
        )
        .timeout(
          const Duration(seconds: 60),
          onTimeout: () => throw Exception('Timeout MotorIA (60s)'),
        );

    if (response.statusCode >= 300) {
      throw Exception(
        'Error MotorIA ${response.statusCode}: ${_extraerDetail(response.body)}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final texto =
        json['respuesta'] as String? ?? json['content'] as String? ?? '';
    return RagChatResponse(texto: texto);
  }

  String _extraerDetail(String resp) {
    try {
      final json = jsonDecode(resp);
      if (json is Map<String, dynamic>) {
        final detail = json['detail'];
        if (detail is String && detail.isNotEmpty) return detail;
      }
    } catch (_) {}
    return resp.isEmpty ? 'Sin detalle' : resp;
  }
}