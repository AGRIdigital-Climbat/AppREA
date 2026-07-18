import 'dart:convert';

class ReporteOffline {
  final int? idLocal;
  final int? idServer;
  final int usuarioId;
  final int departamentoId;
  final int provinciaId;
  final int municipioId;
  final String comunidad;
  final String fechaEvento;
  final String? horaEvento;
  final int tipoEventoId;
  final double? coordenadaLat;
  final double? coordenadaLon;
  final String? descripcion;
  final int estadoId;
  final List<int>? categorias;
  final List<String>? imagenes;
  final bool sincronizado;
  final bool pendienteEliminacion;
  final bool pendienteActualizacion;
  final DateTime fechaCreacion;
  final DateTime? fechaModificacion;
  final int intentosSync;
  final String? ultimoError;

  ReporteOffline({
    this.idLocal,
    this.idServer,
    required this.usuarioId,
    required this.departamentoId,
    required this.provinciaId,
    required this.municipioId,
    required this.comunidad,
    required this.fechaEvento,
    this.horaEvento,
    required this.tipoEventoId,
    this.coordenadaLat,
    this.coordenadaLon,
    this.descripcion,
    this.estadoId = 1,
    this.categorias,
    this.imagenes,
    this.sincronizado = false,
    this.pendienteEliminacion = false,
    this.pendienteActualizacion = false,
    required this.fechaCreacion,
    this.fechaModificacion,
    this.intentosSync = 0,
    this.ultimoError,
  });

  bool get necesitaSync => !sincronizado || pendienteEliminacion || pendienteActualizacion;

  Map<String, dynamic> toMap() {
    return {
      'id_local': idLocal,
      'id_server': idServer,
      'usuario_id': usuarioId,
      'departamento_id': departamentoId,
      'provincia_id': provinciaId,
      'municipio_id': municipioId,
      'comunidad': comunidad,
      'fecha_evento': fechaEvento,
      'hora_evento': horaEvento,
      'tipo_evento_id': tipoEventoId,
      'coordenada_lat': coordenadaLat,
      'coordenada_lon': coordenadaLon,
      'descripcion': descripcion,
      'estado_id': estadoId,
      'categorias': categorias != null ? jsonEncode(categorias) : null,
      'imagenes': imagenes != null ? jsonEncode(imagenes) : null,
      'sincronizado': sincronizado ? 1 : 0,
      'pendiente_eliminacion': pendienteEliminacion ? 1 : 0,
      'pendiente_actualizacion': pendienteActualizacion ? 1 : 0,
      'fecha_creacion': fechaCreacion.toIso8601String(),
      'fecha_modificacion': fechaModificacion?.toIso8601String(),
      'intentos_sync': intentosSync,
      'ultimo_error': ultimoError,
    };
  }

  factory ReporteOffline.fromMap(Map<String, dynamic> map) {
    return ReporteOffline(
      idLocal: map['id_local'],
      idServer: map['id_server'],
      usuarioId: map['usuario_id'],
      departamentoId: map['departamento_id'],
      provinciaId: map['provincia_id'],
      municipioId: map['municipio_id'],
      comunidad: map['comunidad'],
      fechaEvento: map['fecha_evento'],
      horaEvento: map['hora_evento'],
      tipoEventoId: map['tipo_evento_id'],
      coordenadaLat: map['coordenada_lat'],
      coordenadaLon: map['coordenada_lon'],
      descripcion: map['descripcion'],
      estadoId: map['estado_id'],
      categorias: map['categorias'] != null
          ? List<int>.from(jsonDecode(map['categorias']))
          : null,
      imagenes: map['imagenes'] != null
          ? List<String>.from(jsonDecode(map['imagenes']))
          : null,
      sincronizado: map['sincronizado'] == 1,
      pendienteEliminacion: map['pendiente_eliminacion'] == 1,
      pendienteActualizacion: map['pendiente_actualizacion'] == 1,
      fechaCreacion: DateTime.parse(map['fecha_creacion']),
      fechaModificacion: map['fecha_modificacion'] != null
          ? DateTime.parse(map['fecha_modificacion'])
          : null,
      intentosSync: map['intentos_sync'],
      ultimoError: map['ultimo_error'],
    );
  }

  Map<String, dynamic> toApiFormat() {
    return {
      'id_usuario': usuarioId,
      'id_departamento': departamentoId,
      'id_provincia': provinciaId,
      'id_municipio': municipioId,
      'comunidad': comunidad,
      'fecha_evento': fechaEvento,
      'hora_evento': horaEvento,
      'id_tipo_evento': tipoEventoId,
      'coordenada_lat': coordenadaLat,
      'coordenada_lon': coordenadaLon,
      'descripcion': descripcion,
      'id_estado': estadoId,
      'categorias': categorias,
    };
  }

  ReporteOffline copyWith({
    int? idLocal,
    int? idServer,
    bool? sincronizado,
    bool? pendienteEliminacion,
    bool? pendienteActualizacion,
    DateTime? fechaModificacion,
    int? intentosSync,
    String? ultimoError,
  }) {
    return ReporteOffline(
      idLocal: idLocal ?? this.idLocal,
      idServer: idServer ?? this.idServer,
      usuarioId: usuarioId,
      departamentoId: departamentoId,
      provinciaId: provinciaId,
      municipioId: municipioId,
      comunidad: comunidad,
      fechaEvento: fechaEvento,
      horaEvento: horaEvento,
      tipoEventoId: tipoEventoId,
      coordenadaLat: coordenadaLat,
      coordenadaLon: coordenadaLon,
      descripcion: descripcion,
      estadoId: estadoId,
      categorias: categorias,
      imagenes: imagenes,
      sincronizado: sincronizado ?? this.sincronizado,
      pendienteEliminacion: pendienteEliminacion ?? this.pendienteEliminacion,
      pendienteActualizacion:
          pendienteActualizacion ?? this.pendienteActualizacion,
      fechaCreacion: fechaCreacion,
      fechaModificacion: fechaModificacion ?? this.fechaModificacion,
      intentosSync: intentosSync ?? this.intentosSync,
      ultimoError: ultimoError ?? this.ultimoError,
    );
  }
}
