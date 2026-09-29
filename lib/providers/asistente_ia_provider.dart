import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai/asistente_chat_message.dart';
import '../services/ai/asistente_ia_service.dart';
import '../services/ai/asistente_voz_service.dart';
import '../services/auth_service.dart';

class AsistenteIAProvider extends ChangeNotifier {
  final AsistenteIAService _iaService = AsistenteIAService.instance;
  final AsistenteVozService _vozService = AsistenteVozService.instance;

  List<AsistenteChatMessage> _mensajes = [];
  bool _isActive = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isProcessing = false;
  bool _cancelado = false;
  bool _vozHabilitada = true;
  String _bufferIA = '';
  String _textoEscuchado = '';
  bool _huboError = false;
  bool _conversacionIniciada = false;
  bool _esperandoParaHablar = false;
  bool _detenerEscuchaSolicitado = false;
  int _intentosVacios = 0;
  String? _ultimaPreguntaFallida;

  // Contexto del formulario (EDAN wizard)
  final int? grupoId;
  String? contextoPantalla;

  Timer? _timeoutTimer;
  StreamSubscription<String>? _streamSub;

  AsistenteIAProvider({this.grupoId, this.contextoPantalla});

  List<AsistenteChatMessage> get mensajes => _mensajes;
  bool get isActive => _isActive;
  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  bool get isProcessing => _isProcessing;
  bool get cancelado => _cancelado;
  bool get vozHabilitada => _vozHabilitada;
  String get bufferIA => _bufferIA;
  String get textoEscuchado => _textoEscuchado;
  bool get huboError => _huboError;
  bool get esperandoParaHablar => _esperandoParaHablar;

  Future<void> init() async {
    _mensajes = [];
    _isActive = true;
    _cancelado = false;
    _huboError = false;
    _ultimaPreguntaFallida = null;
    _isProcessing = false;
    _isSpeaking = false;
    _isListening = false;
    _bufferIA = '';
    _textoEscuchado = '';
    _conversacionIniciada = false;
    _esperandoParaHablar = false;
    _detenerEscuchaSolicitado = false;
    _intentosVacios = 0;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      _vozHabilitada = prefs.getBool('asistente_voz_habilitada') ?? true;
    } catch (e) {
      debugPrint('[AsistenteIA] No se pudieron leer preferencias: $e');
      _vozHabilitada = true;
    }
    notifyListeners();
  }

  Future<void> toggleVoz() async {
    _vozHabilitada = !_vozHabilitada;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('asistente_voz_habilitada', _vozHabilitada);

    if (!_vozHabilitada) {
      // Modo texto: sin voz ni reconocimiento.
      _detenerEscuchaSolicitado = true;
      _esperandoParaHablar = false;
      _isSpeaking = false;
      _isListening = false;
      notifyListeners();
      await _vozService.detener();
      await _vozService.detenerEscucha();
      return;
    }

    // Modo voz: hablar y escuchar.
    _detenerEscuchaSolicitado = false;
    notifyListeners();
    if (_isActive && !_isProcessing && !_isSpeaking) {
      await _activarModoVoz();
    }
  }

  // Al activar el modo voz: si ya hay conversacion, indica al usuario que haga
  // su pregunta; si aun no hay ninguna, repite el saludo/pregunta inicial.
  // En ambos casos luego comienza a escuchar.
  Future<void> _activarModoVoz() async {
    if (_cancelado) return;

    final hayPreguntaUsuario = _mensajes.any((m) => m.role == 'user');
    final String indicacion;
    if (hayPreguntaUsuario) {
      indicacion = 'Haz tu pregunta.';
      _mensajes.add(
        AsistenteChatMessage(role: 'assistant', content: indicacion),
      );
    } else {
      indicacion = _mensajes.isNotEmpty && _mensajes.last.role == 'assistant'
          ? _mensajes.last.content
          : _buildSaludoInicial();
      if (_mensajes.isEmpty) {
        _mensajes.add(
          AsistenteChatMessage(role: 'assistant', content: indicacion),
        );
      }
    }
    _bufferIA = indicacion;
    notifyListeners();
    await _hablar(indicacion);
    await _esperarAntesDeEscuchar();

    if (!_cancelado && _vozHabilitada) await _iniciarEscuchaCiclo();
  }

  void cancelar() {
    _cancelado = true;
    _isActive = false;
    _isListening = false;
    _isSpeaking = false;
    _isProcessing = false;
    _conversacionIniciada = false;
    _timeoutTimer?.cancel();
    _streamSub?.cancel();
    _vozService.detener();
    _vozService.detenerEscucha();
    notifyListeners();
  }

  void cancelarPeticion() {
    _timeoutTimer?.cancel();
    _streamSub?.cancel();
    _isProcessing = false;
    _huboError = true;
    notifyListeners();
  }

  String _obtenerSaludo() {
    final hora = DateTime.now().hour;
    if (hora < 12) return 'Buenos días';
    if (hora < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  String _obtenerNombreUsuario() {
    final nombre =
        AuthService.instance.userName ??
        AuthService.instance.currentToken?.nombre ??
        '';
    if (nombre.isEmpty) return '';
    return nombre.split(' ').first;
  }

  String _buildSaludoInicial() {
    final saludo = _obtenerSaludo();
    final nombre = _obtenerNombreUsuario();
    final nombreStr = nombre.isNotEmpty ? ' $nombre' : '';
    if (contextoPantalla != null) {
      return '$saludo$nombreStr, estás en la sección $contextoPantalla. '
          '¿Qué ayuda necesitas?';
    }
    return '$saludo$nombreStr, ¿qué quieres aprender o qué duda tienes?';
  }

  Future<void> iniciarConversacion() async {
    if (!isActive || _conversacionIniciada) return;
    _conversacionIniciada = true;

    _isProcessing = false;
    _bufferIA = '';
    _esperandoParaHablar = false;
    _detenerEscuchaSolicitado = false;
    notifyListeners();

    final saludo = _buildSaludoInicial();

    _mensajes.add(AsistenteChatMessage(role: 'assistant', content: saludo));
    _bufferIA = saludo;
    notifyListeners();

    if (_vozHabilitada) {
      await _hablar(saludo);
      await _esperarAntesDeEscuchar();
      if (!_cancelado) await _iniciarEscuchaCiclo();
    }
  }

  Future<void> enviarPregunta(String textoUsuario) async {
    if (_cancelado || textoUsuario.trim().isEmpty) return;

    // Detiene cualquier escucha activa para que el microfono no capture el TTS.
    _vozService.detenerEscucha();
    _isListening = false;
    _esperandoParaHablar = false;

    debugPrint('[AsistenteIA] Usuario: "$textoUsuario"');
    _mensajes.add(AsistenteChatMessage(role: 'user', content: textoUsuario));
    _isProcessing = true;
    _bufferIA = '';
    _huboError = false;
    _ultimaPreguntaFallida = null;
    _intentosVacios = 0;
    notifyListeners();

    final texto = textoUsuario.trim();
    final pregunta = texto;

    final completer = Completer<void>();
    String respuestaCompleta = '';
    List<AsistenteFuente> fuentesRespuesta = [];
    Map<String, AsistenteCita> citasRespuesta = {};

    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 90), () {
      if (!completer.isCompleted) {
        _streamSub?.cancel();
        completer.complete();
      }
    });

    _streamSub = _iaService
        .chatStream(
          pregunta: pregunta,
          grupoId: grupoId,
          termino: contextoPantalla,
          onFuentes: (fuentes) => fuentesRespuesta = fuentes,
          onCitas: (citas) => citasRespuesta = citas,
        )
        .listen(
          (token) {
            respuestaCompleta += token;
            _bufferIA = respuestaCompleta;
            notifyListeners();
          },
          onError: (e) {
            debugPrint('[AsistenteIA] Error stream: $e');
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
        );

    await completer.future;
    _timeoutTimer?.cancel();
    _streamSub = null;

    if (_cancelado) return;

    if (respuestaCompleta.isEmpty) {
      _huboError = true;
      _ultimaPreguntaFallida = textoUsuario;
      const error = 'No se obtuvo respuesta. Toca el ícono para reintentar.';
      _bufferIA = error;
      _mensajes.add(
        const AsistenteChatMessage(role: 'assistant', content: error),
      );
    } else {
      _mensajes.add(
        AsistenteChatMessage(
          role: 'assistant',
          content: respuestaCompleta,
          fuentes: fuentesRespuesta.isEmpty ? null : fuentesRespuesta,
          citas: citasRespuesta.isEmpty ? null : citasRespuesta,
        ),
      );
    }

    _isProcessing = false;
    notifyListeners();

    if (_vozHabilitada && respuestaCompleta.isNotEmpty && !_huboError) {
      await _hablar(respuestaCompleta);
      await _esperarAntesDeEscuchar();
      // Si el usuario calló la lectura (detenerHabla), no reabrir el micrófono
      // automáticamente; se queda el banner "Presiona para volver a hablar".
      if (!_cancelado && _vozHabilitada && !_esperandoParaHablar) {
        await _iniciarEscuchaCiclo();
      }
    }
  }

  Future<void> reintentar() async {
    if (_ultimaPreguntaFallida != null) {
      final pregunta = _ultimaPreguntaFallida!;
      _huboError = false;
      _ultimaPreguntaFallida = null;
      // Remover el último mensaje de error
      if (_mensajes.isNotEmpty &&
          _mensajes.last.content.contains('reintentar')) {
        _mensajes.removeLast();
      }
      notifyListeners();
      await enviarPregunta(pregunta);
    }
  }

  String _stripMarkdown(String text) {
    var r = text;
    // Negrita y cursiva
    r = r.replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1');
    r = r.replaceAll(RegExp(r'__(.+?)__'), r'$1');
    r = r.replaceAll(RegExp(r'\*(.+?)\*'), r'$1');
    r = r.replaceAll(RegExp(r'_(.+?)_'), r'$1');
    // Encabezados
    r = r.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
    // Viñetas y guiones: -, *, •, ▪, ●, +, seguido de espacio
    r = r.replaceAll(RegExp(r'^[\s]*[-\*•▪●+]\s+', multiLine: true), '');
    // Listas numericas: 1. 2. 3. o 1) 2) 3)
    r = r.replaceAll(RegExp(r'^\s*\d+[.)]\s+', multiLine: true), '');
    // Checkbox: [ ] o [x]
    r = r.replaceAll(RegExp(r'^\s*\[[ x]\]\s*', multiLine: true), '');
    // Blockquotes
    r = r.replaceAll(RegExp(r'^>\s*', multiLine: true), '');
    // Imagenes y links
    r = r.replaceAll(RegExp(r'!\[([^\]]*)\]\([^)]+\)'), r'$1');
    r = r.replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1');
    // Codigo inline
    r = r.replaceAll(RegExp(r'`([^`]+)`'), r'$1');
    // Tachado
    r = r.replaceAll(RegExp(r'~~(.+?)~~'), r'$1');
    // Separadores horizontales
    r = r.replaceAll(RegExp(r'^[-*_]{3,}$', multiLine: true), '');
    // Tablas simples: quitar pipes y guiones de separacion
    r = r.replaceAll(RegExp(r'^\|', multiLine: true), '');
    r = r.replaceAll(RegExp(r'\|$', multiLine: true), '');
    r = r.replaceAll(RegExp(r'^[\s:\-|]+$', multiLine: true), '');
    // Colapsar saltos de linea multiples
    r = r.replaceAll(RegExp(r'\n{2,}'), '\n');
    return r.trim();
  }

  Future<void> _hablar(String texto) async {
    if (!_vozHabilitada) return;
    final textoLimpio = _stripMarkdown(texto);
    if (textoLimpio.isEmpty) return;
    _isSpeaking = true;
    notifyListeners();
    try {
      await _vozService.hablar(textoLimpio);
    } catch (e) {
      debugPrint('[AsistenteIA] Error TTS: $e');
    } finally {
      _isSpeaking = false;
      notifyListeners();
    }
  }

  Future<void> _esperarAntesDeEscuchar() async {
    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<void> _iniciarEscuchaCiclo() async {
    if (_cancelado || !_vozHabilitada) return;

    _detenerEscuchaSolicitado = false;
    _esperandoParaHablar = false;
    _isListening = true;
    _textoEscuchado = '';
    notifyListeners();

    await _vozService.escuchar(
      onResultado: (texto) {
        _textoEscuchado = texto;
        notifyListeners();
      },
      onFin: () {
        _isListening = false;
        notifyListeners();
        if (_cancelado || _isProcessing || _detenerEscuchaSolicitado) return;
        if (_textoEscuchado.trim().isNotEmpty) {
          _intentosVacios = 0;
          enviarPregunta(_textoEscuchado);
        } else {
          _reintentarEscucha();
        }
      },
    );
  }

  Future<void> _reintentarEscucha() async {
    if (_cancelado || !_vozHabilitada || _detenerEscuchaSolicitado) return;
    if (_intentosVacios >= 2) {
      _esperandoParaHablar = true;
      notifyListeners();
      return;
    }
    _intentosVacios++;
    await Future.delayed(const Duration(milliseconds: 500));
    if (!_cancelado &&
        _vozHabilitada &&
        !_isProcessing &&
        !_detenerEscuchaSolicitado) {
      await _iniciarEscuchaCiclo();
    }
  }

  void toggleListening() {
    if (_isListening) {
      _detenerEscuchaSolicitado = true;
      _esperandoParaHablar = false;
      _vozService.detenerEscucha();
      _isListening = false;
      notifyListeners();
    } else if (!isProcessing && !isSpeaking && _vozHabilitada) {
      _iniciarEscuchaCiclo();
    }
  }

  Future<void> cancelarEscucha() async {
    _detenerEscuchaSolicitado = true;
    _esperandoParaHablar = true;
    _isListening = false;
    _textoEscuchado = '';
    _intentosVacios = 0;
    await _vozService.detenerEscucha();
    notifyListeners();
  }

  // Detiene la lectura del TTS (modo voz) sin cerrar el asistente y sin abrir
  // el micrófono; queda el banner "Presiona para volver a hablar".
  Future<void> detenerHabla() async {
    _detenerEscuchaSolicitado = true;
    _esperandoParaHablar = true;
    _intentosVacios = 0;
    _isSpeaking = false;
    _isListening = false;
    _vozService.detenerEscucha();
    await _vozService.detener();
    notifyListeners();
  }

  // Reproduce una respuesta específica en voz, sin cambiar de modo y sin
  // activar la escucha posterior (los íconos por mensaje).
  Future<void> reproducirMensaje(String texto) async {
    if (!_vozService.soportaVoz) return;
    final textoLimpio = _stripMarkdown(texto);
    if (textoLimpio.isEmpty) return;
    _vozService.detenerEscucha();
    if (_isSpeaking) await _vozService.detener();
    _isSpeaking = true;
    notifyListeners();
    try {
      await _vozService.hablar(textoLimpio);
    } catch (e) {
      debugPrint('[AsistenteIA] Error reproducir: $e');
    } finally {
      _isSpeaking = false;
      notifyListeners();
    }
  }
}
