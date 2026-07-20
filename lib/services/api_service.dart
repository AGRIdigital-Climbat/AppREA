import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../config/api_config.dart';
import '../models/reporte.dart';
import '../models/departamento.dart';
import '../models/provincia.dart';
import '../models/municipio.dart';
import '../models/usuario.dart';

class ApiService {
  static final ApiService _instance = ApiService._();
  static ApiService get instance => _instance;
  ApiService._();

  String? _token;

  void setToken(String? token) {
    _token = token;
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  Future<Map<String, dynamic>> _handleResponse(http.Response response) async {
    if (response.body.isEmpty) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return <String, dynamic>{};
      }
      throw Exception('Error $response.statusCode');
    }
    final body = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    } else {
      throw Exception(
        body['detail'] ?? body['message'] ?? body['error'] ?? 'Error $response.statusCode',
      );
    }
  }

  Future<TokenResponse> login(String usuario, String contrasena) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.authEndpoint}/login'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'usuario': usuario,
        'contrasena': contrasena,
      }),
    ).timeout(const Duration(seconds: 15));
    final body = await _handleResponse(response);
    return TokenResponse.fromJson(body);
  }

  Future<Map<String, dynamic>> register({
    required String usuario,
    required String contrasena,
    required String nombre,
    String? celular,
    String? carnet,
    String? comunidad,
    int? idDepartamento,
    int? idProvincia,
    int? idMunicipio,
  }) async {
    final response = await http.post(
      Uri.parse(ApiConfig.usuariosEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'usuario': usuario,
        'contrasena': contrasena,
        'nombre': nombre,
        'celular': celular,
        'carnet': carnet,
        'comunidad': comunidad,
        'id_departamento': idDepartamento,
        'id_provincia': idProvincia,
        'id_municipio': idMunicipio,
        'id_rol': 4,
        'activo': true,
      }),
    ).timeout(const Duration(seconds: 15));
    final body = await _handleResponse(response);
    return body;
  }

  Future<List<Departamento>> getDepartamentos() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.sharedEndpoint}/departamentos'),
      headers: _headers,
    ).timeout(const Duration(seconds: 10));
    final body = await _handleResponse(response);
    return (body['data'] as List)
        .map((json) => Departamento.fromJson(json))
        .toList();
  }

  Future<List<Provincia>> getProvincias({int? idDepartamento}) async {
    final uri = idDepartamento != null
        ? Uri.parse(
            '${ApiConfig.sharedEndpoint}/provincias?id_departamento=$idDepartamento')
        : Uri.parse('${ApiConfig.sharedEndpoint}/provincias');
    final response = await http.get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));
    final body = await _handleResponse(response);
    return (body['data'] as List)
        .map((json) => Provincia.fromJson(json))
        .toList();
  }

  Future<List<Municipio>> getMunicipios({
    int? idProvincia,
    int? idDepartamento,
  }) async {
    final params = <String>[];
    if (idProvincia != null) params.add('id_provincia=$idProvincia');
    if (idDepartamento != null) params.add('id_departamento=$idDepartamento');
    final queryString = params.isNotEmpty ? '?${params.join('&')}' : '';
    final response = await http.get(
      Uri.parse('${ApiConfig.sharedEndpoint}/municipios$queryString'),
      headers: _headers,
    ).timeout(const Duration(seconds: 10));
    final body = await _handleResponse(response);
    return (body['data'] as List)
        .map((json) => Municipio.fromJson(json))
        .toList();
  }

  Future<List<Reporte>> getReportes({
    int? idEstado,
    int? idMunicipio,
    int skip = 0,
    int limit = 50,
  }) async {
    final params = <String>['skip=$skip', 'limit=$limit'];
    if (idEstado != null) params.add('id_estado=$idEstado');
    if (idMunicipio != null) params.add('id_municipio=$idMunicipio');
    final response = await http.get(
      Uri.parse('${ApiConfig.reaEndpoint}/reportes?${params.join('&')}'),
      headers: _headers,
    ).timeout(const Duration(seconds: 10));
    final body = await _handleResponse(response);
    return (body['data'] as List)
        .map((json) => Reporte.fromJson(json))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getMisResumenReportes({
    required int idUsuario,
    int skip = 0,
    int limit = 50,
  }) async {
    final response = await http.get(
      Uri.parse('${ApiConfig.reaEndpoint}/reportes/mis-resumen?id_usuario=$idUsuario&skip=$skip&limit=$limit'),
      headers: _headers,
    ).timeout(const Duration(seconds: 10));
    final body = await _handleResponse(response);
    return (body['data'] as List)
        .map((json) => Map<String, dynamic>.from(json))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getMisReportes({
    required int idUsuario,
    int skip = 0,
    int limit = 50,
  }) async {
    final response = await http.get(
      Uri.parse('${ApiConfig.reaEndpoint}/reportes/mis-reportes?id_usuario=$idUsuario&skip=$skip&limit=$limit'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    final body = await _handleResponse(response);
    return (body['data'] as List)
        .map((json) => Map<String, dynamic>.from(json))
        .toList();
  }

  Future<String?> downloadImage(String serverPath, String savePath) async {
    try {
      final encodedPath = Uri.encodeComponent(serverPath);
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/upload/descargar/$encodedPath'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final file = File(savePath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(response.bodyBytes);
        return savePath;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Reporte> createReporte(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.reaEndpoint}/reportes'),
      headers: _headers,
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 15));
    final body = await _handleResponse(response);
    return Reporte.fromJson(body['data']);
  }

  Future<Reporte> updateReporte(int id, Map<String, dynamic> data) async {
    final response = await http.put(
      Uri.parse('${ApiConfig.reaEndpoint}/reportes/$id'),
      headers: _headers,
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 15));
    final body = await _handleResponse(response);
    return Reporte.fromJson(body['data']);
  }

  String _getImageContentType(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  Future<Map<String, dynamic>> uploadFile({
    required String filePath,
    int? idMunicipio,
    String? comunidad,
  }) async {
    final queryParams = <String>[];
    if (idMunicipio != null) queryParams.add('id_municipio=$idMunicipio');
    if (comunidad != null && comunidad.isNotEmpty) queryParams.add('comunidad=$comunidad');
    final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiConfig.baseUrl}/upload$queryString'),
    );

    if (_token != null) {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    request.headers['Accept'] = 'application/json';

    final contentType = _getImageContentType(filePath);
    request.files.add(await http.MultipartFile.fromPath(
      'file',
      filePath,
      contentType: MediaType.parse(contentType),
    ));

    final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamedResponse);
    return _handleResponse(response);
  }

  Future<void> deleteReporte(int id) async {
    await http.delete(
      Uri.parse('${ApiConfig.reaEndpoint}/reportes/$id'),
      headers: _headers,
    ).timeout(const Duration(seconds: 10));
  }

  Future<List<TipoEvento>> getTiposEvento() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.edanEndpoint}/tipo-evento'),
      headers: _headers,
    ).timeout(const Duration(seconds: 10));
    final body = await _handleResponse(response);
    return (body['data'] as List)
        .map((json) => TipoEvento.fromJson(json))
        .toList();
  }

  Future<List<Estado>> getEstados() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.reaEndpoint}/estados'),
      headers: _headers,
    ).timeout(const Duration(seconds: 10));
    final body = await _handleResponse(response);
    return (body['data'] as List)
        .map((json) => Estado.fromJson(json))
        .toList();
  }

  Future<List<Categoria>> getCategorias() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.reaEndpoint}/categorias'),
      headers: _headers,
    ).timeout(const Duration(seconds: 10));
    final body = await _handleResponse(response);
    return (body['data'] as List)
        .map((json) => Categoria.fromJson(json))
        .toList();
  }

  Future<Usuario> getUsuario(int id) async {
    final response = await http.get(
      Uri.parse('${ApiConfig.usuariosEndpoint}/$id'),
      headers: _headers,
    ).timeout(const Duration(seconds: 10));
    final body = await _handleResponse(response);
    return Usuario.fromJson(body['data']);
  }

  Future<Usuario> updateUsuario(int id, {
    String? nombre,
    String? celular,
    String? comunidad,
    int? idDepartamento,
    int? idProvincia,
    int? idMunicipio,
  }) async {
    final data = <String, dynamic>{};
    if (nombre != null) data['nombre'] = nombre;
    if (celular != null) data['celular'] = celular;
    if (comunidad != null) data['comunidad'] = comunidad;
    if (idDepartamento != null) data['id_departamento'] = idDepartamento;
    if (idProvincia != null) data['id_provincia'] = idProvincia;
    if (idMunicipio != null) data['id_municipio'] = idMunicipio;

    final response = await http.put(
      Uri.parse('${ApiConfig.usuariosEndpoint}/$id'),
      headers: _headers,
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 15));
    final body = await _handleResponse(response);
    return Usuario.fromJson(body['data']);
  }
}
