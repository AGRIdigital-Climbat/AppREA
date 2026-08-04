class EdanGrupoEtario {
  String rango;
  int fallecidos;
  int heridos;
  int desaparecidos;

  EdanGrupoEtario({
    this.rango = '',
    this.fallecidos = 0,
    this.heridos = 0,
    this.desaparecidos = 0,
  });

  factory EdanGrupoEtario.fromJson(Map<String, dynamic> json) {
    return EdanGrupoEtario(
      rango: json['rango'] ?? json['grupo'] ?? '',
      fallecidos: _toInt(json['fallecidos']),
      heridos: _toInt(json['heridos']),
      desaparecidos: _toInt(json['desaparecidos']),
    );
  }

  Map<String, dynamic> toJson() => {
        'rango': rango,
        'fallecidos': fallecidos,
        'heridos': heridos,
        'desaparecidos': desaparecidos,
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
  int atencionInmediata;
  String otrasNecesidades;
  String observaciones;

  EdanNecesidadSalud({
    this.botiquines = false,
    this.atencionInmediata = 0,
    this.otrasNecesidades = '',
    this.observaciones = '',
  });

  factory EdanNecesidadSalud.fromJson(Map<String, dynamic> json) {
    return EdanNecesidadSalud(
      botiquines: _toBool(json['botiquines']),
      atencionInmediata: _toInt(json['atencion_inmediata'] ?? json['atencionInmediata']),
      otrasNecesidades: json['otras_necesidades'] ?? json['otrasNecesidades'] ?? '',
      observaciones: json['observaciones'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'botiquines': botiquines,
        'atencion_inmediata': atencionInmediata,
        'otras_necesidades': otrasNecesidades,
        'observaciones': observaciones,
      };
}

class EdanDanoVial {
  String viaPuente;
  String tramo;
  bool danoParcial;
  bool danoTotal;
  String necesidadesInmediatas;
  String observaciones;

  EdanDanoVial({
    this.viaPuente = '',
    this.tramo = '',
    this.danoParcial = false,
    this.danoTotal = false,
    this.necesidadesInmediatas = '',
    this.observaciones = '',
  });

  factory EdanDanoVial.fromJson(Map<String, dynamic> json) {
    return EdanDanoVial(
      viaPuente: json['via_puente'] ?? json['viaPuente'] ?? '',
      tramo: json['tramo'] ?? '',
      danoParcial: _toBool(json['dano_parcial'] ?? json['danoParcial']),
      danoTotal: _toBool(json['dano_total'] ?? json['danoTotal']),
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

class EdanDanoServicioBasico {
  bool luzElectrica;
  bool aguaPotable;
  bool alcantarillado;
  bool gasDomiciliario;
  bool telecomunicaciones;
  bool danoParcial;
  bool danoTotal;
  String necesidadesInmediatas;
  String observaciones;

  EdanDanoServicioBasico({
    this.luzElectrica = false,
    this.aguaPotable = false,
    this.alcantarillado = false,
    this.gasDomiciliario = false,
    this.telecomunicaciones = false,
    this.danoParcial = false,
    this.danoTotal = false,
    this.necesidadesInmediatas = '',
    this.observaciones = '',
  });

  factory EdanDanoServicioBasico.fromJson(Map<String, dynamic> json) {
    return EdanDanoServicioBasico(
      luzElectrica: _toBool(json['luz_electrica'] ?? json['luzElectrica']),
      aguaPotable: _toBool(json['agua_potable'] ?? json['aguaPotable']),
      alcantarillado: _toBool(json['alcantarillado']),
      gasDomiciliario: _toBool(json['gas_domiciliario'] ?? json['gasDomiciliario']),
      telecomunicaciones: _toBool(json['telecomunicaciones']),
      danoParcial: _toBool(json['dano_parcial'] ?? json['danoParcial']),
      danoTotal: _toBool(json['dano_total'] ?? json['danoTotal']),
      necesidadesInmediatas: json['necesidades_inmediatas'] ??
          json['necesidadesInmediatas'] ??
          '',
      observaciones: json['observaciones'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'luz_electrica': luzElectrica,
        'agua_potable': aguaPotable,
        'alcantarillado': alcantarillado,
        'gas_domiciliario': gasDomiciliario,
        'telecomunicaciones': telecomunicaciones,
        'dano_parcial': danoParcial,
        'dano_total': danoTotal,
        'necesidades_inmediatas': necesidadesInmediatas,
        'observaciones': observaciones,
      };

  bool get algunaSeleccionada =>
      luzElectrica ||
      aguaPotable ||
      alcantarillado ||
      gasDomiciliario ||
      telecomunicaciones;
}

class EdanDanoUnidadEducativa {
  String nombreEstablecimiento;
  String comunidad;
  bool danoParcial;
  bool danoTotal;
  bool suspensionClases;
  bool perdidaMaterial;
  bool funcionaAlbergue;

  EdanDanoUnidadEducativa({
    this.nombreEstablecimiento = '',
    this.comunidad = '',
    this.danoParcial = false,
    this.danoTotal = false,
    this.suspensionClases = false,
    this.perdidaMaterial = false,
    this.funcionaAlbergue = false,
  });

  factory EdanDanoUnidadEducativa.fromJson(Map<String, dynamic> json) {
    return EdanDanoUnidadEducativa(
      nombreEstablecimiento: json['nombre_establecimiento'] ??
          json['nombreEstablecimiento'] ??
          '',
      comunidad: json['comunidad'] ?? '',
      danoParcial: _toBool(json['dano_parcial'] ?? json['danoParcial']),
      danoTotal: _toBool(json['dano_total'] ?? json['danoTotal']),
      suspensionClases: _toBool(json['suspension_clases'] ?? json['suspensionClases']),
      perdidaMaterial: _toBool(json['perdida_material'] ?? json['perdidaMaterial']),
      funcionaAlbergue: _toBool(json['funciona_albergue'] ?? json['funcionaAlbergue']),
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
      };
}

class EdanAfectacionEducativa {
  int estudiantes;
  int profesores;
  int administrativos;
  int totalAfectados;
  String observaciones;

  EdanAfectacionEducativa({
    this.estudiantes = 0,
    this.profesores = 0,
    this.administrativos = 0,
    this.totalAfectados = 0,
    this.observaciones = '',
  });

  factory EdanAfectacionEducativa.fromJson(Map<String, dynamic> json) {
    return EdanAfectacionEducativa(
      estudiantes: _toInt(json['estudiantes']),
      profesores: _toInt(json['profesores']),
      administrativos: _toInt(json['administrativos']),
      totalAfectados: _toInt(json['total_afectados'] ?? json['totalAfectados']),
      observaciones: json['observaciones'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'estudiantes': estudiantes,
        'profesores': profesores,
        'administrativos': administrativos,
        'total_afectados': totalAfectados,
        'observaciones': observaciones,
      };
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
  bool danoParcial;
  bool danoTotal;

  EdanInfraProductiva({
    this.tipo = '',
    this.danoParcial = false,
    this.danoTotal = false,
  });

  factory EdanInfraProductiva.fromJson(Map<String, dynamic> json) {
    return EdanInfraProductiva(
      tipo: json['tipo'] ?? '',
      danoParcial: _toBool(json['dano_parcial'] ?? json['danoParcial']),
      danoTotal: _toBool(json['dano_total'] ?? json['danoTotal']),
    );
  }

  Map<String, dynamic> toJson() => {
        'tipo': tipo,
        'dano_parcial': danoParcial,
        'dano_total': danoTotal,
      };
}

class EdanVulnerables {
  int ninos;
  int adolescentes;
  int mujeresLactantes;
  int mujeresEmbarazadas;
  int adultosMayores;
  int personasDiscapacidad;
  int personasEnfermedad;

  EdanVulnerables({
    this.ninos = 0,
    this.adolescentes = 0,
    this.mujeresLactantes = 0,
    this.mujeresEmbarazadas = 0,
    this.adultosMayores = 0,
    this.personasDiscapacidad = 0,
    this.personasEnfermedad = 0,
  });

  factory EdanVulnerables.fromJson(Map<String, dynamic> json) {
    return EdanVulnerables(
      ninos: _toInt(json['ninos'] ?? json['ninas']),
      adolescentes: _toInt(json['adolescentes']),
      mujeresLactantes: _toInt(json['mujeres_lactantes'] ?? json['mujeresLactantes']),
      mujeresEmbarazadas: _toInt(json['mujeres_embarazadas'] ?? json['mujeresEmbarazadas']),
      adultosMayores: _toInt(json['adultos_mayores'] ?? json['adultosMayores']),
      personasDiscapacidad: _toInt(json['personas_discapacidad'] ?? json['personasDiscapacidad']),
      personasEnfermedad: _toInt(json['personas_enfermedad'] ?? json['personasEnfermedad']),
    );
  }

  Map<String, dynamic> toJson() => {
        'ninos': ninos,
        'adolescentes': adolescentes,
        'mujeres_lactantes': mujeresLactantes,
        'mujeres_embarazadas': mujeresEmbarazadas,
        'adultos_mayores': adultosMayores,
        'personas_discapacidad': personasDiscapacidad,
        'personas_enfermedad': personasEnfermedad,
      };

  bool get algunoPositivo =>
      ninos > 0 ||
      adolescentes > 0 ||
      mujeresLactantes > 0 ||
      mujeresEmbarazadas > 0 ||
      adultosMayores > 0 ||
      personasDiscapacidad > 0 ||
      personasEnfermedad > 0;
}

class EdanProteccion {
  EdanVulnerables vulnerables;
  int mujeres;
  int hombres;
  int total;
  String necesidades;
  String apoyoPsicosocial;
  bool reposicionDocumentos;
  String observaciones;

  EdanProteccion({
    EdanVulnerables? vulnerables,
    this.mujeres = 0,
    this.hombres = 0,
    this.total = 0,
    this.necesidades = '',
    this.apoyoPsicosocial = '',
    this.reposicionDocumentos = false,
    this.observaciones = '',
  }) : vulnerables = vulnerables ?? EdanVulnerables();

  factory EdanProteccion.fromJson(Map<String, dynamic> json) {
    return EdanProteccion(
      vulnerables: json['vulnerables'] is Map
          ? EdanVulnerables.fromJson(
              Map<String, dynamic>.from(json['vulnerables'] as Map))
          : null,
      mujeres: _toInt(json['mujeres']),
      hombres: _toInt(json['hombres']),
      total: _toInt(json['total']),
      necesidades: json['necesidades'] ?? '',
      apoyoPsicosocial: json['apoyo_psicosocial'] ?? json['apoyoPsicosocial'] ?? '',
      reposicionDocumentos: _toBool(json['reposicion_documentos'] ?? json['reposicionDocumentos']),
      observaciones: json['observaciones'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'vulnerables': vulnerables.toJson(),
        'mujeres': mujeres,
        'hombres': hombres,
        'total': total,
        'necesidades': necesidades,
        'apoyo_psicosocial': apoyoPsicosocial,
        'reposicion_documentos': reposicionDocumentos,
        'observaciones': observaciones,
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
  String observaciones;

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
    this.observaciones = '',
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
      observaciones: json['observaciones'] ?? '',
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
        'observaciones': observaciones,
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

  EdanImpactoPoblacion impactoPoblacion;
  EdanNecesidadPrimeraRespuesta necesidadPrimeraRespuesta;
  List<EdanEstablecimientoSalud> establecimientosSalud;
  EdanNecesidadSalud necesidadSalud;
  List<EdanDanoVial> danosViales;
  List<EdanDanoInfraPublica> danosInfraPublica;
  EdanDanoServicioBasico serviciosBasicos;
  List<EdanDanoUnidadEducativa> unidadesEducativas;
  EdanAfectacionEducativa afectacionEducativa;
  List<EdanDanoVivienda> danosVivienda;
  List<EdanDanoAgricultura> danosAgricultura;
  List<EdanDanoPecuario> danosPecuarios;
  List<EdanInfraProductiva> infraProductiva;
  EdanProteccion proteccion;

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
    EdanImpactoPoblacion? impactoPoblacion,
    EdanNecesidadPrimeraRespuesta? necesidadPrimeraRespuesta,
    List<EdanEstablecimientoSalud>? establecimientosSalud,
    EdanNecesidadSalud? necesidadSalud,
    List<EdanDanoVial>? danosViales,
    List<EdanDanoInfraPublica>? danosInfraPublica,
    EdanDanoServicioBasico? serviciosBasicos,
    List<EdanDanoUnidadEducativa>? unidadesEducativas,
    EdanAfectacionEducativa? afectacionEducativa,
    List<EdanDanoVivienda>? danosVivienda,
    List<EdanDanoAgricultura>? danosAgricultura,
    List<EdanDanoPecuario>? danosPecuarios,
    List<EdanInfraProductiva>? infraProductiva,
    EdanProteccion? proteccion,
  })  : impactoPoblacion = impactoPoblacion ?? EdanImpactoPoblacion(),
        necesidadPrimeraRespuesta =
            necesidadPrimeraRespuesta ?? EdanNecesidadPrimeraRespuesta(),
        establecimientosSalud = establecimientosSalud ?? [],
        necesidadSalud = necesidadSalud ?? EdanNecesidadSalud(),
        danosViales = danosViales ?? [],
        danosInfraPublica = danosInfraPublica ?? [],
        serviciosBasicos = serviciosBasicos ?? EdanDanoServicioBasico(),
        unidadesEducativas = unidadesEducativas ?? [],
        afectacionEducativa = afectacionEducativa ?? EdanAfectacionEducativa(),
        danosVivienda = danosVivienda ?? [],
        danosAgricultura = danosAgricultura ?? [],
        danosPecuarios = danosPecuarios ?? [],
        infraProductiva = infraProductiva ?? [],
        proteccion = proteccion ?? EdanProteccion();

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
      serviciosBasicos: json['servicios_basicos'] is Map
          ? EdanDanoServicioBasico.fromJson(
              Map<String, dynamic>.from(json['servicios_basicos'] as Map))
          : null,
      unidadesEducativas:
          parseList(json['unidades_educativas'], EdanDanoUnidadEducativa.fromJson),
      afectacionEducativa: json['afectacion_educativa'] is Map
          ? EdanAfectacionEducativa.fromJson(
              Map<String, dynamic>.from(json['afectacion_educativa'] as Map))
          : null,
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
        'impacto_poblacion': impactoPoblacion.toJson(),
        'necesidad_primera_respuesta': necesidadPrimeraRespuesta.toJson(),
        'establecimientos_salud':
            establecimientosSalud.map((e) => e.toJson()).toList(),
        'necesidad_salud': necesidadSalud.toJson(),
        'danos_viales': danosViales.map((e) => e.toJson()).toList(),
        'danos_infra_publica': danosInfraPublica.map((e) => e.toJson()).toList(),
        'servicios_basicos': serviciosBasicos.toJson(),
        'unidades_educativas': unidadesEducativas.map((e) => e.toJson()).toList(),
        'afectacion_educativa': afectacionEducativa.toJson(),
        'danos_vivienda': danosVivienda.map((e) => e.toJson()).toList(),
        'danos_agricultura': danosAgricultura.map((e) => e.toJson()).toList(),
        'danos_pecuarios': danosPecuarios.map((e) => e.toJson()).toList(),
        'infra_productiva': infraProductiva.map((e) => e.toJson()).toList(),
        'proteccion': proteccion.toJson(),
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

  int get localidadesAfectadas => localidades.length;

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
            (json['afectacion_educativa'] is Map) ||
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
    if (json['servicios_basicos'] is Map) {
      localidad.serviciosBasicos = EdanDanoServicioBasico.fromJson(
          Map<String, dynamic>.from(json['servicios_basicos'] as Map));
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
    if (json['afectacion_educativa'] is Map) {
      localidad.afectacionEducativa = EdanAfectacionEducativa.fromJson(
          Map<String, dynamic>.from(json['afectacion_educativa'] as Map));
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
      if (localidad.proteccion.vulnerables.algunoPositivo ||
          localidad.proteccion.mujeres > 0 ||
          localidad.proteccion.hombres > 0) {
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
