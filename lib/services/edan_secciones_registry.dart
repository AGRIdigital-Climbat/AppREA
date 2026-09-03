import 'database_helper.dart';

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
      tabla: 'danos_pecuarios',
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
      tabla: 'necesidad_salud',
    ),
    EdanSeccionDescriptor(
      rutaV2: 'necesidad-humanitaria',
      llaveJson: 'necesidad_humanitaria',
      tipo: EdanSeccionTipo.unoAUno,
      tabla: 'necesidad_humanitaria',
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

  /// Mapping: checkbox de page01 → secciones que activa.
  static const Map<String, List<String>> checkboxSecciones = {
    'impPoblacion': ['impacto-poblacion', 'primera-respuesta'],
    'impSalud': ['salud-establecimientos', 'necesidad-salud'],
    'impInfraestructura': ['danos-viales', 'danos-infra-publica'],
    'impServicios': ['servicios-basicos'],
    'impEducacion': ['unidades-educativas'],
    'impVivienda': ['danos-vivienda'],
    'impAgropecuario': ['danos-agricultura', 'danos-pecuarios', 'infra-productiva'],
    'impProteccion': ['proteccion'],
    'impNecesidades': ['necesidad-humanitaria'],
  };

  /// Mapping: sección (ruta_v2) → flags imp_* que setea (alineado a backend IMP_FLAG_POR_TABLA).
  static const Map<String, List<String>> seccionFlags = {
    'impacto-poblacion': ['imp_impacto_poblacion', 'imp_poblacion'],
    'primera-respuesta': ['imp_primera_respuesta', 'imp_poblacion'],
    'salud-establecimientos': ['imp_salud_establecimientos', 'imp_salud'],
    'necesidad-salud': ['imp_necesidad_salud', 'imp_salud', 'imp_necesidades'],
    'danos-viales': ['imp_danos_viales', 'imp_infraestructura'],
    'danos-infra-publica': ['imp_danos_infra_publica', 'imp_infraestructura'],
    'servicios-basicos': ['imp_servicios_basicos', 'imp_servicios'],
    'unidades-educativas': ['imp_unidades_educativas', 'imp_educacion'],
    'danos-vivienda': ['imp_danos_vivienda', 'imp_vivienda'],
    'danos-agricultura': ['imp_danos_agricultura', 'imp_agropecuario'],
    'danos-pecuarios': ['imp_danos_pecuarios', 'imp_agropecuario'],
    'infra-productiva': ['imp_infra_productiva', 'imp_agropecuario'],
    'proteccion': ['imp_proteccion'],
    'necesidad-humanitaria': ['imp_necesidad_humanitaria', 'imp_necesidades'],
  };

  /// Construye los 22 flags imp_* a partir de las secciones activas.
  static Map<String, bool> construirFlagsDesdeActivas(List<String> activas) {
    final flags = <String, bool>{};
    for (final entry in seccionFlags.entries) {
      final isActive = activas.contains(entry.key);
      for (final flag in entry.value) {
        flags[flag] = isActive || (flags[flag] ?? false);
      }
    }
    return flags;
  }
}