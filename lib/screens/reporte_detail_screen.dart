import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../config/api_config.dart';
import '../config/theme.dart';
import '../models/reporte.dart';
import '../models/reporte_offline.dart';
import '../models/ugr_models.dart';
import '../providers/reporte_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/reporte_documento.dart';
import 'reporte_detalle_data.dart';
import 'reporte_form_screen.dart';
import 'role_screens/ugr/ugr_edan_form_screen.dart';
import 'role_screens/ugr/ugr_evento.dart';

class ReporteDetailScreen extends StatefulWidget {
  final ReporteOffline? reporte;
  final Reporte? reporteServer;
  final UgrReporte? reporteUgr;

  const ReporteDetailScreen({super.key, required this.reporte})
      : reporteServer = null,
        reporteUgr = null;

  const ReporteDetailScreen.server({super.key, required Reporte reporte})
      : reporte = null,
        reporteServer = reporte,
        reporteUgr = null;

  const ReporteDetailScreen.ugr({super.key, required UgrReporte reporte})
      : reporte = null,
        reporteServer = null,
        reporteUgr = reporte;

  @override
  State<ReporteDetailScreen> createState() => _ReporteDetailScreenState();
}

class _ReporteDetailScreenState extends State<ReporteDetailScreen> {
  bool _cambiandoEstado = false;

  @override
  void initState() {
    super.initState();
    // Cambio automático de estado a "En revisión" cuando es UGR y está "Enviado"
    if (widget.reporteUgr != null && widget.reporteUgr!.estado == UgrReporteEstado.enviado) {
      _cambiarEstadoAutomatico();
    }
  }

  Future<void> _cambiarEstadoAutomatico() async {
    final reporte = widget.reporteUgr!;
    final idServer = reporte.idReporte;
    if (idServer == null) return;

    setState(() => _cambiandoEstado = true);
    try {
      await ApiService.instance.cambiarEstadoReporte(idServer, 2); // 2 = En revisión
      if (mounted) {
        setState(() {
          reporte.idEstado = 2;
          reporte.estado = UgrReporteEstado.enRevision;
        });
      }
    } catch (e) {
      debugPrint('Error al cambiar estado automáticamente: $e');
    } finally {
      if (mounted) {
        setState(() => _cambiandoEstado = false);
      }
    }
  }

  ReporteDetalle _buildDetalle(BuildContext context) {
    if (widget.reporteServer != null) {
      return ReporteDetalle.fromServer(widget.reporteServer!);
    }
    if (widget.reporteUgr != null) {
      return ReporteDetalle.fromUgr(widget.reporteUgr!);
    }
    return ReporteDetalle.fromOffline(widget.reporte!, context);
  }

  bool get _esUgr => widget.reporteUgr != null;

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
      bottomNavigationBar: _esUgr ? _buildUgrActionsBar(context) : null,
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
        return 'Fecha del evento: ${detalle.fechaEvento}';
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
        contenido: detalle.categoriaNombres.isNotEmpty
            ? _buildCategorias(detalle.categoriaNombres)
            : null,
      ),
      ReporteDocSeccion(
        titulo: 'UBICACION',
        campos: [
          if (!esUgr) ...[
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
          ] else
            ReporteDocCampo('Municipio', detalle.municipioNombre ?? ''),
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

    if (esUgr) {
      secciones.add(ReporteDocSeccion(
        titulo: 'EVIDENCIA',
        campos: [
          ReporteDocCampo('Fotografias', '${detalle.fotos}'),
          ReporteDocCampo('Videos', '${detalle.videos}'),
          ReporteDocCampo('Documentos', '${detalle.documentos}'),
        ],
      ));
    } else if (detalle.fotoLocalPath != null ||
        detalle.fotoServerPath != null) {
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

  Widget _buildFotoEvidencia(ReporteDetalle detalle) {
    if (detalle.fotoServerPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          '${ApiConfig.baseUrl}/upload/descargar/${Uri.encodeComponent(detalle.fotoServerPath!)}',
          headers: {
            'Authorization':
                'Bearer ${AuthService.instance.currentToken?.accessToken ?? ''}',
          },
          width: double.infinity,
          height: 200,
          cacheWidth: 800,
          fit: BoxFit.cover,
          errorBuilder: (context, url, error) => Container(
            width: double.infinity,
            height: 200,
            color: AppColors.background,
            child: const Center(
              child: Icon(Icons.broken_image,
                  size: 48, color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        File(detalle.fotoLocalPath!),
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
    switch (estado.toLowerCase()) {
      case 'enviado':
        return AppColors.enviado;
      case 'en revisión':
        return AppColors.enRevision;
      case 'aprobado':
        return AppColors.aprobado;
      case 'rechazado':
        return AppColors.rechazado;
      case 'cerrado':
        return AppColors.cerrado;
      case 'pendiente':
        return AppColors.pending;
      case 'confirmado':
        return AppColors.aprobado;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _getReportStatusIcon(String estado) {
    switch (estado.toLowerCase()) {
      case 'enviado':
        return Icons.send;
      case 'en revisión':
        return Icons.visibility;
      case 'aprobado':
        return Icons.check_circle;
      case 'rechazado':
        return Icons.cancel;
      case 'cerrado':
        return Icons.lock;
      case 'pendiente':
        return Icons.schedule;
      case 'confirmado':
        return Icons.check_circle;
      default:
        return Icons.info_outline;
    }
  }

  String _fmtFechaReporte(String fecha) {
    try {
      final dt = DateTime.parse(fecha);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return fecha;
    }
  }

  Widget _buildUgrActionsBar(BuildContext context) {
    final reporte = widget.reporteUgr!;
    final primary = PaletteScope.of(context).primary;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(16),
        color: AppColors.surface,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(reporte.estado.icon, size: 16, color: reporte.estado.color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          reporte.estado.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: reporte.estado.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    reporte.estado.descripcion,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (reporte.estado != UgrReporteEstado.cerrado)
              ElevatedButton.icon(
                onPressed: _cambiandoEstado ? null : _mostrarSelectorEstado,
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Cambiar estado'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _mostrarSelectorEstado() async {
    final reporte = widget.reporteUgr!;
    final idServer = reporte.idReporte;
    if (idServer == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reporte sin ID del servidor'),
            backgroundColor: AppColors.rechazado,
          ),
        );
      }
      return;
    }

    final estadoSeleccionado = await showDialog<UgrReporteEstado>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar estado del reporte'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Seleccione el nuevo estado:',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            ...UgrReporteEstado.values
                .where((e) => e != UgrReporteEstado.enviado && e != reporte.estado)
                .map((estado) => ListTile(
                      leading: Icon(estado.icon, color: estado.color),
                      title: Text(estado.label),
                      subtitle: Text(
                        estado.descripcion,
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                      onTap: () => Navigator.of(ctx).pop(estado),
                    )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (estadoSeleccionado == null || !mounted) return;

    setState(() => _cambiandoEstado = true);
    try {
      await ApiService.instance.cambiarEstadoReporte(idServer, estadoSeleccionado.id);
      if (mounted) {
        setState(() {
          reporte.idEstado = estadoSeleccionado.id;
          reporte.estado = estadoSeleccionado;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Estado cambiado a "${estadoSeleccionado.label}"'),
            backgroundColor: AppColors.aprobado,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cambiar estado: $e'),
            backgroundColor: AppColors.rechazado,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _cambiandoEstado = false);
      }
    }
  }

  Future<void> _confirmarReporte() async {
    final crearEdan = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar reporte'),
        content: const Text('¿Desea crear un EDAN a partir de este reporte?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Más tarde'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sí, crear EDAN'),
          ),
        ],
      ),
    );
    if (crearEdan == null || !mounted) return;

    final reporte = widget.reporteUgr!;
    final idServer = reporte.idReporte;

    if (idServer == null) {
      setState(() => reporte.estado = UgrReporteEstado.aprobado);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reporte confirmado.'),
          backgroundColor: AppColors.aprobado,
        ),
      );
      _navegarACrearEdan(reporte);
      return;
    }

    setState(() => _cambiandoEstado = true);
    try {
      await ApiService.instance.cambiarEstadoReporte(idServer, 3); // 3 = Aprobado para EDAN
      if (!mounted) return;
      setState(() {
        reporte.idEstado = 3;
        reporte.estado = UgrReporteEstado.aprobado;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reporte confirmado. Creando EDAN...'),
          backgroundColor: AppColors.aprobado,
        ),
      );
      Navigator.of(context).pop();
      _navegarACrearEdan(reporte);
    } catch (_) {
      if (!mounted) return;
      setState(() => _cambiandoEstado = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo confirmar el reporte.'),
          backgroundColor: AppColors.rechazado,
        ),
      );
    }
  }

  void _navegarACrearEdan(UgrReporte reporte) async {
    // Navegar al formulario de EDAN con datos pre-llenados
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UgrEdanFormScreen.desdeReporte(reporte: reporte),
      ),
    );
    // Regresar a la pantalla anterior después de crear EDAN
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _confirmarRechazo() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar reporte'),
        content: const Text('¿Está seguro de rechazar este reporte?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rechazado),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    final reporte = widget.reporteUgr!;
    final idServer = reporte.idReporte;

    if (idServer == null) {
      setState(() => reporte.estado = UgrReporteEstado.rechazado);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reporte rechazado.'),
          backgroundColor: AppColors.rechazado,
        ),
      );
      Navigator.of(context).pop();
      return;
    }

    setState(() => _cambiandoEstado = true);
    try {
      await ApiService.instance.cambiarEstadoReporte(idServer, 4);
      if (!mounted) return;
      setState(() => reporte.estado = UgrReporteEstado.rechazado);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reporte rechazado.'),
          backgroundColor: AppColors.rechazado,
        ),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _cambiandoEstado = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo rechazar el reporte.'),
          backgroundColor: AppColors.rechazado,
        ),
      );
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
