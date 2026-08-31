import 'package:flutter/material.dart';
import '../../../../config/theme.dart';

/// Stepper visual del wizard: círculos de sección conectados por líneas,
/// con scroll horizontal cuando hay muchos pasos.
///
/// Cada círculo muestra el icono de la sección. Estados:
/// - Actual: relleno con el color primario del tema.
/// - Completado: relleno verde con check.
/// - Pendiente: gris claro con el icono de la sección.
///
/// Los círculos son clickeables (salto libre) mediante [onTap].
class EdanStepIndicator extends StatelessWidget {
  final int currentIndex;
  final int total;
  final List<String> titulos;
  final List<IconData> iconos;
  final List<bool> completada;
  final ValueChanged<int>? onTap;

  const EdanStepIndicator({
    super.key,
    required this.currentIndex,
    required this.total,
    required this.titulos,
    required this.iconos,
    this.completada = const [],
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = PaletteScope.of(context).primary;
    final titulo = currentIndex < titulos.length ? titulos[currentIndex] : '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < total; i++) ...[
                  if (i > 0) _conector(i - 1),
                  _circulo(context, color, i),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'Paso ${currentIndex + 1} de $total',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Linea que conecta el círculo [desde] con el siguiente.
  Widget _conector(int desde) {
    final completado = desde < completada.length && completada[desde];
    final color = completado ? AppColors.completed : AppColors.divider;
    return Container(
      width: 18,
      height: 3,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _circulo(BuildContext context, Color primary, int i) {
    final esActual = i == currentIndex;
    final esCompletado = i < completada.length && completada[i];

    Color fondo;
    Color iconoColor;
    IconData icon;
    Border? borde;

    if (esCompletado) {
      fondo = AppColors.completed;
      icon = iconos.isNotEmpty ? iconos[i] : Icons.check;
      iconoColor = Colors.white;
    } else {
      fondo = AppColors.divider;
      icon = iconos.isNotEmpty ? iconos[i] : Icons.circle;
      iconoColor = AppColors.textSecondary;
    }

    if (esActual) {
      borde = Border.all(
        color: AppColors.pending,
        width: 2,
      );
    }

    final tooltip = i < titulos.length
        ? '${i + 1}. ${titulos[i]}'
        : '${i + 1}';

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () => onTap?.call(i),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: fondo,
            shape: BoxShape.circle,
            border: borde,
          ),
          child: Icon(icon, size: 18, color: iconoColor),
        ),
      ),
    );
  }
}