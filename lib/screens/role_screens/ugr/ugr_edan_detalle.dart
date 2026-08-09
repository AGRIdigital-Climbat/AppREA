import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:latlong2/latlong.dart';
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
        titulo: 'Evaluación de Daños y Análisis de Necesidades',
        subtitulo: edan.tipoEvento,
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
            ],
            contenido: edan.lat != 0.0 && edan.lon != 0.0
                ? _buildMiniMapa()
                : null,
          ),
          ReporteDocSeccion(
            titulo: 'RESPONSABLE',
            campos: [
              ReporteDocCampo('Nombre', edan.responsable.isNotEmpty ? edan.responsable : 'No registrado'),
              ReporteDocCampo('Cargo', edan.responsableRol.isNotEmpty ? edan.responsableRol : 'No registrado'),
            ],
            contenido: edan.responsableCelular.isNotEmpty
                ? _buildContactActions()
                : null,
          ),
          ReporteDocSeccion(
            titulo: 'DESCRIPCIÓN',
            campos: [
              ReporteDocCampo('Resumen', edan.descripcion),
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

  Widget _buildMiniMapa() {
    final edan = widget.edan;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      height: 180,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(edan.lat, edan.lon),
            initialZoom: 13.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.climbat.edan',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(edan.lat, edan.lon),
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
      child: Row(
        children: [
          const Text(
            'Contactar:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.call, size: 20),
            onPressed: () => _launchUrl('tel:$celular'),
            tooltip: 'Llamar',
            color: AppColors.primary,
          ),
          IconButton(
            icon: const Icon(Icons.message, size: 20),
            onPressed: () => _launchWhatsapp(),
            tooltip: 'WhatsApp',
            color: Colors.green.shade600,
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
    final observado = edan.estado == UgrEdanEstado.observado;
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
              observado
                  ? 'EDAN observado por la autoridad municipal. Corrija las observaciones y vuelva a enviar.'
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
    final puedeFirmar =
        edan.estado == UgrEdanEstado.borrador || edan.estado == UgrEdanEstado.enEdicion;
    final puedeEnviar = edan.estado == UgrEdanEstado.firmado;

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
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Cambios guardados (diseño).'),
                      backgroundColor: AppColors.aprobado,
                    ),
                  );
                },
                child: const Text('Guardar'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: puedeFirmar ? _firmar : null,
                child: const Text('Firmar'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: puedeEnviar ? _enviar : null,
                style: ElevatedButton.styleFrom(backgroundColor: primary),
                child: const Text('Enviar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _firmar() {
    setState(() => widget.edan.estado = UgrEdanEstado.firmado);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('EDAN firmado (diseño).'),
        backgroundColor: AppColors.enRevision,
      ),
    );
  }

  void _enviar() {
    setState(() => widget.edan.estado = UgrEdanEstado.enviado);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('EDAN enviado a revisión (diseño).'),
        backgroundColor: AppColors.enviado,
      ),
    );
  }
}
