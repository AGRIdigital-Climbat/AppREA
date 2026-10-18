/// El cierre del asistente contra SQLite de verdad: borrador -> paso de fotos
/// -> guardado.
///
/// El resto de las pruebas del provider usan dobles. Esta usa la base real para
/// fijar el journey que hace la pantalla, que es donde se perdían datos sin que
/// ninguna prueba unitaria lo notara: la UI traducía el borrador, el paso de
/// fotos cargaba `fotografia` y las coordenadas sobre los ítems, y al guardar
/// el provider volvía a traducir desde cero y armaba otra localidad. Todo
/// pasaba bien salvo las fotos, que desaparecían al cerrar la ficha.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:rea/providers/edan_ia_borrador_provider.dart';
import 'package:rea/services/database_helper.dart';
import 'package:rea/services/edan/edan_store_v2.dart';
import 'package:rea/services/edan_ia/puente_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dir;
  final db = DatabaseHelper.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rea_edan_ia_cierre');
    DatabaseHelper.rutaDePrueba = p.join(dir.path, 'test.db');
  });

  tearDown(() async {
    await db.cerrarParaPrueba();
    DatabaseHelper.rutaDePrueba = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// SSE con un turno completo, como los devuelve el puente.
  ///
  /// El cuerpo va con `Response.bytes` y las líneas unidas por `\n`, que es la
  /// forma verificada contra el parser del servicio.
  http.Response sde(Map<String, dynamic> turno) {
    final parche = turno['parche'] as Map<String, dynamic>?;
    final sse = [
      'data: ${jsonEncode({'tipo': 'token', 'texto': turno['respuesta']})}',
      'data: ${jsonEncode({
            'tipo': 'json',
            'json': {'parche': parche},
          })}',
      'data: ${jsonEncode({
            'tipo': 'done',
            'respuesta': turno['respuesta'],
            'json': {'parche': parche},
            'formato': 'json',
            'modelo': 'openai/gpt-oss-20b',
            'proveedor': 'Groq-adrian',
            'intentos': 1,
            'tokens': {'entrada': 1, 'salida': 1, 'razonamiento': 0},
            'avisos': <String>[],
          })}',
      'data: [DONE]',
    ].join('\n');
    return http.Response.bytes(utf8.encode(sse), 200);
  }

  Future<EdanIaBorradorProvider> providerCompleto() async {
    var llamada = 0;
    final cliente = MockClient((_) async {
      llamada++;
      return sde({
        'respuesta': 'Anotado.',
        'siguiente_pregunta': '',
        'parche': llamada == 1
            ? {
                'municipio': 'Yapacaní',
                'totalAfectada': 350,
                'tipoEvento': {'inundacion': true},
                'infraVial': [
                  {
                    'via': 'Puente Viejo',
                    'tramo': 'km 4',
                    'danoTotal': 'Total',
                  },
                ],
              }
            : <String, dynamic>{},
      });
    });
    final prov = EdanIaBorradorProvider(
      puente: PuenteService(
        baseUrl: 'https://test.puente',
        apiKey: 'llave',
        client: cliente,
      ),
    );
    await prov.enviar('se desbordó el río en Yapacaní, son 350 personas');
    return prov;
  }

  test('el paso de fotos y el guardado viajan en la misma localidad', () async {
    final prov = await providerCompleto();
    expect(prov.borrador.totalAfectada, 350);
    // El borrador está a propósito incompleto: acá importa el viaje del
    // guardado, no la puerta de fotos, que tiene sus propias pruebas.
    final preparado = prov.prepararGuardado();
    expect(preparado.localidad.danosViales, hasLength(1));

    // El paso de fotos escribe sobre los ítems de esa misma localidad.
    final puente = preparado.localidad.danosViales.first;
    puente.fotografia = '/fotos/puente_1.jpg';
    puente.coordenadaLat = -17.0333;
    puente.coordenadaLon = -65.2667;

    // Y al volver, la pantalla pasa esa localidad, no una traducción nueva.
    final uuid = await prov.guardar(usuarioId: 7, preparado: preparado);
    expect(uuid, isNotEmpty, reason: 'sin uuid la UI no sabe qué guardó');

    // Diseño limpio: la única persistencia son las tablas V2.
    final store = EdanStoreV2(db: db);
    final lista = await store.listarFormularios(usuarioId: 7);
    expect(lista, hasLength(1));
    final r = lista.single;
    expect(r.uuidEdanLocalidad, uuid);
    await store.cargarSecciones(r);
    expect(r.municipioNombre, 'Yapacaní');
    expect(r.totalPoblacionAfectada, 350);
    expect(r.sincronizado, isFalse);
    expect(r.grupInfraestructura, isTrue);

    final releido = r.danosViales.single;
    expect(releido.fotografia, '/fotos/puente_1.jpg');
    expect(releido.coordenadaLat, -17.0333);
    expect(releido.coordenadaLon, -65.2667);
  });

  test('sin pasar la localidad preparada, las fotos sí se perdían', () async {
    // Este es el control: documenta por qué el parámetro existe. Si alguien
    // saca `preparado` del provider, esta prueba sigue verde, pero la de
    // arriba se pone roja al primer cambio de la pantalla.
    final prov = await providerCompleto();
    final preparado = prov.prepararGuardado();
    preparado.localidad.danosViales.first.fotografia = '/fotos/puente_1.jpg';

    // Sin `preparado`, el provider traduce de nuevo y la foto no viaja.
    final uuid = await prov.guardar(usuarioId: 7);
    final store = EdanStoreV2(db: db);
    final r = (await store.listarFormularios(usuarioId: 7)).single;
    expect(r.uuidEdanLocalidad, uuid);
    await store.cargarSecciones(r);
    expect(r.danosViales.single.fotografia, isNull);
  });
}
