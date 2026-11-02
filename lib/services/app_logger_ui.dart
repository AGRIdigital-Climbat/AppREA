import 'package:flutter/material.dart';

import 'app_logger.dart';

/// Observador de rutas: registra navegación (push/pop/replace) y mantiene
/// `AppLogger.pantallaActual` para etiquetar el resto de entradas (API, SQL,
/// sync…) con la pantalla donde ocurrieron.
///
/// Se pasa a `MaterialApp.navigatorObservers`. No interfiere con la UI: solo
/// escucha la pila de rutas.
class LogRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final nombre = _nombreDe(route);
    AppLogger.instance.nav(
      titulo: 'push → $nombre',
      pantalla: nombre,
    );
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final destino = previousRoute != null ? _nombreDe(previousRoute) : null;
    AppLogger.instance.nav(
      titulo: 'pop ← ${_nombreDe(route)}',
      pantalla: destino,
    );
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    AppLogger.instance.nav(
      titulo: 'replace ${oldRoute != null ? _nombreDe(oldRoute) : '?'} '
          '→ ${newRoute != null ? _nombreDe(newRoute) : '?'}',
      pantalla: newRoute != null ? _nombreDe(newRoute) : null,
    );
  }

  String _nombreDe(Route<dynamic> route) {
    final name = route.settings.name;
    if (name != null && name.isNotEmpty && name != '/') {
      final seg = Uri.parse(name).pathSegments;
      return seg.isNotEmpty ? seg.last : name;
    }
    // Rutas anónimas: el tipo del builder no es accesible, pero el argumento
    // suele identificar el contexto (p. ej. un uuid o un objeto pantalla).
    final arg = route.settings.arguments;
    if (arg != null) {
      final s = arg.toString();
      return '${route.runtimeType.toString().replaceAll('<dynamic>', '')}'
          '${s.length <= 60 ? ' ($s)' : ''}';
    }
    return route.runtimeType.toString().replaceAll('<dynamic>', '');
  }
}
