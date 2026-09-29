/// Regresiones de la pantalla "Llenar por voz" que seReprodujeron en la
/// corrida real con micrófono, no en los tests de papel.
///
/// Los dos bugs tenían la misma raíz: el provider asumía que el transporte le
/// daba la respuesta completa y en realidad le daba dos pedazos desalineados.
///
/// 1. `AsistenteVozService.escuchar` hace `await _stt.listen(...)`, y en
///    `speech_to_text` ese future resuelve cuando la sesión EMPIEZA, no cuando
///    termina. El final llega por `onStatus` -> `onFin`. El provider esperaba
///    el final, así que seguía con la transcripción vacía y nunca mandaba nada
///    al puente: el micrófono no "funcionaba" para nada.
///
/// 2. El parche estructurado viaja en el evento `json`, pero algunos modelos
///    escriben el JSON en el canal de texto (`token`). El provider acumulaba
///    esos tokens en la burbuja visible sin filtrar, así que la persona leía
///    `{"parche": ...}` crudo. Como el token traía el JSON entero y el `done`
///    lo repetía, se veían dos JSON apilados.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rea/providers/edan_ia_borrador_provider.dart';
import 'package:rea/services/edan_ia/puente_service.dart';

/// Voz que se comporta como el plugin real: `escuchar` resuelve al empezar a
/// escuchar y el resultado/final llegan después, por el canal de estado.
class _VozSttReal implements EdanIaVoz {
  final dicho = <String>[];
  String? _aEscuchar;

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
  }) async {
    final t = _aEscuchar;
    // `speech_to_text` no devuelve la transcripción: hay que esperar a que
    // termine la sesión. El retardo modela una persona hablando.
    Timer(const Duration(milliseconds: 20), () {
      if (t != null) onResultado(t);
      onFin();
    });
  }

  void responder(String texto) => _aEscuchar = texto;
}

http.Response _sse(List<Map<String, dynamic>> eventos) => http.Response.bytes(
      utf8.encode([
        for (final e in eventos) 'data: ${jsonEncode(e)}',
        'data: [DONE]',
      ].join('\n')),
      200,
    );

Map<String, dynamic> _done({
  required String respuesta,
  Map<String, dynamic>? json,
  String formato = 'json',
}) =>
    {
      'tipo': 'done',
      'respuesta': respuesta,
      'json': json,
      'formato': formato,
      'modelo': 'm',
      'proveedor': 'p',
      'intentos': 1,
      'tokens': {'entrada': 10, 'salida': 10, 'razonamiento': 0},
      'avisos': <String>[],
    };

PuenteService _puente(MockClient c) => PuenteService(
      baseUrl: 'https://test.puente',
      apiKey: 'llave',
      client: c,
    );

/// Monta el provider contra un puente que siempre responde [turno].
EdanIaBorradorProvider _conTurno(
  http.Response turno, {
  required EdanIaVoz voz,
  List<String>? pedidos,
}) {
  final cliente = MockClient((req) async {
    pedidos?.add(req.body);
    return turno;
  });
  return EdanIaBorradorProvider(puente: _puente(cliente), voz: voz);
}

/// Los mensajes que ve la persona, en orden.
List<String> _visibles(EdanIaBorradorProvider p) =>
    p.mensajes.where((m) => !m.esUsuario).map((m) => m.texto).toList();

void main() {
  group('micrófono', () {
    test('envía lo que oyó cuando termina la sesión de escucha', () async {
      final voz = _VozSttReal()..responder('hubo una granizada muy fuerte');
      final pedidos = <String>[];
      final p = _conTurno(
        _sse([
          {
            'tipo': 'token',
            'texto': '¿Cuántas personas quedaron afectadas?',
          },
          _done(respuesta: '¿Cuántas personas quedaron afectadas?'),
        ]),
        voz: voz,
        pedidos: pedidos,
      );

      await p.escucharYResponder();

      expect(pedidos, isNotEmpty,
          reason: 'la transcripción tiene que llegar al puente');
      expect(pedidos.first, contains('granizada'));
      expect(_visibles(p), isNotEmpty,
          reason: 'y la persona tiene que leer una respuesta');
    });

    test('no deja el micrófono trabado si no se oyó nada', () async {
      final voz = _VozSttReal(); // nunca responden: silencio
      final pedidos = <String>[];
      final p = _conTurno(
        _sse([_done(respuesta: 'hola')]),
        voz: voz,
        pedidos: pedidos,
      );

      await p.escucharYResponder();

      expect(p.escuchando, isFalse, reason: 'el micrófono tiene que soltarse');
      expect(p.ocupado, isFalse);
      expect(pedidos, isEmpty, reason: 'silencio no se envía como mensaje');
    });

    test('detener corta la escucha y no manda la transcripción a medias',
        () async {
      final voz = _VozSttReal()..responder('hubo una granizada');
      final pedidos = <String>[];
      final p = _conTurno(
        _sse([_done(respuesta: 'ok')]),
        voz: voz,
        pedidos: pedidos,
      );

      final escucha = p.escucharYResponder();
      await p.detener();
      await escucha;

      expect(p.escuchando, isFalse);
      expect(pedidos, isEmpty,
          reason: 'lo que se cortó a mitad no se manda incompleto');
    });
  });

  group('JSON crudo en pantalla', () {
    // Lo que hizo el modelo con "pasó una granizada": en vez de hablar, escribió
    // el objeto del parche en el canal de texto. El `done` lo trae de nuevo.
    const parche = {
      'tipoEvento': {'granizada': true},
      'totalAfectada': 12,
    };
    final jsonCrudo = jsonEncode({'parche': parche});

    test('el parche anotado igual aunque el modelo hable en JSON', () async {
      final voz = _VozSttReal();
      final p = _conTurno(
        _sse([
          {'tipo': 'token', 'texto': jsonCrudo},
          {'tipo': 'json', 'json': {'parche': parche}},
          _done(respuesta: jsonCrudo, json: {'parche': parche}),
        ]),
        voz: voz,
      );

      await p.enviar('pasó una granizada');

      // Lo importante: el dato quedó en el borrador.
      expect(p.ultimoParche.vacio, isFalse,
          reason: 'el parche tiene que haberse aplicado');
      expect(p.borrador.tipoEvento['granizada'], isTrue);
      expect(p.borrador.totalAfectada, 12);
    });

    test('nunca se muestra el JSON en la burbuja', () async {
      final voz = _VozSttReal();
      final p = _conTurno(
        _sse([
          {'tipo': 'token', 'texto': jsonCrudo},
          {'tipo': 'json', 'json': {'parche': parche}},
          _done(respuesta: jsonCrudo, json: {'parche': parche}),
        ]),
        voz: voz,
      );

      await p.enviar('pasó una granizada');

      for (final texto in _visibles(p)) {
        expect(texto.trim(), isNot(startsWith('{')),
            reason: 'se mostró JSON crudo: $texto');
        expect(texto, isNot(contains('"parche"')),
            reason: 'se mostró JSON crudo: $texto');
        expect(texto, isNot(contains('"evento"')),
            reason: 'se mostró JSON crudo: $texto');
      }
    });

    test('no aparecen dos respuestas del mismo turno', () async {
      final voz = _VozSttReal();
      final p = _conTurno(
        _sse([
          {'tipo': 'token', 'texto': jsonCrudo},
          {'tipo': 'json', 'json': {'parche': parche}},
          _done(respuesta: jsonCrudo, json: {'parche': parche}),
        ]),
        voz: voz,
      );

      await p.enviar('pasó una granizada');

      // Un turno no puede repetir la misma respuesta: el texto del modelo entra
      // una sola vez, sin eco del `done` ni del token duplicado.
      final textos = _visibles(p);
      expect(textos.toSet().length, textos.length,
          reason: 'la misma respuesta aparece duplicada: $textos');
    });

    test('la prosa normal se sigue mostrando', () async {
      final voz = _VozSttReal();
      final p = _conTurno(
        _sse([
          {'tipo': 'token', 'texto': 'Anotado. ¿A qué hora cayó?'},
          _done(respuesta: 'Anotado. ¿A qué hora cayó?'),
        ]),
        voz: voz,
      );

      await p.enviar('pasó una granizada');

      expect(_visibles(p).first, 'Anotado. ¿A qué hora cayó?');
    });
  });

  group('la conversación sigue', () {
    // El prompt le pide al modelo una frase para la persona y aparte UNA
    // pregunta en `siguiente_pregunta`. La pregunta viajaba en el JSON y se
    // perdía: la conversación era "Anotado." y "Anotado." sin que nadie supiera
    // qué tenía que contar.
    http.Response _turnoConPregunta({
      String respuesta = 'Anotado.',
      String? siguientePregunta = '¿A qué hora cayó la granizada?',
      Map<String, Object?>? parche,
    }) {
      final json = <String, dynamic>{
        'respuesta': respuesta,
        if (siguientePregunta != null) 'siguiente_pregunta': siguientePregunta,
        if (parche != null) 'parche': parche,
      };
      return _sse([
        {'tipo': 'token', 'texto': respuesta},
        {'tipo': 'json', 'json': json},
        _done(respuesta: respuesta, json: json),
      ]);
    }

    test('la pregunta del modelo llega a la burbuja', () async {
      final voz = _VozSttReal();
      final p = _conTurno(
        _turnoConPregunta(parche: const {'tipoEvento': {'granizada': true}}),
        voz: voz,
      );

      await p.enviar('pasó una granizada');

      expect(_visibles(p).first, contains('¿A qué hora cayó la granizada?'));
    });

    test('la pregunta también se dice por voz', () async {
      final voz = _VozFalsa();
      final p = _conTurno(
        _turnoConPregunta(parche: const {'tipoEvento': {'granizada': true}}),
        voz: voz,
      );

      await p.enviar('pasó una granizada');

      // Si la pregunta no se dice, la persona que habló al micrófono se queda
      // mirando la pantalla esperando que algo suene.
      expect(voz.dicho.join(' '), contains('¿A qué hora cayó la granizada?'));
    });

    test('no repite la pregunta si ya venía en la respuesta', () async {
      final voz = _VozFalsa();
      final p = _conTurno(
        _turnoConPregunta(
          respuesta: 'Anotado. ¿A qué hora cayó la granizada?',
          parche: const {'tipoEvento': {'granizada': true}},
        ),
        voz: voz,
      );

      await p.enviar('pasó una granizada');

      final texto = _visibles(p).first;
      expect(texto, 'Anotado. ¿A qué hora cayó la granizada?',
          reason: 'la pregunta no debe quedar pegada dos veces');
    });

    test('si el modelo no pregunta, no se inventa una', () async {
      final voz = _VozFalsa();
      final p = _conTurno(
        _turnoConPregunta(
          siguientePregunta: null,
          parche: const {'tipoEvento': {'granizada': true}},
        ),
        voz: voz,
      );

      await p.enviar('pasó una granizada');

      expect(_visibles(p).first, 'Anotado.');
    });

    test('una pregunta que viene en JSON no se muestra', () async {
      final voz = _VozFalsa();
      final p = _conTurno(
        _turnoConPregunta(
          respuesta: 'Anotado.',
          siguientePregunta: '{"pregunta": "¿cuántos?"}',
          parche: const {'tipoEvento': {'granizada': true}},
        ),
        voz: voz,
      );

      await p.enviar('pasó una granizada');

      expect(_visibles(p).first, isNot(contains('"')));
    });
  });
}

/// Voz que sí registra lo que se habla, como una persona en el campo.
class _VozFalsa implements EdanIaVoz {
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

