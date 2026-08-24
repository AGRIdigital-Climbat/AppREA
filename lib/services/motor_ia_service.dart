import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config/api_config.dart';

class MotorTipo {
  final int id;
  final String nombre;
  final int prioridad;

  const MotorTipo({
    required this.id,
    required this.nombre,
    required this.prioridad,
  });

  factory MotorTipo.fromJson(Map<String, dynamic> json) => MotorTipo(
        id: json['id'] as int,
        nombre: json['nombre'] as String,
        prioridad: json['prioridad'] as int,
      );
}

class MotorDoc {
  final int id;
  final String titulo;
  final int tipoId;
  final String tipoNombre;
  final String? fechaPublicacion;
  final int numPaginas;
  final int totalChunks;

  const MotorDoc({
    required this.id,
    required this.titulo,
    required this.tipoId,
    required this.tipoNombre,
    required this.fechaPublicacion,
    required this.numPaginas,
    required this.totalChunks,
  });

  factory MotorDoc.fromJson(Map<String, dynamic> json) => MotorDoc(
        id: json['id'] as int,
        titulo: json['titulo'] as String,
        tipoId: json['tipo_id'] as int,
        tipoNombre: json['tipo_nombre'] as String? ?? '',
        fechaPublicacion: json['fecha_publicacion'] as String?,
        numPaginas: json['num_paginas'] as int? ?? 0,
        totalChunks: json['total_chunks'] as int? ?? 0,
      );
}

class MotorFuente {
  final int documentoId;
  final String titulo;
  final String tipo;
  final List<String> numerals;
  final double similitud;

  const MotorFuente({
    required this.documentoId,
    required this.titulo,
    required this.tipo,
    required this.numerals,
    required this.similitud,
  });

  factory MotorFuente.fromJson(Map<String, dynamic> json) => MotorFuente(
        documentoId: json['documento_id'] as int,
        titulo: json['titulo'] as String? ?? '',
        tipo: json['tipo'] as String? ?? '',
        numerals: (json['numerals'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        similitud: (json['similitud'] as num?)?.toDouble() ?? 0,
      );
}

class MotorRespuesta {
  final String texto;
  final String? pregunta;
  final List<MotorFuente> fuentes;

  const MotorRespuesta({
    required this.texto,
    required this.pregunta,
    required this.fuentes,
  });
}

class MotorIA {
  static final MotorIA instance = MotorIA._();
  MotorIA._();

  static String get _base => ApiConfig.motorIaBaseUrl;

  static const Map<String, String> _headers = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  Future<http.Response> _get(String path, {Duration timeout = const Duration(seconds: 20)}) {
    return http
        .get(Uri.parse('$_base$path'), headers: _headers)
        .timeout(timeout);
  }

  Future<http.Response> _post(
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 30),
  }) {
    return http
        .post(
          Uri.parse('$_base$path'),
          headers: _headers,
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(timeout);
  }

  Future<List<MotorTipo>> listarTipos() async {
    final response = await _get('/tipos-documento?todos=false');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return (data['tipos'] as List)
          .map((e) => MotorTipo.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    throw Exception('Error ${response.statusCode}');
  }

  Future<List<MotorDoc>> listarDocumentos({int? tipoId, String? q}) async {
    final query = <String>[
      if (tipoId != null) 'tipo_id=$tipoId',
      if (q != null && q.isNotEmpty) 'q=${Uri.encodeQueryComponent(q)}',
      'orden=titulo',
      'dir=asc',
    ].join('&');
    final response = await _get('/documentos${query.isEmpty ? '' : '?$query'}');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return (data['documentos'] as List)
          .map((e) => MotorDoc.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    throw Exception('Error ${response.statusCode}');
  }

  static Future<String> _dirDocumentos() async {
    final dir = await getApplicationDocumentsDirectory();
    final carpeta = Directory('${dir.path}${Platform.pathSeparator}motor_ia');
    if (!await carpeta.exists()) await carpeta.create(recursive: true);
    return carpeta.path;
  }

  /// Devuelve la ruta del PDF ya descargado si existe, o null.
  Future<String?> archivoDocumento(int id, String titulo) async {
    final dir = await _dirDocumentos();
    final file =
        File('$dir${Platform.pathSeparator}${_nombreArchivo(id, titulo)}');
    return await file.exists() ? file.path : null;
  }

  String _nombreArchivo(int id, String titulo) {
    final base = titulo
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_ñÑáéíóúÁÉÍÓÚ\- ]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    return '${id}_${base.isEmpty ? 'documento' : base}.pdf';
  }

  Future<String> descargarDocumento(int id, {String? titulo}) async {
    final response = await _get('/documentos/$id/descargar',
        timeout: const Duration(seconds: 60));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final dir = await _dirDocumentos();
      final file = File(
          '$dir${Platform.pathSeparator}${_nombreArchivo(id, titulo ?? 'documento')}');
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file.path;
    }
    throw Exception('Error ${response.statusCode}');
  }

  /// Chat streaming (SSE). Emite tokens y cierra con la respuesta completa.
  Stream<MotorRespuesta> chatStream(String pregunta, {int limite = 15}) async* {
    final request = http.Request(
      'POST',
      Uri.parse('$_base/chat'),
    )..headers.addAll({
        'Accept': 'text/event-stream',
        'Content-Type': 'application/json',
      })
      ..body = jsonEncode({
        'pregunta': pregunta,
        'limite': limite,
        'umbral': 0.3,
        'tipo_id': null,
      });

    final streamed = await request.send();
    if (streamed.statusCode >= 300) {
      throw Exception('Error ${streamed.statusCode}');
    }

    final texto = StringBuffer();
    MotorRespuesta? finalRespuesta;
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
            final content = json['content'] as String? ?? '';
            if (content.isNotEmpty) {
              texto.write(content);
              yield MotorRespuesta(
                texto: texto.toString(),
                pregunta: pregunta,
                fuentes: const [],
              );
            }
          } else if (type == 'done') {
            final fuentes = (json['fuentes'] as List<dynamic>? ?? [])
                .map((e) => MotorFuente.fromJson(Map<String, dynamic>.from(e)))
                .toList();
            finalRespuesta = MotorRespuesta(
              texto: texto.toString(),
              pregunta: json['pregunta'] as String? ?? pregunta,
              fuentes: fuentes,
            );
          }
        } catch (_) {}
      }
    }

    finalRespuesta ??= MotorRespuesta(
      texto: texto.toString(),
      pregunta: pregunta,
      fuentes: const [],
    );
    yield finalRespuesta;
  }

  /// Fallback por si el chat no genera tokens.
  Future<MotorRespuesta> buscar(String pregunta, {int limite = 5}) async {
    final response = await _post('/busqueda', body: {
      'pregunta': pregunta,
      'limite': limite,
      'umbral': 0.3,
      'tipo_id': null,
    }, timeout: const Duration(seconds: 60));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final fuentes = (data['resultados'] as List)
          .map((e) => MotorFuente(
                documentoId: e['documento_id'] as int,
                titulo: e['titulo'] as String? ?? '',
                tipo: e['tipo'] as String? ?? '',
                numerals: [e['numeral'] as String? ?? ''].where((n) => n.isNotEmpty).toList(),
                similitud: (e['similitud'] as num?)?.toDouble() ?? 0,
              ))
          .toList();
      final intencion = data['intencion'] as String? ?? '';
      final texto = fuentes.isEmpty
          ? 'No encontré información sobre eso. Intenta con otras palabras.'
          : 'Encontré ${fuentes.length} referencia(s)${intencion.isNotEmpty ? ' (intención: $intencion)' : ''}:';
      return MotorRespuesta(
        texto: texto,
        pregunta: pregunta,
        fuentes: fuentes,
      );
    }
    throw Exception('Error ${response.statusCode}');
  }
}
