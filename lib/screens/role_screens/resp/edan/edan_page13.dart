import 'package:flutter/material.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import '../../../../services/auth_service.dart';

/// Página 13: Datos del responsable del formulario.
class EdanPage13 extends StatelessWidget {
  final EdanLocalidad localidad;

  const EdanPage13({super.key, required this.localidad});

  @override
  Widget build(BuildContext context) {
    final token = AuthService.instance.currentToken;
    final r = localidad.responsable!;
    if (r.nombre.isEmpty) r.nombre = token?.nombre ?? '';
    if (r.cargo.isEmpty) r.cargo = token?.cargo ?? '';
    if (r.fono.isEmpty) r.fono = token?.celular ?? '';
    if (r.correo.isEmpty) r.correo = token?.correo ?? '';

    Widget linea(String label, String? value) {
      if (value == null || value.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Text(
                label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Datos del usuario registrado',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              linea('Nombre', r.nombre),
              linea('Cargo', r.cargo),
              linea('Teléfono', r.fono),
              linea('Carnet', token?.carnet),
              linea('Correo', r.correo),
              linea('Departamento', token?.departamentoNombre),
              linea('Provincia', token?.provinciaNombre),
              linea('Municipio', token?.municipioNombre),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'La información del responsable se completa automáticamente con los '
          'datos del usuario que registra el formulario.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
