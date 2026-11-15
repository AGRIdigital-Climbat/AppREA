import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/edan.dart';

/// Texto pequeño con el motivo de rechazo (`observacion_estado`, API v2) que
/// manda el servidor. Solo se pinta cuando el estado es "Rechazado UGR" y el
/// motivo viene no vacío; en cualquier otro caso ocupa cero espacio.
///
/// Se usa en los listados de localidades del Rol 6 (UGR) y Rol 7 (RESP).
class EdanMotivoRechazo extends StatelessWidget {
  final EdanLocalidad localidad;

  const EdanMotivoRechazo({super.key, required this.localidad});

  @override
  Widget build(BuildContext context) {
    final motivo = (localidad.observacionEstado ?? '').trim();
    if (motivo.isEmpty ||
        localidad.estadoLocalidad != UgrLocalidadEstado.rechazadoUgr) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.feedback_outlined,
              size: 12, color: AppColors.rechazado),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Motivo del rechazo: $motivo',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.rechazado,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
