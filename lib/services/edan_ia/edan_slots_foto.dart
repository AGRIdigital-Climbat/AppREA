/// Listado final de fotos y coordenadas del asistente.
///
/// El formulario EDAN tiene nueve secciones 1:n donde cada ítem lleva su propia
/// coordenada GPS y sus fotos (ver el mixin `EdanFotoHolder`). En el wizard cada
/// página lo pide en su momento; en el asistente la conversación no puede
/// hacerlo, porque una foto es una acción de cámara y el micrófono está
/// ocupado. Por eso las fotos se piden **al final**, en un listado, con el mismo
/// principio del wizard: **primero la coordenada, después la foto**
/// (`EdanBotonSacarFoto.capturar`).
///
/// Decisión de diseño: los slots se derivan de la [EdanLocalidad] ya
/// traducida, no del borrador. Las fotos no son algo que la IA pueda
/// inventar, y para entonces la ficha ya tiene sus filas reales con las claves
/// que se van a guardar.
library;

import '../../models/edan.dart';

/// Un ítem 1:n que puede llevar coordenada y fotos.
class EdanSlotFoto {
  /// Clave de sección (la de `EdanSeccionesRegistry`).
  final String seccion;

  /// Título legible de la sección, para agrupar el listado.
  final String titulo;

  /// Posición dentro de la lista de su sección. Las filas no tienen `id_seccion`
  /// hasta que se guardan, así que el índice es lo que las identifica mientras
  /// se edita.
  final int indice;

  /// El ítem real, para leer y escribir `coordenadaLat/Lon` y `fotos`.
  final EdanFotoHolder item;

  const EdanSlotFoto({
    required this.seccion,
    required this.titulo,
    required this.indice,
    required this.item,
  });

  /// Texto que identifica el ítem en la lista. Si no hay nombre se cae al
  /// contexto (comunidad, tramo) y, en último caso, a la posición.
  String get etiqueta {
    final i = item;
    final nombre = switch (i) {
      EdanEstablecimientoSalud(:final nombreEstablecimiento) => nombreEstablecimiento,
      EdanDanoVial(:final viaPuente) => viaPuente,
      EdanDanoInfraPublica(:final tipoEstructura) => tipoEstructura,
      EdanServicioBasicoDetalle(:final tipo) => tipo,
      EdanDanoUnidadEducativa(:final nombreEstablecimiento) => nombreEstablecimiento,
      EdanDanoVivienda(:final comunidad) => comunidad,
      EdanDanoAgricultura(:final tipoCultivo) => tipoCultivo,
      EdanDanoPecuario(:final especie) => especie,
      EdanInfraProductiva(:final tipo) => tipo,
      _ => '',
    };
    final extra = switch (i) {
      EdanDanoVial(:final tramo) => tramo,
      EdanDanoInfraPublica(:final comunidad) => comunidad,
      EdanDanoUnidadEducativa(:final comunidad) => comunidad,
      EdanDanoVivienda() => '',
      _ => '',
    };
    final n = nombre.trim();
    final e = extra.trim();
    if (n.isEmpty && e.isEmpty) return 'Ítem ${indice + 1}';
    if (e.isEmpty || e == n) return n;
    return n.isEmpty ? e : '$n · $e';
  }

  /// La coordenada 0/0 es "no capturada": `EdanFoto` y las columnas arrancan en
  /// cero, así que cero significa ausencia, no un punto en elAtlántico.
  bool get tieneCoordenada => item.coordenadaLat != 0 || item.coordenadaLon != 0;

  bool get tieneFoto => item.fotos.isNotEmpty || (item.fotografia ?? '').isNotEmpty;

  /// El ícono del listado: verde cuando ya tiene foto, cuando solo tiene
  /// coordenada, o vacío.
  bool get completo => tieneCoordenada && tieneFoto;

  /// Guarda una captura. Mantiene el orden del wizard: la coordenada se escribe
  /// siempre (venga o no con foto) y la foto se agrega a la lista.
  void registrarCaptura({
    required double lat,
    required double lon,
    EdanFoto? foto,
  }) {
    item.coordenadaLat = lat;
    item.coordenadaLon = lon;
    if (foto != null && foto.ruta.trim().isNotEmpty) {
      item.fotos.add(foto);
    }
  }
}

/// Títulos de las nueve secciones que aceptan foto.
///
/// Las claves son las de `EdanSeccionesRegistry.rutaV2`, no nombres invented:
/// es lo que usa `activarSecciones` al guardar, así que una clave inventada
/// acá dejaría la foto huérfana al sincronizar.
const Map<String, String> kEdanSeccionesConFoto = {
  'danos-viales': 'Daños en vías',
  'danos-infra-publica': 'Daños en infraestructura pública',
  'salud-establecimientos': 'Establecimientos de salud',
  'servicios-basicos': 'Servicios básicos',
  'unidades-educativas': 'Unidades educativas',
  'danos-vivienda': 'Daños en viviendas',
  'danos-agricultura': 'Daños en agricultura',
  'danos-pecuarios': 'Daños en ganadería',
  'infra-productiva': 'Infraestructura productiva',
};

/// Lista todos los ítems que pueden llevar foto, en el orden en que aparecen en
/// el formulario.
///
/// Solo entra lo que tiene datos: el traductor ya descarta las filas vacías, así
/// que no se ofrece sacar foto al vacío.
List<EdanSlotFoto> slotsDeFoto(EdanLocalidad l) => [
      ..._seccion(l.danosViales, 'danos-viales'),
      ..._seccion(l.danosInfraPublica, 'danos-infra-publica'),
      ..._seccion(l.establecimientosSalud, 'salud-establecimientos'),
      ..._seccion(l.serviciosBasicos, 'servicios-basicos'),
      ..._seccion(l.unidadesEducativas, 'unidades-educativas'),
      ..._seccion(l.danosVivienda, 'danos-vivienda'),
      ..._seccion(l.danosAgricultura, 'danos-agricultura'),
      ..._seccion(l.danosPecuarios, 'danos-pecuarios'),
      ..._seccion(l.infraProductiva, 'infra-productiva'),
    ];

/// Los mismos huecos pero agrupados por sección, para pintar el listado con
/// separadores. Se conservan las secciones sin ítems fuera del resultado.
Map<String, List<EdanSlotFoto>> slotsDeFotoPorSeccion(EdanLocalidad l) {
  final out = <String, List<EdanSlotFoto>>{};
  for (final s in slotsDeFoto(l)) {
    (out[s.seccion] ??= []).add(s);
  }
  return out;
}

/// Solo los que todavía les falta algo: es la lista de trabajo del paso final.
List<EdanSlotFoto> slotsPendientes(EdanLocalidad l) =>
    slotsDeFoto(l).where((s) => !s.completo).toList();

/// Resumen para el encabezado del paso final.
({int total, int conFoto, int soloCoordenada, int pendientes}) resumenFotos(
    EdanLocalidad l) {
  final s = slotsDeFoto(l);
  return (
    total: s.length,
    conFoto: s.where((x) => x.tieneFoto).length,
    soloCoordenada: s.where((x) => x.tieneCoordenada && !x.tieneFoto).length,
    pendientes: s.where((x) => !x.completo).length,
  );
}

List<EdanSlotFoto> _seccion<T extends EdanFotoHolder>(
  List<T> items,
  String seccion,
) =>
    [
      for (var i = 0; i < items.length; i++)
        EdanSlotFoto(
          seccion: seccion,
          titulo: kEdanSeccionesConFoto[seccion] ?? seccion,
          indice: i,
          item: items[i],
        ),
    ];
