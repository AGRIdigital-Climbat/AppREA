/// El bucle de conversación: puente → parche → borrador.
///
/// Lo que se prueba aquí es el comportamiento que hace que el asistente sea
/// una conversación y no un formulario: que el modelo decide cuándo preguntar,
/// que nunca pisa lo que la persona ya escribió, y que un turno que no se
/// entiende no rompe nada. El transporte real del puente (`PuenteService`) se
/// cubre por separado en `puente_service_test.dart`; acá se le miente a través
/// de un `MockClient` con bodies en el contrato SSE del puente.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rea/models/edan_borrador_ia.dart';
import 'package:rea/providers/edan_ia_borrador_provider.dart';
import 'package:rea/services/edan_ia/puente_service.dart';

/// Voz de mentira: registra lo que se dijo sin tocar los plugins.
class _VozFalsa implements EdanIaVoz {
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
    if (t != null) onResultado(t);
    onFin();
  }

  void responder(String texto) => _aEscuchar = texto;
}

/// Cliente del puente en las pruebas: URL y clave fijas, transporte fake.
PuenteService _puente(MockClient cliente) => PuenteService(
      baseUrl: 'https://test.puente',
      apiKey: 'llave',
      client: cliente,
    );

/// Un body SSE del puente: líneas `data: ` cerradas por `[DONE]`.
///
/// Va como bytes UTF-8 a propósito: `http.Response(String, ...)` codifica en
/// Latin-1 y rompe los acentos del SSE, que el servicio decodifica en UTF-8.
http.Response _sse(List<Map<String, dynamic>> eventos) => http.Response.bytes(
      utf8.encode([
        for (final e in eventos) 'data: ${jsonEncode(e)}',
        'data: [DONE]',
      ].join('\n')),
      200,
    );

/// El evento `done` del puente, con el envelope mínimo.
Map<String, dynamic> _doneDe({
  required String respuesta,
  Map<String, dynamic>? json,
  String formato = 'json',
}) =>
    {
      'tipo': 'done',
      'respuesta': respuesta,
      'json': json,
      'formato': formato,
      'modelo': 'openai/gpt-oss-20b',
      'proveedor': 'Groq-adrian',
      'intentos': 1,
      'tokens': {'entrada': 10, 'salida': 10, 'razonamiento': 0},
      'avisos': <String>[],
    };

/// Un turno JSON completo en SSE: token de la prosa, evento `json` y `done`.
///
/// [pregunta] se embebe en `respuesta`: el contrato del puente no tiene
/// `siguiente_pregunta`; la pregunta va en la prosa.
http.Response _sseJson({
  String respuesta = '',
  String? pregunta,
  Map<String, Object?>? parche,
}) {
  final texto = pregunta == null || pregunta.isEmpty
      ? respuesta
      : '${respuesta.isEmpty ? '' : '$respuesta '}$pregunta';
  final json = parche == null ? null : <String, dynamic>{'parche': parche};
  return _sse([
    {'tipo': 'token', 'texto': texto},
    if (json != null) {'tipo': 'json', 'json': json},
    _doneDe(respuesta: texto, json: json),
  ]);
}

/// Un turno que el puente degradó a texto (`formato: "texto"`): la respuesta
/// vale, pero no hay parche y el cliente cae al extractor.
http.Response _sseTexto(String prosa) => _sse([
      {'tipo': 'token', 'texto': prosa},
      _doneDe(respuesta: prosa, json: null, formato: 'texto'),
    ]);

/// La respuesta de `POST /puente` (el `enviar` de la pasada de reparación).
http.Response _envioJson({Map<String, Object?>? parche}) => http.Response(
      jsonEncode({
        'respuesta': '',
        'json': parche == null ? null : {'parche': parche},
        'formato': 'json',
        'modelo': 'm',
        'proveedor': 'p',
        'intentos': 1,
        'tokens': {'entrada': 1, 'salida': 1, 'razonamiento': 0},
        'avisos': <String>[],
      }),
      200,
    );

/// Monta un provider cuyo puente responde [primera] en el primer turno y nada
/// desde la segunda llamada (la pasada de reparación queda sin datos).
EdanIaBorradorProvider _conRespuesta(
  http.Response primera, {
  _VozFalsa? voz,
  List<String>? pedidos,
}) {
  var llamadas = 0;
  final cliente = MockClient((req) async {
    if (llamadas++ > 0) return http.Response.bytes(const [], 200);
    pedidos?.add(req.body);
    return primera;
  });
  return EdanIaBorradorProvider(
    puente: _puente(cliente),
    voz: voz ?? _VozFalsa(),
  );
}

/// El bloque "lo que todavía falta" de la instrucción de una petición.
String _pendientes(String cuerpoPeticion) {
  final j = jsonDecode(cuerpoPeticion) as Map<String, dynamic>;
  final instruccion = (j['instruccion'] as String?) ?? '';
  final i = instruccion.indexOf('# Lo que todavía falta');
  if (i < 0) return '';
  final resto = instruccion.substring(i);
  final j2 = resto.indexOf('Lo que ya está anotado');
  return j2 < 0 ? resto : resto.substring(0, j2);
}

/// Deja el borrador con todas las secciones completas.
///
/// Se hace a mano y no con quince parches porque lo que se está probando es el
/// cierre, no la fusión. Si el cierre dependiera de que las quince secciones
/// queden arriba del 0.6 por falar, cada cambio de umbral en el cálculo de
/// progreso rompería esta prueba sin que nada esté realmente mal.
void _completar(EdanBorradorIa b) {
  b
    ..departamento = 'Santa Cruz'
    ..provincia = 'Ichilo'
    ..municipio = 'Yapacaní'
    ..alcalde = 'María López'
    ..fechaEvento = '2026-02-10'
    ..horaEvento = '14:30'
    ..responsableNombre = 'Juan Pérez'
    ..totalAfectada = 350
    ..totalFamiliasAfectadas = 80
    ..totalFamiliasDamnificadas = 30
    ..tipoEvento = {for (final k in kEdanClavesEvento) k: k == 'inundacion'};
  b.impactoPoblacion = [
    for (final g in kEdanGruposEdad)
      BchImpactoFila(g)
        ..fallecidos = 1
        ..heridos = 2
        ..desaparecidos = 1
        ..observaciones = 'reportado',
  ];
  b.proteccion = [
    for (final g in kEdanGruposProteccion)
      BchProteccionFila(g)
        ..total = 4
        ..mujeres = 2
        ..hombres = 2
        ..observaciones = 'reportado',
  ];
  b.serviciosBasicos = {
    for (final e in kEdanServiciosBasicos.entries)
      e.key: BchServicioDetalle()
        ..danoParcial = 'daño'
        ..danoTotal = 'daño'
        ..necesidades = 'reparación'
        ..observaciones = 'reportado',
  };
  b.necesidadesHumanitarias = [
    for (final n in kEdanNecesidadesHumanitarias) BchNecesidadFila(n)..si = true,
  ];
  b.primeraRespuesta = BchPrimeraRespuesta()
    ..busqueda = true
    ..salvamento = true
    ..evacuacion = true
    ..observaciones = 'equipo de rescate';
  b.necesidadSalud = BchNecesidadSalud()..observaciones = 'atención primaria';
  b.infraVial = [BchDanoVial(via: 'Ruta 1', tramo: 'km 2')..danoTotal = 'daño'];
  b.infraPublica = [
    BchInfraPublica(tipoEstructura: 'Alcantarillado', comunidad: 'Centro')
      ..danoTotal = 'daño',
  ];
  b.infraProductiva = [
    BchInfraProductiva(tipo: 'Silo', comunidad: 'Centro')..danoTotal = 'daño',
  ];
  b.saludDanios = [
    BchEstablecimientoSalud(establecimiento: 'Hospital', comunidad: 'Centro')
      ..dano = 'daño',
  ];
  b.educacion = [
    BchUnidadEducativa(establecimiento: 'Colegio', comunidad: 'Centro')
      ..estudiantes = 300
      ..danoParcial = 'daño',
  ];
  b.danosVivienda = [
    BchDanoVivienda(comunidad: 'San Pedro')..danoTotal = 10,
  ];
  b.agricultura = [BchAgricultura(cultivo: 'Caña')..hasAfectadas = 20];
  b.pecuario = [BchPecuario(especie: 'Vacas')..animalesAfectados = 15];
  b.comunidades = [BchComunidad(nombre: 'San Pedro')];
}

void main() {
  group('un turno normal', () {
    test('anota lo que dijo la persona y muestra la respuesta', () async {
      final p = _conRespuesta(_sseJson(
        respuesta: 'Anoté lo del puente.',
        pregunta: '¿Se cayó del todo?',
        parche: {'municipio': 'Yapacaní', 'totalAfectada': 40},
      ));

      await p.enviar('Se cayó el puente y hay 40 afectados');

      expect(p.borrador.municipio, 'Yapacaní');
      expect(p.borrador.totalAfectada, 40);
      expect(p.mensajes.last.texto, contains('puente'));
      expect(p.mensajes.last.texto, contains('¿Se cayó del todo?'));
      expect(p.pensando, isFalse);
    });

    test('el borrador arranca con el mensaje de la persona', () async {
      final p = _conRespuesta(_sseJson(respuesta: 'Entendido'));
      await p.enviar('hola');
      expect(p.mensajes.first.esUsuario, isTrue);
      expect(p.mensajes.first.texto, 'hola');
    });

    test('ignora texto vacío y no gasta una llamada', () async {
      var llamadas = 0;
      final cliente = MockClient((_) async {
        llamadas++;
        return http.Response('', 200);
      });
      final p = EdanIaBorradorProvider(
        puente: _puente(cliente),
        voz: _VozFalsa(),
      );
      await p.enviar('   ');
      expect(llamadas, 0);
      expect(p.mensajes, isEmpty);
    });
  });

  group('la persona manda sobre el modelo', () {
    test('no pisa lo que ya estaba anotado con un campo vacío', () async {
      var turno = 0;
      final cliente = MockClient((_) async {
        turno++;
        // El segundo turno manda municipio en blanco: el modelo "olvidó" un
        // dato que ya estaba. No se debe perder.
        final cuerpo = turno == 1
            ? _sseJson(parche: {'municipio': 'Yapacaní', 'totalAfectada': 40})
            : _sseJson(parche: {'municipio': '', 'totalAfectada': 55});
        return cuerpo;
      });
      final p = EdanIaBorradorProvider(
        puente: _puente(cliente),
        voz: _VozFalsa(),
      );

      await p.enviar('Yapacaní, 40 afectados');
      await p.enviar('son 55 ahora');

      expect(p.borrador.municipio, 'Yapacaní', reason: 'el vacío no borra');
      expect(p.borrador.totalAfectada, 55, reason: 'el dato nuevo sí entra');
    });

    test('el modelo no puede inventar una sección que no existe', () async {
      final p = _conRespuesta(_sseJson(parche: {
        'seccionInventada': {'lo que sea': 1},
        'municipio': 'Cochabamba',
      }));
      await p.enviar('soy de Cochabamba');
      expect(p.borrador.municipio, 'Cochabamba');
      // Y no reventó: el turno se completó normal.
      expect(p.descartado, isFalse);
      expect(p.error, isNull);
    });
  });

  group('cuando el modelo no se entiende', () {
    test('no rompe el borrador ni finge que entendió', () async {
      // El puente degradó el turno a texto. Antes eso terminaba en "no pude
      // entender" y la persona perdía el turno; ahora se muestra la frase tal
      // cual y, aun así, el turno queda marcado para que la UI ofrezca repetir.
      final p = _conRespuesta(_sseTexto(
          'Entiendo que el puente se cayó cerca del hospital.'));
      await p.enviar('se cayó el puente cerca del hospital');

      expect(p.descartado, isTrue, reason: 'el contrato no se respetó');
      expect(p.error, isNull, reason: 'no es un error de red');
      expect(p.borrador.municipio, isEmpty);
    });

    test('un ruido corto no se le habla a la persona', () async {
      // Un token suelto o el eco de la instrucción no son una respuesta.
      final voz = _VozFalsa();
      final p = _conRespuesta(_sseTexto('basura'), voz: voz);
      await p.enviar('algo');

      expect(p.mensajes.last.fallo, isTrue);
      expect(p.mensajes.last.texto, contains('repetir'));
      expect(voz.dicho, isEmpty);
    });

    test('un error de red se informa sin romper el estado', () async {
      final cliente = MockClient((_) async => http.Response('nope', 500));
      final p = EdanIaBorradorProvider(
        puente: _puente(cliente),
        voz: _VozFalsa(),
      );
      await p.enviar('hola');
      expect(p.error, isNotNull);
      expect(p.pensando, isFalse);
      expect(p.mensajes.last.fallo, isTrue);
    });
  });

  group('la voz', () {
    test('dice la respuesta del modelo, no "Entendí"', () async {
      final voz = _VozFalsa();
      final p = _conRespuesta(
        _sseJson(respuesta: 'Contame más del puente'),
        voz: voz,
      );
      await p.enviar('el puente');
      expect(voz.dicho, ['Contame más del puente']);
    });

    test('no pide repetir si no entendió', () async {
      final voz = _VozFalsa();
      final p = _conRespuesta(_sseTexto('basura'), voz: voz);
      await p.enviar('x');
      expect(voz.dicho, isEmpty);
    });

    test('escuchar manda lo oído al puente sin anunciarlo', () async {
      final voz = _VozFalsa()..responder('se inundó el pueblo');
      final p = _conRespuesta(_sseJson(respuesta: '¿A qué altura?'), voz: voz);

      await p.escucharYResponder();

      expect(p.mensajes.first.texto, 'se inundó el pueblo');
      expect(voz.dicho, ['¿A qué altura?']);
      expect(voz.dicho.any((d) => d.contains('Entendí')), isFalse);
    });

    test('si no oye nada, no llama al modelo', () async {
      final voz = _VozFalsa(); // no responde nada
      var llamadas = 0;
      final cliente = MockClient((_) async {
        llamadas++;
        return http.Response('', 200);
      });
      final p = EdanIaBorradorProvider(
        puente: _puente(cliente),
        voz: voz,
      );
      await p.escucharYResponder();
      expect(llamadas, 0);
      expect(p.mensajes, isEmpty);
    });
  });

  group('el prompt se recalcula en cada turno', () {
    test('el segundo turno ya no ofrece lo que se llenó en el primero', () async {
      final pedidos = <String>[];
      var turno = 0;
      final cliente = MockClient((req) async {
        pedidos.add(req.body);
        if (turno++ > 0) return http.Response('', 200);
        // Se llenan los siete campos de la cabecera para que la sección pase
        // el umbral de "incompleta" y desaparezca de lo que se ofrece preguntar.
        return _sseJson(
          respuesta: 'ok',
          parche: const {
            'departamento': 'Santa Cruz',
            'provincia': 'Ichilo',
            'municipio': 'Yapacaní',
            'fechaEvento': '2026-02-10',
            'horaEvento': '14:30',
            'totalAfectada': 40,
            'totalFamiliasAfectadas': 12,
            'totalFamiliasDamnificadas': 5,
          },
        );
      });
      final p = EdanIaBorradorProvider(
        puente: _puente(cliente),
        voz: _VozFalsa(),
      );

      await p.enviar('llovió fuerte en Yapacaní');
      await p.enviar('otra cosa');

      expect(pedidos, hasLength(2));
      // El primer turno ofrecía los datos generales entre lo que faltaba; en
      // el segundo ya no. Si el prompt no se recalcula, el modelo los vuelve a
      // preguntar y la persona lo percibe como un formulario que no avanza.
      expect(_pendientes(pedidos.first), contains('- Datos generales'));
      expect(_pendientes(pedidos.last), isNot(contains('- Datos generales')));
    });

    test('el historial de la conversación va en la petición', () async {
      final pedidos = <String>[];
      var turno = 0;
      final cliente = MockClient((req) async {
        if (turno++ > 0) return http.Response('', 200);
        pedidos.add(req.body);
        return _sseJson(respuesta: 'ok');
      });
      final p = EdanIaBorradorProvider(
        puente: _puente(cliente),
        voz: _VozFalsa(),
      );
      await p.enviar('se cayó el puente');
      await p.enviar('y el camino a San José');

      // El segundo turno debe acordarse del primero, si no el modelo no
      // entiende de qué se está hablando.
      expect(pedidos.last, contains('se cayó el puente'));
    });

    test('el modelo ve los valores ya anotados, no solo qué hay lleno', () async {
      final pedidos = <String>[];
      var turno = 0;
      final cliente = MockClient((req) async {
        pedidos.add(req.body);
        if (turno++ > 0) return http.Response('', 200);
        return _sseJson(parche: {
          'municipio': 'Yapacaní',
          'totalAfectada': 350,
        });
      });
      final p = EdanIaBorradorProvider(
        puente: _puente(cliente),
        voz: _VozFalsa(),
      );

      await p.enviar('Yapacaní, 350 afectados');
      await p.enviar('y ahora son 400');

      // Sin los números, el modelo no puede notar que 400 no cierra con 350.
      // Con esto sí puede, y preguntar en vez de anotar la contradicción.
      final body = jsonDecode(pedidos.last) as Map<String, dynamic>;
      final prompt = (body['instruccion'] as String?) ?? '';
      expect(prompt, contains('Yapacaní'));
      expect(prompt, contains('350'));
    });

    test('el modelo recibe el desajuste de población como algo que preguntar',
        () async {
      final pedidos = <String>[];
      var turno = 0;
      final cliente = MockClient((req) async {
        pedidos.add(req.body);
        if (turno++ > 0) return http.Response('', 200);
        return _sseJson(parche: {
          'totalAfectada': 100,
          'impactoPoblacion': {
            'Niño(a) 0-5 años': {'heridos': 400},
          },
        });
      });
      final p = EdanIaBorradorProvider(
        puente: _puente(cliente),
        voz: _VozFalsa(),
      );

      await p.enviar('en los niños');
      await p.enviar('otra vez niños');

      final body = jsonDecode(pedidos.last) as Map<String, dynamic>;
      final prompt = (body['instruccion'] as String?) ?? '';
      expect(prompt, contains('400'));
      expect(prompt, contains('Preguntale'));
    });
  });

  group('el cierre hacia las fotos', () {
    test('cuando no falta nada, dice que toca fotos y coordenadas', () async {
      final voz = _VozFalsa();
      final p = _conRespuesta(_sseJson(respuesta: 'Anotado'), voz: voz);
      _completar(p.borrador);

      await p.enviar('ya no me queda nada');

      expect(p.listoParaFotos, isTrue);
      expect(p.mensajes.last.texto, contains('fotos'));
      expect(p.mensajes.last.texto, contains('coordenadas'));
      expect(voz.dicho.last, contains('fotos'));
    });

    test('el cierre va como mensaje aparte, no pegado a la respuesta', () async {
      final p = _conRespuesta(_sseJson(respuesta: 'Anotado'));
      _completar(p.borrador);

      await p.enviar('ya no me queda nada');

      // Si van pegados, la UI no puede pintar el paso de fotos aparte, y el
      // texto hablado mezcla dos cosas.
      expect(p.mensajes.where((m) => m.texto.contains('Anotado')), hasLength(1));
      expect(p.mensajes.last.texto, isNot(contains('Anotado')));
    });

    test('no lo dice dos veces', () async {
      final cliente =
          MockClient((_) async => _sseJson(respuesta: 'Anotado'));
      final p = EdanIaBorradorProvider(
        puente: _puente(cliente),
        voz: _VozFalsa(),
      );
      _completar(p.borrador);

      await p.enviar('listo');
      await p.enviar('otra cosa más');

      final cierres =
          p.mensajes.where((m) => m.texto.contains('completar las fotos'));
      expect(cierres, hasLength(1));
    });

    test('no lo repite si el modelo ya lo dijo con sus palabras', () async {
      final voz = _VozFalsa();
      final p = _conRespuesta(
        _sseJson(respuesta: 'Listo. Ahora andá a sacarle foto a la vía.'),
        voz: voz,
      );
      _completar(p.borrador);

      await p.enviar('ya está');

      // Si se agrega igual, la persona oye el cierre dos veces y el modelo
      // queda como que no entendió.
      final cierres =
          p.mensajes.where((m) => m.texto.contains('completar las fotos'));
      expect(cierres, isEmpty);
      expect(voz.dicho, hasLength(1));
    });

    test('mientras falte algo, no se desvía a las fotos', () async {
      final p = _conRespuesta(_sseJson(respuesta: '¿Y el municipio?'));
      await p.enviar('hola');
      expect(p.listoParaFotos, isFalse);
      expect(p.mensajes.last.texto, isNot(contains('fotos')));
    });
  });

  group('cuando el puente degrada a texto', () {
    test('una respuesta en prosa igual se la muestra a la persona', () async {
      // Antes esto terminaba en "no pude entender" y la persona perdía el turno.
      // Verificado en vivo: el modelo respondía en texto plano (degradación).
      final voz = _VozFalsa();
      final p = _conRespuesta(
        _sseTexto('Entiendo que el puente se cayó cerca del hospital.'),
        voz: voz,
      );

      await p.enviar('se cayó el puente cerca del hospital');

      // Se muestra, se habla, y queda en el historial: si se marcara como
      // fallo, el modelo se olvidaría de su propia frase al turno siguiente.
      expect(p.mensajes.last.texto, contains('puente'));
      expect(p.mensajes.last.fallo, isFalse);
      expect(voz.dicho, hasLength(1));
      // Pero el turno sigue marcado para que la UI ofrezca repetir.
      expect(p.descartado, isTrue);
    });

    test('lo que dijo la persona queda anotado igual', () async {
      final p = _conRespuesta(_sseTexto('Anotado.'));
      await p.enviar('en Yapacaní hay 350 personas afectadas');
      // Aunque el modelo no mande parche, el extractor lee la frase.
      expect(p.borrador.totalAfectada, 350);
    });

    test('el extractor tampoco inventa el municipio sin la palabra', () async {
      // "en Yapacaní" puede ser la provincia, así que sin "municipio" el
      // extractor no lo toma como dato. La cautela es a propósito.
      final p = _conRespuesta(_sseTexto('Anotado.'));
      await p.enviar('en Yapacaní hay 350 personas afectadas');

      expect(p.borrador.municipio, isEmpty);
    });

    test('si no hay ni prosa ni datos, ahí sí se pide repetir', () async {
      final voz = _VozFalsa();
      final p = _conRespuesta(_sseTexto('   '), voz: voz);
      await p.enviar('mmm');
      expect(p.descartado, isTrue);
      expect(p.mensajes.last.fallo, isTrue);
      expect(voz.dicho, isEmpty);
    });

    test('un JSON sin parche tampoco pierde los datos', () async {
      // Es el otro agujero que se encontró: el modelo responde en palabras
      // pero no deja `parche`. Antes el turno pasaba como si hubiera
      // entendido y lo dicho se perdía en silencio.
      final p = _conRespuesta(_sseJson(respuesta: '¿Y las familias?', parche: null));
      await p.enviar('en Yapacaní hay 350 personas afectadas');

      expect(p.borrador.totalAfectada, 350);
    });
  });

  group('turno de reparación', () {
    test('el modelo puede volver a escribir el parche si se le pide', () async {
      // Lo que se vio en la corrida real: el modelo contestaba largo, preguntaba
      // el dato que faltaba y se dejaba el parche vacío. Con una instrucción
      // corta, sin diálogo que imitar, responde con el JSON.
      var llamada = 0;
      final cliente = MockClient((_) async {
        llamada++;
        if (llamada == 1) {
          return _sseJson(
            respuesta: 'Entiendo que el camino a San Pedro se rompió. '
                '¿Cuánto mide el tramo?',
            parche: <String, Object?>{},
          );
        }
        return _envioJson(parche: {
          'infraVial': [
            {'via': 'San Pedro', 'danoTotal': 'Total'},
          ],
        });
      });
      final p = EdanIaBorradorProvider(
        puente: _puente(cliente),
        voz: _VozFalsa(),
      );

      await p.enviar('se rompió el camino a San Pedro');

      expect(llamada, 2, reason: 'tiene que haber pedido una segunda vez');
      expect(p.borrador.infraVial, hasLength(1));
      expect(p.borrador.infraVial.first.via, 'San Pedro');
    });

    test('el parche reparado se aplica una sola vez', () async {
      var llamada = 0;
      final cliente = MockClient((_) async {
        llamada++;
        if (llamada == 1) {
          return _sseJson(respuesta: 'ok', parche: <String, Object?>{});
        }
        return _envioJson(parche: {
          'infraVial': [
            {'via': 'Ruta 1', 'danoTotal': 'Total'},
          ],
        });
      });
      final p = EdanIaBorradorProvider(
        puente: _puente(cliente),
        voz: _VozFalsa(),
      );

      await p.enviar('se cayó la ruta 1');

      // Una fila, no dos: si se aplicara dos veces la calle se duplicaría.
      expect(p.borrador.infraVial, hasLength(1));
    });

    test('si la reparación tampoco trae datos, no se insiste', () async {
      // La persona puede estar solo conversando. Preguntar tres veces por lo
      // mismo es peor que dejar el turno como está.
      var llamada = 0;
      final cliente = MockClient((_) async {
        llamada++;
        if (llamada == 1) {
          return _sseJson(respuesta: 'ok', parche: <String, Object?>{});
        }
        return _envioJson(parche: <String, Object?>{});
      });
      final p = EdanIaBorradorProvider(
        puente: _puente(cliente),
        voz: _VozFalsa(),
      );

      await p.enviar('gracias, después te cuento');

      expect(llamada, 2, reason: 'una pasada de reparación y nada más');
      expect(p.descartado, isFalse);
    });

    test('la petición pide formato json, no solo por instrucción', () async {
      // El modo JSON no es una promesa: por eso está el respaldo de prosa de
      // arriba. Esta prueba es para que nadie lo saque pensando que sobra, y
      // cubre también la pasada de reparación, que va por el mismo servicio.
      final pedidos = <Map<String, dynamic>>[];
      var llamada = 0;
      final cliente = MockClient((req) async {
        llamada++;
        pedidos.add(jsonDecode(req.body) as Map<String, dynamic>);
        return _sseJson(respuesta: 'ok', parche: <String, Object?>{});
      });
      final p = EdanIaBorradorProvider(
        puente: _puente(cliente),
        voz: _VozFalsa(),
      );
      await p.enviar('hola');

      expect(llamada, 2, reason: 'turno normal más el de reparación');
      expect(pedidos, hasLength(2));
      for (final cuerpo in pedidos) {
        expect(cuerpo['formato'], 'json');
      }
    });
  });

  group('guardar', () {
    test('se niega a guardar con un desajuste de población', () async {
      final p = _conRespuesta(_sseJson(parche: {
        'totalAfectada': 100,
        'impactoPoblacion': {
          'Niño(a) 0-5 años': {'heridos': 400},
        },
      }));
      await p.enviar('en los niños');

      expect(p.avisosPoblacion, isNotEmpty);
      expect(p.bloqueaGuardar, isTrue);
      // Sin base de datos: si llegara a guardar, reventaría por otra cosa y
      // la prueba no probaría nada.
      await expectLater(
        p.guardar(usuarioId: 1),
        throwsA(isA<EdanPoblacionIncoherente>()),
      );
    });

    test('un desajuste que el wizard no bloquea tampoco bloquea acá', () async {
      final p = _conRespuesta(_sseJson(parche: {
        'totalFamiliasAfectadas': 50,
        'totalFamiliasDamnificadas': 120,
      }));
      await p.enviar('120 familias');

      expect(p.avisosPoblacion, hasLength(1));
      expect(p.bloqueaGuardar, isFalse);
    });
  });

  group('estado para la UI', () {
    test('el avance sube a medida que se llena', () async {
      final p = _conRespuesta(_sseJson(
        respuesta: 'ok',
        parche: {'municipio': 'Yapacaní', 'totalAfectada': 40},
      ));
      final antes = p.avance;
      await p.enviar('hola');
      expect(p.avance, greaterThan(antes));
    });

    test('reiniciar deja el borrador como nuevo', () async {
      final p = _conRespuesta(_sseJson(parche: {'municipio': 'Yapacaní'}));
      await p.enviar('hola');
      expect(p.borrador.municipio, isNotNull);

      p.reiniciar();

      expect(p.borrador.municipio, isEmpty);
      expect(p.mensajes, isEmpty);
      expect(p.avance, 0);
    });

    test('prepararGuardado traduce sin tocar la base de datos', () async {
      final p = _conRespuesta(_sseJson(parche: {
        'municipio': 'Yapacaní',
        'totalAfectada': 40,
        'infraVial': [
          {'via': 'Puente San Carlos', 'kmDanio': '1.5', 'danoParcial': 'Parcial'},
        ],
      }));
      await p.enviar('se dañó el puente San Carlos, un kilómetro y medio');

      final r = p.prepararGuardado();
      expect(r.localidad.municipioNombre, 'Yapacaní');
      expect(r.localidad.danosViales, hasLength(1));
      expect(r.seccionesActivas, contains('danos-viales'));
    });
  });
}