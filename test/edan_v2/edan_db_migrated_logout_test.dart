/// Migración de BD al actualizar: `_onUpgrade` (DB < v41) escribe
/// `db_migrated=true` en SharedPreferences; `AuthService.initialize()` lo
/// detecta, limpia `first_sync_done_*` y borra el flag SIN tocar la sesión
/// (forzar logout devolvía la app al login en cada actualización con
/// migración). Con secure-storage mockeado se comprueba que la sesión
/// guardada se restaura tras la migración y que un fallo de red no la
/// destruye.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rea/services/auth_service.dart';
import 'package:rea/services/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('_onUpgrade escribe db_migrated (v31 → v41)', () {
    late Directory dir;
    final db = DatabaseHelper.instance;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('edan_migracion');
      DatabaseHelper.rutaDePrueba = p.join(dir.path, 'test.db');
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      await db.cerrarParaPrueba();
      DatabaseHelper.rutaDePrueba = null;
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('al reabrir una DB v31 el flag queda true', () async {
      // 1. Crear DB "vieja" (v31) con al menos una tabla.
      final ruta = p.join(dir.path, 'test.db');
      final v31 = await openDatabase(
        ruta,
        version: 31,
        onCreate: (d, _) async {
          await d.execute('''
            CREATE TABLE formularios (
              uuid_edan_localidad TEXT PRIMARY KEY,
              localidad TEXT NOT NULL DEFAULT ''
            )
          ''');
        },
      );
      await v31.insert('formularios', {'uuid_edan_localidad': 'loc-vieja'});
      await v31.close();

      // 2. Reabrir con DatabaseHelper (v41): _onUpgrade corre DROP+CREATE
      // y escribe db_migrated=true.
      await db.database;

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('db_migrated'), isTrue,
          reason: '_onUpgrade debe marcar db_migrated tras migrar');
    });

    test('una DB recién creada (onCreate, no upgrade) NO setea el flag',
        () async {
      await db.database; // onCreate, no onUpgrade

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('db_migrated'), isNull,
          reason: 'onCreate no debe setear db_migrated');
    });
  });

  group('AuthService.initialize() detecta el flag', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('db_migrated=true → limpia flag y first_sync_done_* CONSERVANDO sesión',
        () async {
      SharedPreferences.setMockInitialValues({
        'db_migrated': true,
        'first_sync_done_1': true,
        'first_sync_done_2': true,
        'has_logged_in': true,
        'profile_nombre': 'Test',
      });

      await AuthService.instance.initialize();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('db_migrated'), isNull,
          reason: 'el flag debe borrarse tras procesarse');
      expect(prefs.getBool('first_sync_done_1'), isNull,
          reason: 'first_sync_done_* debe limpiarse');
      expect(prefs.getBool('first_sync_done_2'), isNull,
          reason: 'first_sync_done_* debe limpiarse');
      // La migración ya NO cierra sesión: has_logged_in y el perfil siguen
      // intactos (en este entorno sin plugin de secure storage el token no es
      // legible, por eso isAuthenticated queda false sin haber borrado nada).
      expect(prefs.getBool('has_logged_in'), isTrue,
          reason: 'la migración conserva la sesión');
      expect(prefs.getString('profile_nombre'), 'Test',
          reason: 'el perfil no se toca');
      expect(AuthService.instance.isAuthenticated, isFalse,
          reason: 'sin storage mockeado no hay token que restaurar, '
              'pero nada fue borrado');
    });

    test('sin db_migrated no se limpia first_sync_done_*', () async {
      SharedPreferences.setMockInitialValues({
        'first_sync_done_1': true,
      });

      await AuthService.instance.initialize();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('first_sync_done_1'), isTrue,
          reason: 'sin el flag no debe tocarse first_sync_done');
    });

    test('db_migrated=false se ignora igual que ausente', () async {
      SharedPreferences.setMockInitialValues({
        'db_migrated': false,
        'first_sync_done_1': true,
      });

      await AuthService.instance.initialize();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('first_sync_done_1'), isTrue);
    });
  });

  group('Sesión restaurada tras migración (secure storage mockeado)', () {
    const canal = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final storage = <String, String?>{};

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      storage.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(canal, (call) async {
        final args = (call.arguments as Map).cast<String, Object?>();
        switch (call.method) {
          case 'read':
            return storage[args['key'] as String];
          case 'write':
            storage[args['key'] as String] = args['value'] as String?;
            return null;
          case 'delete':
            storage.remove(args['key'] as String);
            return null;
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(canal, null);
      HttpOverrides.global = null;
    });

    void guardarSesion({required String rol, required DateTime lastLogin}) {
      storage.addAll({
        'auth_token': 'jwt-de-prueba',
        'user_id': '28',
        'usuario': 'UGRSCZ',
        'nombre': 'Ugr User',
        'contrasena': 'secreta',
        'id_rol': rol,
        'rol_name': 'UGR Municipio',
        'last_login': lastLogin.toIso8601String(),
        'permisos': '{}',
      });
    }

    test('migración con token vigente → sesión restaurada sin logout',
        () async {
      guardarSesion(rol: '6', lastLogin: DateTime.now());
      SharedPreferences.setMockInitialValues({
        'db_migrated': true,
        'first_sync_done_28': true,
        'has_logged_in': true,
        'profile_nombre': 'Ugr User',
      });

      await AuthService.instance.initialize();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('db_migrated'), isNull);
      expect(prefs.getBool('first_sync_done_28'), isNull,
          reason: 'el sync inicial vuelve a marcarse tras la migración');
      expect(prefs.getBool('has_logged_in'), isTrue);
      expect(AuthService.instance.isAuthenticated, isTrue,
          reason: 'la migración ya NO devuelve la app al login');
      expect(storage['auth_token'], 'jwt-de-prueba',
          reason: 'el token guardado no se toca');
    });

    test('rol 6 con ventana vencida y SIN red → sesión restaurada igual',
        () async {
      // last_login de hace 10 dias (ventana rol 6 = 3 dias) y red que falla:
      // el re-login silencioso no puede tumbar la sesion restaurada.
      guardarSesion(
          rol: '6',
          lastLogin: DateTime.now().subtract(const Duration(days: 10)));
      SharedPreferences.setMockInitialValues({
        'has_logged_in': true,
        'profile_nombre': 'Ugr User',
      });
      HttpOverrides.global = _SinRed();

      await AuthService.instance.initialize();
      // Dejar correr el re-login silencioso (unawaited) hasta su fallo.
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(AuthService.instance.isAuthenticated, isTrue,
          reason: 'arranque offline con ventana vencida: entra igual');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('has_logged_in'), isTrue);
      expect(storage['auth_token'], 'jwt-de-prueba');
    });

    test('sin token y SIN red → credenciales conservadas (no logout)',
        () async {
      // Sin auth_token guardado pero con credenciales: login() falla por
      // red. Antes terminaba en logout() y borraba contrasena/perfil,
      // dejando login permanente. Ahora se conserva todo para reintentar.
      storage.addAll({
        'usuario': 'UGRSCZ',
        'contrasena': 'secreta',
        'id_rol': '6',
      });
      SharedPreferences.setMockInitialValues({
        'has_logged_in': true,
      });
      HttpOverrides.global = _SinRed();

      await AuthService.instance.initialize();

      expect(AuthService.instance.isAuthenticated, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('has_logged_in'), isTrue,
          reason: 'un fallo de red no debe borrar la sesión guardada');
      expect(storage['contrasena'], 'secreta',
          reason: 'las credenciales siguen para el próximo intento');
    });
  });
}

/// HttpOverrides que hace que cualquier conexión falle al instante, simulando
/// arranque sin cobertura (el retry interno de `login()` reintenta con
/// backoff corto; el override lanza antes de tocar red real).
class _SinRed extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw const SocketException('sin red (entorno de prueba)');
  }
}
