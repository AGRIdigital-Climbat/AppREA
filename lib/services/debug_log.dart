import 'dart:io';
import 'dart:async';

import 'package:path_provider/path_provider.dart';

/// Registro de diagnóstico en archivo para depuración en dispositivo real.
///
/// Escribe a la vez en consola (debugPrint) y en un archivo de sesión dentro
/// de los documentos de la app:
///   <app>/app_flutter/rea_logs/debug_<timestamp>.log
///
/// El archivo puede extraerse por ADB con:
///   adb shell run-as net.climbat.rea cat app_flutter/rea_logs/debug_*.log
class DebugLog {
  DebugLog._();

  static final DebugLog instance = DebugLog._();

  File? _file;
  bool _habilitado = false;
  final StringBuffer _memoria = StringBuffer();

  /// Ruta del archivo de log de la sesión actual (null si no inicializado).
  String? get rutaArchivo => _file?.path;

  /// Texto acumulado en memoria (usado como respaldo si falla IO).
  String get contenidoMemoria => _memoria.toString();

  bool get habilitado => _habilitado;

  /// Inicializa el archivo de log de esta sesión.
  /// Devuelve la ruta creada o null ante error (en ese caso sólo se loguea en
  /// memoria y se reenvía el fallo al llamador que quiera mostrarlo).
  Future<String?> inicializar() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final carpetas = Directory('${dir.path}${Platform.pathSeparator}rea_logs');
      if (!await carpetas.exists()) {
        await carpetas.create(recursive: true);
      }
      final ts = _selloParaArchivo(DateTime.now());
      final archivo = File('${carpetas.path}${Platform.pathSeparator}debug_$ts.log');
      _file = archivo;
      _habilitado = true;
      await _escribirInterno(
          '=== INICIO SESIÓN EDAN $ts ===\nPlataforma: ${Platform.operatingSystem}');
      return archivo.path;
    } catch (e) {
      _habilitado = false;
      return null;
    }
  }

  /// Escribe un mensaje informativo.
  void i(String mensaje) => _log('INFO', mensaje);

  /// Escribe un mensaje de error.
  void e(String mensaje, [Object? error, StackTrace? stack]) {
    _log('ERROR', mensaje);
    if (error != null) _log('ERROR', '  -> $error');
    if (stack != null) _log('ERROR', '  -> $stack');
  }

  /// Escribe un separador/encabezado para delimitar pasos.
  void paso(String titulo) => _log('====', '>>> $titulo');

  void _log(String nivel, String mensaje) {
    final linea = '${_marcaTiempo()} [$nivel] $mensaje';
    // ignore: avoid_print
    print(linea);
    _memoria.writeln(linea);
    if (_habilitado && _file != null) {
      unawaited(_escribirInterno(linea));
    }
  }

  Future<void> _escribirInterno(String linea) async {
    try {
      await _file!.writeAsString('$linea\n', mode: FileMode.append);
    } catch (_) {}
  }

  static String _marcaTiempo() {
    final n = DateTime.now();
    String dos(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${dos(n.month)}-${dos(n.day)} '
        '${dos(n.hour)}:${dos(n.minute)}:${dos(n.second)}.${n.millisecond.toString().padLeft(3, '0')}';
  }

  static String _selloParaArchivo(DateTime n) {
    String dos(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${dos(n.month)}${dos(n.day)}'
        '_${dos(n.hour)}${dos(n.minute)}${dos(n.second)}';
  }
}
