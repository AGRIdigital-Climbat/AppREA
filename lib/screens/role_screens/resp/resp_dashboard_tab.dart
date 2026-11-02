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

/// Listado visible de la pestaña Reportes: filtro por estado (los indicadores)
/// + búsqueda por nombre/tipo, aplicados EN EL SITIO sobre `origen`.
/// `estado == null` y `query` vacío = lista completa. Función pura para que
/// sea verificable sin widget-test.
List<EdanLocalidad> filtrarReportesResp(
  List<EdanLocalidad> origen, {
  UgrLocalidadEstado? estado,
  String query = '',
}) {
  var lista = origen;
  if (estado != null) {
    lista = lista.where((l) => l.estadoLocalidad == estado).toList();
  }
  final q = query.trim().toLowerCase();
  if (q.isNotEmpty) {
    lista = lista
        .where((l) =>
            l.nombre.toLowerCase().contains(q) ||
            l.tipoLocalidad.toLowerCase().contains(q))
        .toList();
  }
  return lista;
}

class RespDashboardTab extends StatefulWidget {
  final VoidCallback? onSync;

  const RespDashboardTab({super.key, this.onSync});

  @override
  State<RespDashboardTab> createState() => RespDashboardTabState();
}

class RespDashboardTabState extends State<RespDashboardTab>
    with WidgetsBindingObserver {
  List<EdanLocalidad> _localidades = [];
  bool _wasSyncing = false;

  /// Indicadores de Reportes calculados SOLO de SQLite (offline-first):
  /// `_conteosEstado` trae los 6 estados disgregados (id 1-6) y `_totalRemoto`
  /// su suma. Ya no se consultan al servidor: coinciden con la lista.
  Map<int, int> _conteosEstado = {};
  int _totalRemoto = 0;

  /// Filtro activo desde los indicadores: tap en un estado filtra el listado
  /// de ESTA pestaña; repetir el tap (o tocar Total) lo quita.
  UgrLocalidadEstado? _filtro;

  /// Búsqueda por nombre/tipo sobre el listado (el antiguo tab Reportes vivía
  /// de esto; ahora «todo» está aquí).
  String _query = '';

  /// Controlador del buscador: permite vaciar el campo junto con `_query`
  /// (sin él, «Quitar filtros» limpiaría el estado pero el texto seguiría
  /// visible en el TextField).
  final TextEditingController _ctrlBusqueda = TextEditingController();

  /// Motivo del fallo de la carga base (lectura local); `null` = sin error.
  /// Visible en Reportes para que "lista vacía" nunca sea silenciosa.
  String? _errorCarga;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // V2: escuchar el notificador REAL del motor (el viejo
    // `EdanSyncRespoService.sincronizandoMunicipio` ya nadie lo dispara →
    // el Inicio nunca se refrescaba al terminar la descarga en el login).
    _wasSyncing = EdanStoreV2.instance.sincronizandoNotifier.value;
    EdanStoreV2.instance.sincronizandoNotifier.addListener(_onSyncChanged);
    EdanStoreV2.instance.primeraDescarga.addListener(_onPrimeraDescarga);
    EdanStoreV2.instance.catalogosVersion.addListener(_onCatalogos);
    // Los contadores cambian al guardar/borrar/sync: recargan al instante.
    EdanStoreV2.instance.datosVersion.addListener(_onDatos);
    _cargarLocalidades();
  }

  @override
  void dispose() {
    EdanStoreV2.instance.sincronizandoNotifier.removeListener(_onSyncChanged);
    EdanStoreV2.instance.primeraDescarga.removeListener(_onPrimeraDescarga);
    EdanStoreV2.instance.catalogosVersion.removeListener(_onCatalogos);
    EdanStoreV2.instance.datosVersion.removeListener(_onDatos);
    WidgetsBinding.instance.removeObserver(this);
    _ctrlBusqueda.dispose();
    super.dispose();
  }

  void _onSyncChanged() {
    final syncing = EdanStoreV2.instance.sincronizandoNotifier.value;
    if (_wasSyncing && !syncing) {
      _cargarLocalidades();
    }
    _wasSyncing = syncing;
  }

  /// Cada corrida del motor (primera descarga incluida) termina con un
  /// incremento: refrescar aunque la pantalla se haya montado tarde.
  void _onPrimeraDescarga() {
    _cargarLocalidades();
  }

  /// Los catálogos de red terminaron (llegaron tarde): recargar para
  /// resolver nombres geográficos/tipo sin esperar otro sync.
  void _onCatalogos() {
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

  Future<void> _cargarLocalidades() async {
    final userId = AuthService.instance.userId;
    if (userId == null) {
      return;
    }
    // Sin `catch (_)` monolítico: la lectura base, el enriquecimiento de flags
    // y el catálogo son pasos por-ítem; un fallo no vacía la lista en silencio
    // ni deja el Inicio mudo.
    var visibles = <EdanLocalidad>[];
    String? errorCarga;
    try {
      // Etapa 5: fuente única (ver pestaña de reportes).
      final store = EdanStoreV2.instance;
      final localidades = await store.listarReportes(usuarioId: userId);
      visibles = localidades
          .where((l) => !l.pendienteEliminacion)
          .toList();
    } catch (e) {
      errorCarga = e.toString();
      debugPrint('[RespDashboard] listarReportes falló: $e');
    }
    // Resincronizar flags imp_* desde localidad_secciones_activas, en unión
    // con lo marcado en page01 (flags de datos_json), para que los badges
    // del item reflejen los GRUPOS activos (pantallas de page01), igual que
    // el JSON del long press y la vista previa.
    final sincV2 = EdanLocalidadesEnvioV2Service();
    final storeV2 = EdanStoreV2.instance;
    for (final loc in visibles) {
      try {
        await sincV2.aplicarFlagsDesdeSeccionesActivas(loc,
            unionConGuardados: true);
        await storeV2.aplicarGruposServidorAlModelo(loc);
      } catch (e) {
        debugPrint('[RespDashboard] flags/grupos de ${loc.nombre} '
            'omitidos: $e');
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
          // Resolver tipo de evento desde catálogo (evita "Sin evento").
          if ((loc.tipoEventoNombre == null ||
                  loc.tipoEventoNombre!.isEmpty) &&
              loc.idTipoEvento != null) {
            final nombre = rp.getTipoEventoNombre(loc.idTipoEvento!);
            if (nombre != 'Desconocido') loc.tipoEventoNombre = nombre;
          }
        } catch (e) {
          debugPrint('[RespDashboard] catálogo de ${loc.nombre} '
              'omitido: $e');
        }
      }
    }
    // Más reciente arriba por FECHA DE LLENADO (sin llenado: por modificación).
    visibles.sort(compararRecientePrimero);
    if (mounted) {
      setState(() {
        _localidades = visibles;
        _errorCarga = errorCarga;
      });
    }
    await _cargarIndicadores();
  }

  /// Indicadores calculados SOLO de SQLite (offline-first): los 6 estados
  /// disgregados + total. Sin API y sin memo: coinciden con la lista y
  /// cambian al instante (guardar/borrar/sync vía `datosVersion`).
  Future<void> _cargarIndicadores() async {
    final userId = AuthService.instance.userId;
    if (userId == null) return;
    try {
      final resumen = await EdanStoreV2.instance.resumenLocal(usuarioId: userId);
      if (!mounted) return;
      setState(() {
        _conteosEstado = resumen.porEstado;
        _totalRemoto = resumen.total;
      });
    } catch (e) {
      debugPrint('[RespDashboard] resumenLocal falló: $e');
    }
  }

  /// Los datos mutaron (guardar/borrar/pull/push): recargar contadores.
  void _onDatos() {
    _cargarIndicadores();
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              fueSincronizada
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
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _marcarEnviada(
    EdanLocalidad localidad, {
    UgrLocalidadEstado estadoDestino = UgrLocalidadEstado.enviadoUgr,
  }) async {
    // Igual que la pestaña: la intención se registra, el estado NO se
    // anticipa. El badge `enviado` solo aparece con el 200 del servidor; si
    // falla u offline, se restaura el previo (antes mentía offline).
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
          if (_errorCarga != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.rechazado.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.rechazado.withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'No se pudo cargar la lista local',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.rechazado,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _errorCarga!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _cargarLocalidades(),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Reintentar'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ValueListenableBuilder<int>(
            valueListenable: EdanStoreV2.instance.pendientesNotifier,
            builder: (context, pendientes, _) {
              return ValueListenableBuilder<bool>(
                valueListenable:
                    EdanStoreV2.instance.sincronizandoNotifier,
                builder: (context, sincronizando, _) {
                  if (pendientes == 0 && !sincronizando) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child:
                        _buildSyncBanner(primary, pendientes, sincronizando),
                  );
                },
              );
            },
          ),
          // Los indicadores arrancan directo arriba: sin cabecera de
          // bienvenida ni rótulo de sección (a pedido del usuario,
          // 2026-11-02).
          _buildIndicadores(primary),
          const SizedBox(height: 4),
          _buildEncabezadoLista(),
          const SizedBox(height: 8),
          _buildBusqueda(primary),
          const SizedBox(height: 12),
          _buildListado(),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
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
    // Un contador por estado (disgregado, sin agrupar) + total. Cada uno
    // filtra el listado de ESTa pestaña al tocarlo (tap repetido limpia).
    const estados = UgrLocalidadEstado.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IndicadoresResumenCard(
          total: _totalRemoto,
          primary: primary,
          estados: estados,
          conteos: _conteosEstado,
          seleccionado: _filtro,
          onTapTotal: () => setState(() => _filtro = null),
          onTapEstado: (e) => setState(
            () => _filtro = _filtro == e ? null : e,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Listado visible: indicadores (estado) + búsqueda aplicada en el sitio.
  List<EdanLocalidad> get _listado =>
      filtrarReportesResp(_localidades, estado: _filtro, query: _query);

  Widget _buildEncabezadoLista() {
    final filtrando = _filtro != null || _query.trim().isNotEmpty;
    return Row(
      children: [
        const _SectionTitle('Reportes'),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            filtrando
                ? '${_listado.length} de ${_localidades.length}'
                : '${_localidades.length} '
                    'localidad${_localidades.length == 1 ? '' : 'es'}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        if (_filtro != null)
          InputChip(
            visualDensity: VisualDensity.compact,
            label: Text(_filtro!.label,
                style: const TextStyle(fontSize: 11)),
            avatar: Icon(Icons.filter_alt,
                size: 14, color: _filtro!.color),
            deleteIcon: const Icon(Icons.close, size: 16),
            onDeleted: () => setState(() => _filtro = null),
          ),
      ],
    );
  }

  Widget _buildBusqueda(Color primary) {
    return TextField(
      controller: _ctrlBusqueda,
      onChanged: (v) => setState(() => _query = v),
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Buscar por nombre o tipo de localidad...',
        hintStyle: const TextStyle(
          fontSize: 12.5,
          color: AppColors.textSecondary,
        ),
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _query.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _ctrlBusqueda.clear();
                  setState(() => _query = '');
                },
              )
            : null,
        isDense: true,
        filled: true,
        fillColor: primary.withValues(alpha: 0.05),
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
    );
  }

  Widget _buildListado() {
    final list = _listado;
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text(
              _localidades.isEmpty
                  ? 'Aún no hay localidades registradas'
                  : 'Sin resultados para el filtro o la búsqueda',
              style:
                  const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            if (_localidades.isNotEmpty)
              TextButton.icon(
                onPressed: () {
                  _ctrlBusqueda.clear();
                  setState(() {
                    _filtro = null;
                    _query = '';
                  });
                },
                icon: const Icon(Icons.filter_alt_off, size: 16),
                label: const Text('Quitar filtros'),
              ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < list.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Builder(
            builder: (ctx) {
              final loc = list[i];
              final estado =
                  loc.estadoLocalidad ?? UgrLocalidadEstado.borrador;
              final edanTmp = Edan.desdeLocalidad(loc);
              edanTmp.completarResponsableDesdeCache();
              final completo = edanTmp
                  .incompletosPorSeccion(exigirAlcalde: true)
                  .isEmpty;
              return _RespLocalidadCard(
                localidad: loc,
                completo: completo,
                onTap: () async {
                  final confirmado = await Navigator.of(context).push<bool>(
                    ugrRoute(
                      EdanPreviewRespScreen(localidad: loc),
                      palette: Palettes.rea,
                    ),
                  );
                  if (confirmado == true && mounted) {
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

class _BucketIndicador {
  final String label;
  final int cantidad;
  final Color color;
  final VoidCallback onTap;
  final bool seleccionado;

  const _BucketIndicador({
    required this.label,
    required this.cantidad,
    required this.color,
    required this.onTap,
    this.seleccionado = false,
  });
}

/// Tarjeta de Indicadores: total + un contador por estado (disgregado).
/// Cada estado filtra el listado de la pestaña al tocarlo; el estado
/// seleccionado queda resaltado (otro tap lo quita).
class _IndicadoresResumenCard extends StatelessWidget {
  final int total;
  final Color primary;
  final List<UgrLocalidadEstado> estados;
  final Map<int, int> conteos;
  final VoidCallback onTapTotal;
  final void Function(UgrLocalidadEstado) onTapEstado;
  final UgrLocalidadEstado? seleccionado;

  const _IndicadoresResumenCard({
    required this.total,
    required this.primary,
    required this.estados,
    required this.conteos,
    required this.onTapTotal,
    required this.onTapEstado,
    this.seleccionado,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTapTotal,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: primary.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Total localidades',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: primary,
                      ),
                    ),
                  ),
                  Text(
                    '$total',
                    style: TextStyle(
                      fontSize: 24,
                      height: 1,
                      fontWeight: FontWeight.bold,
                      color: primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  for (final e in estados)
                    _LeyendaIndicador(
                      bucket: _BucketIndicador(
                        label: e.label,
                        cantidad: conteos[e.id] ?? 0,
                        color: e.color,
                        seleccionado: seleccionado == e,
                        onTap: () => onTapEstado(e),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeyendaIndicador extends StatelessWidget {
  final _BucketIndicador bucket;

  const _LeyendaIndicador({required this.bucket});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: bucket.onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: bucket.seleccionado
            ? BoxDecoration(
                color: bucket.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: bucket.color),
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: bucket.color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${bucket.label} ',
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    bucket.seleccionado ? FontWeight.w700 : FontWeight.w400,
                color: bucket.seleccionado
                    ? bucket.color
                    : AppColors.textSecondary,
              ),
            ),
            Text(
              '${bucket.cantidad}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: bucket.color,
              ),
            ),
          ],
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
    final esPendienteEnvio =
        estado == UgrLocalidadEstado.borrador && !localidad.sincronizado;
    final reporterName =
        AuthService.instance.userName ??
        AuthService.instance.currentToken?.nombre ??
        '';
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
