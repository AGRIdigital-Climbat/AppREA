import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

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
          .head(Uri.parse('https://clients3.google.com/generate_204'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 204;
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    _connectionController.close();
  }
}
