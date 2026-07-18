class Departamento {
  final int id;
  final String codigoIne;
  final String nombre;

  Departamento({
    required this.id,
    required this.codigoIne,
    required this.nombre,
  });

  factory Departamento.fromJson(Map<String, dynamic> json) {
    return Departamento(
      id: json['id'],
      codigoIne: json['codigo_ine'],
      nombre: json['nombre'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'codigo_ine': codigoIne,
      'nombre': nombre,
    };
  }

  @override
  String toString() => nombre;
}
