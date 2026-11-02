/// Pruebas de la reorganización del rol 7 (2026-11-01): la pestaña Inicio
/// pasó a llamarse **Reportes** y los indicadores filtran en el sitio; el
/// antiguo tab de listados se reemplazó por **Galería** (fotos por localidad).
/// La galería es un widget compartido (`edan_galeria_view.dart`): el rol 7 lo
/// monta con sus fotos y el rol 6 dentro de Localidades con las del municipio
/// (alcance `listarFotosGaleriaPorMunicipio`, con autor visible).
///
/// Cubre: `filtrarReportesResp` (pura), `agruparFotosPorLocalidad`/
/// `etiquetaTipoEntidad` (puras del view compartido) y `listarFotosGaleria`
/// (+ variante por municipio) contra SQLite real (patrón `rutaDePrueba`).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rea/config/api_config.dart';
import 'package:rea/models/edan.dart';
import 'package:rea/screens/role_screens/resp/resp_dashboard_tab.dart'
    show filtrarReportesResp;
import 'package:rea/widgets/edan_galeria_view.dart'
    show agruparFotosPorLocalidad, etiquetaTipoEntidad, urlRemotaFoto;
import 'package:rea/services/database_helper.dart';
import 'package:rea/services/edan/edan_store_v2.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('filtrarReportesResp (indicadores = filtro en el sitio)', () {
    final localidades = <EdanLocalidad>[
      EdanLocalidad(
        nombre: 'Los Pinos',
        tipoLocalidad: 'Comunidad',
        estadoLocalidad: UgrLocalidadEstado.borrador,
      ),
      EdanLocalidad(
        nombre: 'Urubo',
        tipoLocalidad: 'Comunidad',
        estadoLocalidad: UgrLocalidadEstado.enviadoUgr,
      ),
      EdanLocalidad(
        nombre: 'La Esperanza',
        tipoLocalidad: 'Barrio',
        estadoLocalidad: UgrLocalidadEstado.enviadoUgr,
      ),
    ];

    test('sin filtro ni búsqueda devuelve todo', () {
      expect(filtrarReportesResp(localidades), hasLength(3));
    });

    test('filtro por estado deja solo ese estado', () {
      final r = filtrarReportesResp(
        localidades,
        estado: UgrLocalidadEstado.enviadoUgr,
      );
      expect(r.map((l) => l.nombre), containsAll(['Urubo', 'La Esperanza']));
      expect(r, hasLength(2));
    });

    test('búsqueda por nombre o tipo (sin filtro de estado)', () {
      expect(
        filtrarReportesResp(localidades, query: 'espera').map((l) => l.nombre),
        ['La Esperanza'],
      );
      expect(
        filtrarReportesResp(localidades, query: 'Barrio').map((l) => l.nombre),
        ['La Esperanza'],
      );
    });

    test('estado + búsqueda se combinan (AND)', () {
      final r = filtrarReportesResp(
        localidades,
        estado: UgrLocalidadEstado.enviadoUgr,
        query: 'urubo',
      );
      expect(r.map((l) => l.nombre), ['Urubo']);
    });

    test('localidad sin estado explícito no aparece al filtrar por estado',
        () {
      final conNull = [
        EdanLocalidad(nombre: 'Sin estado'),
        ...localidades,
      ];
      final r = filtrarReportesResp(
        conNull,
        estado: UgrLocalidadEstado.borrador,
      );
      expect(r.map((l) => l.nombre), ['Los Pinos']);
    });
  });

  group('galería: agrupación y etiquetas puras', () {
    EdanFotoGaleria foto(
      String uuid,
      String locUuid,
      String locNombre, {
      String tipo = 'danos_viales',
    }) =>
        EdanFotoGaleria(
          uuidFotografia: uuid,
          uuidEdanLocalidad: locUuid,
          nombreLocalidad: locNombre,
          idEstadoLocalidad: 2,
          tipoEntidad: tipo,
          rutaServidor: '/uploads/reports/$uuid.jpg',
        );

    test('agrupa por localidad preservando el orden de entrada', () {
      final g = agruparFotosPorLocalidad([
        foto('a', 'L1', 'Urubo'),
        foto('b', 'L2', 'Los Pinos'),
        foto('c', 'L1', 'Urubo'),
      ]);
      expect(g.keys.toList(), ['L1', 'L2']);
      expect(g['L1']!.map((f) => f.uuidFotografia), ['a', 'c']);
      expect(g['L2']!.length, 1);
    });

    test('lista vacía → mapa vacío', () {
      expect(agruparFotosPorLocalidad(const []), isEmpty);
    });

    test('etiqueta en español del tipo_entidad', () {
      expect(etiquetaTipoEntidad('danos_viales'), 'Daños viales');
      expect(etiquetaTipoEntidad('vivienda'), 'Vivienda');
      expect(etiquetaTipoEntidad('cabecera'), 'Datos generales');
      // Variante ruta v2 (el servidor a veces manda `danos-viales`).
      expect(etiquetaTipoEntidad('danos-viales'), 'Daños viales');
      // Quirk conocido: llave JSON de salud.
      expect(etiquetaTipoEntidad('establecimientos_salud'),
          'Establecimientos de salud');
      // Desconocido: legible, no lanza.
      expect(etiquetaTipoEntidad('tabla_rara_x'), 'tabla rara x');
      expect(etiquetaTipoEntidad(null), 'Foto');
    });

    test('urlRemotaFoto arma scheme://host/ruta', () {
      final u = urlRemotaFoto(foto('z', 'L1', 'X'));
      final base = Uri.parse(ApiConfig.baseUrl);
      expect(u, '${base.scheme}://${base.host}/uploads/reports/z.jpg');
      // Ruta relativa sin '/' inicial también queda bien colgada.
      expect(
        urlRemotaFoto(const EdanFotoGaleria(
          uuidFotografia: 'w',
          uuidEdanLocalidad: 'L1',
          nombreLocalidad: 'X',
          idEstadoLocalidad: 2,
          rutaServidor: 'uploads/w.png',
        )),
        '${base.scheme}://${base.host}/uploads/w.png',
      );
    });
  });

  group('listarFotosGaleria + setFotoRutaLocal (SQLite real)', () {
    late Directory dir;
    final db = DatabaseHelper.instance;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('rea_galeria');
      DatabaseHelper.rutaDePrueba = p.join(dir.path, 'test.db');
    });

    tearDown(() async {
      await db.cerrarParaPrueba();
      DatabaseHelper.rutaDePrueba = null;
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    Future<void> seed() async {
      final d = await db.database;
      await d.insert('catalogo_tipos_evento',
          {'id_tipo_evento': 2, 'nombre': 'Inundación'});
      await d.insert('formularios', {
        'uuid_edan_localidad': 'loc-own',
        'localidad': 'Urubo',
        'id_usuario': 30,
        'id_municipio': 70101,
        'usuario_nombre': 'Ana Petelo',
        'usuario_login': 'ana',
        'id_edan_localidad_estado': 2,
        'id_tipo_evento': 2,
      });
      await d.insert('formularios', {
        'uuid_edan_localidad': 'loc-other',
        'localidad': 'Otra del municipio',
        'id_usuario': 99,
        'id_municipio': 70101,
        'usuario_nombre': 'Otro Responsable',
        'usuario_login': 'otro',
        'id_edan_localidad_estado': 1,
      });
      await d.insert('fotografias', {
        'uuid_fotografia': 'f-old',
        'uuid_edan_localidad': 'loc-own',
        'tipo_entidad': 'danos_viales',
        'uuid_registro': 'r1',
        'ruta_servidor': '/uploads/reports/f-old.jpg',
        'fecha_modificacion': '2026-01-01T10:00:00',
      });
      await d.insert('fotografias', {
        'uuid_fotografia': 'f-new',
        'uuid_edan_localidad': 'loc-own',
        'tipo_entidad': 'danos_vivienda',
        'uuid_registro': 'r2',
        'ruta_servidor': '/uploads/reports/f-new.jpg',
        'fecha_modificacion': '2026-06-01T10:00:00',
      });
      // Foto dueña de una VIVIENDA: sus coordenadas viven en la fila `viviendas`.
      await d.insert('fotografias', {
        'uuid_fotografia': 'f-viv',
        'uuid_edan_localidad': 'loc-own',
        'tipo_entidad': 'vivienda',
        'uuid_registro': 'viv1',
        'ruta_servidor': '/uploads/reports/f-viv.jpg',
        'fecha_modificacion': '2026-03-01T10:00:00',
      });
      // Fila dueña de f-old: el wizard deja la captura GPS de la foto aquí
      // (`toFotoData` → coordenada_lat/lon en datos_json).
      await d.insert('filas_seccion', {
        'uuid_registro': 'r1',
        'uuid_edan_localidad': 'loc-own',
        'tipo': 'danos-viales',
        'datos_json': '{"nombre_via":"Ruta 7",'
            '"coordenada_lat":-17.783456,"coordenada_lon":-63.182345}',
      });
      await d.insert('viviendas', {
        'uuid_registro': 'viv1',
        'uuid_dano_vivienda': 'dv1',
        'tipo_dano': 'TOTAL',
        'coordenada_lat': -17.80,
        'coordenada_lon': -63.20,
      });
      await d.insert('fotografias', {
        'uuid_fotografia': 'f-borrada',
        'uuid_edan_localidad': 'loc-own',
        'tipo_entidad': 'vivienda',
        'uuid_registro': 'r3',
        'borrado_logico': 1,
      });
      await d.insert('fotografias', {
        'uuid_fotografia': 'f-ajena',
        'uuid_edan_localidad': 'loc-other',
        'tipo_entidad': 'cabecera',
        'uuid_registro': 'r4',
      });
    }

    test('solo fotos vivas de las localidades del usuario, con su nombre',
        () async {
      await seed();
      final fotos =
          await EdanStoreV2.instance.listarFotosGaleria(usuarioId: 30);
      expect(fotos.map((f) => f.uuidFotografia).toSet(),
          {'f-old', 'f-new', 'f-viv'});
      final primera = fotos.first;
      expect(primera.nombreLocalidad, 'Urubo');
      expect(primera.idEstadoLocalidad, 2);
      // Badge de tipo de evento por JOIN con el catálogo local.
      for (final f in fotos) {
        expect(f.tipoEventoNombre, 'Inundación');
      }
    });

    test('orden: más reciente primero dentro de la localidad', () async {
      await seed();
      final fotos =
          await EdanStoreV2.instance.listarFotosGaleria(usuarioId: 30);
      expect(fotos.first.uuidFotografia, 'f-new');
      expect(fotos.last.uuidFotografia, 'f-old');
    });

    test('foto y coordenada van juntas: hereda de su fila dueña (datos_json)',
        () async {
      await seed();
      final fotos =
          await EdanStoreV2.instance.listarFotosGaleria(usuarioId: 30);
      final old = fotos.firstWhere((f) => f.uuidFotografia == 'f-old');
      expect(old.coordenadaLat, -17.783456);
      expect(old.coordenadaLon, -63.182345);
      expect(old.coordenadaTexto, contains('-17.78346'));
      expect(old.coordenadaTexto, contains('-63.1823'));
    });

    test('foto de vivienda: coordenadas de la columna de la vivienda',
        () async {
      await seed();
      final fotos =
          await EdanStoreV2.instance.listarFotosGaleria(usuarioId: 30);
      final viv = fotos.firstWhere((f) => f.uuidFotografia == 'f-viv');
      expect(viv.tipoEntidad, 'vivienda');
      expect(viv.coordenadaLat, -17.80);
      expect(viv.coordenadaLon, -63.20);
      expect(viv.coordenadaTexto, isNotNull);
    });

    test('sin fila dueña con coordenadas → coordenadaTexto null (no inventa)',
        () async {
      await seed();
      final fotos =
          await EdanStoreV2.instance.listarFotosGaleria(usuarioId: 30);
      final newF = fotos.firstWhere((f) => f.uuidFotografia == 'f-new');
      expect(newF.coordenadaLat, isNull);
      expect(newF.coordenadaLon, isNull);
      expect(newF.coordenadaTexto, isNull);
    });

    test('usuario distinto no ve nada', () async {
      await seed();
      expect(
        await EdanStoreV2.instance.listarFotosGaleria(usuarioId: 12345),
        isEmpty,
      );
    });

    test('setFotoRutaLocal marca la descarga y la foto queda local',
        () async {
      await seed();
      final ruta = p.join(dir.path, 'f-new.jpg');
      await File(ruta).writeAsBytes([0xff, 0xd8, 0xff]); // cabecera JPEG
      await EdanStoreV2.instance.setFotoRutaLocal('f-new', ruta);

      final fotos =
          await EdanStoreV2.instance.listarFotosGaleria(usuarioId: 30);
      final descargada =
          fotos.firstWhere((f) => f.uuidFotografia == 'f-new');
      expect(descargada.rutaLocal, ruta);
      expect(descargada.tieneArchivoLocal, isTrue);
      // La que no se descargó no se marca.
      final pend = fotos.firstWhere((f) => f.uuidFotografia == 'f-old');
      expect(pend.tieneArchivoLocal, isFalse);
    });

    test('tieneArchivoLocal es falso con archivo borrado del disco',
        () async {
      await seed();
      final ruta = p.join(dir.path, 'fantasma.jpg');
      await File(ruta).writeAsString('x');
      await EdanStoreV2.instance.setFotoRutaLocal('f-old', ruta);
      await File(ruta).delete();

      final fotos =
          await EdanStoreV2.instance.listarFotosGaleria(usuarioId: 30);
      final f = fotos.firstWhere((f) => f.uuidFotografia == 'f-old');
      expect(f.rutaLocal, ruta);
      expect(f.tieneArchivoLocal, isFalse);
    });

    test('alcance municipio (UGR): fotos de todos los responsables del '
        'municipio, con su autor', () async {
      await seed();
      final fotos = await EdanStoreV2.instance
          .listarFotosGaleriaPorMunicipio(idMunicipio: 70101);
      // Incluye la del otro usuario del mismo municipio (f-ajena).
      expect(
        fotos.map((f) => f.uuidFotografia).toSet(),
        {'f-old', 'f-new', 'f-viv', 'f-ajena'},
      );
      final propia =
          fotos.firstWhere((f) => f.uuidFotografia == 'f-old');
      expect(propia.nombreAutor, 'Ana Petelo');
      final ajena =
          fotos.firstWhere((f) => f.uuidFotografia == 'f-ajena');
      expect(ajena.nombreAutor, 'Otro Responsable');
      expect(ajena.nombreLocalidad, 'Otra del municipio');
      // Borrada y de otro municipio siguen excluidas (el seed no pone
      // f-borrada aquí; f-ajena es del MISMO municipio, usuario 99).
      expect(fotos.where((f) => f.uuidFotografia == 'f-borrada'), isEmpty);
    });

    test('alcance municipio: otro municipio no ve nada', () async {
      await seed();
      expect(
        await EdanStoreV2.instance
            .listarFotosGaleriaPorMunicipio(idMunicipio: 70202),
        isEmpty,
      );
    });

    test('la consulta por usuario (RESP) no carga autor: siempre es propio',
        () async {
      await seed();
      final fotos =
          await EdanStoreV2.instance.listarFotosGaleria(usuarioId: 30);
      expect(fotos, isNotEmpty);
      for (final f in fotos) {
        expect(f.nombreAutor, isNull);
      }
    });
  });
}
