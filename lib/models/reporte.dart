import 'departamento.dart';
import 'provincia.dart';
import 'municipio.dart';

class Reporte {
  final int? idReporte;
  final int idUsuario;
  final int idDepartamento;
  final int idProvincia;
  final int idMunicipio;
  final String comunidad;
  final String fechaEvento;
  final String? horaEvento;
  final String? fechaReporte;
  final int idTipoEvento;
  final double? coordenadaLat;
  final double? coordenadaLon;
  final String? fotografia;
  final String? descripcion;
  final int idEstado;
  final Departamento? departamento;
  final Provincia? provincia;
  final Municipio? municipio;
  final TipoEvento? tipoEvento;
  final Estado? estado;
  final List<Categoria>? categorias;

  Reporte({
    this.idReporte,
    required this.idUsuario,
    required this.idDepartamento,
    required this.idProvincia,
    required this.idMunicipio,
    required this.comunidad,
    required this.fechaEvento,
    this.horaEvento,
    this.fechaReporte,
    required this.idTipoEvento,
    this.coordenadaLat,
    this.coordenadaLon,
    this.fotografia,
    this.descripcion,
    this.idEstado = 1,
    this.departamento,
    this.provincia,
    this.municipio,
    this.tipoEvento,
    this.estado,
    this.categorias,
  });

  factory Reporte.fromJson(Map<String, dynamic> json) {
    return Reporte(
      idReporte: json['id_reporte'],
      idUsuario: json['id_usuario'],
      idDepartamento: json['id_departamento'],
      idProvincia: json['id_provincia'],
      idMunicipio: json['id_municipio'],
      comunidad: json['comunidad'],
      fechaEvento: json['fecha_evento'],
      horaEvento: json['hora_evento'],
      fechaReporte: json['fecha_reporte'],
      idTipoEvento: json['id_tipo_evento'],
      coordenadaLat: json['coordenada_lat']?.toDouble(),
      coordenadaLon: json['coordenada_lon']?.toDouble(),
      fotografia: json['fotografia'],
      descripcion: json['descripcion'],
      idEstado: json['id_estado'],
      departamento: json['departamento'] != null
          ? Departamento.fromJson(json['departamento'])
          : null,
      provincia: json['provincia'] != null
          ? Provincia.fromJson(json['provincia'])
          : null,
      municipio: json['municipio'] != null
          ? Municipio.fromJson(json['municipio'])
          : null,
      tipoEvento: json['tipo_evento'] != null
          ? TipoEvento.fromJson(json['tipo_evento'])
          : null,
      estado: json['estado'] != null ? Estado.fromJson(json['estado']) : null,
      categorias: json['categorias'] != null
          ? (json['categorias'] as List)
              .map((c) => Categoria.fromJson(c))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id_usuario': idUsuario,
      'id_departamento': idDepartamento,
      'id_provincia': idProvincia,
      'id_municipio': idMunicipio,
      'comunidad': comunidad,
      'fecha_evento': fechaEvento,
      'hora_evento': horaEvento,
      'id_tipo_evento': idTipoEvento,
      'coordenada_lat': coordenadaLat,
      'coordenada_lon': coordenadaLon,
      'fotografia': fotografia,
      'descripcion': descripcion,
      'id_estado': idEstado,
      'categorias': categorias?.map((c) => c.idCategoria).toList(),
    };
  }
}

class TipoEvento {
  final int idTipoEvento;
  final String nombre;
  final String? descripcion;

  TipoEvento({
    required this.idTipoEvento,
    required this.nombre,
    this.descripcion,
  });

  factory TipoEvento.fromJson(Map<String, dynamic> json) {
    return TipoEvento(
      idTipoEvento: json['id_tipo_evento'],
      nombre: json['nombre'],
      descripcion: json['descripcion'],
    );
  }
}

class Estado {
  final int idEstado;
  final String nombre;
  final String? descripcion;
  final int? orden;

  Estado({
    required this.idEstado,
    required this.nombre,
    this.descripcion,
    this.orden,
  });

  factory Estado.fromJson(Map<String, dynamic> json) {
    return Estado(
      idEstado: json['id_estado'],
      nombre: json['nombre'],
      descripcion: json['descripcion'],
      orden: json['orden'],
    );
  }
}

class Categoria {
  final int idCategoria;
  final String nombre;
  final String? descripcion;
  final int? orden;

  Categoria({
    required this.idCategoria,
    required this.nombre,
    this.descripcion,
    this.orden,
  });

  factory Categoria.fromJson(Map<String, dynamic> json) {
    return Categoria(
      idCategoria: json['id_categoria'],
      nombre: json['nombre'],
      descripcion: json['descripcion'],
      orden: json['orden'],
    );
  }
}
