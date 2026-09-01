import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../../config/api_config.dart';
import '../../../config/theme.dart';
import '../../../models/edan.dart';
import '../../../providers/reporte_provider.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_helper.dart';

class RespMapaTab extends StatefulWidget {
  final Future<List<EdanLocalidad>> Function()? cargarLocalidades;

  const RespMapaTab({super.key, this.cargarLocalidades});

  @override
  State<RespMapaTab> createState() => RespMapaTabState();
}

class RespMapaTabState extends State<RespMapaTab>
    with AutomaticKeepAliveClientMixin {
  final MapController _mapController = MapController();
  final List<_PuntoMapa> _puntos = [];

  bool _cargando = true;
  bool _isSatellite = false;
  bool _isPreparingGeojson = false;
  bool _geojsonError = false;
  bool _legendAbierto = false;
  int _fotoCount = 0;
  String? _selectedDate;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargarLocalidades();
    _prepararGeojson();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void refresh() {
    _cargarLocalidades();
  }

  Future<void> _prepararGeojson() async {
    if (!mounted) return;
    final provider = context.read<ReporteProvider>();
    if (provider.municipioGeojson != null) return;
    if (_isPreparingGeojson) return;
    setState(() {
      _isPreparingGeojson = true;
      _geojsonError = false;
    });
    await provider.ensureMunicipioGeojson();
    if (!mounted) return;
    setState(() {
      _isPreparingGeojson = false;
      if (provider.municipioGeojson == null) _geojsonError = true;
    });
  }

  Future<void> _cargarLocalidades() async {
    final userId = AuthService.instance.userId;
    if (userId == null) {
      if (mounted) setState(() => _cargando = false);
      return;
    }
    try {
      final List<EdanLocalidad> localidades;
      if (widget.cargarLocalidades != null) {
        localidades = await widget.cargarLocalidades!();
      } else {
        final db = DatabaseHelper.instance;
        localidades = await db.getLocalidades(userId);
      }
      final visibles = localidades.where((l) => !l.pendienteEliminacion).toList();
      final puntos = <_PuntoMapa>[];
      final vistos = <String>{};
      for (final l in visibles) {
        final fechaKey = _fechaKeyDeLocalidad(l);
        for (final s in l.establecimientosSalud) {
          final datos = <String, String>{
            if (s.nombreEstablecimiento.isNotEmpty)
              'Lugar': s.nombreEstablecimiento,
            if (s.comunidad.isNotEmpty) 'Comunidad': s.comunidad,
            if (s.nivelAtencion.isNotEmpty) 'Nivel': s.nivelAtencion,
            'Daño': _danoBool(s.danoParcial, s.danoTotal),
            if (s.medicosAfectados > 0) 'Médicos': '${s.medicosAfectados}',
            if (s.enfermerasAfectados > 0)
              'Enfermeras': '${s.enfermerasAfectados}',
            if (s.otrosAfectados > 0) 'Otros': '${s.otrosAfectados}',
          };
          _agregarSeccion(
            puntos,
            l,
            s.fotos,
            s.coordenadaLat,
            s.coordenadaLon,
            s.fotografia,
            'Salud',
            Icons.local_hospital,
            AppColors.enviado,
            fechaKey,
            vistos,
            datos: datos,
          );
        }
        for (final s in l.danosViales) {
          final datos = <String, String>{
            if (s.viaPuente.isNotEmpty) 'Vía/Puente': s.viaPuente,
            if (s.tramo.isNotEmpty) 'Tramo': s.tramo,
            if (s.kmDanio > 0) 'Km daño': s.kmDanio.toStringAsFixed(1),
            if (s.necesidadesInmediatas.isNotEmpty)
              'Necesidades': s.necesidadesInmediatas,
          };
          _agregarSeccion(
            puntos,
            l,
            s.fotos,
            s.coordenadaLat,
            s.coordenadaLon,
            s.fotografia,
            'Vías y puentes',
            Icons.construction,
            AppColors.primary,
            fechaKey,
            vistos,
            datos: datos,
          );
        }
        for (final s in l.danosInfraPublica) {
          final datos = <String, String>{
            if (s.comunidad.isNotEmpty) 'Comunidad': s.comunidad,
            if (s.tipoEstructura.isNotEmpty) 'Tipo': s.tipoEstructura,
            'Daño': _danoBool(s.danoParcial, s.danoTotal),
          };
          _agregarSeccion(
            puntos,
            l,
            s.fotos,
            s.coordenadaLat,
            s.coordenadaLon,
            s.fotografia,
            'Infraestructura pública',
            Icons.apartment,
            AppColors.pending,
            fechaKey,
            vistos,
            datos: datos,
          );
        }
        for (final s in l.unidadesEducativas) {
          final datos = <String, String>{
            if (s.nombreEstablecimiento.isNotEmpty)
              'Lugar': s.nombreEstablecimiento,
            if (s.comunidad.isNotEmpty) 'Comunidad': s.comunidad,
            'Daño': _danoBool(s.danoParcial, s.danoTotal),
            if (s.totalAfectados > 0) 'Total afectados': '${s.totalAfectados}',
            if (s.suspensionClases == true) 'Suspensión clases': 'Sí',
          };
          _agregarSeccion(
            puntos,
            l,
            s.fotos,
            s.coordenadaLat,
            s.coordenadaLon,
            s.fotografia,
            'Educación',
            Icons.school,
            AppColors.inProgress,
            fechaKey,
            vistos,
            datos: datos,
          );
        }
        for (final s in l.danosVivienda) {
          final datos = <String, String>{
            if (s.comunidad.isNotEmpty) 'Comunidad': s.comunidad,
            if (s.danoParcial > 0) 'Daño parcial': '${s.danoParcial}',
            if (s.danoTotal > 0) 'Daño total': '${s.danoTotal}',
            if (s.necesidadesInmediatas.isNotEmpty)
              'Necesidades': s.necesidadesInmediatas,
          };
          _agregarSeccion(
            puntos,
            l,
            s.fotos,
            s.coordenadaLat,
            s.coordenadaLon,
            s.fotografia,
            'Viviendas',
            Icons.home,
            AppColors.rechazado,
            fechaKey,
            vistos,
            datos: datos,
          );
        }
        for (final s in l.danosAgricultura) {
          final datos = <String, String>{
            if (s.tipoCultivo.isNotEmpty) 'Cultivo': s.tipoCultivo,
            if (s.hectareasAfectadas > 0)
              'Hect. afectadas': '${s.hectareasAfectadas}',
            if (s.hectareasPerdidas > 0)
              'Hect. perdidas': '${s.hectareasPerdidas}',
          };
          _agregarSeccion(
            puntos,
            l,
            s.fotos,
            s.coordenadaLat,
            s.coordenadaLon,
            s.fotografia,
            'Agricultura',
            Icons.agriculture,
            AppColors.aprobado,
            fechaKey,
            vistos,
            datos: datos,
          );
        }
        for (final s in l.danosPecuarios) {
          final datos = <String, String>{
            if (s.especie.isNotEmpty) 'Especie': s.especie,
            if (s.raza.isNotEmpty) 'Raza': s.raza,
            if (s.animalesAfectados > 0) 'Afectados': '${s.animalesAfectados}',
            if (s.animalesMuertos > 0) 'Muertos': '${s.animalesMuertos}',
            if (s.necesidadesInmediatas.isNotEmpty)
              'Necesidades': s.necesidadesInmediatas,
          };
          _agregarSeccion(
            puntos,
            l,
            s.fotos,
            s.coordenadaLat,
            s.coordenadaLon,
            s.fotografia,
            'Pecuario',
            Icons.pets,
            AppColors.secondary,
            fechaKey,
            vistos,
            datos: datos,
          );
        }
        for (final s in l.infraProductiva) {
          final datos = <String, String>{
            if (s.tipo.isNotEmpty) 'Tipo': s.tipo,
            if (s.danoParcial > 0) 'Daño parcial': '${s.danoParcial}',
            if (s.danoTotal > 0) 'Daño total': '${s.danoTotal}',
          };
          _agregarSeccion(
            puntos,
            l,
            s.fotos,
            s.coordenadaLat,
            s.coordenadaLon,
            s.fotografia,
            'Infraestructura productiva',
            Icons.factory,
            AppColors.cerrado,
            fechaKey,
            vistos,
            datos: datos,
          );
        }
      }
      if (mounted) {
        setState(() {
          _puntos
            ..clear()
            ..addAll(puntos);
          _fotoCount = vistos.length;
          _cargando = false;
          final fechas = _ordenarFechas();
          if (_selectedDate == null || !fechas.contains(_selectedDate)) {
            _selectedDate = fechas.isNotEmpty ? fechas.first : null;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _fechaKeyDeLocalidad(EdanLocalidad l) {
    final fe = l.fechaEvento;
    if (fe == null || fe.trim().isEmpty) return 'Sin fecha';
    final dt = DateTime.tryParse(fe);
    return dt == null ? 'Sin fecha' : _fmtFecha(dt);
  }

  String _fmtFecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  void _agregarSeccion(
    List<_PuntoMapa> puntos,
    EdanLocalidad localidad,
    List<EdanFoto> fotos,
    double coordLat,
    double coordLon,
    String? servidor,
    String seccion,
    IconData icon,
    Color color,
    String fechaKey,
    Set<String> vistos, {
    Map<String, String> datos = const {},
  }) {
    final idLugar = localidad.idLocal ?? localidad.nombre;
    final usuario = localidad.usuario?.nombre;
    final evento = localidad.tipoEventoNombre;
    if (fotos.isNotEmpty) {
      for (final foto in fotos) {
        final lat = foto.latitud != 0 ? foto.latitud : coordLat;
        final lon = foto.longitud != 0 ? foto.longitud : coordLon;
        if (!_coordsValidas(lat, lon)) continue;
        final clave = '$idLugar|$seccion|${foto.ruta}|$servidor|$lat,$lon';
        if (!vistos.add(clave)) continue;
        puntos.add(
          _PuntoMapa(
            lat: lat,
            lon: lon,
            localidad: localidad.etiquetaLugar,
            seccion: seccion,
            icon: icon,
            color: color,
            fotos: [foto],
            servidor: servidor,
            fechaKey: fechaKey,
            datos: datos,
            usuarioNombre: usuario,
            tipoEvento: evento,
          ),
        );
      }
    } else if (servidor != null &&
        servidor.trim().isNotEmpty &&
        _coordsValidas(coordLat, coordLon)) {
      final fotoServer = EdanFoto(
        ruta: '',
        latitud: coordLat,
        longitud: coordLon,
      );
      final clave = '$idLugar|$seccion|servidor:$servidor|$coordLat,$coordLon';
      if (!vistos.add(clave)) return;
      puntos.add(
        _PuntoMapa(
          lat: coordLat,
          lon: coordLon,
          localidad: localidad.etiquetaLugar,
          seccion: seccion,
          icon: icon,
          color: color,
          fotos: [fotoServer],
          servidor: servidor,
          fechaKey: fechaKey,
          datos: datos,
          usuarioNombre: usuario,
          tipoEvento: evento,
        ),
      );
    } else if (_coordsValidas(coordLat, coordLon)) {
      final clave = '$idLugar|$seccion|sin-foto|$servidor|$coordLat,$coordLon';
      if (!vistos.add(clave)) return;
      puntos.add(
        _PuntoMapa(
          lat: coordLat,
          lon: coordLon,
          localidad: localidad.etiquetaLugar,
          seccion: seccion,
          icon: icon,
          color: color,
          fotos: const [],
          servidor: servidor,
          fechaKey: fechaKey,
          datos: datos,
          usuarioNombre: usuario,
          tipoEvento: evento,
        ),
      );
    }
  }

  String _danoBool(bool parcial, bool total) {
    if (parcial && total) return 'Parcial y total';
    if (parcial) return 'Parcial';
    if (total) return 'Total';
    return 'Ninguno';
  }

  bool _coordsValidas(double lat, double lon) {
    return lat != 0.0 &&
        lon != 0.0 &&
        !lat.isNaN &&
        !lon.isNaN &&
        !lat.isInfinite &&
        !lon.isInfinite &&
        lat >= -90 &&
        lat <= 90 &&
        lon >= -180 &&
        lon <= 180;
  }

  List<_PuntoMapa> get _puntosFiltrados {
    if (_selectedDate == null) return _puntos;
    return _puntos.where((p) => p.fechaKey == _selectedDate).toList();
  }

  Map<String, int> _contarPorFecha() {
    final m = <String, int>{};
    for (final p in _puntos) {
      m[p.fechaKey] = (m[p.fechaKey] ?? 0) + 1;
    }
    return m;
  }

  List<String> _ordenarFechas() {
    final fechas = _contarPorFecha().keys.toList();
    final fechasOrdenadas = <DateTime>[];
    var conSinFecha = false;
    for (final f in fechas) {
      if (f == 'Sin fecha') {
        conSinFecha = true;
        continue;
      }
      final parts = f.split('/');
      if (parts.length != 3) continue;
      final dt = DateTime(
        int.parse(parts[2]),
        int.parse(parts[1]),
        int.parse(parts[0]),
      );
      fechasOrdenadas.add(dt);
    }
    fechasOrdenadas.sort((a, b) => b.compareTo(a));
    final keys = fechasOrdenadas.map(_fmtFecha).toList();
    if (conSinFecha) keys.add('Sin fecha');
    return keys;
  }

  void _centerMapOnDate() {
    final geojson = context.read<ReporteProvider>().municipioGeojson;
    final hasPolygon =
        geojson != null && _safePolygonBounds(geojson.polygons) != null;
    if (hasPolygon) return;

    final filtered = _puntosFiltrados;
    if (filtered.isEmpty) return;

    if (filtered.length == 1) {
      _mapController.move(LatLng(filtered.first.lat, filtered.first.lon), 15);
      return;
    }

    try {
      final bounds = LatLngBounds.fromPoints(
        filtered.map((p) => LatLng(p.lat, p.lon)).toList(),
      );
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(60),
          maxZoom: 16,
        ),
      );
    } catch (_) {
      debugPrint('Error calculando bounds de puntos');
    }
  }

  LatLngBounds? _safePolygonBounds(List<List<LatLng>> polygons) {
    try {
      final points = polygons.expand((ring) => ring).toList();
      if (points.isEmpty) return null;
      return LatLngBounds.fromPoints(points);
    } catch (e) {
      debugPrint('Error calculando bounds del geojson: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final primary = PaletteScope.of(context).primary;
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Expanded(child: _buildMapView(primary)),
        _buildLegend(primary),
      ],
    );
  }

  Widget _buildMapView(Color primary) {
    final filtered = _puntosFiltrados;
    final markers = filtered.map((p) => _buildMarker(p)).toList();
    final hasPoints = markers.isNotEmpty;

    final geojson = context.watch<ReporteProvider>().municipioGeojson;
    final hasPolygonData = geojson != null && geojson.polygons.isNotEmpty;
    final polygonBounds = hasPolygonData
        ? _safePolygonBounds(geojson.polygons)
        : null;
    final hasPolygon = polygonBounds != null;

    LatLng center;
    if (polygonBounds != null) {
      center = polygonBounds.center;
    } else if (hasPoints) {
      final lats = filtered.map((p) => p.lat);
      final lons = filtered.map((p) => p.lon);
      center = LatLng(
        lats.reduce((a, b) => a + b) / lats.length,
        lons.reduce((a, b) => a + b) / lons.length,
      );
    } else {
      center = const LatLng(-16.5, -68.1);
    }

    final satelliteTileLayer = TileLayer(
      urlTemplate:
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      userAgentPackageName: 'com.climbat.edan',
      keepBuffer: 4,
      tileDimension: 256,
      maxZoom: 18,
    );

    final streetTileLayer = TileLayer(
      urlTemplate:
          'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
      subdomains: const ['a', 'b', 'c', 'd'],
      userAgentPackageName: 'com.climbat.edan',
      keepBuffer: 4,
      tileDimension: 256,
      maxZoom: 18,
    );

    return Stack(
      children: [
        RepaintBoundary(
          child: FlutterMap(
            key: ValueKey('resp_mapa_$_isSatellite'),
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: hasPolygon ? 13 : (hasPoints ? 14 : 10),
              initialCameraFit: polygonBounds != null
                  ? CameraFit.bounds(
                      bounds: polygonBounds,
                      padding: const EdgeInsets.all(40),
                    )
                  : hasPoints
                  ? CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(
                        filtered.map((p) => LatLng(p.lat, p.lon)).toList(),
                      ),
                      padding: const EdgeInsets.all(50),
                    )
                  : null,
              minZoom: 5,
              maxZoom: 18,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              if (_isSatellite) satelliteTileLayer else streetTileLayer,
              if (hasPolygon && geojson != null)
                PolygonLayer(
                  polygons: [
                    for (final ring in geojson.polygons)
                      Polygon(
                        points: ring,
                        color: primary.withValues(alpha: 0.05),
                        borderColor: primary,
                        borderStrokeWidth: 2,
                      ),
                  ],
                ),
              if (hasPoints)
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
                          color: primary,
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
        Positioned(top: 8, left: 8, child: _buildLayerSelector(primary)),
        Positioned(
          top: 8,
          right: 8,
          child: _geojsonError && !hasPolygon
              ? _buildGeojsonRetryButton()
              : _buildCounter(primary),
        ),
        if (!hasPoints)
          Center(
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.location_off_outlined,
                    size: 40,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _puntos.isEmpty
                        ? 'Aún no hay puntos de coordenadas.'
                        : 'No hay puntos para la fecha seleccionada.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _puntos.isEmpty
                        ? 'Toma fotos en el formulario EDAN para registrar su ubicación.'
                        : 'Selecciona otra fecha en el filtro para ver sus puntos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_puntosFiltrados.any((p) => p.fotos.isNotEmpty))
                _buildFotoStrip(primary),
              _buildDateSelector(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCounter(Color primary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${_puntosFiltrados.length} punto(s)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: primary,
            ),
          ),
          Text(
            '$_fotoCount foto(s) con GPS',
            style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildGeojsonRetryButton() {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        onTap: _isPreparingGeojson ? null : _prepararGeojson,
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.refresh_rounded, size: 20),
        ),
      ),
    );
  }

  Widget _buildFotoStrip(Color primary) {
    final items = _puntosFiltrados.where((p) => p.fotos.isNotEmpty).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.photo_library_outlined, size: 14, color: primary),
              const SizedBox(width: 6),
              Text(
                'Galería · toca para ver en el mapa',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final punto = items[index];
                return GestureDetector(
                  onTap: () {
                    _mapController.move(LatLng(punto.lat, punto.lon), 15);
                    _abrirPunto(punto);
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 64,
                      child: _FotoThumb(foto: punto.fotos.first, punto: punto),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    final contador = _contarPorFecha();
    final fechas = _ordenarFechas();
    if (fechas.isEmpty) return const SizedBox.shrink();
    final keys = fechas;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.45),
          ],
        ),
      ),
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: keys.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final key = keys[index];
            final isSelected = key == _selectedDate;
            final count = contador[key] ?? 0;
            return GestureDetector(
              onTap: () {
                setState(() => _selectedDate = key);
                _centerMapOnDate();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
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
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? PaletteScope.of(context).primary
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

  Widget _buildLayerSelector(Color primary) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLayerBtn(
            icon: Icons.map_outlined,
            tooltip: 'Mapa callejero',
            selected: !_isSatellite,
            onTap: () => setState(() => _isSatellite = false),
          ),
          _buildLayerBtn(
            icon: Icons.satellite_alt_outlined,
            tooltip: 'Vista satelital',
            selected: _isSatellite,
            onTap: () => setState(() => _isSatellite = true),
          ),
        ],
      ),
    );
  }

  Widget _buildLayerBtn({
    required IconData icon,
    required String tooltip,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: 18,
            color: selected
                ? PaletteScope.of(context).primary
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Marker _buildMarker(_PuntoMapa punto) {
    return Marker(
      point: LatLng(punto.lat, punto.lon),
      width: 34,
      height: 34,
      child: GestureDetector(
        onTap: () => _abrirPunto(punto),
        child: Container(
          decoration: BoxDecoration(
            color: punto.color,
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
          child: Icon(punto.icon, color: Colors.white, size: 16),
        ),
      ),
    );
  }

  void _abrirPunto(_PuntoMapa punto) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PuntoSheet(
        punto: punto,
        onVerFoto: (foto) => _verFotoFullscreen(ctx, punto, foto),
      ),
    );
  }

  void _verFotoFullscreen(BuildContext ctx, _PuntoMapa punto, EdanFoto foto) {
    showDialog<void>(
      context: ctx,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (dialogCtx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Center(
                  child: _imagenDeFoto(foto, punto, fit: BoxFit.contain),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${punto.localidad} · ${punto.seccion}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: MediaQuery.of(dialogCtx).padding.bottom + 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${punto.lat.toStringAsFixed(5)}, '
                  '${punto.lon.toStringAsFixed(5)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fotoUrl(String serverPath) =>
      '${ApiConfig.baseUrl}/upload/descargar/${Uri.encodeComponent(serverPath)}';

  Map<String, String> get _fotoHeaders => {
    'Authorization':
        'Bearer ${AuthService.instance.currentToken?.accessToken ?? ''}',
  };

  Widget _imagenDeFoto(
    EdanFoto foto,
    _PuntoMapa punto, {
    BoxFit fit = BoxFit.cover,
  }) {
    if (foto.ruta.trim().isNotEmpty && File(foto.ruta).existsSync()) {
      return Image.file(
        File(foto.ruta),
        fit: fit,
        errorBuilder: (_, _, _) => _fotoPlaceholder(),
      );
    }
    final server = punto.servidor;
    if (server != null && server.trim().isNotEmpty) {
      return Image.network(
        _fotoUrl(server),
        headers: _fotoHeaders,
        fit: fit,
        errorBuilder: (_, _, _) => _fotoPlaceholder(),
      );
    }
    return _fotoPlaceholder();
  }

  Widget _fotoPlaceholder() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: AppColors.background,
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported_outlined,
        size: 28,
        color: AppColors.textSecondary,
      ),
    );
  }

  Widget _buildLegend(Color primary) {
    const items = <(String, IconData, Color)>[
      ('Salud', Icons.local_hospital, AppColors.enviado),
      ('Vías y puentes', Icons.construction, AppColors.primary),
      ('Infraestructura pública', Icons.apartment, AppColors.pending),
      ('Educación', Icons.school, AppColors.inProgress),
      ('Viviendas', Icons.home, AppColors.rechazado),
      ('Agricultura', Icons.agriculture, AppColors.aprobado),
      ('Pecuario', Icons.pets, AppColors.secondary),
      ('Infraestructura productiva', Icons.factory, AppColors.cerrado),
    ];
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _legendAbierto = !_legendAbierto),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _legendAbierto ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.expand_more,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.legend_toggle, size: 16, color: primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Leyenda de secciones',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _legendAbierto
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: items.map((item) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: item.$3,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(item.$2, size: 12, color: Colors.white),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        item.$1,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PuntoMapa {
  final double lat;
  final double lon;
  final String localidad;
  final String seccion;
  final IconData icon;
  final Color color;
  final List<EdanFoto> fotos;
  final String? servidor;
  final String fechaKey;
  final Map<String, String> datos;
  final String? usuarioNombre;
  final String? tipoEvento;

  const _PuntoMapa({
    required this.lat,
    required this.lon,
    required this.localidad,
    required this.seccion,
    required this.icon,
    required this.color,
    required this.fotos,
    this.servidor,
    this.fechaKey = 'Sin fecha',
    this.datos = const {},
    this.usuarioNombre,
    this.tipoEvento,
  });
}

class _PuntoSheet extends StatelessWidget {
  final _PuntoMapa punto;
  final void Function(EdanFoto foto) onVerFoto;

  const _PuntoSheet({required this.punto, required this.onVerFoto});

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.80,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: punto.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(punto.icon, color: punto.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      punto.localidad,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      punto.seccion,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (punto.usuarioNombre != null || punto.tipoEvento != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (punto.usuarioNombre != null) ...[
                  const Icon(Icons.person_outline, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    punto.usuarioNombre!,
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
                if (punto.usuarioNombre != null && punto.tipoEvento != null)
                  const Text(' · ', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                if (punto.tipoEvento != null) ...[
                  const Icon(Icons.bolt_outlined, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    punto.tipoEvento!,
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                Icon(Icons.gps_fixed, size: 16, color: punto.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${punto.lat.toStringAsFixed(6)}, '
                    '${punto.lon.toStringAsFixed(6)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (punto.datos.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: punto.datos.entries.map((e) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 110,
                          child: Text(
                            e.key,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            e.value,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          if (punto.fotos.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Fotos (${punto.fotos.length})',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: punto.fotos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final foto = punto.fotos[index];
                  return GestureDetector(
                    onTap: () => onVerFoto(foto),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 110,
                        child: _FotoThumb(foto: foto, punto: punto),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
       ),
      ),
    );
  }
}

class _FotoThumb extends StatelessWidget {
  final EdanFoto foto;
  final _PuntoMapa punto;

  const _FotoThumb({required this.foto, required this.punto});

  @override
  Widget build(BuildContext context) {
    if (foto.ruta.trim().isNotEmpty && File(foto.ruta).existsSync()) {
      return Image.file(
        File(foto.ruta),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _ThumbPlaceholder(),
      );
    }
    final server = punto.servidor;
    if (server != null && server.trim().isNotEmpty) {
      return Image.network(
        '${ApiConfig.baseUrl}/upload/descargar/${Uri.encodeComponent(server)}',
        headers: {
          'Authorization':
              'Bearer ${AuthService.instance.currentToken?.accessToken ?? ''}',
        },
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _ThumbPlaceholder(),
      );
    }
    return const _ThumbPlaceholder();
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported_outlined,
        size: 24,
        color: AppColors.textSecondary,
      ),
    );
  }
}
