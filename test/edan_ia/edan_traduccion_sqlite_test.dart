/// La traducción contra SQLite de verdad.
///
/// `edan_traduccion_ida_vuelta_test.dart` comprueba el contrato `toJson`/
/// `fromJson`. Esta prueba va un paso más allá: usa el mismo SQLite que la app
/// (`sqflite` + el esquema de `DatabaseHelper`, versión 29) contra un archivo
/// temporal, y verifica el viaje completo que hará el asistente:
///
///   borrador -> traducir -> insertLocalidad -> getLocalidades -> secciones
///
/// `DatabaseHelper` es un singleton atado a la ruta real del dispositivo, así
/// que la prueba inyecta `rutaDePrueba` (visible solo para tests) en vez de
/// abrir la base de la app.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rea/models/edan.dart';
import 'package:rea/models/edan_borrador_ia.dart';
import 'package:rea/services/database_helper.dart';
import 'package:rea/services/edan_ia/edan_traduccion.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dir;
  final db = DatabaseHelper.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rea_edan_ia_test');
    DatabaseHelper.rutaDePrueba = p.join(dir.path, 'test.db');
  });

  tearDown(() async {
    await db.cerrarParaPrueba();
    DatabaseHelper.rutaDePrueba = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  EdanBorradorIa borrador() => EdanBorradorIa()
    ..municipio = 'Yapacaní'
    ..totalAfectada = 350
    ..tipoEvento['inundacion'] = true
    ..infraVial = [
      BchDanoVial(via: 'Puente Viejo', tramo: 'km 4', danoTotal: 'Total'),
    ]
    ..agricultura = [BchAgricultura(cultivo: 'Maíz', hasAfectadas: 120)]
    ..pecuario = [
      BchPecuario(especie: 'Vacas', animalesAfectados: 40, observaciones: 'vacas_string'),
    ]
    ..proteccionDe('Mujeres Embarazadas')!.mujeres = 10
    ..necesidadDe('Alimentos')!.si = true
    ..necesidadDe('Politubos')!.observaciones = 'unos 200 metros';

  Future<EdanLocalidad> guardarYReleer(EdanBorradorIa b) async {
    final idLocal =
        await db.insertLocalidad(traducirBorrador(b).localidad, usuarioId: 7);
    final leidas = await db.getLocalidades(7);
    expect(leidas, hasLength(1));
    expect(leidas.first.idLocal, idLocal);
    return leidas.first;
  }

  test('crea el esquema completo y la localidad queda pendiente de sync', () async {
    final r = await guardarYReleer(borrador());

    expect(r.sincronizado, isFalse);
    expect(r.editado, isTrue);
    expect(r.idUsuario, 7);
    expect(r.municipioNombre, 'Yapacaní');
    expect(r.totalPoblacionAfectada, 350);
  });

  test('los totales y las cabeceras sobreviven al viaje por SQLite', () async {
    final r = await guardarYReleer(borrador()
      ..departamento = 'Cochabamba'
      ..provincia = 'Ichu'
      ..alcalde = 'Juan Pérez'
      ..telefono = '70012345'
      ..fechaEvento = '2026-03-12');

    expect(r.departamentoNombre, 'Cochabamba');
    expect(r.provinciaNombre, 'Ichu');
    expect(r.municipioNombre, 'Yapacaní');
    expect(r.nombreAlcalde, 'Juan Pérez');
    expect(r.fonoAlcalde, '70012345');
    expect(r.fechaEvento, '2026-03-12');
    expect(r.totalPoblacionAfectada, 350);
  });

  test('las secciones 1:N sobreviven dentro de datos_json', () async {
    final r = await guardarYReleer(borrador());

    expect(r.danosViales, hasLength(1));
    expect(r.danosViales.first.viaPuente, 'Puente Viejo');
    expect(r.danosViales.first.danoTotal, isTrue);

    expect(r.danosAgricultura, hasLength(1));
    expect(r.danosAgricultura.first.tipoCultivo, 'Maíz');
    expect(r.danosAgricultura.first.hectareasAfectadas, 120);

    expect(r.danosPecuarios, hasLength(1));
    expect(r.danosPecuarios.first.especie, 'Vacas');
    expect(r.danosPecuarios.first.animalesAfectados, 40);
    // `observaciones` se perdió una vez por un `toJson` incompleto; la
    // prueba lo fija para que no vuelva a perderse.
    expect(r.danosPecuarios.first.observaciones, 'vacas_string');
  });

  test('`suspension_clases` sobrevive: antes se leía como null siempre', () async {
    final b = EdanBorradorIa()
      ..municipio = 'Yapacaní'
      ..educacion = [
        BchUnidadEducativa(
            establecimiento: 'Escuela 1',
            comunidad: 'San Pedro',
            danoTotal: 'Total',
            suspensionClases: true,
            estudiantes: 120),
      ];
    final r = await guardarYReleer(b);

    expect(r.unidadesEducativas, hasLength(1));
    expect(r.unidadesEducativas.first.nombreEstablecimiento, 'Escuela 1');
    expect(r.unidadesEducativas.first.suspensionClases, isTrue);
    expect(r.unidadesEducativas.first.estudiantes, 120);
  });

  test('la protección con desglose por sexo sobrevive', () async {
    final r = await guardarYReleer(borrador());
    final g = r.proteccion.firstWhere((g) => g.nombreGrupo == 'Mujeres embarazadas');
    expect(g.mujeres, 10);
    expect(g.hombres, 0);
  });

  test('las 10 necesidades del tutor siguen siendo 9 columnas', () async {
    final r = await guardarYReleer(borrador());
    final n = r.necesidadHumanitaria!;
    expect(n.alimentos, isTrue);
    expect(n.herramientas, isTrue, reason: 'obs ⇒ casilla marcada');
    expect(n.obsHerramientas, 'unos 200 metros');
  });

  test('los flags imp_* coinciden con las secciones activas', () async {
    final r = await guardarYReleer(borrador());
    expect(r.impInfraestructura, isTrue);
    expect(r.impAgropecuario, isTrue);
    expect(r.impProteccion, isTrue);
    expect(r.impNecesidades, isTrue);
    expect(r.impSalud, isFalse);
    expect(r.impServicios, isFalse);
  });

  test('actualizar no duplica la localidad ni pierde secciones', () async {
    final b = borrador();
    final l = traducirBorrador(b).localidad;
    final idLocal = await db.insertLocalidad(l, usuarioId: 7);

    // Editar como haría el asistente: mismo id, más gente y otra fila 1:N.
    l.idLocal = idLocal;
    l.totalPoblacionAfectada = 500;
    l.danosViales.add(EdanDanoVial(viaPuente: 'Ruta 4', danoTotal: true, kmDanio: 2));
    await db.updateLocalidad(l);

    final r = (await db.getLocalidades(7)).single;
    expect(r.totalPoblacionAfectada, 500);
    expect(r.danosViales, hasLength(2));
    expect(
      r.danosViales.map((v) => v.viaPuente),
      containsAll(<String>['Puente Viejo', 'Ruta 4']),
    );
  });

  test('las fotos y coordenadas del paso final sobreviven al guardado', () async {
    // Este es el bug que estaba vivo en la pantalla del asistente: la UI
    // traducía el borrador, cargaba las fotos sobre los ítems de esa localidad,
    // y al guardar llamaba a `guardar()` sin pasarla. El provider volvía a
    // traducir, armaba otra localidad y las fotos se perdían al cerrar la
    // ficha. Ahora `guardar(preparado: ...)` persiste esa misma.
    final preparado = traducirBorrador(borrador());
    final puente = preparado.localidad.danosViales.first;
    puente.fotografia = '/fotos/puente_1.jpg';
    puente.coordenadaLat = -17.0333;
    puente.coordenadaLon = -65.2667;
    puente.fotos.add(EdanFoto(
      ruta: '/fotos/puente_2.jpg',
      latitud: -17.0340,
      longitud: -65.2670,
    ));

    final idLocal = await db.insertLocalidad(preparado.localidad, usuarioId: 7);
    preparado.localidad.idLocal = idLocal;

    // La pantalla vuelve del paso de fotos con la misma localidad ya cargada y
    // la pasa tal cual, sin re-traducir.
    await db.updateLocalidad(preparado.localidad);

    final r = (await db.getLocalidades(7)).single;
    final releido = r.danosViales.first;
    expect(releido.fotografia, '/fotos/puente_1.jpg');
    expect(releido.coordenadaLat, -17.0333);
    expect(releido.coordenadaLon, -65.2667);
    expect(releido.fotos, hasLength(1));
    expect(releido.fotos.first.ruta, '/fotos/puente_2.jpg');
  });

  test('el esquema creado por la prueba es el de la app (versión 29)', () async {
    await db.insertLocalidad(traducirBorrador(borrador()).localidad, usuarioId: 7);
    final d = await db.database;

    final version = await d.rawQuery('PRAGMA user_version');
    expect(version.first.values.first, 29);

    // Las tablas que el asistente toca tienen que existir tal cual.
    final tablas = (await d.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'",
        ))
        .map((r) => r['name'] as String)
        .toSet();
    expect(
      tablas,
      containsAll(<String>[
        'localidades_offline',
        'seccion_impacto_poblacion',
        'seccion_proteccion',
        'seccion_danos_viales',
        'seccion_danos_agricultura',
        'localidad_secciones_activas',
      ]),
    );
  });
}
