import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/reporte_provider.dart';
import '../providers/connectivity_provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../widgets/reporte_card.dart';
import '../widgets/app_drawer.dart';
import '../models/reporte_offline.dart';
import 'reporte_form_screen.dart';
import 'reporte_detail_screen.dart';
import 'municipio_reportes_screen.dart';
import 'edan_reportes_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
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
    return Consumer<AuthProvider>(
      builder: (context, auth, child) {
        final canAccessEDAN = auth.canAccessEDAN;

        final tabs = <Widget>[
          _buildDashboardTab(),
          _buildHistorialTab(),
          if (canAccessEDAN) const EdanReportesTab(),
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
            label: 'Inicio',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.list_outlined),
            activeIcon: Icon(Icons.list),
            label: 'Historial',
          ),
          if (canAccessEDAN)
            const BottomNavigationBarItem(
              icon: Icon(Icons.description_outlined),
              activeIcon: Icon(Icons.description),
              label: 'EDAN',
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

        return Scaffold(
          backgroundColor: AppColors.background,
          drawer: AppDrawer(
            userName: auth.userName ?? 'Usuario',
            roleName: auth.rolName ?? 'Responsable Local',
            canAccessEDAN: canAccessEDAN,
            onEDANTap: () {
              if (canAccessEDAN) {
                setState(() => _selectedIndex = 2);
              }
            },
            onLogout: () => _handleLogout(context),
          ),
          appBar: AppBar(
            leading: Builder(
              builder: (context) => IconButton(
                onPressed: () => Scaffold.of(context).openDrawer(),
                icon: const Icon(Icons.menu_rounded, size: 24),
              ),
            ),
            title: Text(_getTabTitle(canAccessEDAN)),
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
            type: BottomNavigationBarType.fixed,
            items: bottomNavItems,
          ),
        );
      },
    );
  }

  String _getTabTitle(bool canAccessEDAN) {
    switch (_selectedIndex) {
      case 0:
        return 'REA - Inicio';
      case 1:
        return 'REA - Historial';
      case 2:
        return canAccessEDAN ? 'EDAN - Reportes' : 'Municipio';
      case 3:
        return canAccessEDAN ? 'Municipio' : 'Perfil';
      case 4:
        return 'Perfil';
      default:
        return 'REA';
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesion'),
        content: const Text('Esta seguro que desea cerrar sesion?'),
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
      final nav = Navigator.of(context);
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
                const SizedBox(height: 80),
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

  Widget _buildHistorialTab() {
    return const ReportesHistorialTab();
  }

  Widget _buildPerfilTab() {
    return PerfilTab(
      key: _perfilTabKey,
      onEditingChanged: (editing) {
        setState(() => _isProfileEditing = editing);
      },
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

class ReportesHistorialTab extends StatefulWidget {
  const ReportesHistorialTab({super.key});

  @override
  State<ReportesHistorialTab> createState() => _ReportesHistorialTabState();
}

class _ReportesHistorialTabState extends State<ReportesHistorialTab> {
  String _filterStatus = 'all';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              _buildFilterChip('Todos', 'all'),
              const SizedBox(width: 8),
              _buildFilterChip('Pendientes', 'pending'),
              const SizedBox(width: 8),
              _buildFilterChip('Sincronizados', 'synced'),
            ],
          ),
        ),
        Expanded(
          child: Consumer<ReporteProvider>(
            builder: (context, reporteProvider, child) {
              if (reporteProvider.isLoading) {
                return const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.primary),
                );
              }

              var reportes = reporteProvider.reportes;

              if (_filterStatus == 'pending') {
                reportes =
                    reportes.where((r) => !r.sincronizado).toList();
              } else if (_filterStatus == 'synced') {
                reportes =
                    reportes.where((r) => r.sincronizado).toList();
              }

              if (reportes.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 80,
                        color: AppColors.textSecondary
                            .withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No hay reportes',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary
                              .withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _filterStatus == 'all'
                            ? 'Cree su primer reporte de evento adverso'
                            : 'No hay reportes con este filtro',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary
                              .withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  final result = await reporteProvider.refreshFromServer();
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
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(top: 8, bottom: 80),
                  itemCount: reportes.length,
                  itemBuilder: (context, index) {
                    final reporte = reportes[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ReporteCard(
                        reporte: reporte,
                        tipoEventoNombre: reporteProvider.getTipoEventoNombre(reporte.tipoEventoId),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ReporteDetailScreen(reporte: reporte),
                            ),
                          );
                        },
                        onEdit: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ReporteFormScreen(reporte: reporte),
                            ),
                          );
                        },
                        onDelete: () => _confirmDelete(context, reporte),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filterStatus == value;
    return Expanded(
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
        selected: isSelected,
        onSelected: (_) {
          setState(() {
            _filterStatus = value;
          });
        },
        selectedColor: AppColors.primary,
        backgroundColor: AppColors.surface,
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
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

class PerfilTab extends StatefulWidget {
  final ValueChanged<bool>? onEditingChanged;

  const PerfilTab({super.key, this.onEditingChanged});

  @override
  State<PerfilTab> createState() => PerfilTabState();
}

class PerfilTabState extends State<PerfilTab> {
  bool _isEditing = false;
  bool _isSaving = false;
  bool _isLoading = true;

  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _celularController = TextEditingController();
  final _comunidadController = TextEditingController();
  final _carnetController = TextEditingController();

  int? _selectedDepartamento;
  int? _selectedProvincia;
  int? _selectedMunicipio;
  String? _departamentoNombre;
  String? _provinciaNombre;
  String? _municipioNombre;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProfile();
    });
  }

  void resetEditing() {
    if (_isEditing) {
      _loadProfile();
      setState(() => _isEditing = false);
    }
  }

  void _loadProfile() {
    final profile = AuthService.instance.getSavedProfile();
    _nombreController.text = profile['nombre'] as String? ?? '';
    _celularController.text = profile['celular'] as String? ?? '';
    _comunidadController.text = profile['comunidad'] as String? ?? '';
    _carnetController.text = profile['carnet'] as String? ?? '';
    _selectedDepartamento = profile['id_departamento'] as int?;
    _selectedProvincia = profile['id_provincia'] as int?;
    _selectedMunicipio = profile['id_municipio'] as int?;
    _departamentoNombre = profile['departamento_nombre'] as String?;
    _provinciaNombre = profile['provincia_nombre'] as String?;
    _municipioNombre = profile['municipio_nombre'] as String?;

    if (_selectedDepartamento != null) {
      final rp = context.read<ReporteProvider>();
      rp.loadGeography();
      rp.loadProvincias(_selectedDepartamento!);
      if (_selectedProvincia != null) {
        rp.loadMunicipios(_selectedProvincia!, _selectedDepartamento!);
      }
    }
    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _celularController.dispose();
    _comunidadController.dispose();
    _carnetController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final rp = context.read<ReporteProvider>();

    String? depNombre;
    String? provNombre;
    String? munNombre;

    if (_selectedDepartamento != null) {
      final dep = rp.departamentos.where((d) => d.id == _selectedDepartamento);
      if (dep.isNotEmpty) depNombre = dep.first.nombre;
    }
    if (_selectedProvincia != null) {
      final prov = rp.provincias.where((p) => p.id == _selectedProvincia);
      if (prov.isNotEmpty) provNombre = prov.first.nombre;
    }
    if (_selectedMunicipio != null) {
      final mun = rp.municipios.where((m) => m.id == _selectedMunicipio);
      if (mun.isNotEmpty) munNombre = mun.first.nombre;
    }

    await AuthService.instance.saveProfileLocally({
      'nombre': _nombreController.text.trim(),
      'celular': _celularController.text.trim(),
      'carnet': _carnetController.text.trim(),
      'comunidad': _comunidadController.text.trim(),
      'id_departamento': _selectedDepartamento,
      'departamento_nombre': depNombre,
      'id_provincia': _selectedProvincia,
      'provincia_nombre': provNombre,
      'id_municipio': _selectedMunicipio,
      'municipio_nombre': munNombre,
    });

    final userId = AuthService.instance.userId;
    if (userId != null) {
      try {
        await ApiService.instance.updateUsuario(
          userId,
          nombre: _nombreController.text.trim(),
          celular: _celularController.text.trim(),
          comunidad: _comunidadController.text.trim(),
          idDepartamento: _selectedDepartamento,
          idProvincia: _selectedProvincia,
          idMunicipio: _selectedMunicipio,
        );
      } catch (_) {
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Perfil actualizado exitosamente'),
          backgroundColor: AppColors.completed,
        ),
      );
      _loadProfile();
      setState(() => _isEditing = false);
      widget.onEditingChanged?.call(false);
    }

    setState(() => _isSaving = false);
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesion'),
        content: const Text('Esta seguro que desea cerrar sesion?'),
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
      final nav = Navigator.of(context);
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
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: _isEditing ? _buildEditForm() : _buildProfileView(),
    );
  }

  Widget _buildProfileView() {
    final name = _nombreController.text;
    final initials = name.isNotEmpty
        ? name.split(' ').map((s) => s.isNotEmpty ? s[0] : '').take(2).join()
        : 'U';

    return Column(
      children: [
        CircleAvatar(
          radius: 48,
          backgroundColor: AppColors.primary,
          child: Text(
            initials.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          name,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 24),
        _buildInfoCard([
          _infoRow('Carnet de identidad', _carnetController.text),
          _infoRow('Celular', _celularController.text),
          _infoRow('Comunidad', _comunidadController.text),
          _infoRow('Departamento', _departamentoNombre),
          _infoRow('Provincia', _provinciaNombre),
          _infoRow('Municipio', _municipioNombre),
        ]),
        const SizedBox(height: 20),
        _buildOfflineDataButton(),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() => _isEditing = true);
              widget.onEditingChanged?.call(true);
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar perfil'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _handleLogout,
            icon: const Icon(Icons.logout, color: AppColors.error),
            label: const Text('Cerrar sesion',
                style: TextStyle(color: AppColors.error)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.error),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOfflineDataButton() {
    return Consumer<ReporteProvider>(
      builder: (context, rp, child) {
        final estadosCount = rp.estados.length;
        final categoriasCount = rp.categorias.length;
        final tiposCount = rp.tiposEvento.length;
        final hasData = estadosCount > 0 || categoriasCount > 0 || tiposCount > 0;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.download_for_offline, size: 20, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Cargar datos para uso offline',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              if (hasData) ...[
                const SizedBox(height: 8),
                Text(
                  '$estadosCount estados  ·  $tiposCount tipos  ·  $categoriasCount categorias',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Cargando catalogos...'),
                        backgroundColor: AppColors.inProgress,
                      ),
                    );
                    final result = await rp.fetchAndCacheCatalogs();
                    if (context.mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            '${result['estados']} estados, ${result['tipos']} tipos y ${result['categorias']} categorias cargados',
                          ),
                          backgroundColor: AppColors.completed,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('Actualizar catalogos'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoCard(List<Widget> rows) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: rows
            .map((row) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: row,
                ))
            .toList(),
      ),
    );
  }

  Widget _infoRow(String label, String? value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary.withValues(alpha: 0.8),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value?.isNotEmpty == true ? value! : '--',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Los cambios seran verificados.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 20),
          _buildSectionCard(
            'DATOS PERSONALES',
            [
              _buildTextField('Nombre completo', _nombreController, validator: (v) {
                if (v == null || v.isEmpty) return 'Ingrese su nombre';
                return null;
              }),
              const SizedBox(height: 12),
              _buildTextField('Celular', _celularController,
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              _buildTextField('Comunidad', _comunidadController),
            ],
          ),
          const SizedBox(height: 16),
          Consumer<ReporteProvider>(
            builder: (context, rp, child) {
              return _buildSectionCard(
                'UBICACION GEOGRAFICA',
                [
                  DropdownButtonFormField<int>(
                    initialValue: _selectedDepartamento,
                    decoration: _fieldDecoration('Departamento', rp.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null),
                    items: rp.departamentos
                        .map((dep) => DropdownMenuItem(
                            value: dep.id, child: Text(dep.nombre)))
                        .toList(),
                    onChanged: rp.isLoading
                        ? null
                        : (value) {
                            setState(() {
                              _selectedDepartamento = value;
                              _selectedProvincia = null;
                              _selectedMunicipio = null;
                            });
                            if (value != null) {
                              rp.loadProvincias(value);
                            }
                          },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _selectedProvincia,
                    decoration: _fieldDecoration('Provincia', rp.isLoadingProvincias
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null),
                    items: rp.provincias
                        .map((prov) => DropdownMenuItem(
                            value: prov.id, child: Text(prov.nombre)))
                        .toList(),
                    onChanged: _selectedDepartamento == null || rp.isLoadingProvincias
                        ? null
                        : (value) {
                            setState(() {
                              _selectedProvincia = value;
                              _selectedMunicipio = null;
                            });
                            if (value != null) {
                              rp.loadMunicipios(value, _selectedDepartamento!);
                            }
                          },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _selectedMunicipio,
                    decoration: _fieldDecoration('Municipio', rp.isLoadingMunicipios
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null),
                    items: rp.municipios
                        .map((mun) => DropdownMenuItem(
                            value: mun.id, child: Text(mun.nombre)))
                        .toList(),
                    onChanged: _selectedProvincia == null || rp.isLoadingMunicipios
                        ? null
                        : (value) {
                            setState(() {
                              _selectedMunicipio = value;
                            });
                          },
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            'IDENTIFICACION',
            [
              _buildTextField('Carnet de identidad', _carnetController, enabled: false),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _handleSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Guardar cambios'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    _loadProfile();
                    setState(() => _isEditing = false);
                    widget.onEditingChanged?.call(false);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.divider),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Cancelar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSectionCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          const Divider(height: 1, thickness: 1, color: AppColors.divider),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String label, Widget? suffixIcon) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFF7F8FA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      suffixIcon: suffixIcon,
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    bool enabled = true,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: enabled ? const Color(0xFFF7F8FA) : AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}
