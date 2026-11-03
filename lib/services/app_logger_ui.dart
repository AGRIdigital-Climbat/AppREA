import 'package:flutter/material.dart';

import 'app_logger.dart';

/// Muestra un [SnackBar] Y registra su texto en el registro global
/// ([AppLogger], categoría APP).
///
/// La queja del usuario siempre empieza por lo que ve en pantalla; hasta aho-
/// ra el snackbar desaparecía con el frame y el `registro` guardaba solo media
/// historia (la causa que lo disparó). El nivel se deduce del fondo: rojo =
/// error, ámbar = warn, resto = info. Nunca rompe la UI: un fallo del log se
/// traga y el snackbar se muestra igual.
///
/// Reemplazo directo de `ScaffoldMessenger.of(ctx).showSnackBar(snack)`.
void showAppSnackBar(BuildContext context, SnackBar snackBar) {
  _logSnack(snackBar);
  ScaffoldMessenger.of(context).showSnackBar(snackBar);
}

/// Variante para cuando ya se tiene el `ScaffoldMessengerState` capturado
/// (p. ej. antes de un `await` con guarda de `mounted`).
void showAppSnackBarOn(ScaffoldMessengerState messenger, SnackBar snackBar) {
  _logSnack(snackBar);
  messenger.showSnackBar(snackBar);
}

void _logSnack(SnackBar snackBar) {
  try {
    AppLogger.instance.app(
      nivel: nivelSnackLog(snackBar.backgroundColor),
      titulo: 'Snackbar: ${_textoSnack(snackBar)}',
      detalle: snackBar.action != null
          ? 'accion: ${snackBar.action!.label}'
          : null,
    );
  } catch (_) {}
}

/// Nivel de log según el color de fondo del snackbar (null = tema → info).
/// Rojo puro (~AppColors.error) → error; ámbar (0xFFF59E0B, el de
/// "incompleta") → warn; verde/azul informativos → info.
AppLogLevel nivelSnackLog(Color? color) {
  if (color == null) return AppLogLevel.info;
  final r = color.r, g = color.g, b = color.b;
  // Ambar (rojo fuerte + verde medio, 0xFFF59E0B "incompleta" o el
  // AppColors.pending) -> warn. Rojo dominante (error/rechazado del tema,
  // incluidos tonos oscuros como 0xFFB91C1C) -> error. Verde/azul -> info.
  if (r > 0.75 && g >= 0.35 && g < 0.8 && b < 0.35) return AppLogLevel.warn;
  if (r > 0.5 && (r - g) > 0.45 && (r - b) > 0.45) return AppLogLevel.error;
  return AppLogLevel.info;
}

String _textoSnack(SnackBar snackBar) {
  final c = snackBar.content;
  if (c is Text) {
    final t = c.data ?? c.textSpan?.toPlainText();
    if (t != null && t.isNotEmpty) return t;
  }
  return c.toString();
}

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
