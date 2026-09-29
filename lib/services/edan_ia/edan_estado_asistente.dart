/// El estado real de la ficha, en texto, para que el modelo pueda razonar.
///
/// El prompt por sí solo dice "qué secciones están llenas". Con eso el modelo
/// guía, pero no puede *razonar*: no sabe que hay 350 afectados y que acaba de
/// oír "400", ni que la persona se contradijo. Esta es la parte que convierte
/// una lista de pendientes en una conversación con contexto.
///
/// Es un resumen deliberadamente chato: solo lo que la persona ya dijo, en
/// cifras y nombres. Sin esto el modelo no puede detectar ni señalar un
/// desajuste, y la validación de población de `edan_reglas_poblacion.dart`
/// sería un muro sin explicación.
library;

import '../../models/edan_borrador_ia.dart';
import 'edan_reglas_poblacion.dart';

/// Lo que hay anotado ahora, en líneas cortas.
///
/// Devuelve `''` si no hay nada, para no mandar un bloque vacío en el prompt.
String estadoParaAsistente(EdanBorradorIa b) {
  final l = <String>[];

  void campo(String nombre, Object? valor) {
    if (valor == null) return;
    final s = valor.toString().trim();
    if (s.isEmpty || s == '0' || s == 'false') return;
    l.add('$nombre: $s');
  }

  // --- Cabecera ---
  campo('Departamento', b.departamento);
  campo('Provincia', b.provincia);
  campo('Municipio', b.municipio);
  campo('Alcalde', b.alcalde);
  campo('Fecha del evento', b.fechaEvento);
  campo('Hora del evento', b.horaEvento);
  for (final e in b.tipoEvento.entries.where((e) => e.value)) {
    l.add('Tipo de evento: ${_claveEvento(e.key)}');
  }
  campo('Total de familias afectadas', b.totalFamiliasAfectadas);
  campo('Total de familias damnificadas', b.totalFamiliasDamnificadas);
  campo('Población total afectada', b.totalAfectada);
  campo('Responsable', b.responsableNombre);

  // --- Impacto en la población ---
  for (final g in b.impactoPoblacion) {
    final partes = [
      if ((g.fallecidos ?? 0) > 0) '${g.fallecidos} fallecidos',
      if ((g.heridos ?? 0) > 0) '${g.heridos} heridos',
      if ((g.desaparecidos ?? 0) > 0) '${g.desaparecidos} desaparecidos',
    ];
    if (partes.isEmpty) continue;
    final obs = g.observaciones.trim();
    l.add('${g.grupo}: ${partes.join(', ')}'
        '${obs.isEmpty ? '' : ' ($obs)'}');
  }

  // --- Protección ---
  for (final g in b.proteccion) {
    final t = g.total ?? ((g.mujeres ?? 0) + (g.hombres ?? 0));
    if (t <= 0 && g.observaciones.trim().isEmpty) continue;
    final desglose = (g.mujeres != null || g.hombres != null)
        ? ' (${g.mujeres ?? 0} mujeres, ${g.hombres ?? 0} hombres)'
        : ' (sin desglose por sexo)';
    l.add('${g.grupo}: $t$desglose');
  }

  // --- Primera respuesta y necesidades ---
  final pr = b.primeraRespuesta;
  final equipos = [
    if (pr.busqueda) 'Búsqueda y rescate',
    if (pr.salvamento) 'Salvamento',
    if (pr.evacuacion) 'Evacuación',
  ];
  if (equipos.isNotEmpty) l.add('Primera respuesta: ${equipos.join(', ')}');
  if (pr.observaciones.trim().isNotEmpty) {
    l.add('Primera respuesta, observaciones: ${pr.observaciones.trim()}');
  }
  final necesidades = b.necesidadesHumanitarias
      .where((n) => n.si)
      .map((n) => n.item)
      .toList();
  if (necesidades.isNotEmpty) {
    l.add('Necesidades humanitarias: ${necesidades.join(', ')}');
  }
  for (final n in b.necesidadesHumanitarias) {
    if (n.observaciones.trim().isNotEmpty) {
      l.add('Necesidad "${n.item}": ${n.observaciones.trim()}');
    }
  }
  final salud = [
    if (b.necesidadSalud.incendio.trim().isNotEmpty)
      'incendio: ${b.necesidadSalud.incendio.trim()}',
    if (b.necesidadSalud.inundacion.trim().isNotEmpty)
      'inundación: ${b.necesidadSalud.inundacion.trim()}',
    if (b.necesidadSalud.sequia.trim().isNotEmpty)
      'sequía: ${b.necesidadSalud.sequia.trim()}',
    if (b.necesidadSalud.otras.trim().isNotEmpty)
      'otras: ${b.necesidadSalud.otras.trim()}',
  ];
  if (salud.isNotEmpty) l.add('Necesidad de salud — ${salud.join('; ')}');

  // --- Las listas 1:n ---
  for (final f in b.infraVial) {
    l.add(_linea('Vía', f.via, [
      if (f.tramo.isNotEmpty) f.tramo,
      if (f.danoTotal.isNotEmpty) 'daño total',
      if (f.danoParcial.isNotEmpty) 'daño parcial',
      if (f.kmDanio.isNotEmpty) '${f.kmDanio} km',
    ]));
  }
  for (final f in b.infraPublica) {
    l.add(_linea('Infraestructura', f.tipoEstructura, [
      if (f.comunidad.isNotEmpty) f.comunidad,
      if (f.danoTotal.isNotEmpty) 'daño total',
      if (f.danoParcial.isNotEmpty) 'daño parcial',
    ]));
  }
  for (final f in b.infraProductiva) {
    l.add(_linea('Infraestructura productiva', f.tipo, [
      if (f.danoTotal.isNotEmpty) 'daño total',
      if (f.danoParcial.isNotEmpty) 'daño parcial',
    ]));
  }
  for (final f in b.saludDanios) {
    l.add(_linea('Establecimiento de salud', f.establecimiento, [
      if (f.comunidad.isNotEmpty) f.comunidad,
      if (f.dano.isNotEmpty) f.dano,
    ]));
  }
  for (final f in b.educacion) {
    l.add(_linea('Unidad educativa', f.establecimiento, [
      if (f.comunidad.isNotEmpty) f.comunidad,
      if (f.estudiantes != null) '${f.estudiantes} estudiantes',
      if (f.suspensionClases) 'clases suspendidas',
      if (f.danoTotal.isNotEmpty) 'daño total',
    ]));
  }
  for (final f in b.danosVivienda) {
    l.add(_linea('Viviendas', f.comunidad, [
      if ((f.danoParcial ?? 0) > 0) '${f.danoParcial} parciales',
      if ((f.danoTotal ?? 0) > 0) '${f.danoTotal} totales',
    ]));
  }
  for (final f in b.agricultura) {
    l.add(_linea('Agricultura', f.cultivo, [
      if ((f.hasAfectadas ?? 0) > 0) '${f.hasAfectadas} ha afectadas',
      if ((f.hasPerdidas ?? 0) > 0) '${f.hasPerdidas} ha perdidas',
    ]));
  }
  for (final f in b.pecuario) {
    l.add(_linea('Ganadería', f.especie, [
      if ((f.animalesAfectados ?? 0) > 0) '${f.animalesAfectados} afectados',
      if ((f.animalesMuertos ?? 0) > 0) '${f.animalesMuertos} muertos',
    ]));
  }
  if (b.comunidades.isNotEmpty) {
    l.add('Comunidades: ${b.comunidades.map((c) => c.nombre).join(', ')}');
  }

  if (l.isEmpty) return '';
  return l.join('\n');
}

/// Las líneas de desajuste, para que el modelo pueda mencionarlas.
///
/// Van aparte del estado porque son una instrucción, no un dato: el modelo
/// tiene que *decirlo*, no solo saberlo.
String avisosParaAsistente(EdanBorradorIa b) {
  final avisos = validarPoblacion(b);
  if (avisos.isEmpty) return '';
  return avisos
      .map((a) => '- ${a.mensaje} Preguntale para aclararlo, sin reprochar.')
      .join('\n');
}

String _linea(String tipo, String nombre, List<String> detalles) {
  final n = nombre.trim();
  final d = detalles.where((x) => x.trim().isNotEmpty).join(', ');
  final cabeza = n.isEmpty ? tipo : '$tipo $n';
  return d.isEmpty ? cabeza : '$cabeza: $d';
}

String _claveEvento(String clave) => switch (clave) {
      'inundacion' => 'Inundación',
      'riada' => 'Riada',
      'deslizamiento' => 'Deslizamiento',
      'helada' => 'Helada',
      'granizada' => 'Granizada',
      'sequia' => 'Sequía',
      'incendios' => 'Incendios',
      _ => clave,
    };
