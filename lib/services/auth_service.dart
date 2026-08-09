import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/usuario.dart';
import '../services/api_service.dart';
import '../services/database_helper.dart';
import '../services/image_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._();
  static AuthService get instance => _instance;
  AuthService._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final ApiService _api = ApiService.instance;
  SharedPreferences? _prefs;

  TokenResponse? _currentToken;
  String? _lastError;
  int? _idRol;
  String? _rolName;
  dynamic _permisos;

  TokenResponse? get currentToken => _currentToken;
  String? get lastError => _lastError;
  bool get isAuthenticated => _currentToken != null;
  int? get userId => _currentToken?.userId;
  int? get idRol => _idRol;
  String? get rolName => _rolName;
  dynamic get permisos => _permisos;
  String? get userName {
    final nombre = _prefs?.getString('profile_nombre');
    return nombre;
  }
  String? get correo => _prefs?.getString('profile_correo');
  String? get cargo => _prefs?.getString('profile_cargo');

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    await _autoLogin();
  }

  Future<void> _autoLogin() async {
    final hasLoggedIn = _prefs!.getBool('has_logged_in') ?? false;
    if (!hasLoggedIn) {
      _currentToken = null;
      return;
    }

    try {
      final token = await _storage.read(key: 'auth_token');
      final userId = await _storage.read(key: 'user_id');
      final usuario = await _storage.read(key: 'usuario');
      final contrasena = await _storage.read(key: 'contrasena');
      final idRolStr = await _storage.read(key: 'id_rol');
      final lastLoginStr = await _storage.read(key: 'last_login');

      if (token != null && token.isNotEmpty) {
        final idRol = idRolStr != null ? int.tryParse(idRolStr) : null;
        DateTime? lastLogin;
        if (lastLoginStr != null) {
          lastLogin = DateTime.tryParse(lastLoginStr);
        }

        final tokenVigente = await _verificarToken(token, idRol, lastLogin);
        if (tokenVigente) {
          await _loadUserProfile();
          return;
        }
      }

      if (usuario != null && usuario.isNotEmpty && 
          contrasena != null && contrasena.isNotEmpty) {
        final loginExitoso = await login(usuario, contrasena);
        if (loginExitoso) {
          debugPrint('Auto-login exitoso con credenciales guardadas');
          return;
        }
      }

      _currentToken = null;
      await logout();
    } catch (e) {
      debugPrint('Error en auto-login: $e');
      _currentToken = null;
    }
  }

  Future<bool> _verificarToken(String token, int? idRol, DateTime? lastLogin) async {
    if (token.isEmpty) return false;

    if (lastLogin == null) return false;

    final ahora = DateTime.now();
    final diasDesdeLogin = ahora.difference(lastLogin).inDays;

    if (idRol == 7) {
      return true;
    }

    if (diasDesdeLogin > 3) {
      debugPrint('Token expirado: $diasDesdeLogin días desde último login');
      return false;
    }

    return true;
  }

  Future<void> _loadUserProfile() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) return;

      final userId = await _storage.read(key: 'user_id');
      final usuario = await _storage.read(key: 'usuario');
      final nombre = await _storage.read(key: 'nombre');
      final idRolStr = await _storage.read(key: 'id_rol');
      final rolName = await _storage.read(key: 'rol_name');
      final permisosStr = await _storage.read(key: 'permisos');

      if (token != null && userId != null) {
        _idRol = idRolStr != null ? int.tryParse(idRolStr) : null;
        _rolName = rolName;
        if (permisosStr != null) {
          final decoded = _decodePermisos(permisosStr);
          _permisos = decoded;
        }
        final idMunicipio = _prefs!.getInt('profile_id_municipio');
        final municipioNombre = _prefs!.getString('profile_municipio_nombre');
        final idDepartamento = _prefs!.getInt('profile_id_departamento');
        final departamentoNombre = _prefs!.getString('profile_departamento_nombre');
        final idProvincia = _prefs!.getInt('profile_id_provincia');
        final provinciaNombre = _prefs!.getString('profile_provincia_nombre');
        final celular = _prefs!.getString('profile_celular');
        final carnet = _prefs!.getString('profile_carnet');
        final comunidad = _prefs!.getString('profile_comunidad');
        final correo = _prefs!.getString('profile_correo');
        final cargo = _prefs!.getString('profile_cargo');

        _currentToken = TokenResponse(
          accessToken: token,
          tokenType: 'bearer',
          userId: int.parse(userId),
          usuario: usuario ?? '',
          nombre: nombre ?? '',
          idMunicipio: idMunicipio,
          municipioNombre: municipioNombre,
          idDepartamento: idDepartamento,
          departamentoNombre: departamentoNombre,
          idProvincia: idProvincia,
          provinciaNombre: provinciaNombre,
          celular: celular,
          carnet: carnet,
          comunidad: comunidad,
          correo: correo,
          cargo: cargo,
          idRol: _idRol,
          rol: _rolName,
          permisos: _permisos,
        );

        ApiService.instance.setToken(token);
      }
    } catch (e) {
      debugPrint('Error cargando perfil: $e');
    }
  }
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
    data['correo'] = _prefs!.getString('profile_correo') ?? '';
    data['cargo'] = _prefs!.getString('profile_cargo') ?? '';
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
    if (profile['correo'] != null) _prefs!.setString('profile_correo', profile['correo'] as String);
    if (profile['cargo'] != null) _prefs!.setString('profile_cargo', profile['cargo'] as String);
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
      await _storage.write(key: 'contrasena', value: contrasena);
      await _storage.write(key: 'id_rol', value: token.idRol?.toString() ?? '');
      await _storage.write(key: 'rol_name', value: token.rol ?? '');
      await _storage.write(key: 'last_login', value: DateTime.now().toIso8601String());

      _idRol = token.idRol;
      _rolName = token.rol;
      _permisos = token.permisos;

      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setBool('has_logged_in', true);

      final permisosJson = jsonEncode(token.permisos);
      await _storage.write(key: 'permisos', value: permisosJson);

      await saveProfileLocally({
        'nombre': token.nombre,
        'celular': token.celular ?? '',
        'carnet': token.carnet ?? token.usuario,
        'comunidad': token.comunidad ?? '',
        'correo': token.correo ?? '',
        'cargo': token.cargo ?? '',
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
    String? correo,
    String? cargo,
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
        correo: correo,
        cargo: cargo,
        idDepartamento: idDepartamento,
        idProvincia: idProvincia,
        idMunicipio: idMunicipio,
      );

      await saveProfileLocally({
        'nombre': nombre,
        'celular': celular ?? '',
        'carnet': carnet ?? usuario,
        'comunidad': comunidad ?? '',
        'correo': correo ?? '',
        'cargo': cargo ?? '',
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
    _idRol = null;
    _rolName = null;
    _permisos = null;
    _api.setToken(null);
    
    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'user_id');
    await _storage.delete(key: 'usuario');
    await _storage.delete(key: 'nombre');
    await _storage.delete(key: 'contrasena');
    await _storage.delete(key: 'id_rol');
    await _storage.delete(key: 'rol_name');
    await _storage.delete(key: 'permisos');
    await _storage.delete(key: 'last_login');
    
    _prefs?.remove('has_logged_in');
    _prefs?.remove('profile_nombre');
    _prefs?.remove('profile_celular');
    _prefs?.remove('profile_carnet');
    _prefs?.remove('profile_comunidad');
    _prefs?.remove('profile_usuario');
    _prefs?.remove('profile_id_departamento');
    _prefs?.remove('profile_departamento_nombre');
    _prefs?.remove('profile_id_provincia');
    _prefs?.remove('profile_provincia_nombre');
    _prefs?.remove('profile_id_municipio');
    _prefs?.remove('profile_municipio_nombre');
    _prefs?.remove('profile_correo');
    _prefs?.remove('profile_cargo');
  }

  Future<Map<String, dynamic>> cargarCatalogos() async {
    try {
      final catalogos = <String, dynamic>{};
      
      final departamentos = await _api.getDepartamentos();
      catalogos['departamentos'] = departamentos;
      
      final provincias = await _api.getProvincias();
      catalogos['provincias'] = provincias;
      
      final municipios = await _api.getMunicipios();
      catalogos['municipios'] = municipios;
      
      final tiposEvento = await _api.getTiposEvento();
      catalogos['tiposEvento'] = tiposEvento;
      
      final estadosEdan = await _api.getEstadosEdan();
      catalogos['estadosEdan'] = estadosEdan;
      
      return catalogos;
    } catch (e) {
      debugPrint('Error cargando catálogos: $e');
      return <String, dynamic>{};
    }
  }
}

  dynamic _decodePermisos(String encoded) {
    try {
      return jsonDecode(encoded);
    } catch (_) {
      return null;
    }
  }
}
