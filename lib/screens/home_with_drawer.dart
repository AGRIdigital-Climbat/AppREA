import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/modules.dart';
import '../providers/auth_provider.dart';
import '../providers/reporte_provider.dart';
import '../providers/connectivity_provider.dart';
import '../services/sync_manager.dart';
import '../widgets/app_drawer.dart';
import '../widgets/slide_drawer.dart';
import 'login_screen.dart';
import 'home_screen.dart';

class HomeWithDrawer extends StatefulWidget {
  const HomeWithDrawer({super.key});

  @override
  State<HomeWithDrawer> createState() => _HomeWithDrawerState();
}

class _HomeWithDrawerState extends State<HomeWithDrawer>
    with SingleTickerProviderStateMixin {
  late final SlideDrawerController _drawerController;
  ModuleType _currentModule = ModuleType.preEdan;
  bool _showProfile = false;

  @override
  void initState() {
    super.initState();
    _drawerController = SlideDrawerController(vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReporteProvider>().initialize();
      context.read<ConnectivityProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _drawerController.dispose();
    super.dispose();
  }

  void _selectModule(ModuleType module) {
    final auth = context.read<AuthProvider>();
    if (!_canAccess(module, auth)) return;
    setState(() {
      _currentModule = module;
      _showProfile = false;
    });
  }

  void _showProfileView() {
    setState(() {
      _showProfile = true;
    });
  }

  bool _canAccess(ModuleType type, AuthProvider auth) {
    switch (type) {
      case ModuleType.preEdan: return auth.canAccessPreEdan;
      case ModuleType.edan: return auth.canAccessEdan;
      case ModuleType.rida: return auth.canAccessRida;
      case ModuleType.sinb: return auth.canAccessSinb;
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesion'),
        content: const Text(
          'Esta seguro que desea cerrar sesion?\n\n'
          'Se eliminaran todos los datos locales del dispositivo '
          '(reportes, borradores, imagenes y catalogos).\n'
          'Al iniciar sesion nuevamente se recuperara toda la informacion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cerrar sesion'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final auth = context.read<AuthProvider>();
      final reporte = context.read<ReporteProvider>();
      final nav = Navigator.of(context);
      reporte.clearData();
      SyncManager.instance.reset();
      await auth.logout();
      if (mounted) {
        nav.pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, child) {
        return SlideDrawer(
          controller: _drawerController,
          menuContent: AppDrawer(
            userName: auth.userName ?? 'Usuario',
            currentModule: _currentModule,
            isModuleEnabled: (type) => _canAccess(type, auth),
            onModuleTap: _selectModule,
            onClose: _drawerController.close,
            onProfileTap: _showProfileView,
            onLogout: _handleLogout,
          ),
          mainContent: HomeScreen(
            currentModule: _currentModule,
            showProfile: _showProfile,
            onMenuTap: _drawerController.toggle,
            onLogout: _handleLogout,
          ),
        );
      },
    );
  }
}
