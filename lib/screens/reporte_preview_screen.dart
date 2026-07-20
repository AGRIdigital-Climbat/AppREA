import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/reporte_provider.dart';
import '../providers/connectivity_provider.dart';
import '../models/reporte_offline.dart';
import '../widgets/custom_button.dart';

class ReportePreviewScreen extends StatelessWidget {
  final int departamentoId;
  final int provinciaId;
  final int municipioId;
  final String comunidad;
  final String departamentoNombre;
  final String provinciaNombre;
  final String municipioNombre;
  final String fechaEvento;
  final String fechaEventoDisplay;
  final String horaEvento;
  final int tipoEventoId;
  final String descripcion;
  final List<String> imagenes;
  final List<int> categorias;
  final double? latitud;
  final double? longitud;
  final DateTime fechaCreacion;

  ReportePreviewScreen({
    super.key,
    required this.departamentoId,
    required this.provinciaId,
    required this.municipioId,
    required this.comunidad,
    required this.departamentoNombre,
    required this.provinciaNombre,
    required this.municipioNombre,
    required this.fechaEvento,
    required this.fechaEventoDisplay,
    required this.horaEvento,
    required this.tipoEventoId,
    required this.descripcion,
    required this.imagenes,
    required this.categorias,
    this.latitud,
    this.longitud,
    DateTime? fechaCreacion,
  }) : fechaCreacion = fechaCreacion ?? DateTime.now();

  String _getTipoEvento(int id, ReporteProvider rp) {
    return rp.getTipoEventoNombre(id);
  }

  String _getCategoriaNombre(int id, ReporteProvider rp) {
    return rp.getCategoriaNombre(id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Vista Previa del Reporte'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildDocument(context),
            const SizedBox(height: 20),
            CustomButton(
              text: 'Confirmar y Enviar',
              onPressed: () => _showConfirmDialog(context),
              icon: Icons.send,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Volver y editar'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
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
            fechaEventoDisplay,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentBody(BuildContext context) {
    final rp = context.read<ReporteProvider>();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDocSectionTitle('UBICACION'),
          const SizedBox(height: 8),
          _buildDocField('Departamento', departamentoNombre.isNotEmpty ? departamentoNombre : '--'),
          _buildDocField('Provincia', provinciaNombre.isNotEmpty ? provinciaNombre : '--'),
          _buildDocField('Municipio', municipioNombre.isNotEmpty ? municipioNombre : '--'),
          _buildDocField('Comunidad', comunidad.isNotEmpty ? comunidad : '--'),
          const SizedBox(height: 16),
          _buildDocDivider(),
          const SizedBox(height: 16),
          _buildDocSectionTitle('DATOS DEL EVENTO'),
          const SizedBox(height: 8),
          _buildDocField('Fecha del evento', fechaEventoDisplay),
          _buildDocField('Hora del evento', horaEvento.isNotEmpty ? horaEvento : '--'),
          _buildDocField('Tipo de evento', _getTipoEvento(tipoEventoId, rp)),
          if (descripcion.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildDocField('Descripcion', descripcion),
          ],
          const SizedBox(height: 16),
          _buildDocDivider(),
          const SizedBox(height: 16),
          _buildDocSectionTitle('UBICACION GEOGRAFICA'),
          const SizedBox(height: 8),
          _buildDocField('Latitud', latitud != null ? latitud!.toStringAsFixed(6) : '--'),
          _buildDocField('Longitud', longitud != null ? longitud!.toStringAsFixed(6) : '--'),
          if (latitud != null && longitud != null) ...[
            const SizedBox(height: 12),
            _buildSatelliteMap(latitud!, longitud!),
          ],
          const SizedBox(height: 16),
          _buildDocDivider(),
          const SizedBox(height: 16),
          _buildDocSectionTitle('EVIDENCIA FOTOGRAFICA'),
          const SizedBox(height: 8),
          if (imagenes.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(imagenes.first),
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
            )
          else
            _buildDocField('Fotografia', 'Sin evidencia fotografica'),
          const SizedBox(height: 16),
          _buildDocDivider(),
          const SizedBox(height: 16),
          _buildDocSectionTitle('CATEGORIAS DE AFECTACION'),
          const SizedBox(height: 8),
          if (categorias.isEmpty)
            _buildDocField('Categorias', 'Sin categorias seleccionadas')
          else
            ...categorias.map((c) => Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Text(
                '  - ${_getCategoriaNombre(c, rp)}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
            )),
          const SizedBox(height: 16),
          _buildDocDivider(),
          const SizedBox(height: 16),
          _buildDocSectionTitle('ESTADO'),
          const SizedBox(height: 8),
          _buildDocField('Estado', 'Pendiente'),
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
      child: Column(
        children: [
          Text(
            'Este reporte sera verificado por el equipo SINAGER-SAT.',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Fecha de creacion: ${DateFormat("dd/MM/yyyy HH:mm").format(fechaCreacion)}',
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
        ],
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

  void _showConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: AppColors.pending,
          size: 40,
        ),
        title: const Text(
          'Verificar informacion',
          textAlign: TextAlign.center,
        ),
        content: const Text(
          'Los datos ingresados seran verificados por el equipo de SINAGER-SAT. '
          'Asegurese de que toda la informacion sea correcta antes de enviar.',
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Volver'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _submitReport(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Enviar reporte'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitReport(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    final reporteProvider = context.read<ReporteProvider>();
    final connectivity = context.read<ConnectivityProvider>();

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.primary),
                SizedBox(height: 16),
                Text('Enviando reporte...'),
              ],
            ),
          ),
        ),
      ),
    );

    final reporte = ReporteOffline(
      usuarioId: authProvider.userId!,
      departamentoId: departamentoId,
      provinciaId: provinciaId,
      municipioId: municipioId,
      comunidad: comunidad,
      departamentoNombre: departamentoNombre.isNotEmpty ? departamentoNombre : null,
      provinciaNombre: provinciaNombre.isNotEmpty ? provinciaNombre : null,
      municipioNombre: municipioNombre.isNotEmpty ? municipioNombre : null,
      fechaEvento: fechaEvento,
      horaEvento: horaEvento,
      tipoEventoId: tipoEventoId,
      coordenadaLat: latitud,
      coordenadaLon: longitud,
      descripcion: descripcion,
      categorias: categorias.isNotEmpty ? categorias : null,
      imagenes: imagenes.isNotEmpty ? imagenes : null,
      fechaCreacion: DateTime.now(),
    );

    await reporteProvider.crearReporte(reporte);

    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            connectivity.isConnected
                ? 'Reporte enviado exitosamente'
                : 'Reporte guardado localmente',
          ),
          backgroundColor: AppColors.completed,
        ),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }
}
