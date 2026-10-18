import 'dart:async';
import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';

/// Puente entre [ConnectivityService] y la UI.
///
/// Expone [chequeoCompletado] para que las pantallas puedan distinguir
/// "estamos sin conexion" de "todavia no sabemos", que son cosas distintas y
/// merecen comportamientos distintos.
class ConnectivityProvider extends ChangeNotifier {
  final ConnectivityService _connectivityService = ConnectivityService();

  bool _isConnected = true;
  bool _chequeoCompletado = false;
  StreamSubscription<bool>? _subscription;

  bool get isConnected => _isConnected;
  bool get chequeoCompletado => _chequeoCompletado;

  Future<void> initialize() async {
    // Nos suscribimos antes de esperar el primer chequeo para no perder la
    // transicion inicial. Luego esperamos a que el servicio resuelva el
    // chequeo: asi `chequeoCompletado` refleja el estado real y no el optimista
    // de arranque. Antes se copiaba el valor de inmediato (aun en vuelo) y,
    // con red estable, nunca llegaba a `true`: el boton Sincronizar quedaba
    // deshabilitado hasta que un corte de red forzara una transicion.
    _suscribir();
    await _connectivityService.initialize();
    _isConnected = _connectivityService.isConnected;
    _chequeoCompletado = _connectivityService.chequeoCompletado;
    notifyListeners();
  }

  /// Idempotente: varias pantallas pueden pedirlo sin duplicar la suscripcion
  /// al broadcast del servicio (que ademas perderia eventos si se duplica).
  void _suscribir() {
    if (_subscription != null) return;
    _subscription = _connectivityService.connectionStream.listen((connected) {
      _isConnected = connected;
      _chequeoCompletado = true;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }
}
