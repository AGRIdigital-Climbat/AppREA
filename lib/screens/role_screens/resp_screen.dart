import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/reporte_provider.dart';
import '../../services/auth_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/api/edan_api_v2.dart';
import '../../services/edan/edan_store_v2.dart';
import '../../services/sync/edan_sync_engine_v2.dart';
import '../../services/sync_debug_config.dart';
import '../../screens/app_debug_screen.dart';
import '../../widgets/perfil_tab.dart';
import '../../widgets/asistente_ia.dart';
import 'resp/resp_dashboard_tab.dart';
import 'resp/edan/edan_form_wizard.dart';
import 'resp/resp_galeria_tab.dart';
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
  final _galeriaTabKey = GlobalKey<RespGaleriaTabState>();
  final _mapaTabKey = GlobalKey<RespMapaTabState>();

  /// Evita apilar auto-syncs si la red parpadea
  /// (offline→online→offline→online seguidos).
  bool _sincronizandoAuto = false;

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
      _refrescarContadores();
      context.read<ReporteProvider>().initializeResp();
      // Migración única v1.2.0 → V2 (idempotente): los borradores legacy sin
      // contraparte aparecen en `formularios` antes de que las pestañas lean.
      unawaited(EdanStoreV2.instance.migrarLegadoV1());
      // Backfill de grupos para filas legacy sin info de grupos (idempotente):
      // como el listado ya no re-deriva `grup_*` de filas, los borradores
      // viejos necesitan sus grupos una vez para no quedar con badges mudos.
      unawaited(EdanStoreV2.instance.repararGruposLegacy());
      // La primera descarga (login en equipo nuevo) corre en segundo plano:
      // al terminar se refrescan las pestañas para que la lista no quede
      // vacía aunque haya cargado antes de que bajaran los datos.
      EdanStoreV2.instance.primeraDescarga.addListener(_onPrimeraDescarga);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivity?.removeListener(_onConnectivityChanged);
    EdanStoreV2.instance.primeraDescarga.removeListener(_onPrimeraDescarga);
    super.dispose();
  }

  /// La primera descarga terminó (éxito o fallo): repintar con lo bajado y,
  /// si falló, decirlo en vez de quedar muda. Sin conexión no es un error
  /// que valga un snackbar (el chip de la AppBar ya lo indica y todo sigue
  /// en SQLite listo para sincronizar).
  void _onPrimeraDescarga() {
    _dashboardTabKey.currentState?.refresh();
    _galeriaTabKey.currentState?.refresh();
    _mapaTabKey.currentState?.refresh();
    _refrescarContadores();
    final error = EdanStoreV2.instance.ultimoErrorPrimeraDescarga;
    if (error != null && mounted && !error.startsWith('Sin conexión')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Primera sincronización incompleta: $error. '
              'Se reintentará al iniciar sesión.'),
          backgroundColor: const Color(0xFFF59E0B),
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refrescarContadores();
    }
  }

  void _onConnectivityChanged() {
    final online = _connectivity?.isConnected ?? true;
    final volvio = online && !_wasOnline;
    _wasOnline = online;
    _refrescarContadores();
    if (volvio) {
      // Al volver internet se auto-sincroniza sin diálogo (igual que UGR):
      // solo si hay pendientes y sin sync en curso. El snackbar de
      // resultado informa; el modo `auto:true` silencia el "sin cambios".
      unawaited(_sincronizarSiHayPendientes());
    }
  }

  /// Auto-push al reconectar: corre `_sincronizar(auto: true)` solo con
  /// trabajo pendiente y sin corrida en curso. Nunca apila llamadas.
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

  /// Refresca el contador de pendientes del flujo V2 (botón del appbar,
  /// `cola_sincronizacion` + `cola_fotos`). Diseño limpio: RESP ya no usa el
  /// contador legacy.
  void _refrescarContadores() {
    EdanStoreV2.instance.refrescarPendientes();
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
            // Arranque offline-first: la UI se pinta de inmediato con SQLite
            // (la parte local de initialize() es rápida); la red corre en
            // segundo plano. Una SOLA barra bajo el AppBar indica el progreso
            // (nunca se apilan ni tapa contenido): manda la sincronización,
            // si no hay, los catálogos.
            return _buildMainContent(palette, rp);
          },
        ),
      ),
    );
  }

  /// Barra de progreso bajo el AppBar: UNA sola (sync manda, si no
  /// catálogos). Mismas condiciones de visibilidad de siempre, solo cambia
  /// el diseño y la ubicación (empuja el contenido, no lo tapa).
  Widget _barraProgreso(ReporteProvider rp) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        EdanStoreV2.instance.descargaFotosTotal,
        EdanStoreV2.instance.descargaFotosHechas,
        EdanStoreV2.instance.sincronizandoNotifier,
        EdanStoreV2.instance.faseSync,
      ]),
      builder: (context, _) {
        String? texto;
        double? progreso;
        if (EdanStoreV2.instance.sincronizandoNotifier.value) {
          final fase = EdanStoreV2.instance.faseSync.value;
          final total = EdanStoreV2.instance.descargaFotosTotal.value;
          final hechas = EdanStoreV2.instance.descargaFotosHechas.value;
          final esFotos = fase == 'Descargando fotos' && total > 0;
          texto = esFotos
              ? 'Descargando fotos $hechas de $total...'
              : (fase.isNotEmpty ? '$fase...' : 'Sincronizando...');
          progreso = esFotos ? hechas / total : null;
        } else if (rp.isInitializing || rp.progresoCatalogos != null) {
          texto = rp.downloadPhase.isNotEmpty
              ? rp.downloadPhase
              : 'Cargando datos locales...';
          progreso = rp.progresoCatalogos;
        }
        if (texto == null) return const SizedBox.shrink();
        return _contenidoFranja(texto: texto, progreso: progreso);
      },
    );
  }

  /// Barra de progreso clara bajo el AppBar: fondo blanco, texto grafito,
  /// icono y barra en rojo institucional, % a la derecha. Es UN solo slot
  /// (nunca se apila): muestra la sincronización si hay una en curso, si no
  /// los catálogos. Solo diseño: las condiciones de visibilidad no cambian.
  Widget _contenidoFranja({
    required String texto,
    required double? progreso,
  }) {
    const rojo = Color(0xFFC0392B);
    final pct =
        progreso == null ? null : '${(progreso.clamp(0.0, 1.0) * 100).toInt()}%';
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cloud_download_outlined,
                size: 18,
                color: rojo,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  texto,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (pct != null)
                Text(
                  pct,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: rojo,
                  ),
                )
              else
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: rojo,
                  ),
                ),
            ],
          ),
          if (progreso != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progreso.clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: const Color(0xFFF3D9D4),
                valueColor: const AlwaysStoppedAnimation<Color>(rojo),
              ),
            ),
          ],
        ],
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
      body: SafeArea(
        child: Column(
          children: [
            // Barra de progreso entre el AppBar y el contenido: empuja en
            // vez de tapar, y es UN solo slot (nunca se apila).
            _barraProgreso(rp),
            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: [
                  RespDashboardTab(
                    key: _dashboardTabKey,
                    onSync: () => _sincronizar(auto: false),
                  ),
                  RespGaleriaTab(key: _galeriaTabKey),
                  // Diseño limpio: el mapa RESP lee solo tablas V2 (inyectado; el
                  // fallback legacy del widget queda para UGR).
                  RespMapaTab(
                    key: _mapaTabKey,
                    cargarLocalidades: () =>
                        EdanStoreV2.instance.listarFormularios(
                      usuarioId: AuthService.instance.userId,
                    ),
                  ),
                  const RespGuiaTab(),
                  const PerfilTab(catalogoEdan: true),
                ],
              ),
            ),
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
              _galeriaTabKey.currentState?.refresh();
            case 2:
              _mapaTabKey.currentState?.refresh();
          }
          _refrescarContadores();
        },
        selectedItemColor: palette.primary,
        unselectedItemColor: AppColors.textSecondary,
        backgroundColor: AppColors.surface,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.summarize_outlined),
            activeIcon: Icon(Icons.summarize),
            label: 'Reportes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.photo_library_outlined),
            activeIcon: Icon(Icons.photo_library),
            label: 'Galería',
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
                      ? 'Sin conexión. Al recuperar la red se avisará para sincronizar.'
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
      // Carpeta de fotos: la usamos para la recuperacion en un dispositivo
      // nuevo (el motor descarga a `ruta_local` las fotos que el pull trajo
      // solo con metadatos). Única carpeta: `report_photos/`. Si no se puede
      // resolver el directorio, el sync sigue sin descargar (queda pendiente).
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
      // El motor captura casi todo, pero un fallo inesperado (bug local)
      // no debe dejar la UI colgada sin mensaje ni refresco.
      result = EdanSyncResumen(
        exito: false,
        ultimoError: 'Error inesperado: $e',
      );
    } finally {
      store.sincronizandoNotifier.value = false;
    }
    if (!mounted) return;

    _dashboardTabKey.currentState?.refresh();
    _galeriaTabKey.currentState?.refresh();
    _refrescarContadores();

    if (auto &&
        result.enviados == 0 &&
        result.errores == 0 &&
        result.fotosSubidas == 0 &&
        result.fotosDescargadas == 0) {
      return;
    }

    // El motor marca `ultimoError` con prefijo 'Sin conexión' cuando hubo un
    // SocketException (cayó la red durante la corrida). No se pinta rojo: no
    // hay nada que el usuario pueda hacer y el reenvío es automático.
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.exito ? mensaje : '$mensaje${result.ultimoError != null ? ' — ${result.ultimoError}' : ''}',
        ),
        backgroundColor: result.exito ? AppColors.aprobado : AppColors.rechazado,
        duration: const Duration(seconds: 5),
      ),
    );
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
        // Reportes: el `+` abre directo el wizard EDAN (Galería no crea).
        return FloatingActionButton(
          heroTag: 'fab_nuevo_reporte',
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
      ugrRoute(
        EdanFormWizard(storeV2: EdanStoreV2.instance),
        palette: Palettes.rea,
      ),
    );
    if (creado != true || !mounted) return;

    _dashboardTabKey.currentState?.refresh();
    _galeriaTabKey.currentState?.refresh();
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
        return 'Reportes';
      case 1:
        return 'Galería';
      case 2:
        return 'Mapa';
      case 3:
        return 'Guía';
      case 4:
        return 'Perfil';
      default:
        return 'Reportes';
    }
  }
}
