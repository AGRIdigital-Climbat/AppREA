import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/reporte_offline.dart';

class ReporteCard extends StatelessWidget {
  final ReporteOffline reporte;
  final VoidCallback? onTap;

  const ReporteCard({
    super.key,
    required this.reporte,
    this.onTap,
  });

  Color _getBadgeColor() {
    if (reporte.sincronizado && reporte.estadoNombre != null) {
      switch (reporte.estadoNombre!.toLowerCase()) {
        case 'pendiente':
          return AppColors.pending;
        case 'revisado':
          return AppColors.primary;
        case 'atendido':
          return AppColors.completed;
        case 'cerrado':
          return AppColors.closed;
        case 'rechazado':
          return AppColors.rejected;
        default:
          return AppColors.textSecondary;
      }
    }
    if (reporte.sincronizado) return AppColors.completed;
    if (reporte.intentosSync >= 20) return AppColors.error;
    return AppColors.pending;
  }

  IconData _getBadgeIcon() {
    if (reporte.sincronizado && reporte.estadoNombre != null) {
      switch (reporte.estadoNombre!.toLowerCase()) {
        case 'pendiente':
          return Icons.schedule;
        case 'revisado':
          return Icons.visibility;
        case 'atendido':
          return Icons.check_circle;
        case 'cerrado':
          return Icons.lock;
        case 'rechazado':
          return Icons.cancel;
        default:
          return Icons.info_outline;
      }
    }
    if (reporte.sincronizado) return Icons.cloud_done;
    if (reporte.intentosSync >= 20) return Icons.cloud_off;
    return Icons.cloud_upload;
  }

  String _getBadgeText() {
    if (reporte.sincronizado) {
      return reporte.estadoNombre ?? 'Sincronizado';
    }
    if (reporte.intentosSync >= 20) return 'Error de sync';
    return 'Pendiente';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      reporte.comunidad,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildSmallBadge(),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 13, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    reporte.fechaEvento,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  if (reporte.horaEvento != null) ...[
                    const SizedBox(width: 10),
                    const Icon(Icons.access_time, size: 13, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      reporte.horaEvento!,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
              if (reporte.descripcion != null && reporte.descripcion!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  reporte.descripcion!,
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              _buildSyncLine(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmallBadge() {
    final color = _getBadgeColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_getBadgeIcon(), size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            _getBadgeText(),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncLine() {
    IconData icon;
    String text;
    Color color;

    if (reporte.sincronizado) {
      icon = Icons.cloud_done;
      text = 'Sincronizado';
      color = AppColors.completed;
    } else if (reporte.intentosSync >= 20) {
      icon = Icons.cloud_off;
      text = 'Error de sincronización';
      color = AppColors.error;
    } else {
      icon = Icons.cloud_upload;
      text = 'Pendiente de sincronización';
      color = AppColors.pending;
    }

    return Row(
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 11, color: color),
        ),
      ],
    );
  }
}