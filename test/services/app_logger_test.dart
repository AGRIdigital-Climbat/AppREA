import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rea/services/app_logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('app_logger_test');
    AppLogger.rutaDePrueba = p.join(dir.path, 'test_app_logs.db');
  });

  tearDown(() async {
    await AppLogger.instance.apagarParaPrueba();
    AppLogger.rutaDePrueba = null;
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  test('inicializar habilita el logger y crea la BD', () async {
    final ruta = await AppLogger.instance.inicializar();
    expect(ruta, isNotNull);
    expect(AppLogger.instance.habilitado, isTrue);
    expect(File(ruta!).existsSync(), isTrue);
  });

  test('registra API y navegación, consulta reciente primero', () async {
    await AppLogger.instance.inicializar();
    AppLogger.instance.api(
      metodo: 'GET',
      url: 'https://x/api/v2/edan/',
      estado: 200,
      response: '{"success":true,"data":[1,2,3]}',
      duracion: const Duration(milliseconds: 12),
    );
    AppLogger.instance.nav(titulo: 'push → RespEdanTab', pantalla: 'RespEdanTab');
    await AppLogger.instance.esperarFlush();

    final todas = await AppLogger.instance.consultar();
    expect(todas, hasLength(2));
    // DESC: lo último primero.
    expect(todas.first.categoria, AppLogCategoria.nav);
    expect(todas.first.pantalla, 'RespEdanTab');

    final apis =
        await AppLogger.instance.consultar(categoria: AppLogCategoria.api);
    expect(apis, hasLength(1));
    // Título legible: verbo + ruta corta + estado (no el tear-off del helper).
    expect(apis.first.titulo, 'GET /edan/ → 200');
    expect(apis.first.estado, 200);
    expect(apis.first.response, contains('"success":true'));
    expect(apis.first.metodo, 'GET');
  });

  test('sin truncado: cuerpos de 300k caracteres íntegros', () async {
    await AppLogger.instance.inicializar();
    final grande = 'x' * 300000;
    AppLogger.instance.api(
      metodo: 'POST',
      url: 'u',
      estado: 200,
      request: grande,
      response: grande,
    );
    await AppLogger.instance.esperarFlush();

    final e = (await AppLogger.instance
            .consultar(categoria: AppLogCategoria.api))
        .single;
    expect(e.request, hasLength(grande.length));
    expect(e.response, hasLength(grande.length));
  });

  test('redacta la contraseña de login pero conserva el resto', () async {
    await AppLogger.instance.inicializar();
    AppLogger.instance.api(
      metodo: 'POST',
      url: 'https://x/api/v2/auth/login',
      estado: 200,
      request: '{"usuario":"ugrscz","contrasena":"secreta123"}',
      response: '{"data":{"access_token":"abc.def.ghi"}}',
    );
    await AppLogger.instance.esperarFlush();

    final e = (await AppLogger.instance
            .consultar(categoria: AppLogCategoria.api))
        .single;
    expect(e.request, isNot(contains('secreta123')));
    expect(e.request, contains('***'));
    expect(e.request, contains('"usuario":"ugrscz"'));
    // El token NO se redacta (monitoreo de 401).
    expect(e.response, contains('abc.def.ghi'));
  });

  test('retención 1 día: purga las entradas más antiguas', () async {
    await AppLogger.instance.inicializar();
    AppLogger.instance.app(titulo: 'entrada de hoy');
    await AppLogger.instance
        .insertarFilaParaPrueba(<String, Object?>{
      'ts': DateTime.now()
          .subtract(const Duration(hours: 25))
          .millisecondsSinceEpoch,
      'nivel': 'INFO',
      'categoria': 'APP',
      'titulo': 'entrada vieja (debe purgarse)',
    });
    await AppLogger.instance.esperarFlush();
    expect(await AppLogger.instance.consultar(), hasLength(2));

    await AppLogger.instance.purgarParaPrueba();
    final tras = await AppLogger.instance.consultar();
    expect(tras, hasLength(1));
    expect(tras.single.titulo, 'entrada de hoy');
  });

  test('exportarTexto incluye detalle completo y cabecera', () async {
    await AppLogger.instance.inicializar();
    AppLogger.instance.api(
      metodo: 'PUT',
      url: 'https://x/api/v2/edan/formularios/completo',
      estado: 409,
      request: '{"uuid_edan_localidad":"u"}',
      response: '{"detail":"ya existe"}',
    );
    final texto = await AppLogger.instance.exportarTexto();
    expect(texto, contains('REGISTRO DE LA APP EDAN'));
    expect(texto, contains('REQUEST'));
    expect(texto, contains('"detail":"ya existe"'));
    expect(texto, contains('→ 409'));
  });

  test('envoltorio de fábrica: cada SQL queda registrado con args', () async {
    await AppLogger.instance.inicializar();
    // A partir de aquí, la factory global está envuelta: cualquier BD abierta
    // por ella emite eventos SQL hacia el logger.
    final db = await databaseFactory.openDatabase(
      p.join(dir.path, 'monitorizada.db'),
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onCreate: (d, v) => d.execute('CREATE TABLE t (a INTEGER)'),
      ),
    );
    await db.insert('t', {'a': 42});
    await AppLogger.instance.esperarFlush();

    final sql =
        await AppLogger.instance.consultar(categoria: AppLogCategoria.sql);
    final insercion = sql.where((e) => e.titulo.contains('insert'));
    expect(insercion, isNotEmpty);
    expect(insercion.first.request, contains('INSERT INTO t'));
    expect(insercion.first.request, contains('42'));
    await db.close();
  });

  test('desactivado por defecto: los métodos son no-op', () async {
    // Sin inicializar: nada se guarda y consultar devuelve vacío sin romper.
    expect(AppLogger.instance.habilitado, isFalse);
    AppLogger.instance.api(metodo: 'GET', url: 'u');
    AppLogger.instance.error(titulo: 'boom');
    expect(await AppLogger.instance.consultar(), isEmpty);
  });

  // ── ruido del log (404 previstos y avisos cosméticos) ────────────────────

  test('404 previsto: se guarda el detalle pero NO como error', () async {
    await AppLogger.instance.inicializar();
    // Foto legacy que ya no existe en el servidor: es el caso que llenaba el
    // visor de [ERROR] sin describir ningún fallo real.
    AppLogger.instance.api(
      metodo: 'GET',
      url: 'https://api.climbat.net/uploads/reports/general/upload_897.jpg',
      estado: 404,
      response: '{"detail":"Not Found"}',
      duracion: const Duration(milliseconds: 424),
      esErrorEsperado: true,
    );
    await AppLogger.instance.esperarFlush();

    final todas = await AppLogger.instance.consultar();
    expect(todas, hasLength(1));
    expect(todas.single.nivel, AppLogLevel.info);
    expect(todas.single.estado, 404);
    expect(todas.single.esperado, isTrue);
    expect(todas.single.esError, isFalse);
    // La información sigue íntegra (nada se pierde, solo baja de nivel).
    expect(todas.single.titulo, contains('→ 404'));
    expect(todas.single.response, contains('Not Found'));
    expect(todas.single.durMs, 424);

    // Fuera del filtro «solo errores» (lista y exportación).
    expect(await AppLogger.instance.consultar(soloErrores: true), isEmpty);
    final export =
        await AppLogger.instance.exportarTexto(soloErrores: true);
    expect(export, isNot(contains('upload_897')));

    // En el export completo sí aparece, marcado como previsto.
    final completo = await AppLogger.instance.exportarTexto();
    expect(completo, contains('upload_897'));
    expect(completo, contains('fallo esperado'));
  });

  test('sin marcar: el mismo 404/500 sigue forzando nivel error', () async {
    await AppLogger.instance.inicializar();
    AppLogger.instance.api(
      metodo: 'GET',
      url: 'https://x/api/v2/edan/formularios',
      estado: 404,
    );
    AppLogger.instance.api(
      metodo: 'POST',
      url: 'https://x/api/v2/edan/push',
      estado: 500,
      response: '{"detail":"boom"}',
    );
    await AppLogger.instance.esperarFlush();

    final errores = await AppLogger.instance.consultar(soloErrores: true);
    expect(errores, hasLength(2));
    expect(errores.every((e) => e.nivel == AppLogLevel.error), isTrue);
    expect(errores.every((e) => e.esError), isTrue);
  });

  test('404 previsto con nivel warn: tampoco entra en «solo errores»', () async {
    await AppLogger.instance.inicializar();
    AppLogger.instance.api(
      metodo: 'GET',
      url: 'https://x/uploads/reports/a.jpg',
      estado: 404,
      nivel: AppLogLevel.warn,
      esErrorEsperado: true,
    );
    await AppLogger.instance.esperarFlush();
    final e = (await AppLogger.instance.consultar()).single;
    expect(e.nivel, AppLogLevel.warn);
    expect(e.esperado, isTrue);
    // El aviso sigue visible en su nivel, pero no se cuenta como fallo.
    expect(e.esError, isFalse);
  });

  test('error cosmético del framework: no ensucia el registro', () async {
    await AppLogger.instance.inicializar();
    expect(
      AppLogger.esRuidoCosmetico(
        Exception('ListTile background color or ink splashes may be invisible.'),
      ),
      isTrue,
    );
    AppLogger.instance.error(
      titulo: 'FlutterError: ListTile background color or ink splashes '
          'may be invisible.',
      exception: Exception('ListTile background color or ink splashes '
          'may be invisible.'),
      stack: StackTrace.current,
    );
    // Un error real SÍ pasa.
    AppLogger.instance.error(
      titulo: 'FlutterError: Null check operator used on a null value',
      exception: Exception('Null check operator used on a null value'),
    );
    await AppLogger.instance.esperarFlush();

    final entradas = await AppLogger.instance.consultar();
    expect(entradas, hasLength(1));
    expect(entradas.single.titulo, contains('Null check operator'));
  });

  test('esRuidoCosmetico: solo la lista conocida, no cualquier error', () async {
    expect(AppLogger.esRuidoCosmetico(null), isFalse);
    expect(AppLogger.esRuidoCosmetico('StateError: badge sum is zero'), isFalse);
    expect(
      AppLogger.esRuidoCosmetico(
        'ListTile background color or ink splashes may be invisible.\n'
        'The ListTile is wrapped in a DecoratedBox...',
      ),
      isTrue,
    );
    expect(
      AppLogger.ruidoCosmeticoConocido,
      isNot(contains('Zone mismatch')),
      reason: 'el desajuste de zona es un bug real: debe seguir registrándose',
    );
  });
}
