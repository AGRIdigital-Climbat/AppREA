import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

/// Estado de red de la app.
///
/// No basta con saber que hay interfaz de WiFi: un portal cautivo o un API
/// caido responden igual. Por eso se valida contra el servidor real.
///
/// Importante: hay dos ventanas historicas en las que esta clase mentia y por
/// eso la app mostraba errores rojos al usuario que solo estaba sin internet:
///   - `_isConnected` arrancaba en `true` y el primer chequeo puede tardar
///     hasta 13 s (3 s de connectivity_plus + 10 s del HEAD).
///   - La histeresis de 3 fallos daba 45 s para "`darse cuenta`" de que se
///     cayo la red mientras la app estaba abierta.
/// Para ambas, usar [chequeoCompletado] como puerta antes de disparar trabajo
/// de red, o [checkNow] para una verificacion real sin histeresis.
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._();
  factory ConnectivityService() => _instance;
  ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;
  bool _isConnected = true;
  bool _chequeoCompletado = false;
  int _consecutiveFailures = 0;
  static const int _maxConsecutiveFailures = 3;
  Timer? _periodicTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  /// Future del arranque en curso. Permite que [initialize] sea idempotente
  /// *y* esperable: si dos pantallas lo llaman a la vez, la segunda recibe el
  /// mismo Future en vez de retornar de inmediato con el estado aun sin
  /// resolver (que era justo el bug que dejaba el boton Sincronizar apagado).
  Future<void>? _initFuture;

  /// Chequeo de red inyectable para pruebas (evita plugin y red reales).
  @visibleForTesting
  static Future<bool> Function()? debugChequeoDeRed;

  /// En pruebas: no suscribirse a connectivity_plus.
  @visibleForTesting
  static bool debugOmitirPlugin = false;

  bool get isConnected => _isConnected;

  /// `true` cuando ya se resolvio el primer chequeo real de red.
  ///
  /// Mientras sea `false`, [isConnected] es un valor optimista heredado y NO
  /// sirve como puerta para lanzar operaciones de red: haria exactamente lo
  /// que se queria evitar, creyendo que hay internet cuando no lo hay.
  bool get chequeoCompletado => _chequeoCompletado;

  /// Idempotente: se puede llamar desde varias pantallas sin duplicar la
  /// suscripcion a `onConnectivityChanged` ni el timer periodico. Antes cada
  /// entrada a una pantalla de rol suma un timer de 15 s que nunca se cancela.
  Future<void> initialize() {
    return _initFuture ??= _initializeInterno();
  }

  Future<void> _initializeInterno() async {
    if (!debugOmitirPlugin) {
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
        _,
      ) async {
        await _consultarYActualizar();
      });
    }

    await _consultarYActualizar();

    _periodicTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      await _consultarYActualizar();
    });
  }

  Future<void> _consultarYActualizar() async {
    final connected = await _checkConnection();
    if (_chequeoCompletado) {
      _updateState(connected);
      return;
    }
    // El primer chequeo NO pasa por la histeresis: si estamos sin red hay que
    // saberlo ya, no 45 segundos despues.
    //
    // Importante: se comunica SIEMPRE a los suscriptores, sin el atajo de
    // `_aplicarEstado` (que solo emite cuando el estado cambia). Como el valor
    // optimista inicial es `true`, con red estable el resultado tambien es
    // `true` y no se emitia nada: el `ConnectivityProvider` nunca recibia
    // `chequeoCompletado = true` y el boton Sincronizar quedaba deshabilitado
    // de por vida (hasta que un corte de red forzara una transicion).
    _chequeoCompletado = true;
    _consecutiveFailures = connected ? 0 : _maxConsecutiveFailures;
    _isConnected = connected;
    _connectionController.add(connected);
    // Traza unica: deja registro de con que estado arranco la sesion, que es
    // lo primero que hay que saber cuando el modo offline se comporta raro.
    debugPrint('[Connectivity] primer chequeo: ${connected ? 'online' : 'offline'}');
  }

  void _aplicarEstado(bool connected) {
    if (connected == _isConnected) return;
    _isConnected = connected;
    _connectionController.add(connected);
  }

  void _updateState(bool connected) {
    if (connected) {
      _consecutiveFailures = 0;
      _aplicarEstado(true);
      return;
    }
    // Histeresis: un micro-corte de red no debe marcar al usuario como offline.
    _consecutiveFailures++;
    if (_consecutiveFailures >= _maxConsecutiveFailures) {
      _aplicarEstado(false);
    }
  }

  Future<bool> _checkConnection() async {
    final override = debugChequeoDeRed;
    if (override != null) return override();
    try {
      final results = await _connectivity
          .checkConnectivity()
          .timeout(const Duration(seconds: 3));
      if (results.isEmpty || results.first == ConnectivityResult.none) {
        return false;
      }

      final response = await http
          .head(Uri.parse(ApiConfig.baseUrl))
          .timeout(const Duration(seconds: 10));
      // Un 5xx no es internet utilizable para esta app: marcarlo "conectado"
      // solo sirve para que cada peticion posterior falle y muestre un error
      // rojo que en realidad es un problema del servidor.
      return response.statusCode < 500;
    } catch (e) {
      return false;
    }
  }

  /// Verificacion inmediata y sin histeresis.
  ///
  /// Devuelve lo que se pudo comprobar ahora, no el valor cacheado, para que
  /// sirva como puerta fiable antes de una operacion de red. A diferencia de
  /// [isConnected], un fallo aqui SI pasa el estado global a offline de
  /// inmediato, porque el usuario acaba de pedir la comprobacion.
  Future<bool> checkNow() async {
    final connected = await _checkConnection();
    _chequeoCompletado = true;
    _consecutiveFailures = connected ? 0 : _maxConsecutiveFailures;
    _aplicarEstado(connected);
    return connected;
  }

  /// Reinicia el singleton al estado inicial para pruebas. No cierra el
  /// StreamController (que es broadcast y se reutiliza entre pruebas).
  @visibleForTesting
  void debugReset() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _initFuture = null;
    _isConnected = true;
    _chequeoCompletado = false;
    _consecutiveFailures = 0;
    debugChequeoDeRed = null;
    debugOmitirPlugin = false;
  }

  void dispose() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _initFuture = null;
    _connectionController.close();
  }
}
