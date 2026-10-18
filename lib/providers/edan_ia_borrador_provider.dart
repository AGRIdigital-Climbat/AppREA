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
import 'package:flutter/services.dart';

import '../config/api_config.dart';
import '../models/edan_borrador_ia.dart';
import '../services/ai/asistente_voz_service.dart';
import '../services/edan_ia/edan_extractor.dart';
import '../services/edan_ia/edan_fusion.dart';
import '../services/edan_ia/edan_groq_prompt.dart';
import '../services/edan_ia/edan_groq_service.dart';
import '../services/edan_ia/edan_parche.dart';
import '../services/edan_ia/edan_reglas_poblacion.dart';
import '../services/edan_ia/edan_salida.dart';
import '../services/edan_ia/edan_traduccion.dart';
import '../services/edan_ia/puente_models.dart';
import '../services/edan_ia/puente_service.dart';
import '../services/edan/edan_store_v2.dart';

/// Los sonidos del micrófono.
///
/// Son cortos y distintos entre sí a propósito: mirando la pantalla se sabe en
/// qué estado está, pero mirando al horizonte —que es como se carga el
/// teléfono en el campo— el tono dice si está escuchando o si ya terminó.
enum EdanPistaVoz { abriendo, transcribiendo, transcrito, cerrado }

/// Voz que además puede dar señales cortas de estado.
///
/// [EdanIaVoz] no la declara porque el resto de las pantallas que la usan no
/// necesitan pistas; si una implementación no las da, el provider sigue
/// funcionando igual.
abstract interface class EdanIaVozConPistas implements EdanIaVoz {
  Future<void> pista(EdanPistaVoz pista);
}

/// Un mensaje de la conversación, en lo que la UI necesita para pintarlo.
class EdanIaMensaje {
  final String texto;
  final bool esUsuario;

  /// `true` si el modelo no entendió y hay que repreguntar.
  final bool fallo;

  const EdanIaMensaje.usuario(this.texto)
      : esUsuario = true,
        fallo = false;

  /// Crea un mensaje del asistente pasando [texto] por [edanProsaVisible].
  ///
  /// Es el **punto único de control** de lo que la persona puede leer. Todos
  /// los caminos que agregan mensajes del modelo pasan por este constructor,
  /// así que agregar otro camino en el futuro no puede volver a colar el
  /// contrato en el chat: la regla vive en el tipo, no en cada llamador.
  ///
  /// Los mensajes del usuario no se tocan: lo que dijo la persona se muestra
  /// tal cual, aunque contenga llaves.
  ///
  /// No es `const` justamente porque hace este trabajo. Las frases fijas
  /// (`_cierreFotos`, el saludo) salen idénticas, que es lo que exige la UI
  /// al compararlas por igualdad.
  EdanIaMensaje.asistente(String texto, {this.fallo = false})
      : texto = edanProsaVisible(texto),
        esUsuario = false;
}

/// Qué está haciendo el micrófono ahora.
///
/// Sin esto la persona no sabe si el celular la está oyendo o si ya se cansó de
/// escucharla: el botón solo cambiaba de color y en el campo, con las manos
/// ocupadas, eso no se distingue. Son cuatro estados y no dos porque
/// "transcribiendo" es el más largo de todos y el que más confundía.
enum EdanIaEstadoVoz {
  /// Nada: esperando que la persona escriba o toque el micrófono.
  inactivo,

  /// El micrófono está abierto: está escuchando.
  escuchando,

  /// Ya dejó de escuchar y está pasando la voz a texto.
  transcribiendo,

  /// Escuchó, entendió y está contestando.
  pensando;

  bool get activo => this != EdanIaEstadoVoz.inactivo;

  /// Lo que la persona lee en la barra inferior.
  String get etiqueta => switch (this) {
        EdanIaEstadoVoz.inactivo => '',
        EdanIaEstadoVoz.escuchando => 'Te estoy escuchando…',
        EdanIaEstadoVoz.transcribiendo => 'Pasando tu voz a texto…',
        EdanIaEstadoVoz.pensando => 'Estoy pensando tu respuesta…',
      };
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

/// Lo primero que dice la IA al abrir la pantalla.
///
/// Una sola pregunta abierta y ninguna lista de secciones: si arranca vaciando
/// las secciones pendientes, suena a formulario y la persona le contesta una por
/// una en vez de contar qué pasó. La lista se la da el modelo después, en el
/// ritmo en que la persona vaya contando.
const _saludo =
    'Contame qué pasó. Yo voy anotando y te voy preguntando lo que falte.';

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
class EdanIaVozReal implements EdanIaVozConPistas {
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

  /// Las pistas de estado suenan y vibran.
  ///
  /// Cada estado tiene un sonido y una vibración distintos, y el par es
  /// deliberado: el tono solo no se escucha si el teléfono está en el bolsillo, y
  /// la vibración sola no se siente con guantes. Juntos, quien no está mirando la
  /// pantalla igual sabe si el micrófono está abierto o si ya terminó.
  @override
  Future<void> pista(EdanPistaVoz pista) async {
    // Un tono grave al abrir, uno corto al empezar a transcribir y otro más
    // agudo al terminar: la secuencia se reconoce sin mirar.
    switch (pista) {
      case EdanPistaVoz.abriendo:
        await SystemSound.play(SystemSoundType.alert);
        unawaited(HapticFeedback.mediumImpact());
      case EdanPistaVoz.transcribiendo:
        await SystemSound.play(SystemSoundType.click);
        unawaited(HapticFeedback.selectionClick());
      case EdanPistaVoz.transcrito:
        await SystemSound.play(SystemSoundType.click);
        unawaited(HapticFeedback.lightImpact());
      case EdanPistaVoz.cerrado:
        unawaited(HapticFeedback.selectionClick());
    }
  }
}

class EdanIaBorradorProvider extends ChangeNotifier {
  EdanIaBorradorProvider({
    PuenteService? puente,
    EdanIaVoz? voz,
  })  : _puente = puente ??
            PuenteService(
              baseUrl: ApiConfig.puenteBaseUrl,
              apiKey: ApiConfig.puenteApiKey,
            ),
        _voz = voz ?? const EdanIaVozReal();

  final PuenteService _puente;
  final EdanIaVoz _voz;

  EdanBorradorIa _borrador = EdanBorradorIa();
  final List<EdanIaMensaje> _mensajes = [];
  bool _pensando = false;
  bool _escuchando = false;

  /// El saludo ya se dio en esta sesión de conversación: no se repite.
  bool _saludoDado = false;

  /// El micrófono ya se cerró y la voz todavía se está pasando a texto: es la
  /// espera más larga de todo el ciclo y antes no se mostraba.
  bool _transcribiendo = false;

  /// La escucha se cortó a propósito con [detener]: lo que se alcanzó a oír no
  /// se manda, porque el modelo anotaría datos que la persona no dijo.
  bool _escuchaCancelada = false;

  String _respuestaEnCurso = '';

  /// Las últimas palabras que el micrófono reconoció, mientras todavía se está
  /// escuchando.
  ///
  /// Sin esto la persona hablaba, esperaba el cierre de la sesión y recién
  /// después veía lo que dijo: parecía que no la estaba oyendo. Se muestra en
  /// la burbuja del usuario apenas llega la primera palabra.
  String _transcripcionEnCurso = '';
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
  bool get transcribiendo => _transcribiendo;

  /// El estado completo del micrófono, para pintar una sola cosa y no tres
  /// banderas sueltas que se contradigan.
  EdanIaEstadoVoz get estadoVoz {
    if (_escuchando) return EdanIaEstadoVoz.escuchando;
    if (_transcribiendo) return EdanIaEstadoVoz.transcribiendo;
    if (_pensando) return EdanIaEstadoVoz.pensando;
    return EdanIaEstadoVoz.inactivo;
  }

  bool get ocupado => _pensando || _escuchando || _transcribiendo;

  /// Texto que el modelo ya.emitió en este turno. La UI lo muestra como
  /// "escribiendo…" y lo reemplaza cuando llega el mensaje completo.
  String get respuestaEnCurso => _respuestaEnCurso;

  /// Lo que la persona está diciendo, en vivo.
  String get transcripcionEnCurso => _transcripcionEnCurso;

  /// Para los tests: simular lo que llega token a token sin armar un SSE.
  @visibleForTesting
  set debugRespuestaEnCurso(String v) => _respuestaEnCurso = v;

  /// Lo que se dibuja mientras el modelo escribe: nunca JSON, ni completo ni a
  /// medio escribir.
  ///
  /// Si lo que llega es prosa, se muestra tal cual. Si es el contrato, solo
  /// interesa su campo `respuesta`, que el modelo escribe primero: así la
  /// frase aparece apenas se cierra la comilla, sin que las llaves del
  /// envoltorio lleguen a verse nunca. Eso lo decide
  /// [edanRespuestaEnCurso], la misma separación que usa el turno terminado.
  ///
  /// Antes devolvía el buffer de tokens crudo, y por eso en el chat se veía
  /// `"siguiente_pregunta": null, ...` apareciendo letra por letra.
  String get respuestaEnCursoLegible => edanRespuestaEnCurso(_respuestaEnCurso);

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
    // La burbuja de lo que se oyó se reemplaza por el mensaje del usuario en
    // el mismo `notify`, así que no parpadea ni queda un texto suelto.
    _transcripcionEnCurso = '';
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
                _mensajes.add(EdanIaMensaje.asistente(
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

      // -----------------------------------------------------------------
      // Separación de canales.
      //
      // El chat pinta la *respuesta*, no el buffer de tokens. Ese buffer es
      // exactamente lo que traía el JSON entero cuando el modelo escribía el
      // contrato en el canal de texto, y era el motivo de que en la pantalla
      // apareciera `"siguiente_pregunta": null, ...` debajo de la frase.
      //
      // El puente ya parseó el envoltorio (`res.json`), así que se lo pasa
      // directo: es el contrato tal cual lo entendió el transporte. Si no
      // vino, se decodifica lo crudo. En los dos caminos lo que sale acá está
      // garantizado como prosa.
      // -----------------------------------------------------------------
      final crudo = _respuestaEnCurso.isNotEmpty
          ? _respuestaEnCurso
          : res.respuesta;
      final salida = decodificarSalida(crudo, envoltorio: res.json);

      // Canal de datos: el puente manda; si no vino, el que traía el texto
      // crudo. Los dos van por `parcheDesdeJson`, que además normaliza.
      var parche = EdanGroqService.parcheDesdeJson(res.parche ?? salida.parche);
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

      // Canal de texto: la frase ya separada. El prompt le pide al modelo una
      // frase para la persona y aparte UNA pregunta; antes la pregunta se
      // tiraba y la persona se quedaba sin saber qué contar, con la
      // conversación clavada en "Anotado." un turno tras otro.
      //
      // Ojo: `siguiente_pregunta` es hermano de `parche`, no está dentro. Por
      // eso se lee del envoltorio y no de `res.parche`, que es solo el objeto
      // de datos.
      var pregunta = salida.siguientePregunta ?? '';
      if (pregunta.isEmpty) pregunta = _siguientePreguntaDe(res.json);

      var util = salida.respuesta;

      // La pregunta va siempre al final: es lo que la persona tiene que
      // responder. Si ya venía pegada a la respuesta no se repite.
      if (pregunta.isNotEmpty && !_contiene(util, pregunta)) {
        util = util.isEmpty ? pregunta : '$util $pregunta';
      }

      // Un solo texto para la burbuja y para la voz. Antes había dos caminos y
      // no coincidían: cuando la prosa salía vacía, la burbuja caía al
      // "Anotado." de rescate pero la voz se callaba, así que la persona
      // hablaba y no oía nada de vuelta. Y el respaldo era `_respuestaEnCurso`,
      // que en el caso troublesome es el volcado crudo: leerlo por voz sería
      // leerse un JSON.
      //
      // El dato quedó anotado aunque el modelo hablara en JSON: preguntar
      // "¿me contás más?" haría que la persona repitiera lo que ya se tiene,
      // que es la única forma real de perder información.
      final texto = util.isNotEmpty
          ? util
          : (parche.vacio ? '¿Me contás un poco más?' : 'Anotado.');

      _mensajes.add(EdanIaMensaje.asistente(texto));

      // El paso de fotos es obligatorio y no se puede dejar en manos del
      // modelo: si la conversación terminó y no lo mencionó, lo dice el
      // provider. Una sola vez, y solo si de verdad ya no falta nada.
      if (listoParaFotos && !_mencionaFotos(texto) && !_yaCerrado) {
        _mensajes.add(EdanIaMensaje.asistente(_cierreFotos));
        await _voz.hablar(_cierreFotos);
      } else {
        // La respuesta se dice con voz: si la persona usó el micrófono, espera
        // una voz de vuelta, no un texto que tiene que leer. Nunca el volcado
        // del parche.
        if (texto.isNotEmpty) await _voz.hablar(texto);
      }
    } catch (e) {
      _error = e.toString();
      _mensajes.add(EdanIaMensaje.asistente(
        'Ocurrió un error inesperado. Revisá la conexión.',
        fallo: true,
      ));
    } finally {
      _pensando = false;
      // La burbuja de "escribiendo" se dibuja mientras esto tenga algo. Si
      // queda el último fragmento, la pantalla queda con un spinner eterno
      // debajo del último mensaje y parece que la app se colgó: el turno ya
      // terminó, la respuesta ya está en `_mensajes`.
      _respuestaEnCurso = '';
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
    // `mensaje` viene del puente y a veces trae el volcado de validación
    // (un 422 de Pydantic es JSON). Se separa como cualquier otro texto y se
    // acorta: un error no es una respuesta, no tiene que ocupar la pantalla.
    final detalle = edanProsaVisible(mensaje);
    if (detalle.isEmpty) return 'Falló la conexión.';
    final corto = detalle.length > 160
        ? '${detalle.substring(0, 160)}…'
        : detalle;
    return 'Falló la conexión: $corto';
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
    // Acá solo llega texto plano: el puente pidió JSON y no vino. Pero ese
    // texto también puede SER el contrato escrito en el canal de texto, así
    // que se separa igual que en el camino normal. Un solo filtro para los dos
    // casos es justamente lo que faltaba.
    final salida = decodificarSalida(prosa);

    _rescatePorExtractor(dicho);

    // Si el contrato venía dentro del texto, los datos no se pierden.
    if (!salida.parcheVacio) {
      final p = EdanGroqService.parcheDesdeJson(salida.parche);
      if (!p.vacio) {
        _borrador = aplicarParche(_borrador, p);
        _ultimoParche = p;
      }
    }

    final util = _esRespuestaUsable(salida.respuesta)
        ? salida.respuesta
        : '';

    var mostrar = util.isNotEmpty
        ? util
        : 'No pude entender eso. ¿Podés repetirlo?';

    // Si además trajo la pregunta siguiente, se le pega: sin ella la persona
    // no sabe qué contar y la conversación se clava. La pregunta la escribe el
    // modelo dentro de `respuesta` (ver `# Cómo preguntar` en el prompt); este
    // campo es el caso en que la separó a propósito.
    final pregunta = salida.siguientePregunta ?? '';
    if (util.isNotEmpty && pregunta.isNotEmpty && !_contiene(mostrar, pregunta)) {
      mostrar = '$mostrar $pregunta';
    }

    _descartado = true;
    _mensajes.add(EdanIaMensaje.asistente(mostrar, fallo: util.isEmpty));
    // La voz dice lo mismo que la burbuja, pregunta incluida: decir la frase
    // y dejar la pregunta en pantalla era que la persona escuche una respuesta
    // y no sepa que le toca contestar.
    if (mostrar.isNotEmpty && util.isNotEmpty) await _voz.hablar(mostrar);
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

  // La regla de "solo prosa" NO vive más acá: está en `edanProsaVisible` y en
  // `decodificarSalida` (`lib/services/edan_ia/edan_salida.dart`). Acá había
  // una copia propia, y con el tiempo divergió de la de la voz y de la del
  // streaming: cada camino tenía su filtro con sus agujeros distintos y la
  // pantalla terminó viendo el contrato entero. Un solo filtro, un solo lugar.

  /// La pregunta que el modelo dejó preparada en `siguiente_pregunta`.
  ///
  /// Vive al lado de `parche` dentro del JSON, no dentro del parche: es una
  /// decisión de la conversación, no un dato de la ficha. Vacía si vino `null`,
  /// que es lo que significa "no preguntes nada todavía".
  static String _siguientePreguntaDe(Map<String, dynamic>? json) {
    final cruda = json?['siguiente_pregunta'];
    if (cruda is! String) return '';
    // Pasa por el mismo filtro que la respuesta: la pregunta también se
    // muestra, así que tampoco puede traer estructura.
    return edanProsaVisible(cruda);
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


  /// Escucha del micrófono y responde con lo que oyó.
  Future<void> escucharYResponder() async {
    if (_escuchando || _pensando || _transcribiendo) return;
    _escuchando = true;
    _error = null;
    _escuchaCancelada = false;
    notifyListeners();

    // Aviso de que el micrófono se abrió: en el campo la persona necesita saber
    // que ya puede hablar, sin mirar la pantalla.
    _sonar(EdanPistaVoz.abriendo);

    // `AsistenteVozService.escuchar` resuelve cuando la sesión EMPIEZA (así
    // funciona `speech_to_text.listen`): la transcripción y el final llegan
    // después, por el canal de estado. Esperar el `await` y seguir como si ya
    // estuviera todo era el motivo de que el micrófono no hiciera nada: se
    // seguía con la transcripción vacía y nunca se mandaba al puente. La
    // espera real es la promesa que cierra `onFin`.
    String? oido;
    final finDeEscucha = Completer<void>();

    unawaited(_voz.escuchar(
      onResultado: (t) {
        oido = t;
        // Las palabras se pintan apenas llegan, no cuando se cierra la sesión
        // del reconocedor: con el texto en vivo la persona sabe que la están
        // oyendo mientras habla, y la espera de silencio ya no se siente.
        _transcripcionEnCurso = t;
        // Ya hay palabras: el micrófono se suelta y empieza la transcripción.
        // Soltarlo acá y no después es lo que hace que "transcribiendo" se vea
        // de verdad: si se espera al final de la sesión, los dos estados están
        // activos a la vez, `estadoVoz` prioriza "escuchando" y la pantalla nunca
        // muestra la espera más larga del ciclo.
        if (!_transcribiendo) {
          _escuchando = false;
          _transcribiendo = true;
          _sonar(EdanPistaVoz.transcribiendo);
        }
        notifyListeners();
      },
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
    final hablo = (oido?.trim().isNotEmpty ?? false);
    _transcribiendo = false;
    notifyListeners();
    if (hablo) _sonar(EdanPistaVoz.transcrito);

    // Lo que se cortó a mitad no se manda: una transcripción incompleta es peor
    // que no mandar nada, porque el modelo anotaría datos que la persona no dijo.
    if (_escuchaCancelada) {
      _transcripcionEnCurso = '';
      notifyListeners();
      return;
    }

    final texto = oido?.trim() ?? '';
    if (texto.isEmpty) {
      // No se oyó nada: la burbuja no puede quedarse con lo anterior.
      _transcripcionEnCurso = '';
      notifyListeners();
      return;
    }
    // No se repite lo dicho: la respuesta del modelo ya va a confirmar y
    // preguntar. Anunciar "Entendí: ..." por voz hace que la persona espere un
    // tono de máquina y rompe la conversación.
    await enviar(texto);
  }

  /// Abre la conversación: la IA habla primero.
  ///
  /// Se llama al abrir la pantalla. Escribió un mensaje **y** lo dice, porque
  /// quien llegó apretando el micrófono no va a leer: si la pantalla aparece en
  /// silencio, la primera impression es que la app no arrancó.
  ///
  /// Solo una vez: si la persona ya habló, no se interrumpe.
  Future<void> saludo() async {
    if (_mensajes.isNotEmpty || _saludoDado) return;
    _saludoDado = true;
    _mensajes.add(EdanIaMensaje.asistente(_saludo));
    notifyListeners();
    await _voz.hablar(_saludo);
  }

  void _sonar(EdanPistaVoz pista) {
    final s = _voz;
    if (s is EdanIaVozConPistas) unawaited(s.pista(pista));
  }

  /// Corta la escucha o el habla en curso.
  Future<void> detener() async {
    _escuchaCancelada = true;
    await _voz.detenerEscucha();
    await _voz.detener();
    _escuchando = false;
    _pensando = false;
    // Lo que quedó a medias se va de la pantalla: si se corta el turno a la
    // mitad, la burbuja de "escribiendo" no puede quedar clavada debajo del
    // último mensaje pareciendo que la app se colgó.
    _transcribiendo = false;
    _respuestaEnCurso = '';
    _transcripcionEnCurso = '';
    notifyListeners();
  }

  void reiniciar() {
    _borrador = EdanBorradorIa();
    _mensajes.clear();
    _respuestaEnCurso = '';
    _transcripcionEnCurso = '';
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

  /// Traduce y persiste la localidad con sus secciones activas (diseño limpio:
  /// solo tablas V2 vía `guardarTodo` + registro de fotos en memoria).
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
  ///
  /// Devuelve el `uuid_edan_localidad` persistido.
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

    final r = preparado ?? prepararGuardado();

    // Diseño limpio (solo RESP/V2): la única persistencia es `guardarTodo`
    // (cabecera + filas en 1 txn) + registro de fotos en memoria. Sin
    // escrituras legacy: el listado unificado lee `formularios`.
    final store = EdanStoreV2.instance;
    r.localidad.idUsuario = usuarioId;
    await store.guardarTodo(
      r.localidad,
      usuarioId: usuarioId,
      seccionesActivas: r.seccionesActivas,
      tipos: r.seccionesActivas,
    );
    await store.registrarFotosEnMemoria(r.localidad);
    return r.localidad.uuidEdanLocalidad ?? r.localidad.idLocal ?? '';
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
