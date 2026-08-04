import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../../models/ugr_models.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_helper.dart';
import 'ugr_edan_detalle.dart';
import 'ugr_evento.dart';
import 'ugr_route.dart';

class UgrEdanTab extends StatefulWidget {
  const UgrEdanTab({super.key});

  @override
  State<UgrEdanTab> createState() => UgrEdanTabState();
}

class UgrEdanTabState extends State<UgrEdanTab> {
  List<UgrEdan> _edanes = [];
  bool _cargando = true;
  UgrEdanEstado? _filtro;
  String _query = '';

  int get edanesCount => _edanes.length;

  @override
  void initState() {
    super.initState();
    _cargarEdanes();
  }

  Future<void> _cargarEdanes() async {
    final userId = AuthService.instance.userId;
    if (userId == null) {
      if (mounted) setState(() => _cargando = false);
      return;
    }
    try {
      final edanes = await DatabaseHelper.instance.getEdans(userId);
      if (!mounted) return;
      setState(() {
        _edanes = edanes
            .map((e) => UgrEdan.fromEdan(
                  e,
                  municipioNombre: e.municipioNombre ?? '',
                  usuarioNombre: AuthService.instance.userName,
                ))
            .toList();
        _cargando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void addEdan(UgrEdan edan) {
    setState(() => _edanes.insert(0, edan));
  }

  List<UgrEdan> get _filtered {
    var list = _edanes;
    if (_filtro != null) {
      list = list.where((e) => e.estado == _filtro).toList();
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((e) =>
              e.codigo.toLowerCase().contains(q) ||
              e.municipio.toLowerCase().contains(q) ||
              e.comunidad.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return Column(
      children: [
        _buildFilterBar(primary),
        _buildSearchField(primary),
        Expanded(
          child: _buildList(primary),
        ),
      ],
    );
  }

  Widget _buildFilterBar(Color primary) {
    const estados = <UgrEdanEstado?>[
      null,
      UgrEdanEstado.borrador,
      UgrEdanEstado.enEdicion,
      UgrEdanEstado.firmado,
      UgrEdanEstado.enviado,
      UgrEdanEstado.enRevision,
      UgrEdanEstado.observado,
      UgrEdanEstado.aprobado,
    ];

    return Container(
      color: AppColors.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: estados.map((estado) {
            final isSelected = _filtro == estado;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(
                  estado == null ? 'Todos' : estado.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                  ),
                ),
                selected: isSelected,
                onSelected: (_) => setState(() => _filtro = estado),
                selectedColor: primary,
                backgroundColor: AppColors.surface,
                showCheckmark: false,
                side: BorderSide(
                  color: isSelected ? primary : AppColors.divider,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSearchField(Color primary) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      color: AppColors.surface,
      child: TextField(
        onChanged: (value) => setState(() => _query = value),
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Buscar código, municipio o comunidad...',
          prefixIcon: const Icon(Icons.search, size: 20),
          isDense: true,
          filled: true,
          fillColor: PaletteScope.of(context).background,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: primary, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildList(Color primary) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final list = _filtered;
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.assignment_outlined,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              list.isEmpty && _query.isNotEmpty
                  ? 'Sin resultados para la búsqueda'
                  : 'No hay EDAN con este filtro',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final edan = list[index];
        return _UgrEdanCard(
          edan: edan,
          onTap: () async {
            await Navigator.of(context)
                .push(ugrRoute(UgrEdanDetalle(edan: edan)));
            if (mounted) setState(() {});
          },
        );
      },
    );
  }
}

class _UgrEdanCard extends StatelessWidget {
  final UgrEdan edan;
  final VoidCallback onTap;

  const _UgrEdanCard({required this.edan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: ugrEventoColor(edan.tipoEvento, primary)
                    .withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                ugrEventoIcon(edan.tipoEvento),
                size: 22,
                color: ugrEventoColor(edan.tipoEvento, primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          edan.codigo,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        edan.tiempoRelativo,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${edan.tipoEvento} · ${edan.comunidad}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${edan.seccionesCompletadas} de ${edan.seccionesTotal} secciones',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: edan.estado.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: edan.estado.color.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(edan.estado.icon, size: 13, color: edan.estado.color),
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
            ),
          ],
        ),
      ),
    );
  }
}
