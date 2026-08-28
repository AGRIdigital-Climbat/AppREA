import 'dart:async';
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
import '../services/debug_log.dart';

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

  Future<http.Response> _requestWithRetry(
    Future<http.Response> Function() request, {
    int maxRetries = 2,
  }) async {
    http.Response? lastResponse;
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        lastResponse = await request();
        if (lastResponse.statusCode != 502 &&
            lastResponse.statusCode != 503 &&
            lastResponse.statusCode != 504) {
          return lastResponse;
        }
      } on SocketException {
        if (attempt == maxRetries) rethrow;
      } on http.ClientException {
        if (attempt == maxRetries) rethrow;
      } on HttpException {
        if (attempt == maxRetries) rethrow;
      } on TimeoutException {
        if (attempt == maxRetries) rethrow;
      }
      await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
    }
    return lastResponse!;
  }

  static String traducirError(Object e) {
    if (e is SocketException) return 'Sin conexión a internet. Verifica tu red.';
    if (e is TimeoutException) return 'Tiempo de espera agotado. Intenta de nuevo.';
    if (e is http.ClientException) return 'Error de conexión con el servidor.';
    if (e is FormatException) return 'Respuesta inválida del servidor.';
    return e.toString().replaceFirst('Exception: ', '');
  }

  Future<Map<String, dynamic>> _handleResponse(http.Response response) async {
    if (response.body.isEmpty) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return <String, dynamic>{};
      }
      throw Exception('Error ${response.statusCode}');
    }
    final body = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    } else {
      throw Exception(
        body['detail'] ?? body['message'] ?? body['error'] ?? 'Error ${response.statusCode}',
      );
    }
  }

  /// Extrae una lista de Maps desde body['data'].
  /// Maneja tanto `{"data": [...]}` como `{"data": {"items": [...]}}`.
  List<Map<String, dynamic>> _extractDataList(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is List) {
      return data.map((json) => Map<String, dynamic>.from(json)).toList();
    }
    if (data is Map) {
      final items = data['items'] ??
          data['localidades'] ??
          data['results'] ??
          data['data'];
      if (items is List) {
        return items.map((json) => Map<String, dynamic>.from(json)).toList();
      }
    }
    return [];
  }

  Future<TokenResponse> login(String usuario, String contrasena) async {
    final response = await _requestWithRetry(() =>
      http.post(
        Uri.parse('${ApiConfig.authEndpoint}/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'usuario': usuario,
          'contrasena': contrasena,
        }),
      ).timeout(const Duration(seconds: 15))
    );
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
    String? correo,
    String? cargo,
    int? idDepartamento,
    int? idProvincia,
    int? idMunicipio,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.authEndpoint}/register'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'usuario': usuario,
        'contrasena': contrasena,
        'nombre': nombre,
        if (celular != null && celular.isNotEmpty) 'celular': celular,
        if (carnet != null && carnet.isNotEmpty) 'carnet': carnet,
        if (comunidad != null && comunidad.isNotEmpty) 'comunidad': comunidad,
        if (correo != null && correo.isNotEmpty) 'correo': correo,
        if (cargo != null && cargo.isNotEmpty) 'cargo': cargo,
        if (idDepartamento != null) 'id_departamento': idDepartamento,
        if (idProvincia != null) 'id_provincia': idProvincia,
        if (idMunicipio != null) 'id_municipio': idMunicipio,
        'id_rol': 7,
      }),
    ).timeout(const Duration(seconds: 15));
    final body = await _handleResponse(response);
    return body;
  }

  Future<int> verificarIdentidad({
    required String carnet,
    required String celular,
    required int idDepartamento,
    required int idProvincia,
    required int idMunicipio,
    required String comunidad,
  }) async {
    final response = await _requestWithRetry(() =>
      http.post(
        Uri.parse('${ApiConfig.authEndpoint}/verificar-identidad'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'carnet': carnet.trim(),
          'celular': celular.trim(),
          'id_departamento': idDepartamento,
          'id_provincia': idProvincia,
          'id_municipio': idMunicipio,
          'comunidad': comunidad.trim().toLowerCase(),
        }),
      ).timeout(const Duration(seconds: 15))
    );
    final body = await _handleResponse(response);
    final data = body['data'] as Map<String, dynamic>;
    return data['id_usuario'] as int;
  }

  Future<void> cambiarContrasena({
    required int idUsuario,
    required String nuevaContrasena,
  }) async {
    final response = await _requestWithRetry(() =>
      http.post(
        Uri.parse('${ApiConfig.authEndpoint}/cambiar-contrasena'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'id_usuario': idUsuario,
          'nueva_contrasena': nuevaContrasena,
        }),
      ).timeout(const Duration(seconds: 15))
    );
    await _handleResponse(response);
  }

  Future<List<Departamento>> getDepartamentos() async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.sharedEndpoint}/departamentos'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body)
        .map((json) => Departamento.fromJson(json))
        .toList();
  }

  Future<List<Provincia>> getProvincias({int? idDepartamento}) async {
    final uri = idDepartamento != null
        ? Uri.parse(
            '${ApiConfig.sharedEndpoint}/provincias?id_departamento=$idDepartamento')
        : Uri.parse('${ApiConfig.sharedEndpoint}/provincias');
    final response = await _requestWithRetry(() =>
      http.get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body)
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
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.sharedEndpoint}/municipios$queryString'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body)
        .map((json) => Municipio.fromJson(json))
        .toList();
  }

  Future<Map<String, dynamic>> getMunicipioGeojson(String codigoIne) async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.sharedEndpoint}/municipios/$codigoIne/geojson'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15))
    );
    return _handleResponse(response);
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
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.reaEndpoint}/reportes?${params.join('&')}'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body)
        .map((json) => Reporte.fromJson(json))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getMisResumenReportes({
    required int idUsuario,
    int skip = 0,
    int limit = 50,
  }) async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.reaEndpoint}/reportes/mis-resumen?id_usuario=$idUsuario&skip=$skip&limit=$limit'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body);
  }

  Future<List<Map<String, dynamic>>> getMisReportes({
    required int idUsuario,
    int skip = 0,
    int limit = 50,
  }) async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.reaEndpoint}/reportes/mis-reportes?id_usuario=$idUsuario&skip=$skip&limit=$limit'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body);
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
    final response = await _requestWithRetry(() =>
      http.post(
        Uri.parse('${ApiConfig.reaEndpoint}/reportes'),
        headers: _headers,
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 15))
    );
    final body = await _handleResponse(response);
    return Reporte.fromJson(body['data']);
  }

  Future<Reporte> createReporteConFoto({
    required String filePath,
    required Map<String, dynamic> data,
  }) async {
    Future<http.Response> doUpload() async {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.reaEndpoint}/reportes/con-foto'),
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

      data.forEach((key, value) {
        if (value != null) {
          request.fields[key] = value.toString();
        }
      });

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      return http.Response.fromStream(streamedResponse);
    }

    final response = await _requestWithRetry(doUpload);
    final body = await _handleResponse(response);
    return Reporte.fromJson(body['data']);
  }

  Future<Reporte> updateReporte(int id, Map<String, dynamic> data) async {
    final response = await _requestWithRetry(() =>
      http.put(
        Uri.parse('${ApiConfig.reaEndpoint}/reportes/$id'),
        headers: _headers,
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 15))
    );
    final body = await _handleResponse(response);
    return Reporte.fromJson(body['data']);
  }

  Future<void> cambiarEstadoReporte(int id, int idEstado) async {
    final response = await _requestWithRetry(() =>
      http.put(
        Uri.parse('${ApiConfig.reaEndpoint}/reportes/$id/estado'),
        headers: _headers,
        body: jsonEncode({'id_estado': idEstado}),
      ).timeout(const Duration(seconds: 15))
    );
    await _handleResponse(response);
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

    Future<http.Response> doUpload() async {
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
      return http.Response.fromStream(streamedResponse);
    }

    final response = await _requestWithRetry(doUpload);
    return _handleResponse(response);
  }

  Future<void> deleteReporte(int id) async {
    final response = await _requestWithRetry(() =>
      http.delete(
        Uri.parse('${ApiConfig.reaEndpoint}/reportes/$id'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10))
    );
    await _handleResponse(response);
  }

  Future<List<TipoEvento>> getTiposEvento() async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.edanEndpoint}/tipo-evento'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body)
        .map((json) => TipoEvento.fromJson(json))
        .toList();
  }

  Future<List<Cultivo>> getCultivos() async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.sharedEndpoint}/cultivos'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body)
        .map((json) => Cultivo.fromJson(json))
        .toList();
  }

  Future<List<PecuarioGrupo>> getPecuarioGrupos() async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.sharedEndpoint}/pecuario'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body)
        .map((json) => PecuarioGrupo.fromJson(json))
        .toList();
  }

  Future<List<GrupoVulnerableCatalogo>> getGruposVulnerables() async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.edanEndpoint}/grupo-vulnerable'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body)
        .map((json) => GrupoVulnerableCatalogo.fromJson(json))
        .toList();
  }

  Future<List<Estado>> getEstados() async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.reaEndpoint}/estados'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body)
        .map((json) => Estado.fromJson(json))
        .toList();
  }

  Future<List<Categoria>> getCategorias() async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.reaEndpoint}/categorias'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body)
        .map((json) => Categoria.fromJson(json))
        .toList();
  }

  Future<List<Usuario>> getUsuarios({bool soloActivos = true, int? idMunicipio, int? idRol}) async {
    final queryParams = <String>[];
    if (idMunicipio != null) queryParams.add('id_municipio=$idMunicipio');
    if (idRol != null) queryParams.add('id_rol=$idRol');
    queryParams.add('skip=0');
    queryParams.add('limit=50');
    
    final uri = Uri.parse('${ApiConfig.usuariosEndpoint}?${queryParams.join('&')}');
    final response = await _requestWithRetry(() =>
      http.get(uri, headers: _headers).timeout(const Duration(seconds: 10))
    );
    final body = await _handleResponse(response);
    final data = body['data'];
    final list = data is List
        ? data
        : data is Map
            ? (data['items'] ?? data['results'] ?? <dynamic>[])
            : <dynamic>[];
    final usuarios = (list as List)
        .map((json) => Usuario.fromJson(json as Map<String, dynamic>))
        .toList();
    if (soloActivos) {
      usuarios.removeWhere((u) => u.activo == false);
    }
    return usuarios;
  }

  Future<Usuario> createUsuario({
    required String usuario,
    required String contrasena,
    required String nombre,
    String? celular,
    String? carnet,
    String? comunidad,
    String? correo,
    String? cargo,
    int? idDepartamento,
    int? idProvincia,
    int? idMunicipio,
    int idRol = 8,
  }) async {
    final response = await _requestWithRetry(() =>
      http.post(
        Uri.parse(ApiConfig.usuariosEndpoint),
        headers: _headers,
        body: jsonEncode({
          'usuario': usuario,
          'contrasena': contrasena,
          'nombre': nombre,
          'celular': celular ?? '',
          'carnet': carnet ?? '',
          'comunidad': comunidad ?? '',
          'correo': correo ?? '',
          'cargo': cargo ?? '',
          'id_departamento': idDepartamento,
          'id_provincia': idProvincia,
          'id_municipio': idMunicipio,
          'id_rol': idRol,
          'activo': true,
        }),
      ).timeout(const Duration(seconds: 15))
    );
    final body = await _handleResponse(response);
    final data = body['data'];
    if (data is Map<String, dynamic>) {
      return Usuario.fromJson(data);
    }
    throw Exception('No se pudo crear el usuario');
  }

  Future<Usuario> getUsuario(int id) async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.usuariosEndpoint}/$id'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10))
    );
    final body = await _handleResponse(response);
    return Usuario.fromJson(body['data']);
  }

  Future<Usuario> updateUsuario(int id, {
    String? nombre,
    String? celular,
    String? comunidad,
    String? correo,
    String? cargo,
    int? idDepartamento,
    int? idProvincia,
    int? idMunicipio,
  }) async {
    final data = <String, dynamic>{};
    if (nombre != null) data['nombre'] = nombre;
    if (celular != null) data['celular'] = celular;
    if (comunidad != null) data['comunidad'] = comunidad;
    if (correo != null && correo.isNotEmpty) data['correo'] = correo;
    if (cargo != null && cargo.isNotEmpty) data['cargo'] = cargo;
    if (idDepartamento != null) data['id_departamento'] = idDepartamento;
    if (idProvincia != null) data['id_provincia'] = idProvincia;
    if (idMunicipio != null) data['id_municipio'] = idMunicipio;

    final response = await _requestWithRetry(() =>
      http.put(
        Uri.parse('${ApiConfig.usuariosEndpoint}/$id'),
        headers: _headers,
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 15))
    );
    final body = await _handleResponse(response);
    return Usuario.fromJson(body['data']);
  }

  // ========== EDAN ENDPOINTS ==========

  Future<List<Map<String, dynamic>>> getEdans({
    int? idUsuario,
    int? idMunicipio,
    int? idEstado,
    bool? sincronizado,
    bool? esBorrador,
    int skip = 0,
    int limit = 50,
  }) async {
    final params = <String>['skip=$skip', 'limit=$limit'];
    if (idUsuario != null) params.add('id_usuario=$idUsuario');
    if (idMunicipio != null) params.add('id_municipio=$idMunicipio');
    if (idEstado != null) params.add('id_estado=$idEstado');
    if (sincronizado != null) params.add('sincronizado=$sincronizado');
    if (esBorrador != null) params.add('es_borrador=$esBorrador');
    
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.edanEndpoint}/?${params.join('&')}'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body);
  }

  /// Lista EDANs del servidor por municipio (sin localidades; usar
  /// getEdanById para el detalle completo).
  Future<List<Map<String, dynamic>>> listarEdansPorMunicipio(
    int idMunicipio, {
    int skip = 0,
    int limit = 500,
  }) async {
    final params = <String>[
      'order_by=id_edan',
      'order=desc',
      'skip=$skip',
      'limit=$limit',
      'id_municipio=$idMunicipio',
    ];
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.edanEndpoint}/?${params.join('&')}'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body);
  }

  Future<Map<String, dynamic>> getEdanById(int id) async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.edanEndpoint}/$id'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15))
    );
    final body = await _handleResponse(response);
    return Map<String, dynamic>.from(body['data']);
  }

  Future<Map<String, dynamic>> createEdan(Map<String, dynamic> edan) async {
    final response = await _requestWithRetry(() =>
      http.post(
        Uri.parse('${ApiConfig.edanEndpoint}/'),
        headers: _headers,
        body: jsonEncode(edan),
      ).timeout(const Duration(seconds: 20))
    );
    final body = await _handleResponse(response);
    return Map<String, dynamic>.from(body['data']);
  }

  Future<Map<String, dynamic>> updateEdan(int id, Map<String, dynamic> edan) async {
    final response = await _requestWithRetry(() =>
      http.put(
        Uri.parse('${ApiConfig.edanEndpoint}/$id'),
        headers: _headers,
        body: jsonEncode(edan),
      ).timeout(const Duration(seconds: 20))
    );
    final body = await _handleResponse(response);
    return Map<String, dynamic>.from(body['data']);
  }

  Future<void> deleteEdan(int id, {bool permanente = false}) async {
    final response = await _requestWithRetry(() =>
      http.delete(
        Uri.parse('${ApiConfig.edanEndpoint}/$id?permanente=$permanente'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15))
    );
    await _handleResponse(response);
  }

  Future<Map<String, dynamic>> syncEdans(List<Map<String, dynamic>> edans) async {
    final response = await _requestWithRetry(() =>
      http.post(
        Uri.parse('${ApiConfig.edanEndpoint}/sync'),
        headers: _headers,
        body: jsonEncode({'edans': edans}),
      ).timeout(const Duration(seconds: 60))
    );
    final body = await _handleResponse(response);
    return Map<String, dynamic>.from(body);
  }

  Future<List<Map<String, dynamic>>> pullEdans({
    int? idUsuario,
    DateTime? fechaDesde,
    int skip = 0,
    int limit = 100,
  }) async {
    final params = <String>[];
    if (idUsuario != null) params.add('id_usuario=$idUsuario');
    if (fechaDesde != null) params.add('fecha_desde=${fechaDesde.toIso8601String()}');
    params.add('skip=$skip');
    params.add('limit=$limit');
    
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.edanEndpoint}/sync/pull?${params.join('&')}'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body);
  }

  Future<List<Map<String, dynamic>>> getMisReportesEdan({
    required int idUsuario,
    int skip = 0,
    int limit = 50,
  }) async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.edanEndpoint}/reportes/mis-reportes?id_usuario=$idUsuario&skip=$skip&limit=$limit'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body);
  }

  Future<List<Map<String, dynamic>>> getTipoEvento() async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.edanEndpoint}/tipo-evento'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body);
  }

  Future<List<Map<String, dynamic>>> getEstadosEdan() async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.edanEndpoint}/estados'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body);
  }

  // ========== EDAN LOCALIDADES ENDPOINTS ==========

  Future<Map<String, dynamic>> getLocalidadesMisResumen({
    required int idUsuario,
  }) async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.edanLocalidadesEndpoint}/mis-resumen?id_usuario=$idUsuario'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15))
    );
    final body = await _handleResponse(response);
    return Map<String, dynamic>.from(body['data']);
  }

  Future<List<Map<String, dynamic>>> getLocalidadesMisReportes({
    required int idUsuario,
    bool? soloHuerfanas,
    int skip = 0,
    int limit = 50,
  }) async {
    final params = <String>['id_usuario=$idUsuario', 'skip=$skip', 'limit=$limit'];
    if (soloHuerfanas != null) params.add('solo_huerfanas=$soloHuerfanas');
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.edanLocalidadesEndpoint}/mis-reportes?${params.join('&')}'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body);
  }

  Future<List<Map<String, dynamic>>> getLocalidadesSyncPull({
    required int idUsuario,
    DateTime? fechaDesde,
    int skip = 0,
    int limit = 50,
  }) async {
    final params = <String>['id_usuario=$idUsuario', 'skip=$skip', 'limit=$limit'];
    if (fechaDesde != null) params.add('fecha_desde=${fechaDesde.toIso8601String()}');
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.edanLocalidadesEndpoint}/sync/pull?${params.join('&')}'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body);
  }

  Future<Map<String, dynamic>> syncLocalidades(List<Map<String, dynamic>> localidades) async {
    try {
      final response = await _requestWithRetry(() =>
        http.post(
          Uri.parse('${ApiConfig.edanLocalidadesEndpoint}/sync'),
          headers: _headers,
          body: jsonEncode({'localidades': localidades}),
        ).timeout(const Duration(seconds: 120))
      );
      final body = await _handleResponse(response);
      DebugLog.instance.i('syncLocalidades status=${response.statusCode} '
          'localidades=${localidades.length} keyCount=${localidades.isEmpty ? 0 : localidades.first.keys.length}');
      return Map<String, dynamic>.from(body);
    } catch (e, st) {
      DebugLog.instance.e('syncLocalidades ERROR', e, st);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> enviarLocalidadDirecta(Map<String, dynamic> localidadJson) async {
    final respuesta = await syncLocalidades([localidadJson]);
    final datos = respuesta['data'];
    final items = datos is List ? datos : <dynamic>[];
    if (items.isNotEmpty && items.first is Map) {
      return Map<String, dynamic>.from(items.first);
    }
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> editarLocalidadDirecta(int idServer, Map<String, dynamic> json) async {
    final response = await _requestWithRetry(() =>
      http.put(
        Uri.parse('${ApiConfig.edanLocalidadesEndpoint}/$idServer'),
        headers: _headers,
        body: jsonEncode(json),
      ).timeout(const Duration(seconds: 30))
    );
    final body = await _handleResponse(response);
    final data = body['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return Map<String, dynamic>.from(body);
  }

  Future<List<Map<String, dynamic>>> pullEstados({int? idUsuario, String? fechaDesde}) async {
    final params = <String, String>{};
    if (idUsuario != null) params['id_usuario'] = idUsuario.toString();
    if (fechaDesde != null) params['fecha_desde'] = fechaDesde;
    params['limit'] = '1000';
    final uri = Uri.parse('${ApiConfig.edanLocalidadesEndpoint}/sync/pull')
        .replace(queryParameters: params);
    final response = await _requestWithRetry(() =>
      http.get(uri, headers: _headers).timeout(const Duration(seconds: 30))
    );
    final body = await _handleResponse(response);
    final data = body['data'];
    if (data is List) return data.cast<Map<String, dynamic>>();
    return [];
  }

  Future<Map<String, dynamic>> cambiarEstadoLocalidad(int idLocalidad, int idEstado) async {
    final response = await _requestWithRetry(() =>
      http.put(
        Uri.parse('${ApiConfig.edanLocalidadesEndpoint}/$idLocalidad/estado'),
        headers: _headers,
        body: jsonEncode({'id_edan_localidad_estado': idEstado}),
      ).timeout(const Duration(seconds: 15))
    );
    final body = await _handleResponse(response);
    return Map<String, dynamic>.from(body['data']);
  }

  /// Endpoints dedicados de protección (grupos vulnerables).

  Future<List<Map<String, dynamic>>> listarProteccion(int idLocalidad) async {
    try {
      final response = await _requestWithRetry(() =>
        http.get(
          Uri.parse('${ApiConfig.edanLocalidadesEndpoint}/$idLocalidad/proteccion'),
          headers: _headers,
        ).timeout(const Duration(seconds: 15))
      );
      final body = await _handleResponse(response);
      final data = body['data'];
      final lista = data is List ? data.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
      DebugLog.instance.i('listarProteccion idServer=$idLocalidad -> ${lista.length} grupos');
      return lista;
    } catch (e, st) {
      DebugLog.instance.e('listarProteccion ERROR idServer=$idLocalidad', e, st);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> crearProteccion(int idLocalidad, Map<String, dynamic> json) async {
    try {
      final response = await _requestWithRetry(() =>
        http.post(
          Uri.parse('${ApiConfig.edanLocalidadesEndpoint}/$idLocalidad/proteccion'),
          headers: _headers,
          body: jsonEncode(json),
        ).timeout(const Duration(seconds: 15))
      );
      final body = await _handleResponse(response);
      DebugLog.instance.i('crearProteccion OK idServer=$idLocalidad '
          'cat=${json['id_grupo_vulnerable_catalogo']} status=${response.statusCode}');
      final data = body['data'];
      if (data is Map) return Map<String, dynamic>.from(data);
      return Map<String, dynamic>.from(body);
    } catch (e, st) {
      DebugLog.instance.e('crearProteccion ERROR idServer=$idLocalidad '
          'cat=${json['id_grupo_vulnerable_catalogo']} '
          'id_seccion=${json['id_seccion']} '
          'payload=${jsonEncode(json)}', e, st);
      rethrow;
    }
  }

  Future<void> eliminarProteccion(int idLocalidad, int idGrupo) async {
    await _requestWithRetry(() =>
      http.delete(
        Uri.parse('${ApiConfig.edanLocalidadesEndpoint}/$idLocalidad/proteccion/$idGrupo'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15))
    );
  }

  Future<List<Map<String, dynamic>>> getConsolidarPendientes({
    required int idMunicipio,
    String estado = 'aprobado',
  }) async {
    final encodedEstado = Uri.encodeComponent(estado);
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.edanEndpoint}/consolidar/pendientes?id_municipio=$idMunicipio&estado=$encodedEstado'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body);
  }

  Future<Map<String, dynamic>> consolidar({
    required int idMunicipio,
    required int idTipoEvento,
    required List<int> localidadIds,
  }) async {
    final response = await _requestWithRetry(() =>
      http.post(
        Uri.parse('${ApiConfig.edanEndpoint}/consolidar'),
        headers: _headers,
        body: jsonEncode({
          'id_municipio': idMunicipio,
          'id_tipo_evento': idTipoEvento,
          'localidad_ids': localidadIds,
        }),
      ).timeout(const Duration(seconds: 30))
    );
    final body = await _handleResponse(response);
    return Map<String, dynamic>.from(body['data']);
  }

  Future<Map<String, dynamic>> consolidarAuto({
    required int idMunicipio,
    required int idTipoEvento,
  }) async {
    final response = await _requestWithRetry(() =>
      http.post(
        Uri.parse('${ApiConfig.edanEndpoint}/consolidar/auto'),
        headers: _headers,
        body: jsonEncode({
          'id_municipio': idMunicipio,
          'id_tipo_evento': idTipoEvento,
        }),
      ).timeout(const Duration(seconds: 30))
    );
    final body = await _handleResponse(response);
    return Map<String, dynamic>.from(body['data']);
  }

  Future<Map<String, dynamic>> desconsolidar(int idLocalidad) async {
    final response = await _requestWithRetry(() =>
      http.put(
        Uri.parse('${ApiConfig.edanLocalidadesEndpoint}/$idLocalidad/desconsolidar'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15))
    );
    final body = await _handleResponse(response);
    return Map<String, dynamic>.from(body['data']);
  }

  Future<Map<String, dynamic>> deshacerEdan(int idEdan) async {
    final response = await _requestWithRetry(() =>
      http.put(
        Uri.parse('${ApiConfig.edanEndpoint}/$idEdan/deshacer'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15))
    );
    final body = await _handleResponse(response);
    return Map<String, dynamic>.from(body['data']);
  }

  Future<Map<String, dynamic>> cambiarEstadoEdan(
    int idEdan,
    int idEstado, {
    String? observaciones,
  }) async {
    final bodyMap = <String, dynamic>{
      'id_estado': idEstado,
    };
    if (observaciones != null) bodyMap['observaciones'] = observaciones;
    final response = await _requestWithRetry(() =>
      http.put(
        Uri.parse('${ApiConfig.edanEndpoint}/$idEdan/estado'),
        headers: _headers,
        body: jsonEncode(bodyMap),
      ).timeout(const Duration(seconds: 15))
    );
    final body = await _handleResponse(response);
    return Map<String, dynamic>.from(body['data']);
  }

  Future<Map<String, dynamic>> consolidarEdanConLocalidades(dynamic edan) async {
    final response = await _requestWithRetry(() =>
      http.post(
        Uri.parse(ApiConfig.edanEndpoint),
        headers: _headers,
        body: jsonEncode(edan.toJson()),
      ).timeout(const Duration(seconds: 60))
    );
    final body = await _handleResponse(response);
    return Map<String, dynamic>.from(body['data']);
  }

  Future<Map<String, dynamic>> getLocalidadById(int idLocalidad) async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.edanLocalidadesEndpoint}/$idLocalidad'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15))
    );
    final body = await _handleResponse(response);
    return Map<String, dynamic>.from(body['data']);
  }

  Future<Map<String, dynamic>> deleteLocalidad(int idLocalidad) async {
    final response = await _requestWithRetry(() =>
      http.delete(
        Uri.parse('${ApiConfig.edanLocalidadesEndpoint}/$idLocalidad'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15))
    );
    final body = await _handleResponse(response);
    return Map<String, dynamic>.from(body);
  }

  Future<List<TipoLocalidad>> getTipoLocalidad() async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.edanEndpoint}/tipo-localidad'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body)
        .map((json) => TipoLocalidad.fromJson(Map<String, dynamic>.from(json)))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getLocalidadesMunicipio(int idMunicipio) async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.edanLocalidadesEndpoint}/municipio/$idMunicipio'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body);
  }

  Future<Map<String, dynamic>> getResumenLocalidades(int idMunicipio) async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.edanLocalidadesEndpoint}/municipio/$idMunicipio/resumen'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15))
    );
    final body = await _handleResponse(response);
    return Map<String, dynamic>.from(body['data']);
  }

  Future<List<Map<String, dynamic>>> getLocalidadesEstado() async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.edanEndpoint}/localidades-estado'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body);
  }

  // Secciones 1:N de localidad
  Future<List<Map<String, dynamic>>> getLocalidadSeccion(int idLocalidad, String seccion) async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.edanLocalidadesEndpoint}/$idLocalidad/$seccion'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body);
  }

  Future<Map<String, dynamic>> createLocalidadSeccionConFoto({
    required int idLocalidad,
    required String seccion,
    required String filePath,
    required Map<String, dynamic> data,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiConfig.edanLocalidadesEndpoint}/$idLocalidad/$seccion/con-foto'),
    );
    if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
    request.headers['Accept'] = 'application/json';
    final contentType = _getImageContentType(filePath);
    request.files.add(await http.MultipartFile.fromPath('file', filePath, contentType: MediaType.parse(contentType)));
    data.forEach((key, value) {
      if (value != null) request.fields[key] = value.toString();
    });
    final streamedResponse = await request.send().timeout(const Duration(seconds: 90));
    final response = await http.Response.fromStream(streamedResponse);
    final body = await _handleResponse(response);
    final creado = body['data'];
    if (creado is Map) {
      return Map<String, dynamic>.from(creado);
    }
    return <String, dynamic>{};
  }

  // ========== REPOSITORIO ENDPOINTS ==========

  Future<List<Map<String, dynamic>>> listarTiposRepositorio() async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.repositorioEndpoint}/tipos'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body);
  }

  Future<List<Map<String, dynamic>>> listarDocumentosEdan(int idEdan) async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.repositorioEndpoint}/edan/$idEdan/documentos'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body);
  }

  Future<Map<String, dynamic>> subirDocumentoEdan({
    required int idEdan,
    required String filePath,
    required int idTipoDocumento,
    required String nombreDocumento,
    required String fechaDocumento,
    required int idDepartamento,
    required int idProvincia,
    required int idMunicipio,
    String? observaciones,
  }) async {
    Future<http.Response> doUpload() async {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.repositorioEndpoint}/edan/$idEdan/documentos'),
      );
      if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
      request.headers['Accept'] = 'application/json';
      final contentType = _getPdfContentType(filePath);
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        filePath,
        contentType: MediaType.parse(contentType),
      ));
      request.fields['id_tipo_documento'] = idTipoDocumento.toString();
      request.fields['nombre_documento'] = nombreDocumento;
      request.fields['fecha_documento'] = fechaDocumento;
      request.fields['id_departamento'] = idDepartamento.toString();
      request.fields['id_provincia'] = idProvincia.toString();
      request.fields['id_municipio'] = idMunicipio.toString();
      if (observaciones != null && observaciones.isNotEmpty) {
        request.fields['observaciones'] = observaciones;
      }
      final streamedResponse = await request.send().timeout(const Duration(seconds: 60));
      return http.Response.fromStream(streamedResponse);
    }

    final response = await _requestWithRetry(doUpload);
    final body = await _handleResponse(response);
    return Map<String, dynamic>.from(body['data'] ?? body);
  }

  Future<List<int>> descargarDocRepositorio(int idDocumento) async {
    final response = await http.get(
      Uri.parse('${ApiConfig.repositorioEndpoint}/documentos/$idDocumento/descargar'),
      headers: _headers,
    ).timeout(const Duration(seconds: 60));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    throw Exception('Error al descargar documento: ${response.statusCode}');
  }

  Future<List<Map<String, dynamic>>> filtrarDocumentos({
    int? idDepartamento,
    int? idProvincia,
    int? idMunicipio,
    int? idTipoDocumento,
    String? fechaDesde,
    String? fechaHasta,
    String? nombre,
  }) async {
    final params = <String>[];
    if (idDepartamento != null) params.add('id_departamento=$idDepartamento');
    if (idProvincia != null) params.add('id_provincia=$idProvincia');
    if (idMunicipio != null) params.add('id_municipio=$idMunicipio');
    if (idTipoDocumento != null) params.add('id_tipo_documento=$idTipoDocumento');
    if (fechaDesde != null) params.add('fecha_desde=$fechaDesde');
    if (fechaHasta != null) params.add('fecha_hasta=$fechaHasta');
    if (nombre != null && nombre.isNotEmpty) params.add('nombre_documento_like=$nombre');
    final queryString = params.isNotEmpty ? '?${params.join('&')}' : '';
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.repositorioEndpoint}/documentos/filtrar$queryString'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body);
  }

  Future<List<Map<String, dynamic>>> buscarDocumentos(String query) async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.repositorioEndpoint}/documentos/buscar?q=$query'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15))
    );
    final body = await _handleResponse(response);
    return _extractDataList(body);
  }

  Future<void> eliminarDocRepositorio(int idDocumento) async {
    final response = await _requestWithRetry(() =>
      http.delete(
        Uri.parse('${ApiConfig.repositorioEndpoint}/documentos/$idDocumento'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10))
    );
    await _handleResponse(response);
  }

  Future<void> eliminarDocRepositorioHard(int idDocumento) async {
    final response = await _requestWithRetry(() =>
      http.delete(
        Uri.parse('${ApiConfig.repositorioEndpoint}/documentos/$idDocumento/hard'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10))
    );
    await _handleResponse(response);
  }

  Future<Map<String, dynamic>> getDocRepositorio(int idDocumento) async {
    final response = await _requestWithRetry(() =>
      http.get(
        Uri.parse('${ApiConfig.repositorioEndpoint}/documentos/$idDocumento'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10))
    );
    final body = await _handleResponse(response);
    return Map<String, dynamic>.from(body['data'] ?? body);
  }

  String _getPdfContentType(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
      case 'docx':
        return 'application/msword';
      default:
        return 'application/pdf';
    }
  }
}
