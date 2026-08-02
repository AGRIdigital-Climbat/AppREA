import 'package:latlong2/latlong.dart';

class MunicipioGeojson {
  final int id;
  final String codigoIne;
  final String? nombre;
  final String? departamento;
  final String? provincia;
  final double? areaKm2;
  final List<List<LatLng>> polygons;

  MunicipioGeojson({
    required this.id,
    required this.codigoIne,
    this.nombre,
    this.departamento,
    this.provincia,
    this.areaKm2,
    required this.polygons,
  });

  factory MunicipioGeojson.fromJson(Map<String, dynamic> json) {
    final properties = json['properties'] as Map<String, dynamic>? ?? {};
    final geometry = json['geometry'] as Map<String, dynamic>?;
    final type = geometry?['type'] as String? ?? '';
    final coordinates = geometry?['coordinates'] as List? ?? [];

    final polygons = <List<LatLng>>[];

    if (type == 'MultiPolygon') {
      for (final polygon in coordinates) {
        if (polygon is! List) continue;
        for (final ring in polygon) {
          final latLngs = _ringToLatLngs(ring);
          if (latLngs != null) polygons.add(latLngs);
        }
      }
    } else if (type == 'Polygon') {
      for (final ring in coordinates) {
        final latLngs = _ringToLatLngs(ring);
        if (latLngs != null) polygons.add(latLngs);
      }
    }

    return MunicipioGeojson(
      id: (properties['id'] as num?)?.toInt() ?? 0,
      codigoIne: properties['codigo_ine'] as String? ?? '',
      nombre: properties['nombre'] as String?,
      departamento: (properties['departamento']
              as Map<String, dynamic>?)?['nombre'] as String?,
      provincia:
          (properties['provincia'] as Map<String, dynamic>?)?['nombre'] as String?,
      areaKm2: (properties['area_km2'] as num?)?.toDouble(),
      polygons: polygons,
    );
  }

  static List<LatLng>? _ringToLatLngs(Object? ring) {
    if (ring is! List || ring.length < 3) return null;
    final points = <LatLng>[];
    for (final pair in ring) {
      if (pair is! List || pair.length < 2) return null;
      final lng = (pair[0] as num).toDouble();
      final lat = (pair[1] as num).toDouble();
      if (lng.isNaN || lat.isNaN || lng.isInfinite || lat.isInfinite) {
        return null;
      }
      points.add(LatLng(lat, lng));
    }
    return points;
  }
}
