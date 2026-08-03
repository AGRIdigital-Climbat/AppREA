import 'package:flutter/material.dart';
import '../../../config/theme.dart';

IconData ugrEventoIcon(String tipo) {
  final t = tipo.toLowerCase();
  if (t.contains('inund')) return Icons.flood;
  if (t.contains('desliz')) return Icons.terrain;
  if (t.contains('helad')) return Icons.ac_unit;
  if (t.contains('incend')) return Icons.local_fire_department;
  if (t.contains('vendav')) return Icons.air;
  if (t.contains('sequ')) return Icons.wb_sunny_outlined;
  return Icons.warning_amber_rounded;
}

Color ugrEventoColor(String tipo, Color fallback) {
  final t = tipo.toLowerCase();
  if (t.contains('inund')) return AppColors.enviado;
  if (t.contains('desliz')) return AppColors.enRevision;
  if (t.contains('helad')) return AppColors.inProgress;
  if (t.contains('incend')) return AppColors.rechazado;
  if (t.contains('vendav')) return AppColors.enviado;
  if (t.contains('sequ')) return AppColors.pending;
  return fallback;
}
