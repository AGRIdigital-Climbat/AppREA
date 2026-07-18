import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/reporte_offline.dart';
import '../providers/reporte_provider.dart';

class ReporteDetailScreen extends StatelessWidget {
  final ReporteOffline reporte;

  const ReporteDetailScreen({super.key, required this.reporte});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Detalle del Reporte'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (!reporte.sincronizado)
            IconButton(
              icon: const Icon(Icons.sync),
              onPressed: () {
                context.read<ReporteProvider>().sincronizarPendientes();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Intentando sincronizar...'),
                    backgroundColor: AppColors.primary,
                  ),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _showDeleteDialog(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusHeader(),
            const SizedBox(height: 24),
            _buildInfoSection('Ubicación', [
              _buildInfoRow(Icons.map, 'Departamento', reporte.departamentoId.toString()),
              _buildInfoRow(Icons.map_outlined, 'Provincia', reporte.provinciaId.toString()),
              _buildInfoRow(Icons.location_city, 'Municipio', reporte.municipioId.toString()),
              _buildInfoRow(Icons.home, 'Comunidad', reporte.comunidad),
            ]),
            const SizedBox(height: 16),
            _buildInfoSection('Evento', [
              _buildInfoRow(Icons.calendar_today, 'Fecha', reporte.fechaEvento),
              if (reporte.horaEvento != null)
                _buildInfoRow(Icons.access_time, 'Hora', reporte.horaEvento!),
              _buildInfoRow(Icons.warning_amber, 'Tipo', _getTipoEvento(reporte.tipoEventoId)),
            ]),
            if (reporte.descripcion != null && reporte.descripcion!.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildInfoSection('Descripción', [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    reporte.descripcion!,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ]),
            ],
            if (reporte.coordenadaLat != null && reporte.coordenadaLon != null) ...[
              const SizedBox(height: 16),
              _buildInfoSection('Coordenadas', [
                _buildInfoRow(
                  Icons.my_location,
                  'Latitud',
                  reporte.coordenadaLat!.toStringAsFixed(6),
                ),
                _buildInfoRow(
                  Icons.my_location_outlined,
                  'Longitud',
                  reporte.coordenadaLon!.toStringAsFixed(6),
                ),
              ]),
            ],
            if (reporte.imagenes != null && reporte.imagenes!.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildInfoSection('Evidencia Fotográfica', [
                SizedBox(
                  height: 120,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: reporte.imagenes!.length,
                    itemBuilder: (context, index) {
                      return Container(
                        margin: const EdgeInsets.only(right: 8),
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: AppColors.surface,
                        ),
                        child: const Icon(
                          Icons.image,
                          size: 40,
                          color: AppColors.textSecondary,
                        ),
                      );
                    },
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 24),
            _buildSyncInfo(),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _getStatusColor().withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _getStatusColor().withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _getStatusIcon(),
            color: _getStatusColor(),
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getStatusText(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _getStatusColor(),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  reporte.sincronizado
                      ? 'Reporte sincronizado con el servidor'
                      : 'Pendiente de sincronización',
                  style: TextStyle(
                    fontSize: 12,
                    color: _getStatusColor().withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Información de Sincronización',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            Icons.cloud,
            'Estado',
            reporte.sincronizado ? 'Sincronizado' : 'Pendiente',
          ),
          _buildInfoRow(
            Icons.refresh,
            'Intentos',
            reporte.intentosSync.toString(),
          ),
          if (reporte.ultimoError != null)
            _buildInfoRow(
              Icons.error_outline,
              'Último error',
              reporte.ultimoError!,
            ),
          _buildInfoRow(
            Icons.access_time,
            'Creado',
            _formatDate(reporte.fechaCreacion),
          ),
          if (reporte.fechaModificacion != null)
            _buildInfoRow(
              Icons.update,
              'Modificado',
              _formatDate(reporte.fechaModificacion!),
            ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    if (reporte.sincronizado) return AppColors.completed;
    if (reporte.intentosSync >= 3) return AppColors.error;
    return AppColors.pending;
  }

  IconData _getStatusIcon() {
    if (reporte.sincronizado) return Icons.cloud_done;
    if (reporte.intentosSync >= 3) return Icons.cloud_off;
    return Icons.cloud_upload;
  }

  String _getStatusText() {
    if (reporte.sincronizado) return 'Sincronizado';
    if (reporte.intentosSync >= 3) return 'Error de sincronización';
    return 'Pendiente de sincronización';
  }

  String _getTipoEvento(int id) {
    const tipos = {
      1: 'Inundación',
      2: 'Riada',
      3: 'Deslizamiento',
      4: 'Helada',
      5: 'Granizada',
      6: 'Sequía',
      7: 'Incendios',
      8: 'Otros',
    };
    return tipos[id] ?? 'Desconocido';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Reporte'),
        content: const Text('¿Está seguro de eliminar este reporte?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<ReporteProvider>().eliminarReporte(reporte.idLocal!);
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}
