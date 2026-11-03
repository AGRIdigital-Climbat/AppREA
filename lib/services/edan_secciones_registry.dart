import 'database_helper.dart';

import '../models/edan.dart';

/// Tipo de serialización de una sección en la API v2.
enum EdanSeccionTipo { unoAUno, unoAN }

/// Describe una sección de la EDAN para el sync v2 por secciones
/// (`/api/v2/edan/localidades/{id}/...`).
class EdanSeccionDescriptor {
  final String rutaV2;
  final String llaveJson;
  final EdanSeccionTipo tipo;
  final bool usaFoto;
  final String tabla;

  const EdanSeccionDescriptor({
    required this.rutaV2,
    required this.llaveJson,
    required this.tipo,
    required this.tabla,
    this.usaFoto = false,
  });

  /// Nombre de la tabla SQLite por seccion (Modelo A v20).
  String get tablaSqlite => 'seccion_$tabla';
}

/// Registro único y declarativo de las secciones v2 de una localidad EDAN.
///
/// Centraliza el conocimiento de qué secciones existen, su ruta v2, su clave
/// JSON y su tipo (1:N o 1:1), de modo que el sync incremental, el tracking
/// por sección y el marcado al guardar apunten a las mismas secciones.
class EdanSeccionesRegistry {
  const EdanSeccionesRegistry._();

  /// Ruta v2 de la cabecera (UPSERT por `id_local`). No es una sección real.
  static const String cabecera = 'cabecera';

  static const List<EdanSeccionDescriptor> secciones = [
    EdanSeccionDescriptor(
      rutaV2: 'impacto-poblacion',
      llaveJson: 'impacto_poblacion',
      tipo: EdanSeccionTipo.unoAN,
      tabla: 'impacto_poblacion',
    ),
    EdanSeccionDescriptor(
      rutaV2: 'salud-establecimientos',
      llaveJson: 'establecimientos_salud',
      tipo: EdanSeccionTipo.unoAN,
      tabla: 'salud_establecimientos',
      usaFoto: true,
    ),
    EdanSeccionDescriptor(
      rutaV2: 'danos-viales',
      llaveJson: 'danos_viales',
      tipo: EdanSeccionTipo.unoAN,
      tabla: 'danos_viales',
      usaFoto: true,
    ),
    EdanSeccionDescriptor(
      rutaV2: 'danos-infra-publica',
      llaveJson: 'danos_infra_publica',
      tipo: EdanSeccionTipo.unoAN,
      tabla: 'danos_infra_publica',
      usaFoto: true,
    ),
    EdanSeccionDescriptor(
      rutaV2: 'servicios-basicos',
      llaveJson: 'servicios_basicos',
      tipo: EdanSeccionTipo.unoAN,
      tabla: 'servicios_basicos',
      usaFoto: true,
    ),
    EdanSeccionDescriptor(
      rutaV2: 'unidades-educativas',
      llaveJson: 'unidades_educativas',
      tipo: EdanSeccionTipo.unoAN,
      tabla: 'unidades_educativas',
      usaFoto: true,
    ),
    EdanSeccionDescriptor(
      rutaV2: 'danos-vivienda',
      llaveJson: 'danos_vivienda',
      tipo: EdanSeccionTipo.unoAN,
      tabla: 'danos_vivienda',
      usaFoto: true,
    ),
    EdanSeccionDescriptor(
      rutaV2: 'danos-agricultura',
      llaveJson: 'danos_agricultura',
      tipo: EdanSeccionTipo.unoAN,
      tabla: 'danos_agricultura',
      usaFoto: true,
    ),
    EdanSeccionDescriptor(
      rutaV2: 'danos-pecuarios',
      llaveJson: 'danos_pecuarios',
      tipo: EdanSeccionTipo.unoAN,
      tabla: 'danos_pecuario',
      usaFoto: true,
    ),
    EdanSeccionDescriptor(
      rutaV2: 'infra-productiva',
      llaveJson: 'infra_productiva',
      tipo: EdanSeccionTipo.unoAN,
      tabla: 'infra_productiva',
      usaFoto: true,
    ),
    EdanSeccionDescriptor(
      rutaV2: 'proteccion',
      llaveJson: 'proteccion',
      tipo: EdanSeccionTipo.unoAN,
      tabla: 'proteccion',
    ),
    EdanSeccionDescriptor(
      rutaV2: 'primera-respuesta',
      llaveJson: 'necesidad_primera_respuesta',
      tipo: EdanSeccionTipo.unoAUno,
      tabla: 'primera_respuesta',
    ),
    EdanSeccionDescriptor(
      rutaV2: 'necesidad-salud',
      llaveJson: 'necesidad_salud',
      tipo: EdanSeccionTipo.unoAUno,
      tabla: 'salud_necesidades',
    ),
    EdanSeccionDescriptor(
      rutaV2: 'necesidad-humanitaria',
      llaveJson: 'necesidad_humanitaria',
      tipo: EdanSeccionTipo.unoAUno,
      tabla: 'necesidades_humanitarias',
    ),
  ];

  /// Nombre de la tabla SQLite de una sección dada su ruta v2.
  static String? tablaDeRuta(String rutaV2) => porRuta(rutaV2)?.tablaSqlite;

  /// Páginas del wizard EDAN (clave de página) -> rutas v2 que impactan.
  /// `cabecera` agrupa Datos generales (01), población (02) y Responsable (13).
  static const Map<String, List<String>> paginasWizard = {
    '01': [cabecera],
    '02': [cabecera],
    '03': ['impacto-poblacion', 'primera-respuesta'],
    '04': ['salud-establecimientos', 'necesidad-salud'],
    '05': ['danos-viales', 'danos-infra-publica'],
    '06': ['servicios-basicos'],
    '07': ['unidades-educativas'],
    '08': ['danos-vivienda'],
    '09': ['danos-agricultura', 'danos-pecuarios', 'infra-productiva'],
    '10': ['proteccion'],
    '11': ['necesidad-humanitaria'],
    '13': [cabecera],
  };

  static EdanSeccionDescriptor? porRuta(String rutaV2) {
    for (final s in secciones) {
      if (s.rutaV2 == rutaV2) return s;
    }
    return null;
  }

  /// Ruta v2 a partir del nombre de TABLA que envía el servidor en
  /// `sync/pull → secciones[].tipo_seccion` (p. ej. `danos_agricultura` →
  /// `danos-agricultura`). La columna `filas_seccion.tipo` guarda SIEMPRE
  /// ruta (la que escribe el wizard); el pull es el único que trae tabla.
  /// Si ya es ruta se devuelve igual; si es desconocida se devuelve igual
  /// (no se pierde dato: el llamador decide qué hacer).
  static String rutaDesdeTabla(String tabla) {
    for (final s in secciones) {
      if (s.tabla == tabla) return s.rutaV2;
    }
    return porRuta(tabla)?.rutaV2 ?? tabla;
  }

  static List<String> rutasV2Todas() =>
      secciones.map((s) => s.rutaV2).toList();

  /// Nombres de todas las tablas SQLite de sección (Modelo A v20).
  static List<String> tablasSqlite() =>
      secciones.map((s) => s.tablaSqlite).toList();

  /// Nombres de las tablas SQLite de sección con foto.
  static List<String> tablasSqliteConFoto() =>
      secciones.where((s) => s.usaFoto).map((s) => s.tablaSqlite).toList();

  /// Busca en las tablas con foto cuál contiene el [idSeccion] dado.
  /// Retorna el nombre de la tabla o '' si no se encuentra.
  static Future<String> buscarTablaPorIdSeccion(
    String idSeccion,
    DatabaseHelper db,
  ) async {
    final database = await db.database;
    for (final desc in secciones.where((s) => s.usaFoto)) {
      final tabla = desc.tablaSqlite;
      final result = await database.query(
        tabla,
        columns: ['id_seccion'],
        where: 'id_seccion = ?',
        whereArgs: [idSeccion],
        limit: 1,
      );
      if (result.isNotEmpty) return tabla;
    }
    return '';
  }

  /// Rutas v2 que debe marcar una página dada del wizard.
  static List<String> rutasDePagina(String paginaWizard) =>
      paginasWizard[paginaWizard] ?? const [];

  /// **Matriz grupo × secciones** — fuente única de verdad del wizard.
  ///
  /// Cada grupo (checkbox de page01) activa un conjunto de rutas v2. Toda la
  /// derivación en AMBAS direcciones sale de aquí:
  ///
  /// * **Adelante** (formulario nuevo): [rutasDesdeGrupos] — lo que tildó el
  ///   usuario determina qué secciones existen.
  /// * **Atrás** (reabrir borrador / primera sync): [gruposDesdeActivas] — las
  ///   secciones que tienen datos reales determinan qué grupos quedan tildados.
  ///
  /// Es la única copia de esta relación: antes vivía duplicada en
  /// `checkboxSecciones` y en el `_seccionesDesdeFlags` del wizard, que podían
  /// desincronizarse.
  static const Map<String, List<String>> matrizGrupoSecciones = {
    'grupPoblacion': ['impacto-poblacion', 'primera-respuesta'],
    'grupSalud': ['salud-establecimientos', 'necesidad-salud'],
    'grupInfraestructura': ['danos-viales', 'danos-infra-publica'],
    'grupServicios': ['servicios-basicos'],
    'grupEducacion': ['unidades-educativas'],
    'grupVivienda': ['danos-vivienda'],
    'grupAgropecuario': ['danos-agricultura', 'danos-pecuarios', 'infra-productiva'],
    'grupProteccion': ['proteccion'],
    'grupNecesidades': ['necesidad-humanitaria'],
  };

  /// **`tipo_entidad` canónico** de una sección, para `POST /fotografias`.  ///
  /// La tabla `edan.fotografias` tiene un **CHECK** sobre `tipo_entidad` con
  /// los **14 nombres cortos de sección** (el nombre de la tabla sin el prefijo
  /// `edan_localidades_`) **más `'vivienda'`** — EDAN_ESQUEMA_BD §3.7,
  /// PLAN_APIS_V2_EDAN §7. OJO: ese nombre es [EdanSeccionDescriptor.tabla], NO
  /// [EdanSeccionDescriptor.llaveJson]: difieren en `salud_establecimientos`
  /// (la clave JSON es `establecimientos_salud`) y en `primera_respuesta`
  /// (`necesidad_primera_respuesta`). Enviar el nombre equivocado viola el
  /// CHECK y el servidor rechaza la foto.
  static String? tipoEntidadDeRuta(String rutaV2) => porRuta(rutaV2)?.tabla;

  /// `llaveJson` de una flag `imp_*` (`imp_danos_agricultura` → clave
  /// `danos_agricultura` del payload). Se usa para autocorregir el 400
  /// "flag true sin filas" sin tocar SQLite.
  static String? llaveJsonDeImp(String impKey) {
    if (!impKey.startsWith('imp_')) return null;
    final ruta = impKey.substring(4).replaceAll('_', '-');
    return porRuta(ruta)?.llaveJson;
  }

  /// Traduce el `tipo` guardado en `filas_seccion` al `tipo_entidad` del CHECK,
  /// tolerando las tres formas que circulan por la app y sus datos históricos:
  ///  * ruta v2 con guiones (`danos-agricultura`) — la que escribe el wizard;
  ///  * nombre de tabla con guiones bajos (`danos_agricultura`) — la que ya es
  ///    válida, y la que usan varios seeds/pruebas;
  ///  * ruta v2 escrita con guiones bajos (`salud_establecimientos` →
  ///    `salud-establecimientos`).
  static String? tipoEntidadDesdeTipo(String tipo) {
    if (esTipoEntidadValido(tipo)) return tipo;
    final desc = porRuta(tipo) ?? porRuta(tipo.replaceAll('_', '-'));
    return desc?.tabla;
  }

  /// `True` si [valor] es uno de los 15 `tipo_entidad` admitidos por el CHECK
  /// de `edan.fotografias`.
  static bool esTipoEntidadValido(String? valor) =>
      valor == 'vivienda' ||
      (valor != null && secciones.any((s) => s.tabla == valor));

  /// Orden estable de los grupos, igual al que se pinta en page01.
  static const List<String> grupos = [
    'grupPoblacion',
    'grupSalud',
    'grupInfraestructura',
    'grupServicios',
    'grupEducacion',
    'grupVivienda',
    'grupAgropecuario',
    'grupProteccion',
    'grupNecesidades',
  ];

  /// **Id local del grupo → clave `grup_*` del contrato** (nodo `grupos` del
  /// `GET /formularios/{uuid}/completo`, PLAN_APIS_V2_EDAN §20.2).
  ///
  /// Los 9 grupos NUNCA viajan en el `POST /completo`: el servidor los deriva
  /// de las 14 flags de sección. Son un vocabulario distinto al de `imp_*`,
  /// que sí identifica secciones (14). Esta tabla es la única traducción
  /// autorizada entre ambos mundos; úsela cualquier pantalla o depuración que
  /// muestre grupos, para no seguir dibujándolos con prefijo `imp`.
  static const Map<String, String> grupApiDeId = {
    'grupPoblacion': 'grup_poblacion',
    'grupSalud': 'grup_salud',
    'grupInfraestructura': 'grup_infraestructura',
    'grupServicios': 'grup_servicios',
    'grupEducacion': 'grup_educacion',
    'grupVivienda': 'grup_vivienda',
    'grupAgropecuario': 'grup_agropecuario',
    'grupProteccion': 'grup_proteccion',
    'grupNecesidades': 'grup_necesidades',
  };

  /// Inversa de [grupApiDeId]: `grup_poblacion` → `grupPoblacion`. Es la que
  /// consume el pull para cachear el nodo `grupos` en `grupos_local`.
  static Map<String, String> get idDeGrupApi => {
        for (final e in grupApiDeId.entries) e.value: e.key,
      };

  /// Compatibilidad: los llamadores históricos siguen usando este nombre.
  static Map<String, List<String>> get checkboxSecciones => matrizGrupoSecciones;

  /// Bloqueos del botón Siguiente para las rutas de una página del wizard.
  ///
  /// Gatillo: grupo marcado en page01 (`grup* == true`). Las `imp_*` NO son
  /// precondition porque se derivan de las filas: una página vacía las deja
  /// en `false` y anularía el bloqueo (justo el caso que hay que cerrar).
  ///
  /// Regla por grupo, sobre sus rutas que viven en ESTA página:
  ///
  /// * **1:1** ([EdanSeccionTipo.unoAUno]): el registro debe estar COMPLETO
  ///   (`registro.tieneDatos` — regla espejo del servidor: algún checkbox,
  ///   número > 0 o texto con contenido). Se exige en AND.
  /// * **1:N** ([EdanSeccionTipo.unoAN]): ≥1 hija válida en ALGUNA de sus
  ///   secciones (OR dentro del grupo). Casos especiales: `danos-vivienda`
  ///   exige ≥1 `vivienda` hija en el padre (los contadores legacy
  ///   `dano_parcial`/`dano_total` no se llenan en el flujo V2); los catálogos
  ///   (`impacto-poblacion` 4, `proteccion` 8) exigen ≥1 grupo con datos.
  ///
  /// Ejemplo mixto: en page03, aunque `impacto-poblacion` tenga datos, el
  /// registro 1:1 de `primera-respuesta` debe estar lleno para avanzar.
  /// Las páginas de cabecera (01/02/13) no tienen grupo → nunca bloquean.
  /// Devuelve mensajes listos para el tooltip; vacío = puede avanzar.
  static List<String> bloqueosSiguiente(
      EdanLocalidad loc, List<String> rutasPagina) {
    final grupos = <String>{};
    for (final r in rutasPagina) {
      final g = grupoDeRuta(r);
      if (g != null) grupos.add(g);
    }
    final out = <String>[];
    for (final g in grupos) {
      if (!grupoMarcado(loc, g)) continue;
      final rutasPaginaGrupo =
          rutasDeGrupo(g).where(rutasPagina.contains).toList();
      // 1:1: el registro de la página debe ir completo (AND).
      for (final r in rutasPaginaGrupo.where(esRuta1a1)) {
        if (!registro1a1Completo(loc, r)) out.add(mensajeRegistro1a1(r));
      }
      // 1:N: basta ≥1 hija válida en cualquiera de sus secciones (OR).
      if (rutasPaginaGrupo.any((r) => !esRuta1a1(r))) {
        final bloqueo = bloqueoHijas(loc, g);
        if (bloqueo != null) out.add(bloqueo);
      }
    }
    return out;
  }

  /// ¿El grupo de page01 está marcado? Única autoridad del armado del
  /// formulario (los `imp_*` se derivan de las filas, no mandan).
  static bool grupoMarcado(EdanLocalidad loc, String grupo) => switch (grupo) {
        'grupPoblacion' => loc.grupPoblacion,
        'grupSalud' => loc.grupSalud,
        'grupInfraestructura' => loc.grupInfraestructura,
        'grupServicios' => loc.grupServicios,
        'grupEducacion' => loc.grupEducacion,
        'grupVivienda' => loc.grupVivienda,
        'grupAgropecuario' => loc.grupAgropecuario,
        'grupProteccion' => loc.grupProteccion,
        'grupNecesidades' => loc.grupNecesidades,
        _ => false,
      };

  /// ¿La ruta v2 es una sección 1:1 (registro único)?
  static bool esRuta1a1(String rutaV2) =>
      porRuta(rutaV2)?.tipo == EdanSeccionTipo.unoAUno;

  /// Registro 1:1 presente y completo (`tieneDatos`, regla espejo del
  /// servidor). Rutas 1:1 desconocidas no bloquean.
  static bool registro1a1Completo(EdanLocalidad loc, String rutaV2) =>
      switch (rutaV2) {
        'primera-respuesta' =>
          loc.necesidadPrimeraRespuesta?.tieneDatos ?? false,
        'necesidad-salud' => loc.necesidadSalud?.tieneDatos ?? false,
        'necesidad-humanitaria' =>
          loc.necesidadHumanitaria?.tieneDatos ?? false,
        _ => true,
      };

  /// Mensaje del bloqueo 1:1 para el tooltip de Siguiente.
  static String mensajeRegistro1a1(String rutaV2) => switch (rutaV2) {
        'primera-respuesta' =>
          'Población: complete el registro de primera respuesta',
        'necesidad-salud' =>
          'Salud: complete el registro de necesidad de salud',
        'necesidad-humanitaria' =>
          'Necesidades: complete el registro de necesidades humanitarias',
        _ => 'Complete el registro de $rutaV2',
      };

  /// Bloqueo 1:N del grupo: `null` cuando hay ≥1 hija válida en ALGUNA de
  /// sus secciones (OR), mensaje de lo que falta en caso contrario.
  static String? bloqueoHijas(EdanLocalidad loc, String grupo) {
    switch (grupo) {
      case 'grupPoblacion':
        if (!loc.impactoPoblacion.any((i) => i.tieneDatosGlobales)) {
          return 'Población: agregue datos en al menos un grupo etario';
        }
      case 'grupSalud':
        if (!loc.establecimientosSalud
            .any((s) => s.nombreEstablecimiento.trim().isNotEmpty)) {
          return 'Salud: agregue al menos un establecimiento';
        }
      case 'grupInfraestructura':
        final ok = loc.danosViales
                .any((d) => d.viaPuente.trim().isNotEmpty) ||
            loc.danosInfraPublica
                .any((d) => d.tipoEstructura.trim().isNotEmpty);
        if (!ok) {
          return 'Infraestructura: agregue un tramo vial o una estructura';
        }
      case 'grupServicios':
        if (!loc.serviciosBasicos.any((s) => s.tieneDatos)) {
          return 'Servicios básicos: agregue al menos un servicio';
        }
      case 'grupEducacion':
        if (!loc.unidadesEducativas.any((u) =>
            u.nombreEstablecimiento.trim().isNotEmpty ||
            u.estudiantes > 0 ||
            u.profesores > 0 ||
            u.administrativos > 0)) {
          return 'Educación: agregue al menos una unidad educativa';
        }
      case 'grupVivienda':
        // El flujo 1:N vive en `viviendas` (las hijas): los contadores legacy
        // `dano_parcial`/`dano_total` del padre NO se llenan en la página 08
        // (los contadores visibles son los derivados `viviendasParcial/
        // ViviendasTotal`). Validar por ellos bloqueaba "Siguiente" aunque el
        // usuario ya tuviera viviendas capturadas (bug 2026-11-02). Basta ≥1
        // hija en el padre; sin hijas no hay sección.
        if (!loc.danosVivienda.any((v) => v.viviendas.isNotEmpty)) {
          return 'Vivienda: agregue al menos una vivienda con daño';
        }
      case 'grupAgropecuario':
        final ok = loc.danosAgricultura
                .any((a) => a.tipoCultivo.trim().isNotEmpty) ||
            loc.danosPecuarios.any((p) => p.especie.trim().isNotEmpty) ||
            loc.infraProductiva.any((i) => i.tipo.trim().isNotEmpty);
        if (!ok) {
          return 'Agropecuario: agregue al menos una fila en '
              'agricultura, pecuarios o infra productiva';
        }
      case 'grupProteccion':
        if (!loc.proteccion.any((p) => p.tieneDatos)) {
          return 'Protección: agregue datos en al menos un grupo';
        }
    }
    return null;
  }

  /// Bloqueos de campos obligatorios de las páginas de cabecera del wizard.
  ///
  /// * `'01'`: sus cinco asteriscos (`tipoLocalidad`, `nombre`,
  ///   `idTipoEvento`, `fechaEvento`, `horaEvento` — esta solo se escribe con
  ///   hora Y AM/PM) y ≥1 de las 9 casillas de impacto marcadas (el
  ///   formulario se arma acá).
  /// * `'02'`: los 3 totales > 0. La página muestra 0 como campo vacío
  ///   (`int.tryParse(text) ?? 0`), así que "> 0" == "llenado".
  /// * `intro`, `'13'` (solo-lectura autollenada por token) y páginas de
  ///   secciones: `[]` (éstas se gatean con [bloqueosSiguiente]).
  /// Un mensaje por falta, en el orden en que se pintan en la pantalla.
  static List<String> bloqueosCamposPagina(
      EdanLocalidad loc, String paginaKey) {
    switch (paginaKey) {
      case '01':
        final f = <String>[];
        if (loc.tipoLocalidad.trim().isEmpty) {
          f.add('Página 1: seleccione la organización territorial');
        }
        if (loc.nombre.trim().isEmpty) {
          f.add('Página 1: escriba el nombre del lugar');
        }
        if (loc.idTipoEvento == null) {
          f.add('Página 1: seleccione el evento extremo');
        }
        if ((loc.fechaEvento ?? '').trim().isEmpty) {
          f.add('Página 1: indique la fecha de ocurrencia');
        }
        if ((loc.horaEvento ?? '').trim().isEmpty) {
          f.add('Página 1: indique la hora de ocurrencia (hora y AM/PM)');
        }
        final algunCheck = loc.grupPoblacion ||
            loc.grupSalud ||
            loc.grupInfraestructura ||
            loc.grupServicios ||
            loc.grupEducacion ||
            loc.grupVivienda ||
            loc.grupAgropecuario ||
            loc.grupProteccion ||
            loc.grupNecesidades;
        if (!algunCheck) {
          f.add('Página 1: marque al menos una categoría de afectación');
        }
        return f;
      case '02':
        final f = <String>[];
        if (loc.totalFamiliasDamnificadas <= 0) {
          f.add('Página 2: ingrese las familias damnificadas');
        }
        if (loc.totalFamiliasAfectadas <= 0) {
          f.add('Página 2: ingrese las familias afectadas');
        }
        if (loc.totalPoblacionAfectada <= 0) {
          f.add('Página 2: ingrese la población total afectada');
        }
        return f;
      default:
        return const [];
    }
  }

  /// Rutas v2 que activa un grupo.
  static List<String> rutasDeGrupo(String grupo) =>
      matrizGrupoSecciones[grupo] ?? const [];

  /// Grupo responsable de una ruta (el primero que la liste). Devuelve `null`
  /// si la ruta no pertenece a ninguna matriz.
  static String? grupoDeRuta(String ruta) {
    for (final entry in matrizGrupoSecciones.entries) {
      if (entry.value.contains(ruta)) return entry.key;
    }
    return null;
  }

  /// Columna `grup_*` de `formularios` para una ruta
  /// (`danos-agricultura` → `grup_agropecuario`). `null` si la ruta no tiene
  /// grupo en la matriz.
  static String? columnaGrupoDeRuta(String ruta) {
    final grupo = grupoDeRuta(ruta);
    if (grupo == null) return null;
    return _aSnake(grupo);
  }

  /// Unión de las rutas de varios grupos. Ignora grupos desconocidos.
  static List<String> rutasDesdeGrupos(Iterable<String> gruposMarcados) {
    final result = <String>{};
    for (final g in gruposMarcados) {
      result.addAll(rutasDeGrupo(g));
    }
    return result.toList();
  }

  /// **Derivación inversa**: dadas las rutas activas, qué grupos quedan
  /// tildados. Es el complemento de [rutasDesdeGrupos] y garantiza que
  /// `rutasDesdeGrupos(gruposDesdeActivas(r)) ⊇ r`.
  static Set<String> gruposDesdeActivas(Iterable<String> rutas) {
    final activas = rutas.toSet();
    final result = <String>{};
    for (final entry in matrizGrupoSecciones.entries) {
      if (entry.value.any(activas.contains)) result.add(entry.key);
    }
    return result;
  }

  /// Rutas v2 que realmente tienen filas persistidas para [uuidEdanLocalidad].
  /// Es la "verdad en los datos": una sección sin checkbox pero con filas
  /// guardadas debe seguir visible al reabrir el borrador.
  static Future<List<String>> rutasConDatos(
    String uuidEdanLocalidad,
    DatabaseHelper db,
  ) async {
    final database = await db.database;
    final rows = await database.query(
      'filas_seccion',
      columns: ['DISTINCT tipo'],
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuidEdanLocalidad],
    );
    final conocidas = secciones.map((s) => s.rutaV2).toSet();
    return rows
        .map((r) => r['tipo'] as String?)
        .whereType<String>()
        .where(conocidas.contains)
        .toList();
  }

  /// Mapping de referencia: sección (ruta v2) → flags que setea.
  ///
  /// La derivación en runtime ya NO usa este mapa (sale de
  /// [matrizGrupoSecciones] + nombre de ruta en [construirFlagsDesdeActivas]);
  /// se mantiene como documentación del contrato y para los tests que
  /// validan la cobertura de secciones con foto.
  static const Map<String, List<String>> seccionFlags = {
    'impacto-poblacion': ['imp_impacto_poblacion', 'grup_poblacion'],
    'primera-respuesta': ['imp_primera_respuesta', 'grup_poblacion'],
    'salud-establecimientos': ['imp_salud_establecimientos', 'grup_salud'],
    'necesidad-salud': ['imp_necesidad_salud', 'grup_salud', 'grup_necesidades'],
    'danos-viales': ['imp_danos_viales', 'grup_infraestructura'],
    'danos-infra-publica': ['imp_danos_infra_publica', 'grup_infraestructura'],
    'servicios-basicos': ['imp_servicios_basicos', 'grup_servicios'],
    'unidades-educativas': ['imp_unidades_educativas', 'grup_educacion'],
    'danos-vivienda': ['imp_danos_vivienda', 'grup_vivienda'],
    'danos-agricultura': ['imp_danos_agricultura', 'grup_agropecuario'],
    'danos-pecuarios': ['imp_danos_pecuarios', 'grup_agropecuario'],
    'infra-productiva': ['imp_infra_productiva', 'grup_agropecuario'],
    'proteccion': ['imp_proteccion', 'grup_proteccion'],
    'necesidad-humanitaria': ['imp_necesidad_humanitaria', 'grup_necesidades'],
  };

  /// Construye los **23 flags** a partir de las secciones activas, con el
  /// vocabulario exacto del contrato (§20.1/§20.2):
  ///
  /// * **14 `imp_*`** = las **SECCIONES** (una por ruta; `-` → `_`). Son las
  ///   únicas que viajan en `POST /formularios/completo`.
  /// * **9 `grup_*`** = los **GRUPOS** de page01, derivados de
  ///   [matrizGrupoSecciones]; nunca se envían, el servidor los deriva.
  ///
  /// Todas las 23 claves están siempre presentes (en `false` cuando no
  /// aplican), para que los llamadores puedan leer sin `??`. Antes eran 22 con
  /// una **colisión**: el grupo Protección y la sección 14 compartían el nombre
  /// `imp_proteccion`; con `grup_proteccion` separado, cada clave significa una
  /// sola cosa.
  ///
  /// Nota de comportamiento: antes `necesidad-salud` encendía también
  /// `grup_necesidades`, acoplando page04 con page11. La matriz es la
  /// autoridad: `grup_necesidades` solo viene de `necesidad-humanitaria`.
  static Map<String, bool> construirFlagsDesdeActivas(List<String> activas) {
    final set = activas.toSet();
    final flags = <String, bool>{};

    // Flags de sección: uno por cada una de las 14 rutas.
    for (final s in secciones) {
      flags['imp_${s.rutaV2.replaceAll('-', '_')}'] = set.contains(s.rutaV2);
    }
    // Flags de grupo: derivados de la matriz grupo × secciones.
    for (final entry in matrizGrupoSecciones.entries) {
      flags[_aSnake(entry.key)] = entry.value.any(set.contains);
    }
    return flags;
  }

  /// `grupPoblacion` → `grup_poblacion` (el prefijo sale de la propia clave, así
  /// que renombrar los grupos a `grup*` automaticamente produce `grup_*`).
  static String _aSnake(String grupo) => grupo.replaceAllMapped(
        RegExp(r'([A-Z])'),
        (m) => '_${m[1]!.toLowerCase()}',
      );

  /// Columna `grup_*` de `formularios` para un grupo camel
  /// (`grupAgropecuario` → `grup_agropecuario`).
  static String columnaDeGrupo(String grupo) => _aSnake(grupo);

  /// Labels de las secciones visibles en el wizard, indexados por el flag de page01.
  static const Map<String, String> _seccionLabels = {
    'grupPoblacion': 'Población',
    'grupSalud': 'Salud',
    'grupInfraestructura': 'Infraestructura',
    'grupServicios': 'Servicios',
    'grupEducacion': 'Educación',
    'grupVivienda': 'Vivienda',
    'grupAgropecuario': 'Agropecuario',
    'grupProteccion': 'Protección',
    'grupNecesidades': 'Necesidades',
  };

  /// Labels cortos para los badges de impacto (términos completos).
  static const Map<String, String> _seccionLabelsCortos = {
    'grupPoblacion': 'Población',
    'grupSalud': 'Salud',
    'grupInfraestructura': 'Infraestructura',
    'grupServicios': 'Servicios',
    'grupEducacion': 'Educación',
    'grupVivienda': 'Vivienda',
    'grupAgropecuario': 'Agricultura',
    'grupProteccion': 'Protección',
    'grupNecesidades': 'Necesidades',
  };

  /// Retorna los labels de los grupos activos según los flags imp_* de la localidad.
  /// Refleja exactamente lo que se marca en page01 (los 9 grup_*).
  static List<String> seccionesActivasLabels(EdanLocalidad l) {
    final result = <String>[];
    if (l.grupPoblacion) result.add(_seccionLabels['grupPoblacion']!);
    if (l.grupSalud) result.add(_seccionLabels['grupSalud']!);
    if (l.grupInfraestructura) result.add(_seccionLabels['grupInfraestructura']!);
    if (l.grupServicios) result.add(_seccionLabels['grupServicios']!);
    if (l.grupEducacion) result.add(_seccionLabels['grupEducacion']!);
    if (l.grupVivienda) result.add(_seccionLabels['grupVivienda']!);
    if (l.grupAgropecuario) result.add(_seccionLabels['grupAgropecuario']!);
    if (l.grupProteccion) result.add(_seccionLabels['grupProteccion']!);
    if (l.grupNecesidades) result.add(_seccionLabels['grupNecesidades']!);
    return result;
  }

  /// Retorna los labels cortos (estilo UGR) de las secciones activas según los
  /// grupos grup_* de la localidad.
  static List<String> seccionesActivasLabelsCortos(EdanLocalidad l) {
    final result = <String>[];
    if (l.grupPoblacion) result.add(_seccionLabelsCortos['grupPoblacion']!);
    if (l.grupSalud) result.add(_seccionLabelsCortos['grupSalud']!);
    if (l.grupInfraestructura) result.add(_seccionLabelsCortos['grupInfraestructura']!);
    if (l.grupServicios) result.add(_seccionLabelsCortos['grupServicios']!);
    if (l.grupEducacion) result.add(_seccionLabelsCortos['grupEducacion']!);
    if (l.grupVivienda) result.add(_seccionLabelsCortos['grupVivienda']!);
    if (l.grupAgropecuario) result.add(_seccionLabelsCortos['grupAgropecuario']!);
    if (l.grupProteccion) result.add(_seccionLabelsCortos['grupProteccion']!);
    if (l.grupNecesidades) result.add(_seccionLabelsCortos['grupNecesidades']!);
    return result;
  }
}