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
  Usuario? _currentUsuario;

  TokenResponse? get currentToken => _currentToken;
  Usuario? get currentUsuario => _currentUsuario;
  bool get isAuthenticated => _currentToken != null;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    final hasLoggedIn = _prefs!.getBool('has_logged_in') ?? false;

    if (!hasLoggedIn) {
      _currentToken = null;
      return;
    }

    try {
      final token = await _storage.read(key: 'auth_token')
          .timeout(const Duration(seconds: 3));
      final userId = await _storage.read(key: 'user_id')
          .timeout(const Duration(seconds: 3));
      final usuario = await _storage.read(key: 'usuario')
          .timeout(const Duration(seconds: 3));
      final nombre = await _storage.read(key: 'nombre')
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

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> register({
    required String usuario,
    required String contrasena,
    required String nombre,
    String? celular,
    String? comunidad,
    int? idDepartamento,
    int? idProvincia,
    int? idMunicipio,
  }) async {
    try {
      await _api.register(
        usuario: usuario,
        contrasena: contrasena,
        nombre: nombre,
        celular: celular,
        comunidad: comunidad,
        idDepartamento: idDepartamento,
        idProvincia: idProvincia,
        idMunicipio: idMunicipio,
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> logout() async {
    _currentToken = null;
    _currentUsuario = null;
    _api.setToken(null);

    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'user_id');
    await _storage.delete(key: 'usuario');
    await _storage.delete(key: 'nombre');

    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool('has_logged_in', false);
  }

  int? get userId => _currentToken?.userId;
}
