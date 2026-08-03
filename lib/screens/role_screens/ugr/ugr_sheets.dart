import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../../models/ugr_models.dart';
import '../../../mocks/ugr_mock_data.dart';
import '../../../screens/reporte_detail_screen.dart';
import 'ugr_edan_detalle.dart';
import 'ugr_evento.dart';
import 'ugr_route.dart';

void showUgrGlobalSearch(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: PaletteScope.of(context).background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => ugrSheetWrap(
      const _UgrGlobalSearchSheet(),
    ),
  );
}

void showUgrNuevoEdan(
  BuildContext context, {
  required ValueChanged<UgrEdan> onGuardar,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: PaletteScope.of(context).background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => ugrSheetWrap(
      _UgrNuevoEdanSheet(onGuardar: onGuardar),
    ),
  );
}

class _UgrGlobalSearchSheet extends StatefulWidget {
  const _UgrGlobalSearchSheet();

  @override
  State<_UgrGlobalSearchSheet> createState() => _UgrGlobalSearchSheetState();
}

class _UgrGlobalSearchSheetState extends State<_UgrGlobalSearchSheet> {
  final _controller = TextEditingController();
  late final List<UgrReporte> _reportes = mockReportes();
  late final List<UgrEdan> _edanes = mockEdanes();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<UgrReporte> get _reportesFiltrados {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _reportes
        .where((r) =>
            r.comunidad.toLowerCase().contains(q) ||
            r.responsable.toLowerCase().contains(q) ||
            r.tipoEvento.toLowerCase().contains(q))
        .toList();
  }

  List<UgrEdan> get _edanesFiltrados {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _edanes
        .where((e) =>
            e.codigo.toLowerCase().contains(q) ||
            e.municipio.toLowerCase().contains(q) ||
            e.comunidad.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    final height = MediaQuery.of(context).size.height * 0.85;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Búsqueda rápida',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Comunidad, responsable o código EDAN...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: primary, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _buildResultados(primary),
          ),
        ],
      ),
    );
  }

  Widget _buildResultados(Color primary) {
    final reportes = _reportesFiltrados;
    final edanes = _edanesFiltrados;

    if (_query.trim().isEmpty || (reportes.isEmpty && edanes.isEmpty)) {
      return const Center(
        child: Text(
          'Escriba para buscar reportes y EDAN',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (reportes.isNotEmpty) ...[
          const _ResultHeader('Reportes'),
          ...reportes.map((r) => _buildReporteRow(r, primary)),
        ],
        if (edanes.isNotEmpty) ...[
          const _ResultHeader('EDAN'),
          ...edanes.map((e) => _buildEdanRow(e, primary)),
        ],
      ],
    );
  }

  Widget _buildReporteRow(UgrReporte reporte, Color primary) {
    return ListTile(
      leading: Icon(ugrEventoIcon(reporte.tipoEvento), color: primary),
      title: Text(
        reporte.tipoEvento,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${reporte.comunidad} · ${reporte.responsable}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Icon(reporte.estado.icon, size: 18, color: reporte.estado.color),
      onTap: () {
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReporteDetailScreen.ugr(reporte: reporte),
          ),
        );
      },
    );
  }

  Widget _buildEdanRow(UgrEdan edan, Color primary) {
    return ListTile(
      leading: Icon(ugrEventoIcon(edan.tipoEvento), color: primary),
      title: Text(
        edan.codigo,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${edan.comunidad} · ${edan.municipio}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Icon(edan.estado.icon, size: 18, color: edan.estado.color),
      onTap: () {
        Navigator.of(context).pop();
        Navigator.of(context).push(
          ugrRoute(UgrEdanDetalle(edan: edan)),
        );
      },
    );
  }
}

class _ResultHeader extends StatelessWidget {
  final String title;

  const _ResultHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _UgrNuevoEdanSheet extends StatefulWidget {
  final ValueChanged<UgrEdan> onGuardar;

  const _UgrNuevoEdanSheet({required this.onGuardar});

  @override
  State<_UgrNuevoEdanSheet> createState() => _UgrNuevoEdanSheetState();
}

class _UgrNuevoEdanSheetState extends State<_UgrNuevoEdanSheet> {
  final _comunidadController = TextEditingController();
  final _municipioController = TextEditingController();
  String? _tipoEvento;

  @override
  void dispose() {
    _comunidadController.dispose();
    _municipioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + viewInsets),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nuevo EDAN',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _comunidadController,
            decoration: const InputDecoration(labelText: 'Comunidad'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _municipioController,
            decoration: const InputDecoration(labelText: 'Municipio'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _tipoEvento,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Tipo de evento'),
            items: mockTiposEvento()
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (value) => setState(() => _tipoEvento = value),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _guardar,
                  style: ElevatedButton.styleFrom(backgroundColor: primary),
                  child: const Text('Crear'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _guardar() {
    final comunidad = _comunidadController.text.trim();
    final municipio = _municipioController.text.trim();
    final tipoEvento = _tipoEvento;
    if (comunidad.isEmpty || municipio.isEmpty || tipoEvento == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complete comunidad, municipio y tipo de evento.'),
          backgroundColor: AppColors.rechazado,
        ),
      );
      return;
    }

    final codigo =
        'EDAN-2026-${(DateTime.now().millisecondsSinceEpoch % 1000).toString().padLeft(3, '0')}';

    final edan = UgrEdan(
      codigo: codigo,
      tipoEvento: tipoEvento,
      comunidad: comunidad,
      municipio: municipio,
      fechaCreacion: DateTime.now(),
      estado: UgrEdanEstado.borrador,
      secciones: mockSeccionesEdan(),
      historial: mockHistorialEdan(UgrEdanEstado.borrador),
    );

    widget.onGuardar(edan);
    Navigator.of(context).pop();
  }
}
