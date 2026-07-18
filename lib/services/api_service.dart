import 'dart:convert';
import 'package:http/http.dart' as http;
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
    };
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  Future<Map<String, dynamic>> _handleResponse(http.Response response) async {
    final body = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    } else {
      throw Exception(body['detail'] ?? 'Error desconocido');
    }
  }

  Future<TokenResponse> login(String usuario, String contrasena) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.authEndpoint}/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'usuario': usuario,
        'contrasena': contrasena,
      }),
    ).timeout(const Duration(seconds: 15));
    final body = await _handleResponse(response);
    return TokenResponse.fromJson(body);
  }

  Future<void> register({
    required String usuario,
    required String contrasena,
    required String nombre,
    String? celular,
    String? comunidad,
    int? idDepartamento,
    int? idProvincia,
    int? idMunicipio,
  }) async {
    await http.post(
      Uri.parse('${ApiConfig.authEndpoint}/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'usuario': usuario,
        'contrasena': contrasena,
        'nombre': nombre,
        'celular': celular,
        'comunidad': comunidad,
        'id_departamento': idDepartamento,
        'id_provincia': idProvincia,
        'id_municipio': idMunicipio,
      }),
    ).timeout(const Duration(seconds: 15));
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

  Future<void> deleteReporte(int id) async {
    await http.delete(
      Uri.parse('${ApiConfig.reaEndpoint}/reportes/$id'),
      headers: _headers,
    ).timeout(const Duration(seconds: 10));
  }

  Future<List<TipoEvento>> getTiposEvento() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.reaEndpoint}/categorias'),
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
}
