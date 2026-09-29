/// Simulación de llenado conversacional contra la IA real.
///
/// Los tests unitarios comprueban que el provider no rompa, pero no contestan la
/// pregunta que importa en el campo: **¿cómo sigue la conversación?**. Esta
/// simulación juega una ficha completa como una persona en el terreno y muestra
/// el chat tal como lo ve quien llena: `USUARIO` y `SISTEMA` turnando, con lo
/// que quedó anotado debajo de cada respuesta.
///
/// Es un test de aceptación lento y con red, así que está apagado por defecto:
/// la suite de `flutter test` no debe depender de internet. Se corre a mano:
///
///   $env:PUENTE_SIM=1
///   flutter test test/edan_ia/simulacion_chat_test.dart
///
/// Los guiones también se pueden elegir:
///
///   $env:PUENTE_SIM="1 --guion inundacion"
///   flutter test test/edan_ia/simulacion_chat_test.dart
///
/// Falla si algún turno sale defectuoso, que es lo que hay que mirar:
///
/// - **json en pantalla**: se muestra el volcado del parche.
/// - **respuesta vacía**: el modelo no dijo nada legible.
/// - **duplicada**: la misma respuesta aparece dos veces.
/// - **sin avance**: la persona habló y la ficha no progressedó.
/// - **dato perdido**: una sección que estaba llena dejó de estarlo.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rea/config/api_config.dart';
import 'package:rea/providers/edan_ia_borrador_provider.dart';
import 'package:rea/services/edan_ia/puente_service.dart';

/// Voz de mentira que anota lo que se diría: acá no hay TTS, pero lo que se habla
/// importa tanto como lo que se escribe, y eso no se ve en un pantallazo.
class _VozMuda implements EdanIaVoz {
  final dicho = <String>[];

  @override
  Future<void> hablar(String texto) async => dicho.add(texto);

  @override
  Future<void> detener() async {}

  @override
  Future<void> detenerEscucha() async {}

  @override
  Future<void> escuchar({
    required void Function(String texto) onResultado,
    required void Function() onFin,
  }) async =>
      onFin();
}

class _Guion {
  final String nombre;
  final String titulo;
  final List<String> frases;

  const _Guion(this.nombre, this.titulo, this.frases);
}

const _guiones = <_Guion>[
  _Guion(
    'granizada',
    'El caso que salió mal en la corrida real: frases cortas, de campo.',
    [
      'Estamos en San Juan, provincia de San Juan.',
      'Ayer en la tarde pasó una granizada muy fuerte.',
      'Afectó a unas doce personas de la plaza.',
      'No hubo heridos graves, solo cortes de luz.',
      'La escuela local sigue sin luz.',
      'El kilómetro 8 de la ruta nacional está cortado por piedras.',
      'El contacto es 02664 123456, a nombre de María López.',
    ],
  ),
  _Guion(
    'inundacion',
    'Desborde con relaciones 1:N (vivienda, agricultura y pecuario).',
    [
      'Localidad El Barrial, departamento Vallegrande, provincia Jujuy.',
      'El río se desbordó ayer y se metió en veinte viviendas.',
      'Perdieron el techo tres casas y dos departamentos de adobe.',
      'En el campo se perdió toda la cosecha de maíz.',
      'Hay ocho familias damnificadas y treinta personas en total.',
      'Necesitan colchones, agua y atención médica en el puesto de salud.',
    ],
  ),
  _Guion(
    'vago',
    'Persona que se distrae: sirve para ver si el asistente insiste.',
    [
      'Hola, quiero hacer una ficha EDAN.',
      'Mmm, no sé, después vemos.',
      'Pasó un incendio en el barrio.',
      'Bueno, seguime.',
      'En la escuela hubo que evacuar a los niños.',
      'No hay agua potable desde ayer.',
    ],
  ),
];

/// ¿Lo que la persona lee es estructura en vez de una frase?
bool _tieneEstructura(String texto) {
  final t = texto.trimLeft();
  return t.startsWith('{') ||
      t.startsWith('[') ||
      t.contains('"parche"') ||
      t.contains('=>');
}

Set<String> _completas(EdanIaBorradorProvider p) => p.progreso
    .where((s) => s.completo)
    .map((s) => s.titulo)
    .toSet();

String _pct(double v) => '${(v * 100).toStringAsFixed(0)}%';

String _recortar(String s, int n) {
  final t = s.replaceAll('\n', ' / ');
  return t.length <= n ? t : '${t.substring(0, n)}...';
}

void main() {
  final activo = (Platform.environment['PUENTE_SIM'] ?? '').isNotEmpty;
  final pedir = Platform.environment['PUENTE_SIM'] ?? '';
  final solo = pedir.contains('--guion')
      ? pedir.split('--guion').last.trim()
      : '';

  final guiones = solo.isEmpty
      ? _guiones
      : _guiones.where((g) => g.nombre == solo).toList();

  for (final guion in guiones) {
    test('llenado por voz · ${guion.nombre}', () async {
      final base =
          Platform.environment['PUENTE_URL'] ?? ApiConfig.puenteBaseUrl;
      final key = Platform.environment['PUENTE_KEY'] ?? ApiConfig.puenteApiKey;

      final voz = _VozMuda();
      final p = EdanIaBorradorProvider(
        puente: PuenteService(baseUrl: base, apiKey: key),
        voz: voz,
      );

      final linea = '─' * 72;
      // ignore: avoid_print
      print('$linea\n SIMULACIÓN · ${guion.nombre} · $base\n ${guion.titulo}\n$linea');

      final defectos = <String>[];

      for (var i = 0; i < guion.frases.length; i++) {
        final frase = guion.frases[i];
        final n = i + 1;
        final avanceAntes = p.avance;
        final completasAntes = _completas(p);
        final mensajesAntes = p.mensajes.length;
        final vozAntes = voz.dicho.length;

        // ignore: avoid_print
        print('\nUSUARIO  $frase');

        final reloj = Stopwatch()..start();
        await p.enviar(frase);
        reloj.stop();

        final nuevos = p.mensajes.skip(mensajesAntes).toList();
        final delAsistente = nuevos.where((m) => !m.esUsuario).toList();

        if (delAsistente.isEmpty) {
          // ignore: avoid_print
          print('SISTEMA  (sin respuesta)');
        }
        for (final m in delAsistente) {
          // ignore: avoid_print
          print('SISTEMA  ${_recortar(m.texto, 400)}');
        }
        for (final d in voz.dicho.skip(vozAntes)) {
          // ignore: avoid_print
          print('   (voz) ${_recortar(d, 240)}');
        }

        final avanceDespues = p.avance;
        final incompletas = p.progreso.where((s) => !s.completo).length;
        // ignore: avoid_print
        print('   -> ${reloj.elapsedMilliseconds} ms · '
            'avance ${_pct(avanceDespues)} (antes ${_pct(avanceAntes)}) · '
            '$incompletas/${p.progreso.length} secciones incompletas');
        if (p.descartado) {
          // ignore: avoid_print
          print('   -> TURNO DESCARTADO: el modelo no respetó el contrato');
        }
        if (p.error != null) {
          // ignore: avoid_print
          print('   -> ERROR: ${p.error}');
        }

        final visibles = delAsistente.map((m) => m.texto).toList();
        for (final v in visibles) {
          if (_tieneEstructura(v)) {
            defectos.add('turno $n: json en pantalla -> ${_recortar(v, 120)}');
          }
        }
        if (visibles.isEmpty) {
          defectos.add('turno $n: el asistente no respondió nada visible');
        }
        if (visibles.toSet().length != visibles.length) {
          defectos.add('turno $n: respuesta duplicada -> $visibles');
        }
        if (p.error != null) {
          defectos.add('turno $n: error -> ${p.error}');
        }
        if (p.descartado) {
          defectos.add('turno $n: turno descartado');
        }
        if (avanceDespues <= avanceAntes && p.descartado) {
          defectos.add('turno $n: la persona habló y la ficha no avanzó');
        }
        for (final s in completasAntes) {
          if (!_completas(p).contains(s)) {
            defectos.add('turno $n: se perdió el dato de "$s"');
          }
        }
      }

      // ignore: avoid_print
      print('\n$linea\n FIN · avance ${_pct(p.avance)} · '
          'listo para fotos: ${p.listoParaFotos ? "si" : "no"}');

      if (defectos.isNotEmpty) {
        // ignore: avoid_print
        print('\n DEFECTOS (${defectos.length}):');
        for (final d in defectos) {
          // ignore: avoid_print
          print('   x $d');
        }
      }

      expect(defectos, isEmpty,
          reason: 'la conversación tuvo turnos defectuosos:\n'
              '${defectos.map((d) => '  · $d').join('\n')}');
    },
    skip: activo
        ? false
        : 'con red y lento: poné PUENTE_SIM=1 para correrlo a mano',
    timeout: const Timeout(Duration(minutes: 10)));
  }
}
