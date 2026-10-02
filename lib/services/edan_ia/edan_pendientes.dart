/// Las variables de la ficha que todavía están vacías, en el orden en que
/// conviene llenarlas.
///
/// # Por qué existe
///
/// El prompt le mandaba al modelo "lo que falta" como una lista de **títulos
/// de sección** ("Salud", "Educación", "Vivienda"). Con eso el modelo tiene que
/// adivinar *qué* preguntar dentro de cada sección, y medido contra el puente
/// real eso es justo lo que no sostiene: respondía con frases afirmativas, se
/// le olvidaba preguntar, y volvía a pedir el número que la persona acababa de
/// dar.
///
/// Con una lista de **variables concretas** el modelo no tiene que adivinar:
/// elige una de una lista cerrada y la convierte en pregunta. El dato sigue
/// siendo el modelo el que lo pregunta y el que lo escucha — acá no hay ni una
/// pregunta escrita a mano — pero se le da sobre qué preguntar.
///
/// # Cómo avanza
///
/// La lista se recalcula en cada turno desde el borrador real, así que se
/// acorta sola a medida que la ficha se llena y desaparece el día que está
/// completa. Dentro de un bloque el avance es progresivo: primero se pregunta
/// si el evento pasó, y recién si la persona dijo que sí se pregunta el
/// detalle. Ejemplo con necesidades humanitarias:
///
///   1. no hay ninguna marcada  -> "¿Qué necesitan?"
///   2. "Alimentos" marcada     -> "¿Qué necesitan específicamente de alimentos?"
///   3. "Alimentos" con nota    -> esa variable ya no aparece
library;

import '../../models/edan_borrador_ia.dart';

/// Una variable vacía de la ficha, con la forma de preguntarla.
class EdanVacio {
  /// Bloque de la ficha, para agrupar en el JSON que va al prompt.
  final String bloque;

  /// Clave canónica (la que va en `parche`).
  final String clave;

  /// Cómo se le pregunta a la persona, en sus palabras.
  final String pregunta;

  /// Menor número = más urgente.
  final int prioridad;

  const EdanVacio(
    this.bloque,
    this.clave,
    this.pregunta, {
    this.prioridad = 50,
  });
}

/// Todas las variables vacías, ordenadas por prioridad.
///
/// [maximo] limita cuántas van al prompt. Es deliberadamente corto: con quince
/// vacías el modelo vuelve a recitar una lista, que es lo que suena a formulario.
List<EdanVacio> variablesVacias(EdanBorradorIa b, {int maximo = 5}) {
  final out = <EdanVacio>[];
  void add(EdanVacio v) => out.add(v);

  // --- 1. Ubicación: lo primero, y lo que el campo necesita sí o sí ---
  if (b.municipio.trim().isEmpty) {
    add(const EdanVacio('cabecera', 'municipio',
        '¿En qué municipio o comunidad estamos?',
        prioridad: 1));
  } else if (b.provincia.trim().isEmpty) {
    add(const EdanVacio('cabecera', 'provincia', '¿Y en qué provincia?',
        prioridad: 2));
  } else if (b.departamento.trim().isEmpty) {
    add(const EdanVacio('cabecera', 'departamento', '¿Y de qué departamento?',
        prioridad: 3));
  }

  // --- 2. Qué pasó y cuándo ---
  if (!b.tipoEvento.values.any((v) => v)) {
    add(const EdanVacio('evento', 'tipoEvento',
        '¿Qué pasó: inundación, incendio, granizada, deslizamiento?',
        prioridad: 4));
  }
  if (b.fechaEvento.trim().isEmpty) {
    add(const EdanVacio('cabecera', 'fechaEvento', '¿Qué día pasó?',
        prioridad: 6));
  }
  if (b.horaEvento.trim().isEmpty) {
    add(const EdanVacio('cabecera', 'horaEvento', '¿A qué hora?', prioridad: 7));
  }

  // --- 3. Cuánta gente ---
  if (b.totalAfectada == null) {
    add(const EdanVacio('conteos', 'totalAfectada',
        '¿Cuántas personas quedaron afectadas en total?',
        prioridad: 8));
  }
  if (b.totalFamiliasAfectadas == null) {
    add(const EdanVacio('conteos', 'totalFamiliasAfectadas',
        '¿Y cuántas familias?', prioridad: 9));
  }

  // --- 4. Daños humanos ---
  if (!b.impactoPoblacion.any((f) => f.marcado)) {
    add(const EdanVacio('impacto-poblacion', 'impactoPoblacion',
        '¿Hubo heridos, fallecidos o desaparecidos?',
        prioridad: 10));
  }

  // --- 5.CONTACT0 ---
  if (b.telefono.trim().isEmpty && b.responsableTelefono.trim().isEmpty) {
    add(const EdanVacio('cabecera', 'telefono',
        '¿A qué teléfono puedo llamar para confirmar?', prioridad: 11));
  }

  // --- 6. Necesidades humanitarias, en dos tiempos ---
  //
  // Primero si hay alguna necesidad; recién después, el detalle de las que la
  // persona marcó. Así no se le pregunta por algo que no ocurrió.
  final marcadas = b.necesidadesHumanitarias.where((f) => f.si).toList();
  if (b.necesidadesHumanitarias.isNotEmpty && marcadas.isEmpty) {
    add(const EdanVacio('necesidad-humanitaria', 'necesidadesHumanitarias',
        '¿Qué necesitan las personas ahora mismo: agua, comida, abrigo?',
        prioridad: 12));
  } else {
    for (final f in marcadas) {
      if (f.observaciones.trim().isEmpty) {
        add(EdanVacio(
            'necesidad-humanitaria',
            'necesidadesHumanitarias.${f.item}',
            '¿Qué necesitan específicamente de ${f.item.toLowerCase()}?',
            prioridad: 13));
      }
    }
  }

  // --- 7. Lo que se rompió ---
  if (b.infraVial.isEmpty) {
    add(const EdanVacio('danos-viales', 'infraVial',
        '¿Se rompió o se cortó alguna ruta o puente?', prioridad: 14));
  }
  if (b.educacion.isEmpty) {
    add(const EdanVacio('unidades-educativas', 'educacion',
        '¿Alguna escuela o centro educativo se vio afectado?',
        prioridad: 15));
  }
  if (!b.tieneVivienda) {
    add(const EdanVacio('danos-vivienda', 'danosVivienda',
        '¿Hubo viviendas dañadas o destruidas?', prioridad: 16));
  }
  if (b.saludDanios.isEmpty && !b.necesidadSalud.tieneDatos) {
    add(const EdanVacio('salud-establecimientos', 'salud',
        '¿Al hospital o al centro de salud le pasó algo?', prioridad: 17));
  }
  if (b.infraPublica.isEmpty) {
    add(const EdanVacio('danos-infra-publica', 'infraPublica',
        '¿Se dañó alguna plaza, edificio o espacio público?',
        prioridad: 18));
  }
  if (b.agricultura.isEmpty) {
    add(const EdanVacio('danos-agricultura', 'agricultura',
        '¿Se perdieron cultivos o sembradíos?', prioridad: 19));
  }
  if (b.pecuario.isEmpty) {
    add(const EdanVacio('danos-pecuarios', 'pecuario',
        '¿Hubo pérdidas de animales?', prioridad: 20));
  }
  if (b.infraProductiva.isEmpty) {
    add(const EdanVacio('infra-productiva', 'infraProductiva',
        '¿Se dañó algún galpón, silo o obra productiva?', prioridad: 21));
  }

  // --- 8. Servicios básicos, uno por uno ---
  for (final clave in kEdanServiciosBasicos.keys) {
    final d = b.serviciosBasicos[clave];
    if (d == null || !d.tieneDatos) {
      add(EdanVacio('servicios-basicos', 'serviciosBasicos.$clave',
          '¿Cómo está el servicio de ${clave}?', prioridad: 22));
    }
  }

  // --- 9. Grupos de protección, igual que necesidades ---
  if (!b.proteccion.any((f) => f.tieneDatos)) {
    add(const EdanVacio('proteccion', 'proteccion',
        '¿Hay niños, embarazadas, personas mayores o con discapacidad entre los '
        'afectados?',
        prioridad: 23));
  }
  if (!b.primeraRespuesta.tieneDatos) {
    add(const EdanVacio('primera-respuesta', 'primeraRespuesta',
        '¿Llegó algún equipo de rescate o ayuda?', prioridad: 24));
  }
  if (b.comunidades.where((c) => c.tieneDatos).isEmpty) {
    add(const EdanVacio('comunidades', 'comunidades',
        '¿Qué comunidades o barrios quedaron afectados?', prioridad: 25));
  }
  if (b.responsableNombre.trim().isEmpty) {
    add(const EdanVacio('cabecera', 'responsableNombre',
        '¿Quién está llenando la ficha?', prioridad: 26));
  }

  out.sort((a, b2) => a.prioridad.compareTo(b2.prioridad));
  return out.take(maximo).toList();
}

/// Las vacías como JSON agrupado por bloque.
///
/// Es la forma que el modelo entiende mejor (es la misma forma del `parche` que
/// tiene que devolver), así que no tiene que traducir de una lista de frases a
/// claves de un objeto.
Map<String, List<String>> variablesVaciasPorBloque(EdanBorradorIa b,
    {int maximo = 5}) {
  final m = <String, List<String>>{};
  for (final v in variablesVacias(b, maximo: maximo)) {
    m.putIfAbsent(v.bloque, () => <String>[]).add(v.clave);
  }
  return m;
}

/// Las vacías como frases, para pegarlas directas al prompt.
List<String> preguntasDeRespaldo(EdanBorradorIa b, {int maximo = 5}) =>
    [for (final v in variablesVacias(b, maximo: maximo)) v.pregunta];
