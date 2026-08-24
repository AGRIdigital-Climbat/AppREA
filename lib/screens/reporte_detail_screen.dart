import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/api_config.dart';
import '../config/theme.dart';
import '../models/reporte.dart';
import '../models/reporte_offline.dart';
import '../providers/reporte_provider.dart';
import '../services/auth_service.dart';
import '../widgets/reporte_documento.dart';
import 'reporte_detalle_data.dart';
import 'reporte_form_screen.dart';
import 'role_screens/ugr/ugr_evento.dart';

class ReporteDetailScreen extends StatefulWidget {
  final ReporteOffline? reporte;
  final Reporte? reporteServer;

  const ReporteDetailScreen({super.key, required this.reporte})
      : reporteServer = null;

  const ReporteDetailScreen.server({super.key, required Reporte reporte})
      : reporte = null,
        reporteServer = reporte;

  @override
  State<ReporteDetailScreen> createState() => _ReporteDetailScreenState();
}

class _ReporteDetailScreenState extends State<ReporteDetailScreen> {

  @override
  void initState() {
    super.initState();
  }

  ReporteDetalle _buildDetalle(BuildContext context) {
    if (widget.reporteServer != null) {
      return ReporteDetalle.fromServer(widget.reporteServer!);
    }
    return ReporteDetalle.fromOffline(widget.reporte!, context);
  }

  @override
  Widget build(BuildContext context) {
    final detalle = _buildDetalle(context);
    final esOffline = detalle.fuente == ReporteDetalleFuente.offline;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Detalle del Reporte'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (esOffline && !detalle.sincronizado)
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
          if (esOffline && !detalle.sincronizado)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _showDeleteDialog(context),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (esOffline && detalle.esBorrador) ...[
              _buildBorradorBanner(context),
              const SizedBox(height: 12),
            ],
            _buildDocument(context, detalle),
          ],
        ),
      ),
      bottomNavigationBar: null,
    );
  }

  Widget _buildBorradorBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Column(
        children: [
          Icon(Icons.edit_note, color: Colors.orange.shade700, size: 32),
          const SizedBox(height: 8),
          Text(
            'Este reporte es un borrador',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.orange.shade800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Puede editarlo o enviarlo cuando quiera.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.orange.shade700,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReporteFormScreen(reporte: widget.reporte!),
                  ),
                );
              },
              icon: const Icon(Icons.send, size: 18),
              label: const Text('Enviar reporte'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocument(BuildContext context, ReporteDetalle detalle) {
    return ReporteDocumento(
      titulo: 'REPORTE DE EVENTO ADVERSO',
      subtitulo: 'PRE - EDAN',
      fechaCabecera: _fechaCabecera(detalle),
      chip: _buildTipoSello(detalle.tipoEventoNombre),
      cabezalExtra: _buildStatusBadges(detalle),
      secciones: _buildSecciones(detalle),
      footerNota: _footerNota(detalle),
    );
  }

  String _fechaCabecera(ReporteDetalle detalle) {
    switch (detalle.fuente) {
      case ReporteDetalleFuente.offline:
        return 'Fecha de creacion: ${DateFormat('dd/MM/yyyy HH:mm').format(detalle.fechaCreacion)}';
      case ReporteDetalleFuente.server:
        final fecha = detalle.fechaReporte;
        return 'Fecha de reporte: ${fecha != null ? _fmtFechaReporte(fecha) : detalle.fechaEvento}';
      case ReporteDetalleFuente.ugr:
        final fecha = detalle.fechaReporte;
        return 'Fecha de reporte: ${fecha != null ? _fmtFechaReporte(fecha) : detalle.fechaEvento}';
    }
  }

  String _footerNota(ReporteDetalle detalle) {
    if (detalle.fuente == ReporteDetalleFuente.offline) {
      return detalle.esBorrador
          ? 'Este borrador no ha sido enviado al servidor.'
          : detalle.sincronizado
              ? 'Reporte registrado en el sistema SINAGER-SAT.'
              : 'Reporte pendiente de sincronizacion con el servidor.';
    }
    return 'Reporte registrado en el sistema SINAGER-SAT.';
  }

  List<ReporteDocSeccion> _buildSecciones(ReporteDetalle detalle) {
    final esOffline = detalle.fuente == ReporteDetalleFuente.offline;
    final esUgr = detalle.fuente == ReporteDetalleFuente.ugr;

    final secciones = <ReporteDocSeccion>[
      ReporteDocSeccion(
        titulo: 'DATOS DEL EVENTO',
        campos: [
          ReporteDocCampo('Fecha', detalle.fechaEvento),
          if (detalle.horaEvento != null)
            ReporteDocCampo('Hora', detalle.horaEvento!),
          ReporteDocCampo('Tipo', detalle.tipoEventoNombre),
          if (detalle.responsable != null)
            ReporteDocCampo('Reportado por', detalle.responsable!),
          if (detalle.responsableCelular != null &&
              detalle.responsableCelular!.isNotEmpty)
            ReporteDocCampo('Celular', detalle.responsableCelular!),
          if (detalle.responsableRol != null)
            ReporteDocCampo('Cargo', detalle.responsableRol!),
          if (detalle.descripcion != null && detalle.descripcion!.isNotEmpty)
            ReporteDocCampo('Descripcion', detalle.descripcion!),
        ],
        contenido: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (detalle.categoriaNombres.isNotEmpty)
              _buildCategorias(detalle.categoriaNombres),
            if (esUgr &&
                detalle.responsableCelular != null &&
                detalle.responsableCelular!.isNotEmpty) ...[
              if (detalle.categoriaNombres.isNotEmpty) const SizedBox(height: 12),
              _buildContactActions(detalle),
            ],
          ],
        ),
      ),
      ReporteDocSeccion(
        titulo: 'UBICACION',
        campos: [
          ReporteDocCampo(
            'Departamento',
            detalle.departamentoNombre ?? detalle.departamentoId.toString(),
          ),
          ReporteDocCampo(
            'Provincia',
            detalle.provinciaNombre ?? detalle.provinciaId.toString(),
          ),
          ReporteDocCampo(
            'Municipio',
            detalle.municipioNombre ?? detalle.municipioId.toString(),
          ),
          ReporteDocCampo('Comunidad', detalle.comunidad),
          if (detalle.lat != null)
            ReporteDocCampo('Latitud', detalle.lat!.toStringAsFixed(6)),
          if (detalle.lon != null)
            ReporteDocCampo('Longitud', detalle.lon!.toStringAsFixed(6)),
        ],
        contenido: (detalle.lat != null && detalle.lon != null)
            ? ReporteDocMapa(lat: detalle.lat!, lon: detalle.lon!)
            : null,
      ),
    ];

    if (detalle.fotoLocalPath != null || detalle.fotoServerPath != null) {
      secciones.add(ReporteDocSeccion(
        titulo: 'EVIDENCIA FOTOGRAFICA',
        contenido: _buildFotoEvidencia(detalle),
      ));
    }

    secciones.add(esOffline
        ? ReporteDocSeccion(
            titulo: 'SINCRONIZACION',
            campos: [
              ReporteDocCampo('Estado', _getSyncStatusText(detalle)),
              if (detalle.sincronizado && detalle.estadoNombre != null)
                ReporteDocCampo('Progreso', detalle.estadoNombre!),
              ReporteDocCampo('Intentos', detalle.intentosSync.toString()),
              if (detalle.ultimoError != null)
                ReporteDocCampo('Error', detalle.ultimoError!),
              ReporteDocCampo(
                'Creado',
                DateFormat('dd/MM/yyyy HH:mm').format(detalle.fechaCreacion),
              ),
              if (detalle.fechaModificacion != null)
                ReporteDocCampo(
                  'Modificado',
                  DateFormat('dd/MM/yyyy HH:mm').format(detalle.fechaModificacion!),
                ),
            ],
          )
        : ReporteDocSeccion(
            titulo: 'ESTADO',
            campos: [
              ReporteDocCampo('Estado', detalle.estadoNombre ?? 'Enviado'),
              if (detalle.fechaReporte != null)
                ReporteDocCampo(
                  'Reportado',
                  _fmtFechaReporte(detalle.fechaReporte!),
                ),
            ],
          ));

    return secciones;
  }

  Widget _buildTipoSello(String nombre) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ugrEventoIcon(nombre), size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            nombre,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorias(List<String> nombres) {
    final primary = PaletteScope.of(context).primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Categorias de afectacion:',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary.withValues(alpha: 0.8),
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: nombres.map((n) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chevron_right, size: 14, color: primary),
                const SizedBox(width: 4),
                Text(
                  n,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          )).toList(),
        ),
      ],
    );
  }

  Widget _buildContactActions(ReporteDetalle detalle) {
    final celular = detalle.responsableCelular!.replaceAll(r'\s', '');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.divider.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.verified_user_outlined,
                    size: 18, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Acciones para verificar el reporte',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Contacte al reportador para verificar la información del evento.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.call, size: 18),
                  label: const Text('Llamar'),
                  onPressed: () => _launchUrl('tel:$celular'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.message, size: 18),
                  label: const Text('WhatsApp'),
                  onPressed: () => _launchWhatsapp(detalle),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir la aplicación'),
            backgroundColor: AppColors.rechazado,
          ),
        );
      }
    }
  }

  Future<void> _launchWhatsapp(ReporteDetalle detalle) async {
    final celular = detalle.responsableCelular!.replaceAll(r'\s', '');
    final mensaje = 'Hola ${detalle.responsable ?? 'reportador'}, soy de UGR. '
        'Le contacto respecto al reporte de evento adverso.';
    final url = 'https://wa.me/591$celular?text=${Uri.encodeComponent(mensaje)}';
    await _launchUrl(url);
  }

  Widget _buildFotoEvidencia(ReporteDetalle detalle) {
    final Widget preview;
    if (detalle.fotoServerPath != null) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          _fotoUrl(detalle.fotoServerPath!),
          headers: _fotoHeaders,
          width: double.infinity,
          height: 200,
          cacheWidth: 800,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _buildFotoErrorPlaceholder(),
        ),
      );
    } else {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(detalle.fotoLocalPath!),
          width: double.infinity,
          height: 200,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _buildFotoErrorPlaceholder(),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _openFotoFullscreen(detalle),
      child: Stack(
        children: [
          preview,
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fullscreen, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'Ver foto',
                    style: TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fotoUrl(String serverPath) =>
      '${ApiConfig.baseUrl}/upload/descargar/${Uri.encodeComponent(serverPath)}';

  Map<String, String> get _fotoHeaders => {
        'Authorization':
            'Bearer ${AuthService.instance.currentToken?.accessToken ?? ''}',
      };

  Widget _buildFotoErrorPlaceholder() {
    return Container(
      width: double.infinity,
      height: 200,
      color: AppColors.background,
      child: const Center(
        child: Icon(Icons.broken_image, size: 48, color: AppColors.textSecondary),
      ),
    );
  }

  void _openFotoFullscreen(ReporteDetalle detalle) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: detalle.fotoServerPath != null
                      ? Image.network(
                          _fotoUrl(detalle.fotoServerPath!),
                          headers: _fotoHeaders,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, progress) =>
                              progress == null
                                  ? child
                                  : const Center(
                                      child: CircularProgressIndicator(
                                        color: Colors.white54,
                                      ),
                                    ),
                          errorBuilder: (context, error, stackTrace) =>
                              _buildFullscreenFotoError(),
                        )
                      : Image.file(
                          File(detalle.fotoLocalPath!),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              _buildFullscreenFotoError(),
                        ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.4),
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.white, size: 28),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullscreenFotoError() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image, size: 64, color: Colors.white54),
          SizedBox(height: 8),
          Text(
            'No se pudo cargar la imagen',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadges(ReporteDetalle detalle) {
    final esOffline = detalle.fuente == ReporteDetalleFuente.offline;
    final badges = <Widget>[
      if (esOffline)
        _buildBadge(
          icon: _getSyncStatusIcon(detalle),
          text: _getSyncStatusText(detalle),
          color: _getSyncStatusColor(detalle),
        ),
      if (detalle.estadoNombre != null)
        _buildBadge(
          icon: _getReportStatusIcon(detalle.estadoNombre!),
          text: detalle.estadoNombre!,
          color: _getReportStatusColor(detalle.estadoNombre!),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: badges,
      ),
    );
  }

  Widget _buildBadge({
    required IconData icon,
    required String text,
    required Color color,
  }) {
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

  Color _getSyncStatusColor(ReporteDetalle detalle) {
    if (detalle.sincronizado) return AppColors.completed;
    if (detalle.intentosSync >= 20) return AppColors.error;
    return AppColors.pending;
  }

  IconData _getSyncStatusIcon(ReporteDetalle detalle) {
    if (detalle.sincronizado) return Icons.cloud_done;
    if (detalle.intentosSync >= 20) return Icons.cloud_off;
    return Icons.cloud_upload;
  }

  String _getSyncStatusText(ReporteDetalle detalle) {
    if (detalle.sincronizado) return 'Sincronizado';
    if (detalle.intentosSync >= 20) return 'Error de sincronizacion';
    return 'Pendiente de sincronizacion';
  }

  Color _getReportStatusColor(String estado) {
    final e = estado.toLowerCase();
    if (e.contains('rechazad')) return AppColors.rechazado;
    if (e.contains('aprobad')) return AppColors.aprobado;
    if (e.contains('cerrad')) return AppColors.cerrado;
    if (e.contains('revis')) return AppColors.enRevision;
    if (e.contains('enviado')) return AppColors.enviado;
    if (e.contains('pendient')) return AppColors.pending;
    if (e.contains('confirmad')) return AppColors.aprobado;
    return AppColors.textSecondary;
  }

  IconData _getReportStatusIcon(String estado) {
    final e = estado.toLowerCase();
    if (e.contains('rechazad')) return Icons.cancel;
    if (e.contains('aprobad')) return Icons.verified;
    if (e.contains('cerrad')) return Icons.lock;
    if (e.contains('revis')) return Icons.visibility;
    if (e.contains('enviado')) return Icons.send;
    if (e.contains('pendient')) return Icons.schedule;
    if (e.contains('confirmad')) return Icons.check_circle;
    return Icons.info_outline;
  }

  String _fmtFechaReporte(String fecha) {
    try {
      final dt = DateTime.parse(fecha);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return fecha;
    }
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
              context.read<ReporteProvider>().eliminarReporte(widget.reporte!.idLocal!);
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
