/// Diagnóstico de pendientes del botón debug (`sync_diagnostico.dart`):
/// explica QUÉ está atascado y POR QUÉ sin necesidad de correr un sync.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rea/services/database_helper.dart';
import 'package:rea/services/sync_diagnostico.dart';
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
    dir = await Directory.systemTemp.createTemp('edan_diag');
    DatabaseHelper.rutaDePrueba = p.join(dir.path, 'test.db');
  });

  tearDown(() async {
    await db.cerrarParaPrueba();
    DatabaseHelper.rutaDePrueba = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('sin nada pendiente dice ok + watermark', () async {
    final r = await diagnosticarPendientes(dbHelper: db);

    expect(r.any((d) => d.titulo == 'Sin trabajo pendiente'), isTrue);
    expect(r.any((d) => d.nivel == 'error'), isFalse);
  });

  test('formulario + cola + foto bloqueada explican su motivo', () async {
    final database = await db.database;
    await database.insert('formularios', {
      'uuid_edan_localidad': 'u-dg',
      'localidad': 'Diag',
      'pendiente_push': 1,
      'id_edan_localidad_estado': 2,
      'pending_submit': 1,
      'estado_destino': 3,
    });
    await database.insert('cola_sincronizacion', {
      'tabla': 'filas_seccion',
      'uuid_registro': 'f-dg',
      'accion': 'D',
      'estado': 'rechazado',
      'intentos': 0,
      'ultimo_error': '400 regla X',
    });
    await database.insert('filas_seccion', {
      'uuid_registro': 'f-foto',
      'uuid_edan_localidad': 'u-dg',
      'tipo': 'danos-agricultura',
      'datos_json': '{}',
      'estado_sync': 'pendiente',
    });
    await database.insert('cola_fotos', {
      'uuid_fotografia': 'foto-dg',
      'ruta_local': '/no/existe.jpg',
      'tipo_entidad': 'danos_agricultura',
      'uuid_registro': 'f-foto',
      'estado': 'pendiente',
      'intentos': 2,
    });

    final r = await diagnosticarPendientes(dbHelper: db);
    final titulos = r.map((d) => d.titulo).toList();

    expect(titulos.any((t) => t.contains('Diag')), isTrue,
        reason: 'el formulario por enviar aparece con su estado');
    expect(
        r
            .where((d) => d.titulo.contains('Diag'))
            .first
            .motivo,
        contains('estado 2'));
    expect(titulos.any((t) => t.contains('Rechazado')), isTrue);
    expect(
        r.where((d) => d.nivel == 'error').isNotEmpty, isTrue,
        reason: 'el rechazo es error visible, no silencio');
    final foto =
        r.where((d) => d.titulo.contains('Foto en cola')).toList();
    expect(foto, hasLength(1));
    expect(foto.first.motivo, contains('SIN confirmar'));
    expect(foto.first.motivo, contains('ARCHIVO AUSENTE'));
  });
}