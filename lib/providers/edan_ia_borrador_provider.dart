/// Estado y bucle de la conversación EDAN con el puente de IA.
///
/// Es el pegamento entre las cuatro capas, y no hace lógica propia:
///
///   voz o teclado → `PuenteService` (`enviarStream`) → `EdanParche` validado
///   → `aplicarParche` sobre el borrador → pendientes recalculados
///
/// El puente es un proxy genérico: no sabe que esto es EDAN. Todo el vocabulario
/// (prompt, validación, fusión y persistencia) sigue siendo del cliente. El
/// puente solo custodia la clave del proveedor, garantiza que `respuesta` sea
/// string, parsea `json` y tipifica los errores para que esta cadena de
/// respaldos sepa cuándo reintentar y cuándo bajar al extractor determinista.
///
/// Dos reglas que el provider existe para hacer cumplir:
///
/// 1. **La IA nunca escribe en el borrador directamente.** Todo pasa por
///    [aplicarParche], que es el mismo camino que usa el extractor
///    determinista. Así el resultado de hablar y el de leer una frase formal
///    terminan en el mismo lugar, con las mismas garantías.
/// 2. **El prompt se recalcula en cada turno.** Si no, el modelo seguiría
///    preguntando por secciones que ya se llenaron.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/api_config.dart';
import '../models/edan_borrador_ia.dart';
import '../services/ai/asistente_voz_service.dart';
import '../services/database_helper.dart';
import '../services/edan_ia/edan_extractor.dart';
import '../services/edan_ia/edan_fusion.dart';
import '../services/edan_ia/edan_groq_prompt.dart';
import '../services/edan_ia/edan_groq_service.dart';
import '../services/edan_ia/edan_parche.dart';
import '../services/edan_ia/edan_reglas_poblacion.dart';
import '../services/edan_ia/edan_traduccion.dart';
import '../services/edan_ia/puente_models.dart';
import '../services/edan_ia/puente_service.dart';

/// Un mensaje de la conversación, en lo que la UI necesita para pintarlo.
class EdanIaMensaje {
  final String texto;
  final bool esUsuario;

  /// `true` si el modelo no entendió y hay que repreguntar.
  final bool fallo;

  const EdanIaMensaje.usuario(this.texto)
      : esUsuario = true,
        fallo = false;

  const EdanIaMensaje.asistente(this.texto, {this.fallo = false})
      : esUsuario = false;
}

/// Se lanza cuando un desajuste de población impide guardar.
///
/// Existe como tipo propio y no como `StateError` para que la UI pueda
/// distinguir "no guardar" de "se cayó la app" y pueda mostrar el mensaje del
/// wizard en vez de un error genérico.
class EdanPoblacionIncoherente implements Exception {
  final List<EdanAvisoPoblacion> avisos;

  const EdanPoblacionIncoherente(this.avisos);

  @override
  String toString() => avisos.first.mensaje;
}

/// El desvío al paso de fotos, para cuando el modelo no lo dice.
///
/// El prompt ya le pide que lo mencione con sus palabras, y casi siempre lo
/// hace. Pero "casi siempre" no sirve para un paso del que depende que la
/// persona se acuerde de las fotos: si el modelo se olvidó, se lodice el
/// provider. Va como frase aparte, no pegada a la respuesta, para que la UI
/// pueda distinguirla.
const _cierreFotos = 'Con la conversación ya está la ficha. Ahora te toca '
    'completar las fotos y las coordenadas, que es un paso aparte.';

/// Cuántas veces se reintenta un turno tras un error reinentable del puente.
///
/// Una sola a propósito: la tabla de `puente.md` pide "reintenta una vez". Más
/// pasadas seguidas solo gastan cuota (2-3 turnos por minuto con el tier
/// gratuito) y la persona ya esperó.
const _maxReintentosPorTurno = 1;

/// Tope al que se sube `max_tokens` cuando el puente devuelve `truncado`.
const _maxTokensTope = 12000;

/// La voz, detrás de una interfaz mínima.
///
/// Existe para que las pruebas no dependan de los plugins de TTS/STT: si el
/// provider tomara el singleton directamente, ningún test podría ejercitar el
/// camino de voz.
abstract class EdanIaVoz {
  Future<void> hablar(String texto);
  Future<void> detener();
  Future<void> escuchar({
    required void Function(String texto) onResultado,
    required void Function() onFin,
  });
  Future<void> detenerEscucha();
}

/// Habla de verdad, con los plugins del asistente jurídico.
class EdanIaVozReal implements EdanIaVoz {
  const EdanIaVozReal();

  AsistenteVozService get _v => AsistenteVozService.instance;

  @override
  Future<void> hablar(String texto) => _v.hablar(texto);

  @override
  Future<void> detener() => _v.detener();

  @override
  Future<void> detenerEscucha() => _v.detenerEscucha();

  @override
  Future<void> escuchar({
    required void Function(String texto) onResultado,
    required void Function() onFin,
  }) =>
      _v.escuchar(onResultado: onResultado, onFin: onFin);
}

class EdanIaBorradorProvider extends ChangeNotifier {
  EdanIaBorradorProvider({
    PuenteService? puente,
    EdanIaVoz? voz,
    this._db,
  })  : _puente = puente ??
            PuenteService(
              baseUrl: ApiConfig.puenteBaseUrl,
              apiKey: ApiConfig.puenteApiKey,
            ),
        _voz = voz ?? const EdanIaVozReal();

  final PuenteService _puente;
  final EdanIaVoz _voz;
  final DatabaseHelper? _db;

  EdanBorradorIa _borrador = EdanBorradorIa();
  final List<EdanIaMensaje> _mensajes = [];
  bool _pensando = false;
  bool _escuchando = false;

  /// La escucha se cortó a propósito con [detener]: lo que se alcanzó a oír no
  /// se manda, porque el modelo anotaría datos que la persona no dijo.
  bool _escuchaCancelada = false;

  String _respuestaEnCurso = '';
  String? _error;
  EdanParche _ultimoParche = EdanParche();
  bool _descartado = false;

  // ---------------------------------------------------------------------------
  // Estado para la UI
  // ---------------------------------------------------------------------------

  EdanBorradorIa get borrador => _borrador;
  List<EdanIaMensaje> get mensajes => List.unmodifiable(_mensajes);
  bool get pensando => _pensando;
  bool get escuchando => _escuchando;
  bool get ocupado => _pensando || _escuchando;

  /// Texto que el modelo ya.emitió en este turno. La UI lo muestra como
  /// "escribiendo…" y lo reemplaza cuando llega el mensaje completo.
  String get respuestaEnCurso => _respuestaEnCurso;

  String? get error => _error;
  EdanParche get ultimoParche => _ultimoParche;

  /// `true` si el modelo respondió pero no se pudo entender su JSON. En ese
  /// caso la UI debe ofrecer repreguntar en vez de seguir como si nada.
  bool get descartado => _descartado;

  /// Los desajustes de población, con los mensajes del wizard.
  ///
  /// Los ve la persona aunque el modelo no los mencione: una suma que no cierra
  /// no puede quedar en lo que dijo el chatbot.
  List<EdanAvisoPoblacion> get avisosPoblacion => validarPoblacion(_borrador);

  /// `true` si algún desajuste impide guardar, igual que el botón de enviar del
  /// wizard. La UI tiene que bloquear el guardado y decir por qué.
  bool get bloqueaGuardar => bloqueaEnvioPorPoblacion(_borrador);

  List<EdanProgresoSeccion> get progreso => progresoGlobal(_borrador);

  /// Las secciones más vacías, para que el modelo sepa por dónde seguir.
  ///
  /// `maximo: 3` a propósito: darle las quince vacías lo tienta a recites el
  /// listado, que es justo lo que hace sonar a formulario.
  List<EdanProgresoSeccion> get pendientes =>
      seccionesIncompletas(progreso, maximo: 3);

  /// Avance 0..1 del llenado, para la barra de progreso.
  double get avance {
    final p = progreso;
    if (p.isEmpty) return 0;
    return p.fold<double>(0, (s, x) => s + x.valor) / p.length;
  }

  /// `true` si la conversación ya no aporta: hay que pasar a la revisión de
  /// fotos.
  ///
  /// No es un botón de "listo", es una consecuencia: cuando ninguna sección
  /// queda incompleta, la conversación terminó sola. La UI muestra el paso de
  /// fotos cuando esto pasa.
  bool get listoParaFotos => _descartado == false && pendientes.isEmpty;

  /// `true` si hay al menos un ítem al que se le pueda poner foto.
  ///
  /// El paso de fotos NO exige que la ficha esté completa: se puede guardar en
  /// SQLite incompleta y volver acá después a completar coordenadas y fotos.
  /// Por eso la vista se habilita con cualquier sección ya empezada, no solo
  /// cuando [listoParaFotos] se cumple.
  bool get hayDatosParaFotos =>
      _descartado == false && progreso.any((s) => s.valor > 0);

  /// `true` si este turno ya cerró hacia el paso de fotos.
  ///
  /// Evita que el provider insista con el desvío en cada mensaje posterior.
  bool get _yaCerrado => _mensajes.any((m) => !m.esUsuario && !m.fallo && m.texto == _cierreFotos);

  // ---------------------------------------------------------------------------
  // Bucle
  // ---------------------------------------------------------------------------

  /// Manda un mensaje al modelo y aplica lo que devuelva.
  Future<void> enviar(String texto) async {
    final t = texto.trim();
    if (t.isEmpty || _pensando) return;

    _error = null;
    _descartado = false;
    _respuestaEnCurso = '';
    _mensajes.add(EdanIaMensaje.usuario(t));
    _pensando = true;
    notifyListeners();
    final instruccion = edanGroqInstruccion(
      pendientes: pendientes,
      progreso: progreso,
      borrador: _borrador,
    );
    var historial = _historialParaModelo();

    var maxTokens = ApiConfig.puenteMaxTokens;
    var reintentos = 0;

    try {
      PuenteResponse res;
      while (true) {
        try {
          final buffer = StringBuffer();
          res = await _puente.enviarStream(
            PuenteRequest(
              instruccion: instruccion,
              mensajes: [
                for (final m in historial) Mensaje(m['role']!, m['content']!),
              ],
              formato: 'json',
              maxTokens: maxTokens,
              temperatura: ApiConfig.puenteTemperatura,
              razonamiento: 'off',
              intentosJson: 1,
              // `llm_externo` no se manda a propósito: el modo global sortea el
              // proveedor al azar cada turno y reparte la cuota.
            ),
            onToken: (frag) {
              buffer.write(frag);
              _respuestaEnCurso = buffer.toString();
              notifyListeners();
            },
            onRazonamiento: (_) {}, // el razonamiento nunca se muestra
          );
          break;
        } on PuenteError catch (e) {
          // La tabla de `puente.md`: cada código decide "reintentar" o "caer".
          if (reintentos >= _maxReintentosPorTurno) {
            _error = e.mensaje;
            _mensajes.add(EdanIaMensaje.asistente(
              e.hayQueExtraer
                  ? 'No pude anotar eso. ¿Podés repetirlo?'
                  : _mensajeDeFallo(e.codigo, e.mensaje),
              fallo: true,
            ));
            return;
          }
          switch (e.codigo) {
            case 'rate_limit': // 429
              reintentos++;
              _respuestaEnCurso = '';
              notifyListeners();
              await Future.delayed(
                  Duration(milliseconds: e.esperarMs ?? 12000));
              continue;
            case 'timeout': // 504
            case 'proveedor_caido': // 502
              reintentos++;
              continue;
            case 'truncado': // 422
              reintentos++;
              maxTokens = (maxTokens * 1.5).round().clamp(1, _maxTokensTope);
              notifyListeners();
              continue;
            case 'contexto_demasiado': // 413
              reintentos++;
              historial = _historialParaModelo(maxTurnos: 6);
              continue;
            default:
              // `json_invalido` también cae acá por uso explícito abajo y
              // `no_autorizado` por ser de configuración.
              if (e.hayQueExtraer) {
                _rescatePorExtractor(t);
                _descartado = true;
                _mensajes.add(const EdanIaMensaje.asistente(
                  'No pude anotar eso. ¿Podés repetirlo?',
                  fallo: true,
                ));
              } else {
                _error = e.mensaje;
                _mensajes.add(EdanIaMensaje.asistente(
                  _mensajeDeFallo(e.codigo, e.mensaje),
                  fallo: true,
                ));
              }
              return;
          }
        }
      }

      if (res.formato == 'texto') {
        // El puente no pudo dar JSON (§10): la respuesta igual sirve y la ficha
        // no se rompe. `_turnoEnProsa` ya deja mensaje, voz y `descartado`.
        await _turnoEnProsa(t, res.respuesta);
        return;
      }

      // Si hubo un intento de reparación (`intentos > 1`), el texto autoritativo
      // es el del último intento, no la concatenación de tokens del primero.
      if (res.intentos > 1) {
        _respuestaEnCurso = res.respuesta.trim();
        notifyListeners();
      }

      var parche = EdanGroqService.parcheDesdeJson(res.parche ?? {});
      if (parche.vacio) {
        // Parche vacío o ausente: el modelo conversó en vez de anotar (o
        // `respuesta_no_string` sin `parche`). Una pasada de reparación y, si
        // no alcanza, el extractor determinista.
        final reparado = await _reparar(t);
        parche = reparado ?? _rescatePorExtractor(t) ?? EdanParche();
      } else {
        _borrador = aplicarParche(_borrador, parche);
      }
      _ultimoParche = parche;

      // Lo que se muestra y lo que se dice es solo la prosa limpia: si el modelo
      // escribió el parche en el canal de texto, ese volcado no va ni a la
      // burbuja ni a la voz.
      //
      // Y se le pega la `siguiente_pregunta` del JSON, que antes se tiraba: el
      // prompt le pide al modelo una frase para la persona y aparte UNA
      // pregunta. La respuesta sola era "Anotado." y la pregunta se perdía, así
      // que la persona se quedaba sin saber qué contar y la conversación se
      // clavaba en "Anotado." un turno tras otro.
      // Ojo: `siguiente_pregunta` es hermano de `parche`, no está dentro. Por
      // eso se lee de `res.json` y no de `res.parche`, que es solo el objeto de
      // datos.
      final pregunta = _siguientePreguntaDe(res.json);
      final paraMostrar = _prosaVisible(_respuestaEnCurso);

      // El filtro de "tres palabras o más" es para la ruta de texto degradado,
      // donde una respuesta de dos palabras es ruido del modelo. Aquí el turno
      // ya trae un parche: "Anotado" o "Listo" son confirmaciones que la
      // persona quiere leer, así que alcanza con que no sea estructura.
      var util = paraMostrar.isNotEmpty && !_pareceEstructura(paraMostrar)
          ? paraMostrar
          : '';

      // La pregunta va siempre al final: es lo que la persona tiene que
      // responder. Si ya venía pegada a la respuesta no se repite.
      if (pregunta.isNotEmpty && !_contiene(util, pregunta)) {
        util = util.isEmpty ? pregunta : '$util $pregunta';
      }

      _mensajes.add(EdanIaMensaje.asistente(
        util.isNotEmpty
            ? util
            // El dato quedó anotado aunque el modelo hablara en JSON: preguntar
            // "¿me contás más?" haría que la persona repitiera lo que ya se
            // tiene, que es la única forma real de perder información.
            : (parche.vacio ? '¿Me contás un poco más?' : 'Anotado.'),
      ));

      // El paso de fotos es obligatorio y no se puede dejar en manos del
      // modelo: si la conversación terminó y no lo mencionó, lo dice el
      // provider. Una sola vez, y solo si de verdad ya no falta nada.
      if (listoParaFotos && !_mencionaFotos(util) && !_yaCerrado) {
        _mensajes.add(const EdanIaMensaje.asistente(_cierreFotos));
        await _voz.hablar(_cierreFotos);
      } else {
        // La respuesta se dice con voz: si la persona usó el micrófono, espera
        // una voz de vuelta, no un texto que tiene que leer. El volcado del
        // parche nunca se dice: sería leerse un JSON.
        final paraDecir = util.isNotEmpty ? util : _respuestaEnCurso;
        if (paraDecir.isNotEmpty && paraDecir == util) {
          await _voz.hablar(paraDecir);
        }
      }
    } catch (e) {
      _error = e.toString();
      _mensajes.add(const EdanIaMensaje.asistente(
        'Ocurrió un error inesperado. Revisá la conexión.',
        fallo: true,
      ));
    } finally {
      _pensando = false;
      notifyListeners();
    }
  }

  /// Segunda pasada, solo para recuperar el parche.
  ///
  /// En la corrida real el modelo contestaba largo y se dejaba el parche vacío:
  /// "Entiendo que el camino se rompió. ¿Cuánto mide?" es una respuesta
  /// perfectamente razonable, pero el camino que se acababa de mencionar no
  /// llegaba al borrador. Preguntarle otra vez con una instrucción corta y sin
  /// nada más lo resuelve: no hay diálogo que imitar, solo lo que dijo la
  /// persona y dónde va.
  ///
  /// It runs at most once per turn, and a null return means "there was nothing
  /// to save", which is a legitimate answer: the person may have just been
  /// chatting.
  ///
  /// El `intentos_json` del puente solo reintenta cuando el JSON no parsea; esta
  /// pasada cubre el caso opuesto del campo: JSON válido con parche vacío o sin
  /// `parche` (`respuesta_no_string` de los proveedores que conversan).
  Future<EdanParche?> _reparar(String dicho) async {
    try {
      final res = await _puente.enviar(PuenteRequest(
        instruccion: edanGroqInstruccionReparacion(
          pendientes: pendientes.map((s) => s.titulo).toList(growable: false),
          borrador: _borrador,
        ),
        mensajes: [
          Mensaje('user', 'Lo que dijo la persona: "$dicho"\n'
              'Anotá lo que ya dijo, sin preguntar nada. Si de verdad no hay '
              'ningún dato, devolvé el parche vacío.'),
        ],
        formato: 'json',
        intentosJson: 1,
        maxTokens: ApiConfig.puenteMaxTokens,
        temperatura: ApiConfig.puenteTemperatura,
        razonamiento: 'off',
      ));
      // Si el puente respondió texto (degradación), el extractor igual intenta.
      if (res.formato == 'texto') return null;
      final p = EdanGroqService.parcheDesdeJson(res.parche ?? {});
      if (p.vacio) return null;
      _borrador = aplicarParche(_borrador, p);
      return p;
    } on PuenteError {
      // Si la red falla en el rescate, el extractor determinista igual intenta.
      return null;
    }
  }

  /// El mensaje que ve la persona cuando un error reinentable se agotó o no lo
  /// es. `no_autorizado` es de configuración y se distingue de un fallo de red.
  static String _mensajeDeFallo(String codigo, String mensaje) {
    if (codigo == 'no_autorizado') {
      return 'La clave del asistente no es válida. Revisá la configuración.';
    }
    if (codigo == 'truncado') {
      return 'La respuesta quedó cortada. Probá con frases más cortas.';
    }
    return 'Falló la conexión: $mensaje';
  }

  /// Turno en el que el modelo contestó en prosa y no en el JSON del contrato.
  ///
  /// La corrida real contra Groq lo pasó de largo: con el prompt largo y la
  /// API saturada, la respuesta llegaba como texto plano. Descartarla entera
  /// era lo peor posible: la persona había hablado, sus datos se perdían, y
  /// encima se le pedía repetir. Así que acá se hacen las dos cosas:
  ///
  /// 1. **Se muestra lo que respondió**, que para alguien que está en el campo
  ///    es una respuesta, aunque venga sin la parte estructurada. Va como
  ///    mensaje normal y no como fallo, para que siga en el historial: si se
  ///    marcara como fallo, el modelo se olvidaría de su propia frase en el
  ///    turno siguiente.
  /// 2. **Se recupera lo que se pudo con el extractor determinista**, que lee
  ///    números y nombres sin depender de ningún modelo. Es el mismo camino que
  ///    usa la carga por texto formal: si los datos estaban en la frase, quedan
  ///    anotados igual.
  ///
  /// `descartado` queda en `true` igual: la UI puede ofrecer "repetir" porque
  /// el contrato no se respetó. Lo que no se hace es tirar el turno.
  Future<void> _turnoEnProsa(String dicho, String prosa) async {
    final util = _esRespuestaUsable(prosa) ? prosa.trim() : '';
    _rescatePorExtractor(dicho);

    final mostrar = util.isNotEmpty ? util : 'No pude entender eso. ¿Podés repetirlo?';
    _descartado = true;
    _mensajes.add(EdanIaMensaje.asistente(mostrar, fallo: util.isEmpty));
    if (util.isNotEmpty) await _voz.hablar(util);
  }

  /// Último recurso antes de perder lo que dijo la persona.
  ///
  /// Pasa la frase por el extractor determinista, que no depende de ningún
  /// modelo y por eso funciona justo cuando el modelo falló. Devuelve el parche
  /// que aplicó, o `null` si en la frase no había nada que leer.
  ///
  /// Nunca pisa un dato ya anotado: `extraer` recibe el borrador actual.
  EdanParche? _rescatePorExtractor(String dicho) {
    final porExtractor = extraer(dicho, _borrador);
    if (porExtractor.vacio) return null;
    _borrador = aplicarParche(_borrador, porExtractor);
    _ultimoParche = porExtractor;
    return porExtractor;
  }

  /// Si lo que vino es una respuesta o es ruido de relleno.
  ///
  /// El mínimo de palabras filtra los tres casos que se vieron en la corrida
  /// real: el eco de la instrucción, un error repetido y un fragmento suelto. Un
  /// modelo de razonamiento que se salta el JSON igual habla con frases, así que
  /// dos palabras no alcanzan para descartarlo.
  static bool _esRespuestaUsable(String prosa) {
    final limpio = prosa.trim();
    if (limpio.isEmpty) return false;
    // Un JSON truncado o con campos en null no es una respuesta: es un intento
    // de parche que el modelo no terminó.
    if (limpio.startsWith('{') || limpio.contains('"parche"')) return false;
    return limpio.split(RegExp(r'\s+')).length >= 3;
  }

  /// Lo que se escribe en la burbuja: solo la prosa.
  ///
  /// El canal de texto del modelo no siempre trae solo prosa. En la corrida
  /// real, al decir "pasó una granizada" la respuesta llegó con las dos cosas
  /// pegadas: `entiendo que hubo una granizada, siguiente pregunta` y, detrás,
  /// el volcado del parche (`null`, `parche:`, `tipoEvento: granizada: true`).
  /// El `parche` ya viaja aparte y limpio en el evento `json` del puente, así
  /// que lo que se repite en el texto es ruido; pero al pintarlo tal cual la
  /// persona lee dos respuestas y ninguna se entiende.
  ///
  /// La regla exploits el orden del modelo: la prosa va primero y el volcado
  /// después, así que se corta en el primer volcado. Nada más se toca; si la
  /// prosa no queda utilizable, el turno no muestra JSON ni se descarta (eso lo
  /// decide [_esRespuestaUsable] y quien lo llama).
  static String _prosaVisible(String texto) {
    var t = texto.trim();
    if (t.isEmpty) return '';

    // Bloques cercados: ```json ... ```
    t = t.replaceAll(RegExp('```[\\s\\S]*?```'), ' ');

    // Objetos JSON balanceados que envuelven el parche (anidados incluidos).
    t = _sinJsonDelParche(t);

    // A partir de un volcado estructurado ya no hay prosa que valga.
    final corte = RegExp(
      r'(^|\n)[ \t]*(null[ \t]*$|parche\b|"parche"|\{)',
      multiLine: true,
    ).firstMatch(t);
    if (corte != null) t = t.substring(0, corte.start);

    // Líneas que son solo estructura: llaves, corchetes, un `null` suelto o una
    // clave sin valor. Una palabra suelta ("Anotado", "Listo") es una respuesta
    // válida y se conserva, por eso la clave exige los dos puntos.
    final lineas = t
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !_lineaDeEstructura.hasMatch(l))
        .toList();
    return lineas.join(' ').trim();
  }

  /// Una línea que no es una frase: `{`, `}`, `[`, `]`, `null`, `parche` o
  /// `tipoEvento:`. El valor suelto (`granizada: true`) no se quita con esto: va
  /// dentro del bloque que ya se truncó.
  static final _lineaDeEstructura = RegExp(
    r'^(\{|\}|\[|\]|null|parche:?|"?[\wáéíóúñ]+"?[ \t]*:)$',
  );

  /// La pregunta que el modelo dejó preparada en `siguiente_pregunta`.
  ///
  /// Vive al lado de `parche` dentro del JSON, no dentro del parche: es una
  /// decisión de la conversación, no un dato de la ficha. Vacía si vino `null`,
  /// que es lo que significa "no preguntes nada todavía".
  static String _siguientePreguntaDe(Map<String, dynamic>? json) {
    final cruda = json?['siguiente_pregunta'];
    if (cruda is! String) return '';
    final limpia = cruda.trim();
    if (limpia.isEmpty || _pareceEstructura(limpia)) return '';
    return limpia;
  }

  /// ¿`texto` ya dice lo mismo que `frase`?
  ///
  /// Sin tildes ni mayúsculas, para no repetir cuando el modelo metió la
  /// pregunta dentro de la respuesta y además la mandó en su campo.
  static bool _contiene(String texto, String frase) {
    if (texto.isEmpty || frase.isEmpty) return false;
    return _normalizar(texto).contains(_normalizar(frase));
  }

  static String _normalizar(String s) => s
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n')
      .replaceAll('ü', 'u');

  /// ¿Lo que quedó es estructura y no una frase?
  ///
  /// [_prosaVisible] ya quita el volcado del parche; esto es la red detrás, por
  /// si el modelo escribe un objeto suelto o un mapa sin la palabra `parche`.
  static bool _pareceEstructura(String texto) {
    final t = texto.trimLeft();
    return t.startsWith('{') ||
        t.startsWith('[') ||
        t.contains('"parche"') ||
        t.contains('=>');
  }

  /// Quita los objetos JSON balanceados que contienen `"parche"`, con
  /// anidamiento. Un `scan` de llaves, porque un `RegExp` no alcanza cuando el
  /// volcado trae subobjetos: `{"parche":{"tipoEvento":{"granizada":true}}}`.
  static String _sinJsonDelParche(String texto) {
    final limpio = StringBuffer();
    var i = 0;
    while (i < texto.length) {
      final abre = texto.indexOf('{', i);
      if (abre < 0) {
        limpio.write(texto.substring(i));
        break;
      }
      limpio.write(texto.substring(i, abre));

      var nivel = 0;
      var j = abre;
      for (; j < texto.length; j++) {
        if (texto[j] == '{') {
          nivel++;
        } else if (texto[j] == '}') {
          nivel--;
          if (nivel == 0) {
            j++;
            break;
          }
        }
      }
      final fin = j > texto.length ? texto.length : j;
      final bloque = texto.substring(abre, fin);
      if (!bloque.contains('"parche"')) limpio.write(bloque);
      i = fin;
    }
    return limpio.toString();
  }

  /// Escucha del micrófono y responde con lo que oyó.
  Future<void> escucharYResponder() async {
    if (_escuchando || _pensando) return;
    _escuchando = true;
    _error = null;
    _escuchaCancelada = false;
    notifyListeners();

    // `AsistenteVozService.escuchar` resuelve cuando la sesión EMPIEZA (así
    // funciona `speech_to_text.listen`): la transcripción y el final llegan
    // después, por el canal de estado. Esperar el `await` y seguir como si ya
    // estuviera todo era el motivo de que el micrófono no hiciera nada: se
    // seguía con la transcripción vacía y nunca se mandaba al puente. La
    // espera real es la promesa que cierra `onFin`.
    String? oido;
    final finDeEscucha = Completer<void>();

    unawaited(_voz.escuchar(
      onResultado: (t) => oido = t,
      onFin: () {
        if (!finDeEscucha.isCompleted) finDeEscucha.complete();
      },
    ).catchError((Object e) {
      if (!finDeEscucha.isCompleted) {
        _error = 'No se pudo escuchar: $e';
        finDeEscucha.complete();
      }
    }));

    await finDeEscucha.future;
    _escuchando = false;
    notifyListeners();

    // Lo que se cortó a mitad no se manda: una transcripción incompleta es peor
    // que no mandar nada, porque el modelo anotaría datos que la persona no dijo.
    if (_escuchaCancelada) return;

    final texto = oido?.trim() ?? '';
    if (texto.isEmpty) return;
    // No se repite lo dicho: la respuesta del modelo ya va a confirmar y
    // preguntar. Anunciar "Entendí: ..." por voz hace que la persona espere un
    // tono de máquina y rompe la conversación.
    await enviar(texto);
  }

  /// Corta la escucha o el habla en curso.
  Future<void> detener() async {
    _escuchaCancelada = true;
    await _voz.detenerEscucha();
    await _voz.detener();
    _escuchando = false;
    _pensando = false;
    notifyListeners();
  }

  void reiniciar() {
    _borrador = EdanBorradorIa();
    _mensajes.clear();
    _respuestaEnCurso = '';
    _error = null;
    _descartado = false;
    _ultimoParche = EdanParche();
    notifyListeners();
  }

  /// `true` si el modelo ya llevó la conversación al paso de fotos.
  ///
  /// Se miran palabras sueltas y no un campo del JSON porque el modelo no
  /// tiene obligación de estructurar ese cierre: lo dice cuando lo dice.
  static bool _mencionaFotos(String texto) {
    final t = texto.toLowerCase();
    return t.contains('foto') ||
        t.contains('coordenad') ||
        t.contains('ubicac') ||
        t.contains('geolocal');
  }

  // ---------------------------------------------------------------------------
  // Cierre
  // ---------------------------------------------------------------------------

  /// Traduce el borrador a las filas de SQLite, sin tocar la base.
  ///
  /// Va separada de [guardar] a propósito: los avisos de traducción se pueden
  /// mostrar y aceptar antes de escribir, y las pruebas no necesitan una base.
  EdanTraduccionResultado prepararGuardado() => traducirBorrador(_borrador);

  /// Traduce y persiste la localidad con sus secciones activas.
  ///
  /// El id sale del return de `insertLocalidad`, no del objeto: el helper genera
  /// el id en la fila y no lo escribe atrás en [EdanLocalidad]. Leerlo del
  /// objeto después de insertar devolvía `''` y dejaba la UI sin saber qué se
  /// guardó.
  ///
  /// Lanza [EdanPoblacionIncoherente] si un desajuste de población impide
  /// enviar, igual que el wizard no deja mandar una ficha con las sumas
  /// rotas. Que lo tire el provider y no solo la UI evita que un botón mal
  /// conectado guarde datos que después nadie va a poder usar.
  ///
  /// [preparado] es para cuando la UI ya-tradujo antes, por ejemplo después del
  /// paso de fotos: se le pasa esa misma localidad y no se vuelve a traducir.
  /// Sin eso, las fotos y coordenadas se perdían, porque [prepararGuardado] arma
  /// una localidad nueva cada vez y el provider terminaba guardando otra.
  Future<String> guardar({
    required int usuarioId,
    EdanTraduccionResultado? preparado,
  }) async {
    final bloqueantes = avisosPoblacion
        .where((a) => a.bloqueaEnvio)
        .toList(growable: false);
    if (bloqueantes.isNotEmpty) {
      throw EdanPoblacionIncoherente(bloqueantes);
    }

    final db = _db ?? DatabaseHelper.instance;
    final r = preparado ?? prepararGuardado();
    final previo = r.localidad.idLocal;
    final String guardado;
    if (previo == null || previo.isEmpty) {
      guardado = await db.insertLocalidad(r.localidad, usuarioId: usuarioId);
    } else {
      await db.updateLocalidad(r.localidad);
      guardado = previo;
    }

    await db.activarSecciones(guardado, r.seccionesActivas);
    return guardado;
  }

  // ---------------------------------------------------------------------------

  /// El historial que ve el modelo: los últimos turnos, en pares rol/contenido.
  ///
  /// Se recorta porque el prompt ya es largo y cada mensaje suma tokens en
  /// todos los turnos siguientes.
  List<Map<String, String>> _historialParaModelo({int maxTurnos = 12}) {
    // Los turnos que el modelo no entendió no se le reenvían: si no, puede
    // intentar volver a interpretar un mensaje que ya se descartó.
    final utiles = _mensajes.where((m) => !m.fallo).toList();
    final cola = utiles.length <= maxTurnos
        ? utiles
        : utiles.sublist(utiles.length - maxTurnos);
    return [
      for (final m in cola)
        {'role': m.esUsuario ? 'user' : 'assistant', 'content': m.texto},
    ];
  }
}
