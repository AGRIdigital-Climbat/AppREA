import 'package:flutter/material.dart';
import '../providers/auth_provider.dart';
import '../screens/home_with_drawer.dart';
import '../screens/role_screens/ugr_screen.dart';
import '../screens/role_screens/resp_screen.dart';

Widget homeForRole(AuthProvider auth) {
  switch (auth.idRol) {
    case 6:
      return const UgrScreen();
    case 7:
      return const RespScreen();
    default:
      return const HomeWithDrawer();
  }
}
