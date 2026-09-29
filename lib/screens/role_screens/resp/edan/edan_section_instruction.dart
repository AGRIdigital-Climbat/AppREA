import 'package:flutter/material.dart';
import '../../../../config/theme.dart';

/// Card de instrucciones que se muestra al inicio de cada sección del wizard.
class EdanSeccionInstruction extends StatelessWidget {
  final String titulo;
  final String instruccion;
  final IconData icono;
  final String? estadoEtiqueta;
  final bool completada;
  final VoidCallback? onAyuda;

  const EdanSeccionInstruction({
    super.key,
    required this.titulo,
    required this.instruccion,
    required this.icono,
    this.estadoEtiqueta,
    this.completada = false,
    this.onAyuda,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Primera fila: icono + título.
          Row(
            children: [
              Icon(icono, color: color, size: 22),
              const SizedBox(width: 12),
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
            ],
          ),
          // Segunda fila: estado a la izquierda y ayuda a la derecha.
          if (estadoEtiqueta != null || onAyuda != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (estadoEtiqueta != null)
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
                const Spacer(),
                if (onAyuda != null)
                  Material(
                    color: const Color(0xFF2563EB),
                    borderRadius: BorderRadius.circular(20),
                    elevation: 2,
                    shadowColor:
                        const Color(0xFF2563EB).withValues(alpha: 0.45),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: onAyuda,
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.help_outline,
                                color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Ayuda',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
