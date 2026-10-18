/// Viviendas 1:N (Fase 6): modelo `EdanDanoVivienda.viviendas`, case canónico
/// de `tipo_dano` (TOTAL/PARCIAL), contadores derivados y CRUD de store.
///
/// Fija el contrato de §6/§19: cada fila `danos_vivienda` puede desglosarse en
/// N viviendas; con detalle, `dano_total`/`dano_parcial` se derivan de los
/// conteos TOTAL/PARCIAL (no se capturan a mano). El store persiste viviendas
/// en la tabla `viviendas` (CHECK exige mayúsculas).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rea/models/edan.dart';
import 'package:rea/models/edan_registro_v2.dart';
import 'package:rea/services/database_helper.dart';
import 'package:rea/services/edan/edan_store_v2.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  final db = DatabaseHelper.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('edan_viviendas');
    DatabaseHelper.rutaDePrueba = p.join(dir.path, 'test.db');
  });

  tearDown(() async {
    await db.cerrarParaPrueba();
    DatabaseHelper.rutaDePrueba = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  EdanVivienda _v(String uuid, EdanViviendaTipo tipo,
          {String? uuidDano = 'b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2'}) =>
      EdanVivienda(
        uuidRegistro: uuid,
        uuidDanoVivienda: uuidDano,
        tipoDano: tipo,
        coordenadaLat: -1,
        coordenadaLon: -2,
      );

  group('EdanVivienda · case canónico', () {
    test('toJson escribe tipo_dano en MAYÚSCULA (CHECK de la tabla)', () {
      expect(_v('d1d1d1d1-d1d1-4d1d-8d1d-d1d1d1d1d1d1', EdanViviendaTipo.total).toJson()['tipo_dano'], 'TOTAL');
      expect(_v('e2e2e2e2-e2e2-4e2e-8e2e-e2e2e2e2e2e2', EdanViviendaTipo.parcial).toJson()['tipo_dano'],
          'PARCIAL');
    });

    test('fromJson acepta mayúsculas, minúsculas y con espacios', () {
      expect(EdanVivienda.fromJson({'tipo_dano': 'TOTAL'}).tipoDano,
          EdanViviendaTipo.total);
      expect(EdanVivienda.fromJson({'tipo_dano': 'parcial'}).tipoDano,
          EdanViviendaTipo.parcial);
      expect(EdanVivienda.fromJson({'tipo_dano': ' Total '}).tipoDano,
          EdanViviendaTipo.total);
      expect(EdanVivienda.fromJson({'tipo_dano': null}).tipoDano,
          EdanViviendaTipo.parcial,
          reason: 'default parcial');
    });
  });

  group('EdanDanoVivienda · contadores derivados', () {
    test('2 TOTAL + 1 PARCIAL → viviendasTotal=2, viviendasParcial=1', () {
      final fila = EdanDanoVivienda(
        idSeccion: 'b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2',
        comunidad: 'C',
        viviendas: [
          _v('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa', EdanViviendaTipo.total),
          _v('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb', EdanViviendaTipo.total),
          _v('cccccccc-cccc-4ccc-8ccc-cccccccccccc', EdanViviendaTipo.parcial),
        ],
      );
      expect(fila.viviendasTotal, 2);
      expect(fila.viviendasParcial, 1);
    });

    test('toApiJson deriva dano_total/dano_parcial de las viviendas', () {
      final fila = EdanDanoVivienda(
        idSeccion: 'b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2',
        danoTotal: 99, // manuales, ignorados al haber detalle
        danoParcial: 88,
        viviendas: [
          _v('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa', EdanViviendaTipo.total),
          _v('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb', EdanViviendaTipo.parcial),
        ],
      );
      final api = fila.toApiJson();
      expect(api['dano_total'], 1);
      expect(api['dano_parcial'], 1);
    });

    test('sin viviendas conserva los contadores manuales', () {
      final fila = EdanDanoVivienda(
        idSeccion: 'b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2',
        danoTotal: 5,
        danoParcial: 3,
      );
      final api = fila.toApiJson();
      expect(api['dano_total'], 5);
      expect(api['dano_parcial'], 3);
      expect(fila.viviendasTotal, 0);
      expect(fila.viviendasParcial, 0);
    });

    test('baja de una vivienda recalcula los contadores (getters)', () {
      final fila = EdanDanoVivienda(
        idSeccion: 'b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2',
        viviendas: [
          _v('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa', EdanViviendaTipo.total),
          _v('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb', EdanViviendaTipo.total),
          _v('cccccccc-cccc-4ccc-8ccc-cccccccccccc', EdanViviendaTipo.parcial),
        ],
      );
      fila.viviendas.removeWhere((v) =>
          v.uuidRegistro == 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa');
      expect(fila.viviendasTotal, 1);
      expect(fila.viviendasParcial, 1);
    });
  });

  group('EdanDanoVivienda · roundtrip JSON', () {
    test('toJson → fromJson preserva viviendas y contadores', () {
      final fila = EdanDanoVivienda(
        idSeccion: 'b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2',
        comunidad: 'Comunidad 1',
        viviendas: [
          _v('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa', EdanViviendaTipo.total),
          _v('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb', EdanViviendaTipo.total),
          _v('cccccccc-cccc-4ccc-8ccc-cccccccccccc', EdanViviendaTipo.parcial),
        ],
      );

      final restaurada =
          EdanDanoVivienda.fromJson(fila.toJson());

      expect(restaurada.viviendas, hasLength(3));
      expect(restaurada.viviendasTotal, 2);
      expect(restaurada.viviendasParcial, 1);
      expect(restaurada.viviendas.map((v) => v.uuidRegistro),
          containsAll([
            'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',
            'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',
            'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
          ]));
    });
  });

  group('EdanStoreV2 · CRUD de viviendas', () {
    Future<EdanStoreV2> _store() async {
      await db.database;
      return EdanStoreV2(db: db);
    }

    Future<void> _seedFilaDanosVivienda(String uuid) =>
        db.database.then((d) => d.insert('filas_seccion', {
              'uuid_registro': uuid,
              'uuid_edan_localidad': 'loc-1',
              'tipo': 'danos_vivienda',
              'datos_json': '{}',
              'estado_sync': 'confirmado',
            }));

    test('guardarViviendas → cargarViviendas roundtrip con case TOTAL/PARCIAL',
        () async {
      final store = await _store();
      await _seedFilaDanosVivienda('b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2');

      await store.guardarVivienda(_v('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa', EdanViviendaTipo.total));
      await store.guardarVivienda(_v('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb', EdanViviendaTipo.total));
      await store.guardarVivienda(_v('cccccccc-cccc-4ccc-8ccc-cccccccccccc', EdanViviendaTipo.parcial));

      final cargadas = await store.cargarViviendas('b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2');
      expect(cargadas, hasLength(3));
      expect(cargadas.where((v) => v.tipoDano == EdanViviendaTipo.total),
          hasLength(2));
      expect(cargadas.where((v) => v.tipoDano == EdanViviendaTipo.parcial),
          hasLength(1));

      // El CHECK de la tabla exige mayúsculas; verificar el valor crudo.
      final crudo = await (await db.database).query('viviendas',
          where: 'uuid_registro = ?',
          whereArgs: ['aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa']);
      expect(crudo.first['tipo_dano'], 'TOTAL');
    });

    test('guardarVivienda asigna uuidRegistro si falta', () async {
      final store = await _store();
      await _seedFilaDanosVivienda('b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2');
      final v = EdanVivienda(
        uuidDanoVivienda: 'b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2',
        tipoDano: EdanViviendaTipo.parcial,
      );
      expect(v.uuidRegistro, isNull);

      await store.guardarVivienda(v);

      expect(v.uuidRegistro, isNotNull);
      expect(v.uuidRegistro, isNotEmpty);
      final cargadas = await store.cargarViviendas('b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2');
      expect(cargadas, hasLength(1));
    });

    test('eliminarVivienda borra la fila (baja) y los conteos se actualizan',
        () async {
      final store = await _store();
      await _seedFilaDanosVivienda('b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2');
      await store.guardarVivienda(_v('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa', EdanViviendaTipo.total));
      await store.guardarVivienda(_v('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb', EdanViviendaTipo.total));
      await store.guardarVivienda(_v('cccccccc-cccc-4ccc-8ccc-cccccccccccc', EdanViviendaTipo.parcial));

      await store.eliminarVivienda(
          'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa');

      final cargadas = await store.cargarViviendas('b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2');
      expect(cargadas, hasLength(2));
      expect(cargadas.where((v) => v.tipoDano == EdanViviendaTipo.total),
          hasLength(1),
          reason: 'baja de una TOTAL recalcula el conteo derivado');
    });

    test('2 filas con 3 viviendas en total (2 TOTAL/1 PARCIAL)', () async {
      final store = await _store();
      await _seedFilaDanosVivienda('b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2');
      await _seedFilaDanosVivienda('dv-2');

      // Fila 1: 2 viviendas (1 TOTAL, 1 PARCIAL).
      await store.guardarVivienda(_v('a1', EdanViviendaTipo.total,
          uuidDano: 'b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2'));
      await store.guardarVivienda(_v('a2', EdanViviendaTipo.parcial,
          uuidDano: 'b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2'));
      // Fila 2: 1 vivienda TOTAL.
      await store.guardarVivienda(_v('b1', EdanViviendaTipo.total,
          uuidDano: 'dv-2'));

      final fila1 = await store.cargarViviendas('b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2');
      final fila2 = await store.cargarViviendas('dv-2');
      expect(fila1, hasLength(2));
      expect(fila2, hasLength(1));

      final total =
          fila1.where((v) => v.tipoDano == EdanViviendaTipo.total).length +
              fila2.where((v) => v.tipoDano == EdanViviendaTipo.total).length;
      final parcial =
          fila1.where((v) => v.tipoDano == EdanViviendaTipo.parcial).length +
              fila2.where((v) => v.tipoDano == EdanViviendaTipo.parcial).length;
      expect(total, 2);
      expect(parcial, 1);
    });
  });
}