import 'package:flutter/material.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import 'edan_boton_sacar_foto.dart';

/// Card de ítem colapsable dentro de una subsección.
///
/// Muestra el título del ítem, un subtítulo con resumen de datos y botones
/// de acción (Editar / Foto / Eliminar). Se usa para cultivos, establecimientos,
/// unidades educativas, etc.
class EdanItemCard extends StatelessWidget {
  final String titulo;
  final String? subtitulo;
  final IconData icono;
  final VoidCallback onEditar;
  final VoidCallback? onFoto;
  final VoidCallback onEliminar;
  final int? fotoCount;

  /// Al definir [onRespaldar] se muestra en la tarjeta el chip de estado de
  /// respaldo (Diseño C): al tocarlo se captura coordenadas/foto desde la
  /// página (sin pasar por el diálogo).
  final VoidCallback? onRespaldar;

  /// Al definir [onCambiarFoto] se muestra una acción "Cambiar foto" cuando el
  /// ítem ya tiene foto/coordenadas. Al tocarla se recapturan coordenadas y
  /// se toma una foto nueva (reemplazando la existente).
  final VoidCallback? onCambiarFoto;

  final bool tieneCoordenadas;
  final bool tieneFoto;

  /// ítem con foto/coordenadas ([EdanFotoHolder]). Si tiene foto (local o
  /// remota), se muestra en miniatura a la izquierda y al tocarla se abre el
  /// visor con zoom. El chip de estado se oculta cuando ya está completo.
  final EdanFotoHolder? respaldo;
  final String? seccionRespaldo;
  final VoidCallback? onFotoEliminada;

  const EdanItemCard({
    super.key,
    required this.titulo,
    this.subtitulo,
    required this.icono,
    required this.onEditar,
    this.onFoto,
    required     this.onEliminar,
    this.fotoCount,
    this.onRespaldar,
    this.onCambiarFoto,
    this.tieneCoordenadas = false,
    this.tieneFoto = false,
    this.respaldo,
    this.seccionRespaldo,
    this.onFotoEliminada,
  });

  @override
  Widget build(BuildContext context) {
    final EdanFoto? fotoLocal =
        (respaldo?.fotos.isNotEmpty ?? false) ? respaldo!.fotos.first : null;
    final bool completo = respaldo != null
        ? (fotoLocal != null || (respaldo!.fotografia?.isNotEmpty ?? false))
        : tieneFoto;
    final bool coordsOk = respaldo != null
        ? (respaldo!.coordenadaLat != 0 || respaldo!.coordenadaLon != 0)
        : tieneCoordenadas;
    final double lat = respaldo?.coordenadaLat ?? 0;
    final double lon = respaldo?.coordenadaLon ?? 0;
    final double prec =
        respaldo != null && respaldo!.fotos.isNotEmpty
            ? respaldo!.fotos.first.precision
            : 0;
    final bool hayCoords = lat != 0 || lon != 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (completo)
                  EdanFotoMiniatura(
                    foto: fotoLocal,
                    fotografia: respaldo?.fotografia,
                    width: 72,
                    height: 72,
                    onTap: () => EdanBotonSacarFoto.verFotoCompleta(
                      context,
                      fotos: respaldo?.fotos ?? const <EdanFoto>[],
                      fotografia: respaldo?.fotografia,
                      coordenadaLat: respaldo?.coordenadaLat ?? 0,
                      coordenadaLon: respaldo?.coordenadaLon ?? 0,
                      seccion: seccionRespaldo,
                      onEliminada: () => onFotoEliminada?.call(),
                    ),
                  )
                else
                  _miniaturaSinFoto(context, coordsOk: coordsOk),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (subtitulo != null && subtitulo!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitulo!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: onEditar,
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.edit_outlined,
                            size: 20, color: Color(0xFF2196F3)),
                      ),
                    ),
                    InkWell(
                      onTap: onEliminar,
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.delete_outline,
                            size: 20, color: Color(0xFFF44336)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            _bannerFoto(
              context,
              hasFoto: completo,
              hayCoords: hayCoords,
              lat: lat,
              lon: lon,
              prec: prec,
            ),
          ],
        ),
      ),
    );
  }

  /// Zona de miniatura cuando NO hay foto: cuadro 72×72 con ícono de cámara y
  /// badge ámbar que resalta que es importante sacar una foto.
  Widget _miniaturaSinFoto(BuildContext context, {required bool coordsOk}) {
    return GestureDetector(
      onTap: onRespaldar,
      child: Stack(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.pending.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.pending.withValues(alpha: 0.6),
              ),
            ),
            child: Icon(
              Icons.photo_camera_outlined,
              size: 26,
              color: coordsOk ? AppColors.completed : AppColors.pending,
            ),
          ),
          // Badge ámbar "sin foto"
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.pending,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Banner amplio de estado de foto (siempre visible).
  /// - Sin foto: ámbar, invita a sacarla (tap → onRespaldar).
  /// - Con foto: verde, muestra coords/precisión (tap → onCambiarFoto).
  Widget _bannerFoto(
    BuildContext context, {
    required bool hasFoto,
    required bool hayCoords,
    required double lat,
    required double lon,
    required double prec,
  }) {
    if (hasFoto) {
      final String coords = hayCoords
          ? '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}'
          : 'Coordenadas: pendiente';
      return _banner(
        color: AppColors.completed,
        icono: Icons.check_circle_outline,
        titulo: 'Foto OK',
        subtitulo: prec > 0 ? '$coords · ±${prec.toStringAsFixed(0)}m' : coords,
        onTap: onCambiarFoto,
      );
    }
    return _banner(
      color: AppColors.pending,
      icono: Icons.photo_camera_outlined,
      titulo: 'Sin foto — es importante sacar una foto',
      subtitulo: 'Tocar para capturar coordenadas y tomar la foto',
      onTap: onRespaldar,
    );
  }

  Widget _banner({
    required Color color,
    required IconData icono,
    required String titulo,
    required String subtitulo,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icono, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    if (subtitulo.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitulo,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
