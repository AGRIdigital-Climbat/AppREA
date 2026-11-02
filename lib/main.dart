import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/reporte_provider.dart';
import 'providers/connectivity_provider.dart';
import 'screens/splash_screen.dart';
import 'services/connectivity_service.dart';
import 'services/app_logger.dart';
import 'services/app_logger_ui.dart';
import 'services/debug_log.dart';
import 'services/ai/asistente_ia_service.dart';

/// Arranque de la app.
///
/// TODO dentro de [runZonedGuarded]: `WidgetsFlutterBinding.ensureInitialized()`
/// y `runApp()` tienen que ejecutarse en la MISMA zona, si no el framework
/// lanza `FlutterError: Zone mismatch` en cada arranque (el binding guarda su
/// zona y comprueba la activa en cada callback). Por eso el `main` ya no hace
/// inicialización fuera de la zona.
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Desktop: inicializar la factory de SQLite (databaseFactoryFfi).
    // Necesario antes de cualquier uso de openDatabase en Windows/Linux.
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final rutaLog = await DebugLog.instance.inicializar();
    if (rutaLog != null) {
      // ignore: avoid_print
      print('[EDAN-LOG] Shabira depuración en: $rutaLog');
    }

    // Registro global de la app (APIs, SQL, clics, navegación, errores).
    // Guarda en SQLite y retiene 24 h. Visible desde el icono «Debug» de los
    // roles 6 y 7. Si falla, la app sigue funcionando (quedan no-op).
    final rutaBdLog = await AppLogger.instance.inicializar();
    AppLogger.instance.app(
      titulo: 'Arranque de la app',
      detalle: 'plataforma=${Platform.operatingSystem} '
          '${kReleaseMode ? 'release' : 'debug/profile'} · '
          'bd_log=${rutaBdLog ?? 'NO (logger deshabilitado)'}',
    );

    await AsistenteIAService.instance.init();

    FlutterError.onError = (details) {
      // Los avisos puramente cosméticos del framework no van al registro:
      // llenan el visor de 24 h con ruido que no describe ningún fallo real
      // (p. ej. el aviso de ListTile sobre fondo decorado). Se siguen
      // mostrando en consola para quien desarrolle.
      if (AppLogger.esRuidoCosmetico(details.exception)) {
        FlutterError.presentError(details);
        return;
      }
      DebugLog.instance.e('FlutterError: ${details.exception}', details.exception, details.stack);
      AppLogger.instance.error(
        titulo: 'FlutterError: ${details.exception}',
        exception: details.exception,
        stack: details.stack,
      );
      FlutterError.presentError(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      if (!AppLogger.esRuidoCosmetico(error)) {
        DebugLog.instance.e('Error no capturado: $error', error, stack);
        AppLogger.instance.error(
          titulo: 'Error no capturado: $error',
          exception: error,
          stack: stack,
        );
      }
      return true;
    };

    // Unico punto de inicializacion de la conectividad. Arranca el primer
    // chequeo de red cuanto antes; el ConnectivityProvider espera el mismo
    // Future (initialize es idempotente y esperable) para publicar el estado
    // real a la UI. Las pantallas de rol ya no la arrancan por su cuenta.
    unawaited(ConnectivityService().initialize());

    final connectivityProvider = ConnectivityProvider();
    unawaited(connectivityProvider.initialize());

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ReporteProvider()),
          ChangeNotifierProvider<ConnectivityProvider>.value(
            value: connectivityProvider,
          ),
        ],
        child: const MyApp(),
      ),
    );
  }, (error, stack) {
    if (AppLogger.esRuidoCosmetico(error)) return;
    DebugLog.instance.e('Error asíncrono global: $error', error, stack);
    AppLogger.instance.error(
      titulo: 'Error asíncrono global: $error',
      exception: error,
      stack: stack,
    );
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  /// Observador único de navegación para el registro global (AppLogger).
  static final LogRouteObserver _routeLogger = LogRouteObserver();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EDAN - Evaluación de Daños y Necesidades',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      navigatorObservers: [_routeLogger],
      locale: const Locale('es', 'BO'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es', 'BO'),
        Locale('en', 'US'),
      ],
      home: const SplashScreen(),
    );
  }
}
