/// Traduce el borrador conversacional ([EdanBorradorIa]) a los modelos que
/// espera SQLite ([EdanLocalidad] y sus secciones).
///
/// Es una función **pura**: no toca la base de datos. Recibe el borrador ya
/// fusionado y devuelve la localidad lista para que la capa de persistencia la
/// guarde (`insertLocalidad`/`updateLocalidad` + `guardarSecciones` +
/// `activarSecciones`). Así se puede probar sin base de datos y la misma lógica
/// sirve para una localidad nueva o para editar una existente.
///
/// Decisiones que no son obvias y por eso están aquí:
///
/// * Los grupos de edad y de protección del tutor NO se llaman igual que los
///   catálogos de SQLite. Se traducen por equivalencia explícita, nunca por
///   posición, y lo que no se puede resolver sin ambigüedad se devuelve como
///   aviso para que lo pregunte la interfaz en vez de inventarlo.
/// * SQLite separa `mujeres`/`hombres` en protección y en salud. Si la persona
///   solo dio un total sin desglose, la traducción **no lo reparte**: lo deja en
///   observaciones y avisa.
/// * Los `imp_*` no se los pone la persona a mano: se derivan de las secciones
///   que quedaron con datos usando `EdanSeccionesRegistry`.
library;

import 'package:rea/models/edan.dart';
import 'package:rea/models/edan_borrador_ia.dart';
import 'package:rea/services/edan_ia/edan_extractor.dart' show sinTilde;
import 'package:rea/services/edan_secciones_registry.dart';

/// Datos que la traducción NO puede deducir y que resuelve quien la llama
/// (catálogos, locality del usuario, tipo de locality).
class EdanTraduccionOpciones {
  final int? idUsuario;
  final int? idDepartamento;
  final int? idProvincia;
  final int? idMunicipio;
  final int? idTipoEvento;
  final int? idTipoLocalidad;

  /// Nombre del tipo de evento ya resuelto desde el catálogo. Si es null se
  /// arma con las etiquetas del borrador.
  final String? tipoEventoNombre;

  /// `tipo_localidad` de la fila (por ejemplo "Localidad Affected"). Si es null
  /// se copia el nombre del municipio.
  final String? tipoLocalidad;

  /// Filas de `catalogo_grupo_vulnerable`. Si va vacío se usan los 8 grupos por
  /// defecto de `EdanLocalidad`.
  final List<dynamic> catalogoGrupoVulnerable;

  const EdanTraduccionOpciones({
    this.idUsuario,
    this.idDepartamento,
    this.idProvincia,
    this.idMunicipio,
    this.idTipoEvento,
    this.idTipoLocalidad,
    this.tipoEventoNombre,
    this.tipoLocalidad,
    this.catalogoGrupoVulnerable = const [],
  });
}

/// Algo que la traducción no puede decidir sola y que la interfaz debe
/// preguntar antes de dar por buena la ficha.
class EdanAvisoTraduccion {
  /// Clave estable para el código de la vista (p.ej. `proteccion.grupo`).
  final String clave;

  /// Texto para mostrar.
  final String mensaje;

  const EdanAvisoTraduccion(this.clave, this.mensaje);

  @override
  String toString() => '$clave: $mensaje';
}

class EdanTraduccionResultado {
  final EdanLocalidad localidad;

  /// Rutas v2 (`EdanSeccionesRegistry`) con datos, para `activarSecciones`.
  final List<String> seccionesActivas;

  final List<EdanAvisoTraduccion> avisos;

  const EdanTraduccionResultado({
    required this.localidad,
    required this.seccionesActivas,
    required this.avisos,
  });
}

// ---------------------------------------------------------------------------
// Equivalencias de catálogo
// ---------------------------------------------------------------------------

/// Etiqueta del borrador -> `rango` canónico de `seccion_impacto_poblacion`.
/// El texto se canonicaliza para que el texto guardado sea siempre uno del
/// formulario y no una variante escrita al vuelo.
const Map<String, String> kEquivalenciaGruposEtarios = {
  'Niño(a) 0-5 años': 'Niño (a) 0-5 años',
  'Escolar 6-18 años': 'Escolar de 6-18 años',
  'Adulto 19-60 años': 'Adulto de 19-60 años',
  'Adulto mayor 60+': 'Adulto mayor de 60 años adelante',
};

/// Etiqueta del borrador -> nombre del catálogo `catalogo_grupo_vulnerable`.
///
/// `'Niñas y Niños'` NO está a propósito: el catálogo lo parte en dos grupos
/// (0-5 y 6-12) y un total sin edad no se puede repartir sin inventar. Se
/// devuelve como aviso para que la interfaz lo pregunte.
const Map<String, String> kEquivalenciaGruposProteccion = {
  'Adolescentes': 'Adolescentes',
  'Mujeres Lactantes': 'Mujeres lactantes',
  'Mujeres Embarazadas': 'Mujeres embarazadas',
  'Adultos Mayores': 'Adultos mayores',
  'Personas con Discapacidad': 'Personas con discapacidad',
  'Enfermedad Inhabilitante': 'Personas con enfermedad crónica',
};

/// Grupos cuyo nombre ya dice el sexo: un total ahí sí se puede ubicar sin
/// preguntar.
const Set<String> kGruposCodificadosPorSexo = {
  'Mujeres lactantes',
  'Mujeres embarazadas',
  'Niñas y niños 0-5 años',
  'Niñas y niños 6-12 años',
};

/// Ítem del borrador -> columna booleana de `seccion_necesidad_humanitaria`.
///
/// El tutor maneja 10 casillas y SQLite tiene 9: tanques, pastillas, filtros y
/// carro cisterna son cuatro formas de almacenar agua, y politubos es
/// herramienta. Varias de entrada pueden caer en la misma salida.
const Map<String, List<String>> kEquivalenciaNecesidades = {
  'Alimentos': ['alimentos'],
  'Refugio y Vivienda': ['refugioVivienda'],
  'Ropa de Cama': ['ropaCama'],
  'Artículos de Higiene': ['articulosHigiene'],
  'Artículos de Cocina': ['articulosCocina'],
  'Tanques de Agua': ['almacenamientoAgua'],
  'Pastillas Potabilizadoras': ['almacenamientoAgua'],
  'Filtros Vela': ['almacenamientoAgua'],
  'Carro Cisterna': ['almacenamientoAgua'],
  'Politubos': ['herramientas'],
};

// ---------------------------------------------------------------------------
// Traducción
// ---------------------------------------------------------------------------

/// Traduce [b] a una [EdanLocalidad] con sus secciones.
EdanTraduccionResultado traducirBorrador(
  EdanBorradorIa b, {
  EdanTraduccionOpciones opciones = const EdanTraduccionOpciones(),
}) {
  final avisos = <EdanAvisoTraduccion>[];

  final impacto = _traducirImpacto(b);
  final primeraRespuesta = _traducirPrimeraRespuesta(b);
  final salud = _traducirSalud(b);
  final necesidadSalud = _traducirNecesidadSalud(b);
  final viales = _traducirViales(b);
  final infraPublica = _traducirInfraPublica(b);
  final servicios = _traducirServicios(b);
  final educacion = _traducirEducacion(b);
  final vivienda = _traducirVivienda(b);
  final agricultura = _traducirAgricultura(b);
  final pecuario = _traducirPecuario(b);
  final infraProductiva = _traducirInfraProductiva(b);
  final proteccion = _traducirProteccion(b, opciones, avisos);
  final humanitarian = _traducirNecesidadHumanitaria(b);

  final seccionesActivas = <String>[
    if (impacto.isNotEmpty) 'impacto-poblacion',
    if (primeraRespuesta.tieneDatos) 'primera-respuesta',
    if (salud.isNotEmpty) 'salud-establecimientos',
    if (necesidadSalud.tieneDatos) 'necesidad-salud',
    if (viales.isNotEmpty) 'danos-viales',
    if (infraPublica.isNotEmpty) 'danos-infra-publica',
    if (servicios.isNotEmpty) 'servicios-basicos',
    if (educacion.isNotEmpty) 'unidades-educativas',
    if (vivienda.isNotEmpty) 'danos-vivienda',
    if (agricultura.isNotEmpty) 'danos-agricultura',
    if (pecuario.isNotEmpty) 'danos-pecuarios',
    if (infraProductiva.isNotEmpty) 'infra-productiva',
    if (proteccion.isNotEmpty) 'proteccion',
    if (humanitarian.tieneDatos) 'necesidad-humanitaria',
  ];

  final l = EdanLocalidad(
    idUsuario: opciones.idUsuario,
    idDepartamento: opciones.idDepartamento,
    idProvincia: opciones.idProvincia,
    idMunicipio: opciones.idMunicipio,
    idTipoEvento: opciones.idTipoEvento,
    idTipoLocalidad: opciones.idTipoLocalidad,
    departamentoNombre: _vacioANull(b.departamento),
    provinciaNombre: _vacioANull(b.provincia),
    municipioNombre: _vacioANull(b.municipio),
    tipoEventoNombre: opciones.tipoEventoNombre ?? _nombreEvento(b),
    tipoLocalidad: opciones.tipoLocalidad ?? b.municipio,
    nombre: b.municipio,
    fechaLlenado: b.fechaLlenado,
    fechaEvento: _vacioANull(b.fechaEvento),
    horaEvento: _vacioANull(b.horaEvento),
    totalPoblacionAfectada: b.totalAfectada ?? 0,
    totalFamiliasAfectadas: b.totalFamiliasAfectadas ?? 0,
    totalFamiliasDamnificadas: b.totalFamiliasDamnificadas ?? 0,
    nombreAlcalde: b.alcalde,
    fonoAlcalde: b.telefono,
    responsable: _traducirResponsable(b),
    impactoPoblacion: impacto,
    necesidadPrimeraRespuesta: primeraRespuesta,
    establecimientosSalud: salud,
    necesidadSalud: necesidadSalud,
    danosViales: viales,
    danosInfraPublica: infraPublica,
    serviciosBasicos: servicios,
    unidadesEducativas: educacion,
    danosVivienda: vivienda,
    danosAgricultura: agricultura,
    danosPecuarios: pecuario,
    infraProductiva: infraProductiva,
    proteccion: proteccion,
    necesidadHumanitaria: humanitarian,
    // La ficha la escribió una persona (a mano o hablando con la IA), así que
    // se marca como editada para que la sincronización la empuje al servidor.
    editado: true,
  );

  _aplicarFlags(l, seccionesActivas);

  return EdanTraduccionResultado(
    localidad: l,
    seccionesActivas: seccionesActivas,
    avisos: avisos,
  );
}

// --- Cabecera ---------------------------------------------------------------

String? _vacioANull(String s) => s.trim().isEmpty ? null : s.trim();

EdanResponsable? _traducirResponsable(EdanBorradorIa b) {
  if (b.responsableNombre.trim().isEmpty &&
      b.responsableCargo.trim().isEmpty &&
      b.responsableTelefono.trim().isEmpty &&
      b.responsableEmail.trim().isEmpty) {
    return null;
  }
  return EdanResponsable(
    nombre: b.responsableNombre,
    cargo: b.responsableCargo,
    fono: b.responsableTelefono,
    correo: b.responsableEmail,
  );
}

String? _nombreEvento(EdanBorradorIa b) {
  final etiquetas = b.etiquetasEvento;
  if (etiquetas.isEmpty) return null;
  return etiquetas.join(', ');
}

// --- Bloques 1:1 -----------------------------------------------------------

List<EdanImpactoPoblacion> _traducirImpacto(EdanBorradorIa b) => [
      for (final f in b.impactoPoblacion)
        if (f.tieneDatos)
          EdanImpactoPoblacion(
            grupoEtario: kEquivalenciaGruposEtarios[f.grupo] ?? f.grupo,
            fallecidos: f.fallecidos ?? 0,
            heridos: f.heridos ?? 0,
            desaparecidos: f.desaparecidos ?? 0,
            observaciones: f.observaciones,
            gruposEtarios: [
              EdanGrupoEtario(
                rango: kEquivalenciaGruposEtarios[f.grupo] ?? f.grupo,
                fallecidos: f.fallecidos ?? 0,
                heridos: f.heridos ?? 0,
                desaparecidos: f.desaparecidos ?? 0,
                observaciones: f.observaciones,
                marcado: f.marcado,
              ),
            ],
          ),
    ];

EdanNecesidadPrimeraRespuesta _traducirPrimeraRespuesta(EdanBorradorIa b) =>
    EdanNecesidadPrimeraRespuesta(
      busqueda: b.primeraRespuesta.busqueda,
      salvamento: b.primeraRespuesta.salvamento,
      evacuacion: b.primeraRespuesta.evacuacion,
      observaciones: b.primeraRespuesta.observaciones,
    );

/// El extractor determinista no tiene reglas para esta sección (tampoco las
/// tiene `extractor.js`): la llena la IA o la persona en la vista. Aquí solo se
/// traduce lo que haya.
EdanNecesidadSalud _traducirNecesidadSalud(EdanBorradorIa b) {
  final condiciones = <String>[
    if (b.necesidadSalud.incendio.trim().isNotEmpty)
      'Incendio: ${b.necesidadSalud.incendio}',
    if (b.necesidadSalud.inundacion.trim().isNotEmpty)
      'Inundación: ${b.necesidadSalud.inundacion}',
    if (b.necesidadSalud.sequia.trim().isNotEmpty)
      'Sequía: ${b.necesidadSalud.sequia}',
    if (b.necesidadSalud.otras.trim().isNotEmpty)
      b.necesidadSalud.otras,
  ];
  // "botiquines" llega como texto libre: solo se marca si hay un número o un sí.
  final botiquines = _esSi(b.necesidadSalud.incendio) ? true : false;
  return EdanNecesidadSalud(
    botiquines: botiquines,
    numeroPersonas: _aInt(b.necesidadSalud.observaciones) ?? 0,
    otrasNecesidades: condiciones.join('; '),
    observaciones: b.necesidadSalud.observaciones,
  );
}

List<EdanEstablecimientoSalud> _traducirSalud(EdanBorradorIa b) => [
      for (final f in b.saludDanios)
        if (f.tieneDatos)
          EdanEstablecimientoSalud(
            nombreEstablecimiento: f.establecimiento,
            comunidad: f.comunidad,
            nivelAtencion: f.nivel,
            danoParcial: _esDanoParcial(f.dano),
            danoTotal: _esDanoTotal(f.dano),
            otrosAfectados: _aInt(f.dano) ?? 0,
          ),
    ];

/// Daño vial. El borrador guarda el tipo de daño como texto ("Total",
/// "Parcial") y, a veces, solo los kilómetros ("2"). SQLite tiene dos booleanos
/// y un número, así que una cifra es extensión y también daño total.
({bool parcial, bool total, double km}) _traducirDanioVial(
    BchDanoVial f) {
  final km = _kmDe(f.kmDanio) ?? _kmDe(f.danoTotal);
  return (
    parcial: _esDanoParcial(f.danoParcial),
    total: _esDanoTotal(
          f.danoTotal.isNotEmpty ? f.danoTotal : f.danoParcial,
        ) ||
        (km ?? 0) > 0,
    km: km ?? 0,
  );
}

List<EdanDanoVial> _traducirViales(EdanBorradorIa b) => [
      for (final f in b.infraVial)
        if (f.tieneDatos)
          () {
            final d = _traducirDanioVial(f);
            return EdanDanoVial(
              viaPuente: f.via,
              tramo: f.tramo,
              danoParcial: d.parcial,
              danoTotal: d.total,
              kmDanio: d.km,
              necesidadesInmediatas: f.necesidades,
              observaciones: f.observaciones,
            );
          }(),
    ];

List<EdanDanoInfraPublica> _traducirInfraPublica(EdanBorradorIa b) => [
      for (final f in b.infraPublica)
        if (f.tieneDatos)
          EdanDanoInfraPublica(
            comunidad: f.comunidad,
            tipoEstructura: f.tipoEstructura,
            danoParcial: _esDanoParcial(f.danoParcial),
            danoTotal: _esDanoTotal(f.danoTotal),
            observaciones: f.observaciones,
          ),
    ];

List<EdanServicioBasicoDetalle> _traducirServicios(EdanBorradorIa b) => [
      for (final e in b.serviciosBasicos.entries)
        if (e.value.tieneDatos)
          EdanServicioBasicoDetalle(
            tipo: kEdanServiciosBasicos[e.key] ?? e.key,
            afectado: true,
            danoParcial: _esDanoParcial(e.value.danoParcial),
            danoTotal: _esDanoTotal(e.value.danoTotal),
            necesidadesInmediatas: e.value.necesidades,
            observaciones: e.value.observaciones,
          ),
    ];

List<EdanDanoUnidadEducativa> _traducirEducacion(EdanBorradorIa b) => [
      for (final f in b.educacion)
        if (f.tieneDatos)
          EdanDanoUnidadEducativa(
            nombreEstablecimiento: f.establecimiento,
            comunidad: f.comunidad,
            danoParcial: _esDanoParcial(f.danoParcial),
            danoTotal: _esDanoTotal(f.danoTotal),
            // false en el borrador significa "no lo dijo", no "dijo que no".
            suspensionClases: f.suspensionClases ? true : null,
            estudiantes: f.estudiantes ?? 0,
            observaciones: f.observaciones,
          ),
    ];

List<EdanDanoVivienda> _traducirVivienda(EdanBorradorIa b) {
  // Los totales de vivienda no tienen columna: se materializan como una fila,
  // igual que hace el formulario.
  final filas = <EdanDanoVivienda>[
    for (final f in b.danosVivienda)
      if (f.tieneDatos)
        EdanDanoVivienda(
          comunidad: f.comunidad,
          danoParcial: f.danoParcial ?? 0,
          danoTotal: f.danoTotal ?? 0,
          necesidadesInmediatas: f.necesidades,
          observaciones: f.observaciones,
        ),
  ];
  if (b.viviendasAfectadas != null || b.viviendasDamnificadas != null) {
    filas.add(EdanDanoVivienda(
      comunidad: '',
      danoParcial: b.viviendasAfectadas ?? 0,
      danoTotal: b.viviendasDamnificadas ?? 0,
      observaciones: b.viviendaObservaciones,
    ));
  }
  return filas;
}

List<EdanDanoAgricultura> _traducirAgricultura(EdanBorradorIa b) => [
      for (final f in b.agricultura)
        if (f.tieneDatos)
          EdanDanoAgricultura(
            tipoCultivo: f.cultivo,
            hectareasAfectadas: f.hasAfectadas ?? 0,
            hectareasPerdidas: f.hasPerdidas ?? 0,
            necesidadesInmediatas: f.necesidades,
            observaciones: f.observaciones,
          ),
    ];

List<EdanDanoPecuario> _traducirPecuario(EdanBorradorIa b) => [
      for (final f in b.pecuario)
        if (f.tieneDatos)
          EdanDanoPecuario(
            especie: f.especie,
            animalesAfectados: f.animalesAfectados ?? 0,
            animalesMuertos: f.animalesMuertos ?? 0,
            necesidadesInmediatas: f.necesidades,
            observaciones: f.observaciones,
          ),
    ];

List<EdanInfraProductiva> _traducirInfraProductiva(EdanBorradorIa b) => [
      for (final f in b.infraProductiva)
        if (f.tieneDatos)
          EdanInfraProductiva(
            tipo: f.tipo,
            danoParcial: _aInt(f.danoParcial) ?? 0,
            danoTotal: _aInt(f.danoTotal) ?? 0,
          ),
    ];

/// El tutor maneja 10 casillas y SQLite tiene 9. Varias de entrada pueden caer
/// en la misma salida, por eso la columna se queda en `true` si alguna lo pidió.
///
/// Una observación implica marcar la casilla: el formulario borra la observación
/// al desmarcar (invariante `obs => true`) y `toJson` solo serializa la obs de
/// una casilla marcada, así que una obs suelta se perdería al guardar.
EdanNecesidadHumanitaria _traducirNecesidadHumanitaria(EdanBorradorIa b) {
  final l = EdanNecesidadHumanitaria();
  for (final f in b.necesidadesHumanitarias) {
    if (!f.tieneDatos) continue;
    final destinos = kEquivalenciaNecesidades[f.item];
    if (destinos == null) continue;
    final obs = f.observaciones.trim();
    final marcada = f.si || obs.isNotEmpty;
    for (final d in destinos) {
      switch (d) {
        case 'alimentos':
          l.alimentos = l.alimentos || marcada;
          if (obs.isNotEmpty) l.obsAlimentos = obs;
        case 'refugioVivienda':
          l.refugioVivienda = l.refugioVivienda || marcada;
          if (obs.isNotEmpty) l.obsRefugioVivienda = obs;
        case 'ropaCama':
          l.ropaCama = l.ropaCama || marcada;
          if (obs.isNotEmpty) l.obsRopaCama = obs;
        case 'articulosHigiene':
          l.articulosHigiene = l.articulosHigiene || marcada;
          if (obs.isNotEmpty) l.obsArticulosHigiene = obs;
        case 'articulosCocina':
          l.articulosCocina = l.articulosCocina || marcada;
          if (obs.isNotEmpty) l.obsArticulosCocina = obs;
        case 'herramientas':
          l.herramientas = l.herramientas || marcada;
          if (obs.isNotEmpty) l.obsHerramientas = obs;
        case 'almacenamientoAgua':
          l.almacenamientoAgua = l.almacenamientoAgua || marcada;
          if (obs.isNotEmpty) l.obsAlmacenamientoAgua = obs;
      }
    }
  }
  return l;
}

// --- Protección -------------------------------------------------------------

List<EdanGrupoVulnerable> _traducirProteccion(
  EdanBorradorIa b,
  EdanTraduccionOpciones opciones,
  List<EdanAvisoTraduccion> avisos,
) {
  final base = EdanLocalidad.proteccionDesdeCatalogo(
    opciones.catalogoGrupoVulnerable,
  );

  for (final f in b.proteccion) {
    if (!f.tieneDatos) continue;
    final destino = _resolverGrupoProteccion(f.grupo, base);
    if (destino == null) {
      avisos.add(EdanAvisoTraduccion(
        'proteccion.grupo',
        'No sé a qué grupo de protección pertenece "${f.grupo}" '
            '(si son niñas y niños, falta el rango de edad).',
      ));
      continue;
    }

    final total = f.total;
    if (f.tieneDesglose) {
      destino.mujeres = f.mujeres ?? 0;
      destino.hombres = f.hombres ?? 0;
    } else if (total != null) {
      final nombre = _norm(destino.nombreGrupo);
      if (nombre.contains('mujer') || nombre.contains('nina')) {
        destino.mujeres = total;
      } else if (nombre.contains('nino') || nombre.contains('hombre')) {
        destino.hombres = total;
      } else {
        // Adolescentes, adultos mayores, discapacidad: el total no dice el
        // sexo. Se conserva el número y se pregunta, no se reparte al azar.
        destino.observaciones = _une(
          destino.observaciones,
          'Total reportado: $total (sin desglose por sexo)',
        );
        avisos.add(EdanAvisoTraduccion(
          'proteccion.sexo',
          'De "${f.grupo}" dijo $total personas, pero no cuántos mujeres '
              'ni cuántos hombres.',
        ));
      }
    }

    final obs = f.observaciones.trim();
    if (obs.isNotEmpty) destino.observaciones = _une(destino.observaciones, obs);
  }

  return base.where((g) => g.tieneDatos).toList();
}

/// Busca la fila del catálogo que corresponde a la etiqueta del borrador.
/// Primero por equivalencia explícita y después por parecido de palabras; si
/// hay empate devuelve null en vez de elegir una al azar.
EdanGrupoVulnerable? _resolverGrupoProteccion(
  String etiqueta,
  List<EdanGrupoVulnerable> base,
) {
  final objetivo = kEquivalenciaGruposProteccion[etiqueta] ?? etiqueta;
  final n = _norm(objetivo);

  for (final g in base) {
    if (_norm(g.nombreGrupo) == n) return g;
  }
  for (final g in base) {
    if (kEquivalenciaGruposProteccion[etiqueta] == g.nombreGrupo) return g;
  }

  final mejor = _masParecido(n, base.map((g) => _norm(g.nombreGrupo)).toList());
  if (mejor == null) return null;
  return base[mejor.indice];
}

// --- Utilidades de conversión ----------------------------------------------

/// Compara sin tildes, mayúsculas ni espacios sobrantes.
String _norm(Object? s) => sinTilde(s).trim().toLowerCase();

/// Une observaciones sin duplicar ni perder lo anterior.
String _une(String actual, String nuevo) {
  if (nuevo.trim().isEmpty) return actual;
  if (actual.trim().isEmpty) return nuevo.trim();
  if (actual.contains(nuevo.trim())) return actual;
  return '$actual; ${nuevo.trim()}';
}

/// ¿El texto dice que sí? Acepta las formas que puede decir una persona o el
/// modelo: "sí", "total", "dañado", "1", "true".
bool _esSi(Object? v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final t = _norm(v);
  if (t.isEmpty) return false;
  if (const [
    'no',
    'ninguno',
    'ninguna',
    'nada',
    'false',
    '0',
    'falso',
  ].contains(t)) {
    return false;
  }
  return true;
}

int? _aInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.round();
  final m = RegExp(r'\d{1,3}(?:[.,]\d{3})+|\d+')
      .firstMatch(sinTilde(v.toString()));
  if (m == null) return null;
  return int.tryParse(m.group(0)!.replaceAll('.', '').replaceAll(',', ''));
}

/// Kilómetros cuando el texto de daño es una cifra ("2 km" -> 2).
double? _kmDe(String s) {
  final n = _aInt(s);
  if (n == null) return null;
  return n.toDouble();
}

/// `danoParcial` del borrador: "Parcial" o cualquier texto no vacío.
bool _esDanoParcial(String s) {
  final t = _norm(s);
  if (t.isEmpty) return false;
  if (t.contains('total') || t.contains('destruc') || t.contains('inutil')) {
    return false;
  }
  return true;
}

/// `danoTotal` del borrador: "Total" o "destruido".
bool _esDanoTotal(String s) {
  final t = _norm(s);
  if (t.isEmpty) return false;
  return t.contains('total') ||
      t.contains('destruc') ||
      t.contains('inutil') ||
      t == 'todo';
}

/// Jaccard por palabras: qué tan parecidas son dos etiquetas.
double _similitud(String a, String b) {
  final pa = a.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
  final pb = b.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
  if (pa.isEmpty || pb.isEmpty) return 0;
  final inter = pa.intersection(pb).length;
  if (inter == 0) return 0;
  return inter / pa.union(pb).length;
}

class _Mejor {
  final int indice;
  final double valor;
  const _Mejor(this.indice, this.valor);
}

/// Índice del candidato más parecido, o null si nada se parece lo suficiente o
/// hay empate (elegir al azar en un empate sería inventar).
_Mejor? _masParecido(String objetivo, List<String> candidatos) {
  _Mejor? mejor;
  int empates = 0;
  for (var i = 0; i < candidatos.length; i++) {
    final s = _similitud(objetivo, candidatos[i]);
    if (s <= 0) continue;
    if (s >= 0.6) {
      if (mejor == null || s > mejor.valor) {
        mejor = _Mejor(i, s);
        empates = 1;
      } else if (s == mejor.valor) {
        empates++;
      }
    }
  }
  if (mejor == null || empates > 1) return null;
  return mejor;
}

// --- Flags imp_* ------------------------------------------------------------

/// Pone los 23 flags (9 `grup_*` + 14 `imp_*`) según las secciones con datos. La tabla de flags la
/// tiene el registry (es la misma que usa el wizard), no este archivo.
void _aplicarFlags(EdanLocalidad l, List<String> activas) {
  final f = EdanSeccionesRegistry.construirFlagsDesdeActivas(activas);
  bool g(String flag) => f[flag] ?? false;

  l.grupPoblacion = g('grup_poblacion');
  l.grupSalud = g('grup_salud');
  l.grupInfraestructura = g('grup_infraestructura');
  l.grupServicios = g('grup_servicios');
  l.grupEducacion = g('grup_educacion');
  l.grupVivienda = g('grup_vivienda');
  l.grupAgropecuario = g('grup_agropecuario');
  l.impProteccion = g('imp_proteccion');
  l.grupProteccion = g('grup_proteccion');
  l.grupNecesidades = g('grup_necesidades');

  l.impImpactoPoblacion = g('imp_impacto_poblacion');
  l.impSaludEstablecimientos = g('imp_salud_establecimientos');
  l.impDanosViales = g('imp_danos_viales');
  l.impDanosInfraPublica = g('imp_danos_infra_publica');
  l.impServiciosBasicos = g('imp_servicios_basicos');
  l.impUnidadesEducativas = g('imp_unidades_educativas');
  l.impDanosVivienda = g('imp_danos_vivienda');
  l.impDanosAgricultura = g('imp_danos_agricultura');
  l.impDanosPecuarios = g('imp_danos_pecuarios');
  l.impInfraProductiva = g('imp_infra_productiva');
  l.impPrimeraRespuesta = g('imp_primera_respuesta');
  l.impNecesidadSalud = g('imp_necesidad_salud');
  l.impNecesidadHumanitaria = g('imp_necesidad_humanitaria');
}
