import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../../models/ugr_models.dart';
import '../../../services/database_helper.dart';
import 'ugr_edan_preview_screen.dart';
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

class _UgrGlobalSearchSheet extends StatefulWidget {
  const _UgrGlobalSearchSheet();

  @override
  State<_UgrGlobalSearchSheet> createState() => _UgrGlobalSearchSheetState();
}

class _UgrGlobalSearchSheetState extends State<_UgrGlobalSearchSheet> {
  final _controller = TextEditingController();
  late final List<UgrEdan> _edanes = [];
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
                hintText: 'Código EDAN, localidad o municipio...',
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
    final edanes = _edanesFiltrados;

    if (_query.trim().isEmpty || edanes.isEmpty) {
      return const Center(
        child: Text(
          'Escriba para buscar EDAN',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (edanes.isNotEmpty) ...[
          const _ResultHeader('EDAN'),
          ...edanes.map((e) => _buildEdanRow(e, primary)),
        ],
      ],
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
      onTap: () async {
        Navigator.of(context).pop();
        final edanBd = await DatabaseHelper.instance
            .getEdanByIdLocal(edan.idLocal ?? 0);
        if (edanBd == null || !mounted) return;
        Navigator.of(context).push(
          ugrRoute(
            UgrEdanPreviewScreen(edan: edanBd),
          ),
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
