import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../models/edan.dart';
import '../../../providers/reporte_provider.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_helper.dart';
import '../../../services/edan/edan_envio_v2.dart';
import '../../../services/edan/edan_localidades_envio_v2_service.dart';
import '../../../services/edan/edan_store_v2.dart';
import '../../../widgets/edan_json_preview_dialog.dart';
import '../../../widgets/edan_seccion_badges.dart';
import 'edan/edan_form_wizard.dart';
import 'edan/edan_preview_resp_screen.dart';
import '../ugr/ugr_route.dart';

class RespEdanLocalidadTab extends StatefulWidget {
  const RespEdanLocalidadTab({super.key});

  @override
  State<RespEdanLocalidadTab> createState() => RespEdanLocalidadTabState();
}

class RespEdanLocalidadTabState extends State<RespEdanLocalidadTab>
    with WidgetsBindingObserver {
  List<EdanLocalidad> _localidades = [];
  bool _cargando = true;
  UgrLocalidadEstado? _filtro;
  String _query = '';
  bool _wasSyncing = false;

  /// Motivo del fallo de la carga base (lectura local); `null` = sin error.
  /// Se muestra en el estado vacío para que una lista vacía NUNCA sea muda.
  String? _errorCarga;

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
    // V2: escuchar el notificador REAL del motor (el viejo
    // `EdanSyncRespoService.sincronizandoMunicipio` ya nadie lo dispara →
    // la pestaña nunca se refrescaba al terminar la descarga en el login).
    _wasSyncing = EdanStoreV2.instance.sincronizandoNotifier.value;
    EdanStoreV2.instance.sincronizandoNotifier.addListener(_onSyncChanged);
    EdanStoreV2.instance.primeraDescarga.addListener(_onPrimeraDescarga);
    EdanStoreV2.instance.catalogosVersion.addListener(_onCatalogos);
    // Datos mutados (guardar/borrar/pull/push): recarga directa sin esperar
    // al sync ni al retorno del wizard. Sin esto, un formulario recién
    // guardado no aparecía hasta refresh manual.
    EdanStoreV2.instance.datosVersion.addListener(_onDatos);
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
    EdanStoreV2.instance.sincronizandoNotifier.removeListener(_onSyncChanged);
    EdanStoreV2.instance.primeraDescarga.removeListener(_onPrimeraDescarga);
    EdanStoreV2.instance.catalogosVersion.removeListener(_onCatalogos);
    EdanStoreV2.instance.datosVersion.removeListener(_onDatos);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onSyncChanged() {
    final syncing = EdanStoreV2.instance.sincronizandoNotifier.value;
    if (_wasSyncing && !syncing) {
      _cargarLocalidades();
    }
    _wasSyncing = syncing;
  }

  /// La primera descarga (y cada re-corrida) termina con un incremento del
  /// contador: recargar la lista aunque el evento llegue sin transición
  /// previa visible (pantalla montada tarde).
  void _onPrimeraDescarga() {
    _cargarLocalidades();
  }

  /// Los catálogos de red terminaron (llegaron tarde): recargar para
  /// resolver nombres geográficos/tipo sin esperar otro sync.
  void _onCatalogos() {
    _cargarLocalidades();
  }

  /// Los datos mutaron (guardado/borrado/pull/push confirmado): recargar
  /// aunque el wizard siga abierto o el retorno haya sido `pop(false)`.
  void _onDatos() {
    _cargarLocalidades();
  }

  Future<void> _cargarLocalidades() async {
    final userId = AuthService.instance.userId;
    if (userId == null) {
      if (mounted) setState(() => _cargando = false);
      return;
    }
    // Sin el try/catch monolítico de antes: un `catch (_)` sobre TODO el
    // bloque vaciaba la lista en silencio ante la menor excepción (flags,
    // grupos, catálogo). Ahora cada paso de enriquecimiento es por-ítem y el
    // error de la carga base se muestra en el estado vacío.
    String? errorCarga;
    var visibles = <EdanLocalidad>[];
    try {
      // Etapa 5: fuente única (`formularios` + legacy sin contraparte V2,
      // deduplicado por uuid). Los flags se hidratan vía V2 cuando hay fila.
      final store = EdanStoreV2.instance;
      final localidades = await store.listarReportes(usuarioId: userId);
      visibles = localidades
          .where((l) => !l.pendienteEliminacion)
          .toList();
    } catch (e) {
      errorCarga = 'No se pudo leer la lista local: $e';
      debugPrint('[RespTab] listarReportes falló: $e');
    }

    // Resincronizar flags imp_* desde localidad_secciones_activas (fuente
    // autoritativa) para que los badges del item reflejen lo realmente
    // marcado, igual que el JSON del long press y la vista previa.
    final sincV2 = EdanLocalidadesEnvioV2Service();
    final storeV2 = EdanStoreV2.instance;
    for (final loc in visibles) {
      try {
        await sincV2.aplicarFlagsDesdeSeccionesActivas(loc);
        // El nodo `grupos` del servidor manda sobre el snapshot: si el GET
        // trae un grupo en true, el badge lo muestra aunque las filas aún no
        // estén en el dispositivo (caso Urubo).
        await storeV2.aplicarGruposServidorAlModelo(loc);
      } catch (e) {
        // Un ítem malo no tumba la lista entera: se queda con sus flags base.
        debugPrint('[RespTab] flags/grupos de ${loc.nombre} omitidos: $e');
      }
    }
    // Resolver nombres geográficos desde catálogo si faltan (por ítem)
    if (mounted) {
      final rp = context.read<ReporteProvider>();
      for (final loc in visibles) {
        try {
          if ((loc.departamentoNombre == null ||
                  loc.departamentoNombre!.isEmpty) &&
              loc.idDepartamento != null) {
            final match = rp.departamentos.where(
              (d) => d.id == loc.idDepartamento,
            );
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
          // Resolver tipoLocalidad desde catálogo usando idTipoLocalidad
          if (loc.idTipoLocalidad != null) {
            final match = rp.tiposLocalidad.where(
              (t) => t.idTipoLocalidad == loc.idTipoLocalidad,
            );
            if (match.isNotEmpty) loc.tipoLocalidad = match.first.nombre;
          }
          // Resolver tipo de evento desde catálogo (misma regla que geo: sin
          // esto la tarjeta dice "Sin evento" aunque el servidor lo envíe).
          if ((loc.tipoEventoNombre == null ||
                  loc.tipoEventoNombre!.isEmpty) &&
              loc.idTipoEvento != null) {
            final nombre = rp.getTipoEventoNombre(loc.idTipoEvento!);
            if (nombre != 'Desconocido') loc.tipoEventoNombre = nombre;
          }
        } catch (e) {
          debugPrint('[RespTab] catálogo de ${loc.nombre} omitido: $e');
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
        _localidades = visibles;
        _errorCarga = errorCarga;
        _cargando = false;
      });
    }
  }

  Future<void> _editarLocalidad(EdanLocalidad localidad) async {
    final result = await Navigator.of(context).push<bool>(
      ugrRoute(
        EdanFormWizard(
          edanAEditar: Edan.desdeLocalidad(localidad),
          storeV2: EdanStoreV2.instance,
        ),
        palette: Palettes.rea,
      ),
    );
    if (result == true && mounted) {
      await _cargarLocalidades();
    }
  }

  Future<void> _eliminarLocalidad(EdanLocalidad localidad) async {
    final idLocal = localidad.idLocal;
    if (idLocal == null) return;
    // Fuente de verdad: ¿existe en el servidor? Decide el texto y el camino.
    // (`sincronizado` del snapshot puede estar desactualizado.)
    final uuidV2 = localidad.uuidEdanLocalidad;
    final esV2 = uuidV2 != null && uuidV2.isNotEmpty;
    final fueSincronizada =
        localidad.idServer != null || localidad.sincronizado;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Localidad'),
        content: Text(
          fueSincronizada
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
      if (esV2) {
        // Camino V2: borrado total local (+ `D` al servidor solo si estaba
        // sincronizada; si nunca se sincronizó no hay nada que informar).
        await EdanStoreV2.instance.eliminarLocalidad(uuidV2);
      } else if (fueSincronizada) {
        await DatabaseHelper.instance.markLocalidadAsPendingDeletion(idLocal);
      } else {
        await DatabaseHelper.instance.deleteLocalidad(idLocal);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            fueSincronizada
                ? 'Localidad marcada para eliminación. Se borrará al sincronizar.'
                : 'Localidad eliminada',
          ),
          backgroundColor:
              fueSincronizada ? AppColors.pending : AppColors.aprobado,
        ),
      );
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

  Future<void> _marcarEnviada(
    EdanLocalidad localidad, {
    UgrLocalidadEstado estadoDestino = UgrLocalidadEstado.enviadoUgr,
  }) async {
    // Etapa 5 (§6): la intención se registra, el estado NO se anticipa. El
    // badge `enviado` solo aparece con el 200 del servidor; si falla, la
    // tarjeta sigue en borrador + pendiente de sincronización.
    final estadoPrevio = localidad.estadoLocalidad;
    final idEstadoPrevio = localidad.idEdanLocalidadEstado;
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

      sincronizada = await EdanEnvioV2.enviar(
        localidad,
        idEdanLocalidadEstado: estadoDestino.id,
      );

      if (sincronizada) {
        localidad.estadoLocalidad = estadoDestino;
        localidad.idEdanLocalidadEstado = estadoDestino.id;
        localidad.sincronizado = true;
        localidad.pendienteActualizacion = false;
        localidad.editado = false;
        await DatabaseHelper.instance.updateLocalidad(localidad);
      } else {
        // Sin confirmación no hay enviado: se restaura el estado previo en
        // el espejo legacy (el motor ya dejó pendiente_push=1 + intención).
        localidad.estadoLocalidad = estadoPrevio;
        localidad.idEdanLocalidadEstado = idEstadoPrevio;
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
          backgroundColor: sincronizada
              ? AppColors.aprobado
              : AppColors.pending,
        ),
      );
      await _cargarLocalidades();
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
          .where(
            (l) =>
                l.nombre.toLowerCase().contains(q) ||
                l.tipoLocalidad.toLowerCase().contains(q),
          )
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
          valueListenable: EdanStoreV2.instance.sincronizandoNotifier,
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
            if (_errorCarga != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _errorCarga!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.rechazado,
                  ),
                ),
              ),
            ],
            if (_errorCarga != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  setState(() => _cargando = true);
                  _cargarLocalidades();
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargarLocalidades,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final localidad = list[index];
        final edanTmp = Edan.desdeLocalidad(localidad);
        edanTmp.completarResponsableDesdeCache();
        final completo = edanTmp
            .incompletosPorSeccion(exigirAlcalde: true)
            .isEmpty;
        return _RespLocalidadCard(
          localidad: localidad,
          completo: completo,
          onTap: () async {
            final confirmado = await Navigator.of(context).push<bool>(
              ugrRoute(
                EdanPreviewRespScreen(localidad: localidad),
                palette: Palettes.rea,
              ),
            );
            if (confirmado == true && mounted) {
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
        );
      },
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
    final esPendienteEnvio =
        estado == UgrLocalidadEstado.borrador && !localidad.sincronizado;
    // Autor REAL del servidor (nodo `usuario` disgregado); fallback al
    // logueado solo si aún no se conoce autor (borrador local nuevo).
    final autor = localidad.usuario?.nombre;
    final reporterName = (autor != null && autor.isNotEmpty)
        ? autor
        : (AuthService.instance.userName ??
            AuthService.instance.currentToken?.nombre ??
            '');
    return Card(
      margin: EdgeInsets.zero,
      shape: esPendienteEnvio
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: AppColors.pending.withValues(alpha: 0.6),
                width: 1.5,
              ),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => EdanJsonPreviewDialog.show(context, localidad),
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
                          : (localidad.nombre.isNotEmpty
                                ? localidad.nombre
                                : 'Sin nombre'),
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
                  const Icon(
                    Icons.person_outline,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
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
                  const Icon(
                    Icons.warning_amber,
                    size: 14,
                    color: AppColors.pending,
                  ),
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
                  const Icon(
                    Icons.calendar_today,
                    size: 12,
                    color: AppColors.textSecondary,
                  ),
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
              EdanSeccionBadges(localidad: localidad),
              const SizedBox(height: 10),
              if (localidad.envioPendiente)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.completed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.completed.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.send_outlined,
                        size: 16,
                        color: AppColors.completed,
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Envío pendiente: se enviará al UGR al sincronizar.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.completed,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (esPendienteEnvio)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.pending.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.pending.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.cloud_upload_outlined,
                        size: 16,
                        color: AppColors.pending,
                      ),
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
