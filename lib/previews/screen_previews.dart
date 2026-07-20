import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import '../screens/splash_screen.dart';
import '../screens/login_screen.dart';
import '../screens/register_screen.dart';
import '../screens/reporte_form_screen.dart';
import '../screens/reporte_preview_screen.dart';
import 'screen_wrapper.dart';

@Preview(name: 'SplashScreen', group: 'Pantallas', wrapper: reaFullScreenWrapper)
Widget splashScreenPreview() {
  return const SplashScreen();
}

@Preview(name: 'LoginScreen', group: 'Pantallas', wrapper: reaFullScreenWrapper)
Widget loginScreenPreview() {
  return const LoginScreen();
}

@Preview(name: 'RegisterScreen', group: 'Pantallas', wrapper: reaFullScreenWrapper)
Widget registerScreenPreview() {
  return const RegisterScreen();
}

@Preview(name: 'ReporteFormScreen', group: 'Pantallas', wrapper: reaFullScreenWrapper)
Widget reporteFormScreenPreview() {
  return const ReporteFormScreen();
}

@Preview(name: 'ReportePreviewScreen', group: 'Pantallas', wrapper: reaSimpleWrapper)
Widget reportePreviewScreenPreview() {
  return SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: ReportePreviewScreen(
      departamentoId: 1,
      provinciaId: 1,
      municipioId: 1,
      comunidad: 'Villa Fatima',
      departamentoNombre: 'La Paz',
      provinciaNombre: 'Murillo',
      municipioNombre: 'La Paz',
      fechaEvento: '2026-07-15',
      fechaEventoDisplay: '15/7/2026',
      horaEvento: '14:30',
      tipoEventoId: 1,
      descripcion: 'Inundacion por desborde de rio.',
      imagenes: [],
      categorias: [1, 4, 5],
      latitud: -16.5,
      longitud: -68.15,
    ),
  );
}
