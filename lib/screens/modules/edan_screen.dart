import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../widgets/module_shell.dart';

class EdanScreen extends StatelessWidget {
  const EdanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ModuleShell(
      moduleName: 'EDAN',
      tabs: [
        ModuleTab(
          title: 'Inicio',
          icon: Icons.home_outlined,
          activeIcon: Icons.home,
          builder: (_) => _buildPlaceholder(
            icon: Icons.assessment_rounded,
            title: 'EDAN',
            subtitle: 'Evaluación de Daños y Necesidades',
          ),
        ),
        ModuleTab(
          title: 'Historial',
          icon: Icons.list_outlined,
          activeIcon: Icons.list,
          builder: (_) => _buildPlaceholder(
            icon: Icons.list_alt_rounded,
            title: 'Historial EDAN',
            subtitle: 'Historial de reportes EDAN',
          ),
        ),
        ModuleTab(
          title: 'Mapa',
          icon: Icons.location_city_outlined,
          activeIcon: Icons.location_city,
          builder: (_) => _buildPlaceholder(
            icon: Icons.map_rounded,
            title: 'Mapa EDAN',
            subtitle: 'Mapa de reportes EDAN',
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholder({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFEEBA), width: 1),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline, size: 16, color: Color(0xFF856404)),
                  SizedBox(width: 8),
                  Text(
                    'Proximamente disponible',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF856404),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
