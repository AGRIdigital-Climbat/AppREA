/// Fase I — fuente única de secciones: `filas_seccion` ∪ `formularios.datos_json`.
///
/// Regresa el escenario real que rompió el preview y el JSON de long-press:
/// un reporte cuyos datos viven **solo** en el snapshot de cabecera (los creó
/// el camino legado `POST /documento`, que persistía con `updateLocalidad` y
/// nunca escribió `filas_seccion`). Antes:
///  * `prepararPayloadCompleto` leía solo `filas_seccion` → las 14 `imp_*` en
///    `false` y el `POST /completo` salía **sin secciones** (pérdida de datos);
///  * `cargarSecciones` reescribía los arrays con `[]` y `EdanResumenPage`
///    mostraba "Sección no marcada, actualmente sin datos".
///
/// Aquí se fija la invariante del contrato: **flag `imp_*` en `true` ⟺ al
/// menos una fila de esa sección en el payload**.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rea/models/edan.dart';
import 'package:rea/models/edan_registro_v2.dart';
import 'package:rea/services/database_helper.dart';
import 'package:rea/services/edan/edan_localidades_envio_v2_service.dart';
import 'package:rea/services/edan/edan_secciones_fuente.dart';
import 'package:rea/services/edan/edan_store_v2.dart';
import 'package:rea/services/edan_secciones_registry.dart';
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
    dir = await Directory.systemTemp.createTemp('edan_fuente');
    DatabaseHelper.rutaDePrueba = p.join(dir.path, 'test.db');
  });

  tearDown(() async {
    await db.cerrarParaPrueba();
    DatabaseHelper.rutaDePrueba = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<EdanStoreV2> store() async {
    await db.database;
    return EdanStoreV2(db: db);
  }

  Future<Map<String, Object?>> filaCabecera(String uuid) async {
    final rows = await (await db.database).query(
      'formularios',
      where: 'uuid_edan_localidad = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    expect(rows, hasLength(1), reason: 'la cabecera debe existir');
    return rows.first;
  }

  Future<void> seedVacia(String uuid) async {
    final s = await store();
    await s.guardarFormulario(
      EdanLocalidad(uuidEdanLocalidad: uuid, idLocal: uuid, nombre: 'Vacía'),
      usuarioId: 7,
    );
  }

  EdanLocalidad localidadConAgro(String uuid) => EdanLocalidad(
        uuidEdanLocalidad: uuid,
        idLocal: uuid,
        nombre: 'Urubo',
        danosAgricultura: [
          EdanDanoAgricultura(
            idSeccion: 'b3b3b3b3-3333-4333-8333-333333333333',
            tipoCultivo: 'Maíz',
            hectareasAfectadas: 12,
          ),
        ],
      );

  // ── Vocabulario del contrato: 9 grupos (grup_*) ≠ 14 secciones (imp_*) ──
  group('traducción de grupos a grup_*', () {
    test('hay exactamente 9 grup_* y son inversos de los ids locales', () {
      final m = EdanSeccionesRegistry.grupApiDeId;
      expect(m.keys.toSet(), EdanSeccionesRegistry.grupos.toSet());
      expect(m.length, 9);
      for (final v in m.values) {
        expect(v, startsWith('grup_'),
            reason: 'un grupo NUNCA debe escribirse con prefijo imp_');
      }
      final inversa = EdanSeccionesRegistry.idDeGrupApi;
      for (final e in m.entries) {
        expect(inversa[e.value], e.key);
      }
    });

    test('el payload /completo lleva 14 imp_* y ningún flag de grupo', () async {
      final s = await store();
      final loc = localidadConAgro('loc-vocab');
      await s.guardarFormulario(
        loc,
        usuarioId: 7,
        seccionesActivas: ['danos-agricultura'],
      );
      await s.guardarFilas('loc-vocab', ['danos-agricultura'], loc);

      final payload = await EdanSyncEngineV2.prepararPayloadCompleto(
          'loc-vocab', await filaCabecera('loc-vocab'));

      expect(payload['imp_danos_agricultura'], isTrue);
      // Las 14 banderas de SECCIÓN, ni una más ni una menos.
      expect(payload.keys.where((k) => k.startsWith('imp_')), hasLength(14));
      // Los 8 grupos que NO comparten nombre con una sección no pueden viajar:
      // el servidor los deriva. (`imp_proteccion` es caso aparte: es también
      // la sección 14, así que sí viaja.)
      for (final g in const [
        'grup_poblacion', 'grup_salud', 'grup_infraestructura', 'grup_servicios',
        'grup_educacion', 'grup_vivienda', 'grup_agropecuario', 'grup_necesidades',
      ]) {
        expect(payload.containsKey(g), isFalse,
            reason: '$g es un GRUPO: se llama grup_* y no se envía');
      }
      expect(payload.containsKey('grupos'), isFalse);
    });
  });

  // ── El caso reportado: datos SOLO en datos_json ──────────────────────────
  group('rescate desde el snapshot de cabecera (sin filas V2)', () {
    Future<void> seedSnapshotOnly(String uuid) async {
      final s = await store();
      // `guardarFormulario` serializa el modelo completo en `datos_json`
      // (`toJson()` incluye las secciones). NO se llama `guardarFilas`: así se
      // reproduce el estado que dejó el camino legado `/documento`.
      await s.guardarFormulario(localidadConAgro(uuid), usuarioId: 7);
      final filas = await (await db.database).query(
        'filas_seccion',
        where: 'uuid_edan_localidad = ?',
        whereArgs: [uuid],
      );
      expect(filas, isEmpty, reason: 'precondición: sin filas V2');
    }

    test('prepararPayloadCompleto: flag true ACOMPAÑADA de sus datos', () async {
      await seedSnapshotOnly('loc-snap-1');

      final payload = await EdanSyncEngineV2.prepararPayloadCompleto(
          'loc-snap-1', await filaCabecera('loc-snap-1'));

      expect(payload['imp_danos_agricultura'], isTrue,
          reason: 'el flag debe salir de los datos, estén donde estén');
      expect(payload['danos_agricultura'], isA<List>(),
          reason: 'y la sección debe viajar con filas, no en []');
      final filas = payload['danos_agricultura'] as List;
      expect(filas, hasLength(1));
      final f = filas.first as Map<String, dynamic>;
      expect(f['uuid_registro'], 'b3b3b3b3-3333-4333-8333-333333333333',
          reason: 'uuid válido del snapshot se promueve a uuid_registro');
      expect(f['tipo_cultivo'], 'Maíz');
      // Las 14 flags siguen todas presentes y las demás en false.
      expect(payload['imp_danos_vivienda'], isFalse);
      expect(payload.containsKey('danos_vivienda'), isFalse,
          reason: 'flag false ⇒ la clave no aparece');
    });

    test('cargarSecciones puebla el modelo (la preview ya no dice "sin datos")',
        () async {
      await seedSnapshotOnly('loc-snap-2');
      final s = await store();

      final loc = EdanLocalidad(idLocal: 'loc-snap-2');
      await s.cargarSecciones(loc);

      expect(loc.danosAgricultura, hasLength(1),
          reason: 'el snapshot de cabecera es segunda fuente válida');
      expect(loc.danosAgricultura.first.tipoCultivo, 'Maíz');
    });

    test('rutasConDatos y leerActivas incluyen la ruta rescatada', () async {
      await seedSnapshotOnly('loc-snap-3');
      final s = await store();

      expect(await s.rutasConDatos('loc-snap-3'), contains('danos-agricultura'));

      final loc = EdanLocalidad(idLocal: 'loc-snap-3');
      await EdanLocalidadesEnvioV2Service()
          .aplicarFlagsDesdeSeccionesActivas(loc);
      expect(loc.impDanosAgricultura, isTrue, reason: 'flag de SECCIÓN (imp_*)');
      expect(loc.grupAgropecuario, isTrue, reason: 'grupo derivado por la matriz');
    });

    test('sección 1:1 rescatada viaja como objeto único', () async {
      final s = await store();
      final loc = EdanLocalidad(
        uuidEdanLocalidad: 'loc-snap-4',
        idLocal: 'loc-snap-4',
        nombre: 'Urubo',
        necesidadSalud: EdanNecesidadSalud(botiquines: true, numeroPersonas: 30),
      );
      await s.guardarFormulario(loc, usuarioId: 7);

      final payload = await EdanSyncEngineV2.prepararPayloadCompleto(
          'loc-snap-4', await filaCabecera('loc-snap-4'));

      expect(payload['imp_necesidad_salud'], isTrue);
      expect(payload['necesidad_salud'], isA<Map<String, dynamic>>(),
          reason: 'las 4 secciones 1:1 van como objeto, nunca como lista');
    });

    test('danos_vivienda rescatado: objeto 1:1 con viviendas[] anidadas',
        () async {
      final s = await store();
      final loc = EdanLocalidad(
        uuidEdanLocalidad: 'loc-snap-viv',
        idLocal: 'loc-snap-viv',
        nombre: 'Urubo',
        danosVivienda: [
          EdanDanoVivienda(
            idSeccion: 'c4c4c4c4-4444-4444-8444-444444444444',
            comunidad: 'El Carmen',
            coordenadaLat: 1.5,
            coordenadaLon: 2.5,
            viviendas: [EdanVivienda(tipoDano: EdanViviendaTipo.total)],
          ),
        ],
      );
      await s.guardarFormulario(loc, usuarioId: 7);

      final payload = await EdanSyncEngineV2.prepararPayloadCompleto(
          'loc-snap-viv', await filaCabecera('loc-snap-viv'));

      expect(payload['imp_danos_vivienda'], isTrue);
      final padre = payload['danos_vivienda'];
      expect(padre, isA<Map<String, dynamic>>(),
          reason: '1:1 en el servidor, aunque el registro sea 1:N');
      expect((padre as Map)['viviendas'], allOf(isA<List>(), hasLength(1)));
      expect(padre['uuid_registro'], 'c4c4c4c4-4444-4444-8444-444444444444');
      // §20.4 con viviendas hijas: las coords del padre se anulan.
      expect(padre['coordenada_lat'], isNull);
      expect(padre['coordenada_lon'], isNull);
    });

    test('fotografía con path local NO viaja en el payload', () async {
      final s = await store();
      final loc = EdanLocalidad(
        uuidEdanLocalidad: 'loc-snap-5',
        idLocal: 'loc-snap-5',
        nombre: 'Urubo',
        danosAgricultura: [
          EdanDanoAgricultura(
            idSeccion: 'agr-5',
            tipoCultivo: 'Arroz',
            fotografia: r'/data/user/0/com.app/cache/foto.jpg',
          ),
        ],
      );
      await s.guardarFormulario(loc, usuarioId: 7);

      final payload = await EdanSyncEngineV2.prepararPayloadCompleto(
          'loc-snap-5', await filaCabecera('loc-snap-5'));

      final f = (payload['danos_agricultura'] as List).first
          as Map<String, dynamic>;
      expect(f.containsKey('fotografia'), isFalse,
          reason: 'un path /data... es inválido para el servidor');
    });
  });

  // ── No regresión: la prioridad y la no-destrucción ───────────────────────
  group('prioridad de fuentes y protección del modelo', () {
    test('con filas V2 NO se duplica la fila del snapshot', () async {
      final s = await store();
      final loc = localidadConAgro('loc-pri-1');
      await s.guardarFormulario(loc, usuarioId: 7);
      await s.guardarFilas('loc-pri-1', ['danos-agricultura'], loc);

      final payload = await EdanSyncEngineV2.prepararPayloadCompleto(
          'loc-pri-1', await filaCabecera('loc-pri-1'));

      expect(payload['danos_agricultura'], hasLength(1),
          reason: 'filas_seccion es authoritative; el snapshot se ignora');
    });

    test('cargarSecciones NO borra los datos que ya trae el modelo', () async {
      final s = await store();
      // Cabecera con snapshot vacío (borrador recién creado / sin secciones).
      await s.guardarFormulario(
        EdanLocalidad(uuidEdanLocalidad: 'loc-pri-2', idLocal: 'loc-pri-2', nombre: 'Sin nada'),
        usuarioId: 7,
      );
      // El modelo llega lleno desde el GET en línea.
      final loc = localidadConAgro('loc-pri-2');

      await s.cargarSecciones(loc);

      expect(loc.danosAgricultura, hasLength(1),
          reason: 'sin filas V2 ni snapshot, cargarSecciones debe no-op');
    });

    test('sin cabecera ni filas, el payload no inventa secciones', () async {
      await seedVacia('loc-vacia');

      final payload = await EdanSyncEngineV2.prepararPayloadCompleto(
          'loc-vacia', await filaCabecera('loc-vacia'));

      for (final desc in EdanSeccionesRegistry.secciones) {
        final clave = 'imp_${desc.rutaV2.replaceAll('-', '_')}';
        expect(payload[clave], isFalse, reason: '$clave no debe ser true');
        expect(payload.containsKey(desc.llaveJson), isFalse,
            reason: 'flag false ⇒ ${desc.llaveJson} ausente');
      }
    });
  });

  group('Primera descarga modo=comprimido (caso Urubo, en vivo 2026-10-14)', () {
    Map<String, dynamic> filaUrubo() => {
          'tipo_cultivo': 'Algodon',
          'id_cultivo': 56,
          'hectareas_afectadas': 2,
          'hectareas_perdidas': 3,
          'fotografia': '/uploads/reports/general/upload_8960288402b0.jpg',
          'coordenada_lat': '-16.50241790',
          'coordenada_lon': '-68.12100780',
          'id_seccion': '1k2ma9o87-d0601a819c58d',
          'uuid_registro': 'c3484037-9523-4aa7-e6b7-57a9fe67b953',
        };
    test('fromJson no pierde la fila objeto y prefiere uuid_registro', () {
      final loc = EdanLocalidad.fromJson({
        'localidad': 'Urubo',
        'danos_agricultura': filaUrubo(),
      });
      expect(loc.danosAgricultura, hasLength(1), reason: 'objeto unico tambien es 1 fila');
      final item = loc.danosAgricultura.first;
      expect(item.idSeccion, 'c3484037-9523-4aa7-e6b7-57a9fe67b953', reason: 'uuid_registro manda; el id legacy no viaja (daria 422)');
      expect(item.coordenadaLat, closeTo(-16.5024179, 1e-6));
      expect(item.tipoCultivo, 'Algodon');
      loc.recalcularFlagsImpacto();
      expect(loc.impDanosAgricultura, isTrue);
      expect(loc.grupAgropecuario, isTrue);
    });
    test('sin uuid en ningun lado el id nace al persistir, no al parsear', () {
      final loc = EdanLocalidad.fromJson({
        'danos_agricultura': {'tipo_cultivo': 'Maiz', 'id_seccion': 'ag_viejo123'},
      });
      expect(loc.danosAgricultura, hasLength(1));
      expect(loc.danosAgricultura.first.idSeccion, isNull, reason: 'el prefijo legacy se descarta; el store genera uuid');
    });
    test('filasDesdeDocumentoApi valida el fallback de id_seccion', () {
      const uuid = 'aaaaaaaa-0000-4000-8000-000000000001';
      final doc = {'danos_agricultura': {'tipo_cultivo': 'X', 'id_seccion': '1k2ma9o87-d0601a819c58d'}};
      final a = EdanSeccionesFuente.filasDesdeDocumentoApi(doc, uuid);
      final b = EdanSeccionesFuente.filasDesdeDocumentoApi(doc, uuid);
      final idA = a['danos-agricultura']!.first['uuid_registro'] as String;
      expect(idA, isNot('1k2ma9o87-d0601a819c58d'));
      expect(RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(idA), isTrue, reason: 'fallback determinista con forma uuid');
      expect(b['danos-agricultura']!.first['uuid_registro'], idA, reason: 'estable entre corridas (no duplica al reenviar)');
    });
  });
}