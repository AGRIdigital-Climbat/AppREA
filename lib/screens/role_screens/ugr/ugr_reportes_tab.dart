import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../../models/ugr_models.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../screens/reporte_detail_screen.dart';
import 'ugr_evento.dart';

class UgrReportesTab extends StatefulWidget {
  const UgrReportesTab({super.key});

  @override
  State<UgrReportesTab> createState() => _UgrReportesTabState();
}

class _UgrReportesTabState extends State<UgrReportesTab> {
  List<UgrReporte> _reportes = [];
  UgrReporteEstado? _filtro;
  String _query = '';
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _cargarReportes();
  }

  Future<void> _cargarReportes() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    final municipioId = AuthService.instance.currentToken?.idMunicipio;
    if (municipioId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final reportes = await ApiService.instance.getReportes(
        idMunicipio: municipioId,
        limit: 50,
      );
      reportes.sort((a, b) {
        final fa = a.fechaReporte ?? '';
        final fb = b.fechaReporte ?? '';
        return fb.compareTo(fa);
      });
      if (mounted) {
        setState(() {
          _reportes = reportes.map(UgrReporte.fromServer).toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  List<UgrReporte> get _filtered {
    var list = _reportes;
    if (_filtro != null) {
      list = list.where((r) => r.estado == _filtro).toList();
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((r) =>
              r.comunidad.toLowerCase().contains(q) ||
              r.responsable.toLowerCase().contains(q) ||
              r.tipoEvento.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: primary),
      );
    }
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 64, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            const Text(
              'No se pudieron cargar los reportes',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _cargarReportes,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(backgroundColor: primary),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        _buildFilterBar(primary),
        _buildSearchField(primary),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _cargarReportes,
            child: _buildList(),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar(Color primary) {
    final filters = <(String, UgrReporteEstado?)>[
      ('Todos', null),
      ('Pendientes', UgrReporteEstado.pendiente),
      ('Confirmados', UgrReporteEstado.confirmado),
      ('Rechazados', UgrReporteEstado.rechazado),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppColors.surface,
      child: Row(
        children: filters.map((f) {
          final (label, value) = f;
          final isSelected = _filtro == value;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: FilterChip(
                label: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                  ),
                ),
                selected: isSelected,
                onSelected: (_) => setState(() => _filtro = value),
                selectedColor: primary,
                backgroundColor: AppColors.surface,
                showCheckmark: false,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                side: BorderSide(
                  color: isSelected ? primary : AppColors.divider,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSearchField(Color primary) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: AppColors.surface,
      child: TextField(
        onChanged: (value) => setState(() => _query = value),
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Buscar comunidad, responsable o evento...',
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

  Widget _buildList() {
    final list = _filtered;
    if (list.isEmpty) {
      final mensaje = _query.trim().isNotEmpty
          ? 'Sin resultados para la búsqueda'
          : _filtro != null
              ? 'No hay reportes con este filtro'
              : 'No hay reportes en su municipio';
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: constraints.maxHeight,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.inbox_outlined,
                      size: 64, color: AppColors.textSecondary),
                  const SizedBox(height: 12),
                  Text(
                    mensaje,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final reporte = list[index];
        return _UgrReporteCard(
          reporte: reporte,
          onTap: () async {
            await Navigator.of(context)
                .push(MaterialPageRoute(
                  builder: (_) => ReporteDetailScreen.ugr(reporte: reporte),
                ));
            if (mounted) setState(() {});
          },
        );
      },
    );
  }
}

class _UgrReporteCard extends StatelessWidget {
  final UgrReporte reporte;
  final VoidCallback onTap;

  const _UgrReporteCard({required this.reporte, required this.onTap});

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
                color: ugrEventoColor(reporte.tipoEvento, primary).withValues(alpha: 0.1),
              ),
              child: Icon(
                ugrEventoIcon(reporte.tipoEvento),
                size: 22,
                color: ugrEventoColor(reporte.tipoEvento, primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reporte.tipoEvento,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${reporte.comunidad} · ${reporte.municipio}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.person_outline,
                          size: 12, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        reporte.responsable,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.schedule,
                          size: 12, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        reporte.tiempoRelativo,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: reporte.estado.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: reporte.estado.color.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(reporte.estado.icon, size: 13, color: reporte.estado.color),
                  const SizedBox(width: 4),
                  Text(
                    reporte.estado.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: reporte.estado.color,
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

