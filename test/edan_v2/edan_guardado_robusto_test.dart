/// Robustez del guardado: nada en los datos tumba la transacción completa.
///
/// Cubre: NaN en doubles, datos_json corrupto (reapertura y lista),
/// id_server duplicado (UNIQUE), fila corrupta en reapertura.
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
    dir = await Directory.systemTemp.createTemp('edan_robusto');
    DatabaseHelper.rutaDePrueba = p.join(dir.path, 'test.db');
  });

  tearDown(() async {
    await db.cerrarParaPrueba();
    DatabaseHelper.rutaDePrueba = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('sanearJson/decodificarSeguro', () {
    test('NaN/Infinity/DateTime no rompen jsonEncode', () async {
      expect(
        () => EdanStoreV2.sanearJson({
          'a': double.nan,
          'b': double.infinity,
          'c': DateTime(2026),
          'd': [
            {'x': 1.0}
          ],
        }),
        returnsNormally,
      );
      final s = EdanStoreV2.sanearJson({'a': double.nan});
      expect(s['a'], isNull);
    });

    test('decodificarSeguro tolera todo', () {
      expect(EdanStoreV2.decodificarSeguro(null), isNull);
      expect(EdanStoreV2.decodificarSeguro(''), isNull);
      expect(EdanStoreV2.decodificarSeguro('{truncado'), isNull);
      expect(EdanStoreV2.decodificarSeguro('[]'), isNull);
      expect(
          EdanStoreV2.decodificarSeguro('{"a":1}'), {'a': 1});
    });
  });

  group('guardado tolerante', () {
    test('datos_json corrupto no vacía la lista', () async {
      final database = await db.database;
      await database.insert('formularios', {
        'uuid_edan_localidad': 'u-mala',
        'localidad': 'Mala',
      });
      await database.insert('formularios', {
        'uuid_edan_localidad': 'u-buena',
        'localidad': 'Buena',
      });
      await database.update(
        'formularios',
        {'datos_json': '{truncado'},
        where: 'uuid_edan_localidad = ?',
        whereArgs: ['u-mala'],
      );

      final locs =
          await EdanStoreV2(db: db).listarReportes(usuarioId: null);
      expect(locs.map((l) => l.uuidEdanLocalidad),
          containsAll(['u-mala', 'u-buena']),
          reason: 'una fila corrupta no vacía la lista');
    });

    test('id_server duplicado se libera y guarda igual', () async {
      final store = EdanStoreV2(db: db);
      final a = EdanLocalidad(
          nombre: 'A', idTipoEvento: 1, uuidEdanLocalidad: 'u-dup-a')
        ..idServer = 999;
      await store.guardarFormulario(a, usuarioId: 1);
      final b = EdanLocalidad(
          nombre: 'B', idTipoEvento: 1, uuidEdanLocalidad: 'u-dup-b')
        ..idServer = 999;
      await store.guardarFormulario(b, usuarioId: 1);

      final database = await db.database;
      final rows = await database.query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: ['u-dup-b']);
      expect(rows, hasLength(1));
      expect(rows.first['id_server'], isNull,
          reason: 'duplicado liberado para autocurarse por POST→PUT');
      expect(rows.first['localidad'], 'B');
    });

    test('fila corrupta no tumba la reapertura de secciones', () async {      final store = EdanStoreV2(db: db);
      final database = await db.database;
      await database.insert('formularios', {
        'uuid_edan_localidad': 'u-cor',
        'localidad': 'Cor',
        'datos_json': '{}',
      });
      await database.insert('filas_seccion', {
        'uuid_registro': 'f-mala',
        'uuid_edan_localidad': 'u-cor',
        'tipo': 'danos-agricultura',
        'datos_json': '{corrupto',
      });
      await database.insert('filas_seccion', {
        'uuid_registro': 'aaaaaaaa-0000-4000-8000-00000000c011',
        'uuid_edan_localidad': 'u-cor',
        'tipo': 'danos-agricultura',
        'datos_json':
            '{"uuid_registro":"aaaaaaaa-0000-4000-8000-00000000c011","tipo_cultivo":"MAIZ"}',
      });

      final loc = EdanLocalidad(
          nombre: 'Cor', uuidEdanLocalidad: 'u-cor');
      await store.cargarSecciones(loc);

      expect(
          loc.danosAgricultura.map((f) => f.idSeccion),
          contains('aaaaaaaa-0000-4000-8000-00000000c011'),
          reason: 'la fila buena carga aunque otra esté corrupta');
    });
  });

  group('toApiJson en todas las secciones (crash vivo)', () {
    test('guardarTodo con impacto+primera+humanitaria no crashea', () async {
      final store = EdanStoreV2(db: db);
      final loc = EdanLocalidad(
        nombre: 'Loc Crash',
        idTipoEvento: 1,
        uuidEdanLocalidad: 'u-crash',
      )
        ..impactoPoblacion = [
          EdanImpactoPoblacion(
            grupoEtario: 'Niño (a) 0-5 años',
            fallecidos: 1,
          ),
        ]
        ..necesidadPrimeraRespuesta = (EdanNecesidadPrimeraRespuesta()
          ..busqueda = true)
        ..necesidadHumanitaria = (EdanNecesidadHumanitaria()
          ..alimentos = true);
      await store.guardarTodo(
        loc,
        usuarioId: 1,
        seccionesActivas: const [],
        tipos: const [
          'impacto-poblacion',
          'primera-respuesta',
          'necesidad-humanitaria',
        ],
      );

      final database = await db.database;
      for (final tipo in [
        'impacto-poblacion',
        'primera-respuesta',
        'necesidad-humanitaria'
      ]) {
        final rows = await database.query('filas_seccion',
            where: 'uuid_edan_localidad = ? AND tipo = ?',
            whereArgs: ['u-crash', tipo]);
        expect(rows, isNotEmpty,
            reason: '$tipo persiste sin NoSuchMethodError');
      }
    });

    test('impacto resuelve id_grupo_etario para el padding 4', () {
      final item = EdanImpactoPoblacion(
        grupoEtario: 'Niño (a) 0-5 años',
        fallecidos: 2,
      );
      expect(item.toApiJson()['id_grupo_etario'], 1,
          reason: 'el servidor exige el set 1-4');
    });
  });

  group('datosVersion (la lista se entera)', () {
    test('guardarTodo y eliminar incrementan datosVersion', () async {
      final store = EdanStoreV2(db: db);
      final antes = store.datosVersion.value;
      final loc = EdanLocalidad(
        nombre: 'Loc V',
        idTipoEvento: 1,
        uuidEdanLocalidad: 'u-ver',
      );
      await store.guardarTodo(
        loc,
        usuarioId: 1,
        seccionesActivas: const [],
        tipos: const [],
      );
      expect(store.datosVersion.value, antes + 1,
          reason: 'guardar avisa a la lista');
      await store.eliminarLocalidad('u-ver');
      expect(store.datosVersion.value, antes + 2,
          reason: 'borrar avisa a la lista');
    });

    test('marcarEnvioPendiente avisa (banner de la tarjeta)', () async {
      final store = EdanStoreV2(db: db);
      final loc = EdanLocalidad(
        nombre: 'Loc W',
        idTipoEvento: 1,
        uuidEdanLocalidad: 'u-w',
      );
      await store.guardarFormulario(loc, usuarioId: 1);
      final antes = store.datosVersion.value;
      await store.marcarEnvioPendiente('u-w', 2);
      expect(store.datosVersion.value, antes + 1);
    });
  });
}
