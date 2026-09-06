import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import '../screens/splash_screen.dart';
import '../screens/login_screen.dart';
import '../screens/register_screen.dart';
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
