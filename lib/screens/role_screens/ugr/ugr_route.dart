import 'package:flutter/material.dart';
import '../../../config/theme.dart';

Route<T> ugrRoute<T>(Widget screen) {
  return MaterialPageRoute<T>(
    builder: (_) => PaletteScope(
      palette: Palettes.edan,
      child: Theme(
        data: AppTheme.buildTheme(Palettes.edan),
        child: screen,
      ),
    ),
  );
}

Widget ugrSheetWrap(Widget child) {
  return PaletteScope(
    palette: Palettes.edan,
    child: Theme(
      data: AppTheme.buildTheme(Palettes.edan),
      child: child,
    ),
  );
}
