/// Contadores del Inicio calculados SOLO de SQLite (`EdanStoreV2.resumenLocal`).
///
/// Fija: los 6 estados disgregados + total, sobre `formularios` (V2) y
/// `localidades_offline` (legado sin contraparte), filtrados por dueño.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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
    dir = await Directory.systemTemp.createTemp('edan_resumen');
    DatabaseHelper.rutaDePrueba = p.join(dir.path, 'test.db');
  });

  tearDown(() async {
    await db.cerrarParaPrueba();
    DatabaseHelper.rutaDePrueba = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> _insertFormulario(
    String uuid,
    int usuario, {
    int? estado,
    int? idEdan,
  }) async {
    final d = await db.database;
    await d.insert('formularios', {
      'uuid_edan_localidad': uuid,
      'localidad': 'Loc $uuid',
      'id_usuario': usuario,
      'id_edan_localidad_estado': estado,
      'id_edan': idEdan,
    });
  }

  test('cuenta los 6 estados disgregados + total', () async {
    await _insertFormulario('u1', 30, estado: 1);
    await _insertFormulario('u2', 30, estado: 1);
    await _insertFormulario('u3', 30, estado: 1);
    await _insertFormulario('u4', 30, estado: 2);
    await _insertFormulario('u5', 30, estado: 2);
    await _insertFormulario('u6', 30, estado: 3);
    await _insertFormulario('u7', 30, estado: 4);
    await _insertFormulario('u8', 30, estado: 5);
    await _insertFormulario('u9', 30, estado: 6);

    final r = await EdanStoreV2(db: db).resumenLocal(usuarioId: 30);

    expect(r.total, 9);
    expect(r.porEstado[1], 3);
    expect(r.porEstado[2], 2);
    expect(r.porEstado[3], 1);
    expect(r.porEstado[4], 1);
    expect(r.porEstado[5], 1);
    expect(r.porEstado[6], 1);
  });

  test('estado ausente cuenta como borrador (1)', () async {
    await _insertFormulario('u-n', 30);
    final r = await EdanStoreV2(db: db).resumenLocal(usuarioId: 30);
    expect(r.porEstado[1], 1);
    expect(r.total, 1);
  });

  test('filtra por dueño', () async {
    await _insertFormulario('mio', 30, estado: 2);
    await _insertFormulario('ajeno', 99, estado: 3);
    final r = await EdanStoreV2(db: db).resumenLocal(usuarioId: 30);
    expect(r.total, 1);
    expect(r.porEstado[2], 1);
    expect(r.porEstado.containsKey(3), isFalse);
  });

  test('incluye el legado sin contraparte V2 (dedup)', () async {
    final d = await db.database;
    await _insertFormulario('v2', 30, estado: 2);
    await d.insert('localidades_offline', {
      'id_local': 'legacy-1',
      'usuario_id': 30,
      'id_edan_localidad_estado': 1,
      'datos_json': '{}',
      'fecha_creacion': '2026-10-16',
      'pendiente_eliminacion': 0,
    });
    // Legado cuyo id_local YA existe en V2: no debe duplicarse.
    await d.insert('localidades_offline', {
      'id_local': 'v2',
      'usuario_id': 30,
      'id_edan_localidad_estado': 5,
      'datos_json': '{}',
      'fecha_creacion': '2026-10-16',
      'pendiente_eliminacion': 0,
    });

    final r = await EdanStoreV2(db: db).resumenLocal(usuarioId: 30);
    expect(r.total, 2, reason: '1 V2 + 1 legado (el duplicado no cuenta)');
    expect(r.porEstado[2], 1);
    expect(r.porEstado[1], 1);
  });

  test('excluye legado pendiente de eliminación', () async {
    final d = await db.database;
    await d.insert('localidades_offline', {
      'id_local': 'del',
      'usuario_id': 30,
      'id_edan_localidad_estado': 1,
      'datos_json': '{}',
      'fecha_creacion': '2026-10-16',
      'pendiente_eliminacion': 1,
    });
    final r = await EdanStoreV2(db: db).resumenLocal(usuarioId: 30);
    expect(r.total, 0);
  });
}
