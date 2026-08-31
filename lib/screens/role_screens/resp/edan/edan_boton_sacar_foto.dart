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

/// Botón de captura de foto + coordenadas GPS para el wizard EDAN.
///
/// Extraído de `_BotonSacarFoto` en `resp_edan_form_screen.dart`.
/// Flujo:
/// 1. El usuario presiona "Coordenadas" → GPS con precisión < 30m.
/// 2. Solo después puede presionar "Sacar foto" → cámara.
/// 3. La foto se guarda localmente con sus coordenadas.
class EdanBotonSacarFoto extends StatefulWidget {
  final List<EdanFoto> fotos;
  final VoidCallback onChanged;
  final String? fotografia;
  final double coordenadaLat;
  final double coordenadaLon;
  final void Function(double lat, double lon)? onCoordenadasCapturadas;
  final String? seccion;

  /// Solo para uso dentro de [Dialog]: en vez de abrir la cámara con el
  /// diálogo encima (que en Android 12+ deja el diálogo en blanco al volver),
  /// delega el cierre al diálogo y captura la foto fuera con [capturarFoto].
  final Future<void> Function(
          double latitud, double longitud, double precision)?
      onCapturaDesdeDialogo;

  const EdanBotonSacarFoto({
    super.key,
    required this.fotos,
    required this.onChanged,
    this.fotografia,
    this.coordenadaLat = 0,
    this.coordenadaLon = 0,
    this.onCoordenadasCapturadas,
    this.seccion,
    this.onCapturaDesdeDialogo,
  });

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

  @override
  State<EdanBotonSacarFoto> createState() => _EdanBotonSacarFotoState();
}

class _EdanBotonSacarFotoState extends State<EdanBotonSacarFoto> {
  static const double _precisionMinima = 30;

  bool _cargandoCoordenada = false;
  String? _advertencia;
  Position? _posicion;

  @override
  void initState() {
    super.initState();
    if (widget.fotos.isNotEmpty) {
      final foto = widget.fotos.first;
      if (foto.latitud != 0 || foto.longitud != 0) {
        _posicion = Position(
          latitude: foto.latitud,
          longitude: foto.longitud,
          accuracy: foto.precision,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
          timestamp: DateTime.now(),
          isMocked: false,
        );
      }
    }
  }

  Future<void> _capturarCoordenada() async {
    if (_cargandoCoordenada) return;
    setState(() {
      _cargandoCoordenada = true;
      _advertencia = null;
    });

    final hasPermission = await PermissionService.requestLocationPermission();
    if (!hasPermission) {
      if (mounted) {
        setState(() => _cargandoCoordenada = false);
        PermissionService.showPermissionDeniedDialog(context, 'ubicación');
      }
      return;
    }

    final start = DateTime.now();
    const timeout = Duration(seconds: 45);
    Position? mejorPos;

    while (DateTime.now().difference(start) < timeout && mounted) {
      final pos = await LocationService().getCurrentLocation();
      if (pos != null && mounted) {
        if (mejorPos == null || pos.accuracy < mejorPos.accuracy) {
          mejorPos = pos;
        }
        if (pos.accuracy <= _precisionMinima) {
          setState(() {
            _posicion = pos;
            _advertencia = null;
            _cargandoCoordenada = false;
          });
          return;
        }
        setState(() {
          _advertencia = 'Precisión actual: ${pos.accuracy.toStringAsFixed(0)}m. '
              'Reintentando hasta obtener < 30m...';
        });
      }
      await Future.delayed(const Duration(seconds: 2));
    }

    if (!mounted) return;
    setState(() => _cargandoCoordenada = false);

    if (mejorPos != null) {
      setState(() {
        _posicion = mejorPos;
        _advertencia = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Precisión alcanzada: ± ${mejorPos.accuracy.toStringAsFixed(0)} m'),
          backgroundColor: AppColors.pending,
        ),
      );
    } else {
      setState(() {
        _posicion = null;
        _advertencia =
            'No se pudo obtener la ubicación con precisión adecuada. Reintente.';
      });
    }
  }

  Future<void> _sacarFoto() async {
    if (_posicion == null) return;

    // Dentro de un Dialog: el diálogo se cierra, la página captura con
    // [capturarFoto] y lo vuelve a abrir (evita el diálogo blanco en
    // Android 12+ al volver de la cámara).
final de = widget.onCapturaDesdeDialogo;
    if (de != null &&
        context.findAncestorWidgetOfExactType<Dialog>() != null) {
      final p = _posicion!;
      await de(p.latitude, p.longitude, p.accuracy);
      return;
    }

    final ok = await EdanBotonSacarFoto.capturarFoto(
      fotos: widget.fotos,
      latitud: _posicion!.latitude,
      longitud: _posicion!.longitude,
      precision: _posicion!.accuracy,
    );
    if (!ok) return;

    if (mounted) {
      widget.onCoordenadasCapturadas?.call(
          _posicion!.latitude, _posicion!.longitude);
      widget.onChanged();
      setState(() => _advertencia = null);
    }
  }

  void _verFotoCompleta(
    EdanFoto? foto, {
    String? servidor,
    String? seccion,
  }) {
    EdanBotonSacarFoto.verFotoCompleta(
      context,
      fotos: widget.fotos,
      fotografia: widget.fotografia,
      coordenadaLat: widget.coordenadaLat,
      coordenadaLon: widget.coordenadaLon,
      seccion: seccion,
      onEliminada: () {
        widget.onChanged();
        setState(() => _advertencia = null);
      },
    );
  }

  Widget _fotoConFallback(EdanFoto foto, String server,
      {double? width, double? height}) {
    if (foto.ruta.trim().isNotEmpty && File(foto.ruta).existsSync()) {
      return Image.file(
        File(foto.ruta),
        height: height,
        width: width,
        cacheWidth: 480,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fotoPlaceholder(height: height),
      );
    }
    if (widget.fotografia != null && widget.fotografia!.isNotEmpty) {
      return Image.network(
        _fotoUrl(server, widget.fotografia!),
        height: height,
        width: width,
        cacheWidth: 480,
        fit: BoxFit.cover,
        headers: _fotoHeaders(),
        errorBuilder: (_, _, _) => _fotoPlaceholder(height: height),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _fotoPlaceholder(height: height),
      );
    }
    return _fotoPlaceholder(height: height);
  }

  Widget _fotoPlaceholder({double? height}) {
    return Container(
      height: height ?? 120,
      width: double.infinity,
      color: AppColors.background,
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported_outlined,
        size: 28,
        color: AppColors.textSecondary,
      ),
    );
  }

  String _fotoUrl(String server, String path) =>
      '$server/upload/descargar/${Uri.encodeComponent(path)}';

  Map<String, String> _fotoHeaders() {
    final token = AuthService.instance.currentToken?.accessToken;
    return token != null && token.isNotEmpty
        ? {'Authorization': 'Bearer $token'}
        : {};
  }

  @override
  Widget build(BuildContext context) {
    final primaria = PaletteScope.of(context).primary;
    final foto = widget.fotos.isNotEmpty ? widget.fotos.first : null;
    final tieneFotoLocal = foto != null;
    final tieneRemota = foto == null &&
        widget.fotografia != null &&
        widget.fotografia!.isNotEmpty;
    const server = ApiConfig.baseUrl;
    final coordenadaLista = _posicion != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _cargandoCoordenada ? null : _capturarCoordenada,
            icon: _cargandoCoordenada
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : Icon(
                    coordenadaLista ? Icons.gps_fixed : Icons.gps_not_fixed,
                    size: 18,
                  ),
            label: Text(
              _cargandoCoordenada
                  ? 'Buscando precisión < 30m...'
                  : (coordenadaLista
                      ? 'Obtener nuevas coordenadas'
                      : 'Coordenadas'),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: primaria,
              side: BorderSide(color: primaria, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (coordenadaLista)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.aprobado.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.aprobado.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on,
                  size: 18,
                  color: AppColors.aprobado,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_posicion!.latitude.toStringAsFixed(6)}, '
                    '${_posicion!.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.aprobado,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '±${_posicion!.accuracy.toStringAsFixed(0)}m',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.aprobado.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _posicion = null;
                      _advertencia = null;
                    });
                  },
                  child: const Icon(
                    Icons.close,
                    size: 18,
                    color: AppColors.error,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: coordenadaLista ? _sacarFoto : null,
            icon: const Icon(Icons.camera_alt_outlined, size: 18),
            label: const Text('Sacar foto'),
            style: OutlinedButton.styleFrom(
              backgroundColor: coordenadaLista
                  ? AppColors.aprobado
                  : Colors.transparent,
              foregroundColor: coordenadaLista ? Colors.white : primaria,
              side: BorderSide(
                color: coordenadaLista ? AppColors.aprobado : primaria,
                width: 1.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 6),
        if (_advertencia != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _advertencia!,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.pending,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else if (!coordenadaLista && !tieneRemota && foto == null)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Para el respaldo, capture primero las coordenadas '
              '(precisión menor a 30m) y luego tome la foto.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else if (coordenadaLista && foto == null && !tieneRemota)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Tome la foto para el respaldo.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.aprobado,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        if (tieneFotoLocal)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: GestureDetector(
                    onTap: () => _verFotoCompleta(
                      foto,
                      servidor: server,
                      seccion: widget.seccion,
                    ),
                    child: Stack(
                      children: [
                        _fotoConFallback(foto, server,
                            width: double.infinity, height: 120),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.fullscreen,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      size: 12,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${foto.latitud.toStringAsFixed(4)}, ${foto.longitud.toStringAsFixed(4)}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '±${foto.precision.toStringAsFixed(0)}m',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        widget.fotos.clear();
                        widget.onChanged();
                        setState(() => _advertencia = null);
                      },
                      child: const Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: AppColors.rechazado,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          )
        else if (tieneRemota)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: GestureDetector(
                    onTap: () => _verFotoCompleta(
                      null,
                      servidor: server,
                      seccion: widget.seccion,
                    ),
                    child: Stack(
                      children: [
                        Image.network(
                          _fotoUrl(server, widget.fotografia!),
                          height: 120,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          headers: _fotoHeaders(),
                          errorBuilder: (context, error, stackTrace) =>
                              const _FotoRemotaNoDisponible(),
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.fullscreen,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.coordenadaLat != 0 || widget.coordenadaLon != 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 12,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${widget.coordenadaLat.toStringAsFixed(6)}, '
                            '${widget.coordenadaLon.toStringAsFixed(6)}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          )
        else if (widget.coordenadaLat != 0 || widget.coordenadaLon != 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.aprobado.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.aprobado.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on,
                  size: 18,
                  color: AppColors.aprobado,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.coordenadaLat.toStringAsFixed(6)}, '
                    '${widget.coordenadaLon.toStringAsFixed(6)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.aprobado,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
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
