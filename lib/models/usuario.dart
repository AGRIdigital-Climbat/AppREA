import 'departamento.dart';
import 'provincia.dart';
import 'municipio.dart';

class Usuario {
  final int idUsuario;
  final String usuario;
  final String nombre;
  final String? celular;
  final String? carnet;
  final String? comunidad;
  final int? idDepartamento;
  final int? idProvincia;
  final int? idMunicipio;
  final int idRol;
  final bool? activo;
  final Departamento? departamento;
  final Provincia? provincia;
  final Municipio? municipio;
  final Rol? rol;

  Usuario({
    required this.idUsuario,
    required this.usuario,
    required this.nombre,
    this.celular,
    this.carnet,
    this.comunidad,
    this.idDepartamento,
    this.idProvincia,
    this.idMunicipio,
    required this.idRol,
    this.activo,
    this.departamento,
    this.provincia,
    this.municipio,
    this.rol,
  });

  factory Usuario.fromJson(Map<String, dynamic> json) {
    return Usuario(
      idUsuario: json['id_usuario'],
      usuario: json['usuario'],
      nombre: json['nombre'],
      celular: json['celular'],
      carnet: json['carnet'],
      comunidad: json['comunidad'],
      idDepartamento: json['id_departamento'],
      idProvincia: json['id_provincia'],
      idMunicipio: json['id_municipio'],
      idRol: json['id_rol'],
      activo: json['activo'],
      departamento: json['departamento'] != null
          ? Departamento.fromJson(json['departamento'])
          : null,
      provincia: json['provincia'] != null
          ? Provincia.fromJson(json['provincia'])
          : null,
      municipio: json['municipio'] != null
          ? Municipio.fromJson(json['municipio'])
          : null,
      rol: json['rol'] != null ? Rol.fromJson(json['rol']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id_usuario': idUsuario,
      'usuario': usuario,
      'nombre': nombre,
      'celular': celular,
      'carnet': carnet,
      'comunidad': comunidad,
      'id_departamento': idDepartamento,
      'id_provincia': idProvincia,
      'id_municipio': idMunicipio,
      'id_rol': idRol,
      'activo': activo,
    };
  }
}

class Rol {
  final int idRol;
  final String nombre;
  final String? descripcion;
  final int jerarquia;

  Rol({
    required this.idRol,
    required this.nombre,
    this.descripcion,
    required this.jerarquia,
  });

  factory Rol.fromJson(Map<String, dynamic> json) {
    return Rol(
      idRol: json['id_rol'],
      nombre: json['nombre'],
      descripcion: json['descripcion'],
      jerarquia: json['jerarquia'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id_rol': idRol,
      'nombre': nombre,
      'descripcion': descripcion,
      'jerarquia': jerarquia,
    };
  }
}

class TokenResponse {
  final String accessToken;
  final String tokenType;
  final int userId;
  final String usuario;
  final String nombre;
  final int? idRol;
  final String? rol;

  TokenResponse({
    required this.accessToken,
    required this.tokenType,
    required this.userId,
    required this.usuario,
    required this.nombre,
    this.idRol,
    this.rol,
  });

  factory TokenResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    return TokenResponse(
      accessToken: data['access_token'],
      tokenType: data['token_type'],
      userId: data['user_id'],
      usuario: data['usuario'],
      nombre: data['nombre'],
      idRol: data['id_rol'],
      rol: data['rol'],
    );
  }
}
