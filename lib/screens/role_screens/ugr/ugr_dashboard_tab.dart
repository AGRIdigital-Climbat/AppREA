import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../models/edan.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/api_service.dart';
import '../../../services/api/edan_api_v2.dart';
import '../../../services/auth_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/edan/edan_store_v2.dart';
import '../../../services/sync/edan_sync_engine_v2.dart';
import 'ugr_edan_preview_screen.dart';
import 'ugr_route.dart';
import '../../../services/app_logger_ui.dart';

class UgrDashboardTab extends StatefulWidget {
  const UgrDashboardTab({super.key});

  @override
  State<UgrDashboardTab> createState() => UgrDashboardTabState();
}

class UgrDashboardTabState extends State<UgrDashboardTab>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _edanesServidor = [];
  List<EdanLocalidad> _localidadesPendientes = [];
  int _localidadesAprobadas = 0;

  int get edanesCount => _edanesServidor.length;

  int get _edanEnviados =>
      _edanesServidor.where((e) => (e['estado'] ?? '').toString().toLowerCase() == 'enviado').length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sincronizarEnSegundoPlano();
    _cargarEdanesServidor();
    _cargarLocalidadesServidor();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _cargarEdanesServidor();
      _cargarLocalidadesServidor();
    }
  }

  void refresh() {
    _cargarEdanesServidor();
    _cargarLocalidadesServidor();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  int? get _idMunicipio => AuthService.instance.currentToken?.idMunicipio;

  Future<void> _sincronizarEnSegundoPlano() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    final result = await _sincronizarV2();
    if (!mounted) return;
    if (result != null &&
        result.exito &&
        (result.enviados > 0 ||
            result.fotosSubidas > 0 ||
            result.fotosDescargadas > 0)) {
      _cargarEdanesServidor();
      _cargarLocalidadesServidor();
    }
  }

  Future<void> _cargarEdanesServidor() async {
    final municipioId = _idMunicipio;
    if (municipioId == null) return;
    if (!ConnectivityService().isConnected) return;
    try {
      final data = await ApiService.instance.listarEdansPorMunicipio(municipioId);
      if (!mounted) return;
      setState(() {
        _edanesServidor = data;
      });
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 
          SnackBar(content: Text('Error al cargar EDANs: ${ApiService.traducirError(e)}'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _cargarLocalidadesServidor() async {
    final municipioId = _idMunicipio;
    if (municipioId == null) return;
    if (!ConnectivityService().isConnected) return;
    try {
      final resultados = await Future.wait([
        ApiService.instance.getConsolidarPendientes(
          idMunicipio: municipioId,
          estado: 'revision',
        ),
        ApiService.instance.getConsolidarPendientes(
          idMunicipio: municipioId,
          estado: 'aprobado',
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _localidadesPendientes = (resultados[0] as List).map((j) => EdanLocalidad.fromJson(j)).toList();
        _localidadesAprobadas = (resultados[1] as List).length;
      });
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 
          SnackBar(content: Text('Error al cargar localidades: ${ApiService.traducirError(e)}'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return RefreshIndicator(
      onRefresh: () async {
        await _sincronizarManual();
        await _cargarEdanesServidor();
        await _cargarLocalidadesServidor();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _buildWelcomeHeader(),
          const SizedBox(height: 20),
          const _SectionTitle('Indicadores'),
          const SizedBox(height: 8),
          _buildIndicadores(primary),
          const SizedBox(height: 20),
          const _SectionTitle('Actividad reciente'),
          const SizedBox(height: 8),
          _buildActividad(primary),
        ],
      ),
    );
  }

  Future<void> _sincronizarManual() async {
    await _sincronizarV2();
  }

  /// Corre el motor de sync V2 (envío de reportes propios + descarga de sus
  /// fotos). Devuelve `null` si ya hay una corrida en curso o si no hay red.
  Future<EdanSyncResumen?> _sincronizarV2() async {
    final store = EdanStoreV2.instance;
    if (store.sincronizandoNotifier.value) return null;
    if (!await ConnectivityService().checkNow()) return null;
    store.sincronizandoNotifier.value = true;
    try {
      Directory? dirFotos;
      try {
        final appDir = await getApplicationDocumentsDirectory();
        dirFotos = Directory('${appDir.path}/edan_fotos');
      } catch (_) {
        dirFotos = null;
      }
      final resumen = await EdanSyncEngineV2(
        api: EdanApiV2(),
        dirFotos: dirFotos,
      ).sincronizar();
      return resumen;
    } catch (_) {
      return null;
    } finally {
      store.sincronizandoNotifier.value = false;
      await store.refrescarPendientes();
    }
  }

  Widget _buildWelcomeHeader() {
    final nombre = context.watch<AuthProvider>().userName ?? 'UGR';
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: PaletteScope.of(context).primary.withValues(alpha: 0.1),
          child: Icon(Icons.location_city, color: PaletteScope.of(context).primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bienvenido, $nombre',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Gestión de EDAN y localidades',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIndicadores(Color primary) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _IndicatorCard(
                value: _localidadesPendientes.length,
                label: 'Localidades pendientes',
                icon: Icons.pending_actions,
                color: AppColors.pending,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _IndicatorCard(
                value: _localidadesAprobadas,
                label: 'Aprobadas',
                icon: Icons.check_circle_outline,
                color: AppColors.aprobado,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _IndicatorCard(
                value: edanesCount,
                label: 'EDAN consolidados',
                icon: Icons.folder_outlined,
                color: primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _IndicatorCard(
                value: _edanEnviados,
                label: 'EDAN enviados',
                icon: Icons.send_outlined,
                color: AppColors.enviado,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActividad(Color primary) {
    if (_localidadesPendientes.isEmpty && _edanesServidor.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.inbox_outlined, size: 36, color: AppColors.textSecondary.withValues(alpha: 0.4)),
                const SizedBox(height: 8),
                const Text(
                  'Sin actividad reciente',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final loc in _localidadesPendientes.take(5))
          _LocalidadActividadCard(localidad: loc, primary: primary),
        for (final edan in _edanesServidor.take(3))
          _EdanActividadCard(edan: edan, primary: primary),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _IndicatorCard extends StatelessWidget {
  final int value;
  final String label;
  final IconData icon;
  final Color color;

  const _IndicatorCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(
              '$value',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalidadActividadCard extends StatelessWidget {
  final EdanLocalidad localidad;
  final Color primary;
  const _LocalidadActividadCard({required this.localidad, required this.primary});

  @override
  Widget build(BuildContext context) {
    final estado = localidad.estadoLocalidad;
    final estadoColor = estado?.color ?? AppColors.textSecondary;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: primary.withValues(alpha: 0.1),
          child: Icon(Icons.location_on, color: primary, size: 18),
        ),
        title: Text(
          localidad.nombre.isNotEmpty ? localidad.nombre : 'Sin nombre',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${localidad.tipoEventoNombre ?? "Evento"} · ${localidad.totalPoblacionAfectada} personas',
          style: const TextStyle(fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: estadoColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            estado?.label ?? '?',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: estadoColor),
          ),
        ),
        onTap: () {
          final edan = Edan.desdeLocalidad(localidad);
          Navigator.of(context).push(
            ugrRoute(UgrEdanPreviewScreen(edan: edan)),
          );
        },
      ),
    );
  }
}

class _EdanActividadCard extends StatelessWidget {
  final Map<String, dynamic> edan;
  final Color primary;
  const _EdanActividadCard({required this.edan, required this.primary});

  @override
  Widget build(BuildContext context) {
    final codigo = (edan['codigo_edan'] ?? '').toString();
    final estado = (edan['estado'] ?? '').toString();
    final totalLocalidades = edan['total_localidades'] ?? 0;
    final totalPoblacion = edan['total_poblacion_afectada'] ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.aprobado.withValues(alpha: 0.1),
          child: const Icon(Icons.folder, color: AppColors.aprobado, size: 18),
        ),
        title: Text(
          codigo.isNotEmpty ? codigo : 'EDAN',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '$totalLocalidades localidades · $totalPoblacion personas',
          style: const TextStyle(fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.aprobado.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            estado.toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.aprobado),
          ),
        ),
      ),
    );
  }
}
