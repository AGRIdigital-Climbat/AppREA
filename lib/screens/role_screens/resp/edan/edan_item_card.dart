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
    final bool hayCoords = lat != 0 || lon != 0;
    final String textoCoords = hayCoords
        ? '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}'
        : 'Coordenadas: pendiente';

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
                    width: 48,
                    height: 48,
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
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: PaletteScope.of(context).primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icono, size: 22, color: PaletteScope.of(context).primary),
                  ),
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
                      if (onRespaldar != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          textoCoords,
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
                    if (onFoto != null) ...[
                      InkWell(
                        onTap: onFoto,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(Icons.photo_camera_outlined,
                                  size: 20, color: Color(0xFF4CAF50)),
                              if (fotoCount != null && fotoCount! > 0)
                                Positioned(
                                  right: -6,
                                  top: -6,
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF4CAF50),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      '$fotoCount',
                                      style: const TextStyle(
                                        fontSize: 8,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
            if (onRespaldar != null && !completo) ...[
              const SizedBox(height: 10),
              _chipRespaldo(coordsOk: coordsOk),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chipRespaldo({required bool coordsOk}) {
    final Color color = AppColors.pending;
    final String texto = coordsOk
        ? 'Coordenadas OK · falta foto'
        : 'Falta coordenadas y foto';
    return Material(
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onRespaldar,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: AppColors.pending,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  texto,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.pending,
                  ),
                ),
              ),
              const Text(
                'Tocar para capturar',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.pending,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
