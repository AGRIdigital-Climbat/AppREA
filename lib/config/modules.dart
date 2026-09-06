import 'package:flutter/material.dart';
import '../screens/modules/edan_screen.dart';
import '../screens/modules/rida_screen.dart';
import '../screens/modules/sinb_screen.dart';

enum ModuleType { edan, rida, sinb }

class ModuleConfig {
  final ModuleType type;
  final String title;
  final String subtitle;
  final IconData icon;
  final String permissionKey;
  final WidgetBuilder screenBuilder;

  const ModuleConfig({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.permissionKey,
    required this.screenBuilder,
  });
}

final List<ModuleConfig> kModules = [
  ModuleConfig(
    type: ModuleType.edan,
    title: 'EDAN',
    subtitle: 'Evaluación de daños y análisis de necesidades',
    icon: Icons.assessment_rounded,
    permissionKey: 'EDAN',
    screenBuilder: (_) => const EdanScreen(),
  ),
  ModuleConfig(
    type: ModuleType.rida,
    title: 'RIDA',
    subtitle: 'Registro de Información de Daños',
    icon: Icons.bar_chart_rounded,
    permissionKey: 'RIDA',
    screenBuilder: (_) => const RidaScreen(),
  ),
  ModuleConfig(
    type: ModuleType.sinb,
    title: 'SIN-B',
    subtitle: 'Sistema de Información Nacional B',
    icon: Icons.analytics_rounded,
    permissionKey: 'SINB',
    screenBuilder: (_) => const SinbScreen(),
  ),
];

ModuleConfig? findModuleByType(ModuleType type) {
  try {
    return kModules.firstWhere((m) => m.type == type);
  } catch (_) {
    return null;
  }
}
