import 'departamento.dart';
import 'provincia.dart';

class Municipio {
  final int id;
  final String codigoIne;
  final int idDepartamento;
  final int idProvincia;
  final String nombre;
  final Departamento? departamento;
  final Provincia? provincia;

  Municipio({
    required this.id,
    required this.codigoIne,
    required this.idDepartamento,
    required this.idProvincia,
    required this.nombre,
    this.departamento,
    this.provincia,
  });

  factory Municipio.fromJson(Map<String, dynamic> json) {
    return Municipio(
      id: json['id'],
      codigoIne: json['codigo_ine'],
      idDepartamento: json['id_departamento'],
      idProvincia: json['id_provincia'],
      nombre: json['nombre'],
      departamento: json['departamento'] != null
          ? Departamento.fromJson(json['departamento'])
          : null,
      provincia: json['provincia'] != null
          ? Provincia.fromJson(json['provincia'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'codigo_ine': codigoIne,
      'id_departamento': idDepartamento,
      'id_provincia': idProvincia,
      'nombre': nombre,
    };
  }

  @override
  String toString() => nombre;
}
