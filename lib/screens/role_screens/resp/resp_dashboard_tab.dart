import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../models/edan.dart';
import '../../../providers/reporte_provider.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_helper.dart';
import '../../../services/edan/edan_localidades_envio_v2_service.dart';
import '../../../services/localidad_sync_service.dart';
import 'edan/edan_form_wizard.dart';
import '../ugr/ugr_edan_preview_screen.dart';
import '../ugr/ugr_route.dart';

class RespDashboardTab extends StatefulWidget {
  final void Function(UgrLocalidadEstado? estado)? onVerEnReportes;
  final VoidCallback? onSync;

  const RespDashboardTab({super.key, this.onVerEnReportes, this.onSync});

  @override
  State<RespDashboardTab> createState() => RespDashboardTabState();
}

class RespDashboardTabState extends State<RespDashboardTab> with WidgetsBindingObserver {
  List<EdanLocalidad> _localidades = [];

  Map<String, int> get _indicadores {
    final total = _localidades.length;
    final huerfanas = _localidades.where((l) => l.esHuerfana).length;
    final enviadas = _localidades.where((l) => l.estadoLocalidad == UgrLocalidadEstado.enviadoUgr).length;
    final aprobadas = _localidades.where((l) => l.estadoLocalidad == UgrLocalidadEstado.aprobadoUgr).length;
    final rechazadas = _localidades.where((l) => l.estadoLocalidad == UgrLocalidadEstado.rechazadoUgr).length;
    return {
      'total': total,
      'huerfanas': huerfanas,
      'enviadas': enviadas,
      'aprobadas': aprobadas,
      'rechazadas': rechazadas,
    };
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargarLocalidades();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _cargarLocalidades();
    }
  }

  void refresh() {
    _cargarLocalidades();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _cargarLocalidades() async {
    final userId = AuthService.instance.userId;
    if (userId == null) {
      return;
    }
    try {
      final db = DatabaseHelper.instance;
      final localidades = await db.getLocalidades(userId);
      final visibles = localidades.where((l) => !l.pendienteEliminacion).toList();
      // Resolver nombres geográficos desde catálogo si faltan
      if (mounted) {
        final rp = context.read<ReporteProvider>();
        for (final loc in visibles) {
          if ((loc.departamentoNombre == null || loc.departamentoNombre!.isEmpty) &&
              loc.idDepartamento != null) {
            final match = rp.departamentos.where((d) => d.id == loc.idDepartamento);
            if (match.isNotEmpty) loc.departamentoNombre = match.first.nombre;
          }
          if ((loc.provinciaNombre == null || loc.provinciaNombre!.isEmpty) &&
              loc.idProvincia != null) {
            final match = rp.provincias.where((p) => p.id == loc.idProvincia);
            if (match.isNotEmpty) loc.provinciaNombre = match.first.nombre;
          }
          if ((loc.municipioNombre == null || loc.municipioNombre!.isEmpty) &&
              loc.idMunicipio != null) {
            final match = rp.municipios.where((m) => m.id == loc.idMunicipio);
            if (match.isNotEmpty) loc.municipioNombre = match.first.nombre;
          }
        }
      }
      visibles.sort((a, b) {
        final fa = a.fechaModificacion ?? '';
        final fb = b.fechaModificacion ?? '';
        return fb.compareTo(fa);
      });
      if (mounted) {
        setState(() {
          _localidades = visibles.take(15).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _editarLocalidad(EdanLocalidad localidad) async {
    final result = await Navigator.of(context).push<bool>(
      ugrRoute(EdanFormWizard(edanAEditar: Edan.desdeLocalidad(localidad)), palette: Palettes.rea),
    );
    if (result == true && mounted) {
      await _cargarLocalidades();
    }
  }

  Future<void> _eliminarLocalidad(EdanLocalidad localidad) async {
    final idLocal = localidad.idLocal;
    if (idLocal == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Localidad'),
        content: Text(
          localidad.sincronizado
              ? 'Esta localidad ya fue sincronizada con el servidor.\n\n'
                  'Se marcará como "pendiente de eliminación" y se eliminará '
                  'de forma definitiva al sincronizar.'
              : '¿Estás seguro de eliminar esta localidad?\n\n'
                  'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.rechazado),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      if (localidad.sincronizado) {
        await DatabaseHelper.instance.markLocalidadAsPendingDeletion(idLocal);
      } else {
        await DatabaseHelper.instance.deleteLocalidad(idLocal);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              localidad.sincronizado
                  ? 'Localidad marcada para eliminación. Se borrará al sincronizar.'
                  : 'Localidad eliminada',
            ),
            backgroundColor: AppColors.rechazado,
          ),
        );
        await _cargarLocalidades();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _marcarEnviada(
    EdanLocalidad localidad, {
    UgrLocalidadEstado estadoDestino = UgrLocalidadEstado.enviadoUgr,
  }) async {
    localidad.estadoLocalidad = estadoDestino;
    localidad.idEdanLocalidadEstado = estadoDestino.id;
    localidad.pendienteActualizacion = true;
    localidad.sincronizado = false;
    await DatabaseHelper.instance.updateLocalidad(localidad);

    bool sincronizada = false;
    try {
      if (localidad.proteccion.isNotEmpty) {
        final catalogo = context.read<ReporteProvider>().gruposVulnerables;
        if (catalogo.isNotEmpty) {
          for (var i = 0; i < localidad.proteccion.length; i++) {
            if (localidad.proteccion[i].idGrupoVulnerableCatalogo == null &&
                i < catalogo.length) {
              localidad.proteccion[i].idGrupoVulnerableCatalogo =
                  catalogo[i].idGrupoVulnerable;
            }
          }
        }
      }
      localidad.idEdanLocalidadEstado = estadoDestino.id;

      sincronizada =
          await EdanLocalidadesEnvioV2Service().enviarLocalidad(localidad);

      if (sincronizada) {
        localidad.estadoLocalidad = estadoDestino;
        localidad.idEdanLocalidadEstado = estadoDestino.id;
        localidad.sincronizado = true;
        localidad.pendienteActualizacion = false;
        await DatabaseHelper.instance.updateLocalidad(localidad);
      }
    } catch (e) {
      debugPrint('[ENVIO] Error enviando directo: $e');
    }

    if (mounted) {
      final mensaje = switch (estadoDestino) {
        UgrLocalidadEstado.borrador => 'Borrador sincronizado al servidor',
        _ => 'Localidad enviada al UGR',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sincronizada
                ? mensaje
                : 'Localidad guardada; pendiente de sincronización',
          ),
          backgroundColor: sincronizada ? AppColors.aprobado : AppColors.pending,
        ),
      );
      await _cargarLocalidades();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return RefreshIndicator(
      onRefresh: () async {
        await _cargarLocalidades();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _buildWelcomeHeader(),
          ValueListenableBuilder<int>(
            valueListenable: LocalidadSyncService.instance.pendientes,
            builder: (context, pendientes, _) {
              return ValueListenableBuilder<bool>(
                valueListenable: LocalidadSyncService.instance.sincronizando,
                builder: (context, sincronizando, _) {
                  if (pendientes == 0 && !sincronizando) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _buildSyncBanner(primary, pendientes, sincronizando),
                  );
                },
              );
            },
          ),
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

  Widget _buildWelcomeHeader() {
    final token = AuthService.instance.currentToken;
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
                  token?.nombre ?? 'Usuario',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Responsable Local',
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

  Widget _buildSyncBanner(Color primary, int pendientes, bool sincronizando) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.pending.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.pending.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          if (sincronizando)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(
              Icons.cloud_upload_outlined,
              size: 18,
              color: AppColors.pending,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              sincronizando
                  ? 'Sincronizando…'
                  : pendientes == 1
                      ? '1 cambio pendiente de sincronizar'
                      : '$pendientes cambios pendientes de sincronizar',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (!sincronizando)
            FilledButton.icon(
              onPressed: widget.onSync,
              style: FilledButton.styleFrom(
                backgroundColor: primary,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: const Size(0, 36),
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(Icons.sync, size: 16),
              label: const Text('Sincronizar'),
            ),
        ],
      ),
    );
  }

  Widget _buildIndicadores(Color primary) {
    final ind = _indicadores;
    final cards = <_IndicatorCard>[
      _IndicatorCard(
        value: ind['total'] ?? 0,
        label: 'Total localidades',
        icon: Icons.folder,
        color: primary,
        onTap: () => widget.onVerEnReportes?.call(null),
      ),
      _IndicatorCard(
        value: ind['huerfanas'] ?? 0,
        label: 'Sin consolidar',
        icon: Icons.location_on_outlined,
        color: AppColors.pending,
        onTap: () => widget.onVerEnReportes?.call(null),
      ),
      _IndicatorCard(
        value: ind['enviadas'] ?? 0,
        label: 'Enviadas UGR',
        icon: Icons.send,
        color: AppColors.inProgress,
        onTap: () => widget.onVerEnReportes?.call(UgrLocalidadEstado.enviadoUgr),
      ),
      _IndicatorCard(
        value: ind['aprobadas'] ?? 0,
        label: 'Aprobadas',
        icon: Icons.check_circle,
        color: AppColors.aprobado,
        onTap: () => widget.onVerEnReportes?.call(UgrLocalidadEstado.aprobadoUgr),
      ),
      _IndicatorCard(
        value: ind['rechazadas'] ?? 0,
        label: 'Rechazadas',
        icon: Icons.feedback,
        color: AppColors.rechazado,
        onTap: () => widget.onVerEnReportes?.call(UgrLocalidadEstado.rechazadoUgr),
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
      ],
    );
  }

  Widget _buildActividad() {
    final recientes = _localidades.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (recientes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Aún no hay localidades registradas',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
          ),
        for (var i = 0; i < recientes.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Builder(
            builder: (ctx) {
              final loc = recientes[i];
              final estado = loc.estadoLocalidad ?? UgrLocalidadEstado.borrador;
              final edanTmp = Edan.desdeLocalidad(loc);
              edanTmp.completarResponsableDesdeCache();
              final completo =
                  edanTmp.incompletosPorSeccion(exigirAlcalde: true).isEmpty;
              return _RespLocalidadCard(
                localidad: loc,
                completo: completo,
                onTap: () async {
                  final confirmado = await Navigator.of(context).push<Edan>(
                    ugrRoute(UgrEdanPreviewScreen(
                      edan: Edan.desdeLocalidad(loc),
                      sinAlcalde: true,
                      cargarResponsableDeCache: true,
                    ), palette: Palettes.rea),
                  );
                  if (confirmado != null && mounted) {
                    await _marcarEnviada(loc);
                  } else {
                    _cargarLocalidades();
                  }
                },
                onEdit: estado == UgrLocalidadEstado.borrador
                    ? () => _editarLocalidad(loc)
                    : null,
                onDelete: estado == UgrLocalidadEstado.borrador
                    ? () => _eliminarLocalidad(loc)
                    : null,
              );
            },
          ),
        ],
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
  final VoidCallback? onTap;

  const _IndicatorCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
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
                style:
                    TextStyle(fontSize: 10, color: color.withValues(alpha: 0.85)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RespLocalidadCard extends StatelessWidget {
  final EdanLocalidad localidad;
  final bool completo;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _RespLocalidadCard({
    required this.localidad,
    required this.completo,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    final estado = localidad.estadoLocalidad ?? UgrLocalidadEstado.borrador;
    final esPendienteEnvio = estado == UgrLocalidadEstado.borrador && !localidad.sincronizado;
    final reporterName = AuthService.instance.userName ??
        AuthService.instance.currentToken?.nombre ??
        '';
    return Card(
      margin: EdgeInsets.zero,
      shape: esPendienteEnvio
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppColors.pending.withValues(alpha: 0.6), width: 1.5),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      localidad.tipoLocalidad.isNotEmpty
                          ? '${localidad.tipoLocalidad}: ${localidad.nombre.isNotEmpty ? localidad.nombre : 'Sin nombre'}'
                          : (localidad.nombre.isNotEmpty ? localidad.nombre : 'Sin nombre'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildSmallBadge(estado),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Reportado por: $reporterName',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.warning_amber, size: 14, color: AppColors.pending),
                  const SizedBox(width: 4),
                  Text(
                    localidad.tipoEventoNombre ?? 'Sin evento',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.calendar_today, size: 12, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    localidad.fechaEvento ?? 'Sin fecha',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (esPendienteEnvio)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.pending.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.pending.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_upload_outlined, size: 16, color: AppColors.pending),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          completo
                              ? 'Listo para enviar. Pulse la tarjeta y envíe al UGR desde la vista previa.'
                              : 'Incompleta. Pulse la tarjeta para completarla o guardar el borrador en la vista previa.',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.pending,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 14, color: AppColors.primary),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'La información debe ser enviada cuando esté completa desde la vista previa.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (onEdit != null)
                    _buildActionButton(
                      icon: Icons.edit_outlined,
                      label: 'Editar',
                      color: primary,
                      onTap: onEdit!,
                    ),
                  if (onEdit != null && onDelete != null)
                    const SizedBox(width: 8),
                  if (onDelete != null)
                    _buildActionButton(
                      icon: Icons.delete_outline,
                      label: 'Eliminar',
                      color: AppColors.rechazado,
                      onTap: onDelete!,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmallBadge(UgrLocalidadEstado estado) {
    final color = estado.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(estado.icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            estado.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
