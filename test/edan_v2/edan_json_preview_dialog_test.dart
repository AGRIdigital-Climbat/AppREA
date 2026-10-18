/// Depurador JSON EDAN (long-press): fija las FUENTES DE DATOS de las 4 vistas
/// (Datos·GET, Datos·POST, Fotos·GET, Fotos·POST) sin montar el widget (el
/// sqflite-ffi no converge bajo el fake-async de `testWidgets`).
///
/// Reglas fijadas:
///  - GET (documento del servidor) SÍ trae `fotografia` (espejo del path) y el
///    nodo `grupos`.
///  - POST de datos NO trae `fotografia` (§20.10.C): las fotos van por la API
///    separada `POST /api/v2/edan/fotografias` (multipart), cada una con su
///    propio `uuid_fotografia`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rea/services/database_helper.dart';
import 'package:rea/services/sync/edan_sync_engine_v2.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  final db = DatabaseHelper.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('edan_json_dialog');
    DatabaseHelper.rutaDePrueba = p.join(dir.path, 'test.db');
  });

  tearDown(() async {
    await db.cerrarParaPrueba();
    DatabaseHelper.rutaDePrueba = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('las 4 vistas del depurador usan sus fuentes correctas', () async {
    final arch = File(p.join(dir.path, 'foto.png'));
    await arch.writeAsBytes(utf8.encode('img'));

    // Documento del servidor cacheado (GET): incluye `fotografia` (espejo), el
    // nodo `grupos` y la clave `fotos[]`.
    final docServidor = {
      'localidad': 'Servidor',
      'imp_danos_viales': true,
      'danos_viales': [
        {
          'uuid_registro': 'fila-dlg',
          'tramo': 'T',
          'fotografia': '/uploads/reporte.png',
        }
      ],
      'grupos': {'danos_viales': true},
      'fotos': [
        {'uuid_fotografia': 'fs', 'ruta_servidor': '/uploads/x.png'}
      ],
    };

    await db.database.then((d) => d.insert('formularios', {
          'uuid_edan_localidad': 'u-dlg',
          'localidad': 'Loc Dlg',
          'pendiente_push': 0,
          'datos_json_servidor': jsonEncode(docServidor),
        }));
    await db.database.then((d) => d.insert('filas_seccion', {
          'uuid_registro': 'fila-dlg',
          'uuid_edan_localidad': 'u-dlg',
          'tipo': 'danos-viales',
          'datos_json': '{"tramo":"T"}',
          'estado_sync': 'confirmado',
        }));
    await db.database.then((d) => d.insert('cola_fotos', {
          'uuid_fotografia': 'foto-dlg',
          'ruta_local': arch.path,
          'tipo_entidad': 'filas_seccion',
          'uuid_registro': 'fila-dlg',
          'estado': 'pendiente',
          'intentos': 0,
        }));

    // ── Vista Datos · GET ── documento crudo del servidor: SÍ trae
    // `fotografia` y `grupos`.
    final row = (await (await db.database).query('formularios',
            where: 'uuid_edan_localidad = ?', whereArgs: ['u-dlg']))
        .first;
    final get = jsonDecode(row['datos_json_servidor'] as String)
        as Map<String, dynamic>;
    expect(get['grupos'], isNotNull, reason: 'GET trae el nodo grupos');
    final dvGet = (get['danos_viales'] as List).first as Map;
    expect(dvGet['fotografia'], '/uploads/reporte.png',
        reason: 'GET trae fotografia (espejo del path)');
    expect((get['fotos'] as List), hasLength(1), reason: 'Vista Fotos·GET');

    // ── Vista Datos · POST ── body del /formularios/completo: sin `fotografia`.
    final post = await EdanSyncEngineV2.prepararPayloadCompleto('u-dlg', row);
    expect(post['uuid_edan_localidad'], 'u-dlg');
    expect(post.containsKey('grupos'), isFalse);
    expect(post.containsKey('fotos'), isFalse);
    expect((post['danos_viales'] as List).first, isNot(contains('fotografia')));
    expect(post.keys.any((k) => k.startsWith('grup_')), isFalse);

    // ── Vista Fotos · POST ── multipart de la API separada /fotografias, con
    // su PROPIO uuid_fotografia.
    final pendientes = await EdanSyncEngineV2.fotosPendientesDeLocalidad(
      'u-dlg',
      dbHelper: db,
    );
    expect(pendientes, hasLength(1));
    final tipo = await EdanSyncEngineV2.resolverTipoEntidadSoloLectura(
      pendientes.first,
      dbHelper: db,
    );
    expect(pendientes.first['uuid_fotografia'], 'foto-dlg');
    expect(tipo, isNotNull, reason: 'tipo_entidad resoluble por la fila dueña');
    expect(tipo, isNot('filas_seccion'),
        reason: 'se traduce al nombre de tabla real del CHECK');
  });
}