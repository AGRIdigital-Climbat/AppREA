import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/modules.dart';
import '../config/theme.dart';
import '../providers/connectivity_provider.dart';
import '../widgets/perfil_tab.dart';

class HomeScreen extends StatelessWidget {
  final ModuleType currentModule;
  final bool showProfile;
  final VoidCallback? onMenuTap;
  final VoidCallback? onProfileTap;
  final VoidCallback? onLogout;

  const HomeScreen({
    super.key,
    required this.currentModule,
    required this.showProfile,
    this.onMenuTap,
    this.onProfileTap,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          onPressed: onMenuTap,
          icon: const Icon(Icons.menu_rounded, size: 24),
        ),
        title: Text(_getTitle()),
        actions: [
          Consumer<ConnectivityProvider>(
            builder: (context, connectivity, child) {
              final isOnline = connectivity.isConnected;
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isOnline ? AppColors.completed : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isOnline ? AppColors.completed : AppColors.error,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isOnline ? Icons.wifi : Icons.wifi_off,
                      size: 12,
                      color: isOnline ? Colors.white : AppColors.error,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isOnline ? 'En linea' : 'Sin conexion',
                      style: TextStyle(
                        fontSize: 11,
                        color: isOnline ? Colors.white : AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: showProfile
            ? PerfilTab(
                key: ValueKey('perfil_${currentModule.index}'),
                onLogout: onLogout,
              )
            : _buildModuleView(context),
      ),
    );
  }

  String _getTitle() {
    if (showProfile) return 'Mi perfil';
    final module = findModuleByType(currentModule);
    return module?.title ?? '';
  }

  Widget _buildModuleView(BuildContext context) {
    final module = findModuleByType(currentModule);
    if (module == null) return const SizedBox.shrink();
    return module.screenBuilder(context);
  }
}
