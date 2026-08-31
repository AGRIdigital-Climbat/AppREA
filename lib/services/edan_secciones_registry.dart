/// Tipo de serialización de una sección en la API v2.
enum EdanSeccionTipo { unoAUno, unoAN }

/// Describe una sección de la EDAN para el sync v2 por secciones
/// (`/api/v2/edan/localidades/{id}/...`).
class EdanSeccionDescriptor {
  final String rutaV2;
  final String llaveJson;
  final EdanSeccionTipo tipo;
  final bool usaFoto;

  const EdanSeccionDescriptor({
    required this.rutaV2,
    required this.llaveJson,
    required this.tipo,
    this.usaFoto = false,
  });
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
    ),
    EdanSeccionDescriptor(
      rutaV2: 'salud-establecimientos',
      llaveJson: 'establecimientos_salud',
      tipo: EdanSeccionTipo.unoAN,
      usaFoto: true,
    ),
    EdanSeccionDescriptor(
      rutaV2: 'danos-viales',
      llaveJson: 'danos_viales',
      tipo: EdanSeccionTipo.unoAN,
      usaFoto: true,
    ),
    EdanSeccionDescriptor(
      rutaV2: 'danos-infra-publica',
      llaveJson: 'danos_infra_publica',
      tipo: EdanSeccionTipo.unoAN,
      usaFoto: true,
    ),
    EdanSeccionDescriptor(
      rutaV2: 'servicios-basicos',
      llaveJson: 'servicios_basicos',
      tipo: EdanSeccionTipo.unoAN,
      usaFoto: true,
    ),
    EdanSeccionDescriptor(
      rutaV2: 'unidades-educativas',
      llaveJson: 'unidades_educativas',
      tipo: EdanSeccionTipo.unoAN,
      usaFoto: true,
    ),
    EdanSeccionDescriptor(
      rutaV2: 'danos-vivienda',
      llaveJson: 'danos_vivienda',
      tipo: EdanSeccionTipo.unoAN,
      usaFoto: true,
    ),
    EdanSeccionDescriptor(
      rutaV2: 'danos-agricultura',
      llaveJson: 'danos_agricultura',
      tipo: EdanSeccionTipo.unoAN,
      usaFoto: true,
    ),
    EdanSeccionDescriptor(
      rutaV2: 'danos-pecuarios',
      llaveJson: 'danos_pecuarios',
      tipo: EdanSeccionTipo.unoAN,
      usaFoto: true,
    ),
    EdanSeccionDescriptor(
      rutaV2: 'infra-productiva',
      llaveJson: 'infra_productiva',
      tipo: EdanSeccionTipo.unoAN,
      usaFoto: true,
    ),
    EdanSeccionDescriptor(
      rutaV2: 'proteccion',
      llaveJson: 'proteccion',
      tipo: EdanSeccionTipo.unoAN,
    ),
    EdanSeccionDescriptor(
      rutaV2: 'primera-respuesta',
      llaveJson: 'necesidad_primera_respuesta',
      tipo: EdanSeccionTipo.unoAUno,
    ),
    EdanSeccionDescriptor(
      rutaV2: 'necesidad-salud',
      llaveJson: 'necesidad_salud',
      tipo: EdanSeccionTipo.unoAUno,
    ),
    EdanSeccionDescriptor(
      rutaV2: 'necesidad-humanitaria',
      llaveJson: 'necesidad_humanitaria',
      tipo: EdanSeccionTipo.unoAUno,
    ),
  ];

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

  /// Rutas v2 que debe marcar una página dada del wizard.
  static List<String> rutasDePagina(String paginaWizard) =>
      paginasWizard[paginaWizard] ?? const [];
}