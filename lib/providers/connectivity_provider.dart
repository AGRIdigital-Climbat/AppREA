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
    _isConnected = _connectivityService.isConnected;
    _chequeoCompletado = _connectivityService.chequeoCompletado;
    _suscribir();
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
