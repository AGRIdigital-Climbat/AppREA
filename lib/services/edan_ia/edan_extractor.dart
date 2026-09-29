/// Extractor determinista de datos EDAN a partir de texto en español.
///
/// Puerto de `EDAN-Tutor/src/services/extractor.js`.
///
/// Existe porque un modelo que enruta (20B-30B) llenaría el formulario de forma
/// intermitente o inventada. Aquí cada campo se deduce por reglas, así que el
/// mismo texto siempre produce el mismo resultado y nunca se inventa un dato que
/// la persona no dijo. Lo que las reglas no alcanzan lo aporta la IA
/// ([EdanParche]), que se fusiona con el mismo tipo de parche.
///
/// En vez de exigir un orden fijo de palabras (frágil: "350 familias se vio
/// afectadas", "se dañaron 60 viviendas" y "afectadas 350 familias" son tres
/// formas de decir lo mismo), se busca la CIFRA MÁS CERCANA a un par de palabras
/// clave: un sustantivo ("familias") y un calificador ("afectada"). Así el orden
/// deja de importar.
library;

import '../../models/edan_borrador_ia.dart';
import 'edan_parche.dart';

// ---------------------------------------------------------------------------
// Utilidades de texto
// ---------------------------------------------------------------------------

const Map<String, String> _mapaTildes = {
  'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u',
  'Á': 'a', 'É': 'e', 'Í': 'i', 'Ó': 'o', 'Ú': 'u', 'Ü': 'u',
  'Ñ': 'n', 'ñ': 'n',
};

/// Normaliza para poder comparar sin tildes. Conserva longitud e índices, de modo
/// que las posiciones calculadas sobre el texto normalizado son válidas sobre el
/// original: eso permite recuperar "Yapacaní" con su tilde.
String sinTilde(Object? s) {
  final t = s?.toString() ?? '';
  if (t.isEmpty) return '';
  final out = StringBuffer();
  for (final c in t.split('')) {
    out.write(_mapaTildes[c] ?? c);
  }
  return out.toString();
}

String _capitalizar(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

/// Poner un topónimo o un nombre de establecimiento en mayúscula inicial:
/// "san pedro" → "San Pedro", "río yapacaní" → "Río Yapacaní".
///
/// Nota sobre la referencia: su comentario promete esos mismos ejemplos pero su
/// implementación solo capitalizaba la primera palabra ("San pedro"), así que
/// los nombres guardados salían en minúscula. Aquí se titulariza cada palabra.
String capitalizarLugar(String s) => s
    .split(RegExp(r'\s+'))
    .where((p) => p.isNotEmpty)
    .map(_capitalizar)
    .join(' ');

/// Quita la puntuación que el patrón de captura se comió al final del topónimo.
///
/// Sin esto, "municipio de Rurrenabaque." se guardaba como "Rurrenabaque.": el
/// carácter `[\w.-]*` de los patrones admite puntos, y el detalle acaba en la
/// base de datos.
String _sinPuntuacionFinal(String s) => s
    .replaceAll(RegExp(r'[\s.,;:!?¿¡]+$'), '')
    .trim();

/// Recupera el texto ORIGINAL entre dos índices calculados sobre [sinTilde],
/// para guardar nombres propios con sus tildes.
String literal(String original, int ini, int fin) {
  if (ini < 0 || fin > original.length || fin <= ini) return '';
  return original.substring(ini, fin);
}

/// "1.200" / "1,200" / "1200" → 1200 · "2.5" → 2.5 (decimal, no millar).
num? numero(Object? txt) {
  if (txt == null) return null;
  var s = txt.toString().trim();
  if (s.isEmpty) return null;
  final negativo = s.startsWith('-');
  s = s.replaceAll(RegExp(r'[^\d.,]'), '');
  if (s.isEmpty) return null;

  final coma = s.lastIndexOf(',');
  final punto = s.lastIndexOf('.');
  final sep = coma > punto ? coma : punto;
  if (sep > -1) {
    // "1.200" y "1,200" son millares; "2.5" es decimal.
    if (s.length - sep - 1 == 3 && s.length > 4) {
      s = '${s.substring(0, sep).replaceAll(RegExp('[.,]'), '')}${s.substring(sep + 1)}';
    } else {
      final entero = s.substring(0, sep).replaceAll(RegExp('[.,]'), '');
      final decimal = s.substring(sep + 1);
      s = (decimal.length <= 2 && entero.isNotEmpty)
          ? '$entero.$decimal'
          : s.replaceAll(RegExp('[.,]'), '');
    }
  } else {
    s = s.replaceAll(RegExp('[.,]'), '');
  }
  if (s.isEmpty || s == '.') return null;
  final n = num.tryParse(s);
  if (n == null || n.isNaN || n.isInfinite) return null;
  return negativo ? -n : n;
}

/// Redondea a entero para los campos que SQLite guarda como INTEGER.
int? aInt(Object? v) {
  final n = numero(v);
  if (n == null) return null;
  return n.round();
}

/// Una cifra del texto con su posición.
class _Cifra {
  final num n;
  final int ini;
  final int fin;
  _Cifra(this.n, this.ini, this.fin);
}

/// Todas las cifras del texto con su posición.
List<_Cifra> _cifras(String t) {
  final out = <_Cifra>[];
  final rx = RegExp(r'(\d{1,3}(?:[.,]\d{3})+|\d+)');
  for (final m in rx.allMatches(t)) {
    final n = numero(m.group(0));
    if (n != null) out.add(_Cifra(n, m.start, m.end));
  }
  return out;
}

/// Aparición de una palabra, con su posición.
class _Pos {
  final int ini;
  final int fin;
  _Pos(this.ini, this.fin);
}

/// Posiciones de aparición de cualquier palabra de una lista (prefijo, no
/// exacta: "dan" encuentra "daño", "dañada" y "danadas").
List<_Pos> _posicionesPalabras(String t, List<String> palabras) {
  final out = <_Pos>[];
  for (final palabra in palabras) {
    final w = sinTilde(palabra);
    if (w.isEmpty) continue;
    final rx = RegExp('(?<![a-z0-9])${RegExp.escape(w)}[a-z0-9]*',
        caseSensitive: false);
    for (final k in rx.allMatches(t)) {
      out.add(_Pos(k.start, k.end));
    }
  }
  return out;
}

bool _coincide(String t, List<String> palabras) =>
    _posicionesPalabras(t, palabras).isNotEmpty;

/// Cifra más cercana a un conjunto de grupos de palabras, exigiendo que estén
/// TODOS presentes cerca (así "afectadas" no se confunde con "damnificadas").
///
/// El último grupo es el que DISCRIMINA: la puntuación se calcula contra él. Sin
/// esto, en "350 familias afectadas y 80 familias damnificadas" el sustantivo
/// "familias" (cercano al 350) haría que ambas consultas devolvieran 350.
num? _cifraConContexto(String t, List<List<String>> grupos,
    {int ventana = 55}) {
  final nums = _cifras(t);
  if (nums.isEmpty) return null;
  final posPorGrupo = [for (final g in grupos) _posicionesPalabras(t, g)];
  if (posPorGrupo.any((p) => p.isEmpty)) return null;

  int distancia(_Cifra num, List<_Pos> kws) {
    var d = 1 << 30;
    for (final kw in kws) {
      final x = num.ini >= kw.fin
          ? num.ini - kw.fin
          : (kw.ini >= num.fin ? kw.ini - num.fin : 0);
      if (x < d) d = x;
    }
    return d;
  }

  final discriminante = posPorGrupo[posPorGrupo.length - 1];
  num? mejor;
  var mejorScore = 0;
  for (final c in nums) {
    final dist = [for (final p in posPorGrupo) distancia(c, p)];
    if (dist.any((d) => d > ventana)) continue;
    final score = distancia(c, discriminante);
    if (mejor == null || score < mejorScore) {
      mejor = c.n;
      mejorScore = score;
    }
  }
  return mejor;
}

// ---------------------------------------------------------------------------
// Vocabulario
// ---------------------------------------------------------------------------

const List<String> _familias = ['familia', 'familias', 'hogares', 'hogar'];
const List<String> _afectada = [
  'afectada', 'afectado', 'afectadas', 'afectados', 'afecta', 'tocado',
  'tocada', 'alcanzada', 'alcanzado', 'dan', 'danada', 'danado', 'danadas',
  'danados', 'perdid', 'perdi', 'toco',
];
const List<String> _damnificada = [
  'damnificada', 'damnificado', 'damnificadas', 'damnificados', 'destruida',
  'destruido', 'destruidas', 'destruidos', 'perdida', 'perdidas',
  'inhabitable', 'arrasada', 'arrasado', 'sin techo',
];
// Solo sustantivos: incluir aquí los adjetivos hacía que "350 familias afectadas"
// contara también como población afectada, duplicando el dato.
const List<String> _persona = [
  'persona', 'personas', 'gente', 'habitantes', 'vecinos', 'almas',
];
const List<String> _vivienda = [
  'vivienda', 'viviendas', 'casa', 'casas', 'hogar', 'hogares',
  'edificio', 'edificios',
];

// ---------------------------------------------------------------------------
// Eventos
// ---------------------------------------------------------------------------

const Map<String, List<String>> _aliasEvento = {
  'inundacion': [
    'inundacion', 'inundado', 'inundaciones', 'crecida', 'crecidas',
    'llovida', 'lluvia fuerte', 'lluvias fuertes', 'aguada',
  ],
  'riada': ['riada', 'riadas', 'arrastre', 'arrastrado', 'arrastrados'],
  'deslizamiento': [
    'deslizamiento', 'deslizamientos', 'deslave', 'deslaves', 'derrumbe',
    'derrumbes', 'tierra abajo',
  ],
  'helada': ['helada', 'heladas', 'escarcha', 'congelamiento', 'congelado'],
  'granizada': ['granizada', 'granizo', 'pedrisco', 'granizar'],
  'sequia': [
    'sequia', 'sequias', 'falta de agua', 'estiaje', 'resecada', 'resecado',
  ],
  'incendios': [
    'incendio', 'incendios', 'fuego', 'quema', 'arder', 'ardio', 'quemo',
    'quemado', 'fogonazo',
  ],
};

Map<String, bool> _detectarEventos(String t) {
  final parche = <String, bool>{};
  for (final key in kEdanClavesEvento) {
    final alias = _aliasEvento[key] ?? [key];
    if (_coincide(t, alias) || _coincide(t, [kEdanEtiquetasEvento[key]!])) {
      parche[key] = true;
    }
  }
  return parche;
}

// ---------------------------------------------------------------------------
// Población y vivienda
// ---------------------------------------------------------------------------

void _detectarPoblacion(String t, EdanParche p) {
  final pares = <String, List<List<String>>>{
    'totalFamiliasAfectadas': [_familias, _afectada],
    'totalFamiliasDamnificadas': [_familias, _damnificada],
    'totalAfectada': [_persona, _afectada],
  };
  for (final e in pares.entries) {
    final v = aInt(_cifraConContexto(t, e.value, ventana: 50));
    if (v != null) {
      switch (e.key) {
        case 'totalFamiliasAfectadas':
          p.totalFamiliasAfectadas = v;
        case 'totalFamiliasDamnificadas':
          p.totalFamiliasDamnificadas = v;
        default:
          p.totalAfectada = v;
      }
    }
  }
}

void _detectarVivienda(String t, EdanParche p) {
  final a = aInt(_cifraConContexto(t, [_vivienda, _afectada], ventana: 50));
  if (a != null) p.viviendasAfectadas = a;
  final d = aInt(_cifraConContexto(t, [_vivienda, _damnificada], ventana: 50));
  if (d != null) p.viviendasDamnificadas = d;
}

// ---------------------------------------------------------------------------
// Impacto en personas
// ---------------------------------------------------------------------------

class _HitImpacto {
  final int? indice;
  final String campo;
  final int valor;
  const _HitImpacto(this.indice, this.campo, this.valor);
}

List<_HitImpacto> _detectarImpactoPoblacion(String t) {
  final salida = <_HitImpacto>[];
  const heridos = ['herido', 'herida', 'heridos', 'heridas', 'lesionado'];
  const muertos = [
    'murio', 'murieron', 'fallecio', 'fallecieron', 'muerto', 'muerta',
    'fallecido',
  ];
  final reglas = <List<Object>>[
    [
      0,
      'fallecidos',
      [
        ['nino', 'nina', 'infante', 'menor', 'crianza'],
        muertos,
      ],
    ],
    [
      1,
      'heridos',
      [
        ['escolar', 'estudiante', 'escolares', 'estudiantes'],
        heridos,
      ],
    ],
    [
      2,
      'heridos',
      [
        ['adulto', 'persona', 'personas', 'hombre', 'mujer'],
        [...heridos, 'lesionada'],
      ],
    ],
    [
      3,
      'heridos',
      [
        ['anciano', 'anciana', 'abuelo', 'abuela', 'mayor'],
        heridos,
      ],
    ],
  ];
  for (final r in reglas) {
    final v = aInt(_cifraConContexto(t, (r[2] as List<List<String>>),
        ventana: 50));
    if (v != null) {
      salida.add(_HitImpacto(r[0] as int, r[1] as String, v));
    }
  }
  final desp = aInt(_cifraConContexto(
    t,
    [
      [
        'desaparecido', 'desaparecida', 'desaparecidos', 'desaparecidas',
        'perdido', 'perdida',
      ],
    ],
    ventana: 60,
  ));
  if (desp != null) salida.add(_HitImpacto(null, 'desaparecidos', desp));
  return salida;
}

// ---------------------------------------------------------------------------
// Fechas y hora
// ---------------------------------------------------------------------------

const Map<String, int> _meses = {
  'enero': 1, 'febrero': 2, 'marzo': 3, 'abril': 4, 'mayo': 5, 'junio': 6,
  'julio': 7, 'agosto': 8, 'septiembre': 9, 'setiembre': 9, 'octubre': 10,
  'noviembre': 11, 'diciembre': 12,
};

String _dos(int n) => n.toString().padLeft(2, '0');

void _detectarFechas(String t, EdanParche p) {
  var m = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b').firstMatch(t);
  if (m != null) {
    p.fechaEvento =
        '${m.group(1)}-${_dos(int.parse(m.group(2)!))}-${_dos(int.parse(m.group(3)!))}';
  }

  if (p.fechaEvento == null) {
    m = RegExp(
      r'\b(\d{1,2})\s*(?:de\s*)?(enero|febrero|marzo|abril|mayo|junio|julio|'
      r'agosto|septiembre|setiembre|octubre|noviembre|diciembre)\b'
      r'(?:\s*(?:de|del)?\s*(\d{4}))?',
      caseSensitive: false,
    ).firstMatch(t);
    if (m != null) {
      final mes = _dos(_meses[sinTilde(m.group(2)!).toLowerCase()] ?? 1);
      final dia = _dos(int.parse(m.group(1)!));
      final anio = m.group(3) ?? DateTime.now().year.toString();
      p.fechaEvento = '$anio-$mes-$dia';
    }
  }

  if (p.fechaEvento == null) {
    m = RegExp(r'\b(\d{1,2})[\/](\d{1,2})[\/](\d{2,4})\b').firstMatch(t);
    if (m != null) {
      final crudo = m.group(3)!;
      final anio = crudo.length == 2 ? '20$crudo' : crudo;
      p.fechaEvento =
          '$anio-${_dos(int.parse(m.group(2)!))}-${_dos(int.parse(m.group(1)!))}';
    }
  }

  final hora = _detectarHora(t);
  if (hora != null) p.horaEvento = hora;
}

String? _detectarHora(String t) {
  var m = RegExp(
    r'\ba\s+las\s+(\d{1,2})(?::(\d{2}))?\s*(?:horas|hs)?\s*'
    r'(am|pm|a\.?m\.?|de\s+la\s+(?:tarde|noche|mañana|manana))?',
    caseSensitive: false,
  ).firstMatch(t);
  m ??= RegExp(r'\b(\d{1,2}):(\d{2})\s*(am|pm|a\.?m\.?)?\b',
          caseSensitive: false)
      .firstMatch(t);
  if (m == null) return null;
  var h = int.parse(m.group(1)!);
  final suf = sinTilde((m.group(3) ?? '').toLowerCase());
  if (RegExp(r'pm|de la tarde|de la noche').hasMatch(suf) && h < 12) h += 12;
  if (RegExp(r'am|de la manana|de la mañana').hasMatch(suf) && h == 12) h = 0;
  if (h > 23) return null;
  return '${_dos(h)}:${m.group(2) ?? '00'}';
}

// ---------------------------------------------------------------------------
// Ubicación y contacto
// ---------------------------------------------------------------------------

const Map<String, String> _aliasDep = {
  'la paz': 'La Paz',
  'potosi': 'Potosí',
  'potosí': 'Potosí',
  'santa cruz': 'Santa Cruz',
  'cochabamba': 'Cochabamba',
  'chuquisaca': 'Chuquisaca',
  'oruro': 'Oruro',
  'pando': 'Pando',
  'beni': 'Beni',
  'tarija': 'Tarija',
};

/// Lo que puede seguir a un topónimo para cortar la captura.
const String _parada =
    r'(?=\s*(?:,|;|\.|\bque\b|\by\b|\ben\b|\bcon\b|$|hubo|tuvo|se\b|'
    r'est[áa]n|tiene|estaban|quedaron))';

/// Primera palabra de un topónimo. Acento incluido porque el texto ya viene
/// normalizado y el rango sin tilde basta, pero se conserva por legibilidad.
const String _cap = '[A-Za-zÁÉÍÓÚÑ]';
const String _capMay = '[A-ZÁÉÍÓÚÑ]';
const String _cuerpo = r'[\w.-]*';
const String _continuacion =
    r'(?:\s+(?:de|del|la|el|las|los|Villa|Pueblo|Nuevo|Nueva|Santa|San|'
    r'Mont(?:e|añ)o|[A-ZÁÉÍÓÚÑ][\w.-]*)){0,3}';

void _detectarUbicacion(String t, String original, EdanParche p) {
  for (final e in _aliasDep.entries) {
    if (RegExp('(?<![a-z0-9])${RegExp.escape(e.key)}(?![a-z0-9])',
            caseSensitive: false)
        .hasMatch(t)) {
      p.departamento = e.value;
      break;
    }
  }

  final patrones = <RegExp>[
    RegExp('municipio\\s+de\\s+($_cap$_cuerpo$_continuacion)\\s*$_parada',
        caseSensitive: false),
    RegExp('(?:ciudad|localidad|pueblo|comunidad)\\s+de\\s+'
        '($_cap$_cuerpo$_continuacion)\\s*$_parada', caseSensitive: false),
    RegExp('municipio\\s+($_cap$_cuerpo)\\s*$_parada', caseSensitive: false),
  ];
  for (final re in patrones) {
    final m = re.firstMatch(t);
    if (m == null) continue;
    final nombre = m.group(1)!.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (nombre.length < 3) continue;
    if (_aliasDep.values.any((d) => d.toLowerCase() == nombre.toLowerCase())) {
      continue;
    }
    final ini = m.start + m.group(0)!.indexOf(nombre);
    p.municipio =
        _sinPuntuacionFinal(_capitalizar(literal(original, ini, ini + nombre.length)));
    break;
  }

  final tel = RegExp(
    r'(?:tel[ée]fono|celular|whatsapp|contacto|n[uú]mero)\s*(?:es|:)?\s*'
    r'(\+?\d[\d\s-]{6,15}\d)',
    caseSensitive: false,
  ).firstMatch(t);
  if (tel != null) {
    final digitos = tel.group(1)!.replaceAll(RegExp(r'\D'), '');
    if (digitos.length >= 7 && digitos.length <= 15) p.telefono = digitos;
  }
}

// ---------------------------------------------------------------------------
// Comunidades
// ---------------------------------------------------------------------------

const List<String> _tiposLugar = [
  'comunidad', 'localidad', 'localidades', 'barrio', 'barrios', 'pueblo',
  'pueblos', 'colonia', 'sector', 'aldea', 'municipio',
];
const Set<String> _noLugar = {
  'que', 'una', 'uno', 'un', 'la', 'el', 'los', 'las', 'de', 'del', 'se',
  'hubo', 'tuvo', 'donde', 'cuanto', 'cuantos',
};

List<String> _detectarComunidades(
    String t, String original, List<String> excluir) {
  final nombres = <String>[];
  final excluidos = excluir.map((x) => sinTilde(x).toLowerCase()).toSet();

  void agregar(String bruto, int? ini) {
    final n = bruto.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (n.length < 4 || n.length > 45) return;
    if (_noLugar.contains(sinTilde(n).toLowerCase())) return;
    if (RegExp(r'^\d').hasMatch(n)) return;
    // El municipio no es una comunidad afectada: "municipio de Yapacaní" no debe
    // aparecer dos veces en la ficha.
    if (excluidos.contains(sinTilde(n).toLowerCase())) return;
    if (excluidos.contains(sinTilde(n).split(' ').last.toLowerCase())) return;
    final conTilde = ini != null
        ? literal(original, ini, ini + bruto.length)
            .trim()
            .replaceAll(RegExp(r'\s+'), ' ')
        : n;
    final cap = capitalizarLugar(_sinPuntuacionFinal(conTilde.isEmpty ? n : conTilde));
    if (cap.isEmpty) return;
    if (!nombres.any((x) => x.toLowerCase() == cap.toLowerCase())) {
      nombres.add(cap);
    }
  }

  for (final tipo in _tiposLugar) {
    final rx = RegExp(
      '$tipo\\s+(?:de\\s+|del\\s+)?($_cap$_cuerpo'
      r'(?:\s+(?:de|del|la|el|los|y|Villa|Pueblo|Nuevo|Nueva|Santa|San|'
      r'San Pedro|San Juan|[A-ZÁÉÍÓÚÑ][\w.-]*)){0,3})\s*'
      '$_parada',
      caseSensitive: false,
    );
    for (final m in rx.allMatches(t)) {
      agregar(m.group(1)!, m.start + m.group(0)!.indexOf(m.group(1)!));
      if (nombres.length >= 15) break;
    }
    if (nombres.length >= 15) break;
  }

  // Localidades sueltas tras "comunidades:" o separadas por "y".
  final lista = RegExp(
    r'comunidades?\s*(?:de|:)\s*([A-Za-zÁÉÍÓÚÑáéíóúñ,\s]{6,120})',
    caseSensitive: false,
  ).firstMatch(t);
  if (lista != null) {
    final cuerpo = lista.group(1)!;
    for (final parte in cuerpo.split(RegExp(r',|\sy\s'))) {
      agregar(parte, lista.start + lista.group(0)!.length - cuerpo.length +
          cuerpo.indexOf(parte));
    }
  }
  return nombres.take(15).toList();
}

// ---------------------------------------------------------------------------
// Necesidades humanitarias
// ---------------------------------------------------------------------------

const Map<String, List<String>> _aliasNecesidad = {
  'Alimentos': [
    'alimento', 'alimentos', 'comida', 'viandas', 'racion', 'raciones',
    'mercado',
  ],
  'Refugio y Vivienda': [
    'refugio', 'alojamiento', 'alojamientos', 'carpa', 'carpas', 'abrigo',
    'techo', 'techos',
  ],
  'Ropa de Cama': [
    'ropa de cama', 'camas', 'colchon', 'colchones', 'frazada', 'frazadas',
    'manta', 'mantas', 'sabana', 'sabanas',
  ],
  'Artículos de Higiene': [
    'higiene', 'jabon', 'cepillo', 'cepillos', 'toalla', 'toallas',
    'desinfectante', 'lavamanos', 'papel higienico',
  ],
  'Artículos de Cocina': [
    'articulos de cocina', 'cocina', 'utensilios', 'olla', 'ollas', 'vajilla',
    'hornilla',
  ],
  'Tanques de Agua': [
    'tanque de agua', 'tanques de agua', 'tanque', 'tanques',
    'almacenamiento de agua',
  ],
  'Pastillas Potabilizadoras': [
    'pastilla', 'pastillas', 'potabilizadora', 'potabilizadoras', 'cloro',
    'purificar el agua',
  ],
  'Filtros Vela': [
    'filtro vela', 'filtros', 'filtro', 'vela', 'candela', 'velas',
  ],
  'Politubos': ['politubo', 'politubos', 'manguera', 'mangueras'],
  'Carro Cisterna': [
    'cisterna', 'cisternas', 'camion cisterna', 'camion cisterna',
  ],
};

Map<String, bool> _detectarNecesidades(String t) {
  final cambios = <String, bool>{};
  for (final item in _aliasNecesidad.keys) {
    if (_coincide(t, _aliasNecesidad[item]!)) cambios[item] = true;
  }
  return cambios;
}

// ---------------------------------------------------------------------------
// Infraestructura vial
// ---------------------------------------------------------------------------

const List<String> _vias = [
  'puente', 'puentes', 'via', 'vias', 'carretera', 'carreteras', 'camino',
  'caminos', 'calle', 'callej',
];
const List<String> _danos = [
  'danad', 'dan', 'cortad', 'cort', 'afectad', 'destruid', 'inutil', 'perd',
  'arrasad', 'arrancad', 'socav',
];

List<BchDanoVial> _detectarInfraVial(String t, String original) {
  final filas = <BchDanoVial>[];
  final rx = RegExp('(?<![a-z0-9])(${_vias.join('|')})[a-z0-9]*',
      caseSensitive: false);
  for (final m in rx.allMatches(t)) {
    final ventana = t.substring(m.start, (m.start + 140).clamp(0, t.length));
    final kwsDano = _posicionesPalabras(ventana, _danos);
    if (kwsDano.isEmpty) continue;
    _Cifra? km;
    for (final c in _cifras(ventana)) {
      if ((c.ini - kwsDano.first.ini).abs() < 80) {
        km = c;
        break;
      }
    }
    if (km == null) continue;
    final nombre = _nombreDeVia(ventana, m.group(0)!, original, m.start);
    if (filas.any((f) =>
        f.via.isNotEmpty &&
        nombre.isNotEmpty &&
        f.via.toLowerCase() == nombre.toLowerCase())) {
      continue;
    }
    filas.add(BchDanoVial(
      via: nombre,
      danoTotal: '${km.n}',
      origen: EdanOrigen.voz,
    ));
    if (filas.length >= 10) break;
  }
  return filas;
}

/// Nombre propio del puente. Acepta el nombre que sigue ("Puente San Pedro"),
/// el que lo precede ("río Yapacaní") y el que va con conectores en minúscula
/// ("puente sobre el río Yapacaní"), que antes cortaba la extracción.
///
/// Devuelve el texto con sus tildes originales: el patrón corre sobre el texto
/// normalizado, pero se recorta con `literal` sobre el original.
String _nombreDeVia(String ventana, String sustantivo, String original,
    int offsetVentana) {
  final idx = ventana.toLowerCase().indexOf(sustantivo.toLowerCase());
  if (idx < 0) return '';
  final desde = idx + sustantivo.length;
  final despues = ventana.substring(desde, (desde + 45).clamp(0, ventana.length));

  final reDespues = RegExp(
    r'^\s+(?:de\s+|del\s+|sobre\s+|en\s+el\s+|en\s+la\s+)?'
    '($_capMay$_cuerpo(?:\\s+$_capMay$_cuerpo)?)',
  ).firstMatch(despues);
  if (reDespues != null) {
    return capitalizarLugar(
        _recortaConTildes(original, offsetVentana + desde, reDespues, despues));
  }

  // "puente sobre el río Yapacaní": el nombre viene con un sustantivo geográfico.
  final reRio = RegExp(
    '(?:^|\\s)(?:de\\s+|del\\s+|sobre\\s+|en\\s+el\\s+|en\\s+la\\s+)?'
    '((?:el\\s+|la\\s+)?(?:río|quebrada|rio)\\s+$_capMay$_cuerpo)',
  ).firstMatch(despues);
  if (reRio != null) {
    return capitalizarLugar(
        _recortaConTildes(original, offsetVentana + desde, reRio, despues));
  }

  final antes = ventana.substring(
      idx < 45 ? 0 : idx - 45, idx);
  final reAntes = RegExp('($_capMay$_cuerpo(?:\\s+$_capMay$_cuerpo)?)\\s*\$')
      .firstMatch(antes);
  if (reAntes != null) {
    return capitalizarLugar(
        _recortaConTildes(original, offsetVentana, reAntes, antes));
  }
  return '';
}

/// Recorta el grupo capturado y recupera el texto original con tildes.
String _recortaConTildes(
        String original, int baseVentana, RegExpMatch m, String fuente) {
  final grupo = m.group(1)!;
  final ini = m.start + m.group(0)!.indexOf(grupo);
  final conTilde =
      literal(original, baseVentana + ini, baseVentana + ini + grupo.length);
  return _sinPuntuacionFinal((conTilde.isEmpty
          ? fuente.substring(ini, ini + grupo.length)
          : conTilde)
      .trim()
      .replaceAll(RegExp(r'\s+'), ' '));
}

// ---------------------------------------------------------------------------
// Agropecuario
// ---------------------------------------------------------------------------

const List<String> _cultivos = [
  'maiz', 'maicillo', 'papa', 'trigo', 'arroz', 'soja', 'soya', 'girasol',
  'canola', 'cebolla', 'tomate', 'mani', 'guiso', 'haba', 'arveja', 'quinua',
  'avena', 'cebada', 'pasto', 'pastos', 'algodon', 'cafe', 'cacao', 'vinedo',
  'vid', 'cana', 'banano', 'naranja', 'mango', 'durazno', 'pacay',
  'tornabia', 'amaranto',
];

List<BchAgricultura> _detectarAgricultura(String t, String original) {
  final filas = <BchAgricultura>[];
  final rx = RegExp(
    r'(?<![a-z0-9])(\d{1,3}(?:[.,]\d{3})*|\d+)\s*'
    r'(?:ha|h[eé]ctareas?|hectares|hectárea|hectáreas)(?![a-z0-9])',
    caseSensitive: false,
  );
  for (final m in rx.allMatches(t)) {
    // Dos ventanas con propósito distinto. El cultivo se busca SOLO hacia
    // adelante: si esa ventana mirara hacia atrás, en "120 ha de maíz y 40 ha de
    // papa" la segunda cifra también saldría como Maíz. La pérdida total sí
    // necesita contexto previo, porque en "se perdieron 80 ha de soya" la
    // palabra va delante del número.
    final ventana = t.substring(m.start, (m.start + 120).clamp(0, t.length));
    final iniLarga = m.start < 60 ? 0 : m.start - 60;
    final ventanaLarga =
        t.substring(iniLarga, (m.start + 120).clamp(0, t.length));
    final cult = _cultivos.firstWhere(
      (c) => _coincide(ventana, [c]),
      orElse: () => '',
    );
    if (cult.isEmpty) continue;
    final kCult = _posicionesPalabras(ventana, [cult]).first;
    final cultTilde = literal(original, m.start + kCult.ini, m.start + kCult.fin);
    final has = aInt(m.group(1));
    if (has == null) continue;
    final perdidos = _posicionesPalabras(
      ventanaLarga,
      ['perd', 'destruid', 'arrasad', 'arrancad', 'no quedo', 'no quedo nada'],
    ).isNotEmpty;
    filas.add(BchAgricultura(
      cultivo: _capitalizar(cultTilde.isEmpty ? cult : cultTilde),
      hasAfectadas: has,
      hasPerdidas: perdidos ? has : null,
      origen: EdanOrigen.voz,
    ));
    if (filas.length >= 10) break;
  }
  return filas;
}

/// Se detectan por tallo una sola vez: iterar singular y plural por separado
/// generaba la misma fila dos veces ("Vaca" y "Vacas"). Se conserva la palabra
/// tal como la dijo la persona.
const List<String> _tallosPecuario = [
  'vaca', 'ganado', 'bovino', 'borrego', 'oveja', 'cabra', 'cerdo', 'pollo',
  'gallo', 'gallina', 'ave', 'alpaca', 'llama', 'caballo', 'cuy', 'conejo',
  'pato', 'codorniz', 'toro', 'vaca lechera',
];

List<BchPecuario> _detectarPecuario(String t) {
  final filas = <BchPecuario>[];
  final vistos = <String>{};
  String alternativa(String tallo) => tallo == 'ave' ? 'aves' : '${tallo}e?s?';
  final rx = RegExp(
    '(?<![a-z0-9])(${_tallosPecuario.map(alternativa).join('|')})(?![a-z0-9])',
    caseSensitive: false,
  );
  for (final m in rx.allMatches(t)) {
    final palabra = m.group(1)!;
    final bajo = palabra.toLowerCase();
    String? tallo;
    for (final c in _tallosPecuario) {
      if (c.length >= 3 && bajo.startsWith(c.substring(0, 3))) {
        tallo = c;
        break;
      }
    }
    if (tallo == null || !vistos.add(tallo)) continue;

    final iniVentana = m.start < 50 ? 0 : m.start - 50;
    final ventana = t.substring(iniVentana, (m.start + 60).clamp(0, t.length));
    final referencia = m.start - iniVentana;
    final cantidades = _cifras(ventana)
        .map((c) => _Cifra(c.n, (c.ini - referencia).abs(), c.fin))
        .where((c) => c.ini <= 45)
        .toList()
      ..sort((a, b) => a.ini.compareTo(b.ini));
    if (cantidades.isEmpty) continue;
    final cantidad = cantidades.first.n;

    final muertos = _coincide(ventana, [
      'murio', 'murieron', 'muerto', 'muerta', 'muerte', 'falleci',
      'fallecieron', 'perdieron', 'no sobrevivieron',
    ]);
    // Nota: en la referencia también se calcula `afectados`, pero la condición
    // `afectados || !muertos` es siempre cierta cuando `muertos` es falso, así
    // que no influía en el resultado. Aquí queda el caso útil: si hubo muertes
    // en la zona, la cifra es de muertos; si no, de afectados.

    filas.add(BchPecuario(
      especie: _capitalizar(palabra),
      animalesAfectados: muertos ? null : aInt(cantidad),
      animalesMuertos: muertos ? aInt(cantidad) : null,
      origen: EdanOrigen.voz,
    ));
    if (filas.length >= 10) break;
  }
  return filas;
}

// ---------------------------------------------------------------------------
// Educación y salud
// ---------------------------------------------------------------------------

const List<String> _sustEducacion = [
  'escuela', 'escuelas', 'colegio', 'colegios', 'unidad educativa',
  'unidades educativas', 'escuelita', 'preescolar', 'instituto',
];
const List<String> _sustSalud = [
  'hospital', 'hospitales', 'centro de salud', 'centros de salud', 'posta',
  'postas', 'clinica', 'puesto de salud', 'sanatorio',
];

/// Fila de establecimiento dañado,Detectada por sustantivo.
List<T> _detectarDaniosPorSustantivo<T>(
  String t,
  String original,
  List<String> sustantivos,
  T Function(String nombre) construir, {
  int limite = 10,
}) {
  final filas = <T>[];
  final nombres = <String>[];
  for (final sust in sustantivos) {
    final rx = RegExp('(?<![a-z0-9])${RegExp.escape(sust)}[a-z0-9]*',
        caseSensitive: false);
    for (final m in rx.allMatches(t)) {
      final ventana = t.substring(m.start, (m.start + 150).clamp(0, t.length));
      if (!_coincide(ventana, [
        'afect', 'dan', 'sufri', 'perdi', 'destruid', 'inutil', 'cortad',
        'danad',
      ])) {
        continue;
      }
      final nombre = _nombrePropioEn(ventana, m.group(0)!, original, m.start);
      if (nombre.isEmpty) continue;
      if (nombres.any((x) => x.toLowerCase() == nombre.toLowerCase())) continue;
      nombres.add(nombre);
      filas.add(construir(nombre));
      if (filas.length >= limite) return filas;
    }
  }
  return filas;
}

/// Nombre propio del establecimiento ("Hospital San José", "Escuela Juan
/// Montalvo"). Devuelve el texto original con tildes.
String _nombrePropioEn(
    String ventana, String sustantivo, String original, int base) {
  final idx = ventana.toLowerCase().indexOf(sustantivo.toLowerCase());
  if (idx < 0) return '';
  final desde = idx + sustantivo.length;
  final despues = ventana.substring(desde, (desde + 45).clamp(0, ventana.length));
  final m = RegExp(
    r'^\s*(?:de\s+|del\s+|la\s+|el\s+|los\s+|las\s+)?'
    '($_capMay$_cuerpo(?:\\s+(?:de|del|de\\s+la|de\\s+el|$_capMay$_cuerpo)){0,3})',
  ).firstMatch(despues);
  if (m == null) return '';
  final n = m.group(1)!.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (n.length < 3 ||
      _noLugar.contains(sinTilde(n.split(' ').first).toLowerCase())) {
    return '';
  }
  final ini = base + desde + m.group(0)!.indexOf(m.group(1)!);
  final conTilde = literal(original, ini, ini + m.group(1)!.length);
  return capitalizarLugar(
      _sinPuntuacionFinal(conTilde.isEmpty ? m.group(1)! : conTilde));
}

// ---------------------------------------------------------------------------
// Protección
// ---------------------------------------------------------------------------

const Map<String, List<String>> _gruposVulnerables = {
  'Niñas y Niños': [
    'nino', 'nina', 'ninos', 'ninas', 'infante', 'infantes', 'menor',
    'menores', 'crianza',
  ],
  'Adolescentes': ['adolescente', 'adolescentes'],
  'Mujeres Lactantes': [
    'lactante', 'lactantes', 'amamantando', 'lactancia',
  ],
  'Mujeres Embarazadas': [
    'embarazada', 'embarazadas', 'gestante', 'gestantes',
  ],
  'Adultos Mayores': [
    'anciano', 'anciana', 'ancianos', 'ancianas', 'abuelo', 'abuela',
    'mayor', 'mayores',
  ],
  'Personas con Discapacidad': [
    'discapacidad', 'discapacitado', 'discapacitada', 'discapacitados',
  ],
};

const List<String> _muertes = [
  'murio', 'murieron', 'muerto', 'muerta', 'fallecio', 'fallecieron',
  'fallecido', 'fallecida', 'sin vida',
];

/// Palabras que revelan el sexo del grupo. SQLite separa `mujeres`/`hombres`,
/// así que "40 mujeres" no puede acabar en un total sin desglose.
const List<String> _femenino = [
  'mujeres', 'mujer', 'ninas', 'niña', 'lactantes', 'embarazadas', 'gestantes',
];

const List<String> _masculino = [
  'hombres', 'hombre', 'ninos', 'niño', 'varones', 'masculinos',
];

Map<String, BchProteccionFila> _detectarProteccion(String t) {
  final salida = <String, BchProteccionFila>{};
  for (final e in _gruposVulnerables.entries) {
    final v = aInt(_cifraConContexto(t, [e.value], ventana: 30));
    if (v == null) continue;
    final ventana = _ventanaAlrededorDeCifra(t, v);
    // Se descarta la cifra si cerca hay una palabra de muerte: "murieron 3
    // niños" es impacto en población, no 3 niños sobrevivientes en protección.
    if (_coincide(ventana, _muertes)) continue;

    final sexo = _sexoDeCifra(t, v);
    salida[e.key] = BchProteccionFila(
      e.key,
      total: v,
      mujeres: sexo == true ? v : null,
      hombres: sexo == false ? v : null,
    );
  }
  return salida;
}

/// Sexo de la cifra [n]: `true` mujeres, `false` hombres, `null` si no se puede
/// determinar.
///
/// Busca la palabra de sexo MÁS CERCANA a la cifra, no la primera que encuentre
/// en una ventana ancha. Con "40 niños, 25 adolescentes y 10 mujeres
/// embarrass" una ventana de 75 caracteres alrededor del 10 include "niños" y
/// la frase queda sin desglose; con el radio corto solo cuenta "mujeres".
/// Empate o ausencia de dato => `null` (la traducción no repartirá el total).
bool? _sexoDeCifra(String t, int n, {int radio = 20}) {
  _Cifra? c;
  for (final x in _cifras(t)) {
    if (x.n == n) {
      c = x;
      break;
    }
  }
  if (c == null) return null;

  int? dF, dM;
  for (final p in _posicionesPalabras(t, _femenino)) {
    final d = (p.ini - c.fin).abs();
    if (d <= radio && (dF == null || d < dF)) dF = d;
  }
  for (final p in _posicionesPalabras(t, _masculino)) {
    final d = (p.ini - c.fin).abs();
    if (d <= radio && (dM == null || d < dM)) dM = d;
  }
  if (dF == null && dM == null) return null;
  if (dF != null && dM != null && dF == dM) return null;
  return dF != null && (dM == null || dF < dM);
}

/// Texto alrededor de la primera aparición de la cifra [n], para buscar pistas
/// de contexto (sexo, muerte) sin repetir el cálculo en cada detector.
String _ventanaAlrededorDeCifra(String t, int n) {
  for (final c in _cifras(t)) {
    if (c.n != n) continue;
    final ini = c.ini < 30 ? 0 : c.ini - 30;
    final fin = (c.ini + 45).clamp(0, t.length);
    return t.substring(ini, fin);
  }
  return '';
}

// ---------------------------------------------------------------------------
// Servicios básicos
// ---------------------------------------------------------------------------

/// Frases que indican que un servicio quedó interrumpido. Sin esto la sección
/// quedaba vacía aunque la persona contara "quedó sin agua".
const Map<String, List<String>> _caidaServicioFalla = {
  'agua': [
    'sin agua', 'se corto el agua', 'se fue el agua', 'no hay agua',
    'sin agua potable', 'perdieron el agua',
  ],
  'luz': [
    'sin luz', 'sin energia', 'sin electricidad', 'se corto la luz',
    'se fue la luz', 'no hay luz', 'apago',
  ],
  'gas': ['sin gas', 'se corto el gas', 'fuga de gas', 'no hay gas'],
  'telecom': [
    'sin telefono', 'sin internet', 'sin senal', 'sin cobertura',
    'no hay senal', 'se corto el internet',
  ],
  'alcantarillado': [
    'sin alcantarillado', 'alcantarillado dañ', 'alcantarillo roto',
    'cloaca rota', 'sin cloaca',
  ],
};

/// Daño con el que se registra la caída. El alcance difiere: un corte total de
/// agua es "Total", pero un alcantarillado dañado se anota como "Parcial".
const Map<String, String> _caidaServicioDano = {
  'agua': 'Total',
  'luz': 'Total',
  'gas': 'Total',
  'telecom': 'Total',
  'alcantarillado': 'Parcial',
};

void _detectarServicios(String t, EdanParche p) {
  for (final e in _caidaServicioFalla.entries) {
    if (!_coincide(t, e.value)) continue;
    p.serviciosBasicos[e.key] = {
      'danoTotal': _caidaServicioDano[e.key],
      'observaciones': 'Reportado sin servicio',
    };
  }
}

// ---------------------------------------------------------------------------
// API principal
// ---------------------------------------------------------------------------

/// Extrae un [EdanParche] con lo que el texto dice explícitamente.
///
/// [actual] es el borrador en curso: solo se usa para decidir en qué grupo etario
/// va un "desaparecidos" sin grupo explícito, igual que en la referencia.
EdanParche extraer(String texto, [EdanBorradorIa? actual]) {
  final parche = EdanParche();
  if (texto.trim().isEmpty) return parche;

  final original = texto;
  final t = sinTilde(original);

  _detectarUbicacion(t, original, parche);
  _detectarFechas(t, parche);

  parche.tipoEvento.addAll(_detectarEventos(t));
  _detectarPoblacion(t, parche);
  _detectarVivienda(t, parche);

  final impacto = _detectarImpactoPoblacion(t);
  if (impacto.isNotEmpty) {
    // Sin grupo explícito, los desaparecidos van al primer grupo que aún no
    // tenga desaparecidos anotados.
    var idxDesaparecidos = 0;
    for (var i = 0; i < (actual?.impactoPoblacion.length ?? 0); i++) {
      if (actual!.impactoPoblacion[i].desaparecidos == null) {
        idxDesaparecidos = i;
        break;
      }
    }
    for (final hit in impacto) {
      final grupo = kEdanGruposEdad[hit.indice ?? idxDesaparecidos];
      parche.impactoPoblacion.putIfAbsent(grupo, () => {})[hit.campo] =
          hit.valor;
    }
  }

  parche.proteccion.addAll(_detectarProteccion(t));
  _detectarServicios(t, parche);

  final vial = _detectarInfraVial(t, original);
  if (vial.isNotEmpty) parche.infraVial = vial;

  final agri = _detectarAgricultura(t, original);
  if (agri.isNotEmpty) parche.agricultura = agri;

  final pec = _detectarPecuario(t);
  if (pec.isNotEmpty) parche.pecuario = pec;

  final edu = _detectarDaniosPorSustantivo(
      t, original, _sustEducacion, (n) => BchUnidadEducativa(establecimiento: n));
  if (edu.isNotEmpty) parche.educacion = edu;

  final salud = _detectarDaniosPorSustantivo(
      t, original, _sustSalud, (n) => BchEstablecimientoSalud(establecimiento: n));
  if (salud.isNotEmpty) parche.saludDanios = salud;

  final coms = _detectarComunidades(
      t, original, [if (parche.municipio != null) parche.municipio!]);
  if (coms.isNotEmpty) {
    parche.comunidades = [for (final n in coms) BchComunidad(nombre: n)];
  }

  final nec = _detectarNecesidades(t);
  for (final e in nec.entries) {
    parche.necesidadesHumanitarias[e.key] = e.value;
  }

  return parche;
}

/// ¿El texto contiene algo que valga la pena seguir preguntando?
bool tieneDatoReconocible(String texto) => !extraer(texto).vacio;
