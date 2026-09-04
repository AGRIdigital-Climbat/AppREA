import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../../models/edan.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import 'ugr_edan_preview_screen.dart';
import 'ugr_route.dart';

class UgrLocalidadesTab extends StatefulWidget {
  const UgrLocalidadesTab({super.key});

  @override
  State<UgrLocalidadesTab> createState() => UgrLocalidadesTabState();
}

class UgrLocalidadesTabState extends State<UgrLocalidadesTab>
    with AutomaticKeepAliveClientMixin {
  bool _cargando = true;
  String? _error;
  List<EdanLocalidad> _localidades = [];
  String _filtroEstado = 'todos';
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargarLocalidades();
  }

  void refresh() {
    _cargarLocalidades();
  }

  int? get _idMunicipio => AuthService.instance.currentToken?.idMunicipio;

  Future<void> _cargarLocalidades() async {
    final municipioId = _idMunicipio;
    if (municipioId == null) {
      if (mounted) setState(() { _cargando = false; _error = 'Municipio no disponible'; });
      return;
    }
    setState(() { _cargando = true; _error = null; });
    try {
      final data = await ApiService.instance.getConsolidarPendientes(
        idMunicipio: municipioId,
        estado: 'revision',
      );
      final localidades = data.map((json) => EdanLocalidad.fromJson(json)).toList();
      if (!mounted) return;
      setState(() {
        _localidades = localidades;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) setState(() { _cargando = false; _error = e.toString(); });
    }
  }

  List<EdanLocalidad> get _filtradas {
    var list = _localidades;
    if (_filtroEstado != 'todos') {
      list = list.where((l) {
        final estado = l.estadoLocalidad;
        return switch (_filtroEstado) {
          'borrador' => estado == UgrLocalidadEstado.borrador,
          'revision' => estado == UgrLocalidadEstado.enviadoUgr,
          'aprobado' => estado == UgrLocalidadEstado.aprobadoUgr,
          'rechazado' => estado == UgrLocalidadEstado.rechazadoUgr,
          _ => true,
        };
      }).toList();
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((l) =>
          l.nombre.toLowerCase().contains(q) ||
          (l.tipoEventoNombre ?? '').toLowerCase().contains(q)
      ).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final primary = PaletteScope.of(context).primary;

    return Column(
      children: [
        _buildHeader(primary),
        _buildFiltros(primary),
        Expanded(child: _buildContenido()),
      ],
    );
  }

  Widget _buildHeader(Color primary) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Icon(Icons.location_on_outlined, color: primary, size: 22),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Localidades del Municipio',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          IconButton(
            onPressed: _cargando ? null : _cargarLocalidades,
            icon: _cargando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltros(Color primary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          TextField(
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Buscar localidad o tipo de evento...',
              hintStyle: const TextStyle(color: AppColors.textSecondary),
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
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
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _filtroChip('Todas', 'todos', primary),
                _filtroChip('Pendientes', 'revision', primary),
                _filtroChip('Aprobadas', 'aprobado', primary),
                _filtroChip('Rechazadas', 'rechazado', primary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtroChip(String label, String valor, Color primary) {
    final seleccionado = _filtroEstado == valor;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: TextStyle(fontSize: 11, color: seleccionado ? Colors.white : AppColors.textPrimary)),
        selected: seleccionado,
        onSelected: (_) => setState(() => _filtroEstado = valor),
        selectedColor: primary,
        backgroundColor: AppColors.surface,
        side: BorderSide(color: seleccionado ? primary : AppColors.divider),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildContenido() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text('Error: $_error', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _cargarLocalidades,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }
    final filtradas = _filtradas;
    if (filtradas.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: AppColors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              _query.isNotEmpty ? 'Sin resultados para la búsqueda' : 'No hay localidades pendientes',
              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargarLocalidades,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: filtradas.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _LocalidadCard(localidad: filtradas[index]),
      ),
    );
  }
}

class _LocalidadCard extends StatelessWidget {
  final EdanLocalidad localidad;
  const _LocalidadCard({required this.localidad});

  @override
  Widget build(BuildContext context) {
    final estado = localidad.estadoLocalidad;
    final estadoColor = estado?.color ?? AppColors.textSecondary;
    final estadoLabel = estado?.label ?? 'Desconocido';

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _verDetalle(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      localidad.nombre.isNotEmpty ? localidad.nombre : 'Sin nombre',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: estadoColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: estadoColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(estadoLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: estadoColor)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (localidad.tipoEventoNombre != null) ...[
                    Icon(Icons.warning_amber_rounded, size: 13, color: AppColors.pending),
                    const SizedBox(width: 4),
                    Text(localidad.tipoEventoNombre!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(width: 12),
                  ],
                  Icon(Icons.people_outline, size: 13, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    '${localidad.totalPoblacionAfectada} personas',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.home_outlined, size: 13, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    '${localidad.totalFamiliasAfectadas} familias',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
              if ((localidad.fechaEvento ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 12, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(localidad.fechaEvento ?? '', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _verDetalle(BuildContext context) {
    final edan = Edan.desdeLocalidad(localidad);
    Navigator.of(context).push(
      ugrRoute(UgrEdanPreviewScreen(edan: edan)),
    );
  }
}
