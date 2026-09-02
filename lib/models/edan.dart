import 'dart:convert';

import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';
import 'usuario.dart';
import 'id_seccion_helper.dart';

/// Garantiza que un ítem tenga id_seccion. Si [id] es null o vacío,
/// genera uno nuevo con el [prefijo] dado. Esto evita que el backend haga
/// INSERT puro (duplicación) en vez de UPSERT.
String requireIdSeccion(String? id, String prefijo) {
  if (id != null && id.isNotEmpty) return id;
  return generarIdSeccion(prefijo);
}

/// Devuelve el idSeccion de un ítem de sección 1:N (genérico).
String? idSeccionDe(dynamic item) {
  if (item is EdanDanoInfraPublica) return item.idSeccion;
  if (item is EdanEstablecimientoSalud) return item.idSeccion;
  if (item is EdanDanoVial) return item.idSeccion;
  if (item is EdanDanoUnidadEducativa) return item.idSeccion;
  if (item is EdanDanoVivienda) return item.idSeccion;
  if (item is EdanDanoAgricultura) return item.idSeccion;
  if (item is EdanDanoPecuario) return item.idSeccion;
  if (item is EdanInfraProductiva) return item.idSeccion;
  if (item is EdanServicioBasicoDetalle) return item.idSeccion;
  if (item is EdanGrupoVulnerable) return item.idSeccion;
  if (item is EdanImpactoPoblacion) return item.idSeccion;
  return null;
}

enum UgrLocalidadEstado {
  borrador,
  enviadoUgr,
  enRevisionUgr,
  aprobadoUgr,
  rechazadoUgr,
  aprobadoAjuste,
}

extension UgrLocalidadEstadoX on UgrLocalidadEstado {
  int get id => switch (this) {
        UgrLocalidadEstado.borrador => 1,
        UgrLocalidadEstado.enviadoUgr => 2,
        UgrLocalidadEstado.aprobadoUgr => 3,
        UgrLocalidadEstado.rechazadoUgr => 4,
        UgrLocalidadEstado.aprobadoAjuste => 5,
        UgrLocalidadEstado.enRevisionUgr => 6,
      };

  String get label {
    switch (this) {
      case UgrLocalidadEstado.borrador:
        return 'Borrador';
      case UgrLocalidadEstado.enviadoUgr:
        return 'Enviado UGR';
      case UgrLocalidadEstado.enRevisionUgr:
        return 'En revisión UGR';
      case UgrLocalidadEstado.aprobadoUgr:
        return 'Aprobado UGR';
      case UgrLocalidadEstado.rechazadoUgr:
        return 'Rechazado UGR';
      case UgrLocalidadEstado.aprobadoAjuste:
        return 'Aprobado con ajuste';
    }
  }

  Color get color {
    switch (this) {
      case UgrLocalidadEstado.borrador:
        return AppColors.pending;
      case UgrLocalidadEstado.enviadoUgr:
        return AppColors.primary;
      case UgrLocalidadEstado.aprobadoUgr:
        return AppColors.aprobado;
      case UgrLocalidadEstado.rechazadoUgr:
        return AppColors.rechazado;
      case UgrLocalidadEstado.aprobadoAjuste:
        return AppColors.completed;
      case UgrLocalidadEstado.enRevisionUgr:
        return AppColors.pending;
    }
  }

  IconData get icon {
    switch (this) {
      case UgrLocalidadEstado.borrador:
        return Icons.edit_note;
      case UgrLocalidadEstado.enviadoUgr:
        return Icons.send;
      case UgrLocalidadEstado.aprobadoUgr:
        return Icons.verified;
      case UgrLocalidadEstado.rechazadoUgr:
        return Icons.cancel;
      case UgrLocalidadEstado.aprobadoAjuste:
        return Icons.check_circle;
      case UgrLocalidadEstado.enRevisionUgr:
        return Icons.visibility;
    }
  }

  static UgrLocalidadEstado fromId(int? id) {
    return switch (id) {
      1 => UgrLocalidadEstado.borrador,
      2 => UgrLocalidadEstado.enviadoUgr,
      3 => UgrLocalidadEstado.aprobadoUgr,
      4 => UgrLocalidadEstado.rechazadoUgr,
      5 => UgrLocalidadEstado.aprobadoAjuste,
      6 => UgrLocalidadEstado.enRevisionUgr,
      _ => UgrLocalidadEstado.borrador,
    };
  }

  static final Map<int, String> _descripcionesCache = {};

  static void updateDescripciones(List<Map<String, dynamic>> data) {
    _descripcionesCache.clear();
    for (final item in data) {
      final id = item['id_edan_localidad_estado'] as int?;
      final desc = item['descripcion'] as String?;
      if (id != null && desc != null) {
        _descripcionesCache[id] = desc;
      }
    }
  }

  String get descripcion {
    return _descripcionesCache[id] ?? _fallbackDescripcion;
  }

  String get _fallbackDescripcion {
    switch (this) {
      case UgrLocalidadEstado.borrador:
        return 'EDAN en proceso de construcción en el lugar.';
      case UgrLocalidadEstado.enviadoUgr:
        return 'EDAN completo. Revise la información registrada.';
      case UgrLocalidadEstado.enRevisionUgr:
        return 'EDAN abierto por el UGR para verificar y validar la información.';
      case UgrLocalidadEstado.aprobadoUgr:
        return 'EDAN validado y aprobado por el UGR.';
      case UgrLocalidadEstado.rechazadoUgr:
        return 'EDAN rechazado por el UGR. Revise las observaciones.';
      case UgrLocalidadEstado.aprobadoAjuste:
        return 'EDAN aprobado por el UGR con ajustes o correcciones.';
    }
  }
}

class EdanGrupoEtario {
  String? idSeccion;
  String rango;
  int fallecidos;
  int heridos;
  int desaparecidos;
  String observaciones;

  /// Marca de selección explícita del usuario en el formulario. Si el usuario
  /// marcó el check, se conserva aunque los campos numéricos queden vacíos.
  bool marcado;

  /// id_grupo_etario explícito (catálogo `edan.grupo_etario` de la API v2).
  /// Si es nulo, se resuelve por el nombre del rango (compatibilidad v1).
  int? idGrupoEtarioCatalogo;

  EdanGrupoEtario({
    this.idSeccion,
    this.rango = '',
    this.fallecidos = 0,
    this.heridos = 0,
    this.desaparecidos = 0,
    this.observaciones = '',
    this.marcado = false,
    this.idGrupoEtarioCatalogo,
  });

  factory EdanGrupoEtario.fromJson(Map<String, dynamic> json) {
    final fallecidos = _toInt(json['fallecidos']);
    final heridos = _toInt(json['heridos']);
    final desaparecidos = _toInt(json['desaparecidos']);
    final marcadoJson = json['marcado'];
    return EdanGrupoEtario(
      idSeccion: requireIdSeccion(json['id_seccion']?.toString(), 'im'),
      rango: _str(json['rango'] ?? json['grupo']),
      fallecidos: fallecidos,
      heridos: heridos,
      desaparecidos: desaparecidos,
      observaciones: _str(json['observaciones']),
      marcado: marcadoJson is bool
          ? marcadoJson
          : fallecidos > 0 || heridos > 0 || desaparecidos > 0,
      idGrupoEtarioCatalogo: _jsonIntFk(json['id_grupo_etario']),
    );
  }

  /// Catálogo `edan.grupo_etario` de la API v2 (fuente de verdad).
  /// Si el grupo vino del catálogo se usa su id; si no, se resuelve por el
  /// nombre del rango (mapeo canónico v1:
  /// 1 = 0-5 años, 2 = escolar 6-18, 3 = adulto 19-60, 4 = adulto mayor 60+).
  int? get idGrupoEtario =>
      idGrupoEtarioCatalogo ?? EdanGrupoEtario.resolverIdGrupoEtario(rango);

  static int? resolverIdGrupoEtario(String rango) {
    final r = rango.toLowerCase();
    if (r.contains('0-5') || r.contains('niña')) return 1;
    if (r.contains('6-18') || r.contains('escolar')) return 2;
    if (r.contains('19-60') || r.contains('adulto de')) return 3;
    if (r.contains('60') || r.contains('mayor')) return 4;
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id_seccion': idSeccion,
        if (idGrupoEtario != null) 'id_grupo_etario': idGrupoEtario,
        'rango': rango,
        'fallecidos': fallecidos,
        'heridos': heridos,
        'desaparecidos': desaparecidos,
        'observaciones': observaciones,
        'marcado': marcado,
      };

  /// JSON para la API: igual que [toJson] pero SIN `marcado` (campo interno
  /// de la UI que no debe enviarse al servidor).
  Map<String, dynamic> toApiJson() => {
        'id_seccion': idSeccion,
        if (idGrupoEtario != null) 'id_grupo_etario': idGrupoEtario,
        'rango': rango,
        'fallecidos': fallecidos,
        'heridos': heridos,
        'desaparecidos': desaparecidos,
        'observaciones': observaciones,
      };

  bool get tieneDatos => fallecidos > 0 || heridos > 0 || desaparecidos > 0;
}

class EdanImpactoPoblacion {
  String? idSeccion;
  String grupoEtario;
  int fallecidos;
  int heridos;
  int desaparecidos;
  String observaciones;
  List<EdanGrupoEtario> gruposEtarios;

  EdanImpactoPoblacion({
    this.idSeccion,
    this.grupoEtario = '',
    this.fallecidos = 0,
    this.heridos = 0,
    this.desaparecidos = 0,
    this.observaciones = '',
    List<EdanGrupoEtario>? gruposEtarios,
  }) : gruposEtarios = gruposEtarios ?? [
          EdanGrupoEtario(idSeccion: generarIdSeccion('im'), rango: 'Niño (a) 0-5 años'),
          EdanGrupoEtario(idSeccion: generarIdSeccion('im'), rango: 'Escolar de 6-18 años'),
          EdanGrupoEtario(idSeccion: generarIdSeccion('im'), rango: 'Adulto de 19-60 años'),
          EdanGrupoEtario(idSeccion: generarIdSeccion('im'), rango: 'Adulto mayor de 60 años adelante'),
        ];

  factory EdanImpactoPoblacion.fromJson(Map<String, dynamic> json) {
    final grupos = json['grupos_etarios'] ?? json['gruposEtarios'];
    return EdanImpactoPoblacion(
      idSeccion: requireIdSeccion(json['id_seccion']?.toString(), 'im'),
      grupoEtario: _str(json['grupo_etario'] ?? json['grupoEtario']),
      fallecidos: _toInt(json['fallecidos']),
      heridos: _toInt(json['heridos']),
      desaparecidos: _toInt(json['desaparecidos']),
      observaciones: _str(json['observaciones']),
      gruposEtarios: grupos is List
          ? grupos
              .map((g) => EdanGrupoEtario.fromJson(
                  g is Map ? Map<String, dynamic>.from(g) : {}))
              .toList()
          : null,
    );
  }

  /// Construye la lista de grupos etarios desde el catálogo v2
  /// (`edan/grupo-etario`). Cada grupo arrastra su `id_grupo_etario` real.
  /// Si el catálogo está vacío, usa los rangos por defecto v1.
  static List<EdanGrupoEtario> gruposDesdeCatalogo(List<dynamic> catalogo) {
    if (catalogo.isEmpty) return EdanImpactoPoblacion().gruposEtarios;
    return catalogo.map<EdanGrupoEtario>((c) {
      final id = c is Map ? (c['id_grupo_etario'] ?? c['id']) : null;
      final nombre = c is Map ? (c['nombre'] ?? '') : '';
      return EdanGrupoEtario(
        idSeccion: generarIdSeccion('im'),
        rango: nombre.toString(),
        idGrupoEtarioCatalogo: id is int ? id : int.tryParse('$id'),
      );
    }).toList();
  }

  Map<String, dynamic> toJson() => {
        'id_seccion': idSeccion,
        'grupo_etario': grupoEtario,
        'fallecidos': fallecidos,
        'heridos': heridos,
        'desaparecidos': desaparecidos,
        'observaciones': observaciones,
        'grupos_etarios': gruposEtarios.map((g) => g.toJson()).toList(),
      };

  bool get tieneDatosGlobales =>
      fallecidos > 0 || heridos > 0 || desaparecidos > 0;
}

class EdanNecesidadPrimeraRespuesta {
  bool busqueda;
  bool salvamento;
  bool evacuacion;
  String observaciones;
  String? idSeccion;

  EdanNecesidadPrimeraRespuesta({
    this.busqueda = false,
    this.salvamento = false,
    this.evacuacion = false,
    this.observaciones = '',
    String? idSeccion,
  }) : idSeccion = idSeccion ?? generarIdSeccion('nr');

  factory EdanNecesidadPrimeraRespuesta.fromJson(Map<String, dynamic> json) {
    return EdanNecesidadPrimeraRespuesta(
      busqueda: _toBool(json['busqueda']),
      salvamento: _toBool(json['salvamento']),
      evacuacion: _toBool(json['evacuacion']),
      observaciones: _str(json['observaciones']),
      idSeccion: _str(json['id_seccion']).isEmpty
          ? generarIdSeccion('nr')
          : json['id_seccion'].toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'busqueda': busqueda,
        'salvamento': salvamento,
        'evacuacion': evacuacion,
        'observaciones': observaciones,
        'id_seccion': idSeccion,
      };

  bool get algunaSeleccionada => busqueda || salvamento || evacuacion;

  /// Regla única 1:1: la sección cuenta si algún checkbox es true O algún
  /// texto (observaciones) está lleno. Espejo de la condición del servidor.
  bool get tieneDatos =>
      algunaSeleccionada || observaciones.trim().isNotEmpty;
}

class EdanFoto {
  String ruta;
  double latitud;
  double longitud;
  double precision;
  DateTime fecha;

  EdanFoto({
    this.ruta = '',
    this.latitud = 0,
    this.longitud = 0,
    this.precision = 0,
    DateTime? fecha,
  }) : fecha = fecha ?? DateTime.now();

  factory EdanFoto.fromJson(Map<String, dynamic> json) {
    return EdanFoto(
      ruta: _str(json['ruta']),
      latitud: (json['latitud'] ?? 0).toDouble(),
      longitud: (json['longitud'] ?? 0).toDouble(),
      precision: (json['precision'] ?? 0).toDouble(),
      fecha: json['fecha'] != null ? DateTime.tryParse(json['fecha']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'ruta': ruta,
        'latitud': latitud,
        'longitud': longitud,
        'precision': precision,
        'fecha': fecha.toIso8601String(),
      };
}

class EdanEstablecimientoSalud with EdanFotoHolder {
  String? idSeccion;
  String nombreEstablecimiento;
  String comunidad;
  String nivelAtencion;
  bool danoParcial;
  bool danoTotal;
  int medicosAfectados;
  int enfermerasAfectados;
  int otrosAfectados;
  List<EdanFoto> fotos;
  @override
  String? fotografia;
  @override
  double coordenadaLat;
  @override
  double coordenadaLon;

  EdanEstablecimientoSalud({
    this.idSeccion,
    this.nombreEstablecimiento = '',
    this.comunidad = '',
    this.nivelAtencion = '',
    this.danoParcial = false,
    this.danoTotal = false,
    this.medicosAfectados = 0,
    this.enfermerasAfectados = 0,
    this.otrosAfectados = 0,
    List<EdanFoto>? fotos,
    this.fotografia,
    this.coordenadaLat = 0,
    this.coordenadaLon = 0,
  }) : fotos = fotos ?? [];

  factory EdanEstablecimientoSalud.fromJson(Map<String, dynamic> json) {
    final fotosRaw = json['fotos'];
    return EdanEstablecimientoSalud(
      idSeccion: requireIdSeccion(json['id_seccion']?.toString(), 'es'),
      nombreEstablecimiento: _str(json['nombre_establecimiento'] ??
          json['nombreEstablecimiento']),
      comunidad: _str(json['comunidad']),
      nivelAtencion: _str(json['nivel_atencion'] ?? json['nivelAtencion']),
      danoParcial: _toBool(json['dano_parcial'] ?? json['danoParcial']),
      danoTotal: _toBool(json['dano_total'] ?? json['danoTotal']),
      medicosAfectados: _toInt(json['medicos_afectados'] ?? json['medicosAfectados']),
      enfermerasAfectados: _toInt(json['enfermeras_afectados'] ?? json['enfermerasAfectados']),
      otrosAfectados: _toInt(json['otros_afectados'] ?? json['otrosAfectados']),
      fotos: fotosRaw is List
          ? fotosRaw.map((f) => EdanFoto.fromJson(f is Map ? Map<String, dynamic>.from(f) : {})).toList()
          : [],
      fotografia: json['fotografia'],
      coordenadaLat: _toDouble(json['coordenada_lat'] ?? json['coordenadaLat']),
      coordenadaLon: _toDouble(json['coordenada_lon'] ?? json['coordenadaLon']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id_seccion': idSeccion,
        'nombre_establecimiento': nombreEstablecimiento,
        'comunidad': comunidad,
        'nivel_atencion': nivelAtencion,
        'dano_parcial': danoParcial,
        'dano_total': danoTotal,
        'medicos_afectados': medicosAfectados,
        'enfermeras_afectadas': enfermerasAfectados,
        'otros_afectados': otrosAfectados,
        'fotos': fotos.map((f) => f.toJson()).toList(),
        'fotografia': fotografia,
        'coordenada_lat': coordenadaLat,
        'coordenada_lon': coordenadaLon,
      };

  /// Serialización alineada al schema EstablecimientoSalud de la API.
  /// NO incluye fotografia: las fotos se suben vía con-foto (POST dedicado).
  Map<String, dynamic> toApiJson() => {
        'id_seccion': idSeccion,
        'nombre_establecimiento': nombreEstablecimiento,
        'comunidad': comunidad,
        'nivel_atencion': nivelAtencion,
        'dano_parcial': danoParcial,
        'dano_total': danoTotal,
        'medicos_afectados': medicosAfectados,
        'enfermeras_afectadas': enfermerasAfectados,
        'otros_afectados': otrosAfectados,
        'coordenada_lat': coordenadaLat,
        'coordenada_lon': coordenadaLon,
      };

  Map<String, dynamic> toFotoData(EdanFoto foto) => {
        ...toApiJson(),
        'coordenada_lat': foto.latitud,
        'coordenada_lon': foto.longitud,
      };
}

class EdanNecesidadSalud {
  bool botiquines;
  int numeroPersonas;
  String otrasNecesidades;
  String observaciones;
  String? idSeccion;

  EdanNecesidadSalud({
    this.botiquines = false,
    this.numeroPersonas = 0,
    this.otrasNecesidades = '',
    this.observaciones = '',
    String? idSeccion,
  }) : idSeccion = idSeccion ?? generarIdSeccion('ns');

  factory EdanNecesidadSalud.fromJson(Map<String, dynamic> json) {
    return EdanNecesidadSalud(
      botiquines: _toBool(json['botiquines']),
      numeroPersonas: _toInt(json['numero_personas'] ??
          json['numeroPersonas'] ??
          json['atencion_inmediata'] ??
          json['atencionInmediata']),
      otrasNecesidades: _str(json['otras_necesidades'] ?? json['otrasNecesidades']),
      observaciones: _str(json['observaciones']),
      idSeccion: _str(json['id_seccion']).isEmpty
          ? generarIdSeccion('ns')
          : json['id_seccion'].toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'botiquines': botiquines,
        'numero_personas': numeroPersonas,
        'otras_necesidades': otrasNecesidades,
        'observaciones': observaciones,
        'id_seccion': idSeccion,
      };

  Map<String, dynamic> toApiJson() => {
        'botiquines': botiquines,
        'numero_personas': numeroPersonas,
        'otras_necesidades': otrasNecesidades,
        'observaciones': observaciones,
        'id_seccion': idSeccion,
      };
  bool get algunaSeleccionada => botiquines || numeroPersonas > 0;

  /// Regla única 1:1: la sección cuenta si algún checkbox es true O algún
  /// texto (otrasNecesidades/observaciones) está lleno. Espejo del servidor.
  bool get tieneDatos =>
      algunaSeleccionada ||
      otrasNecesidades.trim().isNotEmpty ||
      observaciones.trim().isNotEmpty;
}

class EdanDanoVial with EdanFotoHolder {
  String? idSeccion;
  String viaPuente;
  String tramo;
  bool danoParcial;
  bool danoTotal;
  double kmDanio;
  String necesidadesInmediatas;
  String observaciones;
  List<EdanFoto> fotos;
  @override
  String? fotografia;
  @override
  double coordenadaLat;
  @override
  double coordenadaLon;

  EdanDanoVial({
    this.idSeccion,
    this.viaPuente = '',
    this.tramo = '',
    this.danoParcial = false,
    this.danoTotal = false,
    this.kmDanio = 0,
    this.necesidadesInmediatas = '',
    this.observaciones = '',
    List<EdanFoto>? fotos,
    this.fotografia,
    this.coordenadaLat = 0,
    this.coordenadaLon = 0,
  }) : fotos = fotos ?? [];

  factory EdanDanoVial.fromJson(Map<String, dynamic> json) {
    final fotosRaw = json['fotos'];
    return EdanDanoVial(
      idSeccion: requireIdSeccion(json['id_seccion']?.toString(), 'dv'),
      viaPuente: _str(json['via_puente'] ?? json['viaPuente']),
      tramo: _str(json['tramo']),
      danoParcial: _toBool(json['dano_parcial'] ?? json['danoParcial']),
      danoTotal: _toBool(json['dano_total'] ?? json['danoTotal']),
      kmDanio: _toDouble(json['km_danio'] ?? json['kmDanio']),
      necesidadesInmediatas: _str(json['necesidades_inmediatas'] ??
          json['necesidadesInmediatas']),
      observaciones: _str(json['observaciones']),
      fotos: fotosRaw is List
          ? fotosRaw.map((f) => EdanFoto.fromJson(f is Map ? Map<String, dynamic>.from(f) : {})).toList()
          : [],
      fotografia: json['fotografia'],
      coordenadaLat: _toDouble(json['coordenada_lat'] ?? json['coordenadaLat']),
      coordenadaLon: _toDouble(json['coordenada_lon'] ?? json['coordenadaLon']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id_seccion': idSeccion,
        'via_puente': viaPuente,
        'tramo': tramo,
        'dano_parcial': danoParcial,
        'dano_total': danoTotal,
        'km_danio': kmDanio,
        'necesidades_inmediatas': necesidadesInmediatas,
        'observaciones': observaciones,
        'fotos': fotos.map((f) => f.toJson()).toList(),
        'fotografia': fotografia,
        'coordenada_lat': coordenadaLat,
        'coordenada_lon': coordenadaLon,
      };

  /// Serialización alineada al schema DanoVial de la API: la UI guarda
  /// viaPuente ('Carretera'/'Camino'/'Túnel'/'Puente') y la API espera dos
  /// booleanos via/puente. Carretera, Camino y Túnel se serializan como via.
  /// NO incluye fotografia: las fotos se suben vía con-foto (POST dedicado).
  Map<String, dynamic> toApiJson() {
    final vp = viaPuente.trim().toLowerCase();
    return {
      'id_seccion': idSeccion,
      'via': vp == 'vía' || vp == 'via' || vp == 'carretera' || vp == 'camino' || vp == 'túnel' || vp == 'tunel',
      'puente': vp == 'puente',
      'tramo': tramo,
      'dano_parcial': danoParcial,
      'dano_total': danoTotal,
      'km_danio': kmDanio,
      'necesidades_inmediatas': necesidadesInmediatas,
      'observaciones': observaciones,
      'coordenada_lat': coordenadaLat,
      'coordenada_lon': coordenadaLon,
    };
  }

  Map<String, dynamic> toFotoData(EdanFoto foto) => {
        ...toApiJson(),
        'coordenada_lat': foto.latitud,
        'coordenada_lon': foto.longitud,
      };
}

class EdanDanoInfraPublica with EdanFotoHolder {
  String? idSeccion;
  String comunidad;
  String tipoEstructura;
  bool danoParcial;
  bool danoTotal;
  String observaciones;
  List<EdanFoto> fotos;
  @override
  String? fotografia;
  @override
  double coordenadaLat;
  @override
  double coordenadaLon;

  EdanDanoInfraPublica({
    this.idSeccion,
    this.comunidad = '',
    this.tipoEstructura = '',
    this.danoParcial = false,
    this.danoTotal = false,
    this.observaciones = '',
    List<EdanFoto>? fotos,
    this.fotografia,
    this.coordenadaLat = 0,
    this.coordenadaLon = 0,
  }) : fotos = fotos ?? [];

  factory EdanDanoInfraPublica.fromJson(Map<String, dynamic> json) {
    final fotosRaw = json['fotos'];
    return EdanDanoInfraPublica(
      idSeccion: requireIdSeccion(json['id_seccion']?.toString(), 'di'),
      comunidad: _str(json['comunidad']),
      tipoEstructura: _str(json['tipo_estructura'] ?? json['tipoEstructura']),
      danoParcial: _toBool(json['dano_parcial'] ?? json['danoParcial']),
      danoTotal: _toBool(json['dano_total'] ?? json['danoTotal']),
      observaciones: _str(json['observaciones']),
      fotos: fotosRaw is List
          ? fotosRaw.map((f) => EdanFoto.fromJson(f is Map ? Map<String, dynamic>.from(f) : {})).toList()
          : [],
      fotografia: json['fotografia'],
      coordenadaLat: _toDouble(json['coordenada_lat'] ?? json['coordenadaLat']),
      coordenadaLon: _toDouble(json['coordenada_lon'] ?? json['coordenadaLon']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id_seccion': idSeccion,
        'comunidad': comunidad,
        'tipo_estructura': tipoEstructura,
        'dano_parcial': danoParcial,
        'dano_total': danoTotal,
        'observaciones': observaciones,
        'fotos': fotos.map((f) => f.toJson()).toList(),
        'fotografia': fotografia,
        'coordenada_lat': coordenadaLat,
        'coordenada_lon': coordenadaLon,
      };

  Map<String, dynamic> toApiJson() => {
        'id_seccion': idSeccion,
        'comunidad': comunidad,
        'tipo_estructura': tipoEstructura,
        'dano_parcial': danoParcial,
        'dano_total': danoTotal,
        'observaciones': observaciones,
        'coordenada_lat': coordenadaLat,
        'coordenada_lon': coordenadaLon,
      };

  Map<String, dynamic> toFotoData(EdanFoto foto) => {
        ...toApiJson(),
        'coordenada_lat': foto.latitud,
        'coordenada_lon': foto.longitud,
      };
}

class EdanServicioBasicoDetalle with EdanFotoHolder {
  String? idSeccion;
  String tipo;
  bool afectado;
  bool danoParcial;
  bool danoTotal;
  String necesidadesInmediatas;
  String observaciones;
  List<EdanFoto> fotos;
  @override
  String? fotografia;
  @override
  double coordenadaLat;
  @override
  double coordenadaLon;

  EdanServicioBasicoDetalle({
    this.idSeccion,
    required this.tipo,
    this.afectado = false,
    this.danoParcial = false,
    this.danoTotal = false,
    this.necesidadesInmediatas = '',
    this.observaciones = '',
    List<EdanFoto>? fotos,
    this.fotografia,
    this.coordenadaLat = 0,
    this.coordenadaLon = 0,
  }) : fotos = fotos ?? [];

  factory EdanServicioBasicoDetalle.fromJson(Map<String, dynamic> json) {
    final fotosRaw = json['fotos'];
    return EdanServicioBasicoDetalle(
      idSeccion: requireIdSeccion(json['id_seccion']?.toString(), 'sb'),
      tipo: _str(json['tipo']),
      afectado: _toBool(json['afectado'] ?? json['impactado']),
      danoParcial: _toBool(json['dano_parcial'] ?? json['danoParcial']),
      danoTotal: _toBool(json['dano_total'] ?? json['danoTotal']),
      necesidadesInmediatas: _str(json['necesidades_inmediatas'] ??
          json['necesidadesInmediatas']),
      observaciones: _str(json['observaciones']),
      fotos: fotosRaw is List
          ? fotosRaw.map((f) => EdanFoto.fromJson(f is Map ? Map<String, dynamic>.from(f) : {})).toList()
          : [],
      fotografia: json['fotografia'],
      coordenadaLat: _toDouble(json['coordenada_lat'] ?? json['coordenadaLat']),
      coordenadaLon: _toDouble(json['coordenada_lon'] ?? json['coordenadaLon']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id_seccion': idSeccion,
        'tipo': tipo,
        'afectado': afectado,
        'dano_parcial': danoParcial,
        'dano_total': danoTotal,
        'necesidades_inmediatas': necesidadesInmediatas,
        'observaciones': observaciones,
        'fotos': fotos.map((f) => f.toJson()).toList(),
        'fotografia': fotografia,
        'coordenada_lat': coordenadaLat,
        'coordenada_lon': coordenadaLon,
      };

  Map<String, dynamic> toApiJson() => {
        'id_seccion': idSeccion,
        'tipo': tipo,
        'dano_parcial': danoParcial,
        'dano_total': danoTotal,
        'necesidades_inmediatas': necesidadesInmediatas,
        'observaciones': observaciones,
        'coordenada_lat': coordenadaLat,
        'coordenada_lon': coordenadaLon,
      };

  Map<String, dynamic> toFotoData(EdanFoto foto) => {
        ...toApiJson(),
        'coordenada_lat': foto.latitud,
        'coordenada_lon': foto.longitud,
      };

  String get etiqueta {
    switch (tipo) {
      case 'energia_electrica':
        return 'Energía eléctrica';
      case 'agua_potable':
        return 'Agua potable';
      case 'alcantarillado':
        return 'Alcantarillado';
      case 'gas_domiciliario':
        return 'Gas domiciliario';
      case 'telecomunicaciones':
        return 'Telecomunicaciones';
      default:
        return tipo;
    }
  }

  bool get tieneDatos =>
      afectado ||
      danoParcial ||
      danoTotal ||
      necesidadesInmediatas.trim().isNotEmpty ||
      observaciones.trim().isNotEmpty ||
      fotos.isNotEmpty ||
      coordenadaLat != 0 ||
      coordenadaLon != 0;
}

class EdanDanoServicioBasico {
  List<EdanServicioBasicoDetalle> servicios;

  EdanDanoServicioBasico({List<EdanServicioBasicoDetalle>? servicios})
      : servicios = servicios ?? _serviciosPorDefecto();

  static List<EdanServicioBasicoDetalle> _serviciosPorDefecto() => [
        EdanServicioBasicoDetalle(tipo: 'energia_electrica'),
        EdanServicioBasicoDetalle(tipo: 'agua_potable'),
        EdanServicioBasicoDetalle(tipo: 'alcantarillado'),
        EdanServicioBasicoDetalle(tipo: 'gas_domiciliario'),
        EdanServicioBasicoDetalle(tipo: 'telecomunicaciones'),
      ];

  factory EdanDanoServicioBasico.fromJson(dynamic json) {
    if (json is List) {
      final porTipo = {
        for (final e in json.whereType<Map>())
          (e['tipo'] ?? '').toString(): EdanServicioBasicoDetalle.fromJson(
              Map<String, dynamic>.from(e)),
      };
      final resultado = EdanDanoServicioBasico();
      for (var i = 0; i < resultado.servicios.length; i++) {
        final porDefecto = resultado.servicios[i];
        resultado.servicios[i] = porTipo[porDefecto.tipo] ?? porDefecto;
      }
      return resultado;
    }
    final data =
        json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
    final resultado = EdanDanoServicioBasico();
    final legado = {
      'energia_electrica': 'luz_electrica',
      'agua_potable': 'agua_potable',
      'alcantarillado': 'alcantarillado',
      'gas_domiciliario': 'gas_domiciliario',
      'telecomunicaciones': 'telecomunicaciones',
    };
    for (final s in resultado.servicios) {
      final key = legado[s.tipo] ?? s.tipo;
      s.afectado = _toBool(data[key]);
    }
    final parcial = _toBool(data['dano_parcial'] ?? data['danoParcial']);
    final total = _toBool(data['dano_total'] ?? data['danoTotal']);
    final nec = (data['necesidades_inmediatas'] ??
            data['necesidadesInmediatas'] ??
            '')
        .toString();
    final obs = (data['observaciones'] ?? '').toString();
    for (final s in resultado.servicios) {
      if (s.afectado) {
        s.danoParcial = parcial;
        s.danoTotal = total;
        s.necesidadesInmediatas = nec;
        s.observaciones = obs;
      }
    }
    return resultado;
  }

  List<Map<String, dynamic>> toJson() =>
      servicios.map((e) => e.toJson()).toList();

  bool get algunaSeleccionada =>
      servicios.any((s) => s.afectado || s.tieneDatos);
}

class EdanDanoUnidadEducativa with EdanFotoHolder {
  String? idSeccion;
  String nombreEstablecimiento;
  String comunidad;
  bool danoParcial;
  bool danoTotal;
  bool? suspensionClases;
  bool? perdidaMaterial;
  bool? funcionaAlbergue;
  int estudiantes;
  int profesores;
  int administrativos;
  String observaciones;
  List<EdanFoto> fotos;
  @override
  String? fotografia;
  @override
  double coordenadaLat;
  @override
  double coordenadaLon;

  EdanDanoUnidadEducativa({
    this.idSeccion,
    this.nombreEstablecimiento = '',
    this.comunidad = '',
    this.danoParcial = false,
    this.danoTotal = false,
    this.suspensionClases,
    this.perdidaMaterial,
    this.funcionaAlbergue,
    this.estudiantes = 0,
    this.profesores = 0,
    this.administrativos = 0,
    this.observaciones = '',
    List<EdanFoto>? fotos,
    this.fotografia,
    this.coordenadaLat = 0,
    this.coordenadaLon = 0,
  }) : fotos = fotos ?? [];

  factory EdanDanoUnidadEducativa.fromJson(Map<String, dynamic> json) {
    final fotosRaw = json['fotos'];
    return EdanDanoUnidadEducativa(
      idSeccion: requireIdSeccion(json['id_seccion']?.toString(), 'ue'),
      nombreEstablecimiento: _str(json['nombre_establecimiento'] ??
          json['nombreEstablecimiento']),
      comunidad: _str(json['comunidad']),
      danoParcial: _toBool(json['dano_parcial'] ?? json['danoParcial']),
      danoTotal: _toBool(json['dano_total'] ?? json['danoTotal']),
      suspensionClases: json['suspension_clases'] ?? json['suspensionClases'] == null
          ? null
          : _toBool(json['suspension_clases'] ?? json['suspensionClases']),
      perdidaMaterial: json['perdida_material'] ?? json['perdidaMaterial'] == null
          ? null
          : _toBool(json['perdida_material'] ?? json['perdidaMaterial']),
      funcionaAlbergue: json['funciona_albergue'] ?? json['funciona_albergue'] == null
          ? null
          : _toBool(json['funciona_albergue'] ?? json['funciona_albergue']),
      estudiantes: _toInt(json['estudiantes']),
      profesores: _toInt(json['profesores']),
      administrativos: _toInt(json['administrativos']),
      observaciones: _str(json['observaciones']),
      fotos: fotosRaw is List
          ? fotosRaw.map((f) => EdanFoto.fromJson(f is Map ? Map<String, dynamic>.from(f) : {})).toList()
          : [],
      fotografia: json['fotografia'],
      coordenadaLat: _toDouble(json['coordenada_lat'] ?? json['coordenadaLat']),
      coordenadaLon: _toDouble(json['coordenada_lon'] ?? json['coordenadaLon']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id_seccion': idSeccion,
        'nombre_establecimiento': nombreEstablecimiento,
        'comunidad': comunidad,
        'dano_parcial': danoParcial,
        'dano_total': danoTotal,
        'suspension_clases': suspensionClases,
        'perdida_material': perdidaMaterial,
        'funciona_albergue': funcionaAlbergue,
        'estudiantes': estudiantes,
        'profesores': profesores,
        'administrativos': administrativos,
        'observaciones': observaciones,
        'fotos': fotos.map((f) => f.toJson()).toList(),
        'fotografia': fotografia,
        'coordenada_lat': coordenadaLat,
        'coordenada_lon': coordenadaLon,
      };

  Map<String, dynamic> toApiJson() => {
        'id_seccion': idSeccion,
        'nombre_establecimiento': nombreEstablecimiento,
        'comunidad': comunidad,
        'dano_parcial': danoParcial,
        'dano_total': danoTotal,
        'suspension_clases': suspensionClases,
        'perdida_material': perdidaMaterial,
        'funciona_albergue': funcionaAlbergue,
        'estudiantes': estudiantes,
        'profesores': profesores,
        'administrativos': administrativos,
        'observaciones': observaciones,
        'coordenada_lat': coordenadaLat,
        'coordenada_lon': coordenadaLon,
      };

  Map<String, dynamic> toFotoData(EdanFoto foto) => {
        ...toApiJson(),
        'coordenada_lat': foto.latitud,
        'coordenada_lon': foto.longitud,
      };

  int get totalAfectados => estudiantes + profesores + administrativos;
}

class EdanDanoVivienda with EdanFotoHolder {
  String? idSeccion;
  String comunidad;
  int danoParcial;
  int danoTotal;
  String necesidadesInmediatas;
  String observaciones;
  List<EdanFoto> fotos;
  @override
  String? fotografia;
  @override
  double coordenadaLat;
  @override
  double coordenadaLon;

  EdanDanoVivienda({
    this.idSeccion,
    this.comunidad = '',
    this.danoParcial = 0,
    this.danoTotal = 0,
    this.necesidadesInmediatas = '',
    this.observaciones = '',
    List<EdanFoto>? fotos,
    this.fotografia,
    this.coordenadaLat = 0,
    this.coordenadaLon = 0,
  }) : fotos = fotos ?? [];

  factory EdanDanoVivienda.fromJson(Map<String, dynamic> json) {
    final fotosRaw = json['fotos'];
    return EdanDanoVivienda(
      idSeccion: requireIdSeccion(json['id_seccion']?.toString(), 'dv'),
      comunidad: _str(json['comunidad']),
      danoParcial: _toInt(json['dano_parcial'] ?? json['danoParcial']),
      danoTotal: _toInt(json['dano_total'] ?? json['danoTotal']),
      necesidadesInmediatas: _str(json['necesidades_inmediatas'] ??
          json['necesidadesInmediatas']),
      observaciones: _str(json['observaciones']),
      fotos: fotosRaw is List
          ? fotosRaw.map((f) => EdanFoto.fromJson(f is Map ? Map<String, dynamic>.from(f) : {})).toList()
          : [],
      fotografia: json['fotografia'],
      coordenadaLat: _toDouble(json['coordenada_lat'] ?? json['coordenadaLat']),
      coordenadaLon: _toDouble(json['coordenada_lon'] ?? json['coordenadaLon']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id_seccion': idSeccion,
        'comunidad': comunidad,
        'dano_parcial': danoParcial,
        'dano_total': danoTotal,
        'necesidades_inmediatas': necesidadesInmediatas,
        'observaciones': observaciones,
        'fotos': fotos.map((f) => f.toJson()).toList(),
        'fotografia': fotografia,
        'coordenada_lat': coordenadaLat,
        'coordenada_lon': coordenadaLon,
      };

  Map<String, dynamic> toApiJson() => {
        'id_seccion': idSeccion,
        'comunidad': comunidad,
        'dano_parcial': danoParcial,
        'dano_total': danoTotal,
        'necesidades_inmediatas': necesidadesInmediatas,
        'observaciones': observaciones,
        'coordenada_lat': coordenadaLat,
        'coordenada_lon': coordenadaLon,
      };

  Map<String, dynamic> toFotoData(EdanFoto foto) => {
        ...toApiJson(),
        'coordenada_lat': foto.latitud,
        'coordenada_lon': foto.longitud,
      };
}

class EdanDanoAgricultura with EdanFotoHolder {
  String? idSeccion;
  int? idCultivo;
  String tipoCultivo;
  int hectareasAfectadas;
  int hectareasPerdidas;
  String necesidadesInmediatas;
  String observaciones;
  List<EdanFoto> fotos;
  @override
  String? fotografia;
  @override
  double coordenadaLat;
  @override
  double coordenadaLon;

  EdanDanoAgricultura({
    this.idSeccion,
    this.idCultivo,
    this.tipoCultivo = '',
    this.hectareasAfectadas = 0,
    this.hectareasPerdidas = 0,
    this.necesidadesInmediatas = '',
    this.observaciones = '',
    List<EdanFoto>? fotos,
    this.fotografia,
    this.coordenadaLat = 0,
    this.coordenadaLon = 0,
  }) : fotos = fotos ?? [];

  factory EdanDanoAgricultura.fromJson(Map<String, dynamic> json) {
    final fotosRaw = json['fotos'];
    return EdanDanoAgricultura(
      idSeccion: requireIdSeccion(json['id_seccion']?.toString(), 'da'),
      idCultivo: _jsonIntFk(json['id_cultivo']),
      tipoCultivo: _str(json['tipo_cultivo'] ?? json['tipoCultivo'] ??
          (json['cultivo'] is Map ? json['cultivo']['nombre'] : null)),
      hectareasAfectadas: _toInt(json['hectareas_afectadas'] ?? json['hectareasAfectadas']),
      hectareasPerdidas: _toInt(json['hectareas_perdidas'] ?? json['hectareasPerdidas']),
      necesidadesInmediatas: _str(json['necesidades_inmediatas'] ??
          json['necesidadesInmediatas']),
      observaciones: _str(json['observaciones']),
      fotos: fotosRaw is List
          ? fotosRaw.map((f) => EdanFoto.fromJson(f is Map ? Map<String, dynamic>.from(f) : {})).toList()
          : [],
      fotografia: json['fotografia'],
      coordenadaLat: _toDouble(json['coordenada_lat'] ?? json['coordenadaLat']),
      coordenadaLon: _toDouble(json['coordenada_lon'] ?? json['coordenadaLon']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id_seccion': idSeccion,
        'id_cultivo': idCultivo,
        'tipo_cultivo': tipoCultivo,
        'hectareas_afectadas': hectareasAfectadas,
        'hectareas_perdidas': hectareasPerdidas,
        'necesidades_inmediatas': necesidadesInmediatas,
        'observaciones': observaciones,
        'fotos': fotos.map((f) => f.toJson()).toList(),
        'fotografia': fotografia,
        'coordenada_lat': coordenadaLat,
        'coordenada_lon': coordenadaLon,
      };

  Map<String, dynamic> toApiJson() => {
        'id_seccion': idSeccion,
        'id_cultivo': idCultivo,
        'tipo_cultivo': tipoCultivo,
        'hectareas_afectadas': hectareasAfectadas,
        'hectareas_perdidas': hectareasPerdidas,
        'necesidades_inmediatas': necesidadesInmediatas,
        'observaciones': observaciones,
        'coordenada_lat': coordenadaLat,
        'coordenada_lon': coordenadaLon,
      };

  Map<String, dynamic> toFotoData(EdanFoto foto) => {
        ...toApiJson(),
        'coordenada_lat': foto.latitud,
        'coordenada_lon': foto.longitud,
      };
}

class EdanDanoPecuario with EdanFotoHolder {
  String? idSeccion;
  int? idEspecie;
  String especie;
  String raza;
  int animalesAfectados;
  int animalesMuertos;
  String necesidadesInmediatas;
  List<EdanFoto> fotos;
  @override
  String? fotografia;
  @override
  double coordenadaLat;
  @override
  double coordenadaLon;

  EdanDanoPecuario({
    this.idSeccion,
    this.idEspecie,
    this.especie = '',
    this.raza = '',
    this.animalesAfectados = 0,
    this.animalesMuertos = 0,
    this.necesidadesInmediatas = '',
    List<EdanFoto>? fotos,
    this.fotografia,
    this.coordenadaLat = 0,
    this.coordenadaLon = 0,
  }) : fotos = fotos ?? [];

  factory EdanDanoPecuario.fromJson(Map<String, dynamic> json) {
    final fotosRaw = json['fotos'];
    return EdanDanoPecuario(
      idSeccion: requireIdSeccion(json['id_seccion']?.toString(), 'dp'),
      idEspecie: _jsonIntFk(json['id_especie']),
      especie: json['especie'] is Map
          ? _str(json['especie']['nombre'])
          : _str(json['especie']),
      raza: _str(json['raza']),
      animalesAfectados: _toInt(json['animales_afectados'] ?? json['animalesAfectados']),
      animalesMuertos: _toInt(json['animales_muertos'] ?? json['animalesMuertos']),
      necesidadesInmediatas: json['necesidades_inmediatas'] ??
          json['necesidadesInmediatas'] ??
          '',
      fotos: fotosRaw is List
          ? fotosRaw.map((f) => EdanFoto.fromJson(f is Map ? Map<String, dynamic>.from(f) : {})).toList()
          : [],
      fotografia: json['fotografia'],
      coordenadaLat: _toDouble(json['coordenada_lat'] ?? json['coordenadaLat']),
      coordenadaLon: _toDouble(json['coordenada_lon'] ?? json['coordenadaLon']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id_seccion': idSeccion,
        'id_especie': idEspecie,
        'especie': especie,
        'raza': raza,
        'animales_afectados': animalesAfectados,
        'animales_muertos': animalesMuertos,
        'necesidades_inmediatas': necesidadesInmediatas,
        'fotos': fotos.map((f) => f.toJson()).toList(),
        'fotografia': fotografia,
        'coordenada_lat': coordenadaLat,
        'coordenada_lon': coordenadaLon,
      };

  Map<String, dynamic> toApiJson() => {
        'id_seccion': idSeccion,
        'id_especie': idEspecie,
        'especie': especie,
        'raza': raza,
        'animales_afectados': animalesAfectados,
        'animales_muertos': animalesMuertos,
        'necesidades_inmediatas': necesidadesInmediatas,
        'coordenada_lat': coordenadaLat,
        'coordenada_lon': coordenadaLon,
      };

  Map<String, dynamic> toFotoData(EdanFoto foto) => {
        ...toApiJson(),
        'coordenada_lat': foto.latitud,
        'coordenada_lon': foto.longitud,
      };
}

class EdanInfraProductiva with EdanFotoHolder {
  String? idSeccion;
  String tipo;
  int danoParcial;
  int danoTotal;
  List<EdanFoto> fotos;
  @override
  String? fotografia;
  @override
  double coordenadaLat;
  @override
  double coordenadaLon;

  EdanInfraProductiva({
    this.idSeccion,
    this.tipo = '',
    this.danoParcial = 0,
    this.danoTotal = 0,
    List<EdanFoto>? fotos,
    this.fotografia,
    this.coordenadaLat = 0,
    this.coordenadaLon = 0,
  }) : fotos = fotos ?? [];

  factory EdanInfraProductiva.fromJson(Map<String, dynamic> json) {
    int count(dynamic v) => v is bool ? (v ? 1 : 0) : _toInt(v);
    final fotosRaw = json['fotos'];
    return EdanInfraProductiva(
      idSeccion: requireIdSeccion(json['id_seccion']?.toString(), 'ip'),
      tipo: _str(json['tipo']),
      danoParcial: count(json['dano_parcial'] ?? json['danoParcial']),
      danoTotal: count(json['dano_total'] ?? json['danoTotal']),
      fotos: fotosRaw is List
          ? fotosRaw.map((f) => EdanFoto.fromJson(f is Map ? Map<String, dynamic>.from(f) : {})).toList()
          : [],
      fotografia: json['fotografia'],
      coordenadaLat: _toDouble(json['coordenada_lat'] ?? json['coordenadaLat']),
      coordenadaLon: _toDouble(json['coordenada_lon'] ?? json['coordenadaLon']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id_seccion': idSeccion,
        'tipo': tipo,
        'dano_parcial': danoParcial,
        'dano_total': danoTotal,
        'fotos': fotos.map((f) => f.toJson()).toList(),
        'fotografia': fotografia,
        'coordenada_lat': coordenadaLat,
        'coordenada_lon': coordenadaLon,
      };

  Map<String, dynamic> toApiJson() => {
        'id_seccion': idSeccion,
        'tipo': tipo,
        'dano_parcial': danoParcial,
        'dano_total': danoTotal,
        'coordenada_lat': coordenadaLat,
        'coordenada_lon': coordenadaLon,
      };

  Map<String, dynamic> toFotoData(EdanFoto foto) => {
        ...toApiJson(),
        'coordenada_lat': foto.latitud,
        'coordenada_lon': foto.longitud,
      };
}

class EdanGrupoVulnerable {
  String? idSeccion;
  int? idGrupoVulnerableCatalogo;
  String? nombreGrupo;
  int mujeres;
  int hombres;
  bool? apoyoPsicologico;
  bool? reposicionDocumentos;
  String observaciones;

  EdanGrupoVulnerable({
    this.idSeccion,
    this.idGrupoVulnerableCatalogo,
    this.nombreGrupo,
    this.mujeres = 0,
    this.hombres = 0,
    this.apoyoPsicologico,
    this.reposicionDocumentos,
    this.observaciones = '',
  });

  int get total => mujeres + hombres;

  bool get tieneDatos =>
      mujeres > 0 ||
      hombres > 0 ||
      (apoyoPsicologico == true) ||
      (reposicionDocumentos == true) ||
      observaciones.trim().isNotEmpty;

  factory EdanGrupoVulnerable.fromJson(Map<String, dynamic> json) {
    final grupoRaw = json['grupo'];
    String? nombreGrupo;
    if (grupoRaw is Map) {
      nombreGrupo = grupoRaw['nombre']?.toString();
    }
    nombreGrupo ??= json['nombre_grupo']?.toString();
    return EdanGrupoVulnerable(
      idSeccion: requireIdSeccion(json['id_seccion']?.toString(), 'po'),
      idGrupoVulnerableCatalogo: _jsonIntFk(json['id_grupo_vulnerable_catalogo']) ??
          (grupoRaw is Map ? _jsonIntFk(grupoRaw['id']) : null),
      nombreGrupo: nombreGrupo,
      mujeres: _toInt(json['mujeres']),
      hombres: _toInt(json['hombres']),
      apoyoPsicologico: (() {
        final raw = json['apoyo_psicologico'] ?? json['apoyoPsicologico'];
        return raw == null ? null : _toBool(raw);
      })(),
      reposicionDocumentos: (() {
        final raw = json['reposicion_documentos'] ?? json['reposicionDocumentos'];
        return raw == null ? null : _toBool(raw);
      })(),
      observaciones: _str(json['observaciones']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id_seccion': idSeccion,
        if (nombreGrupo != null) 'nombre_grupo': nombreGrupo,
        'id_grupo_vulnerable_catalogo': idGrupoVulnerableCatalogo,
        'mujeres': mujeres,
        'hombres': hombres,
        'apoyo_psicologico': apoyoPsicologico,
        'reposicion_documentos': reposicionDocumentos,
        'observaciones': observaciones,
      };

  /// Serialización alineada al schema GrupoVulnerable de la API: envía
  /// id_grupo_vulnerable_catalogo (FK) y grupo como objeto.
  Map<String, dynamic> toApiJson(Map<String, dynamic>? grupoCatalogo) => {
        'id_seccion': idSeccion,
        if (idGrupoVulnerableCatalogo != null)
          'id_grupo_vulnerable_catalogo': idGrupoVulnerableCatalogo,
        if (grupoCatalogo != null) 'grupo': grupoCatalogo,
        'mujeres': mujeres,
        'hombres': hombres,
        'total': total,
        'apoyo_psicologico': apoyoPsicologico,
        'reposicion_documentos': reposicionDocumentos,
        'observaciones': observaciones,
      };
}

class EdanVulnerables {
  EdanGrupoVulnerable ninos;
  EdanGrupoVulnerable adolescentes;
  EdanGrupoVulnerable mujeresLactantes;
  EdanGrupoVulnerable mujeresEmbarazadas;
  EdanGrupoVulnerable adultosMayores;
  EdanGrupoVulnerable personasDiscapacidad;
  EdanGrupoVulnerable personasEnfermedad;

  EdanVulnerables({
    EdanGrupoVulnerable? ninos,
    EdanGrupoVulnerable? adolescentes,
    EdanGrupoVulnerable? mujeresLactantes,
    EdanGrupoVulnerable? mujeresEmbarazadas,
    EdanGrupoVulnerable? adultosMayores,
    EdanGrupoVulnerable? personasDiscapacidad,
    EdanGrupoVulnerable? personasEnfermedad,
  })  : ninos = ninos ?? EdanGrupoVulnerable(),
        adolescentes = adolescentes ?? EdanGrupoVulnerable(),
        mujeresLactantes = mujeresLactantes ?? EdanGrupoVulnerable(),
        mujeresEmbarazadas = mujeresEmbarazadas ?? EdanGrupoVulnerable(),
        adultosMayores = adultosMayores ?? EdanGrupoVulnerable(),
        personasDiscapacidad = personasDiscapacidad ?? EdanGrupoVulnerable(),
        personasEnfermedad = personasEnfermedad ?? EdanGrupoVulnerable();

  factory EdanVulnerables.fromJson(Map<String, dynamic> json) {
    EdanGrupoVulnerable fila(dynamic v) => v is Map
        ? EdanGrupoVulnerable.fromJson(Map<String, dynamic>.from(v))
        : EdanGrupoVulnerable(hombres: _toInt(v));
    return EdanVulnerables(
      ninos: fila(json['ninos'] ?? json['ninas']),
      adolescentes: fila(json['adolescentes']),
      mujeresLactantes: fila(json['mujeres_lactantes'] ?? json['mujeresLactantes']),
      mujeresEmbarazadas: fila(json['mujeres_embarazadas'] ?? json['mujeresEmbarazadas']),
      adultosMayores: fila(json['adultos_mayores'] ?? json['adultosMayores']),
      personasDiscapacidad: fila(json['personas_discapacidad'] ?? json['personasDiscapacidad']),
      personasEnfermedad: fila(json['personas_enfermedad'] ?? json['personasEnfermedad']),
    );
  }

  Map<String, dynamic> toJson() => {
        'ninos': ninos.toJson(),
        'adolescentes': adolescentes.toJson(),
        'mujeres_lactantes': mujeresLactantes.toJson(),
        'mujeres_embarazadas': mujeresEmbarazadas.toJson(),
        'adultos_mayores': adultosMayores.toJson(),
        'personas_discapacidad': personasDiscapacidad.toJson(),
        'personas_enfermedad': personasEnfermedad.toJson(),
      };

  List<EdanGrupoVulnerable> get grupos => [
        ninos,
        adolescentes,
        mujeresLactantes,
        mujeresEmbarazadas,
        adultosMayores,
        personasDiscapacidad,
        personasEnfermedad,
      ];

  bool get algunoPositivo => grupos.any((g) => g.tieneDatos);

  int get totalMujeres =>
      grupos.fold<int>(0, (acc, g) => acc + g.mujeres);

  int get totalHombres =>
      grupos.fold<int>(0, (acc, g) => acc + g.hombres);

  int get totalGeneral =>
      grupos.fold<int>(0, (acc, g) => acc + g.total);
}

class EdanProteccion {
  EdanVulnerables vulnerables;

  EdanProteccion({EdanVulnerables? vulnerables})
      : vulnerables = vulnerables ?? EdanVulnerables();

  factory EdanProteccion.fromJson(Map<String, dynamic> json) {
    return EdanProteccion(
      vulnerables: json['vulnerables'] is Map
          ? EdanVulnerables.fromJson(
              Map<String, dynamic>.from(json['vulnerables'] as Map))
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'vulnerables': vulnerables.toJson(),
      };
}

class EdanNecesidadHumanitaria {
  bool alimentos;
  bool refugioVivienda;
  bool ropaCama;
  bool articulosHigiene;
  bool articulosCocina;
  bool prendasVestir;
  bool herramientas;
  bool almacenamientoAgua;
  bool banos;
  String obsAlimentos;
  String obsRefugioVivienda;
  String obsRopaCama;
  String obsArticulosHigiene;
  String obsArticulosCocina;
  String obsPrendasVestir;
  String obsHerramientas;
  String obsAlmacenamientoAgua;
  String obsBanos;
  String? idSeccion;

  EdanNecesidadHumanitaria({
    this.alimentos = false,
    this.refugioVivienda = false,
    this.ropaCama = false,
    this.articulosHigiene = false,
    this.articulosCocina = false,
    this.prendasVestir = false,
    this.herramientas = false,
    this.almacenamientoAgua = false,
    this.banos = false,
    this.obsAlimentos = '',
    this.obsRefugioVivienda = '',
    this.obsRopaCama = '',
    this.obsArticulosHigiene = '',
    this.obsArticulosCocina = '',
    this.obsPrendasVestir = '',
    this.obsHerramientas = '',
    this.obsAlmacenamientoAgua = '',
    this.obsBanos = '',
    String? idSeccion,
  }) : idSeccion = idSeccion ?? generarIdSeccion('nh');

  factory EdanNecesidadHumanitaria.fromJson(Map<String, dynamic> json) {
    return EdanNecesidadHumanitaria(
      alimentos: _toBool(json['alimentos']),
      refugioVivienda: _toBool(json['refugio_vivienda'] ?? json['refugioVivienda']),
      ropaCama: _toBool(json['ropa_cama'] ?? json['ropaCama']),
      articulosHigiene: _toBool(json['articulos_higiene'] ?? json['articulosHigiene']),
      articulosCocina: _toBool(json['articulos_cocina'] ?? json['articulosCocina']),
      prendasVestir: _toBool(json['prendas_vestir'] ?? json['prendasVestir']),
      herramientas: _toBool(json['herramientas']),
      almacenamientoAgua: _toBool(json['almacenamiento_agua'] ?? json['almacenamientoAgua']),
      banos: _toBool(json['banos']),
      obsAlimentos: _str(json['obs_alimentos'] ?? json['obsAlimentos']),
      obsRefugioVivienda: _str(json['obs_refugio_vivienda'] ?? json['obsRefugioVivienda']),
      obsRopaCama: _str(json['obs_ropa_cama'] ?? json['obsRopaCama']),
      obsArticulosHigiene: _str(json['obs_articulos_higiene'] ?? json['obsArticulosHigiene']),
      obsArticulosCocina: _str(json['obs_articulos_cocina'] ?? json['obsArticulosCocina']),
      obsPrendasVestir: _str(json['obs_prendas_vestir'] ?? json['obsPrendasVestir']),
      obsHerramientas: _str(json['obs_herramientas']),
      obsAlmacenamientoAgua: _str(json['obs_almacenamiento_agua'] ?? json['obsAlmacenamientoAgua']),
      obsBanos: _str(json['obs_banos']),
      idSeccion: _str(json['id_seccion']).isEmpty
          ? generarIdSeccion('nh')
          : json['id_seccion'].toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'alimentos': alimentos,
        'refugio_vivienda': refugioVivienda,
        'ropa_cama': ropaCama,
        'articulos_higiene': articulosHigiene,
        'articulos_cocina': articulosCocina,
        'prendas_vestir': prendasVestir,
        'herramientas': herramientas,
        'almacenamiento_agua': almacenamientoAgua,
        'banos': banos,
        'obs_alimentos': obsAlimentos,
        'obs_refugio_vivienda': obsRefugioVivienda,
        'obs_ropa_cama': obsRopaCama,
        'obs_articulos_higiene': obsArticulosHigiene,
        'obs_articulos_cocina': obsArticulosCocina,
        'obs_prendas_vestir': obsPrendasVestir,
        'obs_herramientas': obsHerramientas,
        'obs_almacenamiento_agua': obsAlmacenamientoAgua,
        'obs_banos': obsBanos,
        'id_seccion': idSeccion,
      };

  bool get algunaSeleccionada =>
      alimentos ||
      refugioVivienda ||
      ropaCama ||
      articulosHigiene ||
      articulosCocina ||
      prendasVestir ||
      herramientas ||
      almacenamientoAgua ||
      banos;

  /// Regla única 1:1: la sección cuenta si algún checkbox es true O algún
  /// texto obs_* está lleno. Espejo de la condición del servidor.
  bool get tieneDatos =>
      algunaSeleccionada ||
      obsAlimentos.trim().isNotEmpty ||
      obsRefugioVivienda.trim().isNotEmpty ||
      obsRopaCama.trim().isNotEmpty ||
      obsArticulosHigiene.trim().isNotEmpty ||
      obsArticulosCocina.trim().isNotEmpty ||
      obsPrendasVestir.trim().isNotEmpty ||
      obsHerramientas.trim().isNotEmpty ||
      obsAlmacenamientoAgua.trim().isNotEmpty ||
      obsBanos.trim().isNotEmpty;
}

class EdanLocalidad {
  // IDs y sync
  String? idLocal;
  int? idServer;
  int? idEdan;
  int? idUsuario;
  int? idEdanLocalidadEstado;
  UgrLocalidadEstado? estadoLocalidad;
  bool sincronizado;
  bool pendienteEliminacion;
  bool pendienteActualizacion;
  bool editado;
  String? fechaModificacion;

  // Campos básicos
  String tipoLocalidad;
  String nombre;
  int? idTipoLocalidad;
  int? idTipoEvento;
  int? idDepartamento;
  int? idProvincia;
  int? idMunicipio;
  String? departamentoNombre;
  String? provinciaNombre;
  String? municipioNombre;
  String? fechaLlenado;
  String? fechaEvento;
  String? horaEvento;
  int totalPoblacionAfectada;
  int totalFamiliasAfectadas;
  int totalFamiliasDamnificadas;

  // Campos de encabezado (solo locales; el servidor no los acepta)
  String nombreAlcalde;
  String fonoAlcalde;
  String? tipoEventoNombre;
  EdanResponsable? responsable;
  Usuario? usuario;

  // Flags de impacto
  bool impPoblacion;
  bool impSalud;
  bool impInfraestructura;
  bool impServicios;
  bool impEducacion;
  bool impVivienda;
  bool impAgropecuario;
  bool impProteccion;
  bool impNecesidades;
  bool impImpactoPoblacion;
  bool impSaludEstablecimientos;
  bool impDanosViales;
  bool impDanosInfraPublica;
  bool impServiciosBasicos;
  bool impUnidadesEducativas;
  bool impDanosVivienda;
  bool impDanosAgricultura;
  bool impDanosPecuarios;
  bool impInfraProductiva;
  bool impPrimeraRespuesta;
  bool impNecesidadSalud;
  bool impNecesidadHumanitaria;

  // Secciones como LISTAS (schema API v1.3.0)
  List<EdanImpactoPoblacion> impactoPoblacion;
  EdanNecesidadPrimeraRespuesta? necesidadPrimeraRespuesta;
  List<EdanEstablecimientoSalud> establecimientosSalud;
  EdanNecesidadSalud? necesidadSalud;
  List<EdanDanoVial> danosViales;
  List<EdanDanoInfraPublica> danosInfraPublica;
  List<EdanServicioBasicoDetalle> serviciosBasicos;
  List<EdanDanoUnidadEducativa> unidadesEducativas;
  List<EdanDanoVivienda> danosVivienda;
  List<EdanDanoAgricultura> danosAgricultura;
  List<EdanDanoPecuario> danosPecuarios;
  List<EdanInfraProductiva> infraProductiva;
  List<EdanGrupoVulnerable> proteccion;
  EdanNecesidadHumanitaria? necesidadHumanitaria;

  /// IDs de secciones 1:N eliminadas localmente que aún necesitan DELETE en
  /// el servidor. Cada entrada es un map con 'ruta' y 'id_seccion'.
  List<Map<String, String>> seccionesEliminadas;

  static List<EdanGrupoVulnerable> _proteccionPorDefecto() => [
        EdanGrupoVulnerable(idSeccion: generarIdSeccion('po'), nombreGrupo: 'Niñas y niños 0-5 años'),
        EdanGrupoVulnerable(idSeccion: generarIdSeccion('po'), nombreGrupo: 'Niñas y niños 6-12 años'),
        EdanGrupoVulnerable(idSeccion: generarIdSeccion('po'), nombreGrupo: 'Adolescentes'),
        EdanGrupoVulnerable(idSeccion: generarIdSeccion('po'), nombreGrupo: 'Mujeres lactantes'),
        EdanGrupoVulnerable(idSeccion: generarIdSeccion('po'), nombreGrupo: 'Mujeres embarazadas'),
        EdanGrupoVulnerable(idSeccion: generarIdSeccion('po'), nombreGrupo: 'Adultos mayores'),
        EdanGrupoVulnerable(idSeccion: generarIdSeccion('po'), nombreGrupo: 'Personas con discapacidad'),
        EdanGrupoVulnerable(idSeccion: generarIdSeccion('po'), nombreGrupo: 'Personas con enfermedad crónica'),
      ];

  static List<EdanGrupoVulnerable> proteccionDesdeCatalogo(
      List<dynamic> catalogo) {
    if (catalogo.isEmpty) return _proteccionPorDefecto();
    return catalogo.map<EdanGrupoVulnerable>((c) {
      final id = c is Map ? (c['id_grupo_vulnerable'] ?? c['id']) : null;
      final nombre = c is Map ? (c['nombre'] ?? '') : '';
      return EdanGrupoVulnerable(
        idSeccion: generarIdSeccion('po'),
        idGrupoVulnerableCatalogo: id is int ? id : int.tryParse('$id'),
        nombreGrupo: nombre.toString(),
      );
    }).toList();
  }

  String get etiquetaLugar {
    final t = tipoLocalidad.trim();
    final n = nombre.trim();
    if (n.isEmpty) return t;
    if (t.isEmpty) return n;
    return '$t $n';
  }

  bool get esHuerfana => idEdan == null || idEdan == 0;

  EdanLocalidad({
    this.idLocal,
    this.idServer,
    this.idEdan,
    this.idUsuario,
    this.idEdanLocalidadEstado,
    this.estadoLocalidad,
    this.sincronizado = false,
    this.pendienteEliminacion = false,
    this.pendienteActualizacion = false,
    this.editado = false,
    this.fechaModificacion,
    this.tipoLocalidad = '',
    this.nombre = '',
    this.idTipoLocalidad,
    this.idTipoEvento,
    this.idDepartamento,
    this.idProvincia,
    this.idMunicipio,
    this.departamentoNombre,
    this.provinciaNombre,
    this.municipioNombre,
    this.fechaLlenado,
    this.fechaEvento,
    this.horaEvento,
    this.totalPoblacionAfectada = 0,
    this.totalFamiliasAfectadas = 0,
    this.totalFamiliasDamnificadas = 0,
    this.nombreAlcalde = '',
    this.fonoAlcalde = '',
    this.tipoEventoNombre,
    EdanResponsable? responsable,
    this.usuario,
    this.impPoblacion = false,
    this.impSalud = false,
    this.impInfraestructura = false,
    this.impServicios = false,
    this.impEducacion = false,
    this.impVivienda = false,
    this.impAgropecuario = false,
    this.impProteccion = false,
    this.impNecesidades = false,
    this.impImpactoPoblacion = false,
    this.impSaludEstablecimientos = false,
    this.impDanosViales = false,
    this.impDanosInfraPublica = false,
    this.impServiciosBasicos = false,
    this.impUnidadesEducativas = false,
    this.impDanosVivienda = false,
    this.impDanosAgricultura = false,
    this.impDanosPecuarios = false,
    this.impInfraProductiva = false,
    this.impPrimeraRespuesta = false,
    this.impNecesidadSalud = false,
    this.impNecesidadHumanitaria = false,
    List<EdanImpactoPoblacion>? impactoPoblacion,
    EdanNecesidadPrimeraRespuesta? necesidadPrimeraRespuesta,
    List<EdanEstablecimientoSalud>? establecimientosSalud,
    EdanNecesidadSalud? necesidadSalud,
    List<EdanDanoVial>? danosViales,
    List<EdanDanoInfraPublica>? danosInfraPublica,
    List<EdanServicioBasicoDetalle>? serviciosBasicos,
    List<EdanDanoUnidadEducativa>? unidadesEducativas,
    List<EdanDanoVivienda>? danosVivienda,
    List<EdanDanoAgricultura>? danosAgricultura,
    List<EdanDanoPecuario>? danosPecuarios,
    List<EdanInfraProductiva>? infraProductiva,
    List<EdanGrupoVulnerable>? proteccion,
    EdanNecesidadHumanitaria? necesidadHumanitaria,
    List<Map<String, String>>? seccionesEliminadas,
  })  : impactoPoblacion = impactoPoblacion ?? [],
        necesidadPrimeraRespuesta = necesidadPrimeraRespuesta ?? EdanNecesidadPrimeraRespuesta(),
        establecimientosSalud = establecimientosSalud ?? [],
        necesidadSalud = necesidadSalud ?? EdanNecesidadSalud(),
        danosViales = danosViales ?? [],
        danosInfraPublica = danosInfraPublica ?? [],
        serviciosBasicos = serviciosBasicos ?? [],
        unidadesEducativas = unidadesEducativas ?? [],
        danosVivienda = danosVivienda ?? [],
        danosAgricultura = danosAgricultura ?? [],
        danosPecuarios = danosPecuarios ?? [],
        infraProductiva = infraProductiva ?? [],
        proteccion = proteccion ?? _proteccionPorDefecto(),
        necesidadHumanitaria = necesidadHumanitaria ?? EdanNecesidadHumanitaria(),
        responsable = responsable ?? EdanResponsable(),
        seccionesEliminadas = seccionesEliminadas ?? [];

  factory EdanLocalidad.empty() => EdanLocalidad();

  factory EdanLocalidad.fromJson(Map<String, dynamic> json) {
    List<T> parseList<T>(dynamic value, T Function(Map<String, dynamic>) parser) {
      if (value is List) {
        return value
            .whereType<Map>()
            .map((m) => parser(Map<String, dynamic>.from(m)))
            .toList();
      }
      return <T>[];
    }

    // Parse impacto_poblacion como LISTA (API v1.3.0)
    List<EdanImpactoPoblacion> impactoPoblacion;
    if (json['impacto_poblacion'] is List) {
      impactoPoblacion = parseList(json['impacto_poblacion'], EdanImpactoPoblacion.fromJson);
    } else if (json['impacto_poblacion'] is Map) {
      impactoPoblacion = [EdanImpactoPoblacion.fromJson(
          Map<String, dynamic>.from(json['impacto_poblacion'] as Map))];
    } else {
      impactoPoblacion = [];
    }

    // Parse servicios_basicos como LISTA (API v1.3.0)
    List<EdanServicioBasicoDetalle> serviciosBasicos;
    if (json['servicios_basicos'] is List) {
      serviciosBasicos = parseList(json['servicios_basicos'], EdanServicioBasicoDetalle.fromJson);
    } else {
      serviciosBasicos = [];
    }

    // Parse proteccion como LISTA de EdanGrupoVulnerable (API v1.3.0)
    List<EdanGrupoVulnerable> proteccion;
    if (json['proteccion'] is List) {
      proteccion = parseList(json['proteccion'], EdanGrupoVulnerable.fromJson);
    } else {
      proteccion = [];
    }
    // Backfill to always show all 8 categories (like new mode)
    if (proteccion.length < 8) {
      final defecto = _proteccionPorDefecto();
      for (var i = proteccion.length; i < 8; i++) {
        proteccion.add(defecto[i]);
      }
    }

    // Extraer estado_localidad anidado
    int? idEdanLocalidadEstado;
    UgrLocalidadEstado? estadoLocalidad;
    final estadoRaw = json['estado_localidad'];
    if (estadoRaw is Map) {
      idEdanLocalidadEstado = _toInt(estadoRaw['id_edan_localidad_estado'] ?? estadoRaw['id']);
      final nombre = estadoRaw['nombre']?.toString();
      estadoLocalidad = _estadoFromNombre(nombre);
    } else if (json['id_edan_localidad_estado'] != null) {
      idEdanLocalidadEstado = _toInt(json['id_edan_localidad_estado']);
      estadoLocalidad = switch (idEdanLocalidadEstado) {
        1 => UgrLocalidadEstado.borrador,
        2 => UgrLocalidadEstado.enviadoUgr,
        3 => UgrLocalidadEstado.aprobadoUgr,
        4 => UgrLocalidadEstado.rechazadoUgr,
        5 => UgrLocalidadEstado.aprobadoAjuste,
        6 => UgrLocalidadEstado.enRevisionUgr,
        _ => UgrLocalidadEstado.borrador,
      };
    }

    final localidad = EdanLocalidad(
      idLocal: json['id_local'],
      idServer: _toInt(json['id_edan_localidad']),
      idEdan: _jsonIntFk(json['id_edan'] ??
          (json['edan'] is Map ? json['edan']['id_edan'] : null)),
      idUsuario: _toInt(json['id_usuario']),
      idEdanLocalidadEstado: idEdanLocalidadEstado,
      estadoLocalidad: estadoLocalidad,
      sincronizado: _toBool(json['sincronizado']),
      pendienteEliminacion: _toBool(json['pendiente_eliminacion']),
      pendienteActualizacion: _toBool(json['pendiente_actualizacion']),
      fechaModificacion: json['fecha_modificacion'],
      tipoLocalidad: _str(_parseTipoLocalidad(json['tipo_localidad']) ??
          json['tipoLocalidad']),
      idTipoLocalidad: _jsonIntFk(json['id_tipo_localidad']),
      nombre: _str(json['localidad'] ?? json['nombre']),
      idTipoEvento: _jsonIntFk(json['id_tipo_evento']),
      idDepartamento: _toInt(json['id_departamento']),
      idProvincia: _toInt(json['id_provincia']),
      idMunicipio: _toInt(json['id_municipio']),
      departamentoNombre: _str(json['departamento_nombre'] ??
          (json['departamento'] is Map ? json['departamento']['nombre'] : null)),
      provinciaNombre: _str(json['provincia_nombre'] ??
          (json['provincia'] is Map ? json['provincia']['nombre'] : null)),
      municipioNombre: _str(json['municipio_nombre'] ??
          (json['municipio'] is Map ? json['municipio']['nombre'] : null)),
      fechaLlenado: json['fecha_llenado'],
      fechaEvento: json['fecha_evento'],
      horaEvento: json['hora_evento'],
      totalPoblacionAfectada: _toInt(json['total_poblacion_afectada']),
      totalFamiliasAfectadas: _toInt(json['total_familias_afectadas']),
      totalFamiliasDamnificadas: _toInt(json['total_familias_damnificadas']),
      nombreAlcalde: _str(json['nombre_alcalde'] ?? json['nombreAlcalde']),
      fonoAlcalde: _str(json['fono_alcalde'] ?? json['fonoAlcalde']),
      tipoEventoNombre: json['tipo_evento_nombre'] ??
          json['tipoEventoNombre'] ??
          (json['tipo_evento'] is Map
              ? json['tipo_evento']['nombre']
              : null),
      responsable: json['responsable'] is Map
          ? EdanResponsable.fromJson(
              Map<String, dynamic>.from(json['responsable'] as Map))
          : (json['usuario'] is Map
              ? EdanResponsable(
                  nombre: _str(json['usuario']['nombre']),
                  cargo: _str(json['usuario']['cargo']),
                  fono: _str(json['usuario']['celular']),
                  correo: _str(json['usuario']['correo']),
                )
              : null),
      usuario: _parseUsuario(json['usuario']),
      impPoblacion: _toBool(json['imp_poblacion']),
      impSalud: _toBool(json['imp_salud']),
      impInfraestructura: _toBool(json['imp_infraestructura']),
      impServicios: _toBool(json['imp_servicios']),
      impEducacion: _toBool(json['imp_educacion']),
      impVivienda: _toBool(json['imp_vivienda']),
      impAgropecuario: _toBool(json['imp_agropecuario']),
      impProteccion: _toBool(json['imp_proteccion']),
      impNecesidades: _toBool(json['imp_necesidades']),
      impImpactoPoblacion: _toBool(json['imp_impacto_poblacion']),
      impSaludEstablecimientos: _toBool(json['imp_salud_establecimientos']),
      impDanosViales: _toBool(json['imp_danos_viales']),
      impDanosInfraPublica: _toBool(json['imp_danos_infra_publica']),
      impServiciosBasicos: _toBool(json['imp_servicios_basicos']),
      impUnidadesEducativas: _toBool(json['imp_unidades_educativas']),
      impDanosVivienda: _toBool(json['imp_danos_vivienda']),
      impDanosAgricultura: _toBool(json['imp_danos_agricultura']),
      impDanosPecuarios: _toBool(json['imp_danos_pecuarios']),
      impInfraProductiva: _toBool(json['imp_infra_productiva']),
      impPrimeraRespuesta: _toBool(json['imp_primera_respuesta']),
      impNecesidadSalud: _toBool(json['imp_necesidad_salud']),
      impNecesidadHumanitaria: _toBool(json['imp_necesidad_humanitaria']),
      impactoPoblacion: impactoPoblacion,
      necesidadPrimeraRespuesta: json['necesidad_primera_respuesta'] is Map
          ? EdanNecesidadPrimeraRespuesta.fromJson(
              Map<String, dynamic>.from(json['necesidad_primera_respuesta'] as Map))
          : null,
      establecimientosSalud: parseList(
          json['establecimientos_salud'], EdanEstablecimientoSalud.fromJson),
      necesidadSalud: json['necesidad_salud'] is Map
          ? EdanNecesidadSalud.fromJson(
              Map<String, dynamic>.from(json['necesidad_salud'] as Map))
          : null,
      danosViales: parseList(json['danos_viales'], EdanDanoVial.fromJson),
      danosInfraPublica:
          parseList(json['danos_infra_publica'], EdanDanoInfraPublica.fromJson),
      serviciosBasicos: serviciosBasicos,
      unidadesEducativas:
          parseList(json['unidades_educativas'], EdanDanoUnidadEducativa.fromJson),
      danosVivienda: parseList(json['danos_vivienda'], EdanDanoVivienda.fromJson),
      danosAgricultura:
          parseList(json['danos_agricultura'], EdanDanoAgricultura.fromJson),
      danosPecuarios: parseList(json['danos_pecuarios'], EdanDanoPecuario.fromJson),
      infraProductiva:
          parseList(json['infra_productiva'], EdanInfraProductiva.fromJson),
      proteccion: proteccion,
      necesidadHumanitaria: json['necesidad_humanitaria'] is Map
          ? EdanNecesidadHumanitaria.fromJson(
              Map<String, dynamic>.from(json['necesidad_humanitaria'] as Map))
          : null,
      seccionesEliminadas: _parseSeccionesEliminadas(json['secciones_eliminadas']),
    );
    localidad.deduplicarSecciones();
    return localidad;
  }

  /// Recalcula los flags 1:1 de impacto según los datos reales cargados en las
  /// secciones (espejo local del `_marcar_impacto` del backend). Se invoca
  /// antes de persistir para que el flag refleje el estado tras editar.
  void recalcularFlagsImpacto() {
    impImpactoPoblacion = impactoPoblacion.any((i) =>
        i.fallecidos > 0 || i.heridos > 0 || i.desaparecidos > 0);
    impSaludEstablecimientos = establecimientosSalud.any((e) =>
        e.nombreEstablecimiento.trim().isNotEmpty ||
        e.comunidad.trim().isNotEmpty ||
        e.danoParcial ||
        e.danoTotal ||
        e.medicosAfectados > 0 ||
        e.enfermerasAfectados > 0 ||
        e.otrosAfectados > 0 ||
        e.fotografia != null ||
        e.fotos.isNotEmpty ||
        e.coordenadaLat != 0 ||
        e.coordenadaLon != 0);
    impDanosViales = danosViales.any((d) =>
        d.viaPuente.trim().isNotEmpty ||
        d.tramo.trim().isNotEmpty ||
        d.danoParcial ||
        d.danoTotal ||
        d.kmDanio > 0 ||
        d.necesidadesInmediatas.trim().isNotEmpty ||
        d.observaciones.trim().isNotEmpty ||
        d.fotografia != null ||
        d.fotos.isNotEmpty ||
        d.coordenadaLat != 0 ||
        d.coordenadaLon != 0);
    impDanosInfraPublica = danosInfraPublica.any((d) =>
        d.tipoEstructura.trim().isNotEmpty ||
        d.comunidad.trim().isNotEmpty ||
        d.danoParcial ||
        d.danoTotal ||
        d.observaciones.trim().isNotEmpty ||
        d.fotografia != null ||
        d.fotos.isNotEmpty ||
        d.coordenadaLat != 0 ||
        d.coordenadaLon != 0);
    impServiciosBasicos = serviciosBasicos.any((s) =>
        s.afectado ||
        s.danoParcial ||
        s.danoTotal ||
        s.necesidadesInmediatas.trim().isNotEmpty ||
        s.observaciones.trim().isNotEmpty ||
        s.fotografia != null ||
        s.fotos.isNotEmpty ||
        s.coordenadaLat != 0 ||
        s.coordenadaLon != 0);
    impUnidadesEducativas = unidadesEducativas.any((u) =>
        u.nombreEstablecimiento.trim().isNotEmpty ||
        u.comunidad.trim().isNotEmpty ||
        u.danoParcial ||
        u.danoTotal ||
        u.suspensionClases == true ||
        u.perdidaMaterial == true ||
        u.funcionaAlbergue == true ||
        u.estudiantes > 0 ||
        u.profesores > 0 ||
        u.administrativos > 0 ||
        u.observaciones.trim().isNotEmpty ||
        u.fotografia != null ||
        u.fotos.isNotEmpty ||
        u.coordenadaLat != 0 ||
        u.coordenadaLon != 0);
    impDanosVivienda = danosVivienda.any((d) =>
        d.comunidad.trim().isNotEmpty ||
        d.danoParcial > 0 ||
        d.danoTotal > 0 ||
        d.necesidadesInmediatas.trim().isNotEmpty ||
        d.observaciones.trim().isNotEmpty ||
        d.fotografia != null ||
        d.fotos.isNotEmpty ||
        d.coordenadaLat != 0 ||
        d.coordenadaLon != 0);
    impDanosAgricultura = danosAgricultura.any((d) =>
        d.tipoCultivo.trim().isNotEmpty ||
        d.hectareasAfectadas > 0 ||
        d.hectareasPerdidas > 0 ||
        d.necesidadesInmediatas.trim().isNotEmpty ||
        d.observaciones.trim().isNotEmpty ||
        d.fotografia != null ||
        d.fotos.isNotEmpty ||
        d.coordenadaLat != 0 ||
        d.coordenadaLon != 0);
    impDanosPecuarios = danosPecuarios.any((d) =>
        d.especie.trim().isNotEmpty ||
        d.raza.trim().isNotEmpty ||
        d.animalesAfectados > 0 ||
        d.animalesMuertos > 0 ||
        d.necesidadesInmediatas.trim().isNotEmpty ||
        d.fotografia != null ||
        d.fotos.isNotEmpty ||
        d.coordenadaLat != 0 ||
        d.coordenadaLon != 0);
    impInfraProductiva = infraProductiva.any((d) =>
        d.tipo.trim().isNotEmpty ||
        d.danoParcial > 0 ||
        d.danoTotal > 0 ||
        d.fotografia != null ||
        d.fotos.isNotEmpty ||
        d.coordenadaLat != 0 ||
        d.coordenadaLon != 0);
    impPrimeraRespuesta =
        (necesidadPrimeraRespuesta?.tieneDatos ?? false);
    impNecesidadSalud =
        (necesidadSalud?.tieneDatos ?? false);
    impNecesidadHumanitaria =
        (necesidadHumanitaria?.tieneDatos ?? false);

    // Flags "gruesos": derivados de los datos reales para que la vista y los
    // avisos de sección del preview sean consistentes con el contenido
    // (se alinean con los criterios que usan los renderers).
    impPoblacion = impImpactoPoblacion || impPrimeraRespuesta;
    impSalud = impSaludEstablecimientos || impNecesidadSalud;
    impInfraestructura = impDanosViales || impDanosInfraPublica;
    impServicios = impServiciosBasicos;
    impEducacion = impUnidadesEducativas;
    impVivienda = impDanosVivienda;
    impAgropecuario =
        impDanosAgricultura || impDanosPecuarios || impInfraProductiva;
    impProteccion = proteccion.any((g) => g.tieneDatos);
    impNecesidades = impNecesidadHumanitaria;
  }

  static List<Map<String, String>> _parseSeccionesEliminadas(dynamic json) {
    if (json is! List) return [];
    final result = <Map<String, String>>[];
    for (final item in json) {
      if (item is Map && item['ruta'] != null && item['id_seccion'] != null) {
        result.add({
          'ruta': item['ruta'].toString(),
          'id_seccion': item['id_seccion'].toString(),
        });
      }
    }
    return result;
  }

  static UgrLocalidadEstado? _estadoFromNombre(String? nombre) {
    if (nombre == null) return null;
    final n = nombre.toLowerCase();
    if (n.contains('borrador')) return UgrLocalidadEstado.borrador;
    if (n.contains('enviado')) return UgrLocalidadEstado.enviadoUgr;
    if (n.contains('revision')) return UgrLocalidadEstado.enRevisionUgr;
    if (n.contains('aprobado') && n.contains('ajuste')) return UgrLocalidadEstado.aprobadoAjuste;
    if (n.contains('aprobado')) return UgrLocalidadEstado.aprobadoUgr;
    if (n.contains('rechazado')) return UgrLocalidadEstado.rechazadoUgr;
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id_local': idLocal,
        'id_edan_localidad': idServer,
        'id_edan': idEdan,
        'id_usuario': idUsuario,
        'id_edan_localidad_estado': idEdanLocalidadEstado,
        'tipo_localidad': tipoLocalidad.isEmpty ? null : tipoLocalidad,
        'id_tipo_localidad': idTipoLocalidad,
        'localidad': nombre.isEmpty ? null : nombre,
        'id_tipo_evento': idTipoEvento,
        'id_departamento': idDepartamento,
        'id_provincia': idProvincia,
        'id_municipio': idMunicipio,
        'departamento_nombre': departamentoNombre,
        'provincia_nombre': provinciaNombre,
        'municipio_nombre': municipioNombre,
        'fecha_llenado': fechaLlenado,
        'fecha_evento': fechaEvento,
        'hora_evento': horaEvento,
        'total_poblacion_afectada': totalPoblacionAfectada,
        'total_familias_afectadas': totalFamiliasAfectadas,
        'total_familias_damnificadas': totalFamiliasDamnificadas,
        'nombre_alcalde': nombreAlcalde.isEmpty ? null : nombreAlcalde,
        'fono_alcalde': fonoAlcalde.isEmpty ? null : fonoAlcalde,
        'tipo_evento_nombre': tipoEventoNombre,
        if (responsable != null) 'responsable': responsable!.toJson(),
        'imp_poblacion': impPoblacion,
        'imp_salud': impSalud,
        'imp_infraestructura': impInfraestructura,
        'imp_servicios': impServicios,
        'imp_educacion': impEducacion,
        'imp_vivienda': impVivienda,
        'imp_agropecuario': impAgropecuario,
        'imp_proteccion': impProteccion,
        'imp_necesidades': impNecesidades,
        'imp_impacto_poblacion': impImpactoPoblacion,
        'imp_salud_establecimientos': impSaludEstablecimientos,
        'imp_danos_viales': impDanosViales,
        'imp_danos_infra_publica': impDanosInfraPublica,
        'imp_servicios_basicos': impServiciosBasicos,
        'imp_unidades_educativas': impUnidadesEducativas,
        'imp_danos_vivienda': impDanosVivienda,
        'imp_danos_agricultura': impDanosAgricultura,
        'imp_danos_pecuarios': impDanosPecuarios,
        'imp_infra_productiva': impInfraProductiva,
        'imp_primera_respuesta': impPrimeraRespuesta,
        'imp_necesidad_salud': impNecesidadSalud,
        'imp_necesidad_humanitaria': impNecesidadHumanitaria,
        'impacto_poblacion': impactoPoblacion.map((e) => e.toJson()).toList(),
        if (necesidadPrimeraRespuesta != null)
          'necesidad_primera_respuesta': necesidadPrimeraRespuesta!.toJson(),
        'establecimientos_salud':
            establecimientosSalud.map((e) => e.toJson()).toList(),
        if (necesidadSalud != null) 'necesidad_salud': necesidadSalud!.toJson(),
        'danos_viales': danosViales.map((e) => e.toJson()).toList(),
        'danos_infra_publica': danosInfraPublica.map((e) => e.toJson()).toList(),
        'servicios_basicos': serviciosBasicos.map((e) => e.toJson()).toList(),
        'unidades_educativas': unidadesEducativas.map((e) => e.toJson()).toList(),
        'danos_vivienda': danosVivienda.map((e) => e.toJson()).toList(),
        'danos_agricultura': danosAgricultura.map((e) => e.toJson()).toList(),
        'danos_pecuarios': danosPecuarios.map((e) => e.toJson()).toList(),
        'infra_productiva': infraProductiva.map((e) => e.toJson()).toList(),
        'proteccion': proteccion.map((e) => e.toJson()).toList(),
        if (necesidadHumanitaria != null)
          'necesidad_humanitaria': necesidadHumanitaria!.toJson(),
        'sincronizado': sincronizado,
        'pendiente_eliminacion': pendienteEliminacion,
        'pendiente_actualizacion': pendienteActualizacion,
        'fecha_modificacion': fechaModificacion,
        'secciones_eliminadas': seccionesEliminadas.toList(),
      };

  /// Serialización alineada al schema LocalidadCreate de la API
  /// (POST /edan/localidades/sync). No envía campos locales (fotos, id_local
  /// opcional, etc.) y ajusta las secciones al formato del servidor.
  Map<String, dynamic> toApiJson() => {
        'id_local': idLocal,
        'id_usuario': idUsuario,
        'id_tipo_localidad': idTipoLocalidadResuelto,
        'id_edan_localidad_estado': idEdanLocalidadEstado,
        'tipo_localidad': tipoLocalidad.isEmpty ? null : tipoLocalidad,
        'id_tipo_evento':
            (idTipoEvento == null || idTipoEvento == 0) ? null : idTipoEvento,
        'id_departamento': idDepartamento,
        'id_provincia': idProvincia,
        'id_municipio': idMunicipio,
        'fecha_llenado': fechaLlenado,
        'fecha_evento': fechaEvento,
        'hora_evento': horaEvento,
        'total_poblacion_afectada': totalPoblacionAfectada,
        'total_familias_afectadas': totalFamiliasAfectadas,
        'total_familias_damnificadas': totalFamiliasDamnificadas,
        'localidad': nombre,
        'imp_poblacion': impPoblacion,
        'imp_salud': impSalud,
        'imp_infraestructura': impInfraestructura,
        'imp_servicios': impServicios,
        'imp_educacion': impEducacion,
        'imp_vivienda': impVivienda,
        'imp_agropecuario': impAgropecuario,
        'imp_proteccion': impProteccion,
        'imp_necesidades': impNecesidades,
        'imp_impacto_poblacion': impImpactoPoblacion,
        'imp_salud_establecimientos': impSaludEstablecimientos,
        'imp_danos_viales': impDanosViales,
        'imp_danos_infra_publica': impDanosInfraPublica,
        'imp_servicios_basicos': impServiciosBasicos,
        'imp_unidades_educativas': impUnidadesEducativas,
        'imp_danos_vivienda': impDanosVivienda,
        'imp_danos_agricultura': impDanosAgricultura,
        'imp_danos_pecuarios': impDanosPecuarios,
        'imp_infra_productiva': impInfraProductiva,
        'imp_primera_respuesta': impPrimeraRespuesta,
        'imp_necesidad_salud': impNecesidadSalud,
        'imp_necesidad_humanitaria': impNecesidadHumanitaria,
        'impacto_poblacion': _impactoPoblacionApi(),
        if (necesidadPrimeraRespuesta != null)
          'necesidad_primera_respuesta': necesidadPrimeraRespuesta!.toJson(),
        'establecimientos_salud': establecimientosSalud
            .map((e) => e.toApiJson())
            .toList(),
        if (necesidadSalud != null) 'necesidad_salud': necesidadSalud!.toApiJson(),
        'danos_viales': danosViales
            .map((e) => e.toApiJson())
            .toList(),
        'danos_infra_publica': danosInfraPublica
            .map((e) => e.toApiJson())
            .toList(),
        'servicios_basicos': serviciosBasicos.map((e) => e.toApiJson()).toList(),
        'unidades_educativas': unidadesEducativas
            .map((e) => e.toApiJson())
            .toList(),
        'danos_vivienda': danosVivienda
            .map((e) => e.toApiJson())
            .toList(),
        'danos_agricultura': danosAgricultura
            .map((e) => e.toApiJson())
            .toList(),
        'danos_pecuarios': danosPecuarios
            .map((e) => e.toApiJson())
            .toList(),
        'infra_productiva': infraProductiva
            .map((e) => e.toApiJson())
            .toList(),
        'proteccion': _proteccionApi(),
        if (necesidadHumanitaria != null)
          'necesidad_humanitaria': necesidadHumanitaria!.toJson(),
        'fecha_modificacion': fechaModificacion,
        'pendiente_actualizacion': pendienteActualizacion,
        'pendiente_eliminacion': pendienteEliminacion,
      };

  /// La API espera ImpactoPoblacion planos (uno por rango etario); la app
  /// agrupa en EdanImpactoPoblacion con una lista grupos_etarios.
  /// Cada grupo etario debe tener su PROPIO id_seccion único para UPSERT.
  List<Map<String, dynamic>> _impactoPoblacionApi() {
    final grupos = <Map<String, dynamic>>[];
    for (final p in impactoPoblacion) {
      final marcados = p.gruposEtarios.where((g) => g.marcado).toList();
      if (marcados.isNotEmpty) {
        grupos.addAll(marcados.map((g) => g.toApiJson()));
      } else if (p.tieneDatosGlobales) {
        final idGrupoEtario = EdanGrupoEtario.resolverIdGrupoEtario(p.grupoEtario);
        if (idGrupoEtario == null) {
          // Rango legacy sin equivalente en el catálogo v2: se omite para
          // evitar un 400 por fila (aislamiento de errores del servidor).
          continue;
        }
        grupos.add({
          'id_seccion': p.idSeccion,
          'id_grupo_etario': idGrupoEtario,
          'rango': p.grupoEtario,
          'fallecidos': p.fallecidos,
          'heridos': p.heridos,
          'desaparecidos': p.desaparecidos,
          'observaciones': p.observaciones,
        });
      }
    }
    return grupos;
  }

  static const List<String> etiquetasProteccion = [
    'Niñas y niños 0-5 años',
    'Niñas y niños 6-12 años',
    'Adolescentes',
    'Mujeres lactantes',
    'Mujeres embarazadas',
    'Adultos mayores',
    'Personas con discapacidad',
    'Personas con enfermedad crónica',
  ];

  /// La protección se envía por endpoints dedicados (POST /proteccion),
  /// NO dentro del JSON principal de la localidad.
  List<Map<String, dynamic>> _proteccionApi() => [];

  /// Grupos vulnerables con datos, listos para enviar por endpoints dedicados.
  /// Cada item se envía individualmente via POST /edan/localidades/{id}/proteccion.
  List<Map<String, dynamic>> proteccionParaEndpointDedicado() => [
        for (final g in proteccion)
          if (g.tieneDatos) g.toApiJson(null),
      ];

  /// Resuelve el id_tipo_localidad desde el catálogo usando el nombre cuando
  /// el id no está seteado o quedó en 0 (corrupción null→0). Nunca devuelve 0.
  int? get idTipoLocalidadResuelto {
    if (idTipoLocalidad != null && idTipoLocalidad != 0) return idTipoLocalidad;
    return tipoLocalidadIdPorNombre(tipoLocalidad);
  }

  bool get tieneImpactos =>
      impPoblacion ||
      impSalud ||
      impInfraestructura ||
      impServicios ||
      impEducacion ||
      impVivienda ||
      impAgropecuario ||
      impProteccion ||
      impNecesidades;

  EdanVulnerables get vulnerables => EdanVulnerables(
    ninos: proteccion.isNotEmpty ? proteccion[0] : EdanGrupoVulnerable(),
    adolescentes: proteccion.length > 1 ? proteccion[1] : EdanGrupoVulnerable(),
    mujeresLactantes: proteccion.length > 2 ? proteccion[2] : EdanGrupoVulnerable(),
    mujeresEmbarazadas: proteccion.length > 3 ? proteccion[3] : EdanGrupoVulnerable(),
    adultosMayores: proteccion.length > 4 ? proteccion[4] : EdanGrupoVulnerable(),
    personasDiscapacidad: proteccion.length > 5 ? proteccion[5] : EdanGrupoVulnerable(),
    personasEnfermedad: proteccion.length > 6 ? proteccion[6] : EdanGrupoVulnerable(),
  );

  /// Registra la eliminación de un ítem de sección 1:N para que el sync lo
  /// envíe como DELETE al servidor. [ruta] es la ruta v2 (p.ej. 'danos-viales'),
  /// [idSeccion] es el id único del ítem eliminado.
  void registrarEliminacionSeccion(String ruta, String idSeccion) {
    seccionesEliminadas.add({'ruta': ruta, 'id_seccion': idSeccion});
  }

  /// Elimina secciones 1:N duplicadas por idSeccion (v2.9.0+).
  /// Fallback: si no hay idSeccion, usa JSON completo como huella.
  void deduplicarSecciones() {
    establecimientosSalud = _sinDuplicados(establecimientosSalud);
    danosViales = _sinDuplicados(danosViales);
    danosInfraPublica = _sinDuplicados(danosInfraPublica);
    unidadesEducativas = _sinDuplicados(unidadesEducativas);
    danosVivienda = _sinDuplicados(danosVivienda);
    danosAgricultura = _sinDuplicados(danosAgricultura);
    danosPecuarios = _sinDuplicados(danosPecuarios);
    infraProductiva = _sinDuplicados(infraProductiva);
    serviciosBasicos = _sinDuplicados(serviciosBasicos);
    proteccion = _sinDuplicados(proteccion);
    impactoPoblacion = _sinDuplicados(impactoPoblacion);
  }

  static List<T> _sinDuplicados<T>(List<T> items) {
    if (items.length < 2) return items;
    final vistos = <String>{};
    final resultado = <T>[];
    for (final item in items) {
      final huella = _huellaItem(item as Object);
      if (huella == null || vistos.add(huella)) resultado.add(item);
    }
    return resultado;
  }

  /// Huella de identidad: idSeccion si existe, fallback a JSON completo.
  static String? _huellaItem(Object item) {
    try {
      final id = idSeccionDe(item);
      if (id != null && id.isNotEmpty) return id;
      if (item is EdanEstablecimientoSalud) return jsonEncode(item.toJson());
      if (item is EdanDanoVial) return jsonEncode(item.toJson());
      if (item is EdanDanoInfraPublica) return jsonEncode(item.toJson());
      if (item is EdanDanoUnidadEducativa) return jsonEncode(item.toJson());
      if (item is EdanDanoVivienda) return jsonEncode(item.toJson());
      if (item is EdanDanoAgricultura) return jsonEncode(item.toJson());
      if (item is EdanDanoPecuario) return jsonEncode(item.toJson());
      if (item is EdanInfraProductiva) return jsonEncode(item.toJson());
      if (item is EdanServicioBasicoDetalle) return jsonEncode(item.toJson());
      if (item is EdanGrupoVulnerable) return jsonEncode(item.toJson());
      if (item is EdanImpactoPoblacion) return jsonEncode(item.toJson());
    } catch (_) {
      return null;
    }
    return null;
  }
}

class EdanResponsable {
  String nombre;
  String cargo;
  String fono;
  String correo;

  EdanResponsable({
    this.nombre = '',
    this.cargo = '',
    this.fono = '',
    this.correo = '',
  });

  factory EdanResponsable.fromJson(Map<String, dynamic> json) {
    return EdanResponsable(
      nombre: _str(json['nombre']),
      cargo: _str(json['cargo']),
      fono: _str(json['fono']),
      correo: _str(json['correo']),
    );
  }

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        'cargo': cargo,
        'fono': fono,
        'correo': correo,
      };
}

class Edan {
  int? idLocal;
  int? idServer;
  int? idEdan;
  String codigoEdan;
  int? idUsuario;
  int? idDepartamento;
  int? idProvincia;
  int? idMunicipio;
  String? departamentoNombre;
  String? provinciaNombre;
  String? municipioNombre;
  int? idUsuarioAlcalde;
  String nombreAlcalde;
  String fonoAlcalde;
  String fechaLlenado;
  String fechaEvento;
  String horaEvento;
  int totalPoblacionAfectada;
  int totalFamiliasAfectadas;
  int totalFamiliasDamnificadas;
  int? idTipoEvento;
  String? tipoEventoNombre;
  List<EdanLocalidad> localidades;
  EdanNecesidadHumanitaria necesidadHumanitaria;
  EdanResponsable responsable;
  int idEstado;
  String estado;
  bool sincronizado;
  bool pendienteEliminacion;
  bool pendienteActualizacion;
  bool esBorrador;
  int? idReporte;

  int get localidadesAfectadas => localidades.length;

  Map<String, List<String>> incompletosPorSeccion({bool exigirAlcalde = true}) {
    final result = <String, List<String>>{};
    String etiqueta(EdanLocalidad l, int i) =>
        l.etiquetaLugar.isEmpty ? 'Lugar ${i + 1}' : l.etiquetaLugar;

    void marcar(String seccion, List<String> detalle) {
      if (detalle.isNotEmpty) result[seccion] = detalle;
    }

    final generales01 = <String>[
      if (idDepartamento == null ||
          idProvincia == null ||
          idMunicipio == null)
        'Ubicación (departamento, provincia, municipio)',
      if (exigirAlcalde && idUsuarioAlcalde == null) 'Alcalde responsable',
      if (exigirAlcalde && nombreAlcalde.trim().isEmpty) 'Nombre del alcalde',
      if (exigirAlcalde && fonoAlcalde.trim().isEmpty) 'Teléfono del alcalde',
      if (fechaLlenado.trim().isEmpty) 'Fecha de llenado',
      if (fechaEvento.trim().isEmpty) 'Fecha del evento',
      if (tipoEventoNombre == null || tipoEventoNombre!.trim().isEmpty)
        'Tipo de evento no seleccionado',
    ];
    final lugares01 = <String>[
      for (final entry in localidades.asMap().entries)
        if (entry.value.tipoLocalidad.trim().isEmpty ||
            entry.value.nombre.trim().isEmpty)
          etiqueta(entry.value, entry.key),
    ];
    marcar('01', [...generales01, ...lugares01]);

    final lugares03 = <String>[
      for (final entry in localidades.asMap().entries)
        if (entry.value.impPoblacion &&
            !entry.value.impactoPoblacion.any((i) => i.tieneDatosGlobales))
          '${etiqueta(entry.value, entry.key)} (impacto en población)',
    ];
    marcar('03', lugares03);

    final lugares04 = <String>[
      for (final entry in localidades.asMap().entries)
        if (entry.value.impSalud &&
            !(entry.value.establecimientosSalud
                    .any((s) => s.nombreEstablecimiento.trim().isNotEmpty) ||
                (entry.value.necesidadSalud?.botiquines ?? false) ||
                (entry.value.necesidadSalud?.numeroPersonas ?? 0) > 0))
          '${etiqueta(entry.value, entry.key)} (salud)',
    ];
    marcar('04', lugares04);

    final lugares05 = <String>[
      for (final entry in localidades.asMap().entries)
        if (entry.value.impInfraestructura &&
            !(entry.value.danosViales
                    .any((d) => d.viaPuente.trim().isNotEmpty) ||
                entry.value.danosInfraPublica
                    .any((d) => d.tipoEstructura.trim().isNotEmpty)))
          '${etiqueta(entry.value, entry.key)} (infraestructuras)',
    ];
    marcar('05', lugares05);

    final lugares06 = <String>[
      for (final entry in localidades.asMap().entries)
        if (entry.value.impServicios &&
            !entry.value.serviciosBasicos.any((s) => s.tieneDatos))
          '${etiqueta(entry.value, entry.key)} (servicios básicos)',
    ];
    marcar('06', lugares06);

    final lugares07 = <String>[
      for (final entry in localidades.asMap().entries)
        if (entry.value.impEducacion &&
            !entry.value.unidadesEducativas.any((u) =>
                u.nombreEstablecimiento.trim().isNotEmpty ||
                u.estudiantes > 0 ||
                u.profesores > 0 ||
                u.administrativos > 0))
          '${etiqueta(entry.value, entry.key)} (educación)',
    ];
    marcar('07', lugares07);

    final lugares08 = <String>[
      for (final entry in localidades.asMap().entries)
        if (entry.value.impVivienda &&
            !entry.value.danosVivienda
                .any((v) => v.danoParcial > 0 || v.danoTotal > 0))
          '${etiqueta(entry.value, entry.key)} (vivienda)',
    ];
    marcar('08', lugares08);

    final lugares09 = <String>[
      for (final entry in localidades.asMap().entries)
        if (entry.value.impAgropecuario &&
            !(entry.value.danosAgricultura
                    .any((a) => a.tipoCultivo.trim().isNotEmpty) ||
                entry.value.danosPecuarios
                    .any((p) => p.especie.trim().isNotEmpty) ||
                entry.value.infraProductiva.any((i) => i.tipo.trim().isNotEmpty)))
          '${etiqueta(entry.value, entry.key)} (agropecuario)',
    ];
    marcar('09', lugares09);

    final lugares10 = <String>[
      for (final entry in localidades.asMap().entries)
        if (entry.value.impProteccion &&
            !entry.value.proteccion.any((g) => g.tieneDatos))
          '${etiqueta(entry.value, entry.key)} (protección)',
    ];
    marcar('10', lugares10);

    final lugares11 = <String>[
      for (final entry in localidades.asMap().entries)
        if (entry.value.impNecesidades &&
            !(entry.value.necesidadHumanitaria?.algunaSeleccionada ?? false))
          '${etiqueta(entry.value, entry.key)} (necesidades humanitarias)',
    ];
    marcar('11', lugares11);

    final responsables13 = <String>[
      if (responsable.nombre.trim().isEmpty) 'Nombre del responsable',
      if (responsable.cargo.trim().isEmpty) 'Cargo del responsable',
    ];
    marcar('13', responsables13);

    return result;
  }

  Edan({
    this.idLocal,
    this.idServer,
    this.idEdan,
    this.codigoEdan = '',
    this.idUsuario,
    this.idDepartamento,
    this.idProvincia,
    this.idMunicipio,
    this.departamentoNombre,
    this.provinciaNombre,
    this.municipioNombre,
    this.idUsuarioAlcalde,
    this.nombreAlcalde = '',
    this.fonoAlcalde = '',
    this.fechaLlenado = '',
    this.fechaEvento = '',
    this.horaEvento = '',
    this.totalPoblacionAfectada = 0,
    this.totalFamiliasAfectadas = 0,
    this.totalFamiliasDamnificadas = 0,
    this.idTipoEvento,
    this.tipoEventoNombre,
    List<EdanLocalidad>? localidades,
    EdanNecesidadHumanitaria? necesidadHumanitaria,
    EdanResponsable? responsable,
    this.idEstado = 1,
    this.estado = 'borrador',
    this.sincronizado = false,
    this.pendienteEliminacion = false,
    this.pendienteActualizacion = false,
    this.esBorrador = false,
    this.idReporte,
  })  : localidades = localidades ?? [],
        necesidadHumanitaria = necesidadHumanitaria ?? EdanNecesidadHumanitaria(),
        responsable = responsable ?? EdanResponsable();

  factory Edan.empty() => Edan();

  /// Reconstruye un [Edan] a partir de una localidad persistida (rol 7).
  /// Usado para editar (RespEdanFormScreen) y previsualizar
  /// (UgrEdanPreviewScreen) un reporte guardado como localidad.
  factory Edan.desdeLocalidad(EdanLocalidad loc) => Edan(
        idEdan: loc.idEdan,
        idUsuario: loc.idUsuario,
        idDepartamento: loc.idDepartamento,
        idProvincia: loc.idProvincia,
        idMunicipio: loc.idMunicipio,
        departamentoNombre: loc.departamentoNombre,
        provinciaNombre: loc.provinciaNombre,
        municipioNombre: loc.municipioNombre,
        nombreAlcalde: loc.nombreAlcalde,
        fonoAlcalde: loc.fonoAlcalde,
        fechaLlenado: _str(loc.fechaLlenado),
        fechaEvento: _str(loc.fechaEvento),
        horaEvento: _str(loc.horaEvento),
        totalPoblacionAfectada: loc.totalPoblacionAfectada,
        totalFamiliasAfectadas: loc.totalFamiliasAfectadas,
        totalFamiliasDamnificadas: loc.totalFamiliasDamnificadas,
        idTipoEvento: loc.idTipoEvento,
        tipoEventoNombre: loc.tipoEventoNombre,
        localidades: [loc],
        necesidadHumanitaria: loc.necesidadHumanitaria,
        responsable: loc.responsable,
        idEstado: loc.idEdanLocalidadEstado ?? 1,
        estado: loc.estadoLocalidad?.label.toLowerCase() ?? 'borrador',
        esBorrador: loc.estadoLocalidad == UgrLocalidadEstado.borrador,
      );

  /// Completa los campos vacíos del responsable con los datos del usuario
  /// logueado (caché), manteniendo cualquier valor ya persistido.
  void completarResponsableDesdeCache() {
    final token = AuthService.instance.currentToken;
    if (token == null) return;
    final r = responsable;
    if (r.nombre.trim().isEmpty && token.nombre.trim().isNotEmpty) {
      r.nombre = token.nombre;
    }
    if (r.cargo.trim().isEmpty && (token.cargo ?? '').trim().isNotEmpty) {
      r.cargo = token.cargo!;
    }
    if (r.fono.trim().isEmpty && (token.celular ?? '').trim().isNotEmpty) {
      r.fono = token.celular!;
    }
    if (r.correo.trim().isEmpty && (token.correo ?? '').trim().isNotEmpty) {
      r.correo = token.correo!;
    }
  }

  factory Edan.fromJson(Map<String, dynamic> json) {
    final localidadesRaw = json['localidades'];
    final localidades = localidadesRaw is List
        ? localidadesRaw
            .whereType<Map>()
            .map((m) => EdanLocalidad.fromJson(Map<String, dynamic>.from(m)))
            .toList()
        : <EdanLocalidad>[];

    return Edan(
      idLocal: _toInt(json['id_local']),
      idServer: _toInt(json['id_server']),
      idEdan: _toInt(json['id_edan']),
      codigoEdan: _str(json['codigo_edan']),
      idUsuario: _toInt(json['id_usuario']),
      idDepartamento: _toInt(json['id_departamento']),
      idProvincia: _toInt(json['id_provincia']),
      idMunicipio: _toInt(json['id_municipio']),
      departamentoNombre: _str(json['departamento_nombre'] ??
          json['departamentoNombre'] ??
          (json['departamento'] is Map ? json['departamento']['nombre'] : null)),
      provinciaNombre: _str(json['provincia_nombre'] ??
          json['provinciaNombre'] ??
          (json['provincia'] is Map ? json['provincia']['nombre'] : null)),
      municipioNombre: _str(json['municipio_nombre'] ??
          json['municipioNombre'] ??
          (json['municipio'] is Map ? json['municipio']['nombre'] : null)),
      nombreAlcalde: _str(json['nombre_alcalde'] ?? json['nombreAlcalde'] ?? json['alc_nombre'] ??
          (json['usuario_alcalde'] is Map ? json['usuario_alcalde']['nombre'] : null)),
      fonoAlcalde: _str(json['fono_alcalde'] ?? json['fonoAlcalde'] ??
          (json['usuario_alcalde'] is Map ? json['usuario_alcalde']['celular'] : null)),
      idUsuarioAlcalde: _jsonIntFk(json['id_usuario_alcalde'] ?? json['idUsuarioAlcalde'] ?? json['alc_id']),
      fechaLlenado: _str(json['fecha_llenado'] ?? json['fechaLlenado']),
      fechaEvento: _str(json['fecha_evento'] ?? json['fechaEvento']),
      horaEvento: _str(json['hora_evento'] ?? json['horaEvento']),
      totalPoblacionAfectada: _toInt(json['total_poblacion_afectada'] ?? json['totalPoblacionAfectada']),
      totalFamiliasAfectadas: _toInt(json['total_familias_afectadas'] ?? json['totalFamiliasAfectadas']),
      totalFamiliasDamnificadas: _toInt(json['total_familias_damnificadas'] ?? json['totalFamiliasDamnificadas']),
      idTipoEvento: _jsonIntFk(json['id_tipo_evento'] ?? json['idTipoEvento']),
      tipoEventoNombre: _str(json['tipo_evento_nombre'] ??
          json['tipoEventoNombre'] ??
          (json['tipo_evento'] is Map ? json['tipo_evento']['nombre'] : null)),
      localidades: _migrarLocalidades(json, localidades),
      necesidadHumanitaria: json['necesidad_humanitaria'] is Map
          ? EdanNecesidadHumanitaria.fromJson(
              Map<String, dynamic>.from(json['necesidad_humanitaria'] as Map))
          : EdanNecesidadHumanitaria(),
      responsable: json['responsable'] is Map
          ? EdanResponsable.fromJson(
              Map<String, dynamic>.from(json['responsable'] as Map))
          : EdanResponsable(),
      idReporte: _toInt(json['id_reporte'] ?? json['idReporte']),
      idEstado: _toInt(json['id_estado']) == 0
          ? (json['estado'] is Map ? _toInt((json['estado'] as Map)['id_estado']) : 0) == 0
              ? 1
              : _toInt((json['estado'] as Map)['id_estado'])
          : _toInt(json['id_estado']),
      estado: json['estado'] is Map
          ? _str((json['estado'] as Map)['nombre'], 'borrador')
          : _str(json['estado'] ?? json['estadoNombre'] ??
              (json['estado_obj'] is Map ? json['estado_obj']['nombre'] : null) ?? 'borrador'),
      sincronizado: _toBool(json['sincronizado']),
      pendienteEliminacion: _toBool(json['pendiente_eliminacion'] ?? json['pendienteEliminacion']),
      pendienteActualizacion: _toBool(json['pendiente_actualizacion'] ?? json['pendienteActualizacion']),
      esBorrador: _toBool(json['es_borrador'] ?? json['esBorrador']),
    );
  }

  static List<EdanLocalidad> _migrarLocalidades(
      Map<String, dynamic> json, List<EdanLocalidad> localidades) {
    if (localidades.isNotEmpty) return localidades;

    final comunidades = json['comunidades_afectadas'];
    final nombres = comunidades is List
        ? comunidades
            .whereType<Map>()
            .map((m) => _str(m['nombre_comunidad'] ?? m['nombreComunidad']))
            .where((n) => n.trim().isNotEmpty)
            .toList()
        : <String>[];

    final tieneDatosGlobales =
        (json['impacto_poblacion'] is Map) ||
            (json['necesidad_primera_respuesta'] is Map) ||
            (json['establecimientos_salud'] is List) ||
            (json['necesidad_salud'] is Map) ||
            (json['danos_viales'] is List) ||
            (json['danos_infra_publica'] is List) ||
            (json['servicios_basicos'] is Map) ||
            (json['unidades_educativas'] is List) ||
            (json['danos_vivienda'] is List) ||
            (json['danos_agricultura'] is List) ||
            (json['danos_pecuarios'] is List) ||
            (json['infra_productiva'] is List) ||
            (json['proteccion'] is Map);

    if (nombres.isEmpty && !tieneDatosGlobales) return <EdanLocalidad>[];

    final localidad = EdanLocalidad(
      tipoLocalidad: _str(json['tipo_localidad'] ?? json['tipoLocalidad']),
      nombre: nombres.isNotEmpty ? nombres.first : '',
    );

    if (json['impacto_poblacion'] is Map) {
      localidad.impactoPoblacion.add(EdanImpactoPoblacion.fromJson(
          Map<String, dynamic>.from(json['impacto_poblacion'] as Map)));
      localidad.impPoblacion = true;
    }
    if (json['necesidad_primera_respuesta'] is Map) {
      localidad.necesidadPrimeraRespuesta = EdanNecesidadPrimeraRespuesta.fromJson(
          Map<String, dynamic>.from(json['necesidad_primera_respuesta'] as Map));
    }
    if (json['establecimientos_salud'] is List) {
      localidad.establecimientosSalud = (json['establecimientos_salud'] as List)
          .whereType<Map>()
          .map((m) => EdanEstablecimientoSalud.fromJson(
              Map<String, dynamic>.from(m)))
          .toList();
      if (localidad.establecimientosSalud.isNotEmpty) localidad.impSalud = true;
    }
    if (json['necesidad_salud'] is Map) {
      localidad.necesidadSalud = EdanNecesidadSalud.fromJson(
          Map<String, dynamic>.from(json['necesidad_salud'] as Map));
    }
    if (json['danos_viales'] is List) {
      localidad.danosViales = (json['danos_viales'] as List)
          .whereType<Map>()
          .map((m) => EdanDanoVial.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      if (localidad.danosViales.isNotEmpty) localidad.impInfraestructura = true;
    }
    if (json['danos_infra_publica'] is List) {
      localidad.danosInfraPublica = (json['danos_infra_publica'] as List)
          .whereType<Map>()
          .map((m) => EdanDanoInfraPublica.fromJson(
              Map<String, dynamic>.from(m)))
          .toList();
      if (localidad.danosInfraPublica.isNotEmpty) localidad.impInfraestructura = true;
    }
    if (json['servicios_basicos'] is Map ||
        json['servicios_basicos'] is List) {
      final servicios = EdanDanoServicioBasico.fromJson(json['servicios_basicos']);
      localidad.serviciosBasicos = servicios.servicios;
      if (servicios.algunaSeleccionada) localidad.impServicios = true;
    }
    if (json['unidades_educativas'] is List) {
      localidad.unidadesEducativas = (json['unidades_educativas'] as List)
          .whereType<Map>()
          .map((m) => EdanDanoUnidadEducativa.fromJson(
              Map<String, dynamic>.from(m)))
          .toList();
      if (localidad.unidadesEducativas.isNotEmpty) localidad.impEducacion = true;
    }
    if (json['danos_vivienda'] is List) {
      localidad.danosVivienda = (json['danos_vivienda'] as List)
          .whereType<Map>()
          .map((m) => EdanDanoVivienda.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      if (localidad.danosVivienda.isNotEmpty) localidad.impVivienda = true;
    }
    if (json['danos_agricultura'] is List) {
      localidad.danosAgricultura = (json['danos_agricultura'] as List)
          .whereType<Map>()
          .map((m) => EdanDanoAgricultura.fromJson(
              Map<String, dynamic>.from(m)))
          .toList();
      if (localidad.danosAgricultura.isNotEmpty) localidad.impAgropecuario = true;
    }
    if (json['danos_pecuarios'] is List) {
      localidad.danosPecuarios = (json['danos_pecuarios'] as List)
          .whereType<Map>()
          .map((m) => EdanDanoPecuario.fromJson(
              Map<String, dynamic>.from(m)))
          .toList();
      if (localidad.danosPecuarios.isNotEmpty) localidad.impAgropecuario = true;
    }
    if (json['infra_productiva'] is List) {
      localidad.infraProductiva = (json['infra_productiva'] as List)
          .whereType<Map>()
          .map((m) => EdanInfraProductiva.fromJson(
              Map<String, dynamic>.from(m)))
          .toList();
      if (localidad.infraProductiva.isNotEmpty) localidad.impAgropecuario = true;
    }
    if (json['proteccion'] is Map) {
      final prot = EdanProteccion.fromJson(
          Map<String, dynamic>.from(json['proteccion'] as Map));
      localidad.proteccion = prot.vulnerables.grupos;
      if (prot.vulnerables.algunoPositivo) {
        localidad.impProteccion = true;
      }
    }

    localidad.deduplicarSecciones();
    return <EdanLocalidad>[localidad];
  }

  Map<String, dynamic> toJson() => {
        'id_local': idLocal,
        'id_server': idServer,
        'id_edan': idEdan,
        'codigo_edan': codigoEdan,
        'id_usuario': idUsuario,
        'id_departamento': idDepartamento,
        'id_provincia': idProvincia,
        'id_municipio': idMunicipio,
        'departamento_nombre': departamentoNombre,
        'provincia_nombre': provinciaNombre,
        'municipio_nombre': municipioNombre,
        'nombre_alcalde': nombreAlcalde,
        'fono_alcalde': fonoAlcalde,
        'id_usuario_alcalde': idUsuarioAlcalde,
        'fecha_llenado': fechaLlenado,
        'fecha_evento': fechaEvento,
        'hora_evento': horaEvento,
        'total_poblacion_afectada': totalPoblacionAfectada,
        'total_familias_afectadas': totalFamiliasAfectadas,
        'total_familias_damnificadas': totalFamiliasDamnificadas,
        'id_tipo_evento': idTipoEvento,
        'tipo_evento_nombre': tipoEventoNombre,
        'id_reporte': idReporte,
        'localidades': localidades.map((e) => e.toJson()).toList(),
        'necesidad_humanitaria': necesidadHumanitaria.toJson(),
        'responsable': responsable.toJson(),
        'id_estado': idEstado,
        'estado': estado,
        'sincronizado': sincronizado,
        'pendiente_eliminacion': pendienteEliminacion,
        'pendiente_actualizacion': pendienteActualizacion,
        'es_borrador': esBorrador,
      };

}

/// Convierte un valor dinámico a String de forma segura.
/// Si [value] es un Map, llama a toString() en lugar de troncar.
String _str(dynamic value, [String fallback = '']) =>
    value?.toString() ?? fallback;

String? _parseTipoLocalidad(dynamic value) {
  if (value is Map) {
    final nombre = value['nombre'];
    if (nombre is String && nombre.isNotEmpty) return nombre;
    return null;
  }
  if (value is String) return value;
  return null;
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

/// Como [_toInt] pero preservando null y normalizando 0 → null (los ids de
/// claves foráneas nunca son 0; 0 era la corrupción producida por [_toInt]).
int? _jsonIntFk(dynamic value) {
  if (value == null) return null;
  final n = _toInt(value);
  return n == 0 ? null : n;
}

/// Catálogo de tipos de localidad del servidor (GET /edan/tipo-localidad).
const Map<String, int> kTiposLocalidadId = {
  'Localidad': 1,
  'Comunidad': 2,
  'Comunidad indígena': 3,
  'Comunidad campesina': 4,
  'Ayllu': 5,
  'Marka': 6,
  'TIOC': 7,
  'TCO': 8,
  'OTB': 9,
  'Distrito municipal': 10,
  'Distrito indígena originario campesino': 11,
  'Barrio': 12,
  'Zona': 13,
  'Centro poblado': 14,
  'Pueblo indígena': 15,
  'Capitanía': 16,
  'Cabildo': 17,
  'Sindicato agrario': 18,
  'Subcentral': 19,
  'Central agraria': 20,
  'Territorio indígena': 21,
};

String _normalizarTipoLocalidad(String s) => s
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ñ', 'n');

/// Resuelve el id del tipo de localidad a partir del nombre (insensible a
/// acentos) según el catálogo del servidor.
int? tipoLocalidadIdPorNombre(String? nombre) {
  if (nombre == null || nombre.isEmpty) return null;
  final n = _normalizarTipoLocalidad(nombre);
  for (final entry in kTiposLocalidadId.entries) {
    if (_normalizarTipoLocalidad(entry.key) == n) return entry.value;
  }
  return null;
}

/// Nombre canónico del tipo de localidad (según el catálogo del servidor) que
/// coincide de forma insensible a acentos/mayúsculas, o el mismo nombre si no
/// hay coincidencia.
String? tipoLocalidadNombreCanonico(String? nombre) {
  if (nombre == null || nombre.isEmpty) return null;
  final n = _normalizarTipoLocalidad(nombre);
  for (final entry in kTiposLocalidadId.entries) {
    if (_normalizarTipoLocalidad(entry.key) == n) return entry.key;
  }
  return nombre;
}

bool _toBool(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is num) return value != 0;
  return value.toString().toLowerCase() == 'true';
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().replaceAll(',', '.')) ?? 0;
}

Usuario? _parseUsuario(dynamic json) {
  if (json is! Map) return null;
  try {
    return Usuario(
      idUsuario: json['id_usuario'] ?? 0,
      usuario: json['usuario']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? '',
      celular: json['celular']?.toString(),
      carnet: json['carnet']?.toString(),
      comunidad: json['comunidad']?.toString(),
      idRol: json['id_rol'] ?? 6,
      activo: json['activo'],
    );
  } catch (_) {
    return null;
  }
}

/// Marcador común de las secciones 1:N con foto: expone `fotografia`
/// (path server o null) y las coordenadas GPS. Permite construir la fila de
/// la sección en la API v2 (Vía B) incluyendo siempre `fotografia` y las
/// coordenadas si hay foto.
abstract mixin class EdanFotoHolder {
  List<EdanFoto> get fotos;
  String? get fotografia;
  double get coordenadaLat;
  double get coordenadaLon;
}
