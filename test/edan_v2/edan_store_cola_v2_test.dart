/// Cola de sincronización y activación de grupos (Fase 7) en `EdanStoreV2`.
///
/// Fija el contrato §5.2/§16: guardar la cabecera o una fila la marca
/// `pendiente` en `cola_sincronizacion` (upsert idempotente por
/// `(tabla, uuid, accion)`), y las secciones activas (grupos de page01, p.ej.
/// `grupAgropecuario` → agricultura/pecuarios/infra-productiva) se persisten en
/// `secciones_activas_json` sin perderse al re-guardar.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rea/models/edan.dart';
import 'package:rea/models/edan_registro_v2.dart';
import 'package:rea/services/database_helper.dart';
import 'package:rea/services/edan/edan_store_v2.dart';
import 'package:rea/services/edan/edan_uuid_helper.dart';
import 'package:rea/services/edan_secciones_registry.dart';
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
    dir = await Directory.systemTemp.createTemp('edan_cola');
    DatabaseHelper.rutaDePrueba = p.join(dir.path, 'test.db');
  });

  tearDown(() async {
    await db.cerrarParaPrueba();
    DatabaseHelper.rutaDePrueba = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  EdanLocalidad _loc({String? uuid}) => EdanLocalidad(
        nombre: 'Comunidad Test',
        idTipoEvento: 1,
        uuidEdanLocalidad: uuid,
      );

  Future<List<Map<String, Object?>>> _cola(EdanStoreV2 store,
      {String? tabla}) async {
    final database = await db.database;
    return database.query(
      'cola_sincronizacion',
      where: tabla != null ? 'tabla = ?' : null,
      whereArgs: tabla != null ? [tabla] : null,
      orderBy: 'id',
    );
  }

  group('guardarFormulario · pendiente_push (Fase D)', () {
    test('marca pendiente_push=1 al guardar', () async {
      final store = EdanStoreV2(db: db);
      final loc = _loc();
      await store.guardarFormulario(loc, usuarioId: 1);

      final f = await (await db.database).query('formularios',
          columns: ['pendiente_push'],
          where: 'uuid_edan_localidad = ?',
          whereArgs: [loc.uuidEdanLocalidad]);
      expect(f.first['pendiente_push'], 1);
    });

    test('NO encola C/U en cola_sincronizacion (solo D)', () async {
      final store = EdanStoreV2(db: db);
      final loc = _loc();
      await store.guardarFormulario(loc, usuarioId: 1);

      final cola = await _cola(store, tabla: 'formulario');
      expect(cola, isEmpty,
          reason: 'la cola solo queda para accion=D (borrados)');
    });
  });

  group('guardarFormulario · preservación de grupos (secciones_activas_json)',
      () {
    test('grupos imp_* de page01 se persisten como rutas activas', () async {
      final store = EdanStoreV2(db: db);
      final loc = _loc()..grupAgropecuario = true..grupVivienda = true;
      final activas = EdanSeccionesRegistry.construirFlagsDesdeActivas(
          _rutasAgropecuario() + ['danos-vivienda']);
      // Simula las rutas activas derivadas de los flags de page01.
      final rutas = <String>[
        ...EdanSeccionesRegistry.checkboxSecciones['grupAgropecuario']!,
        ...EdanSeccionesRegistry.checkboxSecciones['grupVivienda']!,
      ];
      await store.guardarFormulario(loc, usuarioId: 1,
          seccionesActivas: rutas);

      final leidas = await store.leerSeccionesActivas(loc.uuidEdanLocalidad!);
      expect(leidas, containsAll(rutas));
      expect(activas['grup_agropecuario'], isTrue);
    });

    test('re-guardar SIN seccionesActivas NO borra las grupos existentes',
        () async {
      final store = EdanStoreV2(db: db);
      final loc = _loc();
      final rutas = EdanSeccionesRegistry.checkboxSecciones['grupAgropecuario']!;
      await store.guardarFormulario(loc, usuarioId: 1,
          seccionesActivas: rutas);

      // Re-guarda desde guardarFilas (sin el parámetro): debe preservar.
      await store.guardarFormulario(loc, usuarioId: 1);

      final leidas = await store.leerSeccionesActivas(loc.uuidEdanLocalidad!);
      expect(leidas, containsAll(rutas),
          reason: 'no perder la activación de grupos al re-guardar');
    });
  });

  group('guardarFormulario · preservación de la cabecera sincronizada', () {
    test('no pierde datos_json_servidor al re-guardar', () async {
      final store = EdanStoreV2(db: db);
      final loc = _loc();
      await store.guardarFormulario(loc, usuarioId: 1);

      // Simula el resultado de un pull exitoso (`GET /completo`).
      final doc = jsonEncode({'uuid_edan_localidad': loc.uuidEdanLocalidad});
      await (await db.database).update(
        'formularios',
        {'datos_json_servidor': doc},
        where: 'uuid_edan_localidad = ?',
        whereArgs: [loc.uuidEdanLocalidad],
      );

      // Re-guardar desde el wizard/`guardarFilas`: usa INSERT OR REPLACE.
      await store.guardarFormulario(loc, usuarioId: 1);

      final f = await (await db.database).query(
        'formularios',
        columns: ['datos_json_servidor'],
        where: 'uuid_edan_localidad = ?',
        whereArgs: [loc.uuidEdanLocalidad],
      );
      expect(f.first['datos_json_servidor'], doc,
          reason: 'la caché GET del depurador no debe borrarse al editar');
    });
  });

  group('guardarFilas · Fase D (cola solo D)', () {
    test('persiste filas 1:N sin encolar C/U (van por /completo)', () async {
      final store = EdanStoreV2(db: db);
      final loc = _loc();
      await store.guardarFormulario(loc, usuarioId: 1);
      final uuid = loc.uuidEdanLocalidad!;

      loc.danosVivienda = [
        EdanDanoVivienda(idSeccion: '11111111-1111-4111-8111-111111111111'),
        EdanDanoVivienda(idSeccion: '22222222-2222-4222-8222-222222222222'),
      ];
      await store.guardarFilas(uuid, ['danos-vivienda'], loc);

      final dbLocal = await db.database;
      final filas = await dbLocal.query('filas_seccion',
          where: 'uuid_edan_localidad = ?', whereArgs: [uuid]);
      expect(filas, hasLength(2),
          reason: 'las filas se persisten en SQLite');
      final cola = await _cola(store, tabla: 'filas_seccion');
      expect(cola, isEmpty,
          reason: 'la cola solo queda para accion=D (borrados)');
    });

    test(
        'guardarFilas con MÚLTIPLES rutas persiste filas de todas las '
        'secciones (contrato de "guardar todas las activas", P1)', () async {
      final store = EdanStoreV2(db: db);
      final loc = _loc();
      await store.guardarFormulario(loc, usuarioId: 1);
      final uuid = loc.uuidEdanLocalidad!;

      loc.danosVivienda = [EdanDanoVivienda(idSeccion: '33333333-3333-4333-8333-333333333333')];
      loc.danosAgricultura = [
        // Contrato "solo lo llenado" (2026-10-17): una fila de agricultura
        // sin `tipo_cultivo` NO se persiste; se le da datos reales para que
        // la prueba siga cubriendo "persiste en AMBAS rutas".
        EdanDanoAgricultura(
            idSeccion: '44444444-4444-4444-8444-444444444444',
            tipoCultivo: 'MAIZ'),
      ];

      await store.guardarFilas(
        uuid,
        ['danos-vivienda', 'danos-agricultura'],
        loc,
      );

      final dbLocal = await db.database;
      final filas = await dbLocal.query('filas_seccion',
          where: 'uuid_edan_localidad = ?', whereArgs: [uuid]);
      expect(filas, hasLength(2),
          reason: 'las dos secciones activas deben persistir, no solo una');
      expect(filas.map((r) => r['tipo']).toSet(),
          {'danos-vivienda', 'danos-agricultura'});
      expect(filas.map((r) => r['uuid_registro']).toSet(),
          {'33333333-3333-4333-8333-333333333333', '44444444-4444-4444-8444-444444444444'});
    });

    test('persiste viviendas de una fila danos_vivienda sin encolar', () async {
      final store = EdanStoreV2(db: db);
      final loc = _loc();
      await store.guardarFormulario(loc, usuarioId: 1);
      final uuid = loc.uuidEdanLocalidad!;

      final fila = EdanDanoVivienda(
        idSeccion: '55555555-5555-4555-8555-555555555555',
        viviendas: [
          EdanVivienda(
            uuidRegistro: '33333333-3333-4333-8333-333333333333',
            uuidDanoVivienda: '55555555-5555-4555-8555-555555555555',
            tipoDano: EdanViviendaTipo.total,
          ),
          EdanVivienda(
            uuidRegistro: '66666666-6666-4666-8666-666666666666',
            uuidDanoVivienda: '55555555-5555-4555-8555-555555555555',
            tipoDano: EdanViviendaTipo.parcial,
          ),
        ],
      );
      loc.danosVivienda = [fila];
      await store.guardarFilas(uuid, ['danos-vivienda'], loc);

      final dbViv = await db.database;
      final rows = await dbViv.query('viviendas',
          where: 'uuid_dano_vivienda = ?', whereArgs: ['55555555-5555-4555-8555-555555555555']);
      expect(rows, hasLength(2));
      final cola = await _cola(store, tabla: 'vivienda');
      expect(cola, isEmpty, reason: 'la cola solo queda para D');
    });

    test('baja de vivienda encola accion D (el único caso que usa la cola)',
        () async {
      final store = EdanStoreV2(db: db);
      final loc = _loc();
      await store.guardarFormulario(loc, usuarioId: 1);
      final uuid = loc.uuidEdanLocalidad!;

      final fila = EdanDanoVivienda(
        idSeccion: '77777777-7777-4777-8777-777777777777',
        viviendas: [
          EdanVivienda(
              uuidRegistro: '88888888-8888-4888-8888-888888888888',
              uuidDanoVivienda: '77777777-7777-4777-8777-777777777777',
              tipoDano: EdanViviendaTipo.total),
          EdanVivienda(
              uuidRegistro: '99999999-9999-4999-8999-999999999999',
              uuidDanoVivienda: '77777777-7777-4777-8777-777777777777',
              tipoDano: EdanViviendaTipo.parcial),
        ],
      );
      loc.danosVivienda = [fila];
      await store.guardarFilas(uuid, ['danos-vivienda'], loc);

      // Quita viv-b del modelo y re-guarda: debe encolar su baja.
      fila.viviendas.removeWhere((v) => v.uuidRegistro == '99999999-9999-4999-8999-999999999999');
      await store.guardarFilas(uuid, ['danos-vivienda'], loc);

      final vivCola = await _cola(store, tabla: 'vivienda');
      expect(vivCola, hasLength(1),
          reason: 'solo el D de viv-b; el C de viv-a va por /completo');
      expect(vivCola.first['uuid_registro'], '99999999-9999-4999-8999-999999999999');
      expect(vivCola.first['accion'], 'D');

      final dbViv = await db.database;
      final restantes = await dbViv.query('viviendas',
          where: 'uuid_dano_vivienda = ?', whereArgs: ['77777777-7777-4777-8777-777777777777']);
      expect(restantes, hasLength(1));
      expect(restantes.first['uuid_registro'], '88888888-8888-4888-8888-888888888888');
    });
  });

  group('guardarFilas · sección protección (regresión toApiJson)', () {
    test('defaults sin datos no persisten; con un grupo lleno, set exacto 8 '
        'sin encolar (regresión toApiJson + contrato 2026-10-17)', () async {
      final store = EdanStoreV2(db: db);
      final loc = _loc();
      await store.guardarFormulario(loc, usuarioId: 1);
      final uuid = loc.uuidEdanLocalidad!;

      // `EdanLocalidad()` trae 8 grupos `proteccion` por defecto. Dos
      // regresiones conviven acá: (1) `registrarFila` llamaba
      // `item.toApiJson()` sin resolver el `id_grupo_vulnerable_catalogo`
      // (los defaults solo traen nombre → hoy el resolver lo deriva); (2) el
      // contrato "solo lo llenado": guardados VACÍOS no persisten, y en cuanto
      // hay un grupo con datos el servidor exige el set EXACTO de 8.
      expect(loc.proteccion, hasLength(8));
      await store.guardarFilas(uuid, ['proteccion'], loc);
      final dbLocal = await db.database;
      expect(
          await dbLocal.query('filas_seccion',
              where: 'tipo = ? AND uuid_edan_localidad = ?',
              whereArgs: ['proteccion', uuid]),
          isEmpty,
          reason: 'los 8 defaults vacíos no se persisten');

      loc.proteccion[0].mujeres = 1;
      loc.recalcularImpDesdeListas();
      await store.guardarFilas(uuid, ['proteccion'], loc);

      final filas = await dbLocal.query('filas_seccion',
          where: 'tipo = ? AND uuid_edan_localidad = ?',
          whereArgs: ['proteccion', uuid]);
      expect(filas, hasLength(8), reason: 'set exacto: 1 lleno + 7 de relleno');
      expect(filas.every((r) => r['datos_json'] != null), isTrue);
      final ids = filas.map((r) {
        final dec =
            jsonDecode(r['datos_json'] as String) as Map<String, dynamic>;
        return dec['id_grupo_vulnerable_catalogo'];
      }).toSet();
      expect(ids, {1, 2, 3, 4, 5, 6, 7, 8},
          reason: 'los defaults resuelven su id de catálogo por nombre');

      final cola = await _cola(store, tabla: 'filas_seccion');
      expect(cola, isEmpty, reason: 'la cola solo queda para D');
    });

    test('marcarBorradoFormulario borra viviendas por su fila danos_vivienda',
        () async {
      final store = EdanStoreV2(db: db);
      final loc = _loc();
      await store.guardarFormulario(loc, usuarioId: 1);
      final uuid = loc.uuidEdanLocalidad!;

      loc.danosVivienda = [
        EdanDanoVivienda(
          idSeccion: 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',
          viviendas: [
            EdanVivienda(
              uuidRegistro: 'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',
              uuidDanoVivienda: 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',
              tipoDano: EdanViviendaTipo.total,
            ),
          ],
        ),
      ];
      await store.guardarFilas(uuid, ['danos-vivienda'], loc);

      await store.marcarBorradoFormulario(uuid);

      final dbLocal = await db.database;
      final restantes = await dbLocal.query('viviendas',
          where: 'uuid_dano_vivienda = ?', whereArgs: ['aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa']);
      expect(restantes, isEmpty,
          reason: 'las viviendas hijas deben borrarse con su formulario');
    });
  });

  group('Etapa 3 · guardarTodo atómico + preservación de estado', () {
    test('guardarTodo persiste cabecera + filas en una llamada', () async {
      final store = EdanStoreV2(db: db);
      final loc = _loc();
      loc.danosVivienda = [
        EdanDanoVivienda(
          idSeccion: 'd0d0d0d0-d0d0-4d0d-8d0d-d0d0d0d0d0d0',
          comunidad: 'B',
          viviendas: [
            EdanVivienda(
              uuidRegistro: 'e1e1e1e1-e1e1-4e1e-8e1e-e1e1e1e1e1e1',
              uuidDanoVivienda: 'd0d0d0d0-d0d0-4d0d-8d0d-d0d0d0d0d0d0',
              tipoDano: EdanViviendaTipo.total,
            ),
          ],
        ),
      ];
      await store.guardarTodo(loc,
          usuarioId: 1,
          seccionesActivas: ['danos-vivienda'],
          tipos: ['danos-vivienda']);

      final dbLocal = await db.database;
      final forms = await dbLocal.query('formularios',
          where: 'uuid_edan_localidad = ?',
          whereArgs: [loc.uuidEdanLocalidad]);
      expect(forms, hasLength(1));
      expect(forms.first['pendiente_push'], 1);
      final filas = await dbLocal.query('filas_seccion',
          where: 'uuid_edan_localidad = ?',
          whereArgs: [loc.uuidEdanLocalidad]);
      expect(filas.map((r) => r['uuid_registro']), contains('d0d0d0d0-d0d0-4d0d-8d0d-d0d0d0d0d0d0'));
      final vivs = await dbLocal.query('viviendas',
          where: 'uuid_dano_vivienda = ?', whereArgs: ['d0d0d0d0-d0d0-4d0d-8d0d-d0d0d0d0d0d0']);
      expect(vivs.map((r) => r['uuid_registro']), contains('e1e1e1e1-e1e1-4e1e-8e1e-e1e1e1e1e1e1'));
    });

    test('re-guardar conserva estado_local y degrada synced→pending_update',
        () async {
      final store = EdanStoreV2(db: db);
      final loc = _loc();
      await store.guardarFormulario(loc, usuarioId: 1);
      final uuid = loc.uuidEdanLocalidad!;
      // Simula confirmación del motor + envío del usuario.
      await (await db.database).update(
          'formularios',
          {'sync_state': 'synced', 'estado_local': 'enviado'},
          where: 'uuid_edan_localidad = ?',
          whereArgs: [uuid]);

      loc.nombre = 'Editado';
      await store.guardarFormulario(loc, usuarioId: 1);

      final rows = await (await db.database).query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: [uuid]);
      expect(rows.first['estado_local'], 'enviado',
          reason: 'arquitectura §6: re-guardar no degrada el estado de negocio');
      expect(rows.first['sync_state'], 'pending_update',
          reason: 'cambios sobre confirmado vuelven a pendiente de subida');
      expect(rows.first['localidad'], 'Editado');
    });

    test('encolar genera operation_uuid + idempotency_key', () async {
      final store = EdanStoreV2(db: db);
      await store.encolar(
          tabla: 'filas_seccion', uuidRegistro: 'u-op', accion: 'D');
      final cola = await _cola(store, tabla: 'filas_seccion');
      expect(cola, hasLength(1));
      expect(cola.first['operation_uuid'], isNotNull);
      expect(cola.first['idempotency_key'], cola.first['operation_uuid']);
    });
  });

  group('Etapa 4 · fotos: tipo_entidad canónico + metadatos + sha', () {
    Future<String> _fotoTemp(String nombre, List<int> bytes) async {
      final f = File(p.join(dir.path, nombre));
      await f.writeAsBytes(bytes, flush: true);
      return f.path;
    }

    test('sha256Archivo en streaming coincide con el hash en memoria',
        () async {
      final ruta = await _fotoTemp('sha.bin', [1, 2, 3, 4, 5]);
      final esperado =
          EdanUuidHelper.sha256Bytes(Uint8List.fromList([1, 2, 3, 4, 5]));
      expect(await EdanUuidHelper.sha256Archivo(ruta), esperado);
      expect(await EdanUuidHelper.sha256Archivo('$ruta.noexiste'), isNull);
    });

    test('registrarFoto persiste tipo canónico + metadatos v35', () async {
      final store = EdanStoreV2(db: db);
      final ruta = await _fotoTemp('f1.jpg', List.filled(100, 7));
      final loc = _loc();
      await store.guardarFormulario(loc, usuarioId: 1);
      await store.guardarFilas(loc.uuidEdanLocalidad!, ['danos-agricultura'],
          loc..danosAgricultura = []);
      // Fila real para derivar la dueña.
      final dbLocal = await db.database;
      await dbLocal.insert('filas_seccion', {
        'uuid_registro': 'f2f2f2f2-f2f2-4f2f-8f2f-f2f2f2f2f2f2',
        'uuid_edan_localidad': loc.uuidEdanLocalidad,
        'tipo': 'danos-agricultura',
        'datos_json': '{}',
      });

      final foto = EdanFoto(ruta: ruta);
      await store.registrarFoto(foto, 'danos_agricultura', 'f2f2f2f2-f2f2-4f2f-8f2f-f2f2f2f2f2f2');
      expect(foto.uuidFotografia, isNotNull);
      expect(foto.tipoEntidad, 'danos_agricultura');
      expect(foto.sha256, isNotNull);

      final rows = await dbLocal.query('fotografias',
          where: 'uuid_fotografia = ?', whereArgs: [foto.uuidFotografia]);
      expect(rows.first['upload_state'], 'pending');
      expect(rows.first['file_name'], 'f1.jpg');
      expect(rows.first['mime_type'], 'image/jpeg');
      expect(rows.first['size_bytes'], 100);

      await store.encolarFoto(foto);
      final cola = await dbLocal.query('cola_fotos',
          where: 'uuid_fotografia = ?', whereArgs: [foto.uuidFotografia]);
      expect(cola.first['mime_type'], 'image/jpeg');
      expect(cola.first['size_bytes'], 100);
    });

    test("marcador 'filas_seccion' se deriva de la dueña, no se persiste",
        () async {
      final store = EdanStoreV2(db: db);
      final ruta = await _fotoTemp('f2.jpg', [9]);
      final dbLocal = await db.database;
      await dbLocal.insert('filas_seccion', {
        'uuid_registro': 'a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1',
        'uuid_edan_localidad': 'loc-x',
        'tipo': 'danos-viales',
        'datos_json': '{}',
      });

      final foto = EdanFoto(ruta: ruta);
      await store.registrarFoto(foto, 'filas_seccion', 'a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1');
      expect(foto.tipoEntidad, 'danos_viales',
          reason: 'el marcador local nunca viaja (server: 400)');

      // Hidratación tolerante: el lector legacy la encuentra igual.
      final leidas =
          await store.cargarFotosDeEntidad('filas_seccion', 'a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1');
      expect(leidas.map((f) => f.uuidFotografia),
          contains(foto.uuidFotografia));
    });

    test('tipo irresoluble sin dueña se rechaza en local', () async {
      final store = EdanStoreV2(db: db);
      final ruta = await _fotoTemp('f3.jpg', [9]);
      expect(
        () => store.registrarFoto(EdanFoto(ruta: ruta), 'filas_seccion', 'nada'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Etapa 5 · listado unificado + fotos en memoria', () {
    test('listarReportes une V2 + legacy sin duplicar por uuid', () async {
      final store = EdanStoreV2(db: db);
      final loc = _loc();
      await store.guardarFormulario(loc, usuarioId: 1);
      final uuid = loc.uuidEdanLocalidad!;

      // Espejo legacy con el MISMO uuid (doble-escritor viejo) + uno huérfano.
      final dbLocal = await db.database;
      final ahora = DateTime.now().toIso8601String();
      await dbLocal.insert('localidades_offline', {
        'id_local': uuid,
        'usuario_id': 1,
        'localidad': 'Duplicado',
        'datos_json': '{}',
        'pendiente_eliminacion': 0,
        'fecha_creacion': ahora,
      });
      await dbLocal.insert('localidades_offline', {
        'id_local': 'legacy-solo',
        'usuario_id': 1,
        'localidad': 'Huerfano',
        'datos_json': '{}',
        'pendiente_eliminacion': 0,
        'fecha_creacion': ahora,
      });

      final lista = await store.listarReportes(usuarioId: 1);
      final ids = lista.map((l) => l.uuidEdanLocalidad ?? l.idLocal).toList();
      expect(ids.where((id) => id == uuid), hasLength(1),
          reason: 'el espejo legacy no duplica la fila V2');
      expect(ids, contains('legacy-solo'),
          reason: 'lo legacy sin contraparte V2 sigue visible');
    });

    test('registrarFotosEnMemoria registra las fotos del modelo', () async {
      final store = EdanStoreV2(db: db);
      final ruta = File(p.join(dir.path, 'mem.jpg'));
      await ruta.writeAsBytes([1, 2, 3]);
      final loc = _loc();
      loc.danosViales = [
        EdanDanoVial(
            idSeccion: 'f0f0f0f0-f0f0-4f0f-8f0f-f0f0f0f0f0f0',
            tramo: 'T',
            fotos: [
              EdanFoto(ruta: ruta.path),
            ]),
      ];
      await store.guardarTodo(loc,
          usuarioId: 1,
          seccionesActivas: ['danos-viales'],
          tipos: ['danos-viales']);
      await store.registrarFotosEnMemoria(loc);

      final fotos = await store.cargarFotosDeEntidad(
          'danos_viales', 'f0f0f0f0-f0f0-4f0f-8f0f-f0f0f0f0f0f0');
      expect(fotos, hasLength(1));
      expect(fotos.first.uuidFotografia, isNotNull);
    });
  });

  group('derivarFlagsDesdeFilas: badges desde filas reales', () {
    test('una fila en filas_seccion enciende su sección (grup manda en DB)',
        () async {
      final store = EdanStoreV2(db: db);
      final loc = _loc();
      await store.guardarFormulario(loc, usuarioId: 1);
      final uuid = loc.uuidEdanLocalidad!;
      await (await db.database).insert('filas_seccion', {
        'uuid_registro': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'uuid_edan_localidad': uuid,
        'tipo': 'danos-agricultura',
        'datos_json': '{"tipo_cultivo":"Maíz"}',
        'estado_sync': 'confirmado',
      });

      final derivada = await store.derivarFlagsDesdeFilas(uuid);

      // En memoria: la sección se enciende (la UI la combina con el grupo).
      expect(derivada?.impDanosAgricultura, isTrue);
      // En DB: las columnas `grup_*` NO se tocan (las gobiernan page01 /
      // servidor; re-derivarlas re-encendería un grupo destildado).
      final dbLocal = await db.database;
      final row = (await dbLocal.query('formularios',
              where: 'uuid_edan_localidad = ?', whereArgs: [uuid]))
          .first;
      expect(row['grup_agropecuario'], 0,
          reason: 'grup manda: solo page01/servidor escriben columnas grup_*');
    });

    test('sin filas queda todo en false', () async {
      final store = EdanStoreV2(db: db);
      final loc = _loc();
      await store.guardarFormulario(loc, usuarioId: 1);
      final uuid = loc.uuidEdanLocalidad!;
      await (await db.database).insert('filas_seccion', {
        'uuid_registro': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'uuid_edan_localidad': uuid,
        'tipo': 'danos-agricultura',
        'datos_json': '{}',
        'estado_sync': 'confirmado',
      });
      // borrar la fila simula "no hay datos"
      await (await db.database)
          .delete('filas_seccion', where: 'uuid_edan_localidad = ?', whereArgs: [uuid]);

      await store.derivarFlagsDesdeFilas(uuid);

      final dbLocal = await db.database;
      final row = (await dbLocal.query('formularios',
              where: 'uuid_edan_localidad = ?', whereArgs: [uuid]))
          .first;
      expect(row['grup_agropecuario'], 0);
    });

    test('id_seccion con prefijo legacy no se guarda como uuid_registro',
        () async {
      expect(EdanUuidHelper.esUuidValido('po_abc123'), isFalse,
          reason: 'el prefijo legacy no es uuid: al persistir nace uno nuevo');
      expect(
          EdanUuidHelper.esUuidValido(
              'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
          isTrue);
    });
  });

  group('Migración única v1.2.0 → V2', () {
    Future<void> _legacyRow({
      required String idLocal,
      required Map<String, dynamic> datos,
    }) async {
      await (await db.database).insert('localidades_offline', {
        'id_local': idLocal,
        'usuario_id': 1,
        'localidad': datos['localidad'] ?? 'L',
        'datos_json': jsonEncode(datos),
        'pendiente_eliminacion': 0,
        'fecha_creacion': DateTime.now().toIso8601String(),
      });
    }

    test('migra N danos_vivienda → 1 padre + ids frescos, idempotente',
        () async {
      final store = EdanStoreV2(db: db);
      const uuid = '11111111-1111-4111-8111-111111111111';
      final loc = _loc(uuid: uuid)
        ..danosVivienda = [
          EdanDanoVivienda(
              idSeccion: 'dv_vieja1', comunidad: 'A', danoTotal: 2),
          EdanDanoVivienda(
              idSeccion: 'dv_vieja2', comunidad: 'B', danoParcial: 3),
        ]
        ..danosViales = [
          EdanDanoVial(idSeccion: 'dv_abc123', tramo: 'T', viaPuente: 'V'),
        ];
      await _legacyRow(idLocal: uuid, datos: loc.toJson());

      final n = await store.migrarLegadoV1(usuarioId: 1);
      expect(n, 1);

      final dbLocal = await db.database;
      final forms = await dbLocal.query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: [uuid]);
      expect(forms, hasLength(1), reason: 'reutiliza el id_local como uuid');
      final filas = await dbLocal.query('filas_seccion',
          where: 'uuid_edan_localidad = ?', whereArgs: [uuid]);
      final viales =
          filas.where((r) => r['tipo'] == 'danos-viales').toList();
      expect(viales, hasLength(1));
      expect(
          EdanUuidHelper.esUuidValido(
              viales.first['uuid_registro'] as String?),
          isTrue,
          reason: 'el prefijo legacy no viaja (daría 422)');
      final vivs = filas
          .where((r) => r['tipo'] == 'danos-vivienda')
          .toList();
      expect(vivs, hasLength(1), reason: 'colapso N→1 (server: máx 1)');
      final dv = jsonDecode(vivs.first['datos_json'] as String)
          as Map<String, dynamic>;
      expect(dv['comunidad'], 'A');
      expect(dv['observaciones'], contains('v1.2.0'));

      // Idempotente: segunda corrida no duplica ni remigra.
      expect(await store.migrarLegadoV1(usuarioId: 1), 0);
      final forms2 = await dbLocal.query('formularios',
          where: 'uuid_edan_localidad = ?', whereArgs: [uuid]);
      expect(forms2, hasLength(1));
    });
  });

  group('Estado negocio: la columna manda sobre el snapshot', () {
    Future<UgrLocalidadEstado?> _estadoDe(String uuid) async {
      final store = EdanStoreV2(db: db);
      final lista = await store.listarFormularios();
      for (final l in lista) {
        if (l.uuidEdanLocalidad == uuid) return l.estadoLocalidad;
      }
      return null;
    }

    test('id 3/6/4 → aprobadoUgr/enRevisionUgr/rechazadoUgr', () async {
      final dbLocal = await db.database;
      for (final e in [(3, 'a'), (6, 'b'), (4, 'c')]) {
        await dbLocal.insert('formularios', {
          'uuid_edan_localidad': 'u-est-${e.$2}',
          'localidad': 'X',
          'id_edan_localidad_estado': e.$1,
        });
      }
      expect(await _estadoDe('u-est-a'), UgrLocalidadEstado.aprobadoUgr);
      expect(await _estadoDe('u-est-b'), UgrLocalidadEstado.enRevisionUgr);
      expect(await _estadoDe('u-est-c'), UgrLocalidadEstado.rechazadoUgr);
    });

    test('el int del pull pisa el borrador del snapshot (bug reportado)',
        () async {
      final store = EdanStoreV2(db: db);
      final loc = _loc()..estadoLocalidad = UgrLocalidadEstado.borrador;
      await store.guardarFormulario(loc, usuarioId: 1);
      final uuid = loc.uuidEdanLocalidad!;
      // El servidor lo movió a aprobado (pull/estados escriben la columna).
      await (await db.database).update(
          'formularios', {'id_edan_localidad_estado': 3},
          where: 'uuid_edan_localidad = ?', whereArgs: [uuid]);
      expect(await _estadoDe(uuid), UgrLocalidadEstado.aprobadoUgr,
          reason: 'la UI lee el enum: debe reflejar la columna, no el snapshot');
    });

    test('sin estado en la fila se conserva el del snapshot', () async {
      final store = EdanStoreV2(db: db);
      final loc = _loc()..estadoLocalidad = UgrLocalidadEstado.borrador;
      await store.guardarFormulario(loc, usuarioId: 1);
      await (await db.database).update(
          'formularios', {'id_edan_localidad_estado': null},
          where: 'uuid_edan_localidad = ?',
          whereArgs: [loc.uuidEdanLocalidad]);
      expect(await _estadoDe(loc.uuidEdanLocalidad!),
          UgrLocalidadEstado.borrador);
    });
  });

  group('Ajuste Urubo: badge y vista desde el nodo grupos', () {
    test('aplicarGruposServidorAlModelo enciende el grupo del nodo', () async {
      final store = EdanStoreV2(db: db);
      final loc = _loc();
      await store.guardarFormulario(loc, usuarioId: 1);
      final uuid = loc.uuidEdanLocalidad!;
      // Nodo del servidor: solo agro en true (como el GET de Urubo).
      await store.guardarGruposServidor(uuid, {
        'grupPoblacion': false,
        'grupSalud': false,
        'grupInfraestructura': false,
        'grupServicios': false,
        'grupEducacion': false,
        'grupVivienda': false,
        'grupAgropecuario': true,
        'grupProteccion': false,
        'grupNecesidades': false,
      });

      final modelo = _loc(uuid: uuid);
      expect(modelo.grupAgropecuario, isFalse);
      await store.aplicarGruposServidorAlModelo(modelo);
      expect(modelo.grupAgropecuario, isTrue,
          reason: 'el nodo manda sobre el snapshot sin filas');
      expect(modelo.grupSalud, isFalse);
      expect(
          EdanSeccionesRegistry.seccionesActivasLabelsCortos(modelo),
          contains('Agricultura'),
          reason: 'badge del item = grupo del nodo');
    });

    test('sin caché no toca el modelo', () async {
      final store = EdanStoreV2(db: db);
      final modelo = _loc();
      await store.aplicarGruposServidorAlModelo(modelo);
      expect(modelo.grupAgropecuario, isFalse);
    });
  });

  group('Mapeo de grupos del registro', () {    test('grupAgropecuario activa agricultura + pecuarios + infra-productiva',
        () async {      final rutas =
          EdanSeccionesRegistry.checkboxSecciones['grupAgropecuario']!;
      expect(rutas, containsAll(
          ['danos-agricultura', 'danos-pecuarios', 'infra-productiva']));

      final flags =
          EdanSeccionesRegistry.construirFlagsDesdeActivas(rutas);
      expect(flags['grup_agropecuario'], isTrue);
      expect(flags['imp_danos_agricultura'], isTrue);
      expect(flags['imp_danos_pecuarios'], isTrue);
      expect(flags['imp_infra_productiva'], isTrue);
    });
  });

  group('Regla grup-manda (imp desde datos, grupos intactos)', () {
    test('recalcularImpDesdeListas enciende imp sin tocar grup', () {
      final loc = _loc()
        ..grupAgropecuario = true
        ..danosAgricultura = [
          EdanDanoAgricultura(tipoCultivo: 'Maíz', hectareasAfectadas: 2)
        ];
      expect(loc.impDanosAgricultura, isFalse);
      loc.recalcularImpDesdeListas();
      expect(loc.impDanosAgricultura, isTrue,
          reason: 'imp = tiene datos ahora');
      expect(loc.grupAgropecuario, isTrue,
          reason: 'page01 intacto: imp no gobierna grupos');
      expect(loc.grupSalud, isFalse);
      expect(loc.impDanosPecuarios, isFalse);
    });

    test('vaciarSecciones limpia listas y 1:1 sin tocar el resto', () {
      final loc = _loc()
        ..grupAgropecuario = true
        ..danosAgricultura = [EdanDanoAgricultura(tipoCultivo: 'X')]
        ..necesidadSalud = EdanNecesidadSalud(numeroPersonas: 3);
      loc.vaciarSecciones(['danos-agricultura', 'necesidad-salud']);
      expect(loc.danosAgricultura, isEmpty);
      expect(loc.necesidadSalud, isNull);
      expect(loc.grupAgropecuario, isTrue,
          reason: 'vaciar datos no destilda el grupo');
    });

    test('purgarSecciones borra filas y encola D si confirmada', () async {
      final store = EdanStoreV2(db: db);
      final loc = _loc();
      await store.guardarFormulario(loc, usuarioId: 1);
      final uuid = loc.uuidEdanLocalidad!;
      await (await db.database).insert('filas_seccion', {
        'uuid_registro': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'uuid_edan_localidad': uuid,
        'tipo': 'danos-agricultura',
        'datos_json': '{"tipo_cultivo":"Maíz"}',
        'estado_sync': 'confirmado',
      });

      await store.purgarSecciones(uuid, ['danos-agricultura']);

      final filas = await (await db.database).query('filas_seccion',
          where: 'uuid_edan_localidad = ?', whereArgs: [uuid]);
      expect(filas, isEmpty);
      final cola = await _cola(store, tabla: 'filas_seccion');
      expect(cola, hasLength(1));
      expect(cola.first['accion'], 'D');
      expect(cola.first['uuid_registro'],
          'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    });

    test('purgarSecciones no encola D si la fila nunca se confirmó',
        () async {      final store = EdanStoreV2(db: db);
      final loc = _loc();
      await store.guardarFormulario(loc, usuarioId: 1);
      final uuid = loc.uuidEdanLocalidad!;
      await (await db.database).insert('filas_seccion', {
        'uuid_registro': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        'uuid_edan_localidad': uuid,
        'tipo': 'danos-agricultura',
        'datos_json': '{}',
        'estado_sync': 'pendiente',
      });

      await store.purgarSecciones(uuid, ['danos-agricultura']);

      final filas = await (await db.database).query('filas_seccion',
          where: 'uuid_edan_localidad = ?', whereArgs: [uuid]);
      expect(filas, isEmpty);
      expect(await _cola(store, tabla: 'filas_seccion'), isEmpty,
          reason: 'lo nunca subido no deja borrado pendiente');
    });

    test('repararGruposLegacy enciende grupos de filas sin info (idempotente)',
        () async {
      final store = EdanStoreV2(db: db);
      final loc = _loc();
      await store.guardarFormulario(loc, usuarioId: 1);
      final uuid = loc.uuidEdanLocalidad!;
      await (await db.database).insert('filas_seccion', {
        'uuid_registro': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'uuid_edan_localidad': uuid,
        'tipo': 'danos-agricultura',
        'datos_json': '{}',
        'estado_sync': 'confirmado',
      });

      expect(await store.repararGruposLegacy(), 1);
      var row = (await (await db.database).query('formularios',
              where: 'uuid_edan_localidad = ?', whereArgs: [uuid]))
          .first;
      expect(row['grup_agropecuario'], 1);
      expect(await store.repararGruposLegacy(), 0,
          reason: 'segunda corrida: nada que reparar');
      row = (await (await db.database).query('formularios',
              where: 'uuid_edan_localidad = ?', whereArgs: [uuid]))
          .first;
      expect(row['grup_agropecuario'], 1);
    });

    test('repararGruposLegacy respeta registros gestionados', () async {
      final store = EdanStoreV2(db: db);
      final loc = _loc();
      await store.guardarFormulario(loc, usuarioId: 1);
      final uuid = loc.uuidEdanLocalidad!;
      await (await db.database).insert('filas_seccion', {
        'uuid_registro': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'uuid_edan_localidad': uuid,
        'tipo': 'danos-agricultura',
        'datos_json': '{}',
        'estado_sync': 'confirmado',
      });
      // Registro gestionado: el usuario destildó (selección explícita).
      await (await db.database).insert('grupos_local', {
        'uuid_edan_localidad': uuid,
        'grupo': 'grupAgropecuario',
        'seleccion_usuario': 0,
        'grup_servidor': null,
      });

      expect(await store.repararGruposLegacy(), 0);
      final row = (await (await db.database).query('formularios',
              where: 'uuid_edan_localidad = ?', whereArgs: [uuid]))
          .first;
      expect(row['grup_agropecuario'], 0,
          reason: 'grupo destildado no se re-enciende');
    });
  });

  group('eliminarLocalidad (borrado V2)', () {
    Future<void> _sembrarCompleto(String uuid, {int? idServer}) async {
      final database = await db.database;
      await database.insert('formularios', {
        'uuid_edan_localidad': uuid,
        'localidad': 'Borrar',
        'pendiente_push': 1,
        if (idServer != null) 'id_server': idServer,
      });
      await database.insert('filas_seccion', {
        'uuid_registro': 'f-$uuid',
        'uuid_edan_localidad': uuid,
        'tipo': 'danos-agricultura',
        'datos_json': '{}',
        'estado_sync': 'confirmado',
      });
      await database.insert('fotografias', {
        'uuid_fotografia': 'foto-$uuid',
        'uuid_edan_localidad': uuid,
        'tipo_entidad': 'danos_agricultura',
        'uuid_registro': 'f-$uuid',
        'ruta_local': '/no/existe.jpg',
      });
      await database.insert('cola_sincronizacion', {
        'tabla': 'filas_seccion',
        'uuid_registro': 'f-$uuid',
        'accion': 'D',
        'estado': 'pendiente',
        'intentos': 0,
      });
    }

    Future<int> _contar(String tabla, String uuid) async =>
        (await (await db.database).query(tabla,
                where: 'uuid_edan_localidad = ?',
                whereArgs: [uuid],
                columns: ['uuid_edan_localidad']))
            .length;

    test('nunca sincronizado: borrado total local, cero red', () async {
      final store = EdanStoreV2(db: db);
      const uuid = 'u-del-local';
      await _sembrarCompleto(uuid);

      // Sin cliente HTTP: el borrado de un nunca-sincronizado es 100% local.
      await store.eliminarLocalidad(uuid);

      expect(await _contar('formularios', uuid), 0);
      expect(await _contar('filas_seccion', uuid), 0);
      expect(await _contar('fotografias', uuid), 0);
      final cola = await (await db.database).query('cola_sincronizacion');
      expect(cola, isEmpty,
          reason: 'ni siquiera se encola D: el servidor no lo conoce');
      final lista = await store.listarFormularios();
      expect(lista.where((l) => l.uuidEdanLocalidad == uuid), isEmpty);
    });

    test('sincronizado: borra local y encola D al servidor', () async {
      final store = EdanStoreV2(db: db);
      const uuid = 'u-del-server';
      await _sembrarCompleto(uuid, idServer: 999);

      await store.eliminarLocalidad(uuid);

      expect(await _contar('formularios', uuid), 0);
      expect(await _contar('filas_seccion', uuid), 0);
      expect(await _contar('fotografias', uuid), 0);
      final cola = await (await db.database).query('cola_sincronizacion');
      expect(cola, hasLength(1));
      expect(cola.first['tabla'], 'formulario');
      expect(cola.first['accion'], 'D');
      expect(cola.first['uuid_registro'], uuid);
    });

    test('el contador baja a cero: purga cola_fotos por uuid de dueña',
        () async {
      final store = EdanStoreV2(db: db);
      const uuid = 'u-del-contador';
      await _sembrarCompleto(uuid);
      // Foto pendiente de subir (dueña = la fila, NO la foto misma).
      await (await db.database).insert('cola_fotos', {
        'uuid_fotografia': 'foto-u-del-contador',
        'ruta_local': '/no/existe.jpg',
        'tipo_entidad': 'danos_agricultura',
        'uuid_registro': 'f-u-del-contador',
        'estado': 'pendiente',
        'intentos': 0,
      });
      expect(await store.contarPendientesSync() +
          await store.contarPendientesFotos(), 3,
          reason: '1 D en cola + 1 formulario con pendiente_push + 1 foto');

      await store.eliminarLocalidad(uuid);

      expect(await store.contarPendientesSync(), 0);
      expect(await store.contarPendientesFotos(), 0,
          reason: 'la cola de fotos se purga por uuid_registro de la dueña; '
              'antes se buscaba por uuid_fotografia y el badge quedaba marcado');
    });

    test('eliminarFila purga las fotos de la fila (sin huérfanas en cola)',
        () async {
      final store = EdanStoreV2(db: db);
      final loc = _loc();
      await store.guardarFormulario(loc, usuarioId: 1);
      final uuid = loc.uuidEdanLocalidad!;
      await (await db.database).insert('filas_seccion', {
        'uuid_registro': 'fila-con-foto',
        'uuid_edan_localidad': uuid,
        'tipo': 'danos-agricultura',
        'datos_json': '{}',
        'estado_sync': 'pendiente',
      });
      await (await db.database).insert('fotografias', {
        'uuid_fotografia': 'foto-de-fila',
        'uuid_edan_localidad': uuid,
        'tipo_entidad': 'danos_agricultura',
        'uuid_registro': 'fila-con-foto',
        'ruta_local': '/no/existe.jpg',
      });
      await (await db.database).insert('cola_fotos', {
        'uuid_fotografia': 'foto-de-fila',
        'ruta_local': '/no/existe.jpg',
        'tipo_entidad': 'danos_agricultura',
        'uuid_registro': 'fila-con-foto',
        'estado': 'pendiente',
        'intentos': 0,
      });

      await store.eliminarFila('danos-agricultura', 'fila-con-foto');

      expect(await _colaFotosCount('foto-de-fila'), 0,
          reason: 'sin esto la foto huérfana atascaba el contador');
      final meta = await (await db.database).query('fotografias',
          where: 'uuid_fotografia = ?', whereArgs: ['foto-de-fila']);
      expect(meta, isEmpty,
          reason: 'nunca se subió: se elimina el registro, no queda borrado');
    });

    test('contarPendientesSync incluye formularios con pendiente_push',
        () async {
      final store = EdanStoreV2(db: db);
      final loc = _loc();
      // guardarFormulario marca pendiente_push=1 sin encolar nada (Fase D).
      await store.guardarFormulario(loc, usuarioId: 1);

      expect(await store.contarPendientesSync(), 1,
          reason: 'el badge debe contar lo que el motor sí va a subir');
    });

    test('contarLocalidadesPendientes agrupa por localidad (no por op)',
        () async {
      final store = EdanStoreV2(db: db);
      final database = await db.database;
      // 1 formulario pendiente + 1 D de su fila + 1 foto pendiente:
      // 3 operaciones, UNA localidad.
      await database.insert('formularios', {
        'uuid_edan_localidad': 'u-agrup',
        'localidad': 'Agrup',
        'pendiente_push': 1,
      });
      await database.insert('filas_seccion', {
        'uuid_registro': 'f-agrup',
        'uuid_edan_localidad': 'u-agrup',
        'tipo': 'danos-agricultura',
        'datos_json': '{}',
        'estado_sync': 'pendiente',
      });
      await database.insert('cola_sincronizacion', {
        'tabla': 'filas_seccion',
        'uuid_registro': 'f-agrup',
        'accion': 'D',
        'estado': 'pendiente',
        'intentos': 0,
      });
      await database.insert('cola_fotos', {
        'uuid_fotografia': 'foto-agrup',
        'ruta_local': '/no/existe.jpg',
        'tipo_entidad': 'danos_agricultura',
        'uuid_registro': 'f-agrup',
        'estado': 'pendiente',
        'intentos': 0,
      });

      expect(await store.contarLocalidadesPendientes(), 1,
          reason: 'el badge cuadra con Total localidades');
    });

    test('contarLocalidadesPendientes cuenta D huérfanos como sueltos',
        () async {      final store = EdanStoreV2(db: db);
      final database = await db.database;
      // D de un formulario ya borrado localmente: sin dueño resoluble pero
      // con trabajo real (viaja al servidor).
      await database.insert('cola_sincronizacion', {
        'tabla': 'formulario',
        'uuid_registro': 'u-fantasma',
        'accion': 'D',
        'estado': 'pendiente',
        'intentos': 0,
      });

      expect(await store.contarLocalidadesPendientes(), 1);
    });
  });
}

Future<int> _colaFotosCount(String uuid) async {
  final database = await DatabaseHelper.instance.database;
  return (await database.query('cola_fotos',
          where: 'uuid_fotografia = ?', whereArgs: [uuid]))
      .length;
}

List<String> _rutasAgropecuario() =>
    EdanSeccionesRegistry.checkboxSecciones['grupAgropecuario']!;