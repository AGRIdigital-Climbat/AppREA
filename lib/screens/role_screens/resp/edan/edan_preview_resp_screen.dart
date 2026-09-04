import 'package:flutter/material.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import 'edan_resumen_page.dart';

/// Pantalla de previsualización del EDAN para el rol RESP.
///
/// Envuelve [EdanResumenPage] en un Scaffold con AppBar y barra de
/// acciones ("Volver y Editar" / "Confirmar y Enviar").
///
/// Hace pop con `true` cuando el usuario confirma el envío, o `null`
/// cuando vuelve atrás.
class EdanPreviewRespScreen extends StatelessWidget {
  final EdanLocalidad localidad;

  const EdanPreviewRespScreen({super.key, required this.localidad});

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    final seccionesCompletas =
        EdanResumenPage.calcularSeccionesCompletas(localidad);
    final tieneDatos = seccionesCompletas.values.any((v) => v);
    final incompletos = seccionesCompletas.entries
        .where((e) => !e.value)
        .map((e) => e.key)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          localidad.nombre.isNotEmpty ? localidad.nombre : 'Vista previa EDAN',
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: EdanResumenPage(
          localidad: localidad,
          seccionesCompletas: seccionesCompletas,
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (incompletos.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.pending.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.pending.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 16, color: AppColors.pending),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Secciones incompletas: ${incompletos.join(", ")}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.pending,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (incompletos.isNotEmpty) const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primary,
                        side: BorderSide(color: primary, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        minimumSize: const Size(0, 50),
                      ),
                      child: const Text('Volver'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: tieneDatos
                          ? () => _confirmarEnvio(context)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.divider,
                        disabledForegroundColor: AppColors.textSecondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        minimumSize: const Size(0, 50),
                      ),
                      child: const Text('Enviar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmarEnvio(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon:
            const Icon(Icons.warning_amber_rounded, size: 48, color: Color(0xFFF59E0B)),
        title: const Text('Confirmar envío'),
        content: const Text(
          'La información será revisada para análisis. '
          'Corresponde hacer el documento legal del EDAN municipal '
          'por parte del UGR.\n\n'
          'Es información con declaración jurada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
            ),
            child: const Text('Enviar'),
          ),
        ],
      ),
    ).then((confirmado) {
      if (confirmado == true && context.mounted) {
        Navigator.of(context).pop(true);
      }
    });
  }
}
