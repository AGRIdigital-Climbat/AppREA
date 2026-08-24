import 'package:flutter/material.dart';
import '../config/modules.dart';
import '../config/theme.dart';

class AppDrawer extends StatelessWidget {
  final String userName;
  final ModuleType currentModule;
  final bool Function(ModuleType) isModuleEnabled;
  final ValueChanged<ModuleType>? onModuleTap;
  final VoidCallback? onClose;
  final VoidCallback? onProfileTap;
  final VoidCallback? onLogout;

  const AppDrawer({
    super.key,
    required this.userName,
    required this.currentModule,
    required this.isModuleEnabled,
    this.onModuleTap,
    this.onClose,
    this.onProfileTap,
    this.onLogout,
  });

  static const Color _neutral400 = Color(0xFF9CA3AF);
  static const Color _neutral500 = Color(0xFF6B7280);
  static const Color _neutral300 = Color(0xFFD1D5DB);
  static const Color _selectedBg = Color(0xFFFFF5F5);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFAFAFA), Color(0xFFF5F5F5)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildDivider(),
            _buildMenuSection(context),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final initials = userName.isNotEmpty
        ? userName.split(' ').map((s) => s.isNotEmpty ? s[0] : '').take(2).join()
        : 'U';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(Icons.shield_rounded, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          const Text(
            'SINAGER-SAT',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                initials.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(height: 1, color: AppColors.divider),
    );
  }

  Widget _buildMenuSection(BuildContext context) {
    return Expanded(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        children: [
          _buildSectionLabel('HERRAMIENTAS'),
          const SizedBox(height: 4),
          ...kModules.map((module) => _buildModuleItem(
                icon: module.icon,
                title: module.title,
                subtitle: module.subtitle,
                isSelected: currentModule == module.type,
                isEnabled: isModuleEnabled(module.type),
                onTap: isModuleEnabled(module.type)
                    ? () {
                        onClose?.call();
                        onModuleTap?.call(module.type);
                      }
                    : null,
              )),
          const SizedBox(height: 16),
          _buildSectionLabel('GENERAL'),
          const SizedBox(height: 4),
          _buildMenuItem(
            icon: Icons.map_rounded,
            title: 'Mapas',
            subtitle: 'Proximamente',
            onTap: () => onClose?.call(),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: _neutral400,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildModuleItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isSelected,
    required bool isEnabled,
    required VoidCallback? onTap,
  }) {
    final Color iconColor;
    final Color textColor;
    final Color subtitleColor;
    final Color iconBgColor;

    if (!isEnabled) {
      iconColor = _neutral300;
      textColor = _neutral300;
      subtitleColor = _neutral300.withValues(alpha: 0.5);
      iconBgColor = Colors.transparent;
    } else if (isSelected) {
      iconColor = AppColors.primary;
      textColor = AppColors.textPrimary;
      subtitleColor = AppColors.textSecondary;
      iconBgColor = AppColors.primary.withValues(alpha: 0.1);
    } else {
      iconColor = _neutral400;
      textColor = _neutral500;
      subtitleColor = _neutral400;
      iconBgColor = Colors.transparent;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: isEnabled ? 1.0 : 0.5,
            child: Container(
              decoration: BoxDecoration(
                color: isSelected ? _selectedBg : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: iconBgColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(icon, size: 20, color: iconColor),
                        if (!isEnabled)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: _neutral300,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFFF5F5F5),
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.lock_rounded,
                                size: 10,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: subtitleColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    )
                  else if (isEnabled)
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: _neutral400.withValues(alpha: 0.4),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: _neutral400),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _neutral500,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: _neutral400.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildFooterItem(
            icon: Icons.person_rounded,
            title: 'Mi perfil',
            onTap: () {
              onClose?.call();
              onProfileTap?.call();
            },
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            height: 1,
            color: AppColors.divider,
          ),
          _buildFooterItem(
            icon: Icons.logout_rounded,
            title: 'Cerrar sesion',
            color: const Color(0xFFEF4444),
            onTap: () {
              onClose?.call();
              onLogout?.call();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFooterItem({
    required IconData icon,
    required String title,
    Color? color,
    required VoidCallback onTap,
  }) {
    final itemColor = color ?? _neutral500;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: itemColor),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: itemColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
