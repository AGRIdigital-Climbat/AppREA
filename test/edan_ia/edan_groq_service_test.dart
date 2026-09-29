/// El cliente Groq sin tocar la red.
///
/// Lo que se prueba aquí es lo que puede salir mal de verdad: que el modelo
/// envuelva el JSON, que invente claves, que mande cifras como texto, y que el
/// razonamiento no llegue nunca a la interfaz. La capa HTTP se sustituye por un
/// `MockClient`, así que la suite no necesita internet ni token.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rea/services/edan_ia/edan_groq_service.dart';

void main() {
  group('jsonDesdeTexto: el modelo no siempre devuelve JSON limpio', () {
    test('JSON directo', () {
      final j = EdanGroqService.jsonDesdeTexto('{"respuesta":"hola"}');
      expect(j?['respuesta'], 'hola');
    });

    test('dentro de un bloque ```json', () {
      final j = EdanGroqService.jsonDesdeTexto('''
```json
{"respuesta":"hola","siguiente_pregunta":"¿dónde?"}
```
''');
      expect(j?['siguiente_pregunta'], '¿dónde?');
    });

    test('embebido en una frase', () {
      final j = EdanGroqService.jsonDesdeTexto(
        'Listo, anoté eso. {"respuesta":"anotado"} ¡Sigo!',
      );
      expect(j?['respuesta'], 'anotado');
    });

    test('con el razonamiento <think> adelante', () {
      final j = EdanGroqService.jsonDesdeTexto('''
<think>La persona dijo 40 niños, lo sumo al grupo de edad.{"parche":{"impactoPoblacion":{"Niño(a) 0-5 años":{"heridos":40}}}}
</think>
{"respuesta":"Anoté 40 heridos en niños.","parche":{"impactoPoblacion":{"Niño(a) 0-5 años":{"heridos":40}}}}
''');
      expect(j?['respuesta'], contains('40 heridos'));
      expect((j?['parche'] as Map)['impactoPoblacion'], isNotNull);
    });

    test('con <think> sin cerrar', () {
      expect(
        EdanGroqService.jsonDesdeTexto('<think>se cortó a mitad {"a":1'),
        isNull,
      );
    });

    test('prosa sin JSON devuelve null, no revienta', () {
      expect(EdanGroqService.jsonDesdeTexto('No entendí la pregunta.'), isNull);
      expect(EdanGroqService.jsonDesdeTexto(''), isNull);
    });
  });

  group('interpretarLineaSse', () {
    String linea(Map<String, dynamic> delta) => 'data: ${jsonEncode({
          'choices': [
            {'delta': delta}
          ]
        })}';

    test('el contenido normal no es razonamiento', () {
      final f = EdanGroqService.interpretarLineaSse(
        linea({'content': 'Anoté'}),
      );
      expect(f?.texto, 'Anoté');
      expect(f?.esRazonamiento, isFalse);
    });

    test('el razonamiento llega marcado, para que la UI lo oculte', () {
      final f = EdanGroqService.interpretarLineaSse(
        linea({'reasoning': 'la persona dijo 40 niños'}),
      );
      expect(f?.texto, 'la persona dijo 40 niños');
      expect(f?.esRazonamiento, isTrue);
    });

    test('"reasoning_content" también cuenta como razonamiento', () {
      final f = EdanGroqService.interpretarLineaSse(
        linea({'reasoning_content': 'pensando'}),
      );
      expect(f?.esRazonamiento, isTrue);
    });

    test('[DONE], comentarios y basura se ignoran', () {
      expect(EdanGroqService.interpretarLineaSse('data: [DONE]'), isNull);
      expect(EdanGroqService.interpretarLineaSse(': keep-alive'), isNull);
      expect(EdanGroqService.interpretarLineaSse(''), isNull);
      expect(EdanGroqService.interpretarLineaSse('data: {roto'), isNull);
      expect(EdanGroqService.interpretarLineaSse('event: message'), isNull);
    });

    test('delta vacío no emite un fragmento inútil', () {
      expect(EdanGroqService.interpretarLineaSse(linea({})), isNull);
      expect(EdanGroqService.interpretarLineaSse(linea({'content': ''})), isNull);
    });
  });

  group('parcheDesdeJson: la red de seguridad contra lo que inventa el modelo', () {
    test('acepta el vocabulario exacto', () {
      final p = EdanGroqService.parcheDesdeJson({
        'tipoEvento': {'inundacion': true},
        'impactoPoblacion': {
          'Niño(a) 0-5 años': {'fallecidos': 2}
        },
        'proteccion': {
          'Mujeres Embarazadas': {'mujeres': 10}
        },
        'necesidadesHumanitarias': {'Alimentos': true},
        'primeraRespuesta': {'Búsqueda': true},
        'serviciosBasicos': {
          'agua': {'danoParcial': 'Parcial'}
        },
      });
      expect(p.tipoEvento['inundacion'], isTrue);
      expect(p.impactoPoblacion['Niño(a) 0-5 años']!['fallecidos'], 2);
      expect(p.proteccion['Mujeres Embarazadas']!.mujeres, 10);
      expect(p.necesidadesHumanitarias['Alimentos'], isTrue);
      expect(p.primeraRespuesta['Búsqueda'], isTrue);
      expect(p.serviciosBasicos['agua']!['danoParcial'], 'Parcial');
    });

    test('tolera tildes, mayúsculas y espacios en las etiquetas', () {
      final p = EdanGroqService.parcheDesdeJson({
        'impactoPoblacion': {
          '  NIÑO (A) 0-5 AÑOS ': {'heridos': 3}
        },
        'necesidadesHumanitarias': {'alimentos': true},
      });
      expect(p.impactoPoblacion['Niño(a) 0-5 años']!['heridos'], 3);
      expect(p.necesidadesHumanitarias['Alimentos'], isTrue);
    });

    test('descarta etiquetas que no existen en el formulario', () {
      final p = EdanGroqService.parcheDesdeJson({
        'tipoEvento': {'meteorito': true},
        'impactoPoblacion': {
          'Ancianos': {'fallecidos': 5}
        },
        'proteccion': {
          'Extraterrestres': {'total': 3}
        },
        'necesidadesHumanitarias': {'Helado': true},
        'serviciosBasicos': {
          'teleportación': {'danoTotal': 'Total'}
        },
      });
      expect(p.tipoEvento, isEmpty);
      expect(p.impactoPoblacion, isEmpty);
      expect(p.proteccion, isEmpty);
      expect(p.necesidadesHumanitarias, isEmpty);
      expect(p.serviciosBasicos, isEmpty);
      expect(p.vacio, isTrue);
    });

    test('lee cifras que llegan como texto', () {
      final p = EdanGroqService.parcheDesdeJson({
        'totalAfectada': '350 personas',
        'impactoPoblacion': {
          'Adulto 19-60 años': {'fallecidos': '7 muertos'}
        },
        'agricultura': [
          {'cultivo': 'Maíz', 'hasAfectadas': '120 ha'}
        ],
      });
      expect(p.totalAfectada, 350);
      expect(p.impactoPoblacion['Adulto 19-60 años']!['fallecidos'], 7);
      expect(p.agricultura.single.hasAfectadas, 120);
    });

    test('un 0 explícito es un dato, no una ausencia', () {
      final p = EdanGroqService.parcheDesdeJson({
        'danosVivienda': [
          {'comunidad': 'San Pedro', 'danoParcial': 0}
        ],
      });
      expect(p.danosVivienda, hasLength(1));
      expect(p.danosVivienda.single.danoParcial, 0);
    });

    test('una cadena vacía NO pisa lo que ya había', () {
      // El parche solo lleva lo detectado: "" significa "no lo dijo".
      final p = EdanGroqService.parcheDesdeJson({
        'municipio': '',
        'alcalde': '   ',
        'observacionesX': 'x',
      });
      expect(p.municipio, isNull);
      expect(p.alcalde, isNull);
      expect(p.vacio, isTrue);
    });

    test('descarta filas 1:n sin ningún dato', () {
      final p = EdanGroqService.parcheDesdeJson({
        'infraVial': [
          {'via': 'Puente Viejo', 'danoTotal': 'Total'},
          {'via': '', 'danoTotal': ''},
        ],
        'educacion': [
          {'establecimiento': 'Escuela 1', 'suspensionClases': true}
        ],
      });
      expect(p.infraVial, hasLength(1));
      expect(p.educacion, hasLength(1));
      expect(p.educacion.single.suspensionClases, isTrue);
    });

    test('acepta "sí"/"no" como booleano', () {
      final p = EdanGroqService.parcheDesdeJson({
        'necesidadesHumanitarias': {'Alimentos': 'sí', 'Ropa de Cama': 'no'}
      });
      expect(p.necesidadesHumanitarias['Alimentos'], isTrue);
      expect(p.necesidadesHumanitarias['Ropa de Cama'], isFalse);
    });

    test('nunca acepta claves de sincronización', () {
      // El modelo no puede inventar `id_seccion`: se genera solo al guardar.
      final p = EdanGroqService.parcheDesdeJson({
        'infraVial': [
          {
            'via': 'Puente Viejo',
            'danoTotal': 'Total',
            'id_seccion': 'sv_ inventado',
            'idSeccion': 'sv_otro',
            'editado': 1,
            'sincronizado': 1,
          }
        ],
      });
      // `BchDanoVial` ni siquiera tiene esos campos: se descartan al construir.
      expect(p.infraVial, hasLength(1));
    });

    test('protección: un total sin desglose se guarda, no se reparte', () {
      final p = EdanGroqService.parcheDesdeJson({
        'proteccion': {
          'Mujeres Embarazadas': {'total': 25}
        },
      });
      final f = p.proteccion['Mujeres Embarazadas']!;
      expect(f.total, 25);
      expect(f.mujeres, isNull);
      expect(f.hombres, isNull);
      expect(f.tieneDesglose, isFalse);
    });

    test('JSON vacío o con tipos raros no rompe nada', () {
      expect(EdanGroqService.parcheDesdeJson({}).vacio, isTrue);
      expect(
        EdanGroqService.parcheDesdeJson({
          'infraVial': 'no soy una lista',
          'municipio': 123,
          'impactoPoblacion': 'nada',
        }).vacio,
        isTrue,
      );
    });
  });

  group('la llamada a Groq', () {
    /// Respuesta de chat completions normal, sin streaming.
    String cuerpo(String contenido) => jsonEncode({
          'choices': [
            {
              'message': {'content': contenido}
            }
          ]
        });

    test('arma la petición con el modelo, el system y stream=false', () async {
      late Map<String, dynamic> enviado;
      late Map<String, String> cabeceras;
      final cliente = MockClient((req) async {
        cabeceras = req.headers;
        enviado = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          cuerpo('{"respuesta":"anotado","parche":{"municipio":"Yapacaní"}}'),
          200,
        );
      });

      final s = EdanGroqService(cliente: cliente, apiKey: 'k');
      final turno = await s.turno(
        mensajes: [
          {'role': 'user', 'content': 'fueron 350 afectados'}
        ],
        instruccionSistema: 'eres el asistente EDAN',
      );

      expect(cabeceras['Authorization'], 'Bearer k');
      expect(cabeceras['Content-Type'], 'application/json');
      expect(enviado['model'], s.modelo);
      expect(enviado['stream'], isFalse);
      expect(enviado['reasoning_effort'], 'low');
      final msgs = enviado['messages'] as List;
      expect((msgs.first as Map)['role'], 'system');
      expect((msgs.last as Map)['content'], 'fueron 350 afectados');
      expect(turno.respuesta, 'anotado');
      expect(turno.parche.municipio, 'Yapacaní');
    });

    test('si Groq se equivoca, el turno llega sin parche pero con su texto', () async {
      final cliente = MockClient((_) async => http.Response(cuerpo('Hola'), 200));
      final turno = await EdanGroqService(cliente: cliente).turno(mensajes: const []);
      expect(turno.respuesta, 'Hola');
      expect(turno.sinNadaQueAnotar, isTrue);
    });

    test('un 401 se distingue para poder avisar de la credencial', () async {
      final cliente = MockClient((_) async => http.Response(
            jsonEncode({
              'error': {'message': 'Invalid API Key'}
            }),
            401,
          ));
      await expectLater(
        EdanGroqService(cliente: cliente).turno(mensajes: const []),
        throwsA(isA<EdanGroqError>()
            .having((e) => e.status, 'status', 401)
            .having((e) => e.esCredenciales, 'esCredenciales', isTrue)
            .having((e) => e.mensaje, 'mensaje', contains('Invalid API Key'))),
      );
    });

    test('un 429 reporta el error sin tragárselo', () async {
      final cliente = MockClient((_) async => http.Response('rate limited', 429));
      await expectLater(
        EdanGroqService(cliente: cliente).turno(mensajes: const []),
        throwsA(isA<EdanGroqError>().having((e) => e.status, 'status', 429)),
      );
    });

    test('el streaming separa el texto del razonamiento', () async {
      final sse = [
        'data: ${jsonEncode({'choices': [{'delta': {'reasoning': 'pienso'}}]})}',
        'data: ${jsonEncode({'choices': [{'delta': {'content': 'A'}}]})}',
        'data: ${jsonEncode({'choices': [{'delta': {'content': 'n'}}]})}',
        'data: [DONE]',
      ].join('\n');

      final cliente = MockClient((_) async =>
          http.Response.bytes(utf8.encode(sse), 200, headers: {}));

      final partes = await EdanGroqService(cliente: cliente)
          .streamTurno(mensajes: const [])
          .toList();

      expect(partes.first.esRazonamiento, isTrue);
      expect(partes.first.texto, 'pienso');
      expect(partes.skip(1).map((p) => p.texto).join(), 'An');
      expect(partes.skip(1).every((p) => !p.esRazonamiento), isTrue);
    });
  });
}
