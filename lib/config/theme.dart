import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // EDAN Primary - Rojo Alerta
  static const primary = Color(0xFFC0392B);
  static const primaryLight = Color(0xFFE74C3C);
  static const primaryDark = Color(0xFF7F1D1D);

  static const secondary = Color(0xFF0D47A1);

  // EDAN Backgrounds
  static const background = Color(0xFFFFF8F8);
  static const surface = Color(0xFFFFFFFF);
  static const card = Color(0xFFFFFFFF);

  // Semantic States
  static const enviado = Color(0xFF2196F3);
  static const enRevision = Color(0xFFFFB300);
  static const aprobado = Color(0xFF4CAF50);
  static const error = Color(0xFFB91C1C);
  static const rechazado = Color(0xFFF44336);
  static const cerrado = Color(0xFF607D8B);

  // Utility colors (non-state)
  static const pending = Color(0xFFFFA000);
  static const completed = Color(0xFF4CAF50);
  static const inProgress = Color(0xFF2196F3);
  static const closed = Color(0xFF6B7280);
  static const rejected = Color(0xFFDC2626);

  // EDAN Specific
  static const reaButtonPressed = Color(0xFF991B1B);
  static const reaInputFocused = Color(0xFFFFF8F8);
  static const reaFooter = Color(0xFF7F1D1D);
  static const reaFooterText = Color(0xFFFEE2E2);

  // Text
  static const textPrimary = Color(0xFF212121);
  static const textSecondary = Color(0xFF757575);
  static const divider = Color(0xFFE2E8F0);
}

@immutable
class ToolPalette {
  final Color primary;
  final Color background;
  final Color footer;
  final Color accent;

  const ToolPalette({
    required this.primary,
    required this.background,
    required this.footer,
    required this.accent,
  });
}

class Palettes {
  static const sinager = ToolPalette(
    primary: Color(0xFF1A365D),
    background: Color(0xFFF8FAFC),
    footer: Color(0xFF0F172A),
    accent: Color(0xFF3B82F6),
  );

  static const edan = ToolPalette(
    primary: Color(0xFFE67E22),
    background: Color(0xFFFFF7ED),
    footer: Color(0xFF7C2D12),
    accent: Color(0xFFC24100),
  );

  static const rea = ToolPalette(
    primary: Color(0xFFC0392B),
    background: Color(0xFFFEF2F2),
    footer: Color(0xFF7F1D1D),
    accent: Color(0xFF991B1B),
  );

  static const rida = ToolPalette(
    primary: Color(0xFF2980B9),
    background: Color(0xFFF0F9FF),
    footer: Color(0xFF0C4A6E),
    accent: Color(0xFF0284C7),
  );

  static const sinb = ToolPalette(
    primary: Color(0xFF2ECC71),
    background: Color(0xFFF0FDF4),
    footer: Color(0xFF14532D),
    accent: Color(0xFF15803D),
  );

  static const geovisor = ToolPalette(
    primary: Color(0xFF8E44AD),
    background: Color(0xFFFAF5FF),
    footer: Color(0xFF8E44AD),
    accent: Color(0xFFA855F7),
  );

  static const documentacion = ToolPalette(
    primary: Color(0xFF16A085),
    background: Color(0xFFF0FDFA),
    footer: Color(0xFF16A085),
    accent: Color(0xFF0D9488),
  );
}

class PaletteScope extends InheritedWidget {
  final ToolPalette palette;

  const PaletteScope({
    super.key,
    required this.palette,
    required super.child,
  });

  static ToolPalette of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<PaletteScope>()?.palette ??
        Palettes.edan;
  }

  @override
  bool updateShouldNotify(PaletteScope oldWidget) {
    return oldWidget.palette != palette;
  }
}

class AppTheme {
  static ThemeData buildTheme(ToolPalette palette) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.primary,
        brightness: Brightness.light,
        surface: palette.background,
      ),
      scaffoldBackgroundColor: palette.background,
      textTheme: GoogleFonts.robotoTextTheme(),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.primary,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(color: palette.primary),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.primary,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
      ),
    );
  }

  static ThemeData get lightTheme => buildTheme(Palettes.edan);
}
