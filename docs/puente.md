# API Puente - referencia implementada y guia de integracion

Como funciona `POST /puente` y `POST /puente/stream` **tal como esta
implementado hoy**, y como lo consume una app Flutter.

- Especifica original (que pide el cliente EDAN): [`PUENTE/PUENTE_EDAN_API.md`](../PUENTE/PUENTE_EDAN_API.md)
- Esquemas JSON autoritativos: [`PUENTE/schemas/`](../PUENTE/schemas/)

---

## Que es y que no es

El puente es un **proxy generico hacia el LLM**. No hace RAG.

| El puente SI hace | El puente NO hace |
|---|---|
| Custodia y cifra la apikey del proveedor | Buscar chunks en la base |
| Sortea proveedor y reintenta si uno cae | Armar contexto de leyes |
| Elige el modelo segun el modo global | Citar fuentes |
| Traduce fallos a codigos tipificados | Conocer el vocabulario EDAN |
| Cuenta tokens por llamada | Persistir nada en el cliente |

**No uses `/puente` para consultas legales**: para eso esta `/chat`, que si hace
RAG sobre las leyes y devuelve citas. `/puente` es para asistentes que arman su
propio prompt en el cliente y necesitan que el modelo lo ejecute tal cual.

---

## Base, autenticacion y salud

```
Base local : http://localhost:8001
Swagger    : http://localhost:8001/docs
Tunel      : ver `bash scripts/motoria.sh url`  (cambia en cada reinicio)
```

**`/puente` y `/puente/stream` exigen `X-API-Key` siempre.** Sin la cabecera, o
con una incorrecta, la respuesta es `401` con el cuerpo de error tipificado
(mismo formato que cualquier otro error del puente):

```json
{
  "tipo": "error",
  "codigo": "no_autorizado",
  "mensaje": "Falta o es invalida la cabecera X-API-Key.",
  "reintentable": false,
  "esperar_ms": null,
  "detalle": { "cabecera": "X-API-Key" }
}
```

El valor es `API_AUTH_TOKEN` de `.env`. A diferencia del resto de la API, el
puente **no** acepta peticiones del mismo origen: siempre pide la clave.

Si el servidor no tiene `API_AUTH_TOKEN` configurado, el puente cierra en falso
(401) y deja un `ERROR` en el log. No devuelve 500 a proposito, para que el
cliente no intente reintentar algo que es un problema de configuracion.

---

## Los tres endpoints

| Metodo | Ruta              | Que hace |
|--------|-------------------|----------|
| POST   | `/puente`         | Un turno, respuesta completa |
| POST   | `/puente/stream`  | Un turno, token a token (SSE) |
| GET    | `/puente/modo`    | A que modelo ira ahora mismo, sin llamar a nadie |

`GET /puente/modo` es solo diagnostico. Sirve para separar "el cliente no mando
la clave" de "esta en modo local y por eso responde raro":

```bash
curl http://localhost:8001/puente/modo -H "X-API-Key: $API_AUTH_TOKEN"
# {"modo":"external","destino":"externo","explicacion":"..."}
```

---

## El body: 12 campos

El mismo body va a los dos POST. Una clave desconocida es `422`, no se ignora.

| Campo | Tipo | Default | Que hace |
|---|---|---|---|
| `instruccion` | string | `null` | System prompt. **Precede a `sistema`** |
| `mensajes` | `[{role,content}]` | ver abajo | Historial literal. **Gana sobre `prompt`** |
| `prompt` | string | `null` | Atajo de un turno, reservado al asistente legal |
| `sistema` | string | `null` | System propio del asistente legal |
| `formato` | `"texto"` \| `"json"` | `"texto"` | `"json"` fuerza `response_format` y verifica que lo que vuelve parsea |
| `json_schema` | object | `null` | Valida `json` contra el. Si falla, cuenta como intento fallido |
| `intentos_json` | int `0..2` | `1` | Intentos **extra** cuando `formato:"json"` y no sale JSON |
| `razonamiento` | `"off"` \| `"low"` \| `"medium"` | `"off"` | Mapea a `reasoning_effort`. `"off"` no lo manda |
| `stop` | string[] | `null` | Se pasa tal cual al proveedor |
| `max_tokens` | int `>=1` | `512` | Tope de **salida visible** |
| `temperatura` | number `0..2` | `0.7` | `0.3` para EDAN |
| `llm_externo` | bool \| null | modo global | `null` = modo global, `true` sortea externos, `false` fuerza local |

### Precedencia

```text
system  :  instruccion  >  sistema  >  prompt generico del puente
turno   :  mensajes     >  prompt
```

`mensajes` se reenvia **tal cual**: el puente no reescribe ni resume el
historial, porque el cliente EDAN ya armo el bloque de estado a proposito.

Si no mandas ningun campo de conversacion (`instruccion`, `mensajes`, `prompt`,
`sistema`) es `422`. Si mandas `mensajes: []` tambien: una lista vacia no es una
peticion.

Si no hay `prompt` ni `mensajes`, el puente usa como turno una frase neutra:
`"Quiero reportar un evento."`

### Como se elige el modelo

Misma regla que `/chat`, via `usar_modelo_externo()`:

| `llm_externo` | Modo global | Quien responde |
|---|---|---|
| `null` (default) | `external` | Un proveedor sorteado **al azar** entre los habilitados |
| `null` | `local` | `local/qwen2.5-3b` |
| `true` | cualquiera | Sorteo entre externos |
| `false` | cualquiera | El local |

El sorteo se mantiene a proposito: reparte la cuota de las APIs gratuitas y si
uno se queda sin cuota el siguiente turno usa otro.

---

## La respuesta

```json
{
  "respuesta": "Lamento mucho lo de Yapacaní. ¿Cuántas familias quedaron con su vivienda dañada?",
  "json": {
    "parche": { "municipio": "Yapacaní", "totalAfectada": 350, "tipoEvento": { "inundacion": true } }
  },
  "formato": "json",
  "modelo": "openai/gpt-oss-20b",
  "proveedor": "Groq-adrian",
  "intentos": 1,
  "tokens": { "entrada": 2640, "salida": 212, "razonamiento": 0 },
  "avisos": []
}
```

| Campo | Contrato |
|---|---|
| `respuesta` | **Siempre string.** Si el proveedor devuelve un objeto, se serializa. Nunca `[object Object]` |
| `json` | El objeto ya parseado, o `null`. Para que el cliente no lo parsee con regex |
| `formato` | Como llego de verdad la respuesta. Si pediste `json` y no vino, es `"texto"` |
| `modelo`, `proveedor` | Siempre presentes. Sin esto no se puede depurar cual modelo rompio el contrato |
| `intentos` | Entre 1 y 3. Si fue 3, algo va mal |
| `tokens` | `entrada`, `salida`, `razonamiento` |
| `avisos` | Texto para logs, no para mostrar |

### Avisos

| Aviso | Significado |
|---|---|
| `respuesta_no_string` | El modelo entrego el objeto ya parseado; el puente lo serializo para `respuesta` |
| `reintento_por_json_invalido` | Hubo al menos un intento de reparacion |
| `json_no_soportado` | El proveedor rechazo `response_format` (tipico del modelo local) |
| `truncado_por_max_tokens` | Salida cortada, pero se pidio `formato:"texto"` |

---

## Streaming (SSE)

```text
data: {"tipo":"razonamiento","texto":"la persona dijo que hubo inundación"}
data: {"tipo":"token","texto":"Lamento"}
data: {"tipo":"token","texto":" mucho lo de Yapacaní."}
data: {"tipo":"json","json":{"parche":{"municipio":"Yapacaní","totalAfectada":350}}}
data: {"tipo":"done","respuesta":"...","formato":"json","modelo":"...","proveedor":"...","intentos":1,"tokens":{...},"avisos":[]}
data: [DONE]
```

| Evento | Cuando | Nota |
|---|---|---|
| `razonamiento` | Delta de pensamiento | **Nunca** va dentro de `respuesta`. El cliente lo oculta |
| `token` | Delta de contenido visible | Es lo unico que se muestra |
| `json` | Una vez, al terminar | El parche ya parseado. Aplica esto cuando llegue, no antes |
| `done` | Al terminar bien | Lleva el envelope completo |
| `error` | Fallo a mitad | Cuerpo de la tabla de errores |
| `[DONE]` | Terminador | Se mantiene por compatibilidad |

`respuesta` se reconstruye concatenando los `token`. El evento `json` es el que
garantiza integridad: el cliente puede pintar el texto mientras llega, pero solo
aplica el parche cuando llega `json`.

### Dos detalles que sorprenden

**1. Un reintento no reenvia prosa.** Si hubo un intento de reparacion
(`intentos > 1`), los intentos 2 y siguientes **no emiten eventos `token`**: su
prompt pide JSON puro, y mandar ese JSON al area de prosa del cliente seria peor
que no mandarlo. En ese caso `done.respuesta` es el texto del ultimo intento y es
el campo autoritativo. Cuando `intentos` vale 1 (lo normal) los `token`
concatenados dan exactamente ese mismo texto.

**2. Los errores tempranos conservan el HTTP.** El primer evento del generador
se consume **antes** de abrir la respuesta, asi que un 413 de ventana o un 429
del proveedor llegan como status HTTP real, no como evento `error` dentro de un
200. Los fallos posteriores al primer token si salen como evento `error`, porque
las cabeceras ya se enviaron.

---

## Errores tipificados

| `codigo` | HTTP | `reintentable` | Que hacer |
|---|---|---|---|
| `rate_limit` | 429 | si | Reintenta una vez tras `esperar_ms` |
| `json_invalido` | 422 | no | Baja al extractor determinista |
| `truncado` | 422 | no | Sube `max_tokens` y avisa |
| `timeout` | 504 | si | Reintenta una vez, luego mensaje de red |
| `proveedor_caido` | 502 | si | El puente ya sorteo otro; reintenta |
| `no_autorizado` | 401 | no | Falta `X-API-Key` |
| `contexto_demasiado` | 413 | no | Acortar el historial desde el cliente |

```json
{
  "tipo": "error",
  "codigo": "rate_limit",
  "mensaje": "El proveedor alcanzó su límite de tokens por minuto",
  "reintentable": true,
  "esperar_ms": 12000,
  "detalle": {}
}
```

Esta tabla es lo que hace decidible la cadena de respaldos. Con un error generico
el cliente no puede distinguir "reintentar" de "bajar al extractor", que son
decisiones opuestas.

### Las dos degradaciones que importan

**JSON que no sale, sin truncado -> `200`, nunca `500`.** Tras agotar
`intentos_json`, si el modelo sigue sin devolver JSON:

```json
{
  "respuesta": "Lamento mucho lo de Yapacaní. ¿Cuántas familias?",
  "json": null,
  "formato": "texto",
  "modelo": "qwen2.5-3b-local",
  "proveedor": "local",
  "intentos": 2,
  "tokens": { "entrada": 2610, "salida": 88, "razonamiento": 0 },
  "avisos": ["json_no_soportado", "reintento_por_json_invalido"]
}
```

La respuesta sigue siendo buena y servible. El cliente la muestra y baja al
extractor determinista sobre el texto de la persona. **La ficha no se rompe.**

**Truncado depende del formato pedido:**

| Pedido | Corte | Resultado |
|---|---|---|
| `formato:"json"` | si | `422 truncado`. Un JSON a medio aplicar perderia datos |
| `formato:"texto"` | si | `200` + aviso `truncado_por_max_tokens` |

---

## El intento de reparacion

Cuando `formato:"json"` y la salida no parsea, el puente hace hasta
`intentos_json` pasadas extra. Cada una es un turno nuevo y asi se arma:

- **system:** tu `instruccion` (o `sistema`) **tal cual**, mas una linea que
  pide JSON puro, sin texto antes ni despues.
- **user:** lo que dijo la persona en su ultimo turno, con la instruccion de
  *anotar sin preguntar nada* y *si no hay dato, devolver el parche vacio*.

El puente reutiliza tu instruccion en vez de una propia para no perder el
vocabulario que tu ya definiste. El sigue sin saber que es EDAN.

**Costo:** cada intento es una llamada completa. Con el tier gratuito de Groq
(8.000 TPM) eso es 2-3 turnos por minuto. Por eso `intentos_json` maximo 2 y la
recomendacion es 1.

---

## Recomendaciones para EDAN

| Parametro | Valor | Por que |
|---|---|---|
| `max_tokens` | **1200 a 4096** | El default 512 trunca el parche a mitad de camino |
| `temperatura` | **0.3** | Que no invente cifras |
| `razonamiento` | **`"off"`** | Ver la nota de abajo |
| `intentos_json` | **1** | Cada reintento es una llamada mas |
| `formato` | `"json"` | Sin esto el modelo conversa en vez de parchear |
| Pausa entre turnos | **12 s, en el cliente** | El puente no duerme |

### Nota sobre `razonamiento: "off"`

Los modelos `gpt-oss-20b` en Groq razonan siempre, y su parametro
`reasoning_effort` solo acepta `low|medium|high` (no `none`). Por eso `"off"`
en el puente significa **no mandar el parametro**, no forzar el modelo a no
razonar.

Medido con `razonamiento:"off"` y `max_tokens: 400`: entre 219 y 656 deltas de
razonamiento antes del primer token de contenido. Con `max_tokens: 120` se
consumo el presupuesto entero razonando y **no quedo nada de respuesta visible**.

Por eso: `razonamiento:"off"` + `max_tokens >= 1200`. El razonamiento llega
igual, pero en su propio evento, y el cliente lo oculta.

### Nota sobre `tokens.razonamiento`

Ese numero viene de `usage.completion_tokens_details.reasoning_tokens`, y no
todos los proveedores lo reportan. Medido hoy:

| Proveedor | `razonamiento` reportado | Realidad |
|---|---|---|
| `groq-*` / `gpt-oss-20b` | 113 | correcto |
| `nvidia-*` / Nemotron | 0 | **incorrecto**: si emitio deltas de razonamiento |

Los Nemotron tambien reportan `tokens.entrada` ~= 38 para prompts de ~500
tokens. Si necesitas contabilidad fina de tokens, excluye los proveedores NVIDIA
o no confies en esas dos cifras.

---

## Integracion en Flutter

Sustituye la llamada directo a Groq por esta. La clave del proveedor **no viaja
en la app**: solo la del puente.

### 1. Modelos

```dart
// lib/services/edan_ia/puente_models.dart

class Mensaje {
  final String role;      // 'system' | 'user' | 'assistant'
  final String content;
  const Mensaje(this.role, this.content);

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class PuenteRequest {
  final String? instruccion;
  final List<Mensaje>? mensajes;
  final String formato;
  final Map<String, dynamic>? jsonSchema;
  final int intentosJson;
  final String razonamiento;          // 'off' | 'low' | 'medium'
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

class Tokens {
  final int entrada, salida, razonamiento;
  const Tokens(this.entrada, this.salida, this.razonamiento);
  factory Tokens.fromJson(Map<String, dynamic> j) => Tokens(
        (j['entrada'] as num?)?.toInt() ?? 0,
        (j['salida'] as num?)?.toInt() ?? 0,
        (j['razonamiento'] as num?)?.toInt() ?? 0,
      );
}

class PuenteResponse {
  final String respuesta;                        // SIEMPRE string
  final Map<String, dynamic>? json;              // ya parseado
  final String formato;                          // 'texto' | 'json'
  final String modelo, proveedor;
  final int intentos;
  final Tokens tokens;
  final List<String> avisos;

  const PuenteResponse({
    required this.respuesta, required this.json, required this.formato,
    required this.modelo, required this.proveedor, required this.intentos,
    required this.tokens, required this.avisos,
  });

  /// El parche salio bien. Si no, baja al extractor determinista.
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

/// Un `codigo` de la tabla de errores, con la decision ya resuelta.
class PuenteError implements Exception {
  final String codigo;       // 'rate_limit' | 'truncado' | ...
  final String mensaje;
  final bool reintentable;
  final int? esperarMs;
  final Map<String, dynamic> detalle;

  /// Bajar al extractor determinista: la ficha se sigue llenando sin internet.
  bool get hayQueExtraer =>
      codigo == 'json_invalido' || formatoCaidoEnTexto;

  /// El puente pidio JSON y respondio texto (HTTP 200 con `formato:"texto"`).
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
```

### 2. Cliente

```dart
// lib/services/edan_ia/puente_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'puente_models.dart';

class PuenteService {
  PuenteService({
    required this.baseUrl,        // ej. 'https://xxxx.trycloudflare.com'
    required this.apiKey,         // API_AUTH_TOKEN. En la app, no la del proveedor
    http.Client? client,
  }) : _http = client ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final http.Client _http;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-API-Key': apiKey,
      };

  Future<PuenteResponse> enviar(PuenteRequest req) async {
    final r = await _http.post(
      Uri.parse('$baseUrl/puente'),
      headers: _headers,
      body: jsonEncode(req.toJson()),
    );
    final cuerpo = _mapaDe(r.body);

    if (r.statusCode != 200) {
      // Un 502 con HTML no tiene que explotar en el parseo, sino quedar como un
      // error sin codigo (`proveedor_caido` por default).
      throw PuenteError.fromJson(cuerpo);
    }
    return PuenteResponse.fromJson(cuerpo);
  }

  /// `{}` si el cuerpo no es JSON o esta vacio.
  static Map<String, dynamic> _mapaDe(String body) {
    if (body.isEmpty) return const {};
    try {
      final j = jsonDecode(body);
      return j is Map ? j.cast<String, dynamic>() : const {};
    } catch (_) {
      return const {};
    }
  }

  /// Un turno en streaming. [onToken] es la prosa visible, [onRazonamiento] el
  /// pensamiento ( normalmente lo ocultas). [onJson] dispara UNA vez con el
  /// parche ya parseado: ahi se aplica al borrador.
  ///
  /// Devuelve el envelope final (`done`).
  Future<PuenteResponse> enviarStream(
    PuenteRequest req, {
    required void Function(String) onToken,
    void Function(String)? onRazonamiento,
    void Function(Map<String, dynamic>)? onJson,
  }) async {
    final peticion = http.Request('POST', Uri.parse('$baseUrl/puente/stream'))
      ..headers.addAll(_headers)
      ..body = jsonEncode(req.toJson());

    final respuesta = await _http.send(peticion);
    final cuerpo = await respuesta.stream.transform(utf8.decoder).join();

    if (respuesta.statusCode != 200) {
      // Error temprano: el puente todavia no abrio el stream, asi que esto es
      // un status HTTP de verdad y el cuerpo ya viene tipificado.
      throw PuenteError.fromJson(_mapaDe(cuerpo));
    }

    PuenteResponse? done;
    StringBuffer respuestaVisible = StringBuffer();

    for (final linea in const LineSplitter().convert(cuerpo)) {
      if (!linea.startsWith('data: ')) continue;
      final bruto = linea.substring(6).trim();
      if (bruto == '[DONE]') break;
      final e = jsonDecode(bruto) as Map<String, dynamic>;

      switch (e['tipo']) {
        case 'token':
          final t = e['texto'] as String? ?? '';
          respuestaVisible.write(t);
          onToken(t);
          break;
        case 'razonamiento':
          onRazonamiento?.call(e['texto'] as String? ?? '');
          break;
        case 'json':
          onJson?.call((e['json'] as Map?)?.cast<String, dynamic>() ?? {});
          break;
        case 'error':
          final err = PuenteError.fromJson(e);
          err.formatoCaidoEnTexto = respuestaVisible.isNotEmpty;
          throw err;
        case 'done':
          done = PuenteResponse.fromJson(e);
          break;
      }
    }

    return done ??
        PuenteResponse(
          respuesta: respuestaVisible.toString(),
          json: null, formato: 'texto',
          modelo: '?', proveedor: '?', intentos: 1,
          tokens: const Tokens(0, 0, 0), avisos: const [],
        );
  }
}
```

### 3. Un turno completo, con la cadena de respaldos

```dart
// El extractor determinista es la ultima linea y NO necesita internet.
Future<void> enviarTurno(String dijoLaPersona) async {
  try {
    final res = await puente.enviarStream(
      PuenteRequest(
        instruccion: edanGroqInstruccion,          // con el bloque de estado ya armado
        mensajes: [Mensaje('user', dijoLaPersona)],
        formato: 'json',
        maxTokens: 1200,
        temperatura: 0.3,
        razonamiento: 'off',
        intentosJson: 1,
      ),
      onToken: (t) => setState(() => _borrador.hablar(t)),
      onRazonamiento: (_) {},                       // se oculta
      onJson: (json) => _borrador.aplicar(
        (json['parche'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );

    if (res.parche != null) {
      _borrador.recalcularProgreso();
      _borrador.revisarReglasDePoblacion();        // §9 paso 4
    } else {
      // HTTP 200 pero vino texto, no JSON (§10). La respuesta igual sirve.
      _aviso('Anote algo del texto a mano.');
      _borrador.aplicar(edanExtractor.extraer(dijoLaPersona));
    }
  } on PuenteError catch (e) {
    switch (e.codigo) {
      case 'rate_limit':                            // 429
        await Future.delayed(Duration(milliseconds: e.esperarMs ?? 12000));
        return enviarTurno(dijoLaPersona);           // reintenta UNA vez
      case 'timeout':                               // 504
      case 'proveedor_caido':                       // 502
        _mensajeDeRed();
        return enviarTurno(dijoLaPersona);
      case 'truncado':                              // 422
        _subirMaxTokens();                          // y avisar
        return enviarTurno(dijoLaPersona);
      case 'contexto_demasiado':                    // 413
        _acortarHistorial();
        break;
      case 'json_invalido':                         // 422
        _borrador.aplicar(edanExtractor.extraer(dijoLaPersona));
        break;
      case 'no_autorizado':                         // 401
        _errorDeConfiguracion();                    // no reintentar
        break;
    }
  }
}
```

### 4. Como aplicar el parche

El puente no sabe de EDAN, asi que esto es del cliente:

1. **Validar** `json.parche` contra
   [`edan-parche.schema.json`](../PUENTE/schemas/edan-parche.schema.json).
   Clave desconocida se **ignora**, no rompe: una respuesta valida con una clave
   de mas no puede costarle la ficha a la persona.
2. **Fusionar** con clave natural. **Nunca pisar un dato existente**: un campo
   ausente en el parche no existe para el merge. Un `0` explicito si cuenta.
3. **Recalcular** progreso y pendientes de seccion.
4. **Revisar las reglas de poblacion** antes de aplicar, y si la suma de grupos
   etarios supera el total, avisar para que el modelo lo mencione.
5. **Hablar** `respuesta`. Si viene relleno tipo "Entiendo, gracias por contarme
   lo que paso", descartar y queda solo la pregunta.

Las listas siguen una regla: **una fila sin ningun dato reconocible no se
agrega**. Es preferible perder una fila inutil que ensuciar la ficha.

---

## Migracion desde el cliente anterior

| Antes | Ahora |
|---|---|
| `ApiConfig.groqApiKey` hardcodeada en la app | `API_AUTH_TOKEN` del puente, por cabecera |
| `sistema:` para la instruccion | `instruccion:` |
| `/chat` como default de `PUENTE_URL` | `/puente` |
| `normalizarRespuesta` defensivo | Opcional: `respuesta` ya es siempre string y `json` ya viene parseado |
| Parsear el parche con regex | `res.parche` directo |

`normalizarRespuesta` puede quedarse como red de seguridad, pero deja de ser
obligatorio.

Si venias de `sistema`, el cambio es semantico: `sistema` ya no se inyecta solo.
Si mandabas `prompt` esperando que el servidor lo usara tal cual, ahora
`instruccion` es el campo explicito para eso.

### Checklist

| # | Paso | Donde |
|---|---|---|
| 1 | Agregar `puenteBaseUrl` y `puenteApiKey` (la del puente, no la del proveedor) | `lib/config/api_config.dart` |
| 2 | Copiar los modelos del §1 | `lib/services/edan_ia/puente_models.dart` |
| 3 | Copiar el cliente del §2 | `lib/services/edan_ia/puente_service.dart` |
| 4 | Cambiar el constructor del provider de `groq:` a `puente:` | `lib/providers/edan_ia_borrador_provider.dart` |
| 5 | Mover la cadena de respaldos del §3 al provider, con **un** reintento por turno | idem |
| 6 | Pasar `sistema:` a `instruccion:` y mandar `formato:'json'` | idem |
| 7 | Aplicar el parche con la regla del §4: nunca pisar un dato existente | idem |
| 8 | Si el turno baja a texto, igual mostrar la respuesta y pasar el extractor | idem |
| 9 | Cambiar los dobles de las pruebas al contrato SSE del puente (eventos `token`/`json`/`done`, no `choices[].delta`) | `test/edan_ia/` |

El punto 9 no es cosmético: los fixtures con el formato viejo pasan a dar
`formato:'texto'` y todas las pruebas de parche pasan en verde sin aplicar nada.

### Verificado contra la API en vivo

Corrida la sonda `tool/prueba_puente.dart` (10 casos, 10 PASS) contra el tunel.
Esto quedo fuera del doc del puente y el cliente tiene que aguantarlo:

| Hallazgo | Como lo maneja el cliente |
|---|---|
| El `422` de validacion **no** es el envelope tipificado: es Pydantic, `detail[].value_error` | Sin `codigo` cae al default `proveedor_caido`, o sea reintenta una vez. Preferible mandarlo a `json_invalido` |
| `mensajes: []` sin `instruccion` da `422`; con la instruccion presente, `200` | Mandar siempre la instruccion y un historial de al menos un turno |
| El content-type real del stream es `text/event-stream`, no `application/json` | No decidir por content-type: leer lineas `data: ` |
| Llegan eventos `razonamiento` aunque mandes `razonamiento:'off'` | Ocultarlos siempre, no asumir que no van a llegar |
| Un proveedor sorteado puede responder `200`, `formato:'json'` y `parche:null`, con aviso `respuesta_no_string` (medido con NVIDIA Nemotron) | `parche` ausente es "el modelo converso": reintento de parche y, si tampoco, extractor |

Del lado servidor quedan pendientes: el `content-type` del OpenAPI todavia dice
`application/json`, los codigos HTTP de la tabla de errores no estan declarados, y
algunas descripciones del OpenAPI salen con mojibake.

---

## Diagnostico rapido

| Sintoma | Causa probable |
|---|---|
| `401 no_autorizado` en un APK que "antes funcionaba" | Falta `X-API-Key`. El puente la exige siempre |
| `502` diciendo que no hay proveedores | Todos marcados como caidos. Corre `bash scripts/motoria.sh proveedores` |
| `422 truncado` | `max_tokens` muy bajo. EDAN necesita 1200+ |
| Respuesta vacia con `200` | El modelo gasto el presupuesto razonando. Subi `max_tokens` |
| `tokens.razonamiento: 0` con razonamiento visible | El proveedor no lo reporta (NVIDIA). Es cosmético |
| Sale prosa en vez de JSON | Falta `formato:"json"`, o la `instruccion` no pide parche |
| `respuesta` es un objeto y antes se rompia la UI | Ya no pasa: el puente lo serializa |

Cuando un proveedor falla, el puente lo saca del sorteo 15 minutos. Vencido,
vuelve como sonda. Para recuperarlos antes: `bash scripts/motoria.sh proveedores`.
