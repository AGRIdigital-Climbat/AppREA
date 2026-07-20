import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../config/theme.dart';

Locale _locale = const Locale('es', 'BO');
List<LocalizationsDelegate> _delegates = const [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
List<Locale> _supported = const [
  Locale('es', 'BO'),
  Locale('en', 'US'),
];

Widget reaSimpleWrapper(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    locale: _locale,
    localizationsDelegates: _delegates,
    supportedLocales: _supported,
    home: Scaffold(
      body: SafeArea(child: child),
    ),
  );
}

Widget reaFullScreenWrapper(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    locale: _locale,
    localizationsDelegates: _delegates,
    supportedLocales: _supported,
    home: child,
  );
}
