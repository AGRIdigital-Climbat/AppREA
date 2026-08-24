import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/theme.dart';
import '../../../models/ugr_models.dart';

class UgrEdanCard extends StatelessWidget {
  final UgrEdan edan;
  final VoidCallback onTap;

  const UgrEdanCard({super.key, required this.edan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final estado = edan.estado;
    final fechaFmt = DateFormat('dd/MM/yyyy').format(edan.fechaCreacion);
    final horaFmt = DateFormat('HH:mm').format(edan.fechaCreacion);
    final codigo = edan.codigo.isNotEmpty ? edan.codigo : 'EDAN';

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
                      codigo,
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
                  _buildBadge(estado.color, estado.icon, estado.label),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 13, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    fechaFmt,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.access_time, size: 13, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    horaFmt,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
              if (edan.tipoEvento.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 13, color: AppColors.pending),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        edan.tipoEvento,
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (edan.descripcion.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  edan.descripcion,
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 12, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      edan.responsable.isNotEmpty
                          ? 'Reportado por ${edan.responsable}'
                          : 'EDAN del municipio',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(Color color, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}
