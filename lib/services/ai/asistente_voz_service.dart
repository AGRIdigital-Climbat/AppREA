import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../permission_service.dart';

class AsistenteVozService {
  static final AsistenteVozService instance = AsistenteVozService._();
  AsistenteVozService._();

  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();
  bool _sttInitialized = false;
  bool _ttsReady = false;
  Completer<void>? _ttsCompleter;
  VoidCallback? _activeFin;
  String? ultimoErrorStt;

  bool get soportaVoz => !Platform.isWindows;

  Future<void> initTts() async {
    if (_ttsReady) return;
    if (!soportaVoz) return;
    try {
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {}
    try {
      final idiomas = await _tts.getLanguages;
      final lista = idiomas is List
          ? idiomas.map((e) => e.toString()).toList()
          : <String>[];
      String idioma = 'es-ES';
      if (lista.isNotEmpty && !lista.contains('es-ES')) {
        final es = lista.where((l) => l.startsWith('es')).toList();
        idioma = es.isNotEmpty ? es.first : lista.first;
      }
      await _tts.setLanguage(idioma);
    } catch (e) {
      debugPrint('[TTS] No se pudo configurar idioma: $e');
    }
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(_completarHabla);
    _tts.setCancelHandler(_completarHabla);
    _tts.setErrorHandler((msg) {
      debugPrint('[TTS] error: $msg');
      _completarHabla();
    });
    _ttsReady = true;
  }

  void _completarHabla() {
    if (_ttsCompleter != null && !_ttsCompleter!.isCompleted) {
      _ttsCompleter!.complete();
    }
  }

  Future<void> hablar(String texto) async {
    if (!soportaVoz) return;
    if (!_ttsReady) await initTts();
    if (texto.trim().isEmpty) return;

    // iOS comparte la sesión de audio entre reproducción y grabación: si
    // quedó una escucha viva, el TTS habla sobre el micro abierto (y el
    // reconocedor padea el audio). Se cierra la escucha antes de hablar.
    try {
      if (_sttInitialized && _stt.isListening) await _stt.stop();
    } catch (_) {}

    // Espera acotada segun la longitud del texto: si el motor TTS nunca
    // dispara el callback de finalizacion, no se bloquea el microfono.
    final espera = (2000 + texto.length * 60).clamp(3000, 60000).toInt();
    _ttsCompleter = Completer<void>();
    try {
      await _tts.speak(texto);
      await _ttsCompleter!.future.timeout(Duration(milliseconds: espera));
    } catch (e) {
      debugPrint('[TTS] Error al hablar: $e');
    } finally {
      _completarHabla();
    }
  }

  Future<void> detener() async {
    if (!soportaVoz) return;
    if (_ttsCompleter != null && !_ttsCompleter!.isCompleted) {
      _ttsCompleter!.complete();
    }
    await _tts.stop();
  }

  Future<bool> initStt() async {
    if (!soportaVoz) return false;
    if (_sttInitialized) return true;

    final permiso = await PermissionService.requestMicrophonePermission();
    if (!permiso) {
      ultimoErrorStt = 'Permiso de microfono denegado';
      debugPrint('[STT] Permiso de microfono denegado.');
      return false;
    }

    try {
      _sttInitialized = await _stt.initialize(
        onError: (e) {
          ultimoErrorStt = e.errorMsg;
          debugPrint('[STT] error: ${e.errorMsg}');
        },
        onStatus: (s) {
          debugPrint('[STT] status: $s');
          if (s == 'done' || s == 'notListening') {
            final fin = _activeFin;
            _activeFin = null;
            fin?.call();
          }
        },
      );
    } catch (e) {
      ultimoErrorStt = e.toString();
      debugPrint('[STT] No se pudo inicializar: $e');
      _sttInitialized = false;
    }
    return _sttInitialized;
  }

  Future<void> escuchar({
    required Function(String texto) onResultado,
    required Function() onFin,
  }) async {
    if (!soportaVoz) {
      onFin();
      return;
    }

    if (!_sttInitialized) {
      final ok = await initStt();
      if (!ok) {
        onFin();
        return;
      }
    }

    // Si el TTS no llegó a disparar su callback de fin (interrupión de
    // llamada en iOS), el micro abriría sobre la sesión de reproducción y
    // speech_to_text fallaría. Se corta el habla pendiente antes de escuchar.
    try {
      await _tts.stop();
    } catch (_) {}
    _completarHabla();

    var finalizado = false;
    void finalizar() {
      if (finalizado) return;
      finalizado = true;
      _activeFin = null;
      onFin();
    }

    // El `onStatus` global de initStt invoca este callback cuando el plugin
    // termina la sesion (silencio, sin resultado, error), garantizando que el
    // microfono nunca quede atascado en estado de escucha.
    _activeFin = finalizar;

    try {
      await _stt.listen(
        onResult: (result) {
          if (result.recognizedWords.isNotEmpty) {
            onResultado(result.recognizedWords);
          }
          if (result.finalResult) {
            finalizar();
          }
        },
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          listenFor: const Duration(seconds: 60),
          // De 8 s a 3 s: es cuánto espera el reconocedor después de que
          // dejás de hablar antes de dar el resultado por terminado. Con 8 s
          // la persona terminaba de hablar, se quedaba mirando la pantalla
          // ocho segundos con nada, y recién ahí aparecía lo que dijo. Tres
          // segundos siguen alcanzando para una pausa natural sin cortar la
          // frase, y el texto además ya se muestra mientras se habla.
          pauseFor: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      ultimoErrorStt = e.toString();
      debugPrint('[STT] Error al escuchar: $e');
      finalizar();
    }
  }

  Future<void> detenerEscucha() async {
    if (!soportaVoz) return;
    await _stt.stop();
  }

  bool get escuchando => _stt.isListening;
}
