/// Contrato de la API puente (ver `docs/puente.md` y `docs/PUENTE/`).
///
/// Modelos tipados para `POST /puente` y `POST /puente/stream`. El puente es un
/// proxy genérico hacia el LLM: no conoce el vocabulario EDAN, así que todo lo
/// que sea EDAN (prompt, validación del parche, fusión, persistencia) vive en el
/// cliente.
///
/// Los nombres del JSON son snake_case por contrato. Un campo `null` no se manda
/// (`toJson` lo omite), porque el puente no distingue "ausente" de "explicito".
library;

/// Un turno del historial, como lo espera el puente.
class Mensaje {
  final String role; // 'system' | 'user' | 'assistant'
  final String content;

  const Mensaje(this.role, this.content);

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// Body de `POST /puente` y `POST /puente/stream`: los 12 campos.
class PuenteRequest {
  final String? instruccion;
  final List<Mensaje>? mensajes;
  final String formato;
  final Map<String, dynamic>? jsonSchema;
  final int intentosJson;
  final String razonamiento; // 'off' | 'low' | 'medium'
  final List<String>? stop;
  final int maxTokens;
  final double temperatura;
  final bool? llmExterno;

  const PuenteRequest({
    this.instruccion,
    this.mensajes,
    this.formato = 'json',
    this.jsonSchema,
    this.intentosJson = 1,
    this.razonamiento = 'off',
    this.stop,
    this.maxTokens = 1200,
    this.temperatura = 0.3,
    this.llmExterno,
  });

  Map<String, dynamic> toJson() => {
        if (instruccion != null) 'instruccion': instruccion,
        if (mensajes != null)
          'mensajes': mensajes!.map((m) => m.toJson()).toList(),
        'formato': formato,
        if (jsonSchema != null) 'json_schema': jsonSchema,
        'intentos_json': intentosJson,
        'razonamiento': razonamiento,
        if (stop != null) 'stop': stop,
        'max_tokens': maxTokens,
        'temperatura': temperatura,
        if (llmExterno != null) 'llm_externo': llmExterno,
      };
}

/// Uso de tokens de una llamada.
class Tokens {
  final int entrada, salida, razonamiento;

  const Tokens(this.entrada, this.salida, this.razonamiento);

  factory Tokens.fromJson(Map<String, dynamic> j) => Tokens(
        (j['entrada'] as num?)?.toInt() ?? 0,
        (j['salida'] as num?)?.toInt() ?? 0,
        (j['razonamiento'] as num?)?.toInt() ?? 0,
      );
}

/// Envelope de respuesta de `POST /puente` y del evento `done` del stream.
class PuenteResponse {
  final String respuesta; // SIEMPRE string
  final Map<String, dynamic>? json; // ya parseado
  final String formato; // 'texto' | 'json'
  final String modelo, proveedor;
  final int intentos;
  final Tokens tokens;
  final List<String> avisos;

  const PuenteResponse({
    required this.respuesta,
    required this.json,
    required this.formato,
    required this.modelo,
    required this.proveedor,
    required this.intentos,
    required this.tokens,
    required this.avisos,
  });

  /// El parche salió bien. Si no, baja al extractor determinista.
  Map<String, dynamic>? get parche =>
      (json?['parche'] as Map?)?.cast<String, dynamic>();

  factory PuenteResponse.fromJson(Map<String, dynamic> j) => PuenteResponse(
        respuesta: j['respuesta'] as String? ?? '',
        json: (j['json'] as Map?)?.cast<String, dynamic>(),
        formato: j['formato'] as String? ?? 'texto',
        modelo: j['modelo'] as String? ?? '?',
        proveedor: j['proveedor'] as String? ?? '?',
        intentos: (j['intentos'] as num?)?.toInt() ?? 1,
        tokens: Tokens.fromJson(
            (j['tokens'] as Map?)?.cast<String, dynamic>() ?? const {}),
        avisos: ((j['avisos'] as List?) ?? const []).cast<String>(),
      );
}

/// Un `codigo` de la tabla de errores tipificados del puente, con la decisión
/// ya resuelta para el cliente:
///
/// | codigo            | Hay que extraer | Reintenta |
/// |-------------------|-----------------|-----------|
/// | `json_invalido`   | sí              | no        |
/// | `texto` (HTTP 200)| sí              | no        |
/// | `rate_limit`      | no              | sí (tras `esperar_ms`) |
/// | `timeout`         | no              | sí        |
/// | `proveedor_caido` | no              | sí        |
/// | `truncado`        | no              | sí (sabiendo `max_tokens`) |
/// | `contexto_demasiado` | no           | sí (acortando historial) |
/// | `no_autorizado`   | no              | no        |
class PuenteError implements Exception {
  final String codigo;
  final String mensaje;
  final bool reintentable;
  final int? esperarMs;
  final Map<String, dynamic> detalle;

  /// Bajar al extractor determinista: la ficha se sigue llenando sin internet.
  bool get hayQueExtraer => codigo == 'json_invalido' || formatoCaidoEnTexto;

  /// El puente pidió JSON y respondió texto (HTTP 200 con `formato:"texto"`).
  ///
  /// Se distingue del `json_invalido` (422) porque en ese caso hubo un intento
  /// de reparación que no alcanzó, y del `truncado` porque la respuesta es
  /// completa y servible.
  bool formatoCaidoEnTexto = false;

  PuenteError(this.codigo, this.mensaje, this.reintentable, this.esperarMs, this.detalle);

  factory PuenteError.fromJson(Map<String, dynamic> j) => PuenteError(
        j['codigo'] as String? ?? 'proveedor_caido',
        j['mensaje'] as String? ?? 'Error sin mensaje',
        j['reintentable'] as bool? ?? false,
        (j['esperar_ms'] as num?)?.toInt(),
        (j['detalle'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  @override
  String toString() => 'PuenteError($codigo): $mensaje';
}