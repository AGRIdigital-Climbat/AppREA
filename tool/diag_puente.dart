// Diagnóstico del puente: por qué los proveedores NVIDIA devuelven `respuesta`
// vacía (`respuesta_no_string`) y por qué hay turnos de 112 s.
//
// Corre N llamadas cortas en `formato: 'texto'` (que no depende del envelope
// JSON) y registra tokens de razonamiento, para ver si el modelo gasta la
// salida en razonamiento y deja `contenido` vacío.
//
//   dart run tool/diag_puente.dart --n=8
library;

import 'package:rea/config/api_config.dart';
import 'package:rea/services/edan_ia/puente_models.dart';
import 'package:rea/services/edan_ia/puente_service.dart';

void main(List<String> args) async {
  final n = int.tryParse(_arg(args, '--n') ?? '') ?? 8;
  final formato = _arg(args, '--formato') ?? 'texto';

  // Relleno para simular el tamaño real del prompt del asistente EDAN, a ver
  // en qué punto el Nemotron deja de salir. Con prompt corto sale casi la
  // mitad de las veces; con el prompt largo de EDAN no salió ninguna.
  final rellenoN = int.tryParse(_arg(args, '--largo') ?? '') ?? 0;
  final relleno = rellenoN > 0
      ? '\n\n' +
          List.filled(
            rellenoN,
            'Regla de la ficha que el modelo debe tener presente.',
          ).join('\n')
      : '';

  final puente = PuenteService(
    baseUrl: ApiConfig.puenteBaseUrl,
    apiKey: ApiConfig.puenteApiKey,
  );

  for (var i = 0; i < n; i++) {
    final reloj = Stopwatch()..start();
    try {
      final res = await puente.enviarStream(
        PuenteRequest(
          instruccion: (formato == 'json'
                  ? '''
Devolvé un objeto JSON con EXACTAMENTE dos claves: "respuesta" (string) y
"parche" (objeto). Nada antes ni después.

Ejemplo de forma:
{"respuesta": "Hola, ¿cómo estás?", "parche": {}}
'''
                  : 'Contestá con una sola frase corta, sin comillas.') +
              relleno,
          mensajes: const [Mensaje('user', 'Decime hola.')],
          formato: formato,
          maxTokens: 300,
          temperatura: 0.1,
          razonamiento: 'off',
          intentosJson: 0,
        ),
        onToken: (_) {},
      );
      reloj.stop();
      // ignore: avoid_print
      print('${i + 1}. ${reloj.elapsedMilliseconds.toString().padLeft(6)}ms  '
          '${res.modelo.padRight(38)} '
          'in=${res.tokens.entrada} out=${res.tokens.salida} '
          'raz=${res.tokens.razonamiento}  avisos=${res.avisos}');
      // ignore: avoid_print
      print('   cruda=[${_corta(res.respuesta, 220)}]');
      // ignore: avoid_print
      print('   claves=${res.json?.keys.toList()} '
          'respuestaTipo=${res.json?['respuesta'].runtimeType}');
    } catch (e) {
      reloj.stop();
      // ignore: avoid_print
      print('${i + 1}. ${reloj.elapsedMilliseconds.toString().padLeft(6)}ms  '
          'ERROR $e');
    }
  }
}

String? _arg(List<String> args, String nombre) {
  for (final a in args) {
    if (a.startsWith('$nombre=')) return a.substring(nombre.length + 1);
  }
  return null;
}

String _corta(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}...';
