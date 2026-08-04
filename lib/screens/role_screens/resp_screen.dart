import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/reporte_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../services/sync_manager.dart';
import '../../models/reporte_offline.dart';
import '../../widgets/perfil_tab.dart';
import '../../widgets/reporte_card.dart';
import '../../widgets/reporte_historial_tab.dart';
import '../login_screen.dart';
import '../municipio_reportes_screen.dart';
import '../reporte_detail_screen.dart';
import '../reporte_form_screen.dart';

class RespScreen extends StatefulWidget {
  const RespScreen({super.key});

  @override
  State<RespScreen> createState() => _RespScreenState();
}

class _RespScreenState extends State<RespScreen> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  bool _isProfileEditing = false;
  bool _isSyncing = false;
  final _perfilTabKey = GlobalKey<PerfilTabState>();
  late AnimationController _syncAnimController;

  @override
  void initState() {
    super.initState();
    _syncAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReporteProvider>().initialize();
      context.read<ConnectivityProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _syncAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      _buildDashboardTab(),
      const ReportesHistorialTab(),
      const MunicipioReportesTab(),
      _buildPerfilTab(),
    ];

    if (_selectedIndex >= tabs.length) {
      _selectedIndex = 0;
    }

    final bottomNavItems = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(
        icon: Icon(Icons.home_outlined),
        activeIcon: Icon(Icons.home),
        label: 'Reportes',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.list_outlined),
        activeIcon: Icon(Icons.list),
        label: 'Historial',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.location_city_outlined),
        activeIcon: Icon(Icons.location_city),
        label: 'Municipio',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.person_outlined),
        activeIcon: Icon(Icons.person),
        label: 'Perfil',
      ),
    ];

    return PaletteScope(
      palette: Palettes.rea,
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_getTabTitle()),
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
        child: IndexedStack(
          index: _selectedIndex,
          children: tabs,
        ),
      ),
      floatingActionButton: (_selectedIndex == 0 || _selectedIndex == 1)
          ? FloatingActionButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ReporteFormScreen(),
                  ),
                );
              },
              tooltip: 'Nuevo reporte',
              backgroundColor: PaletteScope.of(context).primary,
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
            if (_isProfileEditing) {
              _isProfileEditing = false;
              _perfilTabKey.currentState?.resetEditing();
            }
          });
        },
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        backgroundColor: AppColors.surface,
        type: BottomNavigationBarType.fixed,
        items: bottomNavItems,
      ),
      ),
    );
  }

  String _getTabTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Reportes';
      case 1:
        return 'Historial';
      case 2:
        return 'Municipio';
      case 3:
        return 'Perfil';
      default:
        return 'Reportes';
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

  Widget _buildDashboardTab() {
    return Consumer2<AuthProvider, ReporteProvider>(
      builder: (context, auth, reporte, child) {
        return RefreshIndicator(
          onRefresh: () async {
            final result = await reporte.refreshFromServer();
            if (context.mounted) {
              if (result == -1) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Error al consultar el servidor'),
                    backgroundColor: Colors.red,
                  ),
                );
              } else if (result > 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$result reporte(s) actualizado(s)'),
                    backgroundColor: AppColors.primary,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Reportes sin cambios'),
                    backgroundColor: AppColors.textSecondary,
                  ),
                );
              }
            }
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWelcomeHeader(auth),
                const SizedBox(height: 20),
                _buildStatsRow(reporte),
                const SizedBox(height: 20),
                _buildPendingSection(reporte),
                const SizedBox(height: 20),
                _buildLastReportSection(reporte),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWelcomeHeader(AuthProvider auth) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/images/SINAGER.png',
            width: 62,
            height: 62,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bienvenido,',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                Text(
                  auth.userName ?? 'Usuario',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  auth.rolName ?? 'Responsable Local',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(ReporteProvider reporte) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            reporte.reportes.length.toString(),
            'Total',
            Icons.assessment,
            AppColors.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            reporte.pendingCount.toString(),
            'Pendientes',
            Icons.pending_actions,
            AppColors.enviado,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            (reporte.reportes.length - reporte.pendingCount).toString(),
            'Sincronizados',
            Icons.cloud_done,
            AppColors.aprobado,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String value,
    String label,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingSection(ReporteProvider reporte) {
    final pendingReports =
        reporte.reportes.where((r) => !r.sincronizado).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Reportes Pendientes',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            Consumer<ConnectivityProvider>(
              builder: (context, connectivity, child) {
                if (pendingReports.isEmpty || !connectivity.isConnected) {
                  return const SizedBox.shrink();
                }
                return _isSyncing
                    ? ElevatedButton.icon(
                        onPressed: null,
                        icon: RotationTransition(
                          turns: _syncAnimController,
                          child: const Icon(Icons.sync, size: 16),
                        ),
                        label: const Text('Sincronizando...'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          textStyle: const TextStyle(fontSize: 13),
                          backgroundColor: AppColors.primary.withValues(alpha: 0.6),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.6),
                          disabledForegroundColor: Colors.white70,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: () async {
                          setState(() => _isSyncing = true);
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await reporte.sincronizarPendientes();
                            if (mounted) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Sincronizacion completada'),
                                  backgroundColor: AppColors.completed,
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('Error al sincronizar: $e'),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _isSyncing = false);
                          }
                        },
                        icon: const Icon(Icons.sync, size: 16),
                        label: Text('Sincronizar (${pendingReports.length})'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          textStyle: const TextStyle(fontSize: 13),
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (pendingReports.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.cloud_done,
                  size: 48,
                  color: AppColors.completed.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'Todos los reportes sincronizados',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          )
        else
          ...pendingReports.take(3).map(
                (r) => ReporteCard(
                  reporte: r,
                  tipoEventoNombre: reporte.getTipoEventoNombre(r.tipoEventoId),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ReporteDetailScreen(reporte: r),
                      ),
                    );
                  },
                  onEdit: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ReporteFormScreen(reporte: r),
                      ),
                    );
                  },
                  onDelete: () => _confirmDelete(context, r),
                ),
              ),
      ],
    );
  }

  Widget _buildLastReportSection(ReporteProvider reporte) {
    final syncedReports = reporte.reportes
        .where((r) => r.sincronizado)
        .toList()
      ..sort((a, b) => b.fechaCreacion.compareTo(a.fechaCreacion));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ultimo Reporte Sincronizado',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        if (syncedReports.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 48,
                  color: AppColors.textSecondary.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 12),
                Text(
                  'Aun no hay reportes sincronizados',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          )
        else
          ReporteCard(
            reporte: syncedReports.first,
            tipoEventoNombre: reporte.getTipoEventoNombre(syncedReports.first.tipoEventoId),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ReporteDetailScreen(reporte: syncedReports.first),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildPerfilTab() {
    return PerfilTab(
      key: _perfilTabKey,
      onLogout: _handleLogout,
    );
  }

  void _confirmDelete(BuildContext context, ReporteOffline reporte) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Reporte'),
        content: const Text('¿Está seguro de eliminar este reporte?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<ReporteProvider>().eliminarReporte(reporte.idLocal!);
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}
