import 'package:flutter/material.dart';
import '../../../../config/theme.dart';

/// Encabezado de subsección con botón para agregar ítems.
class EdanSubsectionHeader extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final VoidCallback onAgregar;
  final String botonAgregar;
  final int itemCount;

  const EdanSubsectionHeader({
    super.key,
    required this.titulo,
    required this.icono,
    required this.onAgregar,
    this.botonAgregar = 'Agregar',
    this.itemCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = PaletteScope.of(context).primary;
    return Row(
      children: [
        Icon(icono, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            titulo,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (itemCount > 0)
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$itemCount',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        Material(
          color: color,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onAgregar,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add, color: Colors.white, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    botonAgregar,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
