import '../models/departamento.dart';
import '../models/provincia.dart';
import '../models/municipio.dart';

final mockDepartamentos = [
  Departamento(id: 1, codigoIne: '01', nombre: 'La Paz'),
  Departamento(id: 2, codigoIne: '02', nombre: 'Cochabamba'),
  Departamento(id: 3, codigoIne: '03', nombre: 'Santa Cruz'),
];

final mockProvincias = [
  Provincia(id: 1, codigoIne: '0101', nombre: 'Murillo', idDepartamento: 1),
  Provincia(id: 2, codigoIne: '0102', nombre: 'Cercado', idDepartamento: 1),
  Provincia(id: 3, codigoIne: '0201', nombre: 'Andres Ibañez', idDepartamento: 2),
];

final mockMunicipios = [
  Municipio(id: 1, codigoIne: '010101', nombre: 'La Paz', idDepartamento: 1, idProvincia: 1),
  Municipio(id: 2, codigoIne: '010102', nombre: 'El Alto', idDepartamento: 1, idProvincia: 1),
  Municipio(id: 3, codigoIne: '020101', nombre: 'Cochabamba', idDepartamento: 2, idProvincia: 2),
];
