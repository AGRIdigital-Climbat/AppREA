/// Separación de lo que escribe el modelo en tres canales.
///
/// El contrato del puente le pide al modelo un objeto con tres campos:
/// `respuesta` (la frase para la persona), `siguiente_pregunta` (la próxima
/// pregunta) y `parche` (los datos para la ficha). El chat solo puede ver el
/// primero.
///
/// El bug que motivó este módulo era de arquitectura y no de filtro: el
/// provider acumulaba los tokens del canal de texto en un solo buffer y
/// pintaba ese buffer entero como si fuera prosa. Como el modelo a veces
/// escribía el JSON ahí, en el chat aparecía el objeto completo:
///
/// ```json
/// {"respuesta":"Se registró una granizada muy fuerte.",
///  "siguiente_pregunta":null,
///  "parche":{"tipoEvento":{"granizada":true}}}
/// ```
///
/// La respuesta entonces no era "quitarle las llaves", sino **separar los
/// canales**: decodificar el envoltorio y llevar cada campo a su destino.
/// Este módulo hace eso y además garantiza, por construcción y como última
/// red, que la frase que sale nunca contenga estructura.
///
/// Hay dos entradas porque hay dos situaciones reales:
///
/// * [decodificarSalida] cuando hay texto completo (turno terminado).
/// * [edanRespuestaEnCurso] mientras se está escribiendo, donde el JSON todavía
///   no se puede parsear pero el campo `respuesta` ya puede estar cerrado.
library;

import 'dart:convert';

/// El resultado de separar lo que escribió el modelo.
///
/// Los tres canales ya no se mezclan: `respuesta` es lo que se muestra y se
/// dice, `parche` se aplica al borrador y `siguiente_pregunta` se le pregunta
/// a la persona.
class EdanSalida {
  /// La frase para la persona. **Nunca** contiene JSON: eso lo garantiza
  /// [decodificarSalida] en cada camino y [edanProsaVisible] al final.
  final String respuesta;

  /// La próxima pregunta, ya separada de la frase. `null` si el modelo no
  /// mandó ninguna.
  final String? siguientePregunta;

  /// Los datos para la ficha, ya separados. Vacío si no vino nada.
  final Map<String, dynamic> parche;

  /// `true` si había un envoltorio JSON que se pudo decodificar.
  final bool vinoJson;

  /// `true` si había JSON pero no se pudo decodificar.
  ///
  /// Es distinto de "no había JSON": significa que el contrato se rompió, y la
  /// UI puede ofrecer repetir.
  final bool contratoRoto;

  const EdanSalida({
    this.respuesta = '',
    this.siguientePregunta,
    this.parche = const {},
    this.vinoJson = false,
    this.contratoRoto = false,
  });

  const EdanSalida.vacia() : this();

  bool get parcheVacio => parche.isEmpty;

  bool get preguntaVacia =>
      siguientePregunta == null || siguientePregunta!.trim().isEmpty;

  @override
  String toString() => 'EdanSalida(respuesta: $respuesta, '
      'pregunta: $siguientePregunta, parche: $parche, '
      'json: $vinoJson, roto: $contratoRoto)';
}

/// Claves que identifican un envoltorio del contrato.
const _clavesDeContrato = {'respuesta', 'parche', 'siguiente_pregunta'};

/// Claves con las que algunos modelos contestan el mismo contrato en inglés.
///
/// No es hipotético: medido contra el puente en vivo, `nemotron-3-ultra-550b`
/// devuelve el objeto correcto pero con la clave `response` en vez de
/// `respuesta`, y `gpt-oss-20b` devuelve la clave que se le ocurra. Con el
/// contrato estricto, el Nemotron —el único modelo grande que hay— perdía la
/// respuesta entera y el turno llegaba vacío a la persona.
///
/// Con esto la misma respuesta se acepta tal cual, sin pedirle al modelo que
/// cambie su inglés: la traducción es nuestra, del lado del contrato.
const _aliasDeClave = <String, String>{
  'response': 'respuesta',
  'answer': 'respuesta',
  'reply': 'respuesta',
  'next_question': 'siguiente_pregunta',
  'next_question_to_ask': 'siguiente_pregunta',
  'siguiente_question': 'siguiente_pregunta',
  'patch': 'parche',
  'patches': 'parche',
};

/// Pasa los alias a las claves del contrato, sin pisar lo que ya venía bien.
///
/// Si el modelo mandó `respuesta` y además `response`, gana `respuesta`: el
/// contrato es el que manda.
Map<String, dynamic> _normalizarClaves(Map<String, dynamic> mapa) {
  if (!mapa.keys.any(_aliasDeClave.containsKey)) return mapa;
  final out = <String, dynamic>{...mapa};
  for (final alias in _aliasDeClave.entries) {
    if (out[alias.value] == null && out[alias.key] != null) {
      out[alias.value] = out.remove(alias.key);
    }
  }
  return out;
}

/// Separa [crudo] en sus tres canales.
///
/// [envoltorio] es el mapa que el puente ya decodificó (`res.json`). Si viene,
/// manda: es el contrato tal cual lo entendió el transporte y no hace falta
/// reparsear. Solo se usa si efectivamente es del contrato; si no, se ignora y
/// se decodifica [crudo] igual que siempre.
///
/// Casos que cubre, en orden:
///
/// 1. **Envoltorio ya separado**: el camino normal, cuando el puente parseó.
/// 2. **JSON completo en el texto**: se decodifica y cada campo va a su lado.
/// 3. **Prosa con objetos adentro**: se sacan los objetos, se intenta
///    decodificar cada uno, y lo que queda afuera es prosa. Un objeto que no
///    es del contrato se descarta como ruido, nunca se pinta.
/// 4. **Solo prosa**: devuelve la frase tal cual (filtrada).
/// 5. **JSON que no parsea**: marca `contratoRoto` y devuelve la prosa que se
///    pudo rescatar alrededor.
EdanSalida decodificarSalida(String crudo, {Map<String, dynamic>? envoltorio}) {
  final t = crudo.trim();

  // 1. El puente ya separó: se respeta tal cual.
  if (envoltorio != null && _esDelContrato(envoltorio)) {
    return _desdeEnvoltorio(envoltorio, prosaAlrededor: t);
  }

  if (t.isEmpty) return const EdanSalida.vacia();

  // 2. El texto entero es el envoltorio.
  final entero = _comoMapa(t);
  if (entero != null && _esDelContrato(entero)) {
    return _desdeEnvoltorio(entero, prosaAlrededor: '');
  }

  // 3. Prosa y objetos mezclados: se separan los dos tipos de contenido.
  final separado = _separarProsaYJson(t);

  if (separado.envoltorio != null) {
    return _desdeEnvoltorio(separado.envoltorio!, prosaAlrededor: separado.prosa);
  }

  // 3. No había envoltorio: todo es prosa (y cualquier objeto ruidoso ya se
  //    descartó al separar).
  final prosa = edanProsaVisible(separado.prosa);
  return EdanSalida(
    respuesta: prosa,
    vinoJson: separado.huboJson,
    contratoRoto: separado.huboJson,
  );
}

/// Lo que se muestra mientras el modelo todavía escribe [parcial].
///
/// Es la misma separación aplicada a un texto incompleto. Un JSON a medio
/// escribir no se puede decodificar, pero el campo `respuesta` sí: el modelo
/// lo escribe primero, así que aparece en pantalla apenas se cierra la comilla
/// y sin que las llaves del envoltorio lleguen a verse nunca.
///
/// Si lo que se está escribiendo es prosa de verdad, se muestra tal cual.
String edanRespuestaEnCurso(String parcial) {
  final t = parcial.trimLeft();
  if (t.isEmpty) return '';

  final arrancaEstructural = t.startsWith('{') ||
      t.startsWith('[') ||
      t.startsWith('```');
  if (!arrancaEstructural) return edanProsaVisible(t);

  final respuesta = _leerCampoTexto(t, 'respuesta') ??
      _leerPrimerAlias(t, 'respuesta');
  if (respuesta == null) return '';
  return edanProsaVisible(respuesta);
}

/// La pregunta del envoltorio, aplicada a texto en curso o completo.
///
/// Igual que arriba: sirve para no perderla si llega en el canal de texto.
String? edanPreguntaEnCurso(String crudo) {
  final t = crudo.trim();
  if (t.isEmpty) return null;
  final v = _leerCampoTexto(t, 'siguiente_pregunta') ??
      _leerPrimerAlias(t, 'siguiente_pregunta');
  if (v == null || v.trim().isEmpty) return null;
  return v.trim();
}

/// Primer alias presente en el texto, para el streaming.
///
/// ElNemotron escribe `response`, no `respuesta`; sin esto, durante el
/// streaming no se vería nada hasta el final.
String? _leerPrimerAlias(String texto, String campoDelContrato) {
  for (final alias in _aliasDeClave.entries) {
    if (alias.value != campoDelContrato) continue;
    final v = _leerCampoTexto(texto, alias.key);
    if (v != null) return v;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Garantía final de prosa
// ---------------------------------------------------------------------------

/// Filtra [crudo] y devuelve solo texto que se puede mostrar.
///
/// Es la red de seguridad de este módulo: aunque los pasos de separación no
/// agarren algo, acá no sale estructura. Devuelve `''` si no queda nada
/// utilizable, nunca JSON.
///
/// No toca la prosa de verdad, porque eso importa por dos motivos: la voz no
/// puede leerle un JSON a la persona, y el provider compara las frases fijas
/// (`_cierreFotos`, el saludo) por igualdad.
String edanProsaVisible(String crudo) {
  var t = crudo;
  if (t.trim().isEmpty) return '';

  // Bloques cercados. El primero los saca completos; el segundo cubre uno
  // que se abrió y no se cerró (el modelo se quedó sin tokens).
  t = t.replaceAll(RegExp(r'```[\s\S]*?```'), '\n');
  t = t.replaceAll(RegExp(r'```[\s\S]*'), '\n');

  // Objetos y arreglos balanceados.
  t = _sinBalanceados(t);

  // Una llave sin cerrar es un volcado incompleto: no hay prosa que valga
  // después. Se corta, no se "corrige": si había frase antes, se conserva.
  final cola = _indiceDeAbiertaSinCerrar(t);
  if (cola != null) t = t.substring(0, cola);

  // Fragmentos de clave sueltos que quedaron fuera de cualquier objeto.
  t = t.replaceAll(_claveValorSuelto, '');
  t = t.replaceAll(_parcheSuelto, '');

  // Líneas que son pura estructura.
  final lineas = t
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !_esLineaDeEstructura(l))
      .toList();
  t = lineas.join(' ');

  // Red de seguridad.
  if (_pareceEstructura(t)) return '';

  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

// ---------------------------------------------------------------------------
// Separación de prosa y objetos
// ---------------------------------------------------------------------------

class _Separado {
  /// La prosa que quedó fuera de los objetos.
  final String prosa;

  /// El primer objeto que era un envoltorio del contrato, ya decodificado.
  final Map<String, dynamic>? envoltorio;

  /// `true` si había algún objeto, aunque no se haya podido decodificar.
  final bool huboJson;

  const _Separado(this.prosa, this.envoltorio, this.huboJson);
}

/// Recorre [texto] separando prosa de objetos JSON.
///
/// Cada `{...}` balanceado se intenta decodificar: si es un envoltorio se
/// guarda (el primero manda), y si no se descarta entero como ruido. Eso es lo
/// que hace que un objeto suelto nunca termine en la pantalla: no se "filtra",
/// se saca del canal de prosa por estar en el canal equivocado.
_Separado _separarProsaYJson(String texto) {
  final prosa = StringBuffer();
  Map<String, dynamic>? envoltorio;
  var huboJson = false;

  var i = 0;
  while (i < texto.length) {
    final c = texto.codeUnitAt(i);
    if (c != 0x7B && c != 0x5B) {
      prosa.write(texto[i]);
      i++;
      continue;
    }

    final fin = _buscarCierre(texto, i);
    if (fin == null) {
      // Objeto sin cerrar: hasta acá llega lo que se pueda leer.
      huboJson = true;
      break;
    }

    huboJson = true;
    final candidato = texto.substring(i, fin + 1);
    final mapa = _comoMapa(candidato);
    if (mapa != null && envoltorio == null && _esDelContrato(mapa)) {
      envoltorio = mapa;
    }
    // Tanto si se decodificó como si no, se queda fuera de la prosa.
    i = fin + 1;
  }

  // Si había un envoltorio, la prosa que queda alrededor puede ser eco del
  // propio `respuesta`; eso lo resuelve `_desdeEnvoltorio`.
  return _Separado(prosa.toString(), envoltorio, huboJson);
}

// ---------------------------------------------------------------------------
// Envoltorio
// ---------------------------------------------------------------------------

bool _esDelContrato(Map<String, dynamic> mapa) => mapa.keys
    .any((k) => _clavesDeContrato.contains(k) || _aliasDeClave.containsKey(k));

EdanSalida _desdeEnvoltorio(
  Map<String, dynamic> mapa, {
  required String prosaAlrededor,
}) {
  final m = _normalizarClaves(mapa);

  final respuestaPropia = m['respuesta'] is String
      ? (m['respuesta'] as String).trim()
      : '';

  // El contrato manda: si el modelo puso `respuesta`, esa es la frase. La
  // prosa de alrededor se descarta porque es casi siempre un eco del propio
  // `respuesta` (y pintar "Anotado. Se registró una granizada muy fuerte."
  // es peor que la frase sola). Se usa solo cuando el envoltorio no trajo
  // ninguna, que es el caso en que la prosa sí aporta.
  var respuesta = respuestaPropia;
  if (respuesta.isEmpty) {
    respuesta = edanProsaVisible(prosaAlrededor);
  }

  final pregunta = m['siguiente_pregunta'] is String
      ? (m['siguiente_pregunta'] as String).trim()
      : '';
  final parche = m['parche'] is Map
      ? (m['parche'] as Map).cast<String, dynamic>()
      : const <String, dynamic>{};

  return EdanSalida(
    respuesta: edanProsaVisible(respuesta),
    siguientePregunta: pregunta.isEmpty ? null : pregunta,
    parche: parche,
    vinoJson: true,
  );
}

// ---------------------------------------------------------------------------
// Lectura puntual de un campo dentro de texto incompleto
// ---------------------------------------------------------------------------

/// Lee el valor de `"campo": "..."` aunque el objeto todavía no esté cerrado.
///
/// Es lo que hace que la respuesta se vea al instante durante el streaming:
/// el JSON no se puede decodificar a medias, pero la comilla de cierre de
/// `respuesta` sí se puede esperar.
String? _leerCampoTexto(String texto, String campo) {
  final inicio = texto.indexOf('"$campo"');
  if (inicio < 0) return null;

  var i = inicio + campo.length + 2;
  while (i < texto.length && (texto[i] == ' ' || texto[i] == ':')) {
    i++;
  }
  if (i >= texto.length || texto[i] != '"') return null;

  i++; // arranca después de la comilla de apertura
  final valor = StringBuffer();
  var escape = false;
  while (i < texto.length) {
    final c = texto[i];
    if (escape) {
      // Se reescapa para poder pasar por jsonDecode abajo.
      valor.write('\\');
      valor.write(c);
      escape = false;
    } else if (c == r'\') {
      escape = true;
    } else if (c == '"') {
      // Cerró: el valor es completo aunque falte el resto del objeto.
      try {
        return jsonDecode('"${valor.toString()}"') as String;
      } on FormatException {
        return valor.toString();
      }
    } else {
      valor.write(c);
    }
    i++;
  }
  return null; // todavía no cerró la comilla
}

// ---------------------------------------------------------------------------
// Utilidades bajas
// ---------------------------------------------------------------------------

Map<String, dynamic>? _comoMapa(String texto) {
  try {
    final v = jsonDecode(texto);
    return v is Map<String, dynamic> ? v : (v is Map ? v.cast<String, dynamic>() : null);
  } catch (_) {
    return null;
  }
}

/// Recorre [texto] sacando cada `{...}` y `[...]` balanceado.
///
/// Busca la próxima apertura y la cierra. No puede usar
/// [_indiceDeAbiertaSinCerrar] para eso: esa devuelve `null` cuando todo está
/// balanceado, y entonces no se borraba **ningún** objeto — que es precisamente
/// el caso normal del JSON completo.
///
/// Respeta strings y escapes para no cerrar en una llave que aparezca adentro
/// de un valor (`"nota": "quedó {partido}"`): esa llave no cierra nada.
String _sinBalanceados(String texto) {
  var t = texto;
  for (;;) {
    final ini = _proximoAbre(t);
    if (ini == null) return t;
    final fin = _buscarCierre(t, ini);
    if (fin == null) return t; // sin cierre: lo corta el paso siguiente
    t = t.substring(0, ini) + t.substring(fin + 1);
  }
}

/// Índice de la primera `{` o `[`, sin saltar ninguna.
int? _proximoAbre(String texto) {
  for (var i = 0; i < texto.length; i++) {
    final c = texto.codeUnitAt(i);
    if (c == 0x7B || c == 0x5B) return i;
  }
  return null;
}

/// Índice de la primera `{` o `[` que todavía no tiene cierre, o `null`.
///
/// Sirve para cortar el volcado a medias: si se abrió y nunca cerró, no hay
/// prosa que valga después. Un JSON completo devuelve `null` acá, que es lo
/// contrario que en [_proximoAbre].
int? _indiceDeAbiertaSinCerrar(String texto) {
  var i = 0;
  while (i < texto.length) {
    final c = texto.codeUnitAt(i);
    if (c == 0x7B || c == 0x5B) {
      final fin = _buscarCierre(texto, i);
      if (fin == null) return i;
      i = fin + 1;
      continue;
    }
    i++;
  }
  return null;
}

/// Índice del cierre correspondiente a la apertura en [ini], o `null`.
int? _buscarCierre(String texto, int ini) {
  final abre = texto.codeUnitAt(ini);
  final cierra = abre == 0x7B ? 0x7D : 0x5D;
  var prof = 0;
  var dentroDeString = false;
  var escape = false;

  for (var i = ini; i < texto.length; i++) {
    final c = texto.codeUnitAt(i);
    if (escape) {
      escape = false;
      continue;
    }
    if (dentroDeString) {
      if (c == 0x5C) {
        escape = true;
      } else if (c == 0x22) {
        dentroDeString = false;
      }
      continue;
    }
    if (c == 0x22) {
      dentroDeString = true;
    } else if (c == abre) {
      prof++;
    } else if (c == cierra) {
      prof--;
      if (prof == 0) return i;
    }
  }
  return null;
}

const _claveValorSuelto =
    r',?\s*"[^"\n]{1,80}"\s*:\s*(?:null|true|false|-?\d+(?:\.\d+)?|"[^"\n]*")?';

const _parcheSuelto =
    r',?\s*"?(?:parche)"?\s*:\s*(?:null|true|false|-?\d+(?:\.\d+)?|"[^"\n]*")';

bool _esLineaDeEstructura(String linea) {
  if (RegExp(r'^[\{\}\[\]]$').hasMatch(linea)) return true;
  if (RegExp(r'^(null|true|false)$').hasMatch(linea)) return true;
  if (RegExp(r'^"?parche"?:?$').hasMatch(linea)) return true;
  if (RegExp(r'^"[^"\n]+"\s*:').hasMatch(linea)) return true;
  return false;
}

bool _pareceEstructura(String t) {
  final s = t.trim();
  if (s.isEmpty) return false;
  if (s.startsWith('{') || s.startsWith('[')) return true;
  if (s.contains('```')) return true;
  if (s.contains('"parche"')) return true;
  if (RegExp(r'^"[^"\n]*"\s*:').hasMatch(s)) return true;
  if (RegExp(r'"\s*:\s*').hasMatch(s)) return true;
  return false;
}
