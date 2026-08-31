import 'departamento.dart';
import 'provincia.dart';
import 'municipio.dart';
import 'usuario.dart';

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
  final Usuario? usuario;

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
    this.usuario,
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
      coordenadaLat: double.tryParse(json['coordenada_lat']?.toString() ?? ''),
      coordenadaLon: double.tryParse(json['coordenada_lon']?.toString() ?? ''),
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
      usuario: json['usuario'] != null
          ? Usuario.fromJson(json['usuario'])
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

class Cultivo {
  final int idCultivo;
  final String nombre;
  final String? grupo;

  Cultivo({
    required this.idCultivo,
    required this.nombre,
    this.grupo,
  });

  factory Cultivo.fromJson(Map<String, dynamic> json) {
    return Cultivo(
      idCultivo: json['id_cultivo'] ?? json['id'] ?? 0,
      nombre: json['nombre'] ?? '',
      grupo: json['grupo'],
    );
  }
}

class PecuarioGrupo {
  final int idPecuarioGrupo;
  final String nombre;
  final String? grupo;

  PecuarioGrupo({
    required this.idPecuarioGrupo,
    required this.nombre,
    this.grupo,
  });

  factory PecuarioGrupo.fromJson(Map<String, dynamic> json) {
    return PecuarioGrupo(
      idPecuarioGrupo: json['id_pecuario_grupo'] ?? json['id'] ?? 0,
      nombre: json['nombre'] ?? '',
      grupo: json['grupo'],
    );
  }
}

class GrupoVulnerableCatalogo {
  final int idGrupoVulnerable;
  final String codigo;
  final String nombre;
  final String? descripcion;
  final int? orden;
  final bool activo;

  GrupoVulnerableCatalogo({
    required this.idGrupoVulnerable,
    required this.codigo,
    required this.nombre,
    this.descripcion,
    this.orden,
    this.activo = true,
  });

  factory GrupoVulnerableCatalogo.fromJson(Map<String, dynamic> json) {
    return GrupoVulnerableCatalogo(
      idGrupoVulnerable: json['id_grupo_vulnerable'] ?? json['id'] ?? 0,
      codigo: json['codigo'] ?? '',
      nombre: json['nombre'] ?? '',
      descripcion: json['descripcion'],
      orden: json['orden'],
      activo: json['activo'] ?? true,
    );
  }
}

class GrupoEtarioCatalogo {
  final int idGrupoEtario;
  final String codigo;
  final String nombre;
  final String? descripcion;
  final int? orden;
  final bool activo;

  GrupoEtarioCatalogo({
    required this.idGrupoEtario,
    required this.codigo,
    required this.nombre,
    this.descripcion,
    this.orden,
    this.activo = true,
  });

  factory GrupoEtarioCatalogo.fromJson(Map<String, dynamic> json) {
    return GrupoEtarioCatalogo(
      idGrupoEtario: json['id_grupo_etario'] ?? json['id'] ?? 0,
      codigo: json['codigo'] ?? '',
      nombre: json['nombre'] ?? '',
      descripcion: json['descripcion'],
      orden: json['orden'],
      activo: json['activo'] ?? true,
    );
  }
}

class TipoLocalidad {
  final int idTipoLocalidad;
  final String nombre;
  final String? descripcion;
  final int? orden;

  TipoLocalidad({
    required this.idTipoLocalidad,
    required this.nombre,
    this.descripcion,
    this.orden,
  });

  factory TipoLocalidad.fromJson(Map<String, dynamic> json) {
    return TipoLocalidad(
      idTipoLocalidad: json['id_tipo_localidad'],
      nombre: json['nombre'],
      descripcion: json['descripcion'],
      orden: json['orden'],
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
