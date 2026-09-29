/// Cliente de Groq para el asistente de llenado EDAN.
///
/// Groq habla la API de OpenAI, así que el cuerpo es `chat/completions` con
/// `stream: true` y la respuesta llega como SSE. El modelo elegido
/// (`openai/gpt-oss-20b`) es un modelo de razonamiento: escribe su análisis
/// antes de la respuesta, y ese razonamiento **nunca** se muestra ni se guarda.
///
/// Decisión de diseño: la IA no escribe directo en el borrador. Devuelve un
/// [EdanParche] —el mismo tipo que produce el extractor determinista— y la
/// fusión se encarga de respects lo que la persona ya escribió a mano. Si el
/// modelo inventa una sección, se descarta; si dice algo que el extractor
/// sabía, llega por el mismo camino que las reglas.
///
/// Todo lo que no depende de la red vive en funciones estáticas puras
/// ([jsonDesdeTexto], [parcheDesdeJson], [interpretarLineaSse]) para poder
/// testearlo sin llamar a Groq.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/api_config.dart';
import '../../models/edan_borrador_ia.dart';
import 'edan_extractor.dart' show sinTilde;
import 'edan_parche.dart';

/// Turno del asistente: lo que se le dice a la persona, la pregunta siguiente y
/// el parche con lo que entendió de su mensaje.
class EdanGroqTurno {
  /// Texto para la persona (confirmación breve o respuesta a su pregunta).
  final String respuesta;

  /// La pregunta siguiente, o `null` si ya no queda nada por preguntar.
  final String? siguientePregunta;

  /// Solo lo detectado en este mensaje. Se fusiona con `aplicarParche`.
  final EdanParche parche;

  const EdanGroqTurno({
    required this.respuesta,
    this.siguientePregunta,
    required this.parche,
  });

  bool get sinNadaQueAnotar => parche.vacio;
}

/// Error de Groq con el detalle que devuelve la API, para poder mostrarlo en la
/// interfaz sin adivinar.
class EdanGroqError implements Exception {
  final String mensaje;
  final int? status;

  const EdanGroqError(this.mensaje, {this.status});

  bool get esCredenciales => status == 401 || status == 403;

  @override
  String toString() => 'EdanGroqError($status): $mensaje';
}

/// Un fragmento de texto que va llegando del modelo.
class EdanGroqFragmento {
  final String texto;
  final bool esRazonamiento;

  const EdanGroqFragmento(this.texto, {this.esRazonamiento = false});
}

class EdanGroqService {
  final http.Client _cliente;
  final String _apiKey;
  final String _modelo;

  EdanGroqService({
    http.Client? cliente,
    String? apiKey,
    String? modelo,
  })  : _cliente = cliente ?? http.Client(),
        _apiKey = apiKey ?? ApiConfig.groqApiKey,
        _modelo = modelo ?? ApiConfig.groqModel;

  String get modelo => _modelo;

  static String get _url => '${ApiConfig.groqBaseUrl}/chat/completions';

  Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      };

  // ---------------------------------------------------------------------------
  // Piezas puras
  // ---------------------------------------------------------------------------

  /// Saca el objeto JSON de la respuesta del modelo.
  ///
  /// Un modelo de razonamiento devuelve tres cosas mezcladas: el bloque
  /// `<think>`, texto explanatory y el JSON. Los modelos también envuelven el
  /// JSON en ```json. Se limpian las tres cosas; si no queda JSON válido se
  /// devuelve `null` y quien llama lo trata como "el modelo no entendió", no
  /// como un error.
  static Map<String, dynamic>? jsonDesdeTexto(String texto) {
    var s = texto.trim();

    // 1. Fuera el razonamiento `<think>...</think>` (a veces sin cerrar).
    s = s.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), ' ');
    s = s.replaceAll(RegExp(r'<think>[\s\S]*$'), ' ');

    // 2. Si vino dentro de un bloque cercado, se toma ese bloque.
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(s);
    if (fence != null) s = fence.group(1)!.trim();

    // 3. A menudo el JSON va embebido en una frase: se recorta del primer `{`
    //    al último `}`.
    final ini = s.indexOf('{');
    final fin = s.lastIndexOf('}');
    if (ini >= 0 && fin > ini) s = s.substring(ini, fin + 1);

    try {
      final v = jsonDecode(s);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// Convierte el JSON del modelo en un [EdanParche] validado.
  ///
  /// Es la red de seguridad: el modelo es bueno pero no infalible, así que
  /// todo lo que no encaje con el contrato del borrador se descarta en vez de
  /// propagarse. En concreto:
  ///
  /// - etiquetas de grupo, evento, necesidad, servicio y sección que no
  ///   existan en el vocabulario se ignoran (comparación sin tildes);
  /// - las filas 1:n sin ningún dato reconocible no se agregan;
  /// - las cifras se leen de números o de texto ("40", "40 personas"), y un 0
  ///   explícito sí cuenta como dato;
  /// - una cadena vacía o en blanco equivale a "no lo dijo" y se descarta, para
  ///   no pisar lo que ya estaba escrito.
  static EdanParche parcheDesdeJson(Map<String, dynamic> json) {
    final p = EdanParche();

    // --- Cabecera y conteos ---
    // Nombres y lugares: texto estricto, para que un número suelto no termine
    // en la columna `municipio_nombre`.
    p.departamento = _txtEstricto(json['departamento']);
    p.provincia = _txtEstricto(json['provincia']);
    p.municipio = _txtEstricto(json['municipio']);
    p.alcalde = _txtEstricto(json['alcalde']);
    p.telefono = _txtEstricto(json['telefono']);
    p.fechaLlenado = _txtEstricto(json['fechaLlenado']);
    p.fechaEvento = _txtEstricto(json['fechaEvento']);
    p.horaEvento = _txtEstricto(json['horaEvento']);
    p.tipoEventoOtro = _txtEstricto(json['tipoEventoOtro']);
    p.responsableNombre = _txtEstricto(json['responsableNombre']);
    p.responsableCargo = _txtEstricto(json['responsableCargo']);
    p.responsableTelefono = _txtEstricto(json['responsableTelefono']);
    p.responsableEmail = _txtEstricto(json['responsableEmail']);
    p.totalAfectada = _num(json['totalAfectada']);
    p.totalFamiliasAfectadas = _num(json['totalFamiliasAfectadas']);
    p.totalFamiliasDamnificadas = _num(json['totalFamiliasDamnificadas']);
    p.viviendasAfectadas = _num(json['viviendasAfectadas']);
    p.viviendasDamnificadas = _num(json['viviendasDamnificadas']);

    // --- tipo de evento: solo claves del vocabulario ---
    final ev = _mapa(json['tipoEvento']);
    for (final k in kEdanClavesEvento) {
      if (!ev.containsKey(k)) continue;
      final v = _bool(ev[k]);
      if (v != null) p.tipoEvento[k] = v;
    }

    // --- impacto en población: etiqueta -> campo -> valor ---
    final imp = _mapa(json['impactoPoblacion']);
    for (final entrada in imp.entries) {
      final grupo = _etiquetaConocida(entrada.key, kEdanGruposEdad);
      if (grupo == null) continue;
      final campos = _mapa(entrada.value);
      final destino = <String, Object?>{};
      for (final f in const ['fallecidos', 'heridos', 'desaparecidos']) {
        final v = _num(campos[f]);
        if (v != null) destino[f] = v;
      }
      final obs = _txt(campos['observaciones']);
      if (obs != null) destino['observaciones'] = obs;
      if (destino.isNotEmpty) p.impactoPoblacion[grupo] = destino;
    }

    // --- protección: etiqueta -> BchProteccionFila ---
    final prot = _mapa(json['proteccion']);
    for (final entrada in prot.entries) {
      final grupo = _etiquetaConocida(entrada.key, kEdanGruposProteccion);
      if (grupo == null) continue;
      final campos = _mapa(entrada.value);
      final fila = BchProteccionFila(grupo);
      final total = _num(campos['total']);
      final mujeres = _num(campos['mujeres']);
      final hombres = _num(campos['hombres']);
      if (total != null) fila.total = total;
      if (mujeres != null) fila.mujeres = mujeres;
      if (hombres != null) fila.hombres = hombres;
      final obs = _txt(campos['observaciones']);
      if (obs != null) fila.observaciones = obs;
      if (fila.tieneDatos) p.proteccion[grupo] = fila;
    }

    // --- necesidades humanitarias y primera respuesta: mapas de booleanos ---
    _boolPorEtiqueta(
      _mapa(json['necesidadesHumanitarias']),
      kEdanNecesidadesHumanitarias,
      p.necesidadesHumanitarias,
    );
    _boolPorEtiqueta(
      _mapa(json['primeraRespuesta']),
      kEdanEquiposPrimeraRespuesta,
      p.primeraRespuesta,
    );

    // --- necesidad de salud: solo texto ---
    const clavesSalud = ['incendio', 'inundacion', 'sequia', 'otras', 'observaciones'];
    final salud = _mapa(json['necesidadSalud']);
    for (final k in clavesSalud) {
      final v = _txt(salud[k]);
      if (v != null) p.necesidadSalud[k] = v;
    }

    // --- servicios básicos: clave -> campos de texto ---
    final serv = _mapa(json['serviciosBasicos']);
    for (final entrada in serv.entries) {
      final clave = _claveConocida(entrada.key, kEdanServiciosBasicos.keys);
      if (clave == null) continue;
      final campos = _mapa(entrada.value);
      final destino = <String, String?>{};
      for (final f in const [
        'danoParcial',
        'danoTotal',
        'necesidades',
        'observaciones',
      ]) {
        final v = _txt(campos[f]);
        if (v != null) destino[f] = v;
      }
      if (destino.isNotEmpty) p.serviciosBasicos[clave] = destino;
    }

    // --- listas 1:n ---
    p.infraVial = _filas(json['infraVial'], _via);
    p.infraPublica = _filas(json['infraPublica'], _infraPublica);
    p.infraProductiva = _filas(json['infraProductiva'], _infraProductiva);
    p.saludDanios = _filas(json['saludDanios'], _saludDano);
    p.educacion = _filas(json['educacion'], _educacion);
    p.danosVivienda = _filas(json['danosVivienda'], _vivienda);
    p.agricultura = _filas(json['agricultura'], _agricultura);
    p.pecuario = _filas(json['pecuario'], _pecuario);
    p.comunidades = _filas(json['comunidades'], (m) {
      final f = BchComunidad(nombre: _txt(m['nombre']) ?? '');
      return f.tieneDatos ? f : null;
    });

    return p;
  }

  /// Interpreta una línea de SSE de Groq.
  ///
  /// Devuelve el texto de contenido y el de razonamiento por separado, o `null`
  /// si la línea no trae nada útil (comentarios, `data: [DONE]`, keep-alive).
  static EdanGroqFragmento? interpretarLineaSse(String linea) {
    final t = linea.trim();
    if (!t.startsWith('data:')) return null;
    final payload = t.substring(5).trim();
    if (payload.isEmpty || payload == '[DONE]') return null;
    try {
      final json = jsonDecode(payload);
      if (json is! Map) return null;
      final delta = (json['choices'] as List?)?.firstOrNull;
      if (delta is! Map) return null;
      final d = delta['delta'];
      if (d is! Map) return null;
      final razonamiento = (d['reasoning'] ?? d['reasoning_content']) as String?;
      final contenido = d['content'] as String?;
      final hayContenido = contenido != null && contenido.isNotEmpty;
      final hayRazonamiento = razonamiento != null && razonamiento.isNotEmpty;
      if (!hayContenido && !hayRazonamiento) return null;
      return EdanGroqFragmento(
        hayContenido ? contenido : razonamiento!,
        esRazonamiento: !hayContenido,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Red
  // ---------------------------------------------------------------------------

  /// Un turno con la respuesta completa (sin streaming).
  ///
  /// Se usa cuando la UI no necesita ir mostrando el texto letra por letra; el
  /// resultado pasa por exactamente los mismos validadores que el streaming.
  Future<EdanGroqTurno> turno({
    required List<Map<String, String>> mensajes,
    String? instruccionSistema,
  }) async {
    final resp = await _post(_cuerpo(
      mensajes: mensajes,
      instruccionSistema: instruccionSistema,
      stream: false,
    ));
    if (resp.statusCode >= 300) {
      throw EdanGroqError(
        _detalle(resp.body),
        status: resp.statusCode,
      );
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final contenido = ((json['choices'] as List?)?.firstOrNull
            as Map?)?['message']?['content'] as String?;
    return _turnoDesdeTexto(contenido ?? '');
  }

  /// Un turno token a token, para que la persona vea la respuesta mientras sale.
  ///
  /// Emite el texto útil y, si el modelo razona, también su razonamiento con
  /// [EdanGroqFragmento.esRazonamiento] en `true` para que la UI lo oculte.
  Stream<EdanGroqFragmento> streamTurno({
    required List<Map<String, String>> mensajes,
    String? instruccionSistema,
  }) async* {
    final req = http.Request('POST', Uri.parse(_url))
      ..headers.addAll(_headers())
      ..body = jsonEncode(_cuerpo(
        mensajes: mensajes,
        instruccionSistema: instruccionSistema,
        stream: true,
      ));


    final resp = await _cliente.send(req).timeout(
          const Duration(seconds: 90),
          onTimeout: () => throw const EdanGroqError('Groq tardó demasiado (90s)'),
        );
    if (resp.statusCode >= 300) {
      final cuerpo = await resp.stream.bytesToString();
      throw EdanGroqError(_detalle(cuerpo), status: resp.statusCode);
    }

    var buffer = '';
    await for (final trozo in resp.stream.transform(utf8.decoder)) {
      buffer += trozo;
      var corte = buffer.indexOf('\n');
      while (corte >= 0) {
        final linea = buffer.substring(0, corte);
        buffer = buffer.substring(corte + 1);
        final f = interpretarLineaSse(linea);
        if (f != null) yield f;
        corte = buffer.indexOf('\n');
      }
    }
    // Última línea sin salto de línea (SSE mal cerrado).
    final f = interpretarLineaSse(buffer);
    if (f != null) yield f;
  }

  Future<http.Response> _post(Map<String, dynamic> cuerpo) => _cliente
      .post(
        Uri.parse(_url),
        headers: _headers(),
        body: jsonEncode(cuerpo),
      )
      .timeout(
        const Duration(seconds: 90),
        onTimeout: () =>
            throw const EdanGroqError('Groq tardó demasiado (90s)'),
      );

  Map<String, dynamic> _cuerpo({
    required List<Map<String, String>> mensajes,
    required String? instruccionSistema,
    required bool stream,
  }) =>
      {
        'model': _modelo,
        'messages': [
          if (instruccionSistema != null)
            {'role': 'system', 'content': instruccionSistema},
          ...mensajes,
        ],
        'stream': stream,
        'max_tokens': ApiConfig.groqMaxTokens,
        'temperature': ApiConfig.groqTemperature,
        // El modelo razona antes de responder; a la latencia le interesa la
        // respuesta, no el razonamiento, así que se le pide el mínimo.
        'reasoning_effort': 'low',
        // Modo JSON de la API. Sin esto el modelo se saltea el contrato
        // alrededor de un tercio de las veces y contesta en prosa, lo que en el
        // provider significa turno perdido: la persona habló y no quedó nada
        // anotado. Verificado en vivo contra `openai/gpt-oss-20b`.
        'response_format': {'type': 'json_object'},
      };

  EdanGroqTurno _turnoDesdeTexto(String texto) {
    final json = jsonDesdeTexto(texto);
    if (json == null) {
      // El modelo respondió en prosa. Se conserva como respuesta para no
      // perder lo que dijo, pero sin parche: la UI lo vuelve a preguntar.
      return EdanGroqTurno(respuesta: texto.trim(), parche: EdanParche());
    }
    return EdanGroqTurno(
      respuesta: _txt(json['respuesta']) ?? '',
      siguientePregunta: _txt(json['siguiente_pregunta']),
      parche: parcheDesdeJson(_mapa(json['parche'])),
    );
  }

  String _detalle(String cuerpo) {
    try {
      final json = jsonDecode(cuerpo);
      if (json is Map) {
        final err = json['error'];
        if (err is Map && err['message'] != null) {
          return err['message'].toString();
        }
      }
    } catch (_) {}
    return cuerpo.isEmpty ? 'Groq no devolvió detalle' : cuerpo;
  }
}

// ---------------------------------------------------------------------------
// Ayudas de conversión
// ---------------------------------------------------------------------------

Map<String, dynamic> _mapa(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// Texto no vacío, o `null` (= "no lo dijo"). Nunca devuelve `''`, porque una
/// cadena vacía en un parche terminaría pisando el valor que ya había.
String? _txt(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// Igual que [_txt] pero rechaza números y booleanos.
///
/// Se usa en los campos que son nombres de personas o lugares: si el modelo
/// manda `"municipio": 123` es un error de tipo, y escribir "123" en la
/// columna `municipio_nombre` sería peor que no escribir nada.
String? _txtEstricto(Object? v) {
  if (v is num || v is bool) return null;
  return _txt(v);
}

/// Cifra desde número o desde texto ("40", "40 personas", "1.200"). Devuelve
/// `null` si no hay cifra, y acepta `0` explícito.
int? _num(Object? v) {
  if (v == null) return null;
  if (v is num) return v.round();
  if (v is bool) return null;
  final s = sinTilde(v.toString()).replaceAll(RegExp(r'[^\d-]'), '');
  if (s.isEmpty || s == '-') return null;
  return int.tryParse(s);
}

bool? _bool(Object? v) {
  if (v == null) return null;
  if (v is bool) return v;
  final s = sinTilde(v.toString()).trim();
  if (s == 'true' || s == 'si' || s == 'yes' || s == '1') return true;
  if (s == 'false' || s == 'no' || s == '0') return false;
  return null;
}

/// Busca la etiqueta real de [vocabulario] que corresponde a [etiqueta],
/// ignorando tildes, mayúsculas y espacios. Devuelve `null` si no existe: es
/// más seguro perder un dato dudoso que escribirlo en el grupo equivocado.
String? _etiquetaConocida(String etiqueta, List<String> vocabulario) =>
    _claveConocida(etiqueta, vocabulario);

String? _claveConocida(String clave, Iterable<String> vocabulario) {
  final n = _norm(clave);
  for (final v in vocabulario) {
    if (_norm(v) == n) return v;
  }
  // Segunda pasada: coincidencia por prefijo largo, por si el modelo escribió
  // "Mujeres embarazadas (10)" o "niños 0-5".
  for (final v in vocabulario) {
    final nv = _norm(v);
    if (nv.isNotEmpty && (n.startsWith(nv) || nv.startsWith(n))) return v;
  }
  return null;
}

/// Compara ignorando tildes, mayúsculas y espacios. Se quitan todos los
/// espacios (no solo los de los bordes) porque el modelo escribe
/// "NIÑO (A) 0-5 AÑOS" y la etiqueta real es "Niño(a) 0-5 años".
String _norm(String s) => sinTilde(s.toLowerCase()).replaceAll(RegExp(r'\s+'), '');

void _boolPorEtiqueta(
  Map<String, dynamic> origen,
  List<String> vocabulario,
  Map<String, bool?> destino,
) {
  for (final entrada in origen.entries) {
    final clave = _claveConocida(entrada.key, vocabulario);
    if (clave == null) continue;
    final v = _bool(entrada.value);
    if (v != null) destino[clave] = v;
  }
}

/// Construye las filas 1:n descartando las que no traen ningún dato, para que el
/// modelo no meta filas vacías que luego aparezcan en la UI.
List<T> _filas<T>(Object? bruto, T? Function(Map<String, dynamic>) construir) {
  if (bruto is! List) return [];
  final out = <T>[];
  for (final item in bruto) {
    if (item is! Map) continue;
    final fila = construir(Map<String, dynamic>.from(item));
    if (fila != null) out.add(fila);
  }
  return out;
}

BchDanoVial? _via(Map<String, dynamic> m) {
  final f = BchDanoVial(
    via: _txt(m['via']) ?? '',
    tramo: _txt(m['tramo']) ?? '',
    danoParcial: _txt(m['danoParcial']) ?? '',
    danoTotal: _txt(m['danoTotal']) ?? '',
    kmDanio: _txt(m['kmDanio']) ?? '',
    necesidades: _txt(m['necesidades']) ?? '',
    observaciones: _txt(m['observaciones']) ?? '',
  );
  return f.tieneDatos ? f : null;
}

BchInfraPublica? _infraPublica(Map<String, dynamic> m) {
  final f = BchInfraPublica(
    comunidad: _txt(m['comunidad']) ?? '',
    tipoEstructura: _txt(m['tipoEstructura']) ?? '',
    danoParcial: _txt(m['danoParcial']) ?? '',
    danoTotal: _txt(m['danoTotal']) ?? '',
    necesidades: _txt(m['necesidades']) ?? '',
    observaciones: _txt(m['observaciones']) ?? '',
  );
  return f.tieneDatos ? f : null;
}

BchInfraProductiva? _infraProductiva(Map<String, dynamic> m) {
  final f = BchInfraProductiva(
    tipo: _txt(m['tipo']) ?? '',
    comunidad: _txt(m['comunidad']) ?? '',
    danoParcial: _txt(m['danoParcial']) ?? '',
    danoTotal: _txt(m['danoTotal']) ?? '',
    necesidades: _txt(m['necesidades']) ?? '',
    observaciones: _txt(m['observaciones']) ?? '',
  );
  return f.tieneDatos ? f : null;
}

BchEstablecimientoSalud? _saludDano(Map<String, dynamic> m) {
  final f = BchEstablecimientoSalud(
    establecimiento: _txt(m['establecimiento']) ?? '',
    comunidad: _txt(m['comunidad']) ?? '',
    nivel: _txt(m['nivel']) ?? '',
    dano: _txt(m['dano']) ?? '',
    observaciones: _txt(m['observaciones']) ?? '',
  );
  return f.tieneDatos ? f : null;
}

BchUnidadEducativa? _educacion(Map<String, dynamic> m) {
  final f = BchUnidadEducativa(
    establecimiento: _txt(m['establecimiento']) ?? '',
    comunidad: _txt(m['comunidad']) ?? '',
    danoParcial: _txt(m['danoParcial']) ?? '',
    danoTotal: _txt(m['danoTotal']) ?? '',
    suspensionClases: _bool(m['suspensionClases']) ?? false,
    estudiantes: _num(m['estudiantes']),
    observaciones: _txt(m['observaciones']) ?? '',
  );
  return f.tieneDatos ? f : null;
}

BchDanoVivienda? _vivienda(Map<String, dynamic> m) {
  final f = BchDanoVivienda(
    comunidad: _txt(m['comunidad']) ?? '',
    danoParcial: _num(m['danoParcial']),
    danoTotal: _num(m['danoTotal']),
    necesidades: _txt(m['necesidades']) ?? '',
    observaciones: _txt(m['observaciones']) ?? '',
  );
  return f.tieneDatos ? f : null;
}

BchAgricultura? _agricultura(Map<String, dynamic> m) {
  final f = BchAgricultura(
    cultivo: _txt(m['cultivo']) ?? '',
    hasAfectadas: _num(m['hasAfectadas']),
    hasPerdidas: _num(m['hasPerdidas']),
    necesidades: _txt(m['necesidades']) ?? '',
    observaciones: _txt(m['observaciones']) ?? '',
  );
  return f.tieneDatos ? f : null;
}

BchPecuario? _pecuario(Map<String, dynamic> m) {
  final f = BchPecuario(
    especie: _txt(m['especie']) ?? '',
    animalesAfectados: _num(m['animalesAfectados']),
    animalesMuertos: _num(m['animalesMuertos']),
    necesidades: _txt(m['necesidades']) ?? '',
    observaciones: _txt(m['observaciones']) ?? '',
  );
  return f.tieneDatos ? f : null;
}
