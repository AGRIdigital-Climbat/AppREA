import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService.instance;

  bool _isLoading = false;
  String? _error;

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _authService.isAuthenticated;
  String? get userName => _authService.userName;
  int? get userId => _authService.userId;
  int? get idRol => _authService.idRol;
  String? get rolName => _authService.rolName;
  bool get isUGR => _authService.idRol != null && _authService.idRol != 7;
  bool get canAccessEDAN => isUGR;

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
    String? carnet,
    String? comunidad,
    int? idDepartamento,
    String? departamentoNombre,
    int? idProvincia,
    String? provinciaNombre,
    int? idMunicipio,
    String? municipioNombre,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final success = await _authService.register(
      usuario: usuario,
      contrasena: contrasena,
      nombre: nombre,
      celular: celular,
      carnet: carnet,
      comunidad: comunidad,
      idDepartamento: idDepartamento,
      departamentoNombre: departamentoNombre,
      idProvincia: idProvincia,
      provinciaNombre: provinciaNombre,
      idMunicipio: idMunicipio,
      municipioNombre: municipioNombre,
    );

    _isLoading = false;
    if (!success) {
      _error = _authService.lastError ?? 'Error al registrar usuario';
    }
    notifyListeners();
    return success;
  }

  Future<void> logout() async {
    await _authService.logout();
    notifyListeners();
  }
}
