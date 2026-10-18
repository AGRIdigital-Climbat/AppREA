/// Vínculo `localidades_offline` ↔ `formularios` (V2).
///
/// El wizard (RESP y, desde la paridad, UGR) inserta la localidad en
/// `localidades_offline` (idLocal = A) y luego persiste la cabecera V2 en
/// `formularios`. Para poder REABRIR el borrador el wizard usa
/// `uuidEdanLocalidad ?? idLocal` (`_sincronizarFlagsDesdeSeccionesActivas`),
/// por lo que se exige que `formularios.uuid_edan_localidad` coincida con
/// `localidades_offline.id_local`. `EdanStoreV2._ensureUuid` reutiliza el
/// `idLocal` cuando existe; si no, genera un uuid nuevo (fallback).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rea/models/edan.dart';
import 'package:rea/services/database_helper.dart';
import 'package:rea/services/edan/edan_store_v2.dart';
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
    dir = await Directory.systemTemp.createTemp('edan_vinculo');
    DatabaseHelper.rutaDePrueba = p.join(dir.path, 'test.db');
  });

  tearDown(() async {
    await db.cerrarParaPrueba();
    DatabaseHelper.rutaDePrueba = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<EdanStoreV2> _store() async {
    await db.database;
    return EdanStoreV2(db: db);
  }

  Future<void> _seedFila(
    String uuid,
    String tipo,
    Map<String, dynamic> datos,
  ) =>
      db.database.then((d) => d.insert('filas_seccion', {
            'uuid_registro': '$uuid-$tipo',
            'uuid_edan_localidad': uuid,
            'tipo': tipo,
            'datos_json': jsonEncode(datos),
            'estado_sync': 'confirmado',
          }));

  test('guardarFormulario reutiliza idLocal como uuidEdanLocalidad', () async {
    final store = await _store();
    final loc = EdanLocalidad()..nombre = 'Comunidad X';

    // Como hace el wizard: primero la fila en localidades_offline.
    final idA = await db.insertLocalidad(loc, usuarioId: 7);
    loc.idLocal = idA;

    await store.guardarFormulario(
      loc,
      usuarioId: 7,
      seccionesActivas: ['impacto-poblacion'],
    );

    expect(loc.uuidEdanLocalidad, idA,
        reason: 'el uuid V2 debe coincidir con localidades_offline.id_local');
    expect(await store.cargarFormulario(idA), isNotNull);
  });

  test('sin idLocal previo genera un uuid V2 nuevo (fallback)', () async {
    final store = await _store();
    final loc = EdanLocalidad()..nombre = 'Sin id';
    loc.idLocal = null;

    await store.guardarFormulario(loc, usuarioId: 7);

    expect(loc.uuidEdanLocalidad, isNotNull);
    expect(loc.uuidEdanLocalidad, isNotEmpty);
  });

  test('reapertura por idLocal carga las filas V2 de la sección', () async {
    final store = await _store();
    final loc = EdanLocalidad()..nombre = 'Reapertura';
    final idA = await db.insertLocalidad(loc, usuarioId: 7);
    loc.idLocal = idA;

    await store.guardarFormulario(
      loc,
      usuarioId: 7,
      seccionesActivas: ['impacto-poblacion'],
    );
    await _seedFila(idA, 'impacto-poblacion', {
      'id_seccion': 's-1',
      'id_grupo_etario': 1,
      'rango': 'Niño (a) 0-5 años',
      'fallecidos': 2,
      'heridos': 1,
      'desaparecidos': 0,
      'observaciones': '',
    });

    // Reapertura como el wizard: uuid = uuidEdanLocalidad ?? idLocal.
    final reabierta = EdanLocalidad()..idLocal = idA;
    final activas = await store.leerSeccionesActivas(idA);
    expect(activas, contains('impacto-poblacion'));

    await store.cargarSecciones(reabierta, tipos: activas);
    expect(reabierta.impactoPoblacion, hasLength(1));
    expect(reabierta.impactoPoblacion.first.fallecidos, 2);
  });

  test('datos_json de localidades_offline conserva el uuid tras el guardado',
      () async {
    final store = await _store();
    final loc = EdanLocalidad()..nombre = 'Json';
    final idA = await db.insertLocalidad(loc, usuarioId: 7);
    loc.idLocal = idA;

    await store.guardarFormulario(loc, usuarioId: 7);
    // El wizard sincroniza datos_json con el modelo (incluye el uuid).
    await db.updateLocalidadJson(idA, jsonEncode(loc.toJson()));

    final filas = await db.getLocalidades(7);
    final recuperada = filas.firstWhere((l) => l.idLocal == idA);
    expect(recuperada.uuidEdanLocalidad, idA);
  });

  test(
      'recuperación V2: un formulario sin fila en localidades_offline sigue '
      'visible (listarFormularios) y se detecta para el preview', () async {
    final store = await _store();
    // Simula el pull en un celular nuevo: el reporte propio llega a
    // `formularios` SIN que exista una fila en `localidades_offline`.
    final loc = EdanLocalidad()..nombre = 'Recuperada';
    await store.guardarFormulario(loc, usuarioId: 7);
    final uuid = loc.uuidEdanLocalidad!;

    // No quedó en la tabla legacy...
    expect(await db.getLocalidades(7), isEmpty);

    // ...pero la lista offline lo recupera del store V2.
    final v2 = await store.listarFormularios(usuarioId: 7);
    expect(v2.map((l) => l.idLocal), contains(uuid));

    // Y el preview lo reconoce como V2 (fuente local de secciones).
    expect(await store.cargarFormulario(uuid), isNotNull);
  });
}