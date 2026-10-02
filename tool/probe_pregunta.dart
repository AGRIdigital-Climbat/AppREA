// Sonda descartable: manda los turnos de la simulación al puente y vuelca el
// envelope crudo, para distinguir dos cosas que el transcript no alcanza a
// decir: si `siguiente_pregunta` viene `null` del modelo, o si se pierde en el
// camino. Replica el historial del provider (frase del usuario ANTES de llamar,
// respuesta del asistente DESPUÉS).
//
//   dart run tool/probe_pregunta.dart
library;

import 'package:rea/config/api_config.dart';
import 'package:rea/models/edan_borrador_ia.dart';
import 'package:rea/services/edan_ia/edan_fusion.dart';
import 'package:rea/services/edan_ia/edan_groq_prompt.dart';
import 'package:rea/services/edan_ia/edan_groq_service.dart';
import 'package:rea/services/edan_ia/edan_salida.dart';
import 'package:rea/services/edan_ia/puente_models.dart';
import 'package:rea/services/edan_ia/puente_service.dart';

const _frases = [
  'Estamos en San Juan, provincia de San Juan.',
  'Ayer en la tarde pasó una granizada muy fuerte.',
  'Afectó a unas doce personas de la plaza.',
  'No hubo heridos graves, solo cortes de luz.',
  'La escuela local sigue sin luz.',
  'El kilómetro 8 de la ruta nacional está cortado por piedras.',
  'El contacto es 02664 123456, a nombre de María López.',
];

void main() async {
  final puente = PuenteService(
    baseUrl: ApiConfig.puenteBaseUrl,
    apiKey: ApiConfig.puenteApiKey,
  );
  var borrador = EdanBorradorIa();
  final historial = <Mensaje>[];

  for (final frase in _frases) {
    historial.add(Mensaje('user', frase));

    final progreso = progresoGlobal(borrador);
    final instruccion = edanGroqInstruccion(
      pendientes: seccionesIncompletas(progreso, maximo: 3),
      progreso: progreso,
      borrador: borrador,
    );

    final reloj = Stopwatch()..start();
    final res = await puente.enviarStream(
      PuenteRequest(
        instruccion: instruccion,
        mensajes: historial,
        formato: 'json',
        maxTokens: ApiConfig.puenteMaxTokens,
        temperatura: ApiConfig.puenteTemperatura,
        razonamiento: 'off',
        intentosJson: 1,
      ),
      onToken: (_) {},
    );
    reloj.stop();

    final env = res.json ?? const <String, dynamic>{};
    final pregunta = env['siguiente_pregunta'];
    final parche = env['parche'];
    final salida = decodificarSalida(res.respuesta, envoltorio: res.json);
    historial.add(Mensaje('assistant', salida.respuesta));

    // ignore: avoid_print
    print('--- ${reloj.elapsedMilliseconds} ms · formato=${res.formato} '
        '· intentos=${res.intentos} · modelo=${res.modelo} '
        '· proveedor=${res.proveedor} · avisos=${res.avisos}');
    // ignore: avoid_print
    print('    USUARIO  $frase');
    // ignore: avoid_print
    print('    SISTEMA  ${_corta(salida.respuesta)}');
    // ignore: avoid_print
    print('    PREGUNTA ${pregunta ?? "(null)"}'
        '   [salida.siguientePregunta=${salida.siguientePregunta ?? "null"}]');
    // ignore: avoid_print
    print('    PARCHE   ${parche is Map ? parche.keys.toList() : parche}'
        '   [salida.parche=${salida.parche.keys.toList()}]');
    // ignore: avoid_print
    print('    RESP cruda ${_corta(res.respuesta)}');

    final p = EdanGroqService.parcheDesdeJson(
      parche is Map
          ? parche.cast<String, dynamic>()
          : const <String, dynamic>{},
    );
    if (!p.vacio) borrador = aplicarParche(borrador, p);
  }
}

String _corta(String s) => s.length <= 220 ? s : '${s.substring(0, 220)}...';
