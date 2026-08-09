import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../models/ugr_models.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_helper.dart';
import '../../../services/edan_sync_service.dart';
import 'ugr_edan_list_screen.dart';

class UgrDashboardTab extends StatefulWidget {
  const UgrDashboardTab({super.key});

  @override
  State<UgrDashboardTab> createState() => _UgrDashboardTabState();
}

class _UgrDashboardTabState extends State<UgrDashboardTab> {
  List<UgrReporte> _reportes = [];
  final List<UgrEdan> _edanes = [];
  List<UgrActividad> _actividad = [];

  UgrIndicadores get _indicadores => UgrIndicadores(
        reportesNuevos: _reportes.where((r) => r.estado == UgrReporteEstado.enviado).length,
        reportesConfirmados: _reportes.where((r) => r.estado == UgrReporteEstado.aprobado).length,
        edanEnEdicion: _edanes.where((e) => e.estado == UgrEdanEstado.enEdicion).length,
        edanObservados: _edanes.where((e) => e.estado == UgrEdanEstado.observado).length,
        edanEnviados: _edanes.where((e) => e.estado == UgrEdanEstado.enviado).length,
      );

  @override
  void initState() {
    super.initState();
    _sincronizarEnSegundoPlano();
    _cargarReportes();
    _cargarEdanes();
  }

  Future<void> _sincronizarEnSegundoPlano() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    
    final result = await EdanSyncService.instance.sincronizar();
    
    if (!mounted) return;
    if (result.exito && (result.creados > 0 || result.actualizados > 0 || result.enviados > 0)) {
      _cargarEdanes();
    }
  }

  Future<void> _cargarEdanes() async {
    final userId = AuthService.instance.userId;
    if (userId == null) return;
    try {
      final edanes = await DatabaseHelper.instance.getEdans(userId);
      if (!mounted) return;
      setState(() {
        _edanes
          ..clear()
          ..addAll(edanes.map((e) => UgrEdan.fromEdan(
                e,
                municipioNombre: e.municipioNombre ?? '',
                usuarioNombre: AuthService.instance.userName,
              )));
      });
    } catch (_) {}
  }

  Future<void> _cargarReportes() async {
    final municipioId = AuthService.instance.currentToken?.idMunicipio;
    if (municipioId == null) return;
    try {
      final reportes = await ApiService.instance.getReportes(
        idMunicipio: municipioId,
        limit: 50,
      );
      reportes.sort((a, b) {
        final fa = a.fechaReporte ?? '';
        final fb = b.fechaReporte ?? '';
        return fb.compareTo(fa);
      });
      if (mounted) {
        setState(() {
          _reportes = reportes.map(UgrReporte.fromServer).toList();
          _actividad = _buildActividadFromReportes(_reportes);
        });
      }
    } catch (_) {}
  }

  List<UgrActividad> _buildActividadFromReportes(List<UgrReporte> reportes) {
    final recientes = reportes.take(6).toList();
    return recientes.map((r) {
      final color = switch (r.estado) {
        UgrReporteEstado.enviado => AppColors.pending,
        UgrReporteEstado.enRevision => AppColors.inProgress,
        UgrReporteEstado.aprobado => AppColors.aprobado,
        UgrReporteEstado.rechazado => AppColors.rechazado,
        UgrReporteEstado.cerrado => AppColors.closed,
      };
      final icon = switch (r.estado) {
        UgrReporteEstado.enviado => Icons.send,
        UgrReporteEstado.enRevision => Icons.visibility,
        UgrReporteEstado.aprobado => Icons.verified,
        UgrReporteEstado.rechazado => Icons.cancel,
        UgrReporteEstado.cerrado => Icons.lock,
      };
      final comunidad = r.comunidad.isNotEmpty ? ' en ${r.comunidad}' : '';
      final autor =
          r.responsable.isNotEmpty ? ' por ${r.responsable}' : '';
      return UgrActividad(
        texto: 'Reporte de ${r.tipoEvento}$comunidad$autor',
        tiempo: r.tiempoRelativo,
        icon: icon,
        color: color,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return RefreshIndicator(
      onRefresh: () async {
        await _sincronizarManual();
        await _cargarReportes();
        await _cargarEdanes();
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
          _buildActividad(),
        ],
      ),
    );
  }

  Future<void> _sincronizarManual() async {
    final result = await EdanSyncService.instance.sincronizar();
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.resumen),
        backgroundColor: result.exito ? AppColors.aprobado : AppColors.rechazado,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildWelcomeHeader() {
    final auth = context.watch<AuthProvider>();
    final primary = PaletteScope.of(context).primary;
    final light = Color.lerp(primary, Colors.white, 0.18)!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, light],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.3),
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
                  auth.rolName ?? 'Unidad de Gestión de Riesgo',
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

  Widget _buildIndicadores(Color primary) {
    final ind = _indicadores;
    final cards = <_IndicatorCard>[
      _IndicatorCard(
        value: ind.reportesNuevos,
        label: 'Reportes nuevos',
        icon: Icons.warning_amber_rounded,
        color: AppColors.pending,
      ),
      _IndicatorCard(
        value: ind.reportesConfirmados,
        label: 'Reportes confirmados',
        icon: Icons.check_circle,
        color: AppColors.aprobado,
      ),
      _IndicatorCard(
        value: ind.edanEnEdicion,
        label: 'EDAN en edición',
        icon: Icons.edit,
        color: AppColors.inProgress,
      ),
      _IndicatorCard(
        value: ind.edanObservados,
        label: 'EDAN observados',
        icon: Icons.feedback,
        color: AppColors.rechazado,
      ),
      _IndicatorCard(
        value: ind.edanEnviados,
        label: 'EDAN enviados',
        icon: Icons.send,
        color: primary,
      ),
    ];

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 8),
            Expanded(child: cards[1]),
            const SizedBox(width: 8),
            Expanded(child: cards[2]),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: cards[3]),
            const SizedBox(width: 8),
            Expanded(child: cards[4]),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UgrEdanListScreen()),
            ),
            icon: const Icon(Icons.folder_outlined),
            label: const Text('Ver mis EDAN'),
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActividad() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: _actividad.map((item) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(item.icon, size: 20, color: item.color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.texto,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  item.tiempo,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                '$value',
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
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.85)),
          ),
        ],
      ),
    );
  }
}
