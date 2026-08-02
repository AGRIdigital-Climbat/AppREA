import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/reporte_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../models/reporte_offline.dart';
import '../../widgets/module_shell.dart';
import '../../widgets/reporte_card.dart';
import '../../widgets/reporte_historial_tab.dart';
import '../reporte_form_screen.dart';
import '../reporte_detail_screen.dart';
import '../municipio_reportes_screen.dart';

class PreEdanScreen extends StatefulWidget {
  const PreEdanScreen({super.key});

  @override
  State<PreEdanScreen> createState() => _PreEdanScreenState();
}

class _PreEdanScreenState extends State<PreEdanScreen> with SingleTickerProviderStateMixin {
  bool _isSyncing = false;
  late AnimationController _syncAnimController;

  @override
  void initState() {
    super.initState();
    _syncAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void dispose() {
    _syncAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ModuleShell(
      moduleName: 'PRE EDAN',
      tabs: [
        ModuleTab(
          title: 'Inicio',
          icon: Icons.home_outlined,
          activeIcon: Icons.home,
          builder: (_) => _buildDashboardTab(),
          fab: FloatingActionButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReporteFormScreen()),
            ),
            backgroundColor: AppColors.primary,
            child: const Icon(Icons.add),
          ),
        ),
        ModuleTab(
          title: 'Historial',
          icon: Icons.list_outlined,
          activeIcon: Icons.list,
          builder: (_) => const ReportesHistorialTab(),
          fab: FloatingActionButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReporteFormScreen()),
            ),
            backgroundColor: AppColors.primary,
            child: const Icon(Icons.add),
          ),
        ),
        ModuleTab(
          title: 'Mapa',
          icon: Icons.location_city_outlined,
          activeIcon: Icons.location_city,
          builder: (_) => const MunicipioReportesTab(),
        ),
      ],
    );
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
                  'Responsable de reportar eventos adversos',
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

  Widget _buildStatCard(String value, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.15)),
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
            style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingSection(ReporteProvider reporte) {
    final pendingReports = reporte.reportes.where((r) => !r.sincronizado).toList();

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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                                  content: Text('Sincronización completada'),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                      MaterialPageRoute(builder: (_) => ReporteDetailScreen(reporte: r)),
                    );
                  },
                  onEdit: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ReporteFormScreen(reporte: r)),
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
                MaterialPageRoute(builder: (_) => ReporteDetailScreen(reporte: syncedReports.first)),
              );
            },
          ),
      ],
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
