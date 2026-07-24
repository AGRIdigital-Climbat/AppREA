import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import '../config/theme.dart';
import '../config/api_config.dart';
import '../models/reporte.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class MunicipioReportesTab extends StatefulWidget {
  const MunicipioReportesTab({super.key});

  @override
  State<MunicipioReportesTab> createState() => _MunicipioReportesTabState();
}

class _MunicipioReportesTabState extends State<MunicipioReportesTab>
    with AutomaticKeepAliveClientMixin {
  final ApiService _api = ApiService.instance;
  final MapController _mapController = MapController();

  List<Reporte> _reportes = [];
  bool _isLoading = true;
  bool _isOnline = true;
  bool _isMapView = false;
  bool _isSatellite = true;
  String? _selectedDate;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadReportes();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadReportes() async {
    setState(() {
      _isLoading = true;
      _isOnline = true;
    });

    final municipioId = AuthService.instance.currentToken?.idMunicipio;
    if (municipioId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final reportes = await _api.getReportes(
        idMunicipio: municipioId,
        limit: 30,
      );
      reportes.sort((a, b) {
        final fa = a.fechaReporte ?? '';
        final fb = b.fechaReporte ?? '';
        return fb.compareTo(fa);
      });
      if (mounted) {
        setState(() {
          _reportes = reportes;
          _isLoading = false;
          _isOnline = true;
          _initializeSelectedDate();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isOnline = false;
        });
      }
    }
  }

  Map<String, List<Reporte>> _groupByDate(List<Reporte> reportes) {
    final grouped = <String, List<Reporte>>{};
    for (final r in reportes) {
      final key = _dateKeyFromDate(DateTime.parse(r.fechaEvento));
      grouped.putIfAbsent(key, () => []).add(r);
    }
    return grouped;
  }

  String _dateKeyFromDate(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  void _initializeSelectedDate() {
    if (_reportes.isEmpty) return;
    final keys = _getOrderedDateKeys();
    if (keys.isNotEmpty) {
      _selectedDate = keys.first;
    }
  }

  List<String> _getOrderedDateKeys() {
    final grouped = _groupByDate(_reportes);
    final entries = grouped.entries.toList();
    entries.sort((a, b) {
      final dateA = _parseDateKey(a.key);
      final dateB = _parseDateKey(b.key);
      return dateB.compareTo(dateA);
    });
    return entries.map((e) => e.key).toList();
  }

  DateTime _parseDateKey(String key) {
    final parts = key.split('/');
    return DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
  }

  List<Reporte> get _filteredReportes {
    if (_selectedDate == null) return _reportes;
    return _reportes.where((r) {
      final fecha = DateTime.parse(r.fechaEvento);
      return _dateKeyFromDate(fecha) == _selectedDate;
    }).toList();
  }

  IconData _getEventIcon(String? tipo) {
    switch (tipo?.toLowerCase()) {
      case 'incendios':
        return Icons.local_fire_department;
      case 'inundación':
      case 'inundacion':
        return Icons.flood;
      case 'riada':
        return Icons.waves;
      case 'deslizamiento':
        return Icons.terrain;
      case 'helada':
        return Icons.ac_unit;
      case 'granizada':
        return Icons.grain;
      case 'sequía':
      case 'sequia':
        return Icons.wb_sunny;
      case 'viento fuerte':
        return Icons.air;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  Color _getEstadoColor(int? idEstado) {
    switch (idEstado) {
      case 1:
        return AppColors.pending;
      case 2:
        return AppColors.inProgress;
      case 3:
        return AppColors.completed;
      case 4:
        return AppColors.closed;
      case 5:
        return AppColors.rejected;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (!_isOnline) {
      return _buildOfflineView();
    }

    return Column(
      children: [
        _buildToggleBar(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _reportes.isEmpty
                  ? _buildEmptyView()
                  : _isMapView
                      ? _buildMapView()
                      : _buildListView(),
        ),
      ],
    );
  }

  Widget _buildOfflineView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 64,
              color: AppColors.textSecondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            const Text(
              'Sin conexión a internet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Los reportes del municipio requieren conexión a internet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _loadReportes,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_city_rounded,
              size: 64,
              color: AppColors.textSecondary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            const Text(
              'Sin reportes en el municipio',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Aún no se han registrado reportes en tu municipio',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.list_rounded),
                  label: Text('Lista'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.map_rounded),
                  label: Text('Mapa'),
                ),
              ],
              selected: {_isMapView},
              onSelectionChanged: (selected) {
                setState(() => _isMapView = selected.first);
              },
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return AppColors.primary;
                  }
                  return AppColors.surface;
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Colors.white;
                  }
                  return AppColors.textPrimary;
                }),
                side: WidgetStateProperty.all(
                  const BorderSide(color: AppColors.divider),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildRefreshButton(),
        ],
      ),
    );
  }

  Widget _buildListView() {
    final grouped = _groupByDate(_reportes);
    final dateKeys = _getOrderedDateKeys();

    return RefreshIndicator(
      onRefresh: _loadReportes,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: dateKeys.length,
        itemBuilder: (context, index) {
          final dateKey = dateKeys[index];
          final reportes = grouped[dateKey]!;
          return _buildDateGroup(dateKey, reportes);
        },
      ),
    );
  }

  Widget _buildDateGroup(String dateKey, List<Reporte> reportes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppColors.background,
          child: Row(
            children: [
              const Icon(Icons.calendar_today, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                dateKey,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${reportes.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        ...reportes.map((r) => _buildReportTile(r)),
      ],
    );
  }

  Widget _buildReportTile(Reporte r) {
    final estadoColor = _getEstadoColor(r.idEstado);
    final tipoNombre = r.tipoEvento?.nombre ?? 'Sin tipo';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.divider, width: 0.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showReportBottomSheet(r),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _getEventIcon(r.tipoEvento?.nombre),
                      size: 20,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tipoNombre,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: estadoColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        r.estado?.nombre ?? 'Enviado',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: estadoColor,
                        ),
                      ),
                    ),
                  ],
                ),
                if (r.descripcion != null && r.descripcion!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    r.descripcion!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      r.comunidad,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (r.horaEvento != null) ...[
                      const SizedBox(width: 12),
                      const Icon(Icons.access_time, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        r.horaEvento!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapView() {
    final filtered = _filteredReportes;
    final markers = filtered
        .where((r) =>
            r.coordenadaLat != null &&
            r.coordenadaLon != null &&
            !r.coordenadaLat!.isNaN &&
            !r.coordenadaLon!.isNaN &&
            !r.coordenadaLat!.isInfinite &&
            !r.coordenadaLon!.isInfinite)
        .map((r) => _buildMarker(r))
        .toList();

    final hasCoordinates = markers.isNotEmpty;

    LatLng center;
    if (hasCoordinates) {
      final validLat = filtered
          .where((r) => r.coordenadaLat != null && !r.coordenadaLat!.isNaN && !r.coordenadaLat!.isInfinite)
          .map((r) => r.coordenadaLat!);
      final validLon = filtered
          .where((r) => r.coordenadaLon != null && !r.coordenadaLon!.isNaN && !r.coordenadaLon!.isInfinite)
          .map((r) => r.coordenadaLon!);
      if (validLat.isNotEmpty && validLon.isNotEmpty) {
        center = LatLng(
          validLat.reduce((a, b) => a + b) / validLat.length,
          validLon.reduce((a, b) => a + b) / validLon.length,
        );
      } else {
        center = const LatLng(-16.5, -68.1);
      }
    } else {
      center = const LatLng(-16.5, -68.1);
    }

    final satelliteTileLayer = TileLayer(
      urlTemplate:
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      userAgentPackageName: 'com.example.app',
      keepBuffer: 4,
      tileDimension: 256,
      maxZoom: 18,
    );

    final streetTileLayer = TileLayer(
      urlTemplate:
          'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
      subdomains: const ['a', 'b', 'c', 'd'],
      userAgentPackageName: 'com.example.app',
      keepBuffer: 4,
      tileDimension: 256,
      maxZoom: 18,
    );

    return Stack(
      children: [
        RepaintBoundary(
          child: FlutterMap(
            key: const ValueKey('municipio_map'),
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: hasCoordinates ? 14 : 10,
              minZoom: 5,
              maxZoom: 18,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              if (_isSatellite) satelliteTileLayer else streetTileLayer,
              if (hasCoordinates)
                MarkerClusterLayerWidget(
                  options: MarkerClusterLayerOptions(
                    zoomToBoundsOnClick: false,
                    forceIntegerZoomLevel: true,
                    maxClusterRadius: 80,
                    size: const Size(40, 40),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(50),
                    maxZoom: 15,
                    markers: markers,
                    builder: (context, clusterMarkers) {
                      return Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            '${clusterMarkers.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        Positioned(
          top: 8,
          left: 8,
          child: _buildLayerSelector(),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildDateSelector(),
        ),
      ],
    );
  }

  Widget _buildLayerSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLayerButton(
            icon: Icons.map_rounded,
            label: 'Mapa',
            isActive: !_isSatellite,
            onTap: () => setState(() => _isSatellite = false),
          ),
          _buildLayerButton(
            icon: Icons.satellite_alt_rounded,
            label: 'Satélite',
            isActive: _isSatellite,
            onTap: () => setState(() => _isSatellite = true),
          ),
        ],
      ),
    );
  }

  Widget _buildLayerButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.white.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    final orderedKeys = _getOrderedDateKeys();
    if (orderedKeys.isEmpty) return const SizedBox.shrink();

    final grouped = _groupByDate(_reportes);

    return Container(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: orderedKeys.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final key = orderedKeys[index];
            final count = grouped[key]?.length ?? 0;
            final isSelected = key == _selectedDate;
            return GestureDetector(
              onTap: () {
                setState(() => _selectedDate = key);
                _centerMapOnDate();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.black.withValues(alpha: 0.65)
                      : Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.3),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      key,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRefreshButton() {
    return SizedBox(
      height: 36,
      width: 36,
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(),
        clipBehavior: Clip.hardEdge,
        child: InkWell(
          onTap: _isLoading ? null : _loadReportes,
          child: _isLoading
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded, size: 20),
        ),
      ),
    );
  }

  void _centerMapOnDate() {
    final filtered = _filteredReportes;
    final withCoords = filtered
        .where((r) =>
            r.coordenadaLat != null &&
            r.coordenadaLon != null &&
            !r.coordenadaLat!.isNaN &&
            !r.coordenadaLon!.isNaN &&
            !r.coordenadaLat!.isInfinite &&
            !r.coordenadaLon!.isInfinite)
        .toList();
    if (withCoords.isEmpty) return;

    if (withCoords.length == 1) {
      _mapController.move(
        LatLng(withCoords.first.coordenadaLat!, withCoords.first.coordenadaLon!),
        15,
      );
      return;
    }

    final bounds = LatLngBounds.fromPoints(
      withCoords.map((r) => LatLng(r.coordenadaLat!, r.coordenadaLon!)).toList(),
    );

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(60),
        maxZoom: 16,
      ),
    );
  }

  Marker _buildMarker(Reporte r) {
    return Marker(
      point: LatLng(r.coordenadaLat!, r.coordenadaLon!),
      width: 30,
      height: 30,
      child: GestureDetector(
        onTap: () => _showReportBottomSheet(r),
        child: Container(
          decoration: BoxDecoration(
            color: _getEstadoColor(r.idEstado),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Icon(
            _getEventIcon(r.tipoEvento?.nombre),
            color: Colors.white,
            size: 14,
          ),
        ),
      ),
    );
  }

  void _showReportBottomSheet(Reporte r) {
    final estadoColor = _getEstadoColor(r.idEstado);
    final tipoNombre = r.tipoEvento?.nombre ?? 'Sin tipo';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(
                          _getEventIcon(r.tipoEvento?.nombre),
                          size: 24,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tipoNombre,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: estadoColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            r.estado?.nombre ?? 'Enviado',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: estadoColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow(Icons.calendar_today, 'Fecha', r.fechaEvento),
                    if (r.horaEvento != null)
                      _buildDetailRow(Icons.access_time, 'Hora', r.horaEvento!),
                    _buildDetailRow(Icons.location_on, 'Comunidad', r.comunidad),
                    if (r.descripcion != null && r.descripcion!.isNotEmpty)
                      _buildDetailRow(Icons.description, 'Descripción', r.descripcion!),
                    if (r.coordenadaLat != null && r.coordenadaLon != null)
                      _buildDetailRow(
                        Icons.map,
                        'Coordenadas',
                        '${r.coordenadaLat!.toStringAsFixed(6)}, ${r.coordenadaLon!.toStringAsFixed(6)}',
                      ),
                    if (r.fechaReporte != null)
                      _buildDetailRow(
                        Icons.schedule,
                        'Reportado',
                        _formatFechaReporte(r.fechaReporte!),
                      ),
                    if (r.fotografia != null) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Fotografía',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          '${ApiConfig.baseUrl}/upload/descargar/${Uri.encodeComponent(r.fotografia!)}',
                          headers: {
                            'Authorization': 'Bearer ${AuthService.instance.currentToken?.accessToken ?? ''}',
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
                              child: Icon(Icons.broken_image, size: 48, color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatFechaReporte(String fecha) {
    try {
      final dt = DateTime.parse(fecha);
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return fecha;
    }
  }
}
