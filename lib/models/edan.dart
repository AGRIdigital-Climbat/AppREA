class EdanGrupoEtario {
  String rango;
  int fallecidos;
  int heridos;
  int desaparecidos;
  String observaciones;

  EdanGrupoEtario({
    this.rango = '',
    this.fallecidos = 0,
    this.heridos = 0,
    this.desaparecidos = 0,
    this.observaciones = '',
  });

  factory EdanGrupoEtario.fromJson(Map<String, dynamic> json) {
    return EdanGrupoEtario(
      rango: json['rango'] ?? json['grupo'] ?? '',
      fallecidos: _toInt(json['fallecidos']),
      heridos: _toInt(json['heridos']),
      desaparecidos: _toInt(json['desaparecidos']),
      observaciones: json['observaciones'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'rango': rango,
        'fallecidos': fallecidos,
        'heridos': heridos,
        'desaparecidos': desaparecidos,
        'observaciones': observaciones,
      };

  bool get tieneDatos => fallecidos > 0 || heridos > 0 || desaparecidos > 0;
}

class EdanImpactoPoblacion {
  String grupoEtario;
  int fallecidos;
  int heridos;
  int desaparecidos;
  String observaciones;
  List<EdanGrupoEtario> gruposEtarios;

  EdanImpactoPoblacion({
    this.grupoEtario = '',
    this.fallecidos = 0,
    this.heridos = 0,
    this.desaparecidos = 0,
    this.observaciones = '',
    List<EdanGrupoEtario>? gruposEtarios,
  }) : gruposEtarios = gruposEtarios ?? [
          EdanGrupoEtario(rango: 'Niño (a) 0-5 años'),
          EdanGrupoEtario(rango: 'Escolar de 6-18 años'),
          EdanGrupoEtario(rango: 'Adulto de 19-60 años'),
          EdanGrupoEtario(rango: 'Adulto mayor de 60 años adelante'),
        ];

  factory EdanImpactoPoblacion.fromJson(Map<String, dynamic> json) {
    final grupos = json['grupos_etarios'] ?? json['gruposEtarios'];
    return EdanImpactoPoblacion(
      grupoEtario: json['grupo_etario'] ?? json['grupoEtario'] ?? '',
      fallecidos: _toInt(json['fallecidos']),
      heridos: _toInt(json['heridos']),
      desaparecidos: _toInt(json['desaparecidos']),
      observaciones: json['observaciones'] ?? '',
      gruposEtarios: grupos is List
          ? grupos
              .map((g) => EdanGrupoEtario.fromJson(
                  g is Map ? Map<String, dynamic>.from(g) : {}))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
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

  EdanNecesidadPrimeraRespuesta({
    this.busqueda = false,
    this.salvamento = false,
    this.evacuacion = false,
    this.observaciones = '',
  });

  factory EdanNecesidadPrimeraRespuesta.fromJson(Map<String, dynamic> json) {
    return EdanNecesidadPrimeraRespuesta(
      busqueda: _toBool(json['busqueda']),
      salvamento: _toBool(json['salvamento']),
      evacuacion: _toBool(json['evacuacion']),
      observaciones: json['observaciones'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'busqueda': busqueda,
        'salvamento': salvamento,
        'evacuacion': evacuacion,
        'observaciones': observaciones,
      };

  bool get algunaSeleccionada => busqueda || salvamento || evacuacion;
}

class EdanEstablecimientoSalud {
  String nombreEstablecimiento;
  String comunidad;
  String nivelAtencion;
  bool danoParcial;
  bool danoTotal;
  int medicosAfectados;
  int enfermerasAfectados;
  int otrosAfectados;

  EdanEstablecimientoSalud({
    this.nombreEstablecimiento = '',
    this.comunidad = '',
    this.nivelAtencion = '',
    this.danoParcial = false,
    this.danoTotal = false,
    this.medicosAfectados = 0,
    this.enfermerasAfectados = 0,
    this.otrosAfectados = 0,
  });

  factory EdanEstablecimientoSalud.fromJson(Map<String, dynamic> json) {
    return EdanEstablecimientoSalud(
      nombreEstablecimiento: json['nombre_establecimiento'] ??
          json['nombreEstablecimiento'] ??
          '',
      comunidad: json['comunidad'] ?? '',
      nivelAtencion: json['nivel_atencion'] ?? json['nivelAtencion'] ?? '',
      danoParcial: _toBool(json['dano_parcial'] ?? json['danoParcial']),
      danoTotal: _toBool(json['dano_total'] ?? json['danoTotal']),
      medicosAfectados: _toInt(json['medicos_afectados'] ?? json['medicosAfectados']),
      enfermerasAfectados: _toInt(json['enfermeras_afectados'] ?? json['enfermerasAfectados']),
      otrosAfectados: _toInt(json['otros_afectados'] ?? json['otrosAfectados']),
    );
  }

  Map<String, dynamic> toJson() => {
        'nombre_establecimiento': nombreEstablecimiento,
        'comunidad': comunidad,
        'nivel_atencion': nivelAtencion,
        'dano_parcial': danoParcial,
        'dano_total': danoTotal,
        'medicos_afectados': medicosAfectados,
        'enfermeras_afectados': enfermerasAfectados,
        'otros_afectados': otrosAfectados,
      };
}

class EdanNecesidadSalud {
  bool botiquines;
  int numeroPersonas;
  String otrasNecesidades;
  String observaciones;

  EdanNecesidadSalud({
    this.botiquines = false,
    this.numeroPersonas = 0,
    this.otrasNecesidades = '',
    this.observaciones = '',
  });

  factory EdanNecesidadSalud.fromJson(Map<String, dynamic> json) {
    return EdanNecesidadSalud(
      botiquines: _toBool(json['botiquines']),
      numeroPersonas: _toInt(json['numero_personas'] ??
          json['numeroPersonas'] ??
          json['atencion_inmediata'] ??
          json['atencionInmediata']),
      otrasNecesidades: json['otras_necesidades'] ?? json['otrasNecesidades'] ?? '',
      observaciones: json['observaciones'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'botiquines': botiquines,
        'numero_personas': numeroPersonas,
        'otras_necesidades': otrasNecesidades,
        'observaciones': observaciones,
      };
}

class EdanDanoVial {
  String viaPuente;
  String tramo;
  bool danoParcial;
  bool danoTotal;
  double kmDanio;
  String necesidadesInmediatas;
  String observaciones;

  EdanDanoVial({
    this.viaPuente = '',
    this.tramo = '',
    this.danoParcial = false,
    this.danoTotal = false,
    this.kmDanio = 0,
    this.necesidadesInmediatas = '',
    this.observaciones = '',
  });

  factory EdanDanoVial.fromJson(Map<String, dynamic> json) {
    return EdanDanoVial(
      viaPuente: json['via_puente'] ?? json['viaPuente'] ?? '',
      tramo: json['tramo'] ?? '',
      danoParcial: _toBool(json['dano_parcial'] ?? json['danoParcial']),
      danoTotal: _toBool(json['dano_total'] ?? json['danoTotal']),
      kmDanio: _toDouble(json['km_danio'] ?? json['kmDanio']),
      necesidadesInmediatas: json['necesidades_inmediatas'] ??
          json['necesidadesInmediatas'] ??
          '',
      observaciones: json['observaciones'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'via_puente': viaPuente,
        'tramo': tramo,
        'dano_parcial': danoParcial,
        'dano_total': danoTotal,
        'km_danio': kmDanio,
        'necesidades_inmediatas': necesidadesInmediatas,
        'observaciones': observaciones,
      };
}

class EdanDanoInfraPublica {
  String comunidad;
  String tipoEstructura;
  bool danoParcial;
  bool danoTotal;
  String observaciones;

  EdanDanoInfraPublica({
    this.comunidad = '',
    this.tipoEstructura = '',
    this.danoParcial = false,
    this.danoTotal = false,
    this.observaciones = '',
  });

  factory EdanDanoInfraPublica.fromJson(Map<String, dynamic> json) {
    return EdanDanoInfraPublica(
      comunidad: json['comunidad'] ?? '',
      tipoEstructura: json['tipo_estructura'] ?? json['tipoEstructura'] ?? '',
      danoParcial: _toBool(json['dano_parcial'] ?? json['danoParcial']),
      danoTotal: _toBool(json['dano_total'] ?? json['danoTotal']),
      observaciones: json['observaciones'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'comunidad': comunidad,
        'tipo_estructura': tipoEstructura,
        'dano_parcial': danoParcial,
        'dano_total': danoTotal,
        'observaciones': observaciones,
      };
}

class EdanServicioBasicoDetalle {
  String tipo;
  bool afectado;
  bool danoParcial;
  bool danoTotal;
  String necesidadesInmediatas;
  String observaciones;

  EdanServicioBasicoDetalle({
    required this.tipo,
    this.afectado = false,
    this.danoParcial = false,
    this.danoTotal = false,
    this.necesidadesInmediatas = '',
    this.observaciones = '',
  });

  factory EdanServicioBasicoDetalle.fromJson(Map<String, dynamic> json) {
    return EdanServicioBasicoDetalle(
      tipo: json['tipo'] ?? '',
      afectado: _toBool(json['afectado'] ?? json['impactado']),
      danoParcial: _toBool(json['dano_parcial'] ?? json['danoParcial']),
      danoTotal: _toBool(json['dano_total'] ?? json['danoTotal']),
      necesidadesInmediatas: json['necesidades_inmediatas'] ??
          json['necesidadesInmediatas'] ??
          '',
      observaciones: json['observaciones'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'tipo': tipo,
        'afectado': afectado,
        'dano_parcial': danoParcial,
        'dano_total': danoTotal,
        'necesidades_inmediatas': necesidadesInmediatas,
        'observaciones': observaciones,
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
      danoParcial ||
      danoTotal ||
      necesidadesInmediatas.trim().isNotEmpty ||
      observaciones.trim().isNotEmpty;
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

class EdanDanoUnidadEducativa {
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

  EdanDanoUnidadEducativa({
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
  });

  factory EdanDanoUnidadEducativa.fromJson(Map<String, dynamic> json) {
    return EdanDanoUnidadEducativa(
      nombreEstablecimiento: json['nombre_establecimiento'] ??
          json['nombreEstablecimiento'] ??
          '',
      comunidad: json['comunidad'] ?? '',
      danoParcial: _toBool(json['dano_parcial'] ?? json['danoParcial']),
      danoTotal: _toBool(json['dano_total'] ?? json['danoTotal']),
      suspensionClases: json['suspension_clases'] ?? json['suspensionClases'] == null
          ? null
          : _toBool(json['suspension_clases'] ?? json['suspensionClases']),
      perdidaMaterial: json['perdida_material'] ?? json['perdidaMaterial'] == null
          ? null
          : _toBool(json['perdida_material'] ?? json['perdidaMaterial']),
      funcionaAlbergue: json['funciona_albergue'] ?? json['funcionaAlbergue'] == null
          ? null
          : _toBool(json['funciona_albergue'] ?? json['funcionaAlbergue']),
      estudiantes: _toInt(json['estudiantes']),
      profesores: _toInt(json['profesores']),
      administrativos: _toInt(json['administrativos']),
      observaciones: json['observaciones'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
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
      };

  int get totalAfectados => estudiantes + profesores + administrativos;
}

class EdanDanoVivienda {
  String comunidad;
  int danoParcial;
  int danoTotal;
  String necesidadesInmediatas;
  String observaciones;

  EdanDanoVivienda({
    this.comunidad = '',
    this.danoParcial = 0,
    this.danoTotal = 0,
    this.necesidadesInmediatas = '',
    this.observaciones = '',
  });

  factory EdanDanoVivienda.fromJson(Map<String, dynamic> json) {
    return EdanDanoVivienda(
      comunidad: json['comunidad'] ?? '',
      danoParcial: _toInt(json['dano_parcial'] ?? json['danoParcial']),
      danoTotal: _toInt(json['dano_total'] ?? json['danoTotal']),
      necesidadesInmediatas: json['necesidades_inmediatas'] ??
          json['necesidadesInmediatas'] ??
          '',
      observaciones: json['observaciones'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'comunidad': comunidad,
        'dano_parcial': danoParcial,
        'dano_total': danoTotal,
        'necesidades_inmediatas': necesidadesInmediatas,
        'observaciones': observaciones,
      };
}

class EdanDanoAgricultura {
  String tipoCultivo;
  int hectareasAfectadas;
  int hectareasPerdidas;
  String necesidadesInmediatas;
  String observaciones;

  EdanDanoAgricultura({
    this.tipoCultivo = '',
    this.hectareasAfectadas = 0,
    this.hectareasPerdidas = 0,
    this.necesidadesInmediatas = '',
    this.observaciones = '',
  });

  factory EdanDanoAgricultura.fromJson(Map<String, dynamic> json) {
    return EdanDanoAgricultura(
      tipoCultivo: json['tipo_cultivo'] ?? json['tipoCultivo'] ?? '',
      hectareasAfectadas: _toInt(json['hectareas_afectadas'] ?? json['hectareasAfectadas']),
      hectareasPerdidas: _toInt(json['hectareas_perdidas'] ?? json['hectareasPerdidas']),
      necesidadesInmediatas: json['necesidades_inmediatas'] ??
          json['necesidadesInmediatas'] ??
          '',
      observaciones: json['observaciones'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'tipo_cultivo': tipoCultivo,
        'hectareas_afectadas': hectareasAfectadas,
        'hectareas_perdidas': hectareasPerdidas,
        'necesidades_inmediatas': necesidadesInmediatas,
        'observaciones': observaciones,
      };
}

class EdanDanoPecuario {
  String especie;
  String raza;
  int animalesAfectados;
  int animalesMuertos;
  String necesidadesInmediatas;

  EdanDanoPecuario({
    this.especie = '',
    this.raza = '',
    this.animalesAfectados = 0,
    this.animalesMuertos = 0,
    this.necesidadesInmediatas = '',
  });

  factory EdanDanoPecuario.fromJson(Map<String, dynamic> json) {
    return EdanDanoPecuario(
      especie: json['especie'] ?? '',
      raza: json['raza'] ?? '',
      animalesAfectados: _toInt(json['animales_afectados'] ?? json['animalesAfectados']),
      animalesMuertos: _toInt(json['animales_muertos'] ?? json['animalesMuertos']),
      necesidadesInmediatas: json['necesidades_inmediatas'] ??
          json['necesidadesInmediatas'] ??
          '',
    );
  }

  Map<String, dynamic> toJson() => {
        'especie': especie,
        'raza': raza,
        'animales_afectados': animalesAfectados,
        'animales_muertos': animalesMuertos,
        'necesidades_inmediatas': necesidadesInmediatas,
      };
}

class EdanInfraProductiva {
  String tipo;
  int danoParcial;
  int danoTotal;

  EdanInfraProductiva({
    this.tipo = '',
    this.danoParcial = 0,
    this.danoTotal = 0,
  });

  factory EdanInfraProductiva.fromJson(Map<String, dynamic> json) {
    int count(dynamic v) => v is bool ? (v ? 1 : 0) : _toInt(v);
    return EdanInfraProductiva(
      tipo: json['tipo'] ?? '',
      danoParcial: count(json['dano_parcial'] ?? json['danoParcial']),
      danoTotal: count(json['dano_total'] ?? json['danoTotal']),
    );
  }

  Map<String, dynamic> toJson() => {
        'tipo': tipo,
        'dano_parcial': danoParcial,
        'dano_total': danoTotal,
      };
}

class EdanGrupoVulnerable {
  int mujeres;
  int hombres;
  bool? apoyoPsicologico;
  bool? reposicionDocumentos;
  String observaciones;

  EdanGrupoVulnerable({
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
    return EdanGrupoVulnerable(
      mujeres: _toInt(json['mujeres']),
      hombres: _toInt(json['hombres']),
      apoyoPsicologico: json['apoyo_psicologico'] ?? json['apoyoPsicologico'] == null
          ? null
          : _toBool(json['apoyo_psicologico'] ?? json['apoyoPsicologico']),
      reposicionDocumentos: json['reposicion_documentos'] ?? json['reposicionDocumentos'] == null
          ? null
          : _toBool(json['reposicion_documentos'] ?? json['reposicionDocumentos']),
      observaciones: json['observaciones'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'mujeres': mujeres,
        'hombres': hombres,
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
  });

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
      obsAlimentos: json['obs_alimentos'] ?? json['obsAlimentos'] ?? '',
      obsRefugioVivienda: json['obs_refugio_vivienda'] ?? json['obsRefugioVivienda'] ?? '',
      obsRopaCama: json['obs_ropa_cama'] ?? json['obsRopaCama'] ?? '',
      obsArticulosHigiene: json['obs_articulos_higiene'] ?? json['obsArticulosHigiene'] ?? '',
      obsArticulosCocina: json['obs_articulos_cocina'] ?? json['obsArticulosCocina'] ?? '',
      obsPrendasVestir: json['obs_prendas_vestir'] ?? json['obsPrendasVestir'] ?? '',
      obsHerramientas: json['obs_herramientas'] ?? '',
      obsAlmacenamientoAgua: json['obs_almacenamiento_agua'] ?? json['obsAlmacenamientoAgua'] ?? '',
      obsBanos: json['obs_banos'] ?? '',
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
}

class EdanLocalidad {
  String tipoLocalidad;
  String nombre;

  bool impPoblacion;
  bool impSalud;
  bool impInfraestructura;
  bool impServicios;
  bool impEducacion;
  bool impVivienda;
  bool impAgropecuario;
  bool impProteccion;
  bool impNecesidades;

  EdanImpactoPoblacion impactoPoblacion;
  EdanNecesidadPrimeraRespuesta necesidadPrimeraRespuesta;
  List<EdanEstablecimientoSalud> establecimientosSalud;
  EdanNecesidadSalud necesidadSalud;
  List<EdanDanoVial> danosViales;
  List<EdanDanoInfraPublica> danosInfraPublica;
  EdanDanoServicioBasico serviciosBasicos;
  List<EdanDanoUnidadEducativa> unidadesEducativas;
  List<EdanDanoVivienda> danosVivienda;
  List<EdanDanoAgricultura> danosAgricultura;
  List<EdanDanoPecuario> danosPecuarios;
  List<EdanInfraProductiva> infraProductiva;
  EdanProteccion proteccion;
  EdanNecesidadHumanitaria necesidadHumanitaria;

  String get etiquetaLugar {
    final t = tipoLocalidad.trim();
    final n = nombre.trim();
    if (n.isEmpty) return t;
    if (t.isEmpty) return n;
    return '$t $n';
  }

  EdanLocalidad({
    this.tipoLocalidad = '',
    this.nombre = '',
    this.impPoblacion = false,
    this.impSalud = false,
    this.impInfraestructura = false,
    this.impServicios = false,
    this.impEducacion = false,
    this.impVivienda = false,
    this.impAgropecuario = false,
    this.impProteccion = false,
    this.impNecesidades = false,
    EdanImpactoPoblacion? impactoPoblacion,
    EdanNecesidadPrimeraRespuesta? necesidadPrimeraRespuesta,
    List<EdanEstablecimientoSalud>? establecimientosSalud,
    EdanNecesidadSalud? necesidadSalud,
    List<EdanDanoVial>? danosViales,
    List<EdanDanoInfraPublica>? danosInfraPublica,
    EdanDanoServicioBasico? serviciosBasicos,
    List<EdanDanoUnidadEducativa>? unidadesEducativas,
    List<EdanDanoVivienda>? danosVivienda,
    List<EdanDanoAgricultura>? danosAgricultura,
    List<EdanDanoPecuario>? danosPecuarios,
    List<EdanInfraProductiva>? infraProductiva,
    EdanProteccion? proteccion,
    EdanNecesidadHumanitaria? necesidadHumanitaria,
  })  : impactoPoblacion = impactoPoblacion ?? EdanImpactoPoblacion(),
        necesidadPrimeraRespuesta =
            necesidadPrimeraRespuesta ?? EdanNecesidadPrimeraRespuesta(),
        establecimientosSalud = establecimientosSalud ?? [],
        necesidadSalud = necesidadSalud ?? EdanNecesidadSalud(),
        danosViales = danosViales ?? [],
        danosInfraPublica = danosInfraPublica ?? [],
        serviciosBasicos = serviciosBasicos ?? EdanDanoServicioBasico(),
        unidadesEducativas = unidadesEducativas ?? [],
        danosVivienda = danosVivienda ?? [],
        danosAgricultura = danosAgricultura ?? [],
        danosPecuarios = danosPecuarios ?? [],
        infraProductiva = infraProductiva ?? [],
        proteccion = proteccion ?? EdanProteccion(),
        necesidadHumanitaria = necesidadHumanitaria ?? EdanNecesidadHumanitaria();

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

    return EdanLocalidad(
      tipoLocalidad: json['tipo_localidad'] ?? json['tipoLocalidad'] ?? '',
      nombre: json['nombre'] ?? json['nombre_comunidad'] ?? json['nombreComunidad'] ?? '',
      impPoblacion: _toBool(json['imp_poblacion'] ?? json['impPoblacion']),
      impSalud: _toBool(json['imp_salud'] ?? json['impSalud']),
      impInfraestructura:
          _toBool(json['imp_infraestructura'] ?? json['impInfraestructura']),
      impServicios: _toBool(json['imp_servicios'] ?? json['impServicios']),
      impEducacion: _toBool(json['imp_educacion'] ?? json['impEducacion']),
      impVivienda: _toBool(json['imp_vivienda'] ?? json['impVivienda']),
      impAgropecuario: _toBool(json['imp_agropecuario'] ?? json['impAgropecuario']),
      impProteccion: _toBool(json['imp_proteccion'] ?? json['impProteccion']),
      impNecesidades: _toBool(json['imp_necesidades'] ?? json['impNecesidades']),
      impactoPoblacion: json['impacto_poblacion'] is Map
          ? EdanImpactoPoblacion.fromJson(
              Map<String, dynamic>.from(json['impacto_poblacion'] as Map))
          : null,
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
      serviciosBasicos:
          (json['servicios_basicos'] is Map ||
                  json['servicios_basicos'] is List)
              ? EdanDanoServicioBasico.fromJson(json['servicios_basicos'])
              : null,
      unidadesEducativas:
          parseList(json['unidades_educativas'], EdanDanoUnidadEducativa.fromJson),
      danosVivienda: parseList(json['danos_vivienda'], EdanDanoVivienda.fromJson),
      danosAgricultura:
          parseList(json['danos_agricultura'], EdanDanoAgricultura.fromJson),
      danosPecuarios: parseList(json['danos_pecuarios'], EdanDanoPecuario.fromJson),
      infraProductiva:
          parseList(json['infra_productiva'], EdanInfraProductiva.fromJson),
      proteccion: json['proteccion'] is Map
          ? EdanProteccion.fromJson(
              Map<String, dynamic>.from(json['proteccion'] as Map))
          : null,
      necesidadHumanitaria: json['necesidad_humanitaria'] is Map
          ? EdanNecesidadHumanitaria.fromJson(
              Map<String, dynamic>.from(json['necesidad_humanitaria'] as Map))
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'tipo_localidad': tipoLocalidad,
        'nombre': nombre,
        'imp_poblacion': impPoblacion,
        'imp_salud': impSalud,
        'imp_infraestructura': impInfraestructura,
        'imp_servicios': impServicios,
        'imp_educacion': impEducacion,
        'imp_vivienda': impVivienda,
        'imp_agropecuario': impAgropecuario,
        'imp_proteccion': impProteccion,
        'imp_necesidades': impNecesidades,
        'impacto_poblacion': impactoPoblacion.toJson(),
        'necesidad_primera_respuesta': necesidadPrimeraRespuesta.toJson(),
        'establecimientos_salud':
            establecimientosSalud.map((e) => e.toJson()).toList(),
        'necesidad_salud': necesidadSalud.toJson(),
        'danos_viales': danosViales.map((e) => e.toJson()).toList(),
        'danos_infra_publica': danosInfraPublica.map((e) => e.toJson()).toList(),
        'servicios_basicos': serviciosBasicos.toJson(),
        'unidades_educativas': unidadesEducativas.map((e) => e.toJson()).toList(),
        'danos_vivienda': danosVivienda.map((e) => e.toJson()).toList(),
        'danos_agricultura': danosAgricultura.map((e) => e.toJson()).toList(),
        'danos_pecuarios': danosPecuarios.map((e) => e.toJson()).toList(),
        'infra_productiva': infraProductiva.map((e) => e.toJson()).toList(),
        'proteccion': proteccion.toJson(),
        'necesidad_humanitaria': necesidadHumanitaria.toJson(),
      };

  bool get tieneImpactos =>
      impPoblacion ||
      impSalud ||
      impInfraestructura ||
      impServicios ||
      impEducacion ||
      impVivienda ||
      impAgropecuario ||
      impProteccion;
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
      nombre: json['nombre'] ?? '',
      cargo: json['cargo'] ?? '',
      fono: json['fono'] ?? '',
      correo: json['correo'] ?? '',
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

  int get localidadesAfectadas => localidades.length;

  Map<String, List<String>> get incompletosPorSeccion {
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
      if (nombreAlcalde.trim().isEmpty) 'Alcalde responsable',
      if (fonoAlcalde.trim().isEmpty) 'Teléfono del alcalde',
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
            !entry.value.impactoPoblacion.tieneDatosGlobales)
          '${etiqueta(entry.value, entry.key)} (impacto en población)',
    ];
    marcar('03', lugares03);

    final lugares04 = <String>[
      for (final entry in localidades.asMap().entries)
        if (entry.value.impSalud &&
            !entry.value.establecimientosSalud
                .any((s) => s.nombreEstablecimiento.trim().isNotEmpty))
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
            !entry.value.serviciosBasicos.algunaSeleccionada)
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
            !entry.value.proteccion.vulnerables.algunoPositivo)
          '${etiqueta(entry.value, entry.key)} (protección)',
    ];
    marcar('10', lugares10);

    final lugares11 = <String>[
      for (final entry in localidades.asMap().entries)
        if (entry.value.impNecesidades &&
            !entry.value.necesidadHumanitaria.algunaSeleccionada)
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
  })  : localidades = localidades ?? [],
        necesidadHumanitaria = necesidadHumanitaria ?? EdanNecesidadHumanitaria(),
        responsable = responsable ?? EdanResponsable();

  factory Edan.empty() => Edan();

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
      codigoEdan: json['codigo_edan'] ?? '',
      idUsuario: _toInt(json['id_usuario']),
      idDepartamento: _toInt(json['id_departamento']),
      idProvincia: _toInt(json['id_provincia']),
      idMunicipio: _toInt(json['id_municipio']),
      departamentoNombre: json['departamento_nombre'] ?? json['departamentoNombre'],
      provinciaNombre: json['provincia_nombre'] ?? json['provinciaNombre'],
      municipioNombre: json['municipio_nombre'] ?? json['municipioNombre'],
      nombreAlcalde: json['nombre_alcalde'] ?? json['nombreAlcalde'] ?? '',
      fonoAlcalde: json['fono_alcalde'] ?? json['fonoAlcalde'] ?? '',
      fechaLlenado: json['fecha_llenado'] ?? json['fechaLlenado'] ?? '',
      fechaEvento: json['fecha_evento'] ?? json['fechaEvento'] ?? '',
      horaEvento: json['hora_evento'] ?? json['horaEvento'] ?? '',
      totalPoblacionAfectada: _toInt(json['total_poblacion_afectada'] ?? json['totalPoblacionAfectada']),
      totalFamiliasAfectadas: _toInt(json['total_familias_afectadas'] ?? json['totalFamiliasAfectadas']),
      totalFamiliasDamnificadas: _toInt(json['total_familias_damnificadas'] ?? json['totalFamiliasDamnificadas']),
      idTipoEvento: _toInt(json['id_tipo_evento'] ?? json['idTipoEvento']),
      tipoEventoNombre: json['tipo_evento_nombre'] ?? json['tipoEventoNombre'],
      localidades: _migrarLocalidades(json, localidades),
      necesidadHumanitaria: json['necesidad_humanitaria'] is Map
          ? EdanNecesidadHumanitaria.fromJson(
              Map<String, dynamic>.from(json['necesidad_humanitaria'] as Map))
          : EdanNecesidadHumanitaria(),
      responsable: json['responsable'] is Map
          ? EdanResponsable.fromJson(
              Map<String, dynamic>.from(json['responsable'] as Map))
          : EdanResponsable(),
      idEstado: _toInt(json['id_estado']) == 0 ? 1 : _toInt(json['id_estado']),
      estado: json['estado'] ?? 'borrador',
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
            .map((m) => (m['nombre_comunidad'] ?? m['nombreComunidad'] ?? '')
                .toString())
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
      tipoLocalidad: json['tipo_localidad'] ?? json['tipoLocalidad'] ?? '',
      nombre: nombres.isNotEmpty ? nombres.first : '',
    );

    if (json['impacto_poblacion'] is Map) {
      localidad.impactoPoblacion = EdanImpactoPoblacion.fromJson(
          Map<String, dynamic>.from(json['impacto_poblacion'] as Map));
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
      localidad.serviciosBasicos =
          EdanDanoServicioBasico.fromJson(json['servicios_basicos']);
      if (localidad.serviciosBasicos.algunaSeleccionada) localidad.impServicios = true;
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
      localidad.proteccion = EdanProteccion.fromJson(
          Map<String, dynamic>.from(json['proteccion'] as Map));
      if (localidad.proteccion.vulnerables.algunoPositivo) {
        localidad.impProteccion = true;
      }
    }

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
        'fecha_llenado': fechaLlenado,
        'fecha_evento': fechaEvento,
        'hora_evento': horaEvento,
        'total_poblacion_afectada': totalPoblacionAfectada,
        'total_familias_afectadas': totalFamiliasAfectadas,
        'total_familias_damnificadas': totalFamiliasDamnificadas,
        'id_tipo_evento': idTipoEvento,
        'tipo_evento_nombre': tipoEventoNombre,
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

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
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
