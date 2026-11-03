/// Nivel de log que `showAppSnackBar` deduce del fondo del snackbar: lo que
/// el usuario ve en rojo/ámbar debe quedar marcado como error/warn en el
/// registro de 24 h (el texto vive en el título de la entrada).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rea/config/theme.dart';
import 'package:rea/services/app_logger.dart';
import 'package:rea/services/app_logger_ui.dart';

void main() {
  group('nivelSnackLog', () {
    test('sin fondo (theme por defecto) = info', () {
      expect(nivelSnackLog(null), AppLogLevel.info);
    });

    test('rojo del tema = error', () {
      expect(nivelSnackLog(AppColors.error), AppLogLevel.error);
    });

    test('ámbar de "Primera sincronización incompleta" = warn', () {
      expect(nivelSnackLog(const Color(0xFFF59E0B)), AppLogLevel.warn);
    });

    test('verde de confirmación = info (no ensucia como fallo)', () {
      expect(nivelSnackLog(AppColors.completed), AppLogLevel.info);
    });
  });
}
