import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../config/api_config.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/image_service.dart';
import '../../../../services/location_service.dart';
import '../../../../services/permission_service.dart';
import 'edan_dialog_helper.dart';

/// Utilidades de captura de foto + coordenadas GPS para el wizard EDAN.
///
/// Extraído de `_BotonSacarFoto` en `resp_edan_form_screen.dart`. El flujo de
/// respaldo por ítem se dispara desde la propia página (nunca dentro de un
/// diálogo): primero se captura el GPS con precisión < 30m y luego la cámara.
class EdanBotonSacarFoto {
  /// Captura las coordenadas con precisión < 30m. Devuelve la [Position]
  /// o null si no se logró. Pensado para usarse desde la página (no un
  /// diálogo) en el flujo de respaldo por ítem.
  static Future<Position?> capturarCoordenadas(
    BuildContext context, {
    double precisionMinima = 30,
  }) async {
    final hasPermission = await PermissionService.requestLocationPermission();
    if (!hasPermission) {
      if (context.mounted) {
        PermissionService.showPermissionDeniedDialog(context, 'ubicación');
      }
      return null;
    }

    final start = DateTime.now();
    const timeout = Duration(seconds: 45);
    Position? mejorPos;

    while (DateTime.now().difference(start) < timeout) {
      final pos = await LocationService().getCurrentLocation();
      if (pos != null) {
        if (mejorPos == null || pos.accuracy < mejorPos.accuracy) {
          mejorPos = pos;
        }
        if (pos.accuracy <= precisionMinima) {
          return pos;
        }
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    return mejorPos;
  }

  /// Flujo de respaldo por ítem (Diseño C): captura coordenadas si faltan y
  /// siempre toma una foto nueva, guardando todo en [fotos]/coordenadas.
  /// Devuelve true si se completó el respaldo. Debe llamarse con el contexto
  /// de la página (nunca dentro de un diálogo).
  /// [onCoordenadasCapturadas] recibe las coordenadas finales para que la
  /// página las escriba en el ítem (coordenadaLat/coordenadaLon).
  static Future<bool> capturarRespaldo(
    BuildContext context, {
    required List<EdanFoto> fotos,
    required double latActual,
    required double lonActual,
    required void Function(double lat, double lon) onCoordenadasCapturadas,
  }) async {
    double lat = latActual;
    double lon = lonActual;
    double prec = 0;

    if (lat == 0 && lon == 0) {
      final pos = await capturarCoordenadas(context);
      if (pos == null) return false;
      lat = pos.latitude;
      lon = pos.longitude;
      prec = pos.accuracy;
    } else if (fotos.isNotEmpty) {
      prec = fotos.first.precision;
    }

    onCoordenadasCapturadas(lat, lon);
    return capturarFoto(
      fotos: fotos,
      latitud: lat,
      longitud: lon,
      precision: prec,
    );
  }

  /// Cambia la foto de un ítem que ya tiene una: **siempre** vuelve a
  /// capturar las coordenadas GPS (precisión < 30m) primero y luego toma la
  /// foto nueva, reemplazando la existente en [fotos].
  /// Devuelve true si se completó el cambio. Debe llamarse con el contexto
  /// de la página (nunca dentro de un diálogo).
  static Future<bool> cambiarFoto(
    BuildContext context, {
    required List<EdanFoto> fotos,
    required void Function(double lat, double lon) onCoordenadasCapturadas,
  }) async {
    final pos = await capturarCoordenadas(context);
    if (pos == null) return false;
    onCoordenadasCapturadas(pos.latitude, pos.longitude);
    return capturarFoto(
      fotos: fotos,
      latitud: pos.latitude,
      longitud: pos.longitude,
      precision: pos.accuracy,
    );
  }

  /// Captura una foto con la cámara y la guarda en [fotos] con sus
  /// coordenadas. Utilizable también fuera del widget cuando la captura
  /// se hace con el diálogo ya cerrado.
  static Future<bool> capturarFoto({
    required List<EdanFoto> fotos,
    required double latitud,
    required double longitud,
    required double precision,
  }) async {
    final hasPermission = await PermissionService.requestCameraPermission();
    if (!hasPermission) {
      return false;
    }
    final imagen = await ImageService().takePhoto();
    if (imagen == null) return false;
    final savedPath = await ImageService().saveImageLocally(imagen);
    fotos.clear();
    fotos.add(EdanFoto(
      ruta: savedPath,
      latitud: latitud,
      longitud: longitud,
      precision: precision,
    ));
    return true;
  }

  /// Visor a pantalla completa de la foto con zoom (InteractiveViewer),
  /// coordenadas y botón de borrado. Reutilizable fuera del widget; al borrar
  /// limpia [fotos] y notifica [onEliminada] para refrescar la UI.
  static void verFotoCompleta(
    BuildContext context, {
    required List<EdanFoto> fotos,
    String? fotografia,
    double coordenadaLat = 0,
    double coordenadaLon = 0,
    String? seccion,
    VoidCallback? onEliminada,
  }) {
    final EdanFoto? foto = fotos.isNotEmpty ? fotos.first : null;
    final lat = foto != null && foto.latitud != 0 ? foto.latitud : coordenadaLat;
    final lon = foto != null && foto.longitud != 0 ? foto.longitud : coordenadaLon;
    final precision = foto?.precision ?? 0;
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4,
                  child: Center(
                    child: _imagenCompleta(
                      dialogCtx,
                      foto: foto,
                      fotografia: fotografia,
                    ),
                  ),
                ),
              ),
              if (seccion != null)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Container(
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Respaldo - $seccion',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 28,
                          ),
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                        ),
                      ),
                      const Spacer(),
                      if (lat != 0 || lon != 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${lat.toStringAsFixed(4)}, '
                                  '${lon.toStringAsFixed(4)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (precision > 0)
                                Text(
                                  '±${precision.toStringAsFixed(0)}m',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              const SizedBox(width: 10),
                              if (foto != null)
                                GestureDetector(
                                  onTap: () async {
                                    final ok = await confirmarEliminacion(
                                      dialogCtx,
                                      titulo: '¿Eliminar foto?',
                                      mensaje: 'Se eliminará la foto de respaldo de este ítem.',
                                    );
                                    if (!ok) return;
                                    Navigator.of(dialogCtx).pop();
                                    fotos.clear();
                                    onEliminada?.call();
                                  },
                                  child: const Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                    color: Colors.white,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _imagenCompleta(
    BuildContext context, {
    EdanFoto? foto,
    String? fotografia,
    String? servidor,
  }) {
    final server = servidor ?? ApiConfig.baseUrl;
    if (foto != null && foto.ruta.isNotEmpty) {
      final file = File(foto.ruta);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const _FotoRemotaNoDisponible(),
        );
      }
    }
    if (fotografia != null && fotografia.isNotEmpty) {
      return Image.network(
        _fotoUrl(server, fotografia),
        fit: BoxFit.contain,
        headers: _fotoHeaders(),
        errorBuilder: (context, error, stackTrace) =>
            const _FotoRemotaNoDisponible(),
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
      );
    }
    return const _FotoRemotaNoDisponible();
  }

  static String _fotoUrl(String server, String path) =>
      '$server/upload/descargar/${Uri.encodeComponent(path)}';

  static Map<String, String> _fotoHeaders() {
    final token = AuthService.instance.currentToken?.accessToken;
    return token != null && token.isNotEmpty
        ? {'Authorization': 'Bearer $token'}
        : {};
  }
}

class _FotoRemotaNoDisponible extends StatelessWidget {
  const _FotoRemotaNoDisponible();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF3A3A3A),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              size: 40,
              color: Colors.white54,
            ),
            SizedBox(height: 8),
            Text(
              'Foto no disponible',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Miniatura de la foto de respaldo de un ítem (local primero, remota como
/// fallback). Al tocarla se abre el visor completo vía [EdanBotonSacarFoto.verFotoCompleta].
class EdanFotoMiniatura extends StatelessWidget {
  final EdanFoto? foto;
  final String? fotografia;
  final double? width;
  final double? height;
  final VoidCallback? onTap;

  const EdanFotoMiniatura({
    super.key,
    this.foto,
    this.fotografia,
    this.width,
    this.height,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget contenido;
    final ruta = foto?.ruta ?? '';
    if (ruta.trim().isNotEmpty && File(ruta).existsSync()) {
      contenido = Image.file(
        File(ruta),
        width: width,
        height: height,
        cacheWidth: 480,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    } else if (fotografia != null && fotografia!.isNotEmpty) {
      contenido = Image.network(
        EdanBotonSacarFoto._fotoUrl(ApiConfig.baseUrl, fotografia!),
        width: width,
        height: height,
        cacheWidth: 480,
        fit: BoxFit.cover,
        headers: EdanBotonSacarFoto._fotoHeaders(),
        errorBuilder: (_, _, _) => _placeholder(),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _placeholder(),
      );
    } else {
      contenido = _placeholder();
    }

    final miniatura = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: width,
        height: height,
        child: contenido,
      ),
    );

    if (onTap == null) return miniatura;
    return GestureDetector(onTap: onTap, child: miniatura);
  }

  Widget _placeholder() {
    return Container(
      width: width,
      height: height,
      color: AppColors.background,
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported_outlined,
        size: 18,
        color: AppColors.textSecondary,
      ),
    );
  }
}
