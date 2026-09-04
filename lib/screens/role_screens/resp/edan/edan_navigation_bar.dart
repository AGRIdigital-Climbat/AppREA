import 'package:flutter/material.dart';
import '../../../../config/theme.dart';

/// Barra de navegación inferior del wizard.
///
/// Muestra botones contextuales: Anterior y Siguiente / Enviar
/// según la página actual.
class EdanNavigationBar extends StatelessWidget {
  final bool showBack;
  final bool isLastPage;
  final bool isPreview;
  final bool saving;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback? onSaveDraft;
  final VoidCallback? onEnviar;

  const EdanNavigationBar({
    super.key,
    required this.showBack,
    required this.isLastPage,
    required this.isPreview,
    required this.saving,
    required this.onBack,
    required this.onNext,
    this.onSaveDraft,
    this.onEnviar,
  });

  @override
  Widget build(BuildContext context) {
    final color = PaletteScope.of(context).primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (showBack)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: saving ? null : onBack,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Anterior'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              )
            else
              const Expanded(child: SizedBox()),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: isLastPage
                  ? ElevatedButton.icon(
                      onPressed: saving ? null : (onEnviar ?? onNext),
                      icon: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send, size: 18),
                      label: Text(saving ? 'Guardando…' : 'Enviar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isPreview ? const Color(0xFF4CAF50) : color,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: saving ? null : onNext,
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      label: const Text('Siguiente'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
