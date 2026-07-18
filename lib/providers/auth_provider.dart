import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService.instance;

  bool _isLoading = false;
  String? _error;

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _authService.isAuthenticated;
  String? get userName => _authService.currentToken?.nombre;
  int? get userId => _authService.userId;

  Future<void> initialize() async {
    await _authService.initialize();
    notifyListeners();
  }

  Future<bool> login(String usuario, String contrasena) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final success = await _authService.login(usuario, contrasena);

    _isLoading = false;
    if (!success) {
      _error = 'Usuario o contraseña incorrectos';
    }
    notifyListeners();
    return success;
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
    _isLoading = true;
    _error = null;
    notifyListeners();

    final success = await _authService.register(
      usuario: usuario,
      contrasena: contrasena,
      nombre: nombre,
      celular: celular,
      comunidad: comunidad,
      idDepartamento: idDepartamento,
      idProvincia: idProvincia,
      idMunicipio: idMunicipio,
    );

    _isLoading = false;
    if (!success) {
      _error = 'Error al registrar usuario';
    }
    notifyListeners();
    return success;
  }

  Future<void> logout() async {
    await _authService.logout();
    notifyListeners();
  }
}
