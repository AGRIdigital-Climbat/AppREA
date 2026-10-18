import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_roles.dart';
import '../services/auth_service.dart';
import '../services/api/edan_api_v2.dart';
import '../services/edan_sync_service.dart';
import '../services/edan/edan_store_v2.dart';
import '../services/sync/edan_sync_engine_v2.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService.instance;

  /// Prefijo de la marca (por usuario + dispositivo) de "primera
  /// sincronización" ya realizada.
  static const String _kFirstSyncPrefix = 'first_sync_done_';

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
      unawaited(_dispararCargaEdansMunicipio());
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
      _error = _errorDeLogin();
    } else {
      unawaited(_dispararCargaEdansMunicipio());
    }
    notifyListeners();
    return success;
  }

  /// Traduce el fallo del servicio a un mensaje para el usuario.
  /// Distingue "credenciales incorrectas" de "rol sin acceso a la app".
  String _errorDeLogin() {
    if (_authService.ultimoErrorRolNoPermitido) {
      return AppRoles.mensajeSinAcceso;
    }
    return 'Usuario o contraseña incorrectos';
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
      _error = _authService.ultimoErrorRolNoPermitido
          ? AppRoles.mensajeSinAcceso
          : (_authService.lastError ?? 'Error al registrar usuario');
    } else {
      // Un usuario nuevo ARRANCA LIMPIO: no descargamos "mis reportes".
      // Además marcamos la sincronización inicial como hecha para que tampoco
      // se dispare en su primer inicio de sesión posterior en este equipo.
      final userId = _authService.userId;
      if (userId != null) {
        unawaited(_marcarSyncInicialHecha(userId));
      }
    }
    notifyListeners();
    return success;
  }

  /// Dispara la carga de datos EDAN tras autenticarse.
  ///
  /// - Rol 7 (RESP, diseño limpio solo-V2): **SIEMPRE** baja con el motor V2
  ///   (`GET /formularios/estados` + `GET /sync/pull` + bytes de fotos a
  ///   `report_photos/`) — en CADA login, como hacía v1.2.0 con
  ///   `recargarLocalidades()`. El pull es incremental (watermark), así que
  ///   una reaparición es barata (~200 ms y solo filas cambiadas). La marca
  ///   `first_sync_done_<userId>` ya NO decide si se baja (ese fue el modo de
  ///   fallo: si una build vieja la marcó con datos no aplicados, el usuario
  ///   no volvía a bajar NUNCA); queda solo como indicador informativo.
  /// - Rol 6 (UGR): baja el histórico de EDANs del municipio vía
  ///   `EdanSyncService.recargarEdansMunicipio()` (vía legacy, fuera del
  ///   alcance RESP) + recupera sus reportes propios por V2, también en cada
  ///   login.
  /// - El registro en la app es SOLO rol 7 (`id_rol: 7` forzado) y marca la
  ///   sincronización como hecha SIN descargar (arranque limpio); el rol 6 se
  ///   da de alta por la plataforma web y su primer login sí descarga.
  Future<void> _dispararCargaEdansMunicipio() async {
    final userId = _authService.userId;
    if (userId == null) return;
    if (_authService.idRol == 6) {
      final idMunicipio = _authService.currentToken?.idMunicipio;
      if (idMunicipio == null) return;
      EdanSyncService.instance.recargarEdansMunicipio(
        idMunicipio: idMunicipio,
        usuarioId: userId,
      );
      // Además del histórico del municipio, recupera los reportes PROPIOS del
      // UGR (formularios + secciones + fotos) en este dispositivo: mismo camino
      // V2 que usa RESP. Cubre el caso "perdió el celular y vuelve a entrar".
      unawaited(_recuperarReportesPropiosV2());
    } else if (_authService.idRol == 7) {
      // Descarga en cada login (flujo v1.2.0 con APIs V2): el watermark hace
      // el pull incremental, así que no cuesta una descarga completa. Si el
      // pull termina bien se marca la banda por si acaso; si falla, el
      // próximo login reintenta porque nada depende ya de esa marca.
      final ok = await _recuperarReportesPropiosV2();
      if (ok) await _marcarSyncInicialHecha(userId);
    }
  }

  /// Recupera en este dispositivo los reportes PROPIOS del usuario (cabecera +
  /// secciones + fotos) con el motor V2. Es el mismo camino que usa el botón de
  /// sync del RESP y sirve para el caso "perdió el celular y vuelve a entrar":
  /// el pull trae `formularios`/`filas_seccion`/`fotografias` y luego descarga
  /// los bytes de las fotos a `ruta_local`. No bloquea el login (fire-and-forget).
  ///
  /// Devuelve `true` si la corrida terminó sin error de red/servidor (los
  /// conflictos puntuales por ítem no la tumban). Avisa a la UI vía
  /// `primeraDescarga` para que refresque las pestañas.
  Future<bool> _recuperarReportesPropiosV2() async {
    final store = EdanStoreV2.instance;
    if (store.sincronizandoNotifier.value) return true;
    store.sincronizandoNotifier.value = true;
    var ok = true;
    try {
      Directory? dirFotos;
      try {
        final appDir = await getApplicationDocumentsDirectory();
        // Única carpeta de fotos (capturas y descargas): `report_photos/`.
        dirFotos = Directory('${appDir.path}/report_photos');
        await dirFotos.create(recursive: true);
      } catch (_) {
        dirFotos = null;
      }
      final resumen = await EdanSyncEngineV2(
        api: EdanApiV2(),
        dirFotos: dirFotos,
        usuarioId: _authService.userId,
      ).sincronizar();
      ok = resumen.exito;
      store.ultimoErrorPrimeraDescarga =
          ok ? null : (resumen.ultimoError ?? 'Sincronización inicial incompleta');
    } catch (e) {
      ok = false;
      store.ultimoErrorPrimeraDescarga = e.toString();
      debugPrint('Error recuperando reportes propios V2: $e');
    } finally {
      store.sincronizandoNotifier.value = false;
      await store.refrescarPendientes();
      store.primeraDescarga.value++;
    }
    return ok;
  }

  /// Marca (por usuario + dispositivo) que la sincronización inicial ya corrió.
  /// Solo indicador informativo: decidir si se descarga NO depende de esta
  /// marca (el rol 7 baja en cada login; ver [_dispararCargaEdansMunicipio]).
  Future<void> _marcarSyncInicialHecha(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_kFirstSyncPrefix$userId', true);
  }

  Future<void> logout() async {
    await _authService.logout();
    notifyListeners();
  }
}
