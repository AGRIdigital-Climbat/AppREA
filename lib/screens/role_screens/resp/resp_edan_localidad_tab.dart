import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../models/edan.dart';
import '../../../providers/reporte_provider.dart';
import '../../../services/auth_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/database_helper.dart';
import '../../../services/localidad_sync_service.dart';
import 'resp_edan_form_screen.dart';
import '../ugr/ugr_edan_preview_screen.dart';
import '../ugr/ugr_route.dart';

class RespEdanLocalidadTab extends StatefulWidget {
  const RespEdanLocalidadTab({super.key});

  @override
  State<RespEdanLocalidadTab> createState() => RespEdanLocalidadTabState();
}

class RespEdanLocalidadTabState extends State<RespEdanLocalidadTab> with WidgetsBindingObserver {
  List<EdanLocalidad> _localidades = [];
  bool _cargando = true;
  UgrLocalidadEstado? _filtro;
  String _query = '';

  void refresh() {
    _cargarLocalidades();
  }

  void aplicarFiltro(UgrLocalidadEstado? estado) {
    setState(() {
      _filtro = estado;
      _query = '';
    });
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _cargarLocalidades() async {
    final userId = AuthService.instance.userId;
    if (userId == null) {
      if (mounted) setState(() => _cargando = false);
      return;
    }
    try {
      final db = DatabaseHelper.instance;
      final localidades = await db.getLocalidades(userId);
      // Resolver nombres geográficos desde catálogo si faltan
      if (mounted) {
        final rp = context.read<ReporteProvider>();
        for (final loc in localidades) {
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
      localidades.sort((a, b) {
        final fa = a.fechaModificacion ?? '';
        final fb = b.fechaModificacion ?? '';
        return fb.compareTo(fa);
      });
      if (mounted) {
        setState(() {
          _localidades = localidades;
          _cargando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _editarLocalidad(EdanLocalidad localidad) async {
    final result = await Navigator.of(context).push<bool>(
      ugrRoute(RespEdanFormScreen(edanAEditar: Edan.desdeLocalidad(localidad)), palette: Palettes.rea),
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
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Localidad marcada para eliminación. Se borrará al sincronizar.'),
            backgroundColor: AppColors.pending,
          ),
        );
      } else {
        await DatabaseHelper.instance.deleteLocalidad(idLocal);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Localidad eliminada'),
            backgroundColor: AppColors.aprobado,
          ),
        );
      }
      await _cargarLocalidades();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar: $e'),
          backgroundColor: AppColors.rechazado,
        ),
      );
    }
  }

  Future<void> _enviarLocalidad(EdanLocalidad localidad) async {
    final edan = Edan.desdeLocalidad(localidad);
    edan.completarResponsableDesdeCache();
    final incompletos = edan.incompletosPorSeccion(exigirAlcalde: true);

    if (incompletos.isNotEmpty) {
      final secciones = incompletos.keys.join(', ');
      final totalCampos = incompletos.values.fold<int>(0, (sum, l) => sum + l.length);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, size: 40, color: AppColors.pending),
          title: const Text('Formulario incompleto'),
          content: Text(
            'Faltan $totalCampos campo(s) por completar en la(s) sección(es): $secciones.\n\n'
            'Debe completar todos los campos antes de enviar al UGR.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.send_rounded, size: 40, color: AppColors.aprobado),
        title: const Text('Enviar al UGR'),
        content: const Text(
          'El formulario está completo y listo para enviar.\n\n'
          'Una vez enviado, el UGR revisará su reporte y '
          'no podrá editarlo hasta que sea aprobado o rechazado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.aprobado),
            child: const Text('Confirmar Envío'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await _marcarEnviada(localidad);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _marcarEnviada(EdanLocalidad localidad) async {
    localidad.estadoLocalidad = UgrLocalidadEstado.enviadoUgr;
    localidad.idEdanLocalidadEstado = UgrLocalidadEstado.enviadoUgr.id;
    localidad.pendienteActualizacion = true;
    localidad.sincronizado = false;
    await DatabaseHelper.instance.updateLocalidad(localidad);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Localidad enviada al UGR'),
          backgroundColor: AppColors.aprobado,
        ),
      );
      await _cargarLocalidades();
      _sincronizarServidor();
    }
  }

  Future<void> _sincronizarServidor() async {
    if (LocalidadSyncService.instance.isSyncing) return;
    if (!ConnectivityService().isConnected) return;
    final result = await LocalidadSyncService.instance.sincronizar();
    if (mounted && result.exito) {
      _cargarLocalidades();
    }
  }

  List<EdanLocalidad> get _filtered {
    var list = _localidades;
    if (_filtro != null) {
      list = list.where((l) => l.estadoLocalidad == _filtro).toList();
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((l) =>
              l.nombre.toLowerCase().contains(q) ||
              l.tipoLocalidad.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return Column(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: LocalidadSyncService.instance.sincronizandoMunicipio,
          builder: (context, sincronizando, _) => sincronizando
              ? _buildSyncMunicipioBanner(primary)
              : const SizedBox.shrink(),
        ),
        _buildFilterBar(primary),
        _buildSearchField(primary),
        Expanded(child: _buildList(primary)),
      ],
    );
  }

  Widget _buildSyncMunicipioBanner(Color primary) {
    return Container(
      width: double.infinity,
      color: primary.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: primary),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Sincronizando localidades…',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(Color primary) {
    const estados = <UgrLocalidadEstado?>[
      null,
      UgrLocalidadEstado.borrador,
      UgrLocalidadEstado.enviadoUgr,
      UgrLocalidadEstado.aprobadoUgr,
      UgrLocalidadEstado.rechazadoUgr,
    ];

    return Container(
      color: AppColors.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: estados.map((estado) {
            final isSelected = _filtro == estado;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(
                  estado == null ? 'Todas' : estado.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                  ),
                ),
                selected: isSelected,
                onSelected: (_) => setState(() => _filtro = estado),
                selectedColor: primary,
                backgroundColor: AppColors.surface,
                showCheckmark: false,
                side: BorderSide(
                  color: isSelected ? primary : AppColors.divider,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSearchField(Color primary) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      color: AppColors.surface,
      child: TextField(
        onChanged: (value) => setState(() => _query = value),
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Buscar nombre o tipo de localidad...',
          prefixIcon: const Icon(Icons.search, size: 20),
          isDense: true,
          filled: true,
          fillColor: PaletteScope.of(context).background,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: primary, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildList(Color primary) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final list = _filtered;
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.location_on_outlined,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              list.isEmpty && _query.isNotEmpty
                  ? 'Sin resultados para la búsqueda'
                  : 'No hay localidades registradas',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final localidad = list[index];
        return _RespLocalidadCard(
          localidad: localidad,
          onTap: () async {
            final confirmado = await Navigator.of(context).push<Edan>(
              ugrRoute(UgrEdanPreviewScreen(
                edan: Edan.desdeLocalidad(localidad),
                sinAlcalde: true,
                cargarResponsableDeCache: true,
              ), palette: Palettes.rea),
            );
            if (confirmado != null && mounted) {
              await _marcarEnviada(localidad);
            } else {
              await _cargarLocalidades();
            }
          },
          onEdit: localidad.estadoLocalidad == UgrLocalidadEstado.borrador
              ? () => _editarLocalidad(localidad)
              : null,
          onDelete: localidad.estadoLocalidad == UgrLocalidadEstado.borrador
              ? () => _eliminarLocalidad(localidad)
              : null,
          onEnviar: localidad.estadoLocalidad == UgrLocalidadEstado.borrador
              ? () => _enviarLocalidad(localidad)
              : null,
        );
      },
    );
  }
}

class _RespLocalidadCard extends StatelessWidget {
  final EdanLocalidad localidad;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onEnviar;

  const _RespLocalidadCard({
    required this.localidad,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.onEnviar,
  });

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    final estado = localidad.estadoLocalidad ?? UgrLocalidadEstado.borrador;
    final reporterName = AuthService.instance.userName ??
        AuthService.instance.currentToken?.nombre ??
        '';
    return Card(
      margin: EdgeInsets.zero,
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
