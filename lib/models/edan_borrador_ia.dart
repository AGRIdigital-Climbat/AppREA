/// Borrador intermedio del "Asistente de llenado con IA" (rol 7 RESP / rol 6 UGR).
///
/// Es la CAPA A del diseño: un representation *tolerante* de lo que la persona
/// contó por voz o texto. Deliberadamente NO conoce ids de catálogo ni nombres
/// de tabla: guarda texto tal cual y números como `int?`.
///
/// Motivo de esta capa: el extractor determinista y la IA producen un lenguaje
/// intermedio ("350 familias afectadas") que no encaja 1:1 en SQLite, donde
/// `seccion_danos_agricultura` exige `id_cultivo` y `hectareas_afectadas` como
/// entero. Traducir en un solo punto ([EdanTraduccion] en
/// `services/edan_ia/edan_traduccion.dart`) hace que la operación sea testeable
/// sin base de datos y que se pueda ver exactamente qué dato va a cada tabla.
///
/// Regla de todo el modelo: `null` (o `''`) significa **"no detectado"**, nunca
/// "cero". Por eso todos los números son nulables. El cero explícito ("no hubo
/// heridos") se representa con el valor `0` y es un dato válido.
library;

/// Cómo llegó un dato: útil para marcar en la UI lo que fue dictado.
enum EdanOrigen { voz, texto }

// ---------------------------------------------------------------------------
// Constantes del esquema (puerto de EDAN-Tutor/src/schema/edan.js)
// ---------------------------------------------------------------------------

/// Grupos etarios del bloque de impacto en población. El orden importa: es el
/// índice que usa el extractor paraPlacement cuando no hay grupo explícito.
const List<String> kEdanGruposEdad = [
  'Niño(a) 0-5 años',
  'Escolar 6-18 años',
  'Adulto 19-60 años',
  'Adulto mayor 60+',
];

/// Equipos de primera respuesta. En SQLite es una fila 1:1 con 3 booleanos.
const List<String> kEdanEquiposPrimeraRespuesta = [
  'Búsqueda',
  'Salvamento/Rescate',
  'Evacuación',
];

/// Grupos de protección. Sus etiquetas NO coinciden con las del catálogo
/// `catalogo_grupo_vulnerable`; la traducción resuelve por similitud de
/// nombre (ver `edan_traduccion.dart`).
const List<String> kEdanGruposProteccion = [
  'Niñas y Niños',
  'Adolescentes',
  'Mujeres Lactantes',
  'Mujeres Embarazadas',
  'Adultos Mayores',
  'Personas con Discapacidad',
  'Enfermedad Inhabilitante',
];

/// Ítems del formulario EDAN-Tutor. OJO: el SQLite real tiene 9 casillas
/// distintas (ver `EdanNecesidadBorrador`). Esta lista es el vocabulario de
/// entrada; el mapeo al SQLite está en la traducción.
const List<String> kEdanNecesidadesHumanitarias = [
  'Alimentos',
  'Refugio y Vivienda',
  'Ropa de Cama',
  'Artículos de Higiene',
  'Artículos de Cocina',
  'Tanques de Agua',
  'Pastillas Potabilizadoras',
  'Filtros Vela',
  'Politubos',
  'Carro Cisterna',
];

/// Tipos de evento con su clave canónica (la clave se usa como patch key).
const List<String> kEdanClavesEvento = [
  'inundacion',
  'riada',
  'deslizamiento',
  'helada',
  'granizada',
  'sequia',
  'incendios',
];

/// Etiqueta legible de cada clave de evento.
const Map<String, String> kEdanEtiquetasEvento = {
  'inundacion': 'Inundación',
  'riada': 'Riada',
  'deslizamiento': 'Deslizamiento',
  'helada': 'Helada',
  'granizada': 'Granizada',
  'sequia': 'Sequía',
  'incendios': 'Incendios',
};

/// Servicios básicos: clave interna -> `tipo` exacto que espera la columna
/// `seccion_servicios_basicos.tipo` (ver `EdanServicioBasicoDetalle.etiqueta`).
const Map<String, String> kEdanServiciosBasicos = {
  'luz': 'energia_electrica',
  'agua': 'agua_potable',
  'alcantarillado': 'alcantarillado',
  'gas': 'gas_domiciliario',
  'telecom': 'telecomunicaciones',
};

/// Secciones del formulario, en el orden en que se muestran. La clave
/// coincide con la ruta v2 de `EdanSeccionesRegistry` para las 14 secciones
/// reales; `cabecera` agrupa lo que vive en `localidades_offline`.
class EdanSeccionBorrador {
  final String key;
  final String titulo;

  const EdanSeccionBorrador(this.key, this.titulo);
}

const List<EdanSeccionBorrador> kEdanSeccionesBorrador = [
  EdanSeccionBorrador('cabecera', 'Datos generales'),
  EdanSeccionBorrador('impacto-poblacion', 'Impacto en la población'),
  EdanSeccionBorrador('primera-respuesta', 'Primera respuesta'),
  EdanSeccionBorrador('salud-establecimientos', 'Salud'),
  EdanSeccionBorrador('necesidad-salud', 'Necesidad de salud'),
  EdanSeccionBorrador('danos-viales', 'Daños viales'),
  EdanSeccionBorrador('danos-infra-publica', 'Infraestructura pública'),
  EdanSeccionBorrador('servicios-basicos', 'Servicios básicos'),
  EdanSeccionBorrador('unidades-educativas', 'Educación'),
  EdanSeccionBorrador('danos-vivienda', 'Vivienda'),
  EdanSeccionBorrador('danos-agricultura', 'Agricultura'),
  EdanSeccionBorrador('danos-pecuarios', 'Pecuario'),
  EdanSeccionBorrador('infra-productiva', 'Infraestructura productiva'),
  EdanSeccionBorrador('proteccion', 'Protección'),
  EdanSeccionBorrador('necesidad-humanitaria', 'Necesidades humanitarias'),
];

// ---------------------------------------------------------------------------
// Filas 1:N
// ---------------------------------------------------------------------------

/// Puente o vía dañada. Se fusiona por `via` (clave natural).
class BchDanoVial {
  String via;
  String tramo;
  String danoParcial;
  String danoTotal;
  String kmDanio;
  String necesidades;
  String observaciones;
  EdanOrigen? origen;

  BchDanoVial({
    this.via = '',
    this.tramo = '',
    this.danoParcial = '',
    this.danoTotal = '',
    this.kmDanio = '',
    this.necesidades = '',
    this.observaciones = '',
    this.origen,
  });

  BchDanoVial copy() => BchDanoVial(
        via: via,
        tramo: tramo,
        danoParcial: danoParcial,
        danoTotal: danoTotal,
        kmDanio: kmDanio,
        necesidades: necesidades,
        observaciones: observaciones,
        origen: origen,
      );

  /// `relleno` es la única definición de "esto es un dato": ignora `null`, texto
  /// en blanco y `false`, y cuenta un `0` explícito. Delegar aquí evita que cada
  /// fila tenga su propio criterio y que la traducción y el progreso discrepen.
  bool get tieneDatos => relleno(this);
}

/// Estructura de servicio público dañada. Clave natural: `tipo + comunidad`.
class BchInfraPublica {
  String comunidad;
  String tipoEstructura;
  String danoParcial;
  String danoTotal;
  String necesidades;
  String observaciones;
  EdanOrigen? origen;

  BchInfraPublica({
    this.comunidad = '',
    this.tipoEstructura = '',
    this.danoParcial = '',
    this.danoTotal = '',
    this.necesidades = '',
    this.observaciones = '',
    this.origen,
  });

  BchInfraPublica copy() => BchInfraPublica(
        comunidad: comunidad,
        tipoEstructura: tipoEstructura,
        danoParcial: danoParcial,
        danoTotal: danoTotal,
        necesidades: necesidades,
        observaciones: observaciones,
        origen: origen,
      );

  bool get tieneDatos => relleno(this);
}

/// Unidad productiva dañada. Clave natural: `tipo + comunidad`.
class BchInfraProductiva {
  String tipo;
  String comunidad;
  String danoParcial;
  String danoTotal;
  String necesidades;
  String observaciones;
  EdanOrigen? origen;

  BchInfraProductiva({
    this.tipo = '',
    this.comunidad = '',
    this.danoParcial = '',
    this.danoTotal = '',
    this.necesidades = '',
    this.observaciones = '',
    this.origen,
  });

  BchInfraProductiva copy() => BchInfraProductiva(
        tipo: tipo,
        comunidad: comunidad,
        danoParcial: danoParcial,
        danoTotal: danoTotal,
        necesidades: necesidades,
        observaciones: observaciones,
        origen: origen,
      );

  bool get tieneDatos => relleno(this);
}

/// Establecimiento de salud dañado. Clave natural: `establecimiento`.
class BchEstablecimientoSalud {
  String establecimiento;
  String comunidad;
  String nivel;
  String dano;
  String observaciones;
  EdanOrigen? origen;

  BchEstablecimientoSalud({
    this.establecimiento = '',
    this.comunidad = '',
    this.nivel = '',
    this.dano = '',
    this.observaciones = '',
    this.origen,
  });

  BchEstablecimientoSalud copy() => BchEstablecimientoSalud(
        establecimiento: establecimiento,
        comunidad: comunidad,
        nivel: nivel,
        dano: dano,
        observaciones: observaciones,
        origen: origen,
      );

  bool get tieneDatos => relleno(this);
}

/// Unidad educativa con daños o con afectación de estudiantes. Clave natural:
/// `establecimiento + comunidad` (las dos listas del EDAN-Tutor se funden en
/// una sola fila, igual que en `seccion_unidades_educativas`).
class BchUnidadEducativa {
  String establecimiento;
  String comunidad;
  String danoParcial;
  String danoTotal;
  bool suspensionClases;
  int? estudiantes;
  String observaciones;
  EdanOrigen? origen;

  BchUnidadEducativa({
    this.establecimiento = '',
    this.comunidad = '',
    this.danoParcial = '',
    this.danoTotal = '',
    this.suspensionClases = false,
    this.estudiantes,
    this.observaciones = '',
    this.origen,
  });

  BchUnidadEducativa copy() => BchUnidadEducativa(
        establecimiento: establecimiento,
        comunidad: comunidad,
        danoParcial: danoParcial,
        danoTotal: danoTotal,
        suspensionClases: suspensionClases,
        estudiantes: estudiantes,
        observaciones: observaciones,
        origen: origen,
      );

  bool get tieneDatos => relleno(this);
}

/// Viviendas dañadas. Clave natural: `comunidad`.
class BchDanoVivienda {
  String comunidad;
  int? danoParcial;
  int? danoTotal;
  String necesidades;
  String observaciones;
  EdanOrigen? origen;

  BchDanoVivienda({
    this.comunidad = '',
    this.danoParcial,
    this.danoTotal,
    this.necesidades = '',
    this.observaciones = '',
    this.origen,
  });

  BchDanoVivienda copy() => BchDanoVivienda(
        comunidad: comunidad,
        danoParcial: danoParcial,
        danoTotal: danoTotal,
        necesidades: necesidades,
        observaciones: observaciones,
        origen: origen,
      );

  bool get tieneDatos => relleno(this);
}

/// Cultivo con hectáreas. Clave natural: `cultivo`.
class BchAgricultura {
  String cultivo;
  int? hasAfectadas;
  int? hasPerdidas;
  String necesidades;
  String observaciones;
  EdanOrigen? origen;

  BchAgricultura({
    this.cultivo = '',
    this.hasAfectadas,
    this.hasPerdidas,
    this.necesidades = '',
    this.observaciones = '',
    this.origen,
  });

  BchAgricultura copy() => BchAgricultura(
        cultivo: cultivo,
        hasAfectadas: hasAfectadas,
        hasPerdidas: hasPerdidas,
        necesidades: necesidades,
        observaciones: observaciones,
        origen: origen,
      );

  bool get tieneDatos => relleno(this);
}

/// Especie ganadera afectada. Clave natural: `especie`.
class BchPecuario {
  String especie;
  int? animalesAfectados;
  int? animalesMuertos;
  String necesidades;
  String observaciones;
  EdanOrigen? origen;

  BchPecuario({
    this.especie = '',
    this.animalesAfectados,
    this.animalesMuertos,
    this.necesidades = '',
    this.observaciones = '',
    this.origen,
  });

  BchPecuario copy() => BchPecuario(
        especie: especie,
        animalesAfectados: animalesAfectados,
        animalesMuertos: animalesMuertos,
        necesidades: necesidades,
        observaciones: observaciones,
        origen: origen,
      );

  bool get tieneDatos => relleno(this);
}

/// Comunidad o barrio afectado. Se acumula en `localidades_offline.localidad`.
class BchComunidad {
  String nombre;

  BchComunidad({this.nombre = ''});

  BchComunidad copy() => BchComunidad(nombre: nombre);

  bool get tieneDatos => relleno(this);
}

// ---------------------------------------------------------------------------
// Bloques de tamaño fijo
// ---------------------------------------------------------------------------

/// Fila de impacto en población, identificada por [grupo] (etiqueta de
/// `kEdanGruposEdad`). `marcado` distingue "el grupo no aplica" de "el grupo
/// aplica y tiene ceros", que es lo que el formulario real persiste.
class BchImpactoFila {
  final String grupo;
  int? fallecidos;
  int? heridos;
  int? desaparecidos;
  String observaciones;
  bool marcado;
  EdanOrigen? origen;

  BchImpactoFila(
    this.grupo, {
    this.fallecidos,
    this.heridos,
    this.desaparecidos,
    this.observaciones = '',
    this.marcado = false,
    this.origen,
  });

  BchImpactoFila copy() => BchImpactoFila(
        grupo,
        fallecidos: fallecidos,
        heridos: heridos,
        desaparecidos: desaparecidos,
        observaciones: observaciones,
        marcado: marcado,
        origen: origen,
      );

  /// Una cifra detectada ya es dato, aunque no se haya marcado la casilla: el
  /// grupo cuenta. `marcado` sigue sirviendo para decir "en este grupo no hubo
  /// casualties" sin inventar un cero.
  bool get tieneDatos => relleno(this);
}

/// Fila de protección, identificada por [grupo].
///
/// [total] es la cifra tal como la dijo la persona. SQLite separa
/// `mujeres`/`hombres`, así que el extractor guarda además el desglose cuando la
/// frase lo da ("40 mujeres y 30 hombres"). Si solo hay [total] y el grupo no
/// distingue sexo, la traducción NO lo reparte sola: lo deja en observaciones y
/// avisa, porque inventar el desglose sería falsear el dato.
class BchProteccionFila {
  final String grupo;
  int? total;
  int? mujeres;
  int? hombres;
  String observaciones;
  EdanOrigen? origen;

  BchProteccionFila(
    this.grupo, {
    this.total,
    this.mujeres,
    this.hombres,
    this.observaciones = '',
    this.origen,
  });

  BchProteccionFila copy() => BchProteccionFila(
        grupo,
        total: total,
        mujeres: mujeres,
        hombres: hombres,
        observaciones: observaciones,
        origen: origen,
      );

  /// ¿Hay desglose por sexo? Si no, la traducción tiene que resolverlo.
  bool get tieneDesglose => mujeres != null || hombres != null;

  bool get tieneDatos => relleno(this);
}

/// Casilla de necesidad humanaitaria, identificada por [item].
class BchNecesidadFila {
  final String item;
  bool si;
  String observaciones;
  EdanOrigen? origen;

  BchNecesidadFila(
    this.item, {
    this.si = false,
    this.observaciones = '',
    this.origen,
  });

  BchNecesidadFila copy() => BchNecesidadFila(
        item,
        si: si,
        observaciones: observaciones,
        origen: origen,
      );

  bool get tieneDatos => relleno(this);
}

/// Detalle por servicio básico. `danoParcial`/`danoTotal` quedan como texto
/// porque la persona dice "se dañó a medias" o "5 km" y no un booleano.
class BchServicioDetalle {
  String danoParcial;
  String danoTotal;
  String necesidades;
  String observaciones;
  EdanOrigen? origen;

  BchServicioDetalle({
    this.danoParcial = '',
    this.danoTotal = '',
    this.necesidades = '',
    this.observaciones = '',
    this.origen,
  });

  BchServicioDetalle copy() => BchServicioDetalle(
        danoParcial: danoParcial,
        danoTotal: danoTotal,
        necesidades: necesidades,
        observaciones: observaciones,
        origen: origen,
      );

  bool get tieneDatos => relleno(this);
}

/// Equipos de primera respuesta (sección 1:1 en SQLite: 3 booleanos).
class BchPrimeraRespuesta {
  bool busqueda;
  bool salvamento;
  bool evacuacion;
  String observaciones;
  EdanOrigen? origen;

  BchPrimeraRespuesta({
    this.busqueda = false,
    this.salvamento = false,
    this.evacuacion = false,
    this.observaciones = '',
    this.origen,
  });

  BchPrimeraRespuesta copy() => BchPrimeraRespuesta(
        busqueda: busqueda,
        salvamento: salvamento,
        evacuacion: evacuacion,
        observaciones: observaciones,
        origen: origen,
      );

  bool get tieneDatos => relleno(this);
}

/// Necesidad de atención en salud (sección 1:1).
class BchNecesidadSalud {
  String incendio;
  String inundacion;
  String sequia;
  String otras;
  String observaciones;
  EdanOrigen? origen;

  BchNecesidadSalud({
    this.incendio = '',
    this.inundacion = '',
    this.sequia = '',
    this.otras = '',
    this.observaciones = '',
    this.origen,
  });

  BchNecesidadSalud copy() => BchNecesidadSalud(
        incendio: incendio,
        inundacion: inundacion,
        sequia: sequia,
        otras: otras,
        observaciones: observaciones,
        origen: origen,
      );

  bool get tieneDatos => relleno(this);
}

// ---------------------------------------------------------------------------
// El borrador completo
// ---------------------------------------------------------------------------

/// Estado intermedio completo de la entrevista.
///
/// Todas las listas de tamaño fijo se crean pobladas desde las constantes, para
/// que la traduzca siempre encuentre la fila aunque venga un parche parcial.
/// Las listas 1:n arrancan vacías y crecen con lo que se detecte.
class EdanBorradorIa {
  // Cabecera (localidades_offline)
  String departamento;
  String provincia;
  String municipio;
  String alcalde;
  String telefono;
  String fechaLlenado;
  String fechaEvento;
  String horaEvento;
  String tipoEventoOtro;
  String responsableNombre;
  String responsableCargo;
  String responsableTelefono;
  String responsableEmail;

  // Conteos (localidades_offline)
  int? totalAfectada;
  int? totalFamiliasAfectadas;
  int? totalFamiliasDamnificadas;

  // Totales de vivienda: en SQLite no hay columnas, se materializan como una
  // fila de `seccion_danos_vivienda`.
  int? viviendasAfectadas;
  int? viviendasDamnificadas;
  String viviendaObservaciones;

  // Bloques fijos
  Map<String, bool> tipoEvento;
  List<BchImpactoFila> impactoPoblacion;
  List<BchProteccionFila> proteccion;
  List<BchNecesidadFila> necesidadesHumanitarias;
  List<BchComunidad> comunidades;
  Map<String, BchServicioDetalle> serviciosBasicos;
  BchPrimeraRespuesta primeraRespuesta;
  BchNecesidadSalud necesidadSalud;

  // Listas 1:n
  List<BchDanoVial> infraVial;
  List<BchInfraPublica> infraPublica;
  List<BchInfraProductiva> infraProductiva;
  List<BchEstablecimientoSalud> saludDanios;
  List<BchUnidadEducativa> educacion;
  List<BchDanoVivienda> danosVivienda;
  List<BchAgricultura> agricultura;
  List<BchPecuario> pecuario;

  /// Resumen legible de lo que la última extracción detectó. Alimenta el aviso
  /// "Anotado en la ficha: …" de la vista.
  List<String> ultimaActualizacion = const [];

  EdanBorradorIa()
      : departamento = '',
        provincia = '',
        municipio = '',
        alcalde = '',
        telefono = '',
        fechaLlenado = hoyIso(),
        fechaEvento = '',
        horaEvento = '',
        tipoEventoOtro = '',
        responsableNombre = '',
        responsableCargo = '',
        responsableTelefono = '',
        responsableEmail = '',
        viviendasAfectadas = null,
        viviendasDamnificadas = null,
        viviendaObservaciones = '',
        tipoEvento = {for (final k in kEdanClavesEvento) k: false},
        impactoPoblacion = [
          for (final g in kEdanGruposEdad) BchImpactoFila(g),
        ],
        proteccion = [
          for (final g in kEdanGruposProteccion) BchProteccionFila(g),
        ],
        necesidadesHumanitarias = [
          for (final i in kEdanNecesidadesHumanitarias) BchNecesidadFila(i),
        ],
        comunidades = [],
        serviciosBasicos = {
          for (final k in kEdanServiciosBasicos.keys)
            k: BchServicioDetalle(),
        },
        primeraRespuesta = BchPrimeraRespuesta(),
        necesidadSalud = BchNecesidadSalud(),
        infraVial = [],
        infraPublica = [],
        infraProductiva = [],
        saludDanios = [],
        educacion = [],
        danosVivienda = [],
        agricultura = [],
        pecuario = [];

  /// Copia profunda. La fusión nunca muta el original (puerto de
  /// `structuredClone` de `merge.js`).
  EdanBorradorIa copy() {
    final c = EdanBorradorIa()
      ..departamento = departamento
      ..provincia = provincia
      ..municipio = municipio
      ..alcalde = alcalde
      ..telefono = telefono
      ..fechaLlenado = fechaLlenado
      ..fechaEvento = fechaEvento
      ..horaEvento = horaEvento
      ..tipoEventoOtro = tipoEventoOtro
      ..responsableNombre = responsableNombre
      ..responsableCargo = responsableCargo
      ..responsableTelefono = responsableTelefono
      ..responsableEmail = responsableEmail
      ..totalAfectada = totalAfectada
      ..totalFamiliasAfectadas = totalFamiliasAfectadas
      ..totalFamiliasDamnificadas = totalFamiliasDamnificadas
      ..viviendasAfectadas = viviendasAfectadas
      ..viviendasDamnificadas = viviendasDamnificadas
      ..viviendaObservaciones = viviendaObservaciones
      ..tipoEvento = Map<String, bool>.from(tipoEvento)
      ..impactoPoblacion = impactoPoblacion.map((f) => f.copy()).toList()
      ..proteccion = proteccion.map((f) => f.copy()).toList()
      ..necesidadesHumanitarias =
          necesidadesHumanitarias.map((f) => f.copy()).toList()
      ..comunidades = comunidades.map((f) => f.copy()).toList()
      ..serviciosBasicos = {
        for (final e in serviciosBasicos.entries) e.key: e.value.copy(),
      }
      ..primeraRespuesta = primeraRespuesta.copy()
      ..necesidadSalud = necesidadSalud.copy()
      ..infraVial = infraVial.map((f) => f.copy()).toList()
      ..infraPublica = infraPublica.map((f) => f.copy()).toList()
      ..infraProductiva = infraProductiva.map((f) => f.copy()).toList()
      ..saludDanios = saludDanios.map((f) => f.copy()).toList()
      ..educacion = educacion.map((f) => f.copy()).toList()
      ..danosVivienda = danosVivienda.map((f) => f.copy()).toList()
      ..agricultura = agricultura.map((f) => f.copy()).toList()
      ..pecuario = pecuario.map((f) => f.copy()).toList()
      ..ultimaActualizacion = List<String>.from(ultimaActualizacion);
    return c;
  }

  /// ¿Hay algo en toda la entrevista? Determina si se puede cerrar sin perder
  /// trabajo (mismo criterio que `_esEdanVacio` del wizard).
  ///
  /// Se recorre con `_hojas` sobre una lista explícita de campos porque Dart
  /// no tiene reflexión: pasarle `this` a `_hojas` no inspeccionaría nada y
  /// devolvería siempre "no vacío". `fechaLlenado` queda fuera a propósito (trae
  /// la fecha de hoy por defecto y haría que todo borrador pareciera lleno).
  bool get vacio => !_hojas(<Object?>[
        departamento,
        provincia,
        municipio,
        alcalde,
        telefono,
        fechaEvento,
        horaEvento,
        tipoEventoOtro,
        responsableNombre,
        responsableCargo,
        responsableTelefono,
        responsableEmail,
        totalAfectada,
        totalFamiliasAfectadas,
        totalFamiliasDamnificadas,
        viviendasAfectadas,
        viviendasDamnificadas,
        viviendaObservaciones,
        tipoEvento,
        impactoPoblacion,
        proteccion,
        necesidadesHumanitarias,
        comunidades,
        serviciosBasicos,
        primeraRespuesta,
        necesidadSalud,
        infraVial,
        infraPublica,
        infraProductiva,
        saludDanios,
        educacion,
        danosVivienda,
        agricultura,
        pecuario,
      ]).any(relleno);

  /// Nombres de los tipos de evento marcados.
  List<String> get etiquetasEvento => [
        for (final k in kEdanClavesEvento)
          if (tipoEvento[k] == true) kEdanEtiquetasEvento[k]!,
        if (tipoEventoOtro.isNotEmpty) tipoEventoOtro,
      ];

  /// Fila de impacto del grupo [grupo] (o null si la etiqueta no existe).
  BchImpactoFila? impactoDe(String grupo) {
    for (final f in impactoPoblacion) {
      if (f.grupo == grupo) return f;
    }
    return null;
  }

  /// Fila de protección del grupo [grupo] (o null).
  BchProteccionFila? proteccionDe(String grupo) {
    for (final f in proteccion) {
      if (f.grupo == grupo) return f;
    }
    return null;
  }

  /// Fila de necesidad del ítem [item] (o null).
  BchNecesidadFila? necesidadDe(String item) {
    for (final f in necesidadesHumanitarias) {
      if (f.item == item) return f;
    }
    return null;
  }

  /// Detalle del servicio [clave] (o null si la clave no es de servicio).
  BchServicioDetalle? servicioDe(String clave) => serviciosBasicos[clave];

  /// ¿Hay alguna vivienda dañada/destruida registrada?
  bool get tieneVivienda =>
      viviendasAfectadas != null ||
      viviendasDamnificadas != null ||
      danosVivienda.any((f) => f.tieneDatos);
}

// ---------------------------------------------------------------------------
// Progreso
// ---------------------------------------------------------------------------

/// Progreso 0..1 de una sección del borrador. Mismo criterio que
/// `seccionProgreso` de EDAN-Tutor: cuenta hojas de datos, no bloques, para que
/// un campo omitido a propósito ("no hubo heridos") puntúe distinto de uno
/// simplemente vacío.
double seccionProgreso(String seccionKey, EdanBorradorIa b) {
  double porcentaje(Object? obj) {
    final vals = _hojas(obj);
    if (vals.isEmpty) return 0;
    return vals.where(relleno).length / vals.length;
  }

  switch (seccionKey) {
    case 'impacto-poblacion':
      return porcentaje(b.impactoPoblacion);
    case 'primera-respuesta':
      return b.primeraRespuesta.tieneDatos ? 1.0 : 0.0;
    case 'salud-establecimientos':
      return b.saludDanios.isNotEmpty ? 1 : 0;
    case 'necesidad-salud':
      return b.necesidadSalud.tieneDatos ? 1 : 0;
    case 'danos-viales':
      return b.infraVial.any((f) => f.tieneDatos) ? 1 : 0;
    case 'danos-infra-publica':
      return b.infraPublica.any((f) => f.tieneDatos) ? 1 : 0;
    case 'servicios-basicos':
      return porcentaje(b.serviciosBasicos);
    case 'unidades-educativas':
      return b.educacion.any((f) => f.tieneDatos) ? 1 : 0;
    case 'danos-vivienda':
      return b.tieneVivienda ? 1 : 0;
    case 'danos-agricultura':
      return b.agricultura.any((f) => f.tieneDatos) ? 1 : 0;
    case 'danos-pecuarios':
      return b.pecuario.any((f) => f.tieneDatos) ? 1 : 0;
    case 'infra-productiva':
      return b.infraProductiva.any((f) => f.tieneDatos) ? 1 : 0;
    case 'proteccion':
      return porcentaje(b.proteccion);
    case 'necesidad-humanitaria':
      if (b.necesidadesHumanitarias.isEmpty) return 0;
      return b.necesidadesMarcadasCount() / b.necesidadesHumanitarias.length;
    case 'cabecera':
      return porcentaje(<String, Object?>{
        'departamento': b.departamento,
        'municipio': b.municipio,
        'fechaEvento': b.fechaEvento,
        'horaEvento': b.horaEvento,
        'totalAfectada': b.totalAfectada,
        'totalFamiliasAfectadas': b.totalFamiliasAfectadas,
        'totalFamiliasDamnificadas': b.totalFamiliasDamnificadas,
      });
    default:
      return 0;
  }
}

/// Progreso de todas las secciones del borrador, en orden.
List<EdanProgresoSeccion> progresoGlobal(EdanBorradorIa b) => [
      for (final s in kEdanSeccionesBorrador)
        EdanProgresoSeccion(s.key, s.titulo, seccionProgreso(s.key, b)),
    ];

/// Secciones cuyo progreso está por debajo del umbral, de la más vacía a la
/// más vacía. Es la lista que el tutor usa para decidir qué preguntar.
List<EdanProgresoSeccion> seccionesIncompletas(
  List<EdanProgresoSeccion> progreso, {
  double umbral = 0.6,
  int maximo = 3,
}) {
  final incompletas = progreso.where((s) => s.valor < umbral).toList()
    ..sort((a, b) => a.valor.compareTo(b.valor));
  return incompletas.take(maximo).toList();
}

/// Una sección con su avance, para pintar los chips de progreso.
class EdanProgresoSeccion {
  final String key;
  final String titulo;
  final double valor;

  const EdanProgresoSeccion(this.key, this.titulo, this.valor);

  bool get completo => valor >= 0.999;
}

// ---------------------------------------------------------------------------
// Utilidades
// ---------------------------------------------------------------------------

/// Fecha de hoy en ISO corto (`yyyy-MM-dd`), igual que `hoyISO()` del esquema.
String hoyIso() {
  final d = DateTime.now();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)}';
}

/// ¿El valor cuenta como "dato capturado"?
bool relleno(Object? v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is int || v is double) return true;
  if (v is String) return v.trim().isNotEmpty;
  if (v is List) return v.isNotEmpty;
  if (v is Map) return v.values.any(relleno);
  if (v is EdanBorradorIa) return !v.vacio;
  return _hojas(v).any(relleno);
}

/// Aplana un objeto a la lista de sus valores "hoja", ignorando las claves de
/// etiqueta (`grupo`, `item`) para no contarlas como dato capturado.
List<Object?> _hojas(Object? obj) {
  final out = <Object?>[];
  const ignorar = {'grupo', 'item', 'especie', 'cultivo', 'via', 'establecimiento'};
  void walk(Object? o) {
    if (o is List) {
      o.forEach(walk);
      return;
    }
    if (o is Map) {
      o.forEach((k, v) {
        if (ignorar.contains(k)) return;
        walk(v);
      });
      return;
    }
    if (o is BchImpactoFila) {
      // `marcado` cuenta como dato: confirma que en ese grupo no hubo heridos,
      // que es distinto de no haber preguntado.
      out.addAll([
        o.marcado,
        o.fallecidos,
        o.heridos,
        o.desaparecidos,
        o.observaciones,
      ]);
      return;
    }
    if (o is BchProteccionFila) {
      out.addAll([o.total, o.mujeres, o.hombres, o.observaciones]);
      return;
    }
    if (o is BchNecesidadFila) {
      out.addAll([o.si, o.observaciones]);
      return;
    }
    if (o is BchComunidad) {
      out.add(o.nombre);
      return;
    }
    if (o is BchServicioDetalle) {
      out.addAll([
        o.danoParcial,
        o.danoTotal,
        o.necesidades,
        o.observaciones,
      ]);
      return;
    }
    if (o is BchPrimeraRespuesta) {
      out.addAll([
        o.busqueda,
        o.salvamento,
        o.evacuacion,
        o.observaciones,
      ]);
      return;
    }
    if (o is BchNecesidadSalud) {
      out.addAll([o.incendio, o.inundacion, o.sequia, o.otras, o.observaciones]);
      return;
    }
    if (o is BchDanoVial) {
      out.addAll([
        o.via,
        o.tramo,
        o.danoParcial,
        o.danoTotal,
        o.kmDanio,
        o.necesidades,
        o.observaciones,
      ]);
      return;
    }
    if (o is BchInfraPublica) {
      out.addAll([
        o.comunidad,
        o.tipoEstructura,
        o.danoParcial,
        o.danoTotal,
        o.necesidades,
        o.observaciones,
      ]);
      return;
    }
    if (o is BchInfraProductiva) {
      out.addAll([
        o.tipo,
        o.comunidad,
        o.danoParcial,
        o.danoTotal,
        o.necesidades,
        o.observaciones,
      ]);
      return;
    }
    if (o is BchEstablecimientoSalud) {
      out.addAll([
        o.establecimiento,
        o.comunidad,
        o.nivel,
        o.dano,
        o.observaciones,
      ]);
      return;
    }
    if (o is BchUnidadEducativa) {
      out.addAll([
        o.establecimiento,
        o.comunidad,
        o.danoParcial,
        o.danoTotal,
        o.suspensionClases,
        o.estudiantes,
        o.observaciones,
      ]);
      return;
    }
    if (o is BchDanoVivienda) {
      out.addAll([
        o.comunidad,
        o.danoParcial,
        o.danoTotal,
        o.necesidades,
        o.observaciones,
      ]);
      return;
    }
    if (o is BchAgricultura) {
      out.addAll([
        o.cultivo,
        o.hasAfectadas,
        o.hasPerdidas,
        o.necesidades,
        o.observaciones,
      ]);
      return;
    }
    if (o is BchPecuario) {
      out.addAll([
        o.especie,
        o.animalesAfectados,
        o.animalesMuertos,
        o.necesidades,
        o.observaciones,
      ]);
      return;
    }
    out.add(o);
  }

  walk(obj);
  return out;
}

/// Cuenta de casillas de necesidad humanitaria marcadas o con observación.
extension EdanNecesidadesCount on EdanBorradorIa {
  int necesidadesMarcadasCount() =>
      necesidadesHumanitarias.where((f) => f.tieneDatos).length;
}
