import 'departamento.dart';

class Provincia {
  final int id;
  final String codigoIne;
  final int? idDepartamento;
  final String nombre;
  final Departamento? departamento;

  Provincia({
    required this.id,
    required this.codigoIne,
    this.idDepartamento,
    required this.nombre,
    this.departamento,
  });

  factory Provincia.fromJson(Map<String, dynamic> json) {
    return Provincia(
      id: json['id'],
      codigoIne: json['codigo_ine'],
      idDepartamento: json['id_departamento'],
      nombre: json['nombre'],
      departamento: json['departamento'] != null
          ? Departamento.fromJson(json['departamento'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'codigo_ine': codigoIne,
      if (idDepartamento != null) 'id_departamento': idDepartamento,
      'nombre': nombre,
    };
  }

  @override
  String toString() => nombre;
}
