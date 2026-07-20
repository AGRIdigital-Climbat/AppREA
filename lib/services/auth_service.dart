import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/usuario.dart';
import '../services/api_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._();
  static AuthService get instance => _instance;
  AuthService._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final ApiService _api = ApiService.instance;
  SharedPreferences? _prefs;

  TokenResponse? _currentToken;
  String? _lastError;

  TokenResponse? get currentToken => _currentToken;
  String? get lastError => _lastError;
  bool get isAuthenticated => _currentToken != null;
  int? get userId => _currentToken?.userId;
  String? get userName {
    final nombre = _prefs?.getString('profile_nombre');
    return nombre;
  }

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    final hasLoggedIn = _prefs!.getBool('has_logged_in') ?? false;

    if (!hasLoggedIn) {
      _currentToken = null;
      return;
    }

    try {
      final token = await _storage
          .read(key: 'auth_token')
          .timeout(const Duration(seconds: 3));
      final userId = await _storage
          .read(key: 'user_id')
          .timeout(const Duration(seconds: 3));
      final usuario = await _storage
          .read(key: 'usuario')
          .timeout(const Duration(seconds: 3));
      final nombre = await _storage
          .read(key: 'nombre')
          .timeout(const Duration(seconds: 3));

      if (token != null && userId != null) {
        _currentToken = TokenResponse(
          accessToken: token,
          tokenType: 'bearer',
          userId: int.parse(userId),
          usuario: usuario ?? '',
          nombre: nombre ?? '',
        );
        _api.setToken(token);
      }
    } catch (e) {
      _currentToken = null;
    }
  }

  Map<String, dynamic> getSavedProfile() {
    final data = <String, dynamic>{};
    if (_prefs == null) return data;
    data['nombre'] = _prefs!.getString('profile_nombre') ?? '';
    data['celular'] = _prefs!.getString('profile_celular') ?? '';
    data['carnet'] = _prefs!.getString('profile_carnet') ?? '';
    data['comunidad'] = _prefs!.getString('profile_comunidad') ?? '';
    data['usuario'] = _prefs!.getString('profile_usuario') ?? '';
    data['id_departamento'] = _prefs!.getInt('profile_id_departamento');
    data['departamento_nombre'] = _prefs!.getString('profile_departamento_nombre');
    data['id_provincia'] = _prefs!.getInt('profile_id_provincia');
    data['provincia_nombre'] = _prefs!.getString('profile_provincia_nombre');
    data['id_municipio'] = _prefs!.getInt('profile_id_municipio');
    data['municipio_nombre'] = _prefs!.getString('profile_municipio_nombre');
    return data;
  }

  Future<void> saveProfileLocally(Map<String, dynamic> profile) async {
    _prefs ??= await SharedPreferences.getInstance();
    if (profile['nombre'] != null) _prefs!.setString('profile_nombre', profile['nombre'] as String);
    if (profile['celular'] != null) _prefs!.setString('profile_celular', profile['celular'] as String);
    if (profile['carnet'] != null) _prefs!.setString('profile_carnet', profile['carnet'] as String);
    if (profile['comunidad'] != null) _prefs!.setString('profile_comunidad', profile['comunidad'] as String);
    if (profile['usuario'] != null) _prefs!.setString('profile_usuario', profile['usuario'] as String);
    if (profile['id_departamento'] != null) _prefs!.setInt('profile_id_departamento', profile['id_departamento'] as int);
    if (profile['departamento_nombre'] != null) _prefs!.setString('profile_departamento_nombre', profile['departamento_nombre'] as String);
    if (profile['id_provincia'] != null) _prefs!.setInt('profile_id_provincia', profile['id_provincia'] as int);
    if (profile['provincia_nombre'] != null) _prefs!.setString('profile_provincia_nombre', profile['provincia_nombre'] as String);
    if (profile['id_municipio'] != null) _prefs!.setInt('profile_id_municipio', profile['id_municipio'] as int);
    if (profile['municipio_nombre'] != null) _prefs!.setString('profile_municipio_nombre', profile['municipio_nombre'] as String);
  }

  Future<bool> login(String usuario, String contrasena) async {
    try {
      final token = await _api.login(usuario, contrasena);
      _currentToken = token;
      _api.setToken(token.accessToken);

      await _storage.write(key: 'auth_token', value: token.accessToken);
      await _storage.write(key: 'user_id', value: token.userId.toString());
      await _storage.write(key: 'usuario', value: token.usuario);
      await _storage.write(key: 'nombre', value: token.nombre);

      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setBool('has_logged_in', true);

      await saveProfileLocally({
        'nombre': token.nombre,
        'celular': token.celular ?? '',
        'carnet': token.carnet ?? token.usuario,
        'comunidad': token.comunidad ?? '',
        'usuario': token.usuario,
        'id_departamento': token.idDepartamento,
        'departamento_nombre': token.departamentoNombre,
        'id_provincia': token.idProvincia,
        'provincia_nombre': token.provinciaNombre,
        'id_municipio': token.idMunicipio,
        'municipio_nombre': token.municipioNombre,
      });

      return true;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  Future<bool> register({
    required String usuario,
    required String contrasena,
    required String nombre,
    String? celular,
    String? carnet,
    String? comunidad,
    int? idDepartamento,
    String? departamentoNombre,
    int? idProvincia,
    String? provinciaNombre,
    int? idMunicipio,
    String? municipioNombre,
  }) async {
    try {
      await _api.register(
        usuario: usuario,
        contrasena: contrasena,
        nombre: nombre,
        celular: celular,
        carnet: carnet,
        comunidad: comunidad,
        idDepartamento: idDepartamento,
        idProvincia: idProvincia,
        idMunicipio: idMunicipio,
      );

      await saveProfileLocally({
        'nombre': nombre,
        'celular': celular ?? '',
        'carnet': carnet ?? usuario,
        'comunidad': comunidad ?? '',
        'usuario': usuario,
        'id_departamento': idDepartamento,
        'departamento_nombre': departamentoNombre,
        'id_provincia': idProvincia,
        'provincia_nombre': provinciaNombre,
        'id_municipio': idMunicipio,
        'municipio_nombre': municipioNombre,
      });

      final loginSuccess = await login(usuario, contrasena);

      return loginSuccess;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  Future<void> logout() async {
    _currentToken = null;
    _api.setToken(null);

    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'user_id');
    await _storage.delete(key: 'usuario');
    await _storage.delete(key: 'nombre');

    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool('has_logged_in', false);
    await _prefs!.remove('profile_nombre');
    await _prefs!.remove('profile_celular');
    await _prefs!.remove('profile_carnet');
    await _prefs!.remove('profile_comunidad');
    await _prefs!.remove('profile_usuario');
    await _prefs!.remove('profile_id_departamento');
    await _prefs!.remove('profile_departamento_nombre');
    await _prefs!.remove('profile_id_provincia');
    await _prefs!.remove('profile_provincia_nombre');
    await _prefs!.remove('profile_id_municipio');
    await _prefs!.remove('profile_municipio_nombre');
  }
}
