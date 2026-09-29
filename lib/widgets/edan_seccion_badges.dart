import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/edan.dart';
import '../services/edan_secciones_registry.dart';

/// Muestra badges de las secciones activas de una localidad EDAN.
/// Refleja los flags marcados en page01 con el mismo diseño de píldoras de
/// impacto que usa el item de UGR (rol 6).
class EdanSeccionBadges extends StatelessWidget {
  final EdanLocalidad localidad;

  const EdanSeccionBadges({super.key, required this.localidad});

  @override
  Widget build(BuildContext context) {
    final labels =
        EdanSeccionesRegistry.seccionesActivasLabelsCortos(localidad);
    if (labels.isEmpty) return const SizedBox.shrink();

    final primary = PaletteScope.of(context).primary;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: labels
          .map(
            (t) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                t,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: primary,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
