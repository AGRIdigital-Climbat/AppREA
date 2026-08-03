// Diseño anterior del detalle de reporte UGR (hero con gradiente + tarjetas).
// Guardado a petición para un diseño futuro. NO está en uso.
import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../../models/ugr_models.dart';

class UgrReporteDetalleLegacy extends StatefulWidget {
  final UgrReporte reporte;

  const UgrReporteDetalleLegacy({super.key, required this.reporte});

  @override
  State<UgrReporteDetalleLegacy> createState() =>
      _UgrReporteDetalleLegacyState();
}

class _UgrReporteDetalleLegacyState extends State<UgrReporteDetalleLegacy> {
  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    final reporte = widget.reporte;

    return Scaffold(
      backgroundColor: PaletteScope.of(context).background,
      appBar: AppBar(
        title: const Text('Detalle del reporte'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSummaryCard(primary),
          const SizedBox(height: 16),
          _buildSectionTitle('Información'),
          _buildInfoCard(reporte),
          const SizedBox(height: 16),
          _buildSectionTitle('Ubicación'),
          _buildMapPlaceholder(primary, reporte),
          const SizedBox(height: 16),
          _buildSectionTitle('Fotografías (${reporte.fotos})'),
          _buildMediaRow(reporte.fotos, Icons.photo_outlined, primary),
          const SizedBox(height: 16),
          _buildSectionTitle('Videos (${reporte.videos})'),
          _buildMediaRow(reporte.videos, Icons.videocam_outlined, primary),
          const SizedBox(height: 16),
          _buildSectionTitle('Documentos (${reporte.documentos})'),
          _buildDocumentosList(reporte.documentos),
          const SizedBox(height: 16),
          _buildSectionTitle('Datos adicionales'),
          _buildDataCard(reporte),
          const SizedBox(height: 24),
        ],
      ),
      bottomNavigationBar: _buildActionsBar(primary),
    );
  }

  Widget _buildSummaryCard(Color primary) {
    final reporte = widget.reporte;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, primary.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(reporte.estado.icon, size: 14, color: reporte.estado.color),
                    const SizedBox(width: 6),
                    Text(
                      reporte.estado.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: reporte.estado.color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            reporte.tipoEvento,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SummaryItem(
                  label: 'Fecha',
                  value: _fmtFecha(reporte.fechaEvento),
                ),
              ),
              Expanded(
                child: _SummaryItem(
                  label: 'Comunidad',
                  value: reporte.comunidad,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SummaryItem(
                  label: 'Responsable',
                  value: reporte.responsable,
                ),
              ),
              Expanded(
                child: _SummaryItem(
                  label: 'Coordenadas',
                  value: '${reporte.lat.toStringAsFixed(4)}, ${reporte.lon.toStringAsFixed(4)}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildInfoCard(UgrReporte reporte) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(
        reporte.descripcion,
        style: const TextStyle(
          fontSize: 14,
          height: 1.5,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildMapPlaceholder(Color primary, UgrReporte reporte) {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFE8F0E6),
            Color(0xFFCFE3C8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.location_pin, size: 48, color: primary),
          Positioned(
            bottom: 12,
            child: Text(
              '${reporte.lat.toStringAsFixed(4)}, ${reporte.lon.toStringAsFixed(4)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaRow(int count, IconData icon, Color primary) {
    if (count == 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Sin elementos',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      );
    }
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: primary.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: primary),
          );
        },
      ),
    );
  }

  Widget _buildDocumentosList(int count) {
    if (count == 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Sin documentos',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      );
    }
    return Column(
      children: List.generate(count, (index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              const Icon(Icons.description_outlined,
                  size: 20, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Documento ${index + 1}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const Icon(Icons.open_in_new,
                  size: 16, color: AppColors.textSecondary),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildDataCard(UgrReporte reporte) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          _buildDataRow('Ubicación GPS', '${reporte.lat.toStringAsFixed(4)}, ${reporte.lon.toStringAsFixed(4)}'),
          _buildDataRow('Fecha del evento', _fmtFecha(reporte.fechaEvento)),
          _buildDataRow('Responsable', reporte.responsable),
          _buildDataRow('Municipio', reporte.municipio),
        ],
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsBar(Color primary) {
    final reporte = widget.reporte;
    if (reporte.estado != UgrReporteEstado.pendiente) {
      return SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.surface,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(reporte.estado.icon, size: 18, color: reporte.estado.color),
              const SizedBox(width: 8),
              Text(
                'Reporte ${reporte.estado.label.toLowerCase()}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: reporte.estado.color,
                ),
              ),
            ],
          ),
        ),
      );
    }

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
                onPressed: _confirmarRechazo,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.rechazado,
                  side: const BorderSide(color: AppColors.rechazado),
                ),
                child: const Text('Rechazar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _confirmarReporte,
                style: ElevatedButton.styleFrom(backgroundColor: primary),
                child: const Text('Confirmar'),
              ),
            ),
          ],
        ),
      ),
    );
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
            child: const Text('Sí'),
          ),
        ],
      ),
    );
    if (crearEdan == null || !mounted) return;

    setState(() => widget.reporte.estado = UgrReporteEstado.confirmado);

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          crearEdan
              ? 'Reporte confirmado. EDAN creado (diseño).'
              : 'Reporte confirmado.',
        ),
        backgroundColor: AppColors.aprobado,
      ),
    );
    Navigator.of(context).pop();
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

    setState(() => widget.reporte.estado = UgrReporteEstado.rechazado);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reporte rechazado.'),
        backgroundColor: AppColors.rechazado,
      ),
    );
    Navigator.of(context).pop();
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

String _fmtFecha(DateTime dt) {
  final day = dt.day.toString().padLeft(2, '0');
  final month = dt.month.toString().padLeft(2, '0');
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  return '$day/$month/${dt.year} $hour:$minute';
}
