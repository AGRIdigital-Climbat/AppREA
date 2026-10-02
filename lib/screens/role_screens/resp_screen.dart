import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/edan.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/reporte_provider.dart';
import '../../services/connectivity_service.dart';
import '../../services/edan/edan_sync_respo_service.dart';
import '../../services/sync_debug_config.dart';
import '../../screens/sync_debug_screen.dart';
import '../../widgets/perfil_tab.dart';
import '../../widgets/asistente_ia.dart';
import 'resp/resp_dashboard_tab.dart';
import 'resp/edan/edan_ia_elegir_creacion.dart';
import 'resp/edan/edan_form_wizard.dart';
import 'resp/resp_edan_localidad_tab.dart';
import 'resp/resp_guia_tab.dart';
import 'resp/resp_mapa_tab.dart';
import 'ugr/ugr_route.dart';

class RespScreen extends StatefulWidget {
  const RespScreen({super.key});

  @override
  State<RespScreen> createState() => _RespScreenState();
}

class _RespScreenState extends State<RespScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  bool _wasOnline = true;
  ConnectivityProvider? _connectivity;
  final _dashboardTabKey = GlobalKey<RespDashboardTabState>();
  final _edanTabKey = GlobalKey<RespEdanLocalidadTabState>();
  final _mapaTabKey = GlobalKey<RespMapaTabState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final connectivity = context.read<ConnectivityProvider>();
      _connectivity = connectivity;
      // Si el primer chequeo de red sigue en curso, asumimos "offline" como
      // punto de partida: es lo que garantiza que la transicion a online
      // dispare la sincronizacion, en vez de poder perderse.
      _wasOnline = connectivity.chequeoCompletado && connectivity.isConnected;
      connectivity.addListener(_onConnectivityChanged);
      EdanSyncRespoService.instance.recargarPendientes();
      context.read<ReporteProvider>().initializeResp();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivity?.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      EdanSyncRespoService.instance.recargarPendientes();
    }
  }

  void _onConnectivityChanged() {
    final online = _connectivity?.isConnected ?? true;
    if (online && !_wasOnline) {
      _sincronizar(auto: true);
    }
    _wasOnline = online;
    EdanSyncRespoService.instance.recargarPendientes();
  }

  @override
  Widget build(BuildContext context) {
    const palette = Palettes.rea;
    return PaletteScope(
      palette: palette,
      child: Theme(
        data: AppTheme.buildTheme(palette),
        child: Consumer<ReporteProvider>(
          builder: (context, rp, _) {
            if (rp.isInitializing) {
              return _buildDownloadOverlay(palette, rp.downloadPhase);
            }
            return _buildMainContent(palette);
          },
        ),
      ),
    );
  }

  Widget _buildDownloadOverlay(ToolPalette palette, String phase) {
    return Scaffold(
      backgroundColor: palette.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/SINAGER.png',
              width: 100,
              height: 100,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 32),
            Text(
              'SINAGER-SAT',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: palette.primary,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'EDAN',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: palette.primary.withValues(alpha: 0.7),
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 40),
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 24),
            Text(
              phase.isNotEmpty ? phase : 'Inicializando...',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(ToolPalette palette) {
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: Text(_getTabTitle()),
        centerTitle: false,
        actions: [
          if (kSyncDebugMode)
            IconButton(
              tooltip: 'Depuración Sync',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SyncDebugScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.bug_report_outlined, size: 20),
            ),
          _buildSyncButton(),
          Consumer<ConnectivityProvider>(
            builder: (context, connectivity, child) {
              final isOnline = connectivity.isConnected;
              return Container(
                margin: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 8,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
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
          children: [
            RespDashboardTab(
              key: _dashboardTabKey,
              onVerEnReportes: _verEnReportes,
              onSync: () => _sincronizar(auto: false),
            ),
            RespEdanLocalidadTab(key: _edanTabKey),
            RespMapaTab(key: _mapaTabKey),
            const RespGuiaTab(),
            const PerfilTab(catalogoEdan: true),
          ],
        ),
      ),
      floatingActionButton: _buildFabs(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
          switch (index) {
            case 0:
              _dashboardTabKey.currentState?.refresh();
            case 1:
              _edanTabKey.currentState?.refresh();
            case 2:
              _mapaTabKey.currentState?.refresh();
          }
          EdanSyncRespoService.instance.recargarPendientes();
        },
        selectedItemColor: palette.primary,
        unselectedItemColor: AppColors.textSecondary,
        backgroundColor: AppColors.surface,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assessment_outlined),
            activeIcon: Icon(Icons.assessment),
            label: 'Reportes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Mapa',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book_outlined),
            activeIcon: Icon(Icons.menu_book),
            label: 'Guía',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }

  Widget _buildSyncButton() {
    return ListenableBuilder(
      listenable: Listenable.merge([
        EdanSyncRespoService.instance.pendientes,
        EdanSyncRespoService.instance.sincronizando,
        ?_connectivity,
      ]),
      builder: (context, _) {
        final pendientes = EdanSyncRespoService.instance.pendientes.value;
        final sincronizando = EdanSyncRespoService.instance.sincronizando.value;
        // Sin conexion verificada el boton se apaga en vez de dejar que el
        // usuario lo presione y se le muestre un error. Sin esta distincion
        // habia dos ventanas (13 s al arrancar, 45 s de histeresis) en las que
        // la app creia tener red y cada request fallaba.
        final online = _connectivity?.isConnected ?? false;
        final chequeado = _connectivity?.chequeoCompletado ?? false;
        final puedeIntentar = online && chequeado && !sincronizando;
        return IconButton(
          tooltip: sincronizando
              ? 'Sincronizando...'
              : !puedeIntentar
                  ? 'Sin conexión. Se sincronizará automáticamente al recuperar la red.'
                  : pendientes > 0
                      ? 'Sincronizar ($pendientes pendientes)'
                      : 'Sincronizar',
          onPressed: puedeIntentar ? () => _sincronizar(auto: false) : null,
          icon: Badge(
            isLabelVisible: pendientes > 0 && !sincronizando,
            label: Text('$pendientes'),
            child: sincronizando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    puedeIntentar
                        ? Icons.cloud_upload_outlined
                        : Icons.cloud_off_outlined,
                  ),
          ),
        );
      },
    );
  }

  Future<void> _sincronizar({bool auto = false}) async {
    if (EdanSyncRespoService.instance.isSyncing) return;

    // Chequeo real antes de cualquier trabajo de red. El estado cacheado puede
    // tener hasta 45 s de retraso por la histeresis: sin esto, un estado viejo
    // "online" lanza una corrida completa que va a fallar y a pintar un error.
    final online = await ConnectivityService().checkNow();
    if (!mounted) return;
    if (!online) {
      // Sin conexion no es un error: no se perdio nada, esta todo en SQLite, y
      // el reenvio automatico se dispara solo al volver la red. El chip de la
      // AppBar ya informa del estado, asi que un snackbar aqui seria ruido.
      return;
    }

    final result = await EdanSyncRespoService.instance.sincronizar();
    if (!mounted) return;

    _dashboardTabKey.currentState?.refresh();
    _edanTabKey.currentState?.refresh();
    EdanSyncRespoService.instance.recargarPendientes();

    if (auto &&
        (result.enviados == 0 &&
            result.fallidos == 0 &&
            result.eliminados == 0)) {
      return;
    }

    // Rojo solo cuando hubo red verificada y el servidor rechazo el dato, o
    // cuando el fallo no se puede atribuir a la red. Un fallo de transporte
    // aqui significa que se cayo la red durante la corrida: no hay nada que el
    // usuario pueda hacer, asi que no se molesta con un error.
    if (result.sinConexion) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.resumen),
        backgroundColor: result.exito ? AppColors.aprobado : AppColors.rechazado,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _verEnReportes(UgrLocalidadEstado? estado) {
    setState(() => _selectedIndex = 1);
    _edanTabKey.currentState?.aplicarFiltro(estado);
  }

  Widget _buildFabs() {
    final reporte = _buildReporteFab();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AsistenteIaFab(),
        if (reporte != null) ...[
          const SizedBox(height: 12),
          reporte,
        ],
      ],
    );
  }

  Widget? _buildReporteFab() {
    switch (_selectedIndex) {
      case 0:
      case 1:
        // Inicio y Reportes: el `+` abre directo el wizard EDAN.
        return FloatingActionButton(
          onPressed: () => _abrirWizardDirecto(),
          tooltip: 'Nuevo reporte',
          backgroundColor: PaletteScope.of(context).primary,
          child: const Icon(Icons.add, color: Colors.white),
        );
      default:
        return null;
    }
  }

  /// Abre el wizard EDAN directo, sin pasar por el diálogo de elección.
  /// El código del asistente con IA se conserva pero no se expone desde el FAB.
  Future<void> _abrirWizardDirecto() async {
    final creado = await Navigator.of(context).push<bool>(
      ugrRoute(const EdanFormWizard(), palette: Palettes.rea),
    );
    if (creado != true || !mounted) return;

    _dashboardTabKey.currentState?.refresh();
    _edanTabKey.currentState?.refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reporte guardado correctamente.'),
        backgroundColor: AppColors.completed,
      ),
    );
  }

  /// Abre el diálogo de creación y, según el modo elegido, el wizard o el
  /// asistente con IA. Solo refresca si la ficha quedó guardada.
  ///
  /// **MÉTODO DESACTIVADO**: el FAB ahora llama a `_abrirWizardDirecto`.
  /// Este método se conserva para reactivar el asistente cuando el modelo
  /// esté estable.
  @visibleForTesting
  Future<void> _crearFicha(int tabActual) async {
    final modo = await pedirModoCreacionEdan(context);
    if (modo == null || !mounted) return;

    final exito = await abrirCreacionEdan(context, modo);
    if (!exito || !mounted) return;

    _dashboardTabKey.currentState?.refresh();
    _edanTabKey.currentState?.refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reporte guardado correctamente.'),
        backgroundColor: AppColors.completed,
      ),
    );
  }

  String _getTabTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Inicio';
      case 1:
        return 'Reportes';
      case 2:
        return 'Mapa';
      case 3:
        return 'Guía';
      case 4:
        return 'Perfil';
      default:
        return 'Inicio';
    }
  }
}
