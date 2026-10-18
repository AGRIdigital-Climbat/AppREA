/// E2E del caso Urubo (datos vivos 2026-10-14): pull con `grup_*` crudos en
/// false y sin nodo `grupos` → el badge y la vista deben salir igual, desde
/// las filas normalizadas.
///
/// Fija la cadena que usa la tarjeta del listado/dashboard:
/// pull → `listarFormularios` → `aplicarFlagsDesdeSeccionesActivas` +
/// `aplicarGruposServidorAlModelo` → `seccionesActivasLabelsCortos` +
/// `cargarSecciones` para la vista.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:rea/models/edan.dart';
import 'package:rea/services/api/edan_api_v2.dart';
import 'package:rea/services/database_helper.dart';
import 'package:rea/services/edan/edan_localidades_envio_v2_service.dart';
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
    dir = await Directory.systemTemp.createTemp('edan_urubo');
    DatabaseHelper.rutaDePrueba = p.join(dir.path, 'test.db');
  });

  tearDown(() async {
    await db.cerrarParaPrueba();
    DatabaseHelper.rutaDePrueba = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  http.Response _ok([Object? data]) => http.Response(
        jsonEncode({'success': true, if (data != null) 'data': data}),
        200,
        headers: {'content-type': 'application/json'},
      );

  http.Response _pull(Map<String, dynamic> data) => http.Response(
        jsonEncode({'success': true, 'data': data}),
        200,
        headers: {'content-type': 'application/json'},
      );

  EdanApiV2 _api(MockClient client) => EdanApiV2(
        httpClient: client,
        baseUrl: 'https://api.test/api/v2/edan',
      );

  // Forma textual del pull vivo (grup_* crudos en false, sin nodo `grupos`,
  // fila con id_seccion legacy + uuid_registro + coords string).
  Map<String, dynamic> _pullUrubo() => {
        'watermark': 'wm-urubo',
        'formularios': [
          {
            'id_edan_localidad': 325668,
            'localidad': 'Urubo',
            'grup_poblacion': false,
            'grup_salud': false,
            'grup_infraestructura': false,
            'grup_servicios': false,
            'grup_educacion': false,
            'grup_vivienda': false,
            'grup_agropecuario': false,
            'grup_proteccion': false,
            'grup_necesidades': false,
            'id_tipo_localidad': 10,
            'id_edan_localidad_estado': 3,
            'id_tipo_evento': 5,
            'id_departamento': 7,
            'id_provincia': 701,
            'id_municipio': 70101,
            'fecha_evento': '2026-09-16',
            'total_poblacion_afectada': 100,
            'id_local': '33cd83e3-b2c2-457c-8353-58e3c0db7251',
            'id_usuario': 30,
            'imp_danos_agricultura': true,
            'uuid_edan_localidad': '33cd83e3-b2c2-457c-8353-58e3c0db7251',
            },
        ],
        'secciones': [
          {
            'id_dano_agricultura': 136,
            'id_edan_localidad': 325668,
            'tipo_cultivo': 'Algodón',
            'id_cultivo': 56,
            'hectareas_afectadas': 2,
            'hectareas_perdidas': 3,
            'fotografia': '/uploads/reports/general/upload_8960288402b0.jpg',
            'coordenada_lat': '-16.50241790',
            'coordenada_lon': '-68.12100780',
            'id_seccion': '1k2ma9o87-d0601a819c58d',
            'uuid_registro': 'c3484037-9523-4aa7-e6b7-57a9fe67b953',
            'uuid_edan_localidad': '33cd83e3-b2c2-457c-8353-58e3c0db7251',
            'tipo_seccion': 'danos_agricultura',
          },
        ],
        'fotos': [
          {
            'uuid_fotografia': '236d7751-1b3e-48f3-9c6f-571f32f18770',
            'id_edan_localidad': 325668,
            'tipo_entidad': 'danos_agricultura',
            'uuid_registro': 'c3484037-9523-4aa7-e6b7-57a9fe67b953',
            'ruta_archivo': '/uploads/reports/general/upload_8960288402b0.jpg',
            'borrado_logico': false,
          },
        ],
      };

  test('pull Urubo → badge Agricultura + vista con la fila + estado', () async {
    final client = MockClient((req) async {
      if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
        return _pull(_pullUrubo());
      }
      if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
        return _ok();
      }
      if (req.method == 'GET' && req.url.path.endsWith('/estados')) {
        return _ok([]);
      }
      return _ok();
    });

    await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

    // Cadena exacta de la tarjeta (listado/dashboard).
    final store = EdanStoreV2(db: db);
    final lista = await store.listarFormularios();
    expect(lista, hasLength(1));
    final loc = lista.first;
    await EdanLocalidadesEnvioV2Service(db: db)
        .aplicarFlagsDesdeSeccionesActivas(loc);
    await store.aplicarGruposServidorAlModelo(loc);

    expect(loc.estadoLocalidad, UgrLocalidadEstado.aprobadoUgr,
        reason: 'estado 3 del servidor, no borrador');
    expect(loc.grupAgropecuario, isTrue,
        reason: 'fila de agricultura presente aunque el crudo venga en false');
    expect(
        EdanSeccionesRegistry.seccionesActivasLabelsCortos(loc),
        contains('Agricultura'),
        reason: 'badge del item');
    expect(loc.idTipoEvento, 5,
        reason: 'la tarjeta puede resolver "Granizadas" por catálogo');

    // Cadena de la vista (tap en el item / editar en wizard).
    await store.cargarSecciones(loc);
    expect(loc.danosAgricultura, hasLength(1));
    final fila = loc.danosAgricultura.first;
    expect(fila.idSeccion, 'c3484037-9523-4aa7-e6b7-57a9fe67b953',
        reason: 'uuid real, no el id legacy');
    expect(fila.tipoCultivo, 'Algodón');
    expect(fila.coordenadaLat, closeTo(-16.5024179, 1e-6));
  });

  // Cadena EXACTA de la pantalla rol 7 RESP (`resp_dashboard_tab` +
  // `resp_edan_localidad_tab`): pull vivo textual (2 formularios con
  // `id_usuario: 30`, 4 tombstones ajenos) → `listarReportes(usuarioId: 30)`
  // → `aplicarFlagsDesdeSeccionesActivas` + `aplicarGruposServidorAlModelo` →
  // badges. Fija que el filtro por usuario encuentra las filas del pull y que
  // la lista NUNCA queda vacía (bug "no muestra ningún dato descargado").
  test('pantalla RESP: pull vivo → listarReportes(30) con items y badges',
      () async {
    final client = MockClient((req) async {
      if (req.method == 'GET' && req.url.path.endsWith('/sync/pull')) {
        return _pull({
          'watermark': 'wm-resp',
          'formularios': [
            {
              'id_edan_localidad': 325668,
              'localidad': 'Urubo',
              'grup_poblacion': false,
              'grup_salud': false,
              'grup_infraestructura': false,
              'grup_servicios': false,
              'grup_educacion': false,
              'grup_vivienda': false,
              'grup_agropecuario': false,
              'grup_proteccion': false,
              'grup_necesidades': false,
              'imp_danos_agricultura': true,
              'id_tipo_localidad': 10,
              'id_edan_localidad_estado': 3,
              'id_tipo_evento': 5,
              'id_departamento': 7,
              'id_provincia': 701,
              'id_municipio': 70101,
              'fecha_llenado': '2026-09-16',
              'fecha_evento': '2026-09-16',
              'hora_evento': '18:00:00',
              'total_poblacion_afectada': 100,
              'total_familias_afectadas': 5,
              'total_familias_damnificadas': 2,
              'id_local': '33cd83e3-b2c2-457c-8353-58e3c0db7251',
              'id_usuario': 30,
              'fecha_modificacion': '2026-09-16T23:53:51.129780',
              'uuid_edan_localidad': '33cd83e3-b2c2-457c-8353-58e3c0db7251',
              },
            {
              'id_edan_localidad': 342930,
              'localidad': 'Prueba10',
              'grup_poblacion': false,
              'grup_salud': false,
              'grup_infraestructura': false,
              'grup_servicios': false,
              'grup_educacion': false,
              'grup_vivienda': false,
              'grup_agropecuario': false,
              'grup_proteccion': false,
              'grup_necesidades': false,
              'imp_danos_agricultura': true,
              'id_usuario': 30,
              'id_edan_localidad_estado': 6,
              'uuid_edan_localidad': '79c0725a-8b40-4a13-9eb1-489b6020c663',
              },
          ],
          'secciones': [
            {
              'id_dano_agricultura': 136,
              'id_edan_localidad': 325668,
              'tipo_cultivo': 'Algodón',
              'id_cultivo': 56,
              'hectareas_afectadas': 2,
              'hectareas_perdidas': 3,
              'coordenada_lat': '-16.50241790',
              'coordenada_lon': '-68.12100780',
              'uuid_registro': 'c3484037-9523-4aa7-e6b7-57a9fe67b953',
              'uuid_edan_localidad': '33cd83e3-b2c2-457c-8353-58e3c0db7251',
              'tipo_seccion': 'danos_agricultura',
            },
          ],
          'fotos': [],
          'tombstones': [
            // Ajenos (id_usuario null): no deben tocar los propios.
            {
              'id': 'd65a4da7-0293-4aad-913f-85bc98093b14',
              'tabla': 'edan_localidades',
              'id_registro': 'aaaaaaaa-0000-4000-8000-000000000001',
              'clave_legacy': 'aaaaaaaa-0000-4000-8000-000000000001',
              'borrado_en': '2026-10-13T19:41:54.508799-04:00',
              'id_usuario': null,
            },
          ],
        });
      }
      if (req.method == 'GET' && req.url.path.endsWith('/estados')) {
        return _ok([]);
      }
      if (req.method == 'POST' && req.url.path.endsWith('/sync/ack')) {
        return _ok();
      }
      return _ok();
    });

    await EdanSyncEngineV2(api: _api(client), db: db).sincronizar();

    // Cadena de la pantalla (mismo orden que los tabs).
    final store = EdanStoreV2(db: db);
    final lista = await store.listarReportes(usuarioId: 30);
    expect(lista, hasLength(2),
        reason: 'el filtro por usuario del pull encuentra ambos registros');
    expect(lista.map((l) => l.nombre), containsAll(['Urubo', 'Prueba10']));

    final loc = lista.firstWhere((l) => l.nombre == 'Urubo');
    final sinc = EdanLocalidadesEnvioV2Service(db: db);
    await sinc.aplicarFlagsDesdeSeccionesActivas(loc);
    await store.aplicarGruposServidorAlModelo(loc);

    expect(loc.estadoLocalidad, UgrLocalidadEstado.aprobadoUgr);
    expect(loc.grupAgropecuario, isTrue, reason: 'badge Agrícola visible');
    expect(
        EdanSeccionesRegistry.seccionesActivasLabelsCortos(loc),
        contains('Agricultura'));

    // Prueba10: flag sin filas no inventa badge de grupo.
    final p10 = lista.firstWhere((l) => l.nombre == 'Prueba10');
    await sinc.aplicarFlagsDesdeSeccionesActivas(p10);
    expect(p10.estadoLocalidad, UgrLocalidadEstado.enRevisionUgr,
        reason: 'estado 6 = En revision UGR');

    // Regresión del INSERT: guardar la cabecera no debe lanzar (columnas
    // inexistentes) — la causa del "lista vacía".
    await store.guardarFormulario(loc, usuarioId: 30);
    final otra = await store.listarReportes(usuarioId: 30);
    expect(otra, hasLength(2));
  });
}