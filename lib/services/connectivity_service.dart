import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
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
  bool _isConnected = false;

  bool get isConnected => _isConnected;

  Future<void> initialize() async {
    try {
      _isConnected = await _checkConnection();
      _connectionController.add(_isConnected);
    } catch (e) {
      _isConnected = false;
      _connectionController.add(false);
    }

    _connectivity.onConnectivityChanged.listen((_) async {
      try {
        final connected = await _checkConnection();
        if (_isConnected != connected) {
          _isConnected = connected;
          _connectionController.add(connected);
        }
      } catch (e) {
        // Silenciar errores de conectividad
      }
    });
  }

  Future<bool> _checkConnection() async {
    try {
      final results = await _connectivity.checkConnectivity()
          .timeout(const Duration(seconds: 3));
      if (results.isEmpty || results.first == ConnectivityResult.none) return false;

      final response = await http
          .head(Uri.parse(ApiConfig.baseUrl))
          .timeout(const Duration(seconds: 8));
      return response.statusCode > 0;
    } catch (e) {
      return false;
    }
  }

  Future<bool> checkNow() async {
    try {
      _isConnected = await _checkConnection();
      _connectionController.add(_isConnected);
      return _isConnected;
    } catch (e) {
      _isConnected = false;
      _connectionController.add(false);
      return false;
    }
  }

  void dispose() {
    _connectionController.close();
  }
}
