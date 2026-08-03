import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../../models/ugr_models.dart';

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
              Tab(text: 'Secciones'),
              Tab(text: 'Historial'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildSeccionesTab(primary),
            _buildHistorialTab(),
          ],
        ),
        bottomNavigationBar: _buildActionsBar(primary),
      ),
    );
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

  Widget _buildHistorialTab() {
    final edan = widget.edan;
    if (edan.historial.isEmpty) {
      return const Center(
        child: Text(
          'Sin historial',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: edan.historial.length,
      itemBuilder: (context, index) {
        final evento = edan.historial[index];
        final isLast = index == edan.historial.length - 1;
        return _buildTimelineItem(evento, isLast);
      },
    );
  }

  Widget _buildTimelineItem(UgrHistorialEvento evento, bool isLast) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: evento.color,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(evento.icon, size: 16, color: Colors.white),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: evento.color.withValues(alpha: 0.3),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    evento.titulo,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${evento.fecha} · ${evento.usuario}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
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
