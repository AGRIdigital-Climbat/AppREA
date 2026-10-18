import 'dart:async';
import 'dart:io';
import 'dart:ui';
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
import 'services/debug_log.dart';
import 'services/ai/asistente_ia_service.dart';

void main() async {
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

  await AsistenteIAService.instance.init();

  FlutterError.onError = (details) {
    DebugLog.instance.e('FlutterError: ${details.exception}', details.exception, details.stack);
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    DebugLog.instance.e('Error no capturado: $error', error, stack);
    return true;
  };

  runZonedGuarded(() {
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
    DebugLog.instance.e('Error asíncrono global: $error', error, stack);
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EDAN - Evaluación de Daños y Necesidades',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
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
