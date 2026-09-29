/// Fusión de parches sobre el borrador.
///
/// Puerto de `EDAN-Tutor/src/services/merge.js`.
///
/// Reglas:
///  - Escalar: se reemplaza, pero `null` NUNCA pisa un valor existente ("no lo
///    dijo nadie" ≠ "dijo que no").
///  - Bloques 1:1 (impacto, protección, necesidades, primera respuesta): se
///    fusiona por etiqueta, de modo que la posición en la lista es irrelevante.
///  - Listas 1:n: se fusiona por **clave natural** (el cultivo, la especie, el
///    nombre de la vía…), no por índice.
///
/// La última regla es la importante. Fusionar por índice, como hace un deepMerge
/// ingenuo, tiene un fallo grave: si la persona agregó "Trigo" a mano y la IA
/// responde "Maíz" para la primera posición, la fila de Trigo se sobrescribe y se
/// pierde trabajo. Con clave natural la fila de la IA se AÑADE y la de la
/// persona se conserva.
library;

import '../../models/edan_borrador_ia.dart';
import 'edan_extractor.dart' show aInt, sinTilde;
import 'edan_parche.dart';

/// Aplica [parche] sobre [base] y devuelve un borrador nuevo. El original no se
/// toca (equivalente de `aplicarParche` con `structuredClone`).
EdanBorradorIa aplicarParche(EdanBorradorIa base, EdanParche parche) {
  final copia = base.copy();
  fusionar(copia, parche);
  return copia;
}

/// Fusiona [parche] en [destino], que sí se modifica.
void fusionar(EdanBorradorIa destino, EdanParche parche) {
  _fusionarCabecera(destino, parche);
  _fusionarBloquesFijos(destino, parche);
  _fusionarListas(destino, parche);
}

// ---------------------------------------------------------------------------
// Cabecera y conteos
// ---------------------------------------------------------------------------

void _fusionarCabecera(EdanBorradorIa d, EdanParche p) {
  if (p.departamento != null) d.departamento = p.departamento!;
  if (p.provincia != null) d.provincia = p.provincia!;
  if (p.municipio != null) d.municipio = p.municipio!;
  if (p.alcalde != null) d.alcalde = p.alcalde!;
  if (p.telefono != null) d.telefono = p.telefono!;
  if (p.fechaLlenado != null) d.fechaLlenado = p.fechaLlenado!;
  if (p.fechaEvento != null) d.fechaEvento = p.fechaEvento!;
  if (p.horaEvento != null) d.horaEvento = p.horaEvento!;
  if (p.tipoEventoOtro != null) d.tipoEventoOtro = p.tipoEventoOtro!;
  if (p.responsableNombre != null) d.responsableNombre = p.responsableNombre!;
  if (p.responsableCargo != null) d.responsableCargo = p.responsableCargo!;
  if (p.responsableTelefono != null) {
    d.responsableTelefono = p.responsableTelefono!;
  }
  if (p.responsableEmail != null) d.responsableEmail = p.responsableEmail!;

  if (p.totalAfectada != null) d.totalAfectada = p.totalAfectada;
  if (p.totalFamiliasAfectadas != null) {
    d.totalFamiliasAfectadas = p.totalFamiliasAfectadas;
  }
  if (p.totalFamiliasDamnificadas != null) {
    d.totalFamiliasDamnificadas = p.totalFamiliasDamnificadas;
  }
  if (p.viviendasAfectadas != null) d.viviendasAfectadas = p.viviendasAfectadas;
  if (p.viviendasDamnificadas != null) {
    d.viviendasDamnificadas = p.viviendasDamnificadas;
  }

  // Un tipo de evento detectado se activa; nunca se desactiva por sí solo.
  for (final e in p.tipoEvento.entries) {
    if (e.value) d.tipoEvento[e.key] = true;
  }
}

// ---------------------------------------------------------------------------
// Bloques de tamaño fijo
// ---------------------------------------------------------------------------

void _fusionarBloquesFijos(EdanBorradorIa d, EdanParche p) {
  // Impacto en población, por etiqueta de grupo.
  for (final e in p.impactoPoblacion.entries) {
    final fila = d.impactoDe(e.key);
    if (fila == null) continue;
    fila.marcado = true;
    for (final c in e.value.entries) {
      switch (c.key) {
        case 'fallecidos':
          final v = aInt(c.value);
          if (v != null) fila.fallecidos = v;
        case 'heridos':
          final v = aInt(c.value);
          if (v != null) fila.heridos = v;
        case 'desaparecidos':
          final v = aInt(c.value);
          if (v != null) fila.desaparecidos = v;
        case 'observaciones':
          final v = c.value?.toString() ?? '';
          if (v.isNotEmpty) fila.observaciones = v;
      }
    }
  }

  // Protección, por etiqueta de grupo. Cada campo se fusiona por separado: un
  // parche con solo `mujeres` no borra el `total` que ya estaba.
  for (final e in p.proteccion.entries) {
    final fila = d.proteccionDe(e.key);
    if (fila == null) continue;
    if (e.value.total != null) fila.total = e.value.total;
    if (e.value.mujeres != null) fila.mujeres = e.value.mujeres;
    if (e.value.hombres != null) fila.hombres = e.value.hombres;
    final obs = e.value.observaciones;
    if (obs.isNotEmpty) fila.observaciones = obs;
  }

  // Necesidades humanitarias, por ítem.
  for (final e in p.necesidadesHumanitarias.entries) {
    final si = e.value;
    if (si == null) continue;
    d.necesidadDe(e.key)?.si = si;
  }

  // Equipos de primera respuesta.
  for (final e in p.primeraRespuesta.entries) {
    final v = e.value;
    if (v == null) continue;
    switch (e.key) {
      case 'busqueda':
        d.primeraRespuesta.busqueda = v;
      case 'salvamento':
        d.primeraRespuesta.salvamento = v;
      case 'evacuacion':
        d.primeraRespuesta.evacuacion = v;
    }
  }

  // Necesidad de salud.
  for (final e in p.necesidadSalud.entries) {
    final v = e.value;
    if (v == null || v.isEmpty) continue;
    switch (e.key) {
      case 'incendio':
        d.necesidadSalud.incendio = v;
      case 'inundacion':
        d.necesidadSalud.inundacion = v;
      case 'sequia':
        d.necesidadSalud.sequia = v;
      case 'otras':
        d.necesidadSalud.otras = v;
      case 'observaciones':
        d.necesidadSalud.observaciones = v;
    }
  }

  // Servicios básicos.
  for (final e in p.serviciosBasicos.entries) {
    final detalle = d.serviciosBasicos[e.key];
    if (detalle == null) continue;
    for (final c in e.value.entries) {
      final v = c.value;
      if (v == null || v.isEmpty) continue;
      switch (c.key) {
        case 'danoParcial':
          detalle.danoParcial = v;
        case 'danoTotal':
          detalle.danoTotal = v;
        case 'necesidades':
          detalle.necesidades = v;
        case 'observaciones':
          detalle.observaciones = v;
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Listas 1:n, por clave natural
// ---------------------------------------------------------------------------

void _fusionarListas(EdanBorradorIa d, EdanParche p) {
  // Las filas sin identificar se fotografían ANTES de aplicar el parche. La
  // conversación las produce en dos tiempos todo el tiempo ("se cayó un
  // puente" y dos turnos después "se llama San Carlos"), y sin este snapshot
  // la fila sin nombre sería invisible para el nombre que llega después.
  final sVial = _sinNombre(d.infraVial, (x) => x.via);
  for (final f in p.infraVial) {
    final i = _indice(d.infraVial, (x) => x.via, (x, v) => x.via = v, f.via, sVial);
    if (i < 0) {
      d.infraVial.add(f.copy());
    } else {
      _fusionarDanoVial(d.infraVial[i], f);
    }
  }
  final sPublica = _sinNombre(d.infraPublica, (x) => x.tipoEstructura);
  for (final f in p.infraPublica) {
    final i = _indice(d.infraPublica, (x) => x.tipoEstructura,
        (x, v) => x.tipoEstructura = v, f.tipoEstructura, sPublica);
    if (i < 0) {
      d.infraPublica.add(f.copy());
    } else {
      _fusionarInfraPublica(d.infraPublica[i], f);
    }
  }
  final sProductiva = _sinNombre(d.infraProductiva, (x) => x.tipo);
  for (final f in p.infraProductiva) {
    final i = _indice(d.infraProductiva, (x) => x.tipo, (x, v) => x.tipo = v,
        f.tipo, sProductiva);
    if (i < 0) {
      d.infraProductiva.add(f.copy());
    } else {
      _fusionarInfraProductiva(d.infraProductiva[i], f);
    }
  }
  final sSalud = _sinNombre(d.saludDanios, (x) => x.establecimiento);
  for (final f in p.saludDanios) {
    final i = _indice(d.saludDanios, (x) => x.establecimiento,
        (x, v) => x.establecimiento = v, f.establecimiento, sSalud);
    if (i < 0) {
      d.saludDanios.add(f.copy());
    } else {
      _fusionarSalud(d.saludDanios[i], f);
    }
  }
  final sEducacion = _sinNombre(d.educacion, (x) => x.establecimiento);
  for (final f in p.educacion) {
    final i = _indice(d.educacion, (x) => x.establecimiento,
        (x, v) => x.establecimiento = v, f.establecimiento, sEducacion);
    if (i < 0) {
      d.educacion.add(f.copy());
    } else {
      _fusionarEducacion(d.educacion[i], f);
    }
  }
  final sAgricultura = _sinNombre(d.agricultura, (x) => x.cultivo);
  for (final f in p.agricultura) {
    final i = _indice(d.agricultura, (x) => x.cultivo, (x, v) => x.cultivo = v,
        f.cultivo, sAgricultura);
    if (i < 0) {
      d.agricultura.add(f.copy());
    } else {
      _fusionarAgricultura(d.agricultura[i], f);
    }
  }
  final sPecuario = _sinNombre(d.pecuario, (x) => x.especie);
  for (final f in p.pecuario) {
    final i = _indice(d.pecuario, (x) => x.especie, (x, v) => x.especie = v,
        f.especie, sPecuario);
    if (i < 0) {
      d.pecuario.add(f.copy());
    } else {
      _fusionarPecuario(d.pecuario[i], f);
    }
  }
  final sVivienda = _sinNombre(d.danosVivienda, (x) => x.comunidad);
  for (final f in p.danosVivienda) {
    final i = _indice(d.danosVivienda, (x) => x.comunidad,
        (x, v) => x.comunidad = v, f.comunidad, sVivienda);
    if (i < 0) {
      d.danosVivienda.add(f.copy());
    } else {
      _fusionarDanoVivienda(d.danosVivienda[i], f);
    }
  }
  final sComunidades = _sinNombre(d.comunidades, (x) => x.nombre);
  for (final f in p.comunidades) {
    final i = _indice(d.comunidades, (x) => x.nombre, (x, v) => x.nombre = v,
        f.nombre, sComunidades);
    if (i < 0) d.comunidades.add(f.copy());
  }
}

/// Posiciones de las filas que todavía no tienen nombre.
List<int> _sinNombre<T>(List<T> lista, String Function(T) claveDe) => [
      for (var i = 0; i < lista.length; i++)
        if (_norm(claveDe(lista[i])).isEmpty) i,
    ];

/// Índice de la fila con la que fusiona [nuevo], o -1 si es una fila nueva.
///
/// Busca por clave natural (sin tildes, mayúsculas ni espacios). Si no
/// encuentra y hay **exactamente una** fila sin identificar, esa es la fila:
/// en una conversación la gente describe el daño antes de nombrarlo, y
/// duplicarla perdería la mitad de lo dicho. [nombrar] le pone el nombre a esa
/// fila, que es justo lo que faltaba.
///
/// Con dos o más filas sin nombre no se apuesta: ahí no se sabe cuál es cuál,
/// y adivinar sería peor que dejar una fila de más.
int _indice<T>(
  List<T> lista,
  String Function(T) claveDe,
  void Function(T, String) nombrar,
  String nuevo,
  List<int> sinNombre,
) {
  final n = _norm(nuevo);
  if (n.isNotEmpty) {
    for (var i = 0; i < lista.length; i++) {
      if (_norm(claveDe(lista[i])) == n) return i;
    }
  }
  if (sinNombre.length != 1) return -1;
  final fila = lista[sinNombre.first];
  if (n.isNotEmpty) nombrar(fila, nuevo);
  return sinNombre.first;
}

/// Compara claves sin tildes, mayúsculas ni espacios sobrantes, para que
/// "Maíz" y "maiz " sean la misma fila.
String _norm(Object? s) => sinTilde(s).trim().toLowerCase();

/// Resumen legible de una fila de protección: "40 mujeres, 30 hombres" o el
/// total suelto cuando no hay desglose.
String _resumenProteccion(BchProteccionFila? f) {
  if (f == null) return '';
  final partes = <String>[
    if (f.mujeres != null) '${f.mujeres} mujeres',
    if (f.hombres != null) '${f.hombres} hombres',
    if (f.mujeres == null && f.hombres == null && f.total != null)
      '${f.total} personas',
  ];
  return partes.join(', ');
}

// Cada merge es "solo lo detectado": los campos ausentes del parche se respetan.

void _fusionarDanoVial(BchDanoVial a, BchDanoVial p) {
  if (p.tramo.isNotEmpty) a.tramo = p.tramo;
  if (p.danoParcial.isNotEmpty) a.danoParcial = p.danoParcial;
  if (p.danoTotal.isNotEmpty) a.danoTotal = p.danoTotal;
  if (p.kmDanio.isNotEmpty) a.kmDanio = p.kmDanio;
  if (p.necesidades.isNotEmpty) a.necesidades = p.necesidades;
  if (p.observaciones.isNotEmpty) a.observaciones = p.observaciones;
  a.origen ??= p.origen;
}

void _fusionarInfraPublica(BchInfraPublica a, BchInfraPublica p) {
  if (p.comunidad.isNotEmpty) a.comunidad = p.comunidad;
  if (p.danoParcial.isNotEmpty) a.danoParcial = p.danoParcial;
  if (p.danoTotal.isNotEmpty) a.danoTotal = p.danoTotal;
  if (p.necesidades.isNotEmpty) a.necesidades = p.necesidades;
  if (p.observaciones.isNotEmpty) a.observaciones = p.observaciones;
  a.origen ??= p.origen;
}

void _fusionarInfraProductiva(BchInfraProductiva a, BchInfraProductiva p) {
  if (p.comunidad.isNotEmpty) a.comunidad = p.comunidad;
  if (p.danoParcial.isNotEmpty) a.danoParcial = p.danoParcial;
  if (p.danoTotal.isNotEmpty) a.danoTotal = p.danoTotal;
  if (p.necesidades.isNotEmpty) a.necesidades = p.necesidades;
  if (p.observaciones.isNotEmpty) a.observaciones = p.observaciones;
  a.origen ??= p.origen;
}

void _fusionarSalud(BchEstablecimientoSalud a, BchEstablecimientoSalud p) {
  if (p.comunidad.isNotEmpty) a.comunidad = p.comunidad;
  if (p.nivel.isNotEmpty) a.nivel = p.nivel;
  if (p.dano.isNotEmpty) a.dano = p.dano;
  if (p.observaciones.isNotEmpty) a.observaciones = p.observaciones;
  a.origen ??= p.origen;
}

void _fusionarEducacion(BchUnidadEducativa a, BchUnidadEducativa p) {
  if (p.comunidad.isNotEmpty) a.comunidad = p.comunidad;
  if (p.danoParcial.isNotEmpty) a.danoParcial = p.danoParcial;
  if (p.danoTotal.isNotEmpty) a.danoTotal = p.danoTotal;
  if (p.suspensionClases) a.suspensionClases = true;
  if (p.estudiantes != null) a.estudiantes = p.estudiantes;
  if (p.observaciones.isNotEmpty) a.observaciones = p.observaciones;
  a.origen ??= p.origen;
}

void _fusionarAgricultura(BchAgricultura a, BchAgricultura p) {
  if (p.hasAfectadas != null) a.hasAfectadas = p.hasAfectadas;
  if (p.hasPerdidas != null) a.hasPerdidas = p.hasPerdidas;
  if (p.necesidades.isNotEmpty) a.necesidades = p.necesidades;
  if (p.observaciones.isNotEmpty) a.observaciones = p.observaciones;
  a.origen ??= p.origen;
}

void _fusionarPecuario(BchPecuario a, BchPecuario p) {
  if (p.animalesAfectados != null) a.animalesAfectados = p.animalesAfectados;
  if (p.animalesMuertos != null) a.animalesMuertos = p.animalesMuertos;
  if (p.necesidades.isNotEmpty) a.necesidades = p.necesidades;
  if (p.observaciones.isNotEmpty) a.observaciones = p.observaciones;
  a.origen ??= p.origen;
}

void _fusionarDanoVivienda(BchDanoVivienda a, BchDanoVivienda p) {
  if (p.danoParcial != null) a.danoParcial = p.danoParcial;
  if (p.danoTotal != null) a.danoTotal = p.danoTotal;
  if (p.necesidades.isNotEmpty) a.necesidades = p.necesidades;
  if (p.observaciones.isNotEmpty) a.observaciones = p.observaciones;
  a.origen ??= p.origen;
}

// ---------------------------------------------------------------------------
// Edición manual de las listas 1:n
// ---------------------------------------------------------------------------

/// Listas 1:n del borrador. La hoja de revisión permite agregar y quitar filas
/// detectadas, porque la IA se equivoca y la persona tiene que poder corregarla.
enum EdanLista {
  comunidades,
  agricultura,
  pecuario,
  infraVial,
  infraPublica,
  infraProductiva,
  saludDanios,
  educacion,
  danosVivienda,
}

/// Número de filas de [lista].
int largoLista(EdanBorradorIa d, EdanLista lista) {
  switch (lista) {
    case EdanLista.comunidades:
      return d.comunidades.length;
    case EdanLista.agricultura:
      return d.agricultura.length;
    case EdanLista.pecuario:
      return d.pecuario.length;
    case EdanLista.infraVial:
      return d.infraVial.length;
    case EdanLista.infraPublica:
      return d.infraPublica.length;
    case EdanLista.infraProductiva:
      return d.infraProductiva.length;
    case EdanLista.saludDanios:
      return d.saludDanios.length;
    case EdanLista.educacion:
      return d.educacion.length;
    case EdanLista.danosVivienda:
      return d.danosVivienda.length;
  }
}

/// Quita la fila [indice]. Un índice fuera de rango no hace nada ni revienta.
void quitarFila(EdanBorradorIa d, EdanLista lista, int indice) {
  if (indice < 0 || indice >= largoLista(d, lista)) return;
  switch (lista) {
    case EdanLista.comunidades:
      d.comunidades.removeAt(indice);
    case EdanLista.agricultura:
      d.agricultura.removeAt(indice);
    case EdanLista.pecuario:
      d.pecuario.removeAt(indice);
    case EdanLista.infraVial:
      d.infraVial.removeAt(indice);
    case EdanLista.infraPublica:
      d.infraPublica.removeAt(indice);
    case EdanLista.infraProductiva:
      d.infraProductiva.removeAt(indice);
    case EdanLista.saludDanios:
      d.saludDanios.removeAt(indice);
    case EdanLista.educacion:
      d.educacion.removeAt(indice);
    case EdanLista.danosVivienda:
      d.danosVivienda.removeAt(indice);
  }
}

/// Añade una fila vacía al final, para que la persona la complete a mano.
void agregarFila(EdanBorradorIa d, EdanLista lista) {
  switch (lista) {
    case EdanLista.comunidades:
      d.comunidades.add(BchComunidad());
    case EdanLista.agricultura:
      d.agricultura.add(BchAgricultura());
    case EdanLista.pecuario:
      d.pecuario.add(BchPecuario());
    case EdanLista.infraVial:
      d.infraVial.add(BchDanoVial());
    case EdanLista.infraPublica:
      d.infraPublica.add(BchInfraPublica());
    case EdanLista.infraProductiva:
      d.infraProductiva.add(BchInfraProductiva());
    case EdanLista.saludDanios:
      d.saludDanios.add(BchEstablecimientoSalud());
    case EdanLista.educacion:
      d.educacion.add(BchUnidadEducativa());
    case EdanLista.danosVivienda:
      d.danosVivienda.add(BchDanoVivienda());
  }
}

// ---------------------------------------------------------------------------
// Resumen de cambios
// ---------------------------------------------------------------------------

/// Resume qué cambió un parche, para mostrárselo a la persona ("Anoté: 350
/// familias afectadas") y para que la interfaz no toque campos que ya había
/// corregido a mano.
///
/// Equivalente de `rutasCambiadas` de la referencia, pero devuelve etiquetas
/// legibles en vez de rutas, porque en la app lo lee una persona.
List<String> resumenCambios(EdanBorradorIa antes, EdanBorradorIa despues) {
  final out = <String>[];

  void txt(String etiqueta, Object? a, Object? b) {
    if (a != b && (b?.toString().trim().isNotEmpty ?? false)) {
      out.add('$etiqueta: $b');
    }
  }

  void num_(String etiqueta, int? a, int? b) {
    if (a != b && b != null) out.add('$etiqueta: $b');
  }

  txt('Departamento', antes.departamento, despues.departamento);
  txt('Provincia', antes.provincia, despues.provincia);
  txt('Municipio', antes.municipio, despues.municipio);
  txt('Alcalde', antes.alcalde, despues.alcalde);
  txt('Teléfono', antes.telefono, despues.telefono);
  txt('Fecha del evento', antes.fechaEvento, despues.fechaEvento);
  txt('Hora del evento', antes.horaEvento, despues.horaEvento);
  num_('Personas afectadas', antes.totalAfectada, despues.totalAfectada);
  num_('Familias afectadas', antes.totalFamiliasAfectadas,
      despues.totalFamiliasAfectadas);
  num_('Familias damnificadas', antes.totalFamiliasDamnificadas,
      despues.totalFamiliasDamnificadas);
  num_('Viviendas afectadas', antes.viviendasAfectadas,
      despues.viviendasAfectadas);
  num_('Viviendas damnificadas', antes.viviendasDamnificadas,
      despues.viviendasDamnificadas);

  for (final e in despues.tipoEvento.entries) {
    if (e.value == true && antes.tipoEvento[e.key] != true) {
      out.add('Evento: ${kEdanEtiquetasEvento[e.key] ?? e.key}');
    }
  }

  for (final f in despues.impactoPoblacion) {
    final a = antes.impactoDe(f.grupo);
    if (a == null) continue;
    num_('${f.grupo} fallecidos', a.fallecidos, f.fallecidos);
    num_('${f.grupo} heridos', a.heridos, f.heridos);
    num_('${f.grupo} desaparecidos', a.desaparecidos, f.desaparecidos);
  }

  for (final f in despues.proteccion) {
    // El resumen compara la fila completa (total y/o desglose) como texto para
    // que un cambio solo en `mujeres` o solo en `hombres` también se reporte.
    final previo = antes.proteccionDe(f.grupo);
    final antesTxt = _resumenProteccion(previo);
    final despuesTxt = _resumenProteccion(f);
    if (antesTxt != despuesTxt && despuesTxt.isNotEmpty) {
      out.add('${f.grupo} en protección: $despuesTxt');
    }
  }

  for (final f in despues.necesidadesHumanitarias) {
    if (f.si && !(antes.necesidadDe(f.item)?.si ?? false)) {
      out.add('Necesitan: ${f.item}');
    }
  }

  for (final e in despues.serviciosBasicos.entries) {
    final etiqueta = kEdanServiciosBasicos[e.key] ?? e.key;
    if (e.value.danoTotal.isNotEmpty &&
        (antes.serviciosBasicos[e.key]?.danoTotal.isEmpty ?? true)) {
      out.add('$etiqueta: ${e.value.danoTotal}');
    }
  }

  _resumenFilas(antes.agricultura, despues.agricultura, (f) => f.cultivo,
      (f) => '${f.hasAfectadas ?? 0} ha afectadas', out);
  _resumenFilas(antes.pecuario, despues.pecuario, (f) => f.especie,
      (f) => '${f.animalesAfectados ?? 0} afectados', out);
  _resumenFilas(antes.saludDanios, despues.saludDanios,
      (f) => f.establecimiento, (f) => 'con daños', out);
  _resumenFilas(antes.educacion, despues.educacion, (f) => f.establecimiento,
      (f) => 'con daños', out);
  _resumenFilas(antes.infraVial, despues.infraVial, (f) => f.via,
      (f) => f.danoTotal.isEmpty ? 'con daños' : f.danoTotal, out);
  _resumenFilas(antes.comunidades, despues.comunidades, (f) => f.nombre,
      (f) => 'afectada', out);

  return out;
}

/// Añade al resumen las filas de una lista 1:n que no existían antes.
void _resumenFilas<T>(
  List<T> antes,
  List<T> despues,
  String Function(T) clave,
  String Function(T) valor,
  List<String> out,
) {
  final previos = antes.map((f) => _norm(clave(f))).toSet();
  for (final f in despues) {
    if (previos.contains(_norm(clave(f)))) continue;
    final etiqueta = clave(f).trim();
    if (etiqueta.isEmpty) continue;
    out.add('$etiqueta: ${valor(f)}');
  }
}
