import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../config/theme.dart';
import 'permission_service.dart';

/// Servicio de ubicación multiplataforma.
/// - Android/iOS: GPS real via geolocator
/// - Windows: ingreso manual de coordenadas
class LocationService {
  static final LocationService _instance = LocationService._();
  factory LocationService() => _instance;
  LocationService._();

  /// Retorna la ubicación actual según la plataforma.
  /// - Windows: posición fija (aprox. Bolívia) para testing.
  /// - Android/iOS: GPS real via geolocator.
  Future<Position?> getCurrentLocation() async {
    if (Platform.isWindows) {
      // Windows: Forzar ingreso manual/posición fija para testing/talleres
      return _manualLocationWindows();
    }
    return await _getLocationByGPS();
  }

  /// Muestra un diálogo manual de ingreso de coordenadas (solo Windows).
  /// El usuario escribe latitud y longitud. Retorna [Position] o null si cancela.
  static Future<Position?> manualLocationDialog(
    BuildContext context, {
    double latInicial = 0,
    double lonInicial = 0,
  }) async {
    final latCtrl = TextEditingController(
      text: latInicial != 0 ? latInicial.toStringAsFixed(6) : '',
    );
    final lonCtrl = TextEditingController(
      text: lonInicial != 0 ? lonInicial.toStringAsFixed(6) : '',
    );
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_on_outlined, color: AppColors.completed, size: 22),
            SizedBox(width: 10),
            Text('Coordenadas manuales', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Ingresa las coordenadas del punto de muestreo:',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: latCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(
                  labelText: 'Latitud',
                  hintText: 'ej: -16.500000',
                  prefixIcon: const Icon(Icons.north, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Requerido';
                  final n = double.tryParse(v.trim());
                  if (n == null) return 'Número inválido';
                  if (n < -90 || n > 90) return 'Rango: -90 a 90';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: lonCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(
                  labelText: 'Longitud',
                  hintText: 'ej: -68.000000',
                  prefixIcon: const Icon(Icons.east, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Requerido';
                  final n = double.tryParse(v.trim());
                  if (n == null) return 'Número inválido';
                  if (n < -180 || n > 180) return 'Rango: -180 a 180';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.completed),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(true);
              }
            },
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Usar coordenadas'),
          ),
        ],
      ),
    );

    if (result == true) {
      final lat = double.parse(latCtrl.text.trim());
      final lon = double.parse(lonCtrl.text.trim());
      return Position(
        latitude: lat,
        longitude: lon,
        timestamp: DateTime.now(),
        accuracy: 10.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );
    }
    return null;
  }

  /// Windows: posición fija para testing/talleres.
  /// THESE COORDINATES ARE MANUALLY SET for testing purposes only.
  /// To change them, edit the values below directly.
  /// NOT obtained via geolocator - user inputs them manually.
  /// Bolívia: coordenadas aproximadas para testing (La Paz approx.).
  Position?_manualLocationWindows() {
    return Position(
      latitude: -16.2902, // LatitudBolivia (La Paz approx.)
      longitude: -63.5887, // LongitudBolivia (La Paz approx.)
      timestamp: DateTime.now(),
      /// Accuracy alta para entrada manual: since user enters coords directly,
      /// precision de 30m no es requerida ni garantizada.
      /// Se usa un valor alto para indicar "aproximado por entrada manual".
      accuracy: 100000.0, // Accuracy alta - entrada manual, no GPS preciso
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );
  }

  /// GPS real para Android/iOS.
  Future<Position?> _getLocationByGPS() async {
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      final granted = await PermissionService.requestLocationPermission();
      if (!granted) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      return null;
    }
  }

  /// Stream de ubicación actualizado según la plataforma.
  /// - Windows: posición fija cada 30 segundos para testing.
  ///   Accuracy alta para entrada manual (no GPS preciso).
  /// - Android/iOS: GPS real con alta precisión.
  Stream<Position> getLocationStream() {
    if (Platform.isWindows) {
      // Windows: Para testing/talleres, retornar posición fija cada 30 seg
      // Accuracy alta para entrada manual (no GPS preciso)
      return Stream.periodic(
        const Duration(seconds: 30),
        (_) => Position(
          latitude: -16.2902, // LatitudBolivia (La Paz approx.)
          longitude: -63.5887, // LongitudBolivia (La Paz approx.)
          timestamp: DateTime.now(),
          accuracy: 100000.0, // Accuracy alta - entrada manual, no GPS preciso
          altitude: 0.0,
          altitudeAccuracy: 0.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
        ),
      );
    }
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    );
  }
}