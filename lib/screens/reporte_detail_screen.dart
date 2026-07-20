import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
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
          if (!reporte.sincronizado)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _showDeleteDialog(context),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _buildDocument(context),
      ),
    );
  }

  Widget _buildDocument(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDocumentHeader(),
          _buildStatusBadges(),
          _buildDocumentBody(context),
          _buildDocumentFooter(),
        ],
      ),
    );
  }

  Widget _buildDocumentHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(4),
        ),
      ),
      child: Column(
        children: [
          const Text(
            'REPORTE DE EVENTO ADVERSO',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'REA - SINAGER SAT',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.8),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            reporte.fechaEvento,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Color _getSyncStatusColor() {
    if (reporte.sincronizado) return AppColors.completed;
    if (reporte.intentosSync >= 20) return AppColors.error;
    return AppColors.pending;
  }

  IconData _getSyncStatusIcon() {
    if (reporte.sincronizado) return Icons.cloud_done;
    if (reporte.intentosSync >= 20) return Icons.cloud_off;
    return Icons.cloud_upload;
  }

  String _getSyncStatusText() {
    if (reporte.sincronizado) return 'Sincronizado';
    if (reporte.intentosSync >= 20) return 'Error de sincronizacion';
    return 'Pendiente de sincronizacion';
  }

  Color _getReportStatusColor() {
    if (reporte.estadoNombre == null) return AppColors.textSecondary;
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

  IconData _getReportStatusIcon() {
    if (reporte.estadoNombre == null) return Icons.info_outline;
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

  Widget _buildStatusBadges() {
    final syncColor = _getSyncStatusColor();
    final hasReportStatus = reporte.sincronizado && reporte.estadoNombre != null;
    final reportColor = hasReportStatus ? _getReportStatusColor() : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _buildBadge(
            icon: _getSyncStatusIcon(),
            text: _getSyncStatusText(),
            color: syncColor,
          ),
          if (hasReportStatus)
            _buildBadge(
              icon: _getReportStatusIcon(),
              text: reporte.estadoNombre!,
              color: reportColor!,
            ),
        ],
      ),
    );
  }

  Widget _buildBadge({required IconData icon, required String text, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentBody(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDocSectionTitle('UBICACION'),
          const SizedBox(height: 8),
          _buildDocField('Departamento', reporte.departamentoNombre ?? reporte.departamentoId.toString()),
          _buildDocField('Provincia', reporte.provinciaNombre ?? reporte.provinciaId.toString()),
          _buildDocField('Municipio', reporte.municipioNombre ?? reporte.municipioId.toString()),
          _buildDocField('Comunidad', reporte.comunidad),
          const SizedBox(height: 16),
          _buildDocDivider(),
          const SizedBox(height: 16),
          _buildDocSectionTitle('DATOS DEL EVENTO'),
          const SizedBox(height: 8),
          _buildDocField('Fecha', reporte.fechaEvento),
          if (reporte.horaEvento != null)
            _buildDocField('Hora', reporte.horaEvento!),
          _buildDocField('Tipo', _getTipoEvento(reporte.tipoEventoId, context)),
          if (reporte.descripcion != null && reporte.descripcion!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildDocField('Descripcion', reporte.descripcion!),
          ],
          if (reporte.coordenadaLat != null && reporte.coordenadaLon != null) ...[
            const SizedBox(height: 16),
            _buildDocDivider(),
            const SizedBox(height: 16),
            _buildDocSectionTitle('UBICACION GEOGRAFICA'),
            const SizedBox(height: 8),
            _buildDocField('Latitud', reporte.coordenadaLat!.toStringAsFixed(6)),
            _buildDocField('Longitud', reporte.coordenadaLon!.toStringAsFixed(6)),
            const SizedBox(height: 12),
            _buildSatelliteMap(reporte.coordenadaLat!, reporte.coordenadaLon!),
          ],
          if (reporte.imagenes != null && reporte.imagenes!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildDocDivider(),
            const SizedBox(height: 16),
            _buildDocSectionTitle('EVIDENCIA FOTOGRAFICA'),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(reporte.imagenes!.first),
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 200,
                  color: AppColors.surface,
                  child: const Center(
                    child: Text('Error al cargar la imagen',
                      style: TextStyle(color: AppColors.textSecondary)),
                  ),
                ),
              ),
            ),
          ],
          if (reporte.categorias != null && reporte.categorias!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildDocDivider(),
            const SizedBox(height: 16),
            _buildDocSectionTitle('CATEGORIAS DE AFECTACION'),
            const SizedBox(height: 8),
            ...reporte.categorias!.map((c) => Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Text(
                '  - ${_getCategoriaNombre(c, context)}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
            )),
          ],
          const SizedBox(height: 16),
          _buildDocDivider(),
          const SizedBox(height: 16),
          _buildDocSectionTitle('SINCRONIZACION'),
          const SizedBox(height: 8),
          _buildDocField('Estado', _getSyncStatusText()),
          if (reporte.sincronizado && reporte.estadoNombre != null)
            _buildDocField('Progreso', reporte.estadoNombre!),
          _buildDocField('Intentos', reporte.intentosSync.toString()),
          if (reporte.ultimoError != null)
            _buildDocField('Error', reporte.ultimoError!),
          _buildDocField('Creado', DateFormat('dd/MM/yyyy HH:mm').format(reporte.fechaCreacion)),
          if (reporte.fechaModificacion != null)
            _buildDocField('Modificado', DateFormat('dd/MM/yyyy HH:mm').format(reporte.fechaModificacion!)),
        ],
      ),
    );
  }

  Widget _buildDocumentFooter() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
        border: Border(
          top: BorderSide(color: AppColors.divider),
        ),
      ),
      child: Text(
        reporte.sincronizado
            ? 'Reporte registrado en el sistema SINAGER-SAT.'
            : 'Reporte pendiente de sincronizacion con el servidor.',
        style: TextStyle(
          fontSize: 11,
          color: AppColors.textSecondary.withValues(alpha: 0.7),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildDocSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: AppColors.primary,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildDocField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary.withValues(alpha: 0.8),
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocDivider() {
    return Container(
      height: 1,
      color: AppColors.divider,
    );
  }

  String _getTipoEvento(int id, BuildContext context) {
    return context.read<ReporteProvider>().getTipoEventoNombre(id);
  }

  String _getCategoriaNombre(int id, BuildContext context) {
    return context.read<ReporteProvider>().getCategoriaNombre(id);
  }

  Widget _buildSatelliteMap(double lat, double lon) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 180,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(lat, lon),
            initialZoom: 16,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
              userAgentPackageName: 'rea',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(lat, lon),
                  width: 40,
                  height: 40,
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.red,
                    size: 36,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Reporte'),
        content: const Text('¿Esta seguro de eliminar este reporte?'),
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