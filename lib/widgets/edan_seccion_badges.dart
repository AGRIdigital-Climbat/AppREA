import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/edan.dart';
import '../services/edan_secciones_registry.dart';

/// Muestra badges de las secciones activas de una localidad EDAN.
/// Refleja los flags marcados en page01.
class EdanSeccionBadges extends StatelessWidget {
  final EdanLocalidad localidad;

  const EdanSeccionBadges({super.key, required this.localidad});

  @override
  Widget build(BuildContext context) {
    final labels = EdanSeccionesRegistry.seccionesActivasLabels(localidad);
    if (labels.isEmpty) return const SizedBox.shrink();

    final primary = PaletteScope.of(context).primary;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: labels
          .map(
            (t) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: primary.withValues(alpha: 0.25)),
              ),
              child: Text(
                t,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
