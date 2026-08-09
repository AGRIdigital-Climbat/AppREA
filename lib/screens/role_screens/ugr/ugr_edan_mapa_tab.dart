import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import '../../../config/theme.dart';
import '../../../models/ugr_models.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_helper.dart';
import 'ugr_edan_detalle.dart';
import 'ugr_evento.dart';

class UgrEdanMapaTab extends StatefulWidget {
  const UgrEdanMapaTab({super.key});

  @override
  State<UgrEdanMapaTab> createState() => _UgrEdanMapaTabState();
}

class _UgrEdanMapaTabState extends State<UgrEdanMapaTab>
    with AutomaticKeepAliveClientMixin {
  final MapController _mapController = MapController();

  List<UgrEdan> _edanes = [];
  bool _isLoading = true;
  bool _isSatellite = false;
  bool _isMapView = true;
  String? _selectedDate;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadEdanes();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadEdanes() async {
    setState(() {
      _isLoading = true;
    });

    final userId = AuthService.instance.userId;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final edanes = await DatabaseHelper.instance.getEdans(userId);
      final ugrEdanes = edanes
          .map((e) => UgrEdan.fromEdan(
                e,
                municipioNombre: e.municipioNombre ?? '',
                usuarioNombre: AuthService.instance.userName,
              ))
          .toList();

      if (mounted) {
        setState(() {
          _edanes = ugrEdanes;
          _isLoading = false;
          _initializeSelectedDate();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Map<String, List<UgrEdan>> _groupByDate(List<UgrEdan> edanes) {
    final grouped = <String, List<UgrEdan>>{};
    for (final e in edanes) {
      final key = _dateKeyFromDate(e.fechaCreacion);
      grouped.putIfAbsent(key, () => []).add(e);
    }
    return grouped;
  }

  String _dateKeyFromDate(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  void _initializeSelectedDate() {
    if (_edanes.isEmpty) return;
    final keys = _getOrderedDateKeys();
    if (keys.isNotEmpty) {
      _selectedDate = keys.first;
    }
  }

  List<String> _getOrderedDateKeys() {
    final grouped = _groupByDate(_edanes);
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

  List<UgrEdan> get _filteredEdanes {
    if (_selectedDate == null) return _edanes;
    return _edanes.where((e) {
      return _dateKeyFromDate(e.fechaCreacion) == _selectedDate;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_edanes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.map_outlined,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              'No hay EDANs para mostrar',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildDateSelector(),
        Expanded(
          child: _isMapView ? _buildMap() : _buildList(),
        ),
      ],
    );
  }

  Widget _buildDateSelector() {
    final grouped = _groupByDate(_edanes);
    final dates = _getOrderedDateKeys();

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppColors.surface,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: dates.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final date = dates[index];
          final count = grouped[date]?.length ?? 0;
          final isSelected = date == _selectedDate;

          return ChoiceChip(
            label: Text(
              '$date ($count)',
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
            ),
            selected: isSelected,
            onSelected: (_) => setState(() => _selectedDate = date),
            selectedColor: AppColors.primary,
            backgroundColor: AppColors.background,
          );
        },
      ),
    );
  }

  Widget _buildMap() {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: LatLng(-16.5, -68.15),
            initialZoom: 9.0,
            minZoom: 6.0,
            maxZoom: 18.0,
          ),
          children: [
            TileLayer(
              urlTemplate: _isSatellite
                  ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.climbat.edan',
            ),
            MarkerClusterLayerWidget(
              options: MarkerClusterLayerOptions(
                maxClusterRadius: 45,
                size: const Size(40, 40),
                alignment: Alignment.center,
                builder: (context, markers) {
                  final firstEdan = _filteredEdanes.firstWhere(
                    (e) => e.lat != 0.0 && e.lon != 0.0,
                    orElse: () => _filteredEdanes.first,
                  );
                  return _buildClusterMarker(firstEdan, markers.length);
                },
                markers: _filteredEdanes
                    .where((e) => e.lat != 0.0 && e.lon != 0.0)
                    .map((e) => Marker(
                          point: LatLng(e.lat, e.lon),
                          child: _buildMarker(e),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: Column(
            children: [
              _buildMapControlButton(
                icon: _isSatellite ? Icons.map : Icons.satellite,
                onPressed: () => setState(() => _isSatellite = !_isSatellite),
                tooltip: _isSatellite ? 'Ver mapa' : 'Ver satélite',
              ),
              const SizedBox(height: 8),
              _buildMapControlButton(
                icon: _isMapView ? Icons.list : Icons.map,
                onPressed: () => setState(() => _isMapView = !_isMapView),
                tooltip: _isMapView ? 'Ver lista' : 'Ver mapa',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildClusterMarker(UgrEdan edan, int count) {
    return Container(
      decoration: BoxDecoration(
        color: edan.estado.color,
        shape: BoxShape.circle,
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
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildMarker(UgrEdan edan) {
    return GestureDetector(
      onTap: () => _showEdanDetails(edan),
      child: Container(
        decoration: BoxDecoration(
          color: edan.estado.color.withValues(alpha: 0.2),
          shape: BoxShape.circle,
          border: Border.all(color: edan.estado.color, width: 2),
        ),
        child: Icon(
          ugrEventoIcon(edan.tipoEvento),
          color: edan.estado.color,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildMapControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: AppColors.primary),
        ),
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _filteredEdanes.length,
      itemBuilder: (context, index) {
        final edan = _filteredEdanes[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: ugrEventoColor(edan.tipoEvento, AppColors.primary)
                    .withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                ugrEventoIcon(edan.tipoEvento),
                size: 22,
                color: ugrEventoColor(edan.tipoEvento, AppColors.primary),
              ),
            ),
            title: Text(edan.codigo),
            subtitle: Text('${edan.tipoEvento} · ${edan.comunidad}'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: edan.estado.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                edan.estado.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: edan.estado.color,
                ),
              ),
            ),
            onTap: () => _showEdanDetails(edan),
          ),
        );
      },
    );
  }

  void _showEdanDetails(UgrEdan edan) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EdanBottomSheet(edan: edan),
    );
  }
}

class _EdanBottomSheet extends StatelessWidget {
  final UgrEdan edan;

  const _EdanBottomSheet({required this.edan});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.all(12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        edan.codigo,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: edan.estado.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: edan.estado.color.withValues(alpha: 0.5)),
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
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${edan.tipoEvento} · ${edan.comunidad}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => UgrEdanDetalle(edan: edan),
                        ),
                      );
                    },
                    child: const Text('Ver detalle'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
