/// Filtro `idMunicipio` de `EdanStoreV2.listarFormularios`, la base del mapa
/// UGR offline-first: el mapa pasa de `getLocalidadesMunicipio` (servidor) a
/// leer SQLite filtrando por municipio, igual que RESP lee el store.
library;

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
    dir = await Directory.systemTemp.createTemp('store_municipio');
    DatabaseHelper.rutaDePrueba = p.join(dir.path, 'test.db');
  });
  tearDown(() async {
    await db.cerrarParaPrueba();
    DatabaseHelper.rutaDePrueba = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  EdanLocalidad loc({
    required String uuid,
    required int municipio,
    required int usuario,
  }) {
    final l = EdanLocalidad(
        nombre: 'L-$uuid', idTipoEvento: 1, uuidEdanLocalidad: uuid)
      ..idMunicipio = municipio
      ..idUsuario = usuario
      ..grupPoblacion = true;
    return l;
  }

  Future<void> guardar(EdanLocalidad l, int usuario) async {
    final store = EdanStoreV2(db: db);
    await store.guardarTodo(
      l,
      usuarioId: usuario,
      seccionesActivas: const <String>[],
      tipos: const <String>[],
    );
  }

  test('idMunicipio devuelve solo las localidades de ese municipio', () async {
    await guardar(loc(uuid: 'u-a', municipio: 10101, usuario: 7), 7);
    await guardar(loc(uuid: 'u-b', municipio: 20202, usuario: 8), 8);
    final store = EdanStoreV2(db: db);

    final sucre = await store.listarFormularios(idMunicipio: 10101);
    expect(sucre.map((l) => l.uuidEdanLocalidad), ['u-a']);

    final todos = await store.listarFormularios();
    expect(todos.length, 2, reason: 'sin filtro = todo el municipio/store');
  });

  test('combinar usuarioId + idMunicipio es un AND estricto', () async {
    await guardar(loc(uuid: 'u-a', municipio: 10101, usuario: 7), 7);
    await guardar(loc(uuid: 'u-b', municipio: 20202, usuario: 8), 8);
    final store = EdanStoreV2(db: db);

    final ok = await store.listarFormularios(idMunicipio: 10101, usuarioId: 7);
    expect(ok.map((l) => l.uuidEdanLocalidad), ['u-a']);

    final ninguno =
        await store.listarFormularios(idMunicipio: 10101, usuarioId: 8);
    expect(ninguno, isEmpty,
        reason: 'u-a es del municipio 10101 pero usuario 7, no 8');
  });

  test('usuarioId sigue filtrando igual que antes (sin regresión)', () async {
    await guardar(loc(uuid: 'u-a', municipio: 10101, usuario: 7), 7);
    await guardar(loc(uuid: 'u-b', municipio: 20202, usuario: 8), 8);
    final store = EdanStoreV2(db: db);

    final u7 = await store.listarFormularios(usuarioId: 7);
    expect(u7.map((l) => l.uuidEdanLocalidad), ['u-a']);
  });

  test('municipio inexistente => lista vacía', () async {
    await guardar(loc(uuid: 'u-a', municipio: 10101, usuario: 7), 7);
    final store = EdanStoreV2(db: db);
    expect(await store.listarFormularios(idMunicipio: 99999), isEmpty);
  });
}
