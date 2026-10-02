// Laboratorio de prompts del asistente EDAN.
//
// Corre la MISMA conversación contra el puente real con varias estrategias de
// prompt, mide cada turno y al final agrega por laboratorio y por modelo. El
// sorteo de proveedores del puente es al azar, así que un mismo laboratorio
// pasa por `gpt-oss-20b` y por `nemotron-3-ultra-550b`: por eso el corte por
// modelo es la parte interesante del resultado.
//
//   dart run tool/labs_prompt.dart --labs=vars_json,base --guion=progresivo
//
// Qué se mide por turno:
//   pregunta  : la respuesta termina en `?`
//   apunta    : la pregunta va Directed a una variable que sigue vacía
//   repite    : la pregunta va a una variable que YA se llenó (el fallo que se
//               vio en vivo: preguntar el número que la persona acaba de dar)
//   parche    : cuántas claves metió en el parche
//   avance    : progresoGlobal() antes y después
library;

import 'dart:convert';

import 'package:rea/config/api_config.dart';
import 'package:rea/models/edan_borrador_ia.dart';
import 'package:rea/services/edan_ia/edan_fusion.dart';
import 'package:rea/services/edan_ia/edan_groq_prompt.dart';
import 'package:rea/services/edan_ia/edan_groq_service.dart';
import 'package:rea/services/edan_ia/edan_pendientes.dart';
import 'package:rea/services/edan_ia/edan_salida.dart';
import 'package:rea/services/edan_ia/edan_estado_asistente.dart';
import 'package:rea/services/edan_ia/puente_models.dart';
import 'package:rea/services/edan_ia/puente_service.dart';

// ---------------------------------------------------------------------------
// Guiones
// ---------------------------------------------------------------------------

const _guiones = <String, List<String>>{
  // Pensado para la lógica de bloques: cabecera -> evento -> conteos ->
  // educación -> necesidades -> OBSERVACIONES de esas necesidades -> viales.
  'progresivo': [
    'Estamos en Yapacaní, provincia de Ichilo, Santa Cruz.',
    'Ayer en la tarde el río se desbordó y hubo una inundación fuerte.',
    'Afectó a 350 personas de unas 80 familias.',
    'La escuela del centro se inundó y tiene 120 alumnos sin clases.',
    'Necesitan alimentos y agua potable.',
    'Del agua no alcanza: falta una cisterna y hay que limpiar los pozos.',
    'El puente sobre el río se cayó y la ruta 4 quedó cortada.',
    'No hubo heridos graves, solo cortes de luz en el barrio.',
  ],
  'granizada': [
    'Estamos en San Juan, provincia de San Juan.',
    'Ayer en la tarde pasó una granizada muy fuerte.',
    'Afectó a unas doce personas de la plaza.',
    'No hubo heridos graves, solo cortes de luz.',
    'La escuela local sigue sin luz.',
    'El kilómetro 8 de la ruta nacional está cortado por piedras.',
    'El contacto es 02664 123456, a nombre de María López.',
  ],
};

const _maxVacias = 5;

// ---------------------------------------------------------------------------
// Medición
// ---------------------------------------------------------------------------

class Turno {
  Turno({
    required this.n,
    required this.usuario,
    required this.respuesta,
    required this.proveedor,
    required this.modelo,
    required this.ms,
    required this.intentos,
    required this.avisos,
    required this.tokensIn,
    required this.tokensOut,
    required this.tokensRaz,
    required this.clavesParche,
    required this.avanceAntes,
    required this.avanceDespues,
    required this.pregunta,
    required this.destino,
    required this.pendientes,
  });

  final int n;
  final String usuario;
  final String respuesta;
  final String proveedor;
  final String modelo;
  final int ms;
  final int intentos;
  final List<String> avisos;
  final int tokensIn;
  final int tokensOut;
  final int tokensRaz;
  final int clavesParche;
  final double avanceAntes;
  final double avanceDespues;
  final bool pregunta;

  /// Clave de la variable a la que apunta la pregunta: pendiente, ya llenada,
  /// o null si no se pudo mapear a ninguna.
  final String? destino;

  /// Variables que seguían vacías al armar este turno.
  final List<String> pendientes;

  /// True si la pregunta cayó en una variable que seguía vacía.
  ///
  /// Se acepta el emparejamiento por prefijo porque
  /// `necesidadesHumanitarias.Alimentos` y `necesidadesHumanitarias` son el
  /// mismo bloque, y el matcher a veces devuelve la clave corta.
  bool get apunta => destino != null &&
      pendientes.any((k) => k == destino || k.startsWith('$destino.') ||
          destino!.startsWith('$k.'));
  bool get repite => destino != null && !apunta && pendientes.isNotEmpty;
}

/// Palabras que no sirven para mapear una pregunta a una variable: son
/// conectores, no datos.
const _stop = {
  'favor', 'gracias', 'porque', 'entonces', 'mientras', 'acerca', 'ahora',
  'después', 'hacen', 'contame', 'decime', 'ahí', 'momento',
};

Set<String> _significativas(String s, {int minLen = 5}) {
  final limpio = s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9áéíóúüñ ]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.length >= minLen)
      .where((w) => !_stop.contains(w))
      .toSet();
  return limpio;
}

/// Parte una clave en palabras: `necesidadesHumanitarias.Alimentos` ->
/// `necesidades`, `humanitarias`, `alimentos`. Sin esto la clave llega al
/// matcher como un solo token (`necesidadeshumanitarias`) y nunca coincide.
Set<String> _partesDeClave(String clave) {
  final out = <String>{};
  for (final parte in clave.split('.')) {
    for (final m
        in RegExp(r'[A-Z]?[a-záéíóúüñ]+|[A-Z]+(?![a-z])|\d+').allMatches(parte)) {
      out.addAll(_significativas(m.group(0)!, minLen: 4));
    }
  }
  return out;
}

/// A qué variable del catálogo se parece más la pregunta.
///
/// Puntaje IDF a mano: cada palabra compartida vale `1/palabras(objetivo)`, así
/// que "cuántas" (que aparece en varias) pesa menos que "familias". Sin esto
/// "¿Y cuántas familias?" se iba a casar con `totalAfectada`.
///
/// También compara contra las palabras de la `clave`, no solo contra la
/// pregunta: si no, "¿Qué necesita el agua?" no se empareja con
/// `serviciosBasicos.agua` porque "agua" tiene cuatro letras. Y a igualdad de
/// puntaje gana la clave más larga, que es la más específica.
String? _destino(String pregunta, List<EdanVacio> catalogo) {
  final mias = _significativas(pregunta, minLen: 4);
  if (mias.isEmpty) return null;
  String? mejor;
  var mejorPuntaje = 0.0;
  for (final v in catalogo) {
    final suyas = {
      ..._significativas(v.pregunta),
      ..._partesDeClave(v.clave),
    };
    if (suyas.isEmpty) continue;
    final p = mias.intersection(suyas).length / suyas.length +
        0.004 * v.clave.length;
    if (p > mejorPuntaje) {
      mejorPuntaje = p;
      mejor = v.clave;
    }
  }
  return mejorPuntaje >= 0.2 ? mejor : null;
}

/// Catálogo completo: las mismas variables pero con la ficha vacía, para poder
/// notar cuándo el modelo pregunta por algo que ya está lleno.
final _catalogo = variablesVacias(EdanBorradorIa(), maximo: 999)
    .map((v) => EdanVacio(v.bloque, v.clave, v.pregunta, prioridad: v.prioridad))
    .toList();

// ---------------------------------------------------------------------------
// Laboratorios
// ---------------------------------------------------------------------------

class Lab {
  const Lab(this.id, this.nombre, this.prompt,
      {this.temperatura, this.schema, this.razonamiento});
  final String id;
  final String nombre;
  final String Function(EdanBorradorIa b, List<EdanVacio> vacias) prompt;
  final double? temperatura;
  final Map<String, dynamic>? schema;
  final String? razonamiento;
}

String _jsonVacios(List<EdanVacio> vacias) {
  final porBloque = <String, List<String>>{};
  for (final v in vacias) {
    porBloque.putIfAbsent(v.bloque, () => []).add(v.clave);
  }
  return const JsonEncoder.withIndent('  ').convert(porBloque);
}

/// El prompt ganador hasta ahora: el del repo más la lista de variables
/// vacías como JSON por bloque.
String _promptVarsJson(EdanBorradorIa b, List<EdanVacio> v) => '''
${_promptBase(b, v)}

# Lo que falta
Este JSON tiene las variables de la ficha que siguen vacías, agrupadas por
bloque. Es una lista cerrada: no hay nada más que preguntar.

${_jsonVacios(v)}

Elegí **UNA** de esas claves y preguntá por eso, con tus palabras, al final de
`respuesta`. Terminá siempre en `?`.''';

/// El prompt tal como está en el repo hoy.
String _promptBase(EdanBorradorIa b, List<EdanVacio> v) =>
    edanGroqInstruccion(
      pendientes: seccionesIncompletas(progresoGlobal(b), maximo: 3),
      progreso: progresoGlobal(b),
      borrador: b,
    );

String _bloqueVaciasNatural(List<EdanVacio> vacias) => vacias
    .map((v) => '- ${v.pregunta}')
    .join('\n');

final _labs = <Lab>[
  // --- Controles -----------------------------------------------------------
  Lab('suave', 'control: sin reglas duras', (b, v) => '''
Sos quien ayuda a llenar el formulario EDAN de Bolivia. La persona te cuenta qué
pasó y vos anotás.

Devolvé un objeto JSON: {"respuesta": "...", "siguiente_pregunta": null, "parche": {}}
`respuesta` es lo que le decís, y `parche` lleva lo que dijo de nuevo.

Si la persona no aporta nada nuevo, `parche` va {}.

${estadoParaAsistente(b)}'''),

  Lab('base', 'control: prompt actual del repo', (b, v) => edanGroqInstruccion(
        pendientes: seccionesIncompletas(progresoGlobal(b), maximo: 3),
        progreso: progresoGlobal(b),
        borrador: b,
      )),

  // --- La propuesta: listar las variables vacías ---------------------------
  Lab('vars_frases', 'vacíos como frases, elegí UNA', (b, v) => '''
${edanGroqInstruccion(pendientes: seccionesIncompletas(progresoGlobal(b), maximo: 3), progreso: progresoGlobal(b), borrador: b)}

# Lo que falta, variable por variable
Estas son las cosas que todavía NO te dijo, en el orden en que conviene
llenarlas:

${_bloqueVaciasNatural(v)}

Elegí **UNA** de esa lista y hacé esa pregunta, al final de `respuesta`. Nada
más: no combines dos, no inventes otra, no preguntes por lo que ya está en
"# Lo que hay anotado exactamente".'''),

  Lab('vars_json', 'vacíos como JSON por bloque, elegí UNA', (b, v) => '''
${edanGroqInstruccion(pendientes: seccionesIncompletas(progresoGlobal(b), maximo: 3), progreso: progresoGlobal(b), borrador: b)}

# Lo que falta
Este JSON tiene las variables de la ficha que siguen vacías, agrupadas por
bloque. Es una lista cerrada: no hay nada más que preguntar.

${_jsonVacios(v)}

Elegí **UNA** de esas claves y preguntá por eso, con tus palabras, al final de
`respuesta`. Terminá siempre en `?`.'''),

  Lab('vars_ambas', 'JSON + frases, elegí UNA', (b, v) => '''
${edanGroqInstruccion(pendientes: seccionesIncompletas(progresoGlobal(b), maximo: 3), progreso: progresoGlobal(b), borrador: b)}

# Lo que falta
Este JSON tiene las variables de la ficha que siguen vacías, agrupadas por
bloque. Es una lista cerrada: no hay nada más que preguntar.

${_jsonVacios(v)}

Y así se pregunta cada una:

${_bloqueVaciasNatural(v)}

Elegí **UNA**, preguntala al final de `respuesta`, y terminá en `?`.'''),

  Lab('vars_pico', 'JSON + "no cierres sin preguntar"', (b, v) => '''
${edanGroqInstruccion(pendientes: seccionesIncompletas(progresoGlobal(b), maximo: 3), progreso: progresoGlobal(b), borrador: b)}

# Lo que falta
Lista cerrada de las variables vacías:

${_jsonVacios(v)}

# La regla
`respuesta` NO puede terminar sin `?`. Salís de este turno con una pregunta
abierta sobre UNA de las claves de arriba. Si escribís una frase y cerrás, la
persona se queda sin saber qué contar y se corta la charla.

OJO: ya se te avisó que "Entendido" y "Anotado" no se usan. No arranques con eso.'''),

  // --- Forzar desde la app: que el modelo nombre la variable ---------------
  Lab('clave_obligatoria', 'el modelo debe decir qué clave pregunta', (b, v) => '''
${edanGroqInstruccion(pendientes: seccionesIncompletas(progresoGlobal(b), maximo: 3), progreso: progresoGlobal(b), borrador: b)}

# Lo que falta
Lista cerrada de las variables vacías:

${_jsonVacios(v)}

# Tu salida
Además de "respuesta" y "parche", devolvé "variable_pregunta": la clave exacta
de la lista de arriba sobre la que hiciste tu pregunta. La app la usa para
saber si preguntaste por algo que ya estaba.

"variable_pregunta" va "null" solo en el cierre.'''),

  // --- Estilo ficha parcial con nulls (como el HTML de referencia) ---------
  Lab('ficha_nulls', 'ficha parcial con nulls, llená lo que falta', (b, v) => '''
Sos quien ayuda a llenar el formulario EDAN de Bolivia.

Devolvé un objeto JSON: {"respuesta": "...", "siguiente_pregunta": null, "parche": {}}
`parche` lleva SOLO lo que la persona dijo en este mensaje. `respuesta` es lo
que le escuchás, y termina en UNA pregunta sobre lo que falta.

# La ficha como está ahora
${_fichaConNulos(b)}

# Cómo preguntar
Elegí un `null` de la ficha y preguntá por ese dato. Va **uno por mensaje** y
siempre al final de `respuesta`, terminando en `?`. No preguntes por los valores
que ya están: ahí no hay `null`.'''),

  // --- Anti-repetición explícita ------------------------------------------
  Lab('anti_repet', 'vars_json + no repitas lo recién anotado', (b, v) => '''
${edanGroqInstruccion(pendientes: seccionesIncompletas(progresoGlobal(b), maximo: 3), progreso: progresoGlobal(b), borrador: b)}

# Lo que falta
Lista cerrada de las variables vacías:

${_jsonVacios(v)}

# No repitas
Si en tu última respuesta preguntaste por una variable, NO la vuelvas a
preguntar en este turno aunque siga en la lista. Pasá a la siguiente.

Si la persona te acaba de dar un número o un lugar, tu pregunta NO puede ser
por ese mismo número o lugar. Ya lo tiene.'''),

  // --- Temperatura ---------------------------------------------------------
  Lab('t0', 'vars_json a temperatura 0', (b, v) => '''
${edanGroqInstruccion(pendientes: seccionesIncompletas(progresoGlobal(b), maximo: 3), progreso: progresoGlobal(b), borrador: b)}

# Lo que falta
Lista cerrada de las variables vacías:

${_jsonVacios(v)}

Elegí UNA y preguntala al final de `respuesta`, terminando en `?`.''',
      temperatura: 0.0),

  // --- Eje razonamiento: el modelo gasta casi todo el output en razonar ----
  //
  // Medido: con `razonamiento: 'off'` (que NO manda el parámetro) el
  // gpt-oss-20b responde `out=1452 raz=1374`, o sea 78 tokens para la frase y
  // el parche. Con 'low' debería dejar de quemarlos ahí.
  Lab('raz_low', 'vars_json + razonamiento low', _promptVarsJson,
      razonamiento: 'low'),
  Lab('raz_medium', 'vars_json + razonamiento medium', _promptVarsJson,
      razonamiento: 'medium'),
  Lab('raz_low_base', 'prompt actual + razonamiento low', _promptBase,
      razonamiento: 'low'),
];

/// Ficha parcial con `null` en lo vacío, al estilo del HTML de referencia.
String _fichaConNulos(EdanBorradorIa b) {
  String? t(String s) => s.trim().isEmpty ? null : s.trim();
  int? n(int? v) => v;
  final m = <String, dynamic>{
    'municipio': t(b.municipio),
    'provincia': t(b.provincia),
    'departamento': t(b.departamento),
    'fechaEvento': t(b.fechaEvento),
    'horaEvento': t(b.horaEvento),
    'totalAfectada': n(b.totalAfectada),
    'totalFamiliasAfectadas': n(b.totalFamiliasAfectadas),
    'telefono': t(b.telefono),
    'responsableNombre': t(b.responsableNombre),
    'tipoEvento': {
      for (final k in kEdanClavesEvento) k: b.tipoEvento[k] == true,
    },
    'impactoPoblacion': {
      for (final f in b.impactoPoblacion)
        if (f.marcado) f.grupo: f.heridos ?? 0,
    },
    'necesidadesHumanitarias': {
      for (final f in b.necesidadesHumanitarias)
        if (f.si) f.item: (f.observaciones.trim().isEmpty)
            ? null
            : f.observaciones.trim(),
    },
    'educacion': [
      for (final f in b.educacion)
        {
          'establecimiento': t(f.establecimiento),
          'estudiantes': f.estudiantes,
          'suspensionClases': f.suspensionClases,
        }
    ],
    'infraVial': [
      for (final f in b.infraVial)
        {'via': t(f.via), 'danoTotal': t(f.danoTotal)}
    ],
    'danosVivienda': [
      for (final f in b.danosVivienda)
        {'comunidad': t(f.comunidad), 'danoTotal': f.danoTotal}
    ],
    'serviciosBasicos': {
      for (final e in b.serviciosBasicos.entries)
        e.key: e.value.tieneDatos
            ? {
                'danoTotal': t(e.value.danoTotal),
                'necesidades': t(e.value.necesidades),
              }
            : null,
    },
  };
  return const JsonEncoder.withIndent('  ').convert(m);
}

// ---------------------------------------------------------------------------
// Corrida
// ---------------------------------------------------------------------------

Future<void> main(List<String> args) async {
  if (args.contains('--dry')) {
    _dry();
    return;
  }
  final guion = _arg(args, '--guion') ?? 'progresivo';
  final frases = _guiones[guion];
  if (frases == null) {
    // ignore: avoid_print
    print('Guiones: ${_guiones.keys.join(", ")}');
    return;
  }
  final pedidos = (_arg(args, '--labs') ?? _labs.map((l) => l.id).join(','))
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty);
  final labs = _labs.where((l) => pedidos.contains(l.id)).toList();
  if (labs.isEmpty) {
    // ignore: avoid_print
    print('Labs: ${_labs.map((l) => l.id).join(", ")}');
    return;
  }

  final resumen = <String, List<Turno>>{};
  for (final lab in labs) {
    // ignore: avoid_print
    print('\n################ ${lab.id} · ${lab.nombre}');
    resumen[lab.id] = await _corre(lab, frases);
  }

  _tabla(resumen);
}

Future<List<Turno>> _corre(Lab lab, List<String> frases) async {
  final puente = PuenteService(
    baseUrl: ApiConfig.puenteBaseUrl,
    apiKey: ApiConfig.puenteApiKey,
  );
  var borrador = EdanBorradorIa();
  final historial = <Mensaje>[];
  final out = <Turno>[];

  for (var i = 0; i < frases.length; i++) {
    historial.add(Mensaje('user', frases[i]));

    final vacias = variablesVacias(borrador, maximo: _maxVacias);
    final antes = progresoGlobal(borrador).fold<double>(
        0, (s, e) => s + e.valor) /
        progresoGlobal(borrador).length;

    final reloj = Stopwatch()..start();
    PuenteResponse res;
    try {
      res = await puente.enviarStream(
        PuenteRequest(
          instruccion: lab.prompt(borrador, vacias),
          mensajes: historial,
          formato: 'json',
          jsonSchema: lab.schema,
          maxTokens: ApiConfig.puenteMaxTokens,
          temperatura: lab.temperatura ?? ApiConfig.puenteTemperatura,
          razonamiento: lab.razonamiento ?? 'off',
          intentosJson: 1,
        ),
        onToken: (_) {},
      );
    } catch (e) {
      // ignore: avoid_print
      print('  turno ${i + 1} ERROR: $e');
      historial.add(const Mensaje('assistant', 'Sin respuesta.'));
      continue;
    }
    reloj.stop();

    final salida = decodificarSalida(res.respuesta, envoltorio: res.json);
    historial.add(Mensaje('assistant', salida.respuesta));
    final p = EdanGroqService.parcheDesdeJson(salida.parche);
    if (!p.vacio) borrador = aplicarParche(borrador, p);
    final despues = progresoGlobal(borrador).fold<double>(
            0, (s, e) => s + e.valor) /
        progresoGlobal(borrador).length;

    final t = Turno(
      n: i + 1,
      usuario: frases[i],
      respuesta: salida.respuesta,
      proveedor: res.proveedor,
      modelo: res.modelo,
      ms: reloj.elapsedMilliseconds,
      intentos: res.intentos,
      avisos: res.avisos,
      tokensIn: res.tokens.entrada,
      tokensOut: res.tokens.salida,
      tokensRaz: res.tokens.razonamiento,
      clavesParche: salida.parche.length,
      avanceAntes: antes,
      avanceDespues: despues,
      pregunta: salida.respuesta.trim().endsWith('?'),
      destino: _destino(salida.respuesta, _catalogo),
      pendientes: [for (final v in vacias) v.clave],
    );
    out.add(t);

    // ignore: avoid_print
    print('  ${i + 1}. USUARIO  ${t.usuario}');
    // ignore: avoid_print
    print('     SISTEMA  ${_corta(t.respuesta, 260)}');
    // ignore: avoid_print
    print('     -> pregunta=${t.pregunta} destino=${t.destino ?? "-"} '
        'apunta=${t.apunta} repite=${t.repite} parche=${t.clavesParche} '
        'avance=${(t.avanceDespues * 100).toStringAsFixed(0)}%');
    // ignore: avoid_print
    print('     ${t.ms}ms intentos=${t.intentos} avisos=${t.avisos} '
        'in=${t.tokensIn} out=${t.tokensOut} raz=${t.tokensRaz} '
        '· ${t.proveedor} (${t.modelo})');
  }
  return out;
}

/// Chequeo local sin red: sirve para no gastar llamadas si el listado de
/// variables o el matcher de destinos están rotos.
void _dry() {
  // ignore: avoid_print
  print('== catálogo completo (${_catalogo.length} variables)');
  for (final v in _catalogo) {
    // ignore: avoid_print
    print('   ${v.prioridad.toString().padLeft(2)} ${v.bloque.padRight(24)}'
        '${v.clave.padRight(34)}${v.pregunta}');
  }

  // ignore: avoid_print
  print('\n== pendientes con la ficha vacía (max $_maxVacias)');
  for (final v in variablesVacias(EdanBorradorIa(), maximo: _maxVacias)) {
    // ignore: avoid_print
    print('   ${v.bloque.padRight(24)}${v.clave}');
  }

  // ignore: avoid_print
  print('\n== progresión: "Alimentos" y "Tanques de Agua" marcadas');
  final b = EdanBorradorIa();
  b.necesidadesHumanitarias.firstWhere((f) => f.item == 'Alimentos').si = true;
  b.necesidadesHumanitarias.firstWhere((f) => f.item.startsWith('Tanques')).si = true;
  for (final v in variablesVacias(b, maximo: _maxVacias)) {
    // ignore: avoid_print
    print('   ${v.bloque.padRight(24)}${v.clave.padRight(34)}${v.pregunta}');
  }

  // ignore: avoid_print
  print('\n== matcher: a qué variable apunta cada pregunta');
  const muestras = [
    '¿En qué municipio o comunidad estamos?',
    '¿Y cuántas familias?',
    '¿Cuántas personas quedaron afectadas en total?',
    '¿Qué necesitan específicamente de alimentos?',
    '¿Qué necesitan las personas ahora mismo: agua, comida, abrigo?',
    '¿Qué necesita el agua?',
    '¿El agua está potable?',
    '¿Se rompió o se cortó alguna ruta o puente?',
    '¿Alguna escuela se vio afectada?',
    '¿Cuántas viviendas quedaron dañadas?',
    '¿Cómo está el servicio de luz?',
    '¿Qué día pasó el无故?',
    '¿Hubo heridos o desaparecidos?',
    '¿Hay algo más que me quieras contar?',
    'Perfecto, ¿algo más?',
  ];
  for (final m in muestras) {
    final d = _destino(m, _catalogo);
    // ignore: avoid_print
    print('   ${(d ?? "SIN MAPA").padRight(34)} <- $m');
  }
}

void _tabla(Map<String, List<Turno>> resumen) {
  // ignore: avoid_print
  print('\n\n================ RESUMEN POR LABORATORIO');
  // ignore: avoid_print
  print(_fila('lab', ['?', 'apunta', 'repite', 'parche', 'avance', 'ms']));
  for (final e in resumen.entries) {
    final t = e.value;
    if (t.isEmpty) continue;
    // ignore: avoid_print
    print('${e.key.padRight(20)}${_pct(t, (x) => x.pregunta)}'
        '${_pct(t, (x) => x.apunta).padLeft(8)}${_pct(t, (x) => x.repite).padLeft(8)}'
        '${(t.fold<int>(0, (s, x) => s + x.clavesParche) / t.length).toStringAsFixed(1).padLeft(8)}'
        '${(t.last.avanceDespues * 100).toStringAsFixed(0).padLeft(7)}%'
        '${(t.fold<int>(0, (s, x) => s + x.ms) / t.length).round().toString().padLeft(8)}');
  }

  // ignore: avoid_print
  print('\n================ RESUMEN POR MODELO (todos los labs juntos)');
  final porModelo = <String, List<Turno>>{};
  for (final t in resumen.values.expand((l) => l)) {
    porModelo.putIfAbsent(t.modelo, () => []).add(t);
  }
  // ignore: avoid_print
  print(_fila('modelo', ['n', '?', 'apunta', 'repite', 'ms']));
  for (final e in porModelo.entries) {
    final t = e.value;
    // ignore: avoid_print
    print('${e.key.padRight(38)}${t.length.toString().padLeft(4)}'
        '${_pct(t, (x) => x.pregunta).padLeft(6)}'
        '${_pct(t, (x) => x.apunta).padLeft(8)}'
        '${_pct(t, (x) => x.repite).padLeft(8)}'
        '${(t.fold<int>(0, (s, x) => s + x.ms) / t.length).round().toString().padLeft(8)}');
  }
}

String _pct(List<Turno> t, bool Function(Turno) f) {
  if (t.isEmpty) return '  -';
  final n = t.where(f).length;
  return '${(n * 100 / t.length).round()}%';
}

String? _arg(List<String> args, String nombre) {
  for (final a in args) {
    if (a.startsWith('$nombre=')) return a.substring(nombre.length + 1);
  }
  return null;
}

/// Encabezado de tabla: la primera columna a la izquierda, el resto a la
/// derecha. Se arma con `+` y no con interpolación porque `${'?':>5}` dentro de
/// `${}` se parsea como literal de mapa, no como formato.
String _fila(String primera, List<String> resto) =>
    primera.padRight(primera == 'lab' ? 20 : 38) +
    resto.map((c) => c.padLeft(8)).join();

String _corta(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}...';
