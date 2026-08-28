import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._();
  factory ConnectivityService() => _instance;
  ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;
  bool _isConnected = true;
  int _consecutiveFailures = 0;
  static const int _maxConsecutiveFailures = 3;
  Timer? _periodicTimer;

  bool get isConnected => _isConnected;

  Future<void> initialize() async {
    try {
      _isConnected = await _checkConnection();
      _connectionController.add(_isConnected);
    } catch (e) {
      debugPrint('[Connectivity] init error: $e');
      _isConnected = false;
      _connectionController.add(false);
    }

    _connectivity.onConnectivityChanged.listen((results) async {
      try {
        final connected = await _checkConnection();
        _updateState(connected);
      } catch (e) {}
    });

    _periodicTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      try {
        final connected = await _checkConnection();
        _updateState(connected);
      } catch (e) {}
    });
  }

  void _updateState(bool connected) {
    if (connected) {
      if (!_isConnected) {
        _isConnected = true;
        _connectionController.add(true);
      }
      _consecutiveFailures = 0;
    } else {
      _consecutiveFailures++;
      if (_isConnected && _consecutiveFailures < _maxConsecutiveFailures) {
        return;
      }
      if (_isConnected) {
        _isConnected = false;
        _connectionController.add(false);
      }
    }
  }

  Future<bool> _checkConnection() async {
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
      return response.statusCode > 0;
    } catch (e) {
      return false;
    }
  }

  Future<bool> checkNow() async {
    try {
      final connected = await _checkConnection();
      _updateState(connected);
      return _isConnected;
    } catch (e) {
      _consecutiveFailures++;
      if (_consecutiveFailures >= _maxConsecutiveFailures) {
        _isConnected = false;
        _connectionController.add(false);
      }
      return _isConnected;
    }
  }

  void dispose() {
    _periodicTimer?.cancel();
    _connectionController.close();
  }
}
