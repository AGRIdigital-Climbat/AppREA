/// Separación de canales: qué se puede ver, qué se anota y qué se le pregunta.
///
/// El caso que originó este archivo es este, tal como llegó al chat:
///
/// ```json
/// {"respuesta":"Se registró una granizada muy fuerte.",
///  "siguiente_pregunta":null,
///  "parche":{"tipoEvento":{"granizada":true}}}
/// ```
///
/// Eso no es una respuesta para la persona: es el contrato entero pintado como
/// si fuera prosa. Acá se prueba que cada campo llega a su destino y que la
/// frase que queda no contiene nada estructural, ni completa ni a medio
/// escribir.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rea/services/edan_ia/edan_salida.dart';

/// El JSON del reporte, reproducido carácter por carácter.
const _reportado = '''
{
  "respuesta": "Se registró una granizada muy fuerte.",
  "siguiente_pregunta": null,
  "parche": {
    "tipoEvento": {
      "granizada": true
    }
  }
}''';

/// Marca que [texto] no puede contener estructura. Todas las aserciones de
/// prosa pasan por acá para que la regla no dependa de cada test.
void _sinJson(String texto, String porque) {
  if (texto.contains('{') ||
      texto.contains('}') ||
      texto.contains('[') ||
      texto.contains(']') ||
      texto.contains('"') ||
      texto.contains('```')) {
    throw StateError('Se escapó estructura en "$porque": $texto');
  }
}

void main() {
  group('el JSON que se vio en el chat', () {
    test('se separa en sus tres canales', () {
      final s = decodificarSalida(_reportado);

      expect(s.respuesta, 'Se registró una granizada muy fuerte.');
      expect(s.siguientePregunta, isNull);
      expect(s.parche['tipoEvento'], isA<Map>());
      expect(s.vinoJson, isTrue);
      expect(s.contratoRoto, isFalse);
      _sinJson(s.respuesta, 'respuesta');
    });

    test('el dato queda en el parche, no en la frase', () {
      final s = decodificarSalida(_reportado);

      expect(s.respuesta, isNot(contains('tipoEvento')));
      expect(s.parcheVacio, isFalse);
      // Y el borrador recibe el mapa tal cual, sin tener que recorrer texto.
      expect((s.parche['tipoEvento'] as Map)['granizada'], isTrue);
    });

    test('una pregunta también se puede separar', () {
      final s = decodificarSalida('''
{"respuesta":"Anotado.",
 "siguiente_pregunta":"¿A qué hora pasó?",
 "parche":{"tipoEvento":{"granizada":true}}}
''');

      expect(s.respuesta, 'Anotado.');
      expect(s.siguientePregunta, '¿A qué hora pasó?');
      expect(s.preguntaVacia, isFalse);
      _sinJson(s.siguientePregunta!, 'pregunta');
    });
  });

  group('mezcla de prosa y objetos', () {
    test('un objeto dentro de frase no termina en la frase', () {
      final s = decodificarSalida(
        'Se registró la granizada {"tipoEvento":{"granizada":true}} '
        'y quedó anotado.',
      );

      expect(s.respuesta, isNot(contains('tipoEvento')));
      expect(s.respuesta, contains('granizada'));
      _sinJson(s.respuesta, 'prosa con objeto adentro');
    });

    test('un objeto que no es del contrato se descarta entero', () {
      final s = decodificarSalida(
        'Anotado. {"no":"pertenece","al":"contrato"} Seguimos.',
      );

      expect(s.respuesta, 'Anotado. Seguimos.');
      expect(s.respuesta, isNot(contains('pertenece')));
      expect(s.respuesta, isNot(contains('"')));
      expect(s.respuesta, contains('Anotado.'));
      expect(s.respuesta, contains('Seguimos.'));
      expect(s.parcheVacio, isTrue);
      _sinJson(s.respuesta, 'objeno ajeno al contrato');
    });

    test('si el envoltorio trae respuesta, la prosa de alrededor es eco',
        () {
      final s = decodificarSalida(
        'Anotado. {"respuesta":"Se registró la granizada.",'
        '"siguiente_pregunta":null,"parche":{}}',
      );

      // No se pinta "Anotado. Se registró la granizada.": una sola frase.
      expect(s.respuesta, 'Se registró la granizada.');
      _sinJson(s.respuesta, 'eco del envoltorio');
    });

    test('si el envoltorio no trae respuesta, se usa la prosa de alrededor',
        () {
      final s = decodificarSalida(
        'Quedó cortada la ruta. {"siguiente_pregunta":"¿A qué hora?",'
        '"parche":{"tipoEvento":{"camino":"cortado"}}}',
      );

      expect(s.respuesta, 'Quedó cortada la ruta.');
      expect(s.siguientePregunta, '¿A qué hora?');
      expect(s.parcheVacio, isFalse);
      _sinJson(s.respuesta, 'prosa sin respuesta propia');
    });

    test('prosa sola pasa igual, sin cambios', () {
      const frases = [
        'Anotado.',
        '¿Y a qué hora pasó?',
        'Se registró una granizada muy fuerte.',
        'Quedaron 12 familias sin luz, en la calle Lavalle 1400.',
        'Anotado, pero "el puente" quedó cortado.',
        'Mi papá dijo: "quedó partido".',
        'Medidas: 12,5 metros de largo y 3 de ancho.',
      ];
      for (final f in frases) {
        expect(decodificarSalida(f).respuesta, f,
            reason: 'la frase se tiene que conservar entera: "$f"');
      }
    });
  });

  group('contrato roto', () {
    test('JSON que no parsea no llega a la pantalla', () {
      final s = decodificarSalida('{"respuesta":"Anotado"');

      _sinJson(s.respuesta, 'json incompleto');
      expect(s.contratoRoto, isTrue);
      expect(s.parcheVacio, isTrue);
    });

    test('se rescata la prosa que estuviera alrededor', () {
      final s = decodificarSalida('Anotado {"respuesta": ');

      expect(s.respuesta, contains('Anotado'));
      _sinJson(s.respuesta, 'prosa alrededor de json roto');
    });

    test('llaves sueltas no son prosa', () {
      final s = decodificarSalida('}\n{\nnull');

      expect(s.respuesta, isEmpty);
      expect(s.parcheVacio, isTrue);
    });

    test('bloques cercados no son prosa', () {
      final s = decodificarSalida(
        '```json\n{"respuesta":"Anotado."}\n```',
      );

      // Decodificó el bloque: ese sí es el contrato.
      expect(s.vinoJson, isTrue);
      expect(s.respuesta, 'Anotado.');

      final sinDecodificar =
          decodificarSalida('```json\n{"clave":"y sin cierre"');
      _sinJson(sinDecodificar.respuesta, 'bloque sin cerrar');
    });
  });

  group('mientras se escribe', () {
    test('ningún corte del JSON reportado deja estructura en pantalla', () {
      // Cortes reales, como llegan token a token.
      final cortes = <String>[];
      for (var i = 1; i <= _reportado.length; i += 7) {
        cortes.add(_reportado.substring(0, i));
      }
      cortes.addAll([
        '{',
        '{"res',
        '{"respuesta":"Se',
        '{"respuesta":"Se registró una granizada muy fuerte."',
        '{"respuesta":"Se registró una granizada muy fuerte.",\n'
            '"siguiente_pregunta":null',
        '```json\n{"respuesta":"Se registró una granizada muy fuerte."',
        '```json\n{\n  "respuesta": "Se registró"',
      ]);

      for (final c in cortes) {
        final enCurso = edanRespuestaEnCurso(c);
        _sinJson(enCurso, 'corte a ${c.length} caracteres');
      }
    });

    test('la respuesta se ve apenas se cierra su comilla', () {
      // El JSON todavía no parsea, pero la frase ya está entera.
      final parcial = '{"respuesta":"Se registró una granizada muy fuerte.",'
          '"siguiente_pregunta":null,"parche":{"tipoEvento":{"graniz';

      expect(
        edanRespuestaEnCurso(parcial),
        'Se registró una granizada muy fuerte.',
      );
    });

    test('antes de cerrar la comilla no se muestra nada', () {
      expect(edanRespuestaEnCurso('{"respuesta":"Se registr'), isEmpty);
      expect(edanRespuestaEnCurso('{'), isEmpty);
      expect(edanRespuestaEnCurso(''), isEmpty);
    });

    test('prosa en curso sí se muestra', () {
      expect(edanRespuestaEnCurso('Anotado'), 'Anotado');
      expect(edanRespuestaEnCurso('  Anotado. '), 'Anotado.');
      // Si atrás viene el volcado, se corta ahí.
      expect(
        edanRespuestaEnCurso('Anotado.\n{"parche":{"tipoEvento"'),
        'Anotado.',
      );
    });

    test('un objeto adentro de un string no lo cierra antes de tiempo', () {
      // Caso del detector de balanceo: la llave está entre comillas.
      final s = decodificarSalida(
        '{"nota":"quedó {partido} el techo","respuesta":"Anotado."}',
      );

      expect(s.respuesta, 'Anotado.');
    });

    test('la pregunta se lee del texto en curso también', () {
      const parcial = '{"respuesta":"Anotado.",'
          '"siguiente_pregunta":"¿A qué hora pasó?",';

      expect(edanPreguntaEnCurso(parcial), '¿A qué hora pasó?');
      expect(edanPreguntaEnCurso('{"respuesta":"Anotado."}'), isNull);
      expect(edanPreguntaEnCurso('Anotado. sin contrato'), isNull);
    });
  });

  group('casos límite', () {
    test('texto vacío no rompe', () {
      expect(decodificarSalida('').respuesta, isEmpty);
      expect(decodificarSalida('   ').respuesta, isEmpty);
      expect(edanRespuestaEnCurso(''), isEmpty);
    });

    test('un solo número no es prosa', () {
      expect(decodificarSalida('42').respuesta, '42');
      expect(decodificarSalida('{"clave":42}').respuesta, isEmpty);
    });

    test('cadena JSON en lugar de objeto se toma como prosa', () {
      expect(decodificarSalida('"hola"').respuesta, '"hola"');
    });

    test('JSON que es lista no se confunde con envoltorio', () {
      final s = decodificarSalida('[1,2,3]');
      expect(s.vinoJson, isTrue);
      expect(s.respuesta, isEmpty);
      expect(s.parcheVacio, isTrue);
    });

    test('idempotente: filtrar dos veces da lo mismo', () {
      const frase = 'Se registró una granizada muy fuerte. ¿A qué hora?';
      final una = edanProsaVisible(frase);
      expect(edanProsaVisible(una), una);
      expect(una, frase);
    });
  });

  group('alias de claves en inglés', () {
    // El caso real: `nemotron-3-ultra-550b` devuelve el objeto correcto pero
    // con `response` en vez de `respuesta`, y el turno llegaba vacío.
    test('acepta `response` como `respuesta`', () {
      final salida = decodificarSalida(
        '{"response": "Se registró una inundación.", "parche": {}}',
      );
      expect(salida.respuesta, 'Se registró una inundación.');
      expect(salida.parche, isEmpty);
    });

    test('acepta el alias dentro del envoltorio del puente', () {
      final salida = decodificarSalida(
        '{"response": "Anotado. ¿Cuántas familias?", "parche": {"municipio": "Yapacaní"}}',
        envoltorio: const {
          'response': 'Anotado. ¿Cuántas familias?',
          'parche': {'municipio': 'Yapacaní'},
        },
      );
      expect(salida.respuesta, 'Anotado. ¿Cuántas familias?');
      expect(salida.parche['municipio'], 'Yapacaní');
    });

    test('acepta `next_question` como `siguiente_pregunta`', () {
      final salida = decodificarSalida(
        '{"respuesta": "Listo.", "next_question": "¿Y el agua?", "parche": {}}',
      );
      expect(salida.siguientePregunta, '¿Y el agua?');
    });

    test('el contrato en español gana si vienen los dos', () {
      final salida = decodificarSalida(
        '{"respuesta": "La buena.", "response": "La mala.", "parche": {}}',
      );
      expect(salida.respuesta, 'La buena.');
    });

    test('`patch` se lee como parche', () {
      final salida = decodificarSalida(
        '{"respuesta": "Anotado.", "patch": {"totalAfectada": 350}}',
      );
      expect(salida.parche['totalAfectada'], 350);
    });

    test('el streaming lee `response` antes de que cierre el objeto', () {
      expect(
        edanRespuestaEnCurso('{"response": "Se registró una inundación.",'),
        'Se registró una inundación.',
      );
    });

    test('el streaming de la pregunta acepta `next_question`', () {
      expect(
        edanPreguntaEnCurso('{"respuesta": "x", "next_question": "¿Y el agua?"'),
        '¿Y el agua?',
      );
    });
  });
}
