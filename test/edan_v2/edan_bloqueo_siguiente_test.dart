/// Regla del botón Siguiente (obligatorio por página) + padding 4/8 en SQLite.
///
/// Fija: por grupo marcado, las 1:N exigen ≥1 fila válida en ALGUNA sección
/// (OR) y las 1:1 de la página exigen su registro COMPLETO (AND: `tieneDatos`,
/// regla espejo del servidor); `danos-vivienda` exige padre + ≥1 hija;
/// catálogo exige 1 grupo con datos (el push completa el set exacto); y al
/// guardar, `impacto-poblacion`/`proteccion` persisten el SET EXACTO.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'package:rea/models/edan.dart';
import 'package:rea/models/edan_registro_v2.dart';
import 'package:rea/services/database_helper.dart';
import 'package:rea/services/edan/edan_store_v2.dart';
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
    dir = await Directory.systemTemp.createTemp('edan_bloqueo');
    DatabaseHelper.rutaDePrueba = p.join(dir.path, 'test.db');
  });

  tearDown(() async {
    await db.cerrarParaPrueba();
    DatabaseHelper.rutaDePrueba = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  EdanLocalidad _loc(List<String> rutas) {
    final loc = EdanLocalidad(nombre: 'L', idTipoEvento: 1);
    // Enciende todos los grupos que cubran las rutas pedidas.
    for (final r in rutas) {
      switch (EdanSeccionesRegistry.grupoDeRuta(r)) {
        case 'grupPoblacion':
          loc.grupPoblacion = true;
        case 'grupSalud':
          loc.grupSalud = true;
        case 'grupInfraestructura':
          loc.grupInfraestructura = true;
        case 'grupServicios':
          loc.grupServicios = true;
        case 'grupEducacion':
          loc.grupEducacion = true;
        case 'grupVivienda':
          loc.grupVivienda = true;
        case 'grupAgropecuario':
          loc.grupAgropecuario = true;
        case 'grupProteccion':
          loc.grupProteccion = true;
        case 'grupNecesidades':
          loc.grupNecesidades = true;
      }
    }
    return loc;
  }

  List<String> bloqueos(List<String> rutas) =>
      EdanSeccionesRegistry.bloqueosSiguiente(_loc(rutas), rutas);

  group('bloqueosSiguiente (1:N OR, 1:1 completo)', () {
    test('grupo sin datos bloquea', () {
      expect(bloqueos(const ['impacto-poblacion']), isNotEmpty);
      expect(bloqueos(const ['danos-agricultura']), isNotEmpty);
      expect(bloqueos(const ['proteccion']), isNotEmpty);
    });

    test('grupo apagado no bloquea', () {
      final loc = EdanLocalidad(nombre: 'L', idTipoEvento: 1);
      expect(
          EdanSeccionesRegistry.bloqueosSiguiente(
              loc, const ['impacto-poblacion']),
          isEmpty,
          reason: 'grup* false no exige nada');
    });

    test('agropecuario: 1 fila en una sección basta (OR)', () {
      final loc = _loc(const ['danos-agricultura']);
      loc.danosAgricultura = [EdanDanoAgricultura(tipoCultivo: 'MAIZ')];
      expect(
          EdanSeccionesRegistry.bloqueosSiguiente(
              loc, const ['danos-agricultura']),
          isEmpty,
          reason: 'no exige una fila en CADA sección');
    });

    test('vivienda: padre obligatorio y luego ≥1 hija', () {
      final loc = _loc(const ['danos-vivienda']);
      loc.danosVivienda = [EdanDanoVivienda()..danoTotal = 5];
      expect(
          EdanSeccionesRegistry.bloqueosSiguiente(
              loc, const ['danos-vivienda']),
          isNotEmpty,
          reason: 'padre sin hija aún no avanza');
      loc.danosVivienda.first.viviendas = [EdanVivienda()];
      expect(
          EdanSeccionesRegistry.bloqueosSiguiente(
              loc, const ['danos-vivienda']),
          isEmpty,
          reason: 'padre + 1 hija completa');
    });

    test('vivienda: flujo V2 (solo hijas, contadores del padre en 0) avanza',
        () {
      // Bug 2026-11-02: la página 08 nunca llena `dano_parcial`/`dano_total`
      // del padre (son derivados); validar por ellos dejaba "Siguiente"
      // apagado aunque el usuario ya tuviera viviendas capturadas.
      final loc = _loc(const ['danos-vivienda']);
      loc.danosVivienda = [
        EdanDanoVivienda(comunidad: 'Barrio Norte')
          ..viviendas = [EdanVivienda(tipoDano: EdanViviendaTipo.total)],
      ];
      expect(
          EdanSeccionesRegistry.bloqueosSiguiente(
              loc, const ['danos-vivienda']),
          isEmpty,
          reason: '≥1 hija basta, sin contadores legacy');
    });

    test('impacto: 1 grupo con datos basta (no los 4)', () {
      final loc = _loc(const ['impacto-poblacion']);
      loc.impactoPoblacion = [
        EdanImpactoPoblacion(grupoEtario: 'Niño (a) 0-5 años', fallecidos: 2),
      ];
      expect(
          EdanSeccionesRegistry.bloqueosSiguiente(
              loc, const ['impacto-poblacion']),
          isEmpty);
    });
  });

  group('mixto 1:1 + 1:N en la misma página (AND)', () {
    test('page03: impacto lleno no basta; exige la 1:1 de primera respuesta',
        () {
      final rutas = EdanSeccionesRegistry.rutasDePagina('03');
      final loc = _loc(rutas);
      loc.impactoPoblacion = [
        EdanImpactoPoblacion(grupoEtario: 'Niño (a) 0-5 años', fallecidos: 1),
      ];
      final bloqueos = EdanSeccionesRegistry.bloqueosSiguiente(loc, rutas);
      expect(bloqueos, isNotEmpty,
          reason: '1:N con datos no abre la puerta si la 1:1 está vacía');
      expect(bloqueos.first, contains('primera respuesta'));
      loc.necesidadPrimeraRespuesta!.busqueda = true;
      expect(EdanSeccionesRegistry.bloqueosSiguiente(loc, rutas), isEmpty,
          reason: '1:N con datos + 1:1 completo = avanza');
    });

    test('page04: establecimiento lleno no basta; exige la 1:1 de salud', () {
      final rutas = EdanSeccionesRegistry.rutasDePagina('04');
      final loc = _loc(rutas);
      loc.establecimientosSalud = [
        EdanEstablecimientoSalud(nombreEstablecimiento: 'POSTA Y'),
      ];
      expect(EdanSeccionesRegistry.bloqueosSiguiente(loc, rutas), isNotEmpty);
      loc.necesidadSalud!.numeroPersonas = 2;
      expect(EdanSeccionesRegistry.bloqueosSiguiente(loc, rutas), isEmpty);
    });

    test('page03 sin nada: dos mensajes (1:1 y 1:N) y no uno solo', () {
      final rutas = EdanSeccionesRegistry.rutasDePagina('03');
      final bloqueos =
          EdanSeccionesRegistry.bloqueosSiguiente(_loc(rutas), rutas);
      expect(bloqueos, hasLength(2),
          reason: 'primero el registro 1:1, después el OR de las 1:N');
    });

    test('1:1: solo texto de observaciones cuenta como completo', () {
      final rutas = EdanSeccionesRegistry.rutasDePagina('11');
      final loc = _loc(rutas);
      loc.necesidadHumanitaria!.obsAlimentos = 'faltan víveres';
      expect(EdanSeccionesRegistry.bloqueosSiguiente(loc, rutas), isEmpty,
          reason: 'tieneDatos espeja al servidor: obs_* llena la 1:1');
    });

    test('cabecera (01/02/13) nunca bloquea', () {
      final loc = EdanLocalidad(nombre: 'L', idTipoEvento: 1);
      for (final p in ['01', '02', '13']) {
        expect(
            EdanSeccionesRegistry.bloqueosSiguiente(
                loc, EdanSeccionesRegistry.rutasDePagina(p)),
            isEmpty,
            reason: 'página $p es cabecera: Siguiente libre');
      }
    });
  });

  group('bloqueosCamposPagina (cabecera 01/02)', () {
    EdanLocalidad _llen01({String nombre = 'Villa Nueva'}) => EdanLocalidad(
          nombre: nombre,
          idTipoEvento: 1,
          tipoEventoNombre: 'Inundación',
          tipoLocalidad: 'Comunidad',
          fechaEvento: '2026-10-01',
          horaEvento: '09:00',
        );

    test('page01 todo vacío: los 6 faltantes, en orden de pantalla', () {
      final loc = EdanLocalidad(nombre: '', idTipoEvento: null);
      final b = EdanSeccionesRegistry.bloqueosCamposPagina(loc, '01');
      expect(b, hasLength(6));
      expect(b[0], contains('organización territorial'));
      expect(b[1], contains('nombre del lugar'));
      expect(b[2], contains('evento extremo'));
      expect(b[3], contains('fecha'));
      expect(b[4], contains('hora'));
      expect(b[5], contains('al menos una categoría'));
    });

    test('page01 campos llenos sin ningún check: solo falta el check', () {
      final b = EdanSeccionesRegistry.bloqueosCamposPagina(_llen01(), '01');
      expect(b, [contains('marque al menos una categoría')]);
    });

    test('page01 campo individual: mensaje individual (hora = hora+AM/PM)', () {
      final loc = _llen01();
      loc.grupSalud = true; // solo deben faltar los campos, no el check
      loc.horaEvento = null;
      expect(
          EdanSeccionesRegistry.bloqueosCamposPagina(loc, '01'),
          [contains('hora')],
          reason: 'sin AM/PM no hay hora y bloquea');
      loc.horaEvento = '';
      expect(EdanSeccionesRegistry.bloqueosCamposPagina(loc, '01'),
          [contains('hora')]);
      loc.horaEvento = '09:00';
      expect(EdanSeccionesRegistry.bloqueosCamposPagina(loc, '01'), isEmpty,
          reason: 'campos + 1 casilla = avanza');
    });

    test('page01: nombre en blanco no cuenta', () {
      expect(
          EdanSeccionesRegistry.bloqueosCamposPagina(_llen01(nombre: '   '), '01')
              .where((m) => m.contains('nombre')),
          hasLength(1));
    });

    test('page02: los 3 totales >0 sí o sí', () {
      final loc = EdanLocalidad(nombre: 'L', idTipoEvento: 1)
        ..totalPoblacionAfectada = 10
        ..totalFamiliasAfectadas = 10
        ..totalFamiliasDamnificadas = 0;
      expect(EdanSeccionesRegistry.bloqueosCamposPagina(loc, '02'),
          [contains('damnificadas')]);
      loc.totalPoblacionAfectada = 0;
      final b = EdanSeccionesRegistry.bloqueosCamposPagina(loc, '02');
      expect(b, hasLength(2),
          reason: 'una falta por campo, damnificadas y población');
      loc.totalFamiliasDamnificadas = 5;
      loc.totalPoblacionAfectada = 7;
      expect(EdanSeccionesRegistry.bloqueosCamposPagina(loc, '02'), isEmpty);
    });

    test('page02: 0 == vacío (la página pinta 0 como campo sin llenar)', () {
      final loc = EdanLocalidad(nombre: 'L', idTipoEvento: 1);
      expect(EdanSeccionesRegistry.bloqueosCamposPagina(loc, '02'),
          hasLength(3));
    });

    test('13/intro/secciones/resumen: fuera de esta regla', () {
      final loc = EdanLocalidad(nombre: '', idTipoEvento: null);
      for (final k in ['13', 'intro', 'resumen', '03', '04', '11']) {
        expect(EdanSeccionesRegistry.bloqueosCamposPagina(loc, k), isEmpty,
            reason: '$k no tiene gate de campos');
      }
    });
  });

  group('padding 4/8 persistido en SQLite', () {
    Future<Map<String, dynamic>> _row(String uuid, String tipo) async {
      final rows = await (await db.database).query('filas_seccion',
          where: 'uuid_edan_localidad = ? AND tipo = ?',
          whereArgs: [uuid, tipo]);
      return rows.first;
    }

    test('impacto con 1 fila guarda las 4', () async {
      final store = EdanStoreV2(db: db);
      final loc = EdanLocalidad(
        nombre: 'L4',
        idTipoEvento: 1,
        uuidEdanLocalidad: 'u-4',
      )
        ..impImpactoPoblacion = true
        ..impactoPoblacion = [
          EdanImpactoPoblacion(
              grupoEtario: 'Niño (a) 0-5 años', fallecidos: 1),
        ];
      await store.guardarTodo(
        loc,
        usuarioId: 1,
        seccionesActivas: const [],
        tipos: const ['impacto-poblacion'],
      );

      final rows = await (await db.database).query('filas_seccion',
          where: 'uuid_edan_localidad = ? AND tipo = ?',
          whereArgs: ['u-4', 'impacto-poblacion']);
      expect(rows, hasLength(4), reason: 'set exacto 4');
      final ids = rows
          .map((r) =>
              (jsonDecode(r['datos_json'] as String) as Map)['id_grupo_etario'])
          .toSet();
      expect(ids, {1, 2, 3, 4});
    });

    test('proteccion con 2 filas guarda las 8', () async {
      final store = EdanStoreV2(db: db);
      final loc = EdanLocalidad(
        nombre: 'L8',
        idTipoEvento: 1,
        uuidEdanLocalidad: 'u-8',
      )
        ..impProteccion = true
        ..proteccion = [
          EdanGrupoVulnerable(idGrupoVulnerableCatalogo: 1, mujeres: 3),
          EdanGrupoVulnerable(idGrupoVulnerableCatalogo: 2, hombres: 1),
        ];
      await store.guardarTodo(
        loc,
        usuarioId: 1,
        seccionesActivas: const [],
        tipos: const ['proteccion'],
      );

      final rows = await (await db.database).query('filas_seccion',
          where: 'uuid_edan_localidad = ? AND tipo = ?',
          whereArgs: ['u-8', 'proteccion']);
      expect(rows, hasLength(8), reason: 'set exacto 8');
      final ids = rows
          .map((r) => (jsonDecode(r['datos_json'] as String)
              as Map)['id_grupo_vulnerable_catalogo'])
          .toSet();
      expect(ids, {1, 2, 3, 4, 5, 6, 7, 8});
    });

    test('id determinista: re-guardar no duplica', () async {
      final store = EdanStoreV2(db: db);
      final loc = EdanLocalidad(
        nombre: 'Ld',
        idTipoEvento: 1,
        uuidEdanLocalidad: 'u-d',
      )
        ..impImpactoPoblacion = true
        ..impactoPoblacion = [
          EdanImpactoPoblacion(
              grupoEtario: 'Niño (a) 0-5 años', fallecidos: 1),
        ];
      Future<void> guardar() => store.guardarTodo(
            loc,
            usuarioId: 1,
            seccionesActivas: const [],
            tipos: const ['impacto-poblacion'],
          );
      await guardar();
      await guardar();
      final rows = await (await db.database).query('filas_seccion',
          where: 'uuid_edan_localidad = ? AND tipo = ?',
          whereArgs: ['u-d', 'impacto-poblacion']);
      expect(rows, hasLength(4), reason: 'determinista: sin duplicados');
      expect((await _row('u-d', 'impacto-poblacion'))['uuid_registro'],
          isNotEmpty);
    });

    test('flag apagada no rellena', () async {
      final store = EdanStoreV2(db: db);
      final loc = EdanLocalidad(
        nombre: 'Ln',
        idTipoEvento: 1,
        uuidEdanLocalidad: 'u-n',
      )..impactoPoblacion = [
          EdanImpactoPoblacion(
              grupoEtario: 'Niño (a) 0-5 años', fallecidos: 1),
        ];
      await store.guardarTodo(
        loc,
        usuarioId: 1,
        seccionesActivas: const [],
        tipos: const ['impacto-poblacion'],
      );

      final rows = await (await db.database).query('filas_seccion',
          where: 'uuid_edan_localidad = ? AND tipo = ?',
          whereArgs: ['u-n', 'impacto-poblacion']);
      expect(rows, hasLength(1),
          reason: 'sin flag el set no se fuerza');
    });
  });
}
