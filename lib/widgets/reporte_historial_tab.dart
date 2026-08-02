import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/reporte_provider.dart';
import '../screens/reporte_form_screen.dart';
import '../screens/reporte_detail_screen.dart';
import '../models/reporte_offline.dart';
import 'reporte_card.dart';

class ReportesHistorialTab extends StatefulWidget {
  const ReportesHistorialTab({super.key});

  @override
  State<ReportesHistorialTab> createState() => _ReportesHistorialTabState();
}

class _ReportesHistorialTabState extends State<ReportesHistorialTab> {
  String _filterStatus = 'all';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              _buildFilterChip('Todos', 'all'),
              const SizedBox(width: 8),
              _buildFilterChip('Pendientes', 'pending'),
              const SizedBox(width: 8),
              _buildFilterChip('Sincronizados', 'synced'),
            ],
          ),
        ),
        Expanded(
          child: Consumer<ReporteProvider>(
            builder: (context, reporteProvider, child) {
              if (reporteProvider.isLoading) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                );
              }

              var reportes = reporteProvider.reportes;

              if (_filterStatus == 'pending') {
                reportes = reportes.where((r) => !r.sincronizado).toList();
              } else if (_filterStatus == 'synced') {
                reportes = reportes.where((r) => r.sincronizado).toList();
              }

              if (reportes.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 80,
                        color: AppColors.textSecondary.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No hay reportes',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _filterStatus == 'all'
                            ? 'Cree su primer reporte de evento adverso'
                            : 'No hay reportes con este filtro',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  final result = await reporteProvider.refreshFromServer();
                  if (context.mounted) {
                    if (result == -1) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Error al consultar el servidor'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    } else if (result > 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$result reporte(s) actualizado(s)'),
                          backgroundColor: AppColors.primary,
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Reportes sin cambios'),
                          backgroundColor: AppColors.textSecondary,
                        ),
                      );
                    }
                  }
                },
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(top: 8),
                  itemCount: reportes.length,
                  itemBuilder: (context, index) {
                    final reporte = reportes[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ReporteCard(
                        reporte: reporte,
                        tipoEventoNombre: reporteProvider.getTipoEventoNombre(reporte.tipoEventoId),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ReporteDetailScreen(reporte: reporte),
                            ),
                          );
                        },
                        onEdit: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ReporteFormScreen(reporte: reporte),
                            ),
                          );
                        },
                        onDelete: () => _confirmDelete(context, reporte),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filterStatus == value;
    return Expanded(
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
        selected: isSelected,
        onSelected: (_) {
          setState(() => _filterStatus = value);
        },
        selectedColor: AppColors.primary,
        backgroundColor: AppColors.surface,
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }

  void _confirmDelete(BuildContext context, ReporteOffline reporte) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Reporte'),
        content: const Text('¿Está seguro de eliminar este reporte?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<ReporteProvider>().eliminarReporte(reporte.idLocal!);
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}
