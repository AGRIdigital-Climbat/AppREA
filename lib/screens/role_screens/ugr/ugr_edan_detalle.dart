import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/theme.dart';
import '../../../models/ugr_models.dart';
import '../../../widgets/reporte_documento.dart';

class UgrEdanDetalle extends StatefulWidget {
  final UgrEdan edan;

  const UgrEdanDetalle({super.key, required this.edan});

  @override
  State<UgrEdanDetalle> createState() => _UgrEdanDetalleState();
}

class _UgrEdanDetalleState extends State<UgrEdanDetalle> {
  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    final edan = widget.edan;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: PaletteScope.of(context).background,
        appBar: AppBar(
          title: Text(edan.codigo),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Documento'),
              Tab(text: 'Secciones'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildDocumentoTab(primary),
            _buildSeccionesTab(primary),
          ],
        ),
        bottomNavigationBar: _buildActionsBar(primary),
      ),
    );
  }

  Widget _buildDocumentoTab(Color primary) {
    final edan = widget.edan;
    final fechaFmt = DateFormat('dd/MM/yyyy HH:mm').format(edan.fechaCreacion);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ReporteDocumento(
        titulo: 'EVALUACIÓN DE DAÑOS Y ANÁLISIS DE NECESIDADES',
        subtitulo: 'EDAN - ${edan.tipoEvento}',
        fechaCabecera: fechaFmt,
        icono: Icons.assignment,
        chip: _buildEstadoChip(),
        secciones: [
          ReporteDocSeccion(
            titulo: 'DATOS DEL EDAN',
            campos: [
              ReporteDocCampo('Código', edan.codigo),
              ReporteDocCampo('Tipo de evento', edan.tipoEvento),
              ReporteDocCampo('Fecha de evento', fechaFmt),
            ],
          ),
          ReporteDocSeccion(
            titulo: 'UBICACIÓN',
            campos: [
              ReporteDocCampo('Municipio', edan.municipio),
              ReporteDocCampo('Comunidad', edan.comunidad),
              ReporteDocCampo('Localidades afectadas', '${edan.localidades}'),
              if (edan.lat != 0.0 && edan.lon != 0.0)
                ReporteDocCampo('Latitud', edan.lat.toStringAsFixed(6)),
              if (edan.lat != 0.0 && edan.lon != 0.0)
                ReporteDocCampo('Longitud', edan.lon.toStringAsFixed(6)),
            ],
            contenido: edan.lat != 0.0 && edan.lon != 0.0
                ? ReporteDocMapa(lat: edan.lat, lon: edan.lon)
                : null,
          ),
          ReporteDocSeccion(
            titulo: 'RESPONSABLE DEL EDAN',
            campos: [
              ReporteDocCampo('Nombre', edan.responsable.isNotEmpty ? edan.responsable : 'No registrado'),
              ReporteDocCampo('Cargo', edan.responsableRol.isNotEmpty ? edan.responsableRol : 'No registrado'),
              if (edan.responsableCelular.isNotEmpty)
                ReporteDocCampo('Celular', edan.responsableCelular),
            ],
            contenido: edan.responsableCelular.isNotEmpty
                ? _buildContactActions()
                : null,
          ),
          ReporteDocSeccion(
            titulo: 'DESCRIPTOR DEL IMPACTO',
            campos: [
              ReporteDocCampo('Resumen', edan.descripcion.isNotEmpty ? edan.descripcion : 'Sin descripción'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEstadoChip() {
    final edan = widget.edan;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: edan.estado.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: edan.estado.color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(edan.estado.icon, size: 14, color: edan.estado.color),
          const SizedBox(width: 4),
          Text(
            edan.estado.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: edan.estado.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactActions() {
    final edan = widget.edan;
    final celular = edan.responsableCelular.replaceAll(r'\s', '');
    
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ACCIONES DE CONTROL',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.call, size: 18),
                  label: const Text('Llamar'),
                  onPressed: () => _launchUrl('tel:$celular'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.message, size: 18),
                  label: const Text('WhatsApp'),
                  onPressed: _launchWhatsapp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
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

  Future<void> _launchWhatsapp() async {
    final edan = widget.edan;
    final celular = edan.responsableCelular.replaceAll(r'\s', '');
    final mensaje = 'Hola ${edan.responsable}, soy de UGR. Le contacto respecto al EDAN ${edan.codigo}.';
    final url = 'https://wa.me/591$celular?text=${Uri.encodeComponent(mensaje)}';
    await _launchUrl(url);
  }

  Widget _buildSeccionesTab(Color primary) {
    final edan = widget.edan;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildEstadoBanner(primary),
        const SizedBox(height: 12),
        _buildProgressCard(primary),
        const SizedBox(height: 12),
        ...edan.secciones.map((seccion) => _buildSeccionTile(seccion, primary)),
      ],
    );
  }

  Widget _buildEstadoBanner(Color primary) {
    final edan = widget.edan;
    final rechazado = edan.estado == UgrEdanEstado.rechazado;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: edan.estado.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: edan.estado.color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(edan.estado.icon, size: 20, color: edan.estado.color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              rechazado
                  ? 'EDAN rechazado por la autoridad municipal. Corrija las observaciones y vuelva a enviar.'
                  : 'Estado: ${edan.estado.label}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: edan.estado.color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard(Color primary) {
    final edan = widget.edan;
    final pct = edan.seccionesTotal == 0
        ? 0.0
        : edan.seccionesCompletadas / edan.seccionesTotal;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Progreso del EDAN',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '${edan.seccionesCompletadas} de ${edan.seccionesTotal}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: AppColors.divider,
              valueColor: AlwaysStoppedAnimation<Color>(primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionTile(UgrSeccion seccion, Color primary) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: seccion.completada
              ? AppColors.aprobado.withValues(alpha: 0.4)
              : AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (seccion.completada ? AppColors.aprobado : primary)
                  .withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              seccion.completada ? Icons.check : seccion.icon,
              size: 20,
              color: seccion.completada ? AppColors.aprobado : primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  seccion.nombre,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  seccion.descripcion,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            seccion.completada ? 'Completado' : 'Pendiente',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: seccion.completada ? AppColors.aprobado : AppColors.pending,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsBar(Color primary) {
    final edan = widget.edan;
    final puedeEditar = edan.estado.puedeEditar;
    final puedeEliminar = edan.estado.puedeEliminar;
    final esBorrador = edan.estado == UgrEdanEstado.borrador;
    final esEnviado = edan.estado == UgrEdanEstado.enviado;
    final esRechazado = edan.estado == UgrEdanEstado.rechazado;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.divider.withValues(alpha: 0.6)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Banner de estado
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: edan.estado.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: edan.estado.color.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(edan.estado.icon, size: 16, color: edan.estado.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Estado: ${edan.estado.label}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: edan.estado.color,
                          ),
                        ),
                        Text(
                          edan.estado.descripcion,
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Botones de acción
            Row(
              children: [
                if (puedeEliminar)
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Eliminar'),
                      onPressed: () => _confirmarEliminar(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.rechazado,
                      ),
                    ),
                  ),
                if (puedeEditar && !esBorrador)
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Editar'),
                      onPressed: () => _navegarAEditar(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                      ),
                    ),
                  ),
                if (esBorrador) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _guardarBorrador(context),
                      child: const Text('Guardar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.send, size: 18),
                      label: const Text('Enviar'),
                      onPressed: () => _confirmarEnviar(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
                if (esRechazado)
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Corregir y Re-enviar'),
                      onPressed: () => _navegarAEditar(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                if (esEnviado)
                  const Expanded(
                    child: Text(
                      'Enviado - Pendiente de sincronización',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmarEliminar(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar EDAN'),
        content: const Text('¿Está seguro de eliminar este EDAN? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // TODO: Implementar eliminación de BD y servidor
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('EDAN eliminado correctamente'),
                  backgroundColor: AppColors.rechazado,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.rechazado,
              foregroundColor: Colors.white,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  void _navegarAEditar(BuildContext context) {
    // TODO: Navegar a UgrEdanFormScreen con edanAEditar
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Abriendo editor de EDAN...'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  void _guardarBorrador(BuildContext context) {
    // TODO: Guardar en BD local como borrador
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('EDAN guardado como borrador'),
        backgroundColor: AppColors.aprobado,
      ),
    );
  }

  Future<void> _confirmarEnviar(BuildContext context) async {
    final edan = widget.edan;
    
    // Verificar secciones incompletas
    final incompletas = edan.secciones.where((s) => !s.completada).length;
    
    if (incompletas > 0) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('EDAN Incompleto'),
          content: Text(
            'El EDAN tiene $incompletas secciones incompletas.\n\n'
            'Puede enviarlo ahora y completarlo desde la computadora, '
            'o seguir editando aquí.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Seguir Editando'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Enviar Ahora'),
            ),
          ],
        ),
      );
      
      if (confirmar != true) return;
    }
    
    // TODO: Cambiar estado a "enviado" y sincronizar
    setState(() => edan.estado = UgrEdanEstado.enviado);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('EDAN enviado. Pendiente de sincronización con el servidor.'),
        backgroundColor: AppColors.enviado,
      ),
    );
  }
}
