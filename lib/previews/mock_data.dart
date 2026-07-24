import '../models/reporte_offline.dart';
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

final mockReporteOfflineStats = ReporteOffline(
  usuarioId: 1,
  departamentoId: 1,
  provinciaId: 1,
  municipioId: 1,
  comunidad: 'Villa Fátima',
  departamentoNombre: 'La Paz',
  provinciaNombre: 'Murillo',
  municipioNombre: 'La Paz',
  fechaEvento: '2026-07-15',
  horaEvento: '14:30',
  tipoEventoId: 1,
  descripcion: 'Inundación por desborde de río en la zona baja de la comunidad.',
  estadoId: 1,
  estadoNombre: 'En revisión',
  categorias: [1, 4],
  sincronizado: true,
  fechaCreacion: DateTime(2026, 7, 15, 12, 0),
);

final mockReporteOfflinePendiente = ReporteOffline(
  usuarioId: 1,
  departamentoId: 1,
  provinciaId: 1,
  municipioId: 2,
  comunidad: 'Ciudad Satélite',
  departamentoNombre: 'La Paz',
  provinciaNombre: 'Murillo',
  municipioNombre: 'El Alto',
  fechaEvento: '2026-07-18',
  horaEvento: '09:15',
  tipoEventoId: 3,
  estadoId: 1,
  categorias: [5, 6],
  sincronizado: false,
  fechaCreacion: DateTime(2026, 7, 18, 10, 0),
  intentosSync: 0,
);

final mockReporteOfflineError = ReporteOffline(
  usuarioId: 1,
  departamentoId: 2,
  provinciaId: 2,
  municipioId: 3,
  comunidad: 'Zona Central',
  departamentoNombre: 'Cochabamba',
  provinciaNombre: 'Cercado',
  municipioNombre: 'Cochabamba',
  fechaEvento: '2026-07-10',
  tipoEventoId: 5,
  estadoId: 1,
  sincronizado: false,
  fechaCreacion: DateTime(2026, 7, 10, 8, 0),
  intentosSync: 20,
  ultimoError: 'Error de conexión',
);
