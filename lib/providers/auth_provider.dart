import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/edan_sync_service.dart';
import '../services/edan/edan_sync_respo_service.dart';

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

  bool _hasModulePermission(String moduleKey) {
    final permisos = _authService.permisos;
    if (permisos == null) return false;
    if (permisos is String) return permisos == 'full_access';
    if (permisos is Map) return permisos.containsKey(moduleKey);
    return false;
  }

  bool get canAccessPreEdan => _hasModulePermission('REA');
  bool get canAccessEdan => _hasModulePermission('EDAN');
  bool get canAccessRida => _hasModulePermission('RIDA') || _hasModulePermission('full_access');
  bool get canAccessSinb => _hasModulePermission('SIN-B') || _hasModulePermission('full_access');

  Future<void> initialize() async {
    await _authService.initialize();
    // Si hay sesión activa (auto-login), refrescar localidades del servidor.
    if (_authService.isAuthenticated) {
      _dispararCargaEdansMunicipio();
    }
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
    } else {
      _dispararCargaEdansMunicipio();
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
    String? correo,
    String? cargo,
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
      correo: correo,
      cargo: cargo,
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
    } else {
      _dispararCargaEdansMunicipio();
    }
    notifyListeners();
    return success;
  }

  void _dispararCargaEdansMunicipio() {
    final userId = _authService.userId;
    if (userId == null) return;
    if (_authService.idRol == 6) {
      final idMunicipio = _authService.currentToken?.idMunicipio;
      if (idMunicipio == null) return;
      EdanSyncService.instance.recargarEdansMunicipio(
        idMunicipio: idMunicipio,
        usuarioId: userId,
      );
    } else if (_authService.idRol == 7) {
      EdanSyncRespoService.instance.recargarLocalidades(
        idUsuario: userId,
      );
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    notifyListeners();
  }
}
