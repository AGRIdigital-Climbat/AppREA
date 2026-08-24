import 'package:flutter/material.dart';
import '../../../config/theme.dart';

Route<T> ugrRoute<T>(Widget screen, {ToolPalette? palette}) {
  final p = palette ?? Palettes.edan;
  return MaterialPageRoute<T>(
    builder: (_) => PaletteScope(
      palette: p,
      child: Theme(
        data: AppTheme.buildTheme(p),
        child: screen,
      ),
    ),
  );
}

Widget ugrSheetWrap(Widget child, {ToolPalette? palette}) {
  final p = palette ?? Palettes.edan;
  return PaletteScope(
    palette: p,
    child: Theme(
      data: AppTheme.buildTheme(p),
      child: child,
    ),
  );
}
