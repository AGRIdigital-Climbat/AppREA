import 'package:flutter/material.dart';
import '../../../../config/theme.dart';

/// Card de instrucciones que se muestra al inicio de cada sección del wizard.
class EdanSeccionInstruction extends StatelessWidget {
  final String titulo;
  final String instruccion;
  final IconData icono;
  final String? estadoEtiqueta;
  final bool completada;

  const EdanSeccionInstruction({
    super.key,
    required this.titulo,
    required this.instruccion,
    required this.icono,
    this.estadoEtiqueta,
    this.completada = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = PaletteScope.of(context).primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    titulo,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                if (estadoEtiqueta != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: completada
                          ? const Color(0xFF4CAF50)
                          : color,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      estadoEtiqueta!,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
