import 'dart:io';

/// Centraliza las capacidades por plataforma.
/// Mantiene Android/iOS intactos y habilita Windows con alternativas.
class PlatformFeatures {
  PlatformFeatures._();

  static bool get isMobile => Platform.isAndroid || Platform.isIOS;
  static bool get isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  static bool get isWindows => Platform.isWindows;

  /// Cámara: disponible en Android, iOS y Windows (si tiene hardware).
  static bool get puedeUsarCamara => true;

  /// GPS: solo Android/iOS. Windows usa geolocalización por IP.
  static bool get puedeUsarGPS => isMobile;

  /// Permisos de almacenamiento: solo Android/iOS.
  static bool get necesitaPermisosStorage => isMobile;

  /// Permisos de cámara: solo Android/iOS. Windows no requiere.
  static bool get necesitaPermisosCamara => isMobile;

  /// Permisos de ubicación: solo Android/iOS.
  static bool get necesitaPermisosUbicacion => isMobile;
}
