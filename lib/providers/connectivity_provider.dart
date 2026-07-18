import 'dart:async';
import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';

class ConnectivityProvider extends ChangeNotifier {
  final ConnectivityService _connectivityService = ConnectivityService();

  bool _isConnected = true;
  StreamSubscription<bool>? _subscription;

  bool get isConnected => _isConnected;

  Future<void> initialize() async {
    _isConnected = _connectivityService.isConnected;
    notifyListeners();

    _subscription = _connectivityService.connectionStream.listen((connected) {
      _isConnected = connected;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
