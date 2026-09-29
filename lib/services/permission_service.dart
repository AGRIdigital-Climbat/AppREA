import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<bool> requestCameraPermission() async {
    if (Platform.isWindows) return true;
    final status = await Permission.camera.status;

    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) return false;

    final result = await Permission.camera.request();
    return result.isGranted;
  }

  static Future<bool> requestLocationPermission() async {
    if (Platform.isWindows) return true;
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) return false;

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  static Future<bool> requestNotificationPermission() async {
    if (Platform.isWindows) return true;
    final status = await Permission.notification.status;
    if (status.isGranted) return true;

    final result = await Permission.notification.request();
    return result.isGranted;
  }

  static Future<bool> requestMicrophonePermission() async {
    if (Platform.isWindows) return true;
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) return false;

    final result = await Permission.microphone.request();
    return result.isGranted;
  }

  /// Verifica los permisos de ejecución del formulario EDAN (cámara +
  /// ubicación) para Android/iOS y solicita ÚNICAMENTE los que están
  /// inactivos (no concede los ya activos). En Windows no requiere nada y
  /// devuelve `true`. No muestra diálogos: si un permiso queda negado o el
  /// servicio de ubicación está apagado devuelve `false` y el flujo de captura
  /// (foto/coordenadas) muestra el aviso correspondiente. Cada llamada vuelve
  /// a verificar el estado real del sistema.
  static Future<bool> asegurarPermisosFormulario() async {
    if (Platform.isWindows) return true;

    final camOk = await requestCameraPermission();
    if (!camOk) return false;

    return await requestLocationPermission();
  }

  static void showPermissionDeniedDialog(
      BuildContext context, String permission) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permiso requerido'),
        content: Text(
          'La app necesita acceso a $permission para funcionar correctamente. '
          'Por favor, habilita el permiso en Configuración.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(context);
            },
            child: const Text('Abrir Configuración'),
          ),
        ],
      ),
    );
  }
}
