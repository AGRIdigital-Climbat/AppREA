import 'dart:convert';

/// Envoltorio para persistir una fila de sección en el schema V2.
/// El modelo de dominio real (EdanDanoVial, EdanImpactoPoblacion, etc.) se
/// serializa como JSON en [datosJson]; la identidad permanente es
/// [uuidRegistro].
class EdanRegistroV2 {
  final String uuidRegistro;
  final String uuidEdanLocalidad;
  final String tipo; // 14 literales de EdanSeccionesRegistry.rutasV2Todas()
  String datosJson;
  String? fechaModificacionLocal;
  EdanSyncEstado estadoSync;

  EdanRegistroV2({
    required this.uuidRegistro,
    required this.uuidEdanLocalidad,
    required this.tipo,
    required this.datosJson,
    this.fechaModificacionLocal,
    this.estadoSync = EdanSyncEstado.confirmado,
  });

  Map<String, dynamic> toMap() => {
        'uuid_registro': uuidRegistro,
        'uuid_edan_localidad': uuidEdanLocalidad,
        'tipo': tipo,
        'datos_json': datosJson,
        'fecha_modificacion_local': fechaModificacionLocal,
        'estado_sync': estadoSync.name,
      };

  factory EdanRegistroV2.fromMap(Map<String, dynamic> m) => EdanRegistroV2(
        uuidRegistro: m['uuid_registro'] as String,
        uuidEdanLocalidad: m['uuid_edan_localidad'] as String,
        tipo: m['tipo'] as String,
        datosJson: m['datos_json'] as String,
        fechaModificacionLocal: m['fecha_modificacion_local'] as String?,
        estadoSync: _estadoFromString(m['estado_sync'] as String?),
      );

  Map<String, dynamic> datosComoJson() =>
      jsonDecode(datosJson) as Map<String, dynamic>;

  static EdanSyncEstado _estadoFromString(String? value) {
    return EdanSyncEstado.values.firstWhere(
      (e) => e.name == value,
      orElse: () => EdanSyncEstado.confirmado,
    );
  }
}

/// Modelo para el detalle 1:N de viviendas (`edan_localidades_viviendas`).
class EdanVivienda {
  String? uuidRegistro;
  String? uuidDanoVivienda;
  EdanViviendaTipo tipoDano;
  double coordenadaLat;
  double coordenadaLon;
  String? fotografia; // path local o URL servidor
  String? fechaModificacionLocal;

  EdanVivienda({
    this.uuidRegistro,
    this.uuidDanoVivienda,
    this.tipoDano = EdanViviendaTipo.parcial,
    this.coordenadaLat = 0.0,
    this.coordenadaLon = 0.0,
    this.fotografia,
    this.fechaModificacionLocal,
  });

  Map<String, dynamic> toJson() => {
        'uuid_registro': uuidRegistro,
        'uuid_dano_vivienda': uuidDanoVivienda,
        // El case canónico en BD y en la API es MAYÚSCULA (CHECK de la tabla
        // `viviendas` y `_aplicarViviendaPull`); el enum es minúscula.
        'tipo_dano': tipoDano.name.toUpperCase(),
        'coordenada_lat': coordenadaLat,
        'coordenada_lon': coordenadaLon,
        'fotografia': fotografia,
        'fecha_modificacion_local': fechaModificacionLocal,
      };

  factory EdanVivienda.fromJson(Map<String, dynamic> json) => EdanVivienda(
        uuidRegistro: json['uuid_registro'] as String?,
        uuidDanoVivienda: json['uuid_dano_vivienda'] as String?,
        tipoDano: _tipoFromString(json['tipo_dano'] as String?),
        coordenadaLat: (json['coordenada_lat'] as num?)?.toDouble() ?? 0.0,
        coordenadaLon: (json['coordenada_lon'] as num?)?.toDouble() ?? 0.0,
        fotografia: json['fotografia'] as String?,
        fechaModificacionLocal: json['fecha_modificacion_local'] as String?,
      );

  static EdanViviendaTipo _tipoFromString(String? value) {
    final normalizado = value?.trim().toUpperCase();
    return EdanViviendaTipo.values.firstWhere(
      (e) => e.name.toUpperCase() == normalizado,
      orElse: () => EdanViviendaTipo.parcial,
    );
  }
}

enum EdanViviendaTipo { total, parcial }

enum EdanSyncEstado {
  pendiente,
  subiendo,
  confirmado,
  conflicto,
  rechazado,
}

/// Resultado de intentar enviar un formulario al servidor.
class EdanEnvioResultado {
  final bool exito;
  final String? uuidEdanLocalidad;
  final String? error;
  final int? httpStatus;
  final bool conflicto;

  const EdanEnvioResultado({
    required this.exito,
    this.uuidEdanLocalidad,
    this.error,
    this.httpStatus,
    this.conflicto = false,
  });

  factory EdanEnvioResultado.ok(String uuid) =>
      EdanEnvioResultado(exito: true, uuidEdanLocalidad: uuid);

  factory EdanEnvioResultado.error(String error, {int? status, bool conflicto = false}) =>
      EdanEnvioResultado(
        exito: false,
        error: error,
        httpStatus: status,
        conflicto: conflicto,
      );
}

/// Ítem de la cola de sincronización (`cola_sincronizacion`).
class EdanColaItem {
  final int? id;
  final String tabla;
  final String uuidRegistro;
  final String accion; // 'C' | 'U' | 'D'
  String estado;
  int intentos;
  String? ultimoError;
  String? fechaProximoIntento;
  String? fechaRegistro;

  /// Coordenadas para ejecutar un `D` sin la fila local (p. ej.
  /// `{uuid_edan_localidad, tipo}` en filas o
  /// `{uuid_edan_localidad, uuid_dano_vivienda}` en viviendas). Sin ellas,
  /// un borrado cuya fila ya no existe no puede llamar al servidor y se
  /// purga (el DELETE jamás viajaría, como se verificó en dispositivo).
  Map<String, dynamic>? payloadJson;

  EdanColaItem({
    this.id,
    required this.tabla,
    required this.uuidRegistro,
    required this.accion,
    this.estado = 'pendiente',
    this.intentos = 0,
    this.ultimoError,
    this.fechaProximoIntento,
    this.fechaRegistro,
    this.payloadJson,
  });

  factory EdanColaItem.fromMap(Map<String, dynamic> m) {
    Map<String, dynamic>? payload;
    final crudo = m['payload_json'];
    if (crudo is String && crudo.isNotEmpty) {
      try {
        final dec = jsonDecode(crudo);
        if (dec is Map<String, dynamic>) payload = dec;
      } catch (_) {}
    }
    return EdanColaItem(
      id: m['id'] as int?,
      tabla: m['tabla'] as String,
      uuidRegistro: m['uuid_registro'] as String,
      accion: m['accion'] as String,
      estado: m['estado'] as String,
      intentos: (m['intentos'] as num?)?.toInt() ?? 0,
      ultimoError: m['ultimo_error'] as String?,
      fechaProximoIntento: m['fecha_proximo_intento'] as String?,
      fechaRegistro: m['fecha_registro'] as String?,
      payloadJson: payload,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'tabla': tabla,
        'uuid_registro': uuidRegistro,
        'accion': accion,
        'estado': estado,
        'intentos': intentos,
        'ultimo_error': ultimoError,
        'fecha_proximo_intento': fechaProximoIntento,
        'fecha_registro': fechaRegistro,
      };
}

/// Ítem de la cola de fotos (`cola_fotos`).
class EdanColaFotoItem {
  final String uuidFotografia;
  final String rutaLocal;
  final String? tipoEntidad;
  final String? uuidRegistro;
  final String? sha256;
  String estado;
  int intentos;
  String? ultimoError;
  String? fechaProximoIntento;

  EdanColaFotoItem({
    required this.uuidFotografia,
    required this.rutaLocal,
    this.tipoEntidad,
    this.uuidRegistro,
    this.sha256,
    this.estado = 'pendiente',
    this.intentos = 0,
    this.ultimoError,
    this.fechaProximoIntento,
  });

  factory EdanColaFotoItem.fromMap(Map<String, dynamic> m) => EdanColaFotoItem(
        uuidFotografia: m['uuid_fotografia'] as String,
        rutaLocal: m['ruta_local'] as String,
        tipoEntidad: m['tipo_entidad'] as String?,
        uuidRegistro: m['uuid_registro'] as String?,
        sha256: m['sha256'] as String?,
        estado: m['estado'] as String,
        intentos: (m['intentos'] as num?)?.toInt() ?? 0,
        ultimoError: m['ultimo_error'] as String?,
        fechaProximoIntento: m['fecha_proximo_intento'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'uuid_fotografia': uuidFotografia,
        'ruta_local': rutaLocal,
        'tipo_entidad': tipoEntidad,
        'uuid_registro': uuidRegistro,
        'sha256': sha256,
        'estado': estado,
        'intentos': intentos,
        'ultimo_error': ultimoError,
        'fecha_proximo_intento': fechaProximoIntento,
      };
}
