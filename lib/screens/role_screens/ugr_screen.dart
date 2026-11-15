import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/reporte_provider.dart';
import '../../services/api/edan_api_v2.dart';
import '../../services/edan/edan_store_v2.dart';
import '../../services/sync/edan_sync_engine_v2.dart';
import '../../services/auth_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/sync_debug_config.dart';
import '../../screens/app_debug_screen.dart';
import '../../models/edan.dart';
import '../../widgets/asistente_ia.dart';
import '../../widgets/perfil_tab.dart';
import '../../widgets/ugr_progress_franja.dart';
import 'ugr/ugr_edan_tab.dart';
import 'ugr/ugr_guia_tab.dart';
import 'ugr/ugr_localidades_tab.dart';
import 'ugr/ugr_route.dart';
import 'resp/edan/edan_form_wizard.dart';
import 'resp/resp_mapa_tab.dart';
import '../../services/app_logger_ui.dart';

class UgrScreen extends StatefulWidget {
  const UgrScreen({super.key});

  @override
  State<UgrScreen> createState() => _UgrScreenState();
}

class _UgrScreenState extends State<UgrScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  bool _isProfileEditing = false;
  bool _wasOnline = true;
  ConnectivityProvider? _connectivity;
  /// Evita apilar auto-syncs si la red parpadea
  /// (offline→online→offline→online seguidos).
  bool _sincronizandoAuto = false;
  /// Temporizador de auto-sync por cambios pendientes (debounce).
  Timer? _autoSyncTimer;
  /// Evita apilar descargas del municipio para el mapa (una a la vez).
  bool _descargaMapaMunicipio = false;
  final _edanTabKey = GlobalKey<UgrEdanTabState>();
  final _perfilTabKey = GlobalKey<PerfilTabState>();
  final _localidadesTabKey = GlobalKey<UgrLocalidadesTabState>();
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
      EdanStoreV2.instance.refrescarPendientes();
      EdanStoreV2.instance.pendientesNotifier.addListener(_onPendientesChanged);
      context.read<ReporteProvider>().initializeUgr();
    });
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    EdanStoreV2.instance.pendientesNotifier.removeListener(_onPendientesChanged);
    WidgetsBinding.instance.removeObserver(this);
    _connectivity?.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      EdanStoreV2.instance.refrescarPendientes();
      unawaited(_sincronizarSiHayPendientes());
    }
  }

  void _onConnectivityChanged() {
    final online = _connectivity?.isConnected ?? true;
    final volvio = online && !_wasOnline;
    _wasOnline = online;
    EdanStoreV2.instance.refrescarPendientes();
    if (volvio) {
      // Al volver internet se auto-sincroniza sin diálogo (igual que RESP):
      // solo si hay pendientes y sin sync en curso.
      unawaited(_sincronizarSiHayPendientes());
    }
  }

  /// Auto-sync al reconectar: corre `_sincronizar(auto: true)` solo con
  /// trabajo pendiente y sin corrida en curso. Nunca apila llamadas (mismo
  /// guard `_sincronizandoAuto` que RESP).
  Future<void> _sincronizarSiHayPendientes() async {
    if (!mounted) return;
    if (_sincronizandoAuto) return;
    await EdanStoreV2.instance.refrescarPendientes();
    if (!mounted) return;
    if (EdanStoreV2.instance.sincronizandoNotifier.value) return;
    if (EdanStoreV2.instance.pendientesNotifier.value <= 0) return;
    _sincronizandoAuto = true;
    try {
      await _sincronizar(auto: true);
    } finally {
      _sincronizandoAuto = false;
    }
  }

  void _onPendientesChanged() {
    if (!mounted) return;
    if (EdanStoreV2.instance.pendientesNotifier.value <= 0) {
      _autoSyncTimer?.cancel();
      _autoSyncTimer = null;
      return;
    }
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      unawaited(_sincronizarSiHayPendientes());
    });
  }

  @override
  Widget build(BuildContext context) {
    const palette = Palettes.edan;
    return PaletteScope(
      palette: palette,
      child: Theme(
        data: AppTheme.buildTheme(palette),
        child: Consumer<ReporteProvider>(
          builder: (context, rp, _) {
            if (rp.isInitializing) {
              return _buildDownloadOverlay(palette, rp.downloadPhase);
            }
            return _buildMainContent(palette, rp);
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
              'assets/images/LOGO_VIDECI_1024.png',
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

  Widget _buildMainContent(ToolPalette palette, ReporteProvider rp) {
    return Scaffold(
          backgroundColor: palette.background,
          appBar: AppBar(
            title: Text(_getTabTitle()),
            centerTitle: false,
            actions: [
              if (kSyncDebugMode)
                IconButton(
                  tooltip: 'Debug · Registro de la app (24 h)',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AppDebugScreen(),
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
          body: Column(
            children: [
              // Una sola franja bajo el AppBar (empuja, no tapa): histórico del
              // municipio → motor V2 (primera descarga/reportes propios y sync)
              // → catálogos. Sin actividad no pinta.
              UgrProgressFranja(rp: rp),
              Expanded(
                child: SafeArea(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: [
                      UgrLocalidadesTab(
                        key: _localidadesTabKey,
                        onVistaChanged: () => setState(() {}),
                        onConsolidado: () =>
                            _edanTabKey.currentState?.refresh(),
                        onNavigateToEdan: () =>
                            setState(() => _selectedIndex = 1),
                      ),
                      UgrEdanTab(key: _edanTabKey),
                      RespMapaTab(
                        key: _mapaTabKey,
                        // Offline-first: el mapa lee SQLite (`formularios`),
                        // no la red. Pinta ya con lo local; con red, dispara
                        // en segundo plano `descargarMunicipio` (V2: docs de
                        // `GET /formularios` paginados por municipio), que
                        // escribe `id_municipio` y las secciones con
                        // coordenadas de TODOS los usuarios del municipio
                        // (scope rol 6), y repinta una sola vez al terminar.
                        cargarLocalidades: () async {
                          final token = AuthService.instance.currentToken;
                          final municipio = token?.idMunicipio;
                          if (municipio == null) return <EdanLocalidad>[];
                          unawaited(_refrescarMapaMunicipio(municipio));
                          return EdanStoreV2.instance.listarFormularios(
                            idMunicipio: municipio,
                          );
                        },
                      ),
                      const UgrGuiaTab(),
                      PerfilTab(key: _perfilTabKey, catalogoEdan: true),
                    ],
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: _buildFab(),
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
                switch (index) {
                  case 0:
                    _localidadesTabKey.currentState?.refresh();
                  case 1:
                    _edanTabKey.currentState?.refresh();
                  case 2:
                    _mapaTabKey.currentState?.refresh();
                }
                EdanStoreV2.instance.refrescarPendientes();
              },
              selectedItemColor: palette.primary,
              unselectedItemColor: AppColors.textSecondary,
              backgroundColor: AppColors.surface,
              type: BottomNavigationBarType.fixed,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.location_on_outlined),
                  activeIcon: Icon(Icons.location_on),
                  label: 'Localidades',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.assessment_outlined),
                  activeIcon: Icon(Icons.assessment),
                  label: 'EDAN',
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

  /// Descarga el municipio entero por V2 (`GET /formularios?id_municipio`
  /// paginado con `modo=completo`, aplicando solo los nuevos/modificados) y
  /// repinta el mapa al terminar. Best-effort: cualquier fallo deja el mapa
  /// con lo local (offline-first intacto); el motor y este guard impiden dos
  /// descargas a la vez.
  Future<void> _refrescarMapaMunicipio(int municipio) async {
    if (_descargaMapaMunicipio) return;
    if (!ConnectivityService().isConnected) return;
    _descargaMapaMunicipio = true;
    try {
      final res = await EdanSyncEngineV2(
        api: EdanApiV2(),
        usuarioId: AuthService.instance.userId,
      ).descargarMunicipio(municipio);
      if (!mounted) return;
      if (res.descargados > 0) {
        _mapaTabKey.currentState?.refresh();
      }
    } catch (_) {
      // Best-effort: el mapa sigue con lo local.
    } finally {
      _descargaMapaMunicipio = false;
    }
  }

  Widget _buildSyncButton() {
    return ListenableBuilder(
      listenable: Listenable.merge([
        EdanStoreV2.instance.pendientesNotifier,
        EdanStoreV2.instance.sincronizandoNotifier,
        ?_connectivity,
      ]),
      builder: (context, _) {
        final pendientes = EdanStoreV2.instance.pendientesNotifier.value;
        final sincronizando = EdanStoreV2.instance.sincronizandoNotifier.value;
        // Sin conexion verificada el boton se apaga en vez de dejar que el
        // usuario lo presione y se le muestre un error. Sin esta distincion
        // habia dos ventanas (13 s al arrancar, 45 s de histeresis) en las que
        // la app creia tener red y cada request fallaba.
        final online = _connectivity?.isConnected ?? false;
        final chequeado = _connectivity?.chequeoCompletado ?? false;
        final verificando = !chequeado;
        final puedeIntentar = online && chequeado && !sincronizando;
        return IconButton(
          tooltip: sincronizando
              ? 'Sincronizando...'
              : verificando
                  ? 'Verificando conexión...'
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
                    verificando
                        ? Icons.cloud_queue_outlined
                        : puedeIntentar
                            ? Icons.cloud_upload_outlined
                            : Icons.cloud_off_outlined,
                  ),
          ),
        );
      },
    );
  }

  Future<void> _sincronizar({bool auto = false}) async {
    final store = EdanStoreV2.instance;
    if (store.sincronizandoNotifier.value) return;

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

    store.sincronizandoNotifier.value = true;
    EdanSyncResumen result;
    try {
      // Carpeta de fotos: la usamos para la recuperación en un dispositivo
      // nuevo (el motor descarga a `ruta_local` las fotos que el pull trajo
      // solo con metadatos). Única carpeta: `report_photos/` (igual que RESP).
      Directory? dirFotos;
      try {
        final appDir = await getApplicationDocumentsDirectory();
        dirFotos = Directory('${appDir.path}/report_photos');
        await dirFotos.create(recursive: true);
      } catch (_) {
        dirFotos = null;
      }
      result = await EdanSyncEngineV2(
        api: EdanApiV2(),
        dirFotos: dirFotos,
        usuarioId: AuthService.instance.userId,
      ).sincronizar();
    } catch (e) {
      // El motor captura casi todo, pero un fallo inesperado (bug local) no
      // debe dejar la UI colgada sin mensaje ni refresco (igual que RESP).
      result = EdanSyncResumen(
        exito: false,
        ultimoError: 'Error inesperado: $e',
      );
    } finally {
      store.sincronizandoNotifier.value = false;
    }
    if (!mounted) return;

    _localidadesTabKey.currentState?.refresh();
    _edanTabKey.currentState?.refresh();
    _mapaTabKey.currentState?.refresh();
    store.refrescarPendientes();

    if (auto &&
        result.enviados == 0 &&
        result.errores == 0 &&
        result.fotosSubidas == 0 &&
        result.fotosDescargadas == 0) {
      return;
    }

    // El motor marca `ultimoError` con prefijo 'Sin conexión' cuando hubo un
    // SocketException (cayó la red durante la corrida). No se pinta rojo.
    if (result.ultimoError != null &&
        result.ultimoError!.startsWith('Sin conexión')) {
      return;
    }

    final partes = <String>[
      if (result.enviados > 0) '${result.enviados} enviados',
      if (result.errores > 0) '${result.errores} errores',
      if (result.fotosSubidas > 0) '${result.fotosSubidas} fotos subidas',
      if (result.fotosDescargadas > 0)
        '${result.fotosDescargadas} fotos descargadas',
      if (result.fotosPendientes > 0)
        '${result.fotosPendientes} fotos pendientes',
    ];
    final mensaje = partes.isEmpty
        ? (result.exito ? 'Sin cambios por enviar.' : 'La sincronización falló.')
        : partes.join(' · ');

    showAppSnackBar(context, 
      SnackBar(
        content: Text(
          result.exito
              ? mensaje
              : '$mensaje${result.ultimoError != null ? ' — ${result.ultimoError}' : ''}',
        ),
        backgroundColor: result.exito ? AppColors.aprobado : AppColors.rechazado,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Widget? _buildFab() {
    final palette = PaletteScope.of(context);
    final primary = palette.primary;
    final specificFab = _buildTabFab(primary);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AsistenteIaFab(fabColor: primary),
        if (specificFab != null) ...[
          const SizedBox(height: 12),
          specificFab,
        ],
      ],
    );
  }

  Widget? _buildTabFab(Color primary) {
    switch (_selectedIndex) {
      case 0:
        final tab = _localidadesTabKey.currentState;
        // En la vista Galería del tab Localidades no procede crear ni
        // consolidar: se ocultan ambos FAB (el bug de heroTag ya resuelto).
        if (tab?.vistaGaleria ?? false) return null;
        // En modo consolidación el control es la barra de checks (Cancelar /
        // Vista previa): ocultar el FAB de crear evita ambigüedad.
        if (tab?.modoConsolidacion ?? false) return null;
        final consolidarVisible = tab != null && tab.mostrarFabConsolidar;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (consolidarVisible) ...[
              FloatingActionButton(
                onPressed: () => tab.activarConsolidacion(),
                tooltip: 'Consolidar',
                backgroundColor: primary,
                foregroundColor: Colors.white,
                heroTag: 'fab_consolidar',
                child: const Icon(Icons.layers),
              ),
              const SizedBox(height: 12),
            ],
            FloatingActionButton(
              onPressed: _abrirWizardDirecto,
              tooltip: 'Crear EDAN localidad',
              backgroundColor: primary,
              foregroundColor: Colors.white,
              heroTag: 'fab_crear',
              child: const Icon(Icons.add),
            ),
          ],
        );
      case 1:
        return null;
      case 2:
        return null;
      default:
        return null;
    }
  }

  /// Abre el wizard EDAN directo, igual que el FAB de RESP (sin diálogo de
  /// modo). La ficha nueva queda como **borrador en SQLite** (`EdanStoreV2`),
  /// pendiente de sincronizar; consolidar/enviar a UGR es un paso aparte.
  Future<void> _abrirWizardDirecto() async {
    final creado = await Navigator.of(context).push<bool>(
      ugrRoute(
        EdanFormWizard(storeV2: EdanStoreV2.instance),
        palette: Palettes.rea,
      ),
    );
    if (creado != true || !mounted) return;
    _localidadesTabKey.currentState?.refresh();
    _edanTabKey.currentState?.refresh();
  }

  String _getTabTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Localidades';
      case 1:
        return 'EDAN';
      case 2:
        return 'Mapa';
      case 3:
        return 'Guía';
      case 4:
        return 'Perfil';
      default:
        return 'Localidades';
    }
  }
}
