import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../../models/edan.dart';
import '../../../models/usuario.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/database_helper.dart';
import '../../../services/edan/edan_envio_v2.dart';
import '../../../services/edan/edan_localidades_envio_v2_service.dart';
import '../../../services/edan/edan_store_v2.dart';
import '../../../services/edan/edan_motivo_backfill.dart';
import '../../../services/edan_secciones_registry.dart';
import '../../../services/edan_sync_service.dart';
import 'ugr_edan_preview_screen.dart';
import 'ugr_evento.dart';
import 'ugr_route.dart';
import '../resp/edan/edan_form_wizard.dart';
import '../resp/edan/edan_dialog_helper.dart';
import '../resp/edan/edan_preview_resp_screen.dart';
import '../../../widgets/edan_galeria_view.dart';
import '../../../widgets/edan_json_preview_dialog.dart';
import '../../../widgets/edan_motivo_rechazo.dart';
import '../../../services/app_logger_ui.dart';

enum _VistaLocalidades { todos, sinConsolidar, consolidadas, galeria }

class UgrLocalidadesTab extends StatefulWidget {
  final VoidCallback? onVistaChanged;
  final VoidCallback? onConsolidado;
  final VoidCallback? onNavigateToEdan;
  const UgrLocalidadesTab({super.key, this.onVistaChanged, this.onConsolidado, this.onNavigateToEdan});

  @override
  State<UgrLocalidadesTab> createState() => UgrLocalidadesTabState();

  /// Dedup del merge server+SQLite: devuelve las localidades [locales] que NO
  /// están ya en [servidor]. Compara por `id_edan_localidad` numérico **y** por
  /// identidad uuid (`uuid_edan_localidad ?? id_local`), para que un EDAN propio
  /// ya sincronizado no aparezca duplicado cuando el `idServer` local aún no se
  /// retro-trajo del servidor (o viceversa).
  static List<EdanLocalidad> sinDuplicadas(
    List<EdanLocalidad> servidor,
    List<EdanLocalidad> locales,
  ) {
    String clave(EdanLocalidad l) => l.uuidEdanLocalidad ?? l.idLocal ?? '';
    final vistosIds = servidor.map((l) => l.idServer).whereType<int>().toSet();
    final vistosUuid = servidor.map(clave).where((s) => s.isNotEmpty).toSet();
    return locales.where((l) {
      final dupId = l.idServer != null && vistosIds.contains(l.idServer);
      final k = clave(l);
      final dupUuid = k.isNotEmpty && vistosUuid.contains(k);
      return !dupId && !dupUuid;
    }).toList();
  }
}

class UgrLocalidadesTabState extends State<UgrLocalidadesTab>
    with WidgetsBindingObserver {
  List<EdanLocalidad> _localidades = [];
  Map<String, dynamic>? _resumen;
  bool _cargando = true;
  String? _error;
  String _query = '';
  bool _modoConsolidacion = false;
  final Set<int> _seleccionadas = {};
  _VistaLocalidades _vistaActual = _VistaLocalidades.todos;

  /// La galería es un widget propio con su estado/carga; esta clave permite
  /// refrescarla cuando `ugr_screen` llama a `refresh()` (cambio de pestaña,
  /// tras consolidar, etc.).
  final GlobalKey<EdanGaleriaViewState> _galeriaKey =
      GlobalKey<EdanGaleriaViewState>();

  void refresh() {
    _cargarDatos();
    _galeriaKey.currentState?.refresh();
  }

  bool get mostrarFabConsolidar =>
      !_modoConsolidacion &&
      _vistaActual != _VistaLocalidades.galeria &&
      (_vistaActual == _VistaLocalidades.sinConsolidar || _vistaActual == _VistaLocalidades.todos) &&
      _localidades.where((l) => l.idEdan == null || l.idEdan == 0).isNotEmpty;

  /// La vista actual es la Galería de fotos del municipio: `ugr_screen` usa
  /// esto para ocultar sus FABs (consolidar/crear no aplican a las fotos).
  bool get vistaGaleria => _vistaActual == _VistaLocalidades.galeria;

  /// Modo consolidación activo (con checks): `ugr_screen` oculta el FAB de
  /// crear mientras dura, y `PopScope` usa el estado para el botón atrás.
  bool get modoConsolidacion => _modoConsolidacion;

  void activarConsolidacion() => _activarModoConsolidacion();

  int? get _idMunicipio => AuthService.instance.currentToken?.idMunicipio;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargarDatos();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _cargarDatos();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    final municipioId = _idMunicipio;
    if (municipioId == null) {
      if (mounted) setState(() { _cargando = false; _error = null; });
      return;
    }
    if (!ConnectivityService().isConnected) {
      final userId = AuthService.instance.userId;
      if (userId != null) {
        try {
          final locales = await _cargarLocalidadesLocales(userId);
          await _resincronizarBadges(locales);
          if (mounted) {
            setState(() {
              _localidades = locales;
              _cargando = false;
              _error = null;
            });
          }
        } catch (_) {
          if (mounted) {
            setState(() { _cargando = false; _error = 'Sin conexión a internet'; });
          }
        }
      } else {
        if (mounted) setState(() { _cargando = false; _error = 'Sin conexión a internet'; });
      }
      return;
    }
    try {
      setState(() { _error = null; });
      final resultados = await Future.wait([
        ApiService.instance.getLocalidadesMunicipio(municipioId),
        ApiService.instance.getResumenLocalidades(municipioId),
        ApiService.instance.getLocalidadesEstado(),
      ]);
      final data = resultados[0] as List<Map<String, dynamic>>;
      final resumen = resultados[1] as Map<String, dynamic>;
      final estadosData = resultados[2] as List<Map<String, dynamic>>;
      UgrLocalidadEstadoX.updateDescripciones(estadosData);
      final localidades =
          data.map((j) => EdanLocalidad.fromJson(j)).toList();

      final userId = AuthService.instance.userId;
      if (userId != null) {
        try {
          final locales = await _cargarLocalidadesLocales(userId);
          localidades.addAll(UgrLocalidadesTab.sinDuplicadas(localidades, locales));
        } catch (_) {}
      }

      await _resincronizarBadges(localidades);

      // Más reciente arriba por FECHA DE LLENADO (sin llenado: por modificación).
      localidades.sort(compararRecientePrimero);
      if (mounted) {
        setState(() {
          _localidades = localidades;
          _resumen = resumen;
          _cargando = false;
          _error = null;
        });
      }
      // Rechazos cuya fila del servidor no trajo motivo: retro-traerlo y
      // repintar la tarjeta (online, max 10/pasada, silencioso).
      if (await EdanMotivoBackfill.ejecutar(localidades)) {
        if (mounted) setState(() {});
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = ApiService.traducirError(e);
        });
      }
    }
  }

  /// Consolidable = entra en la dinámica del checkbox: aprobado por el UGR,
  /// aún sin EDAN y (si ya hay algo seleccionado) del MISMO tipo de evento
  /// que la selección — el servidor solo consolida un EDAN por evento.
  bool _esConsolidable(EdanLocalidad l) {
    if (l.estadoLocalidad != UgrLocalidadEstado.aprobadoUgr) return false;
    if (l.idEdan != null && l.idEdan != 0) return false;
    final tipo = _tipoEventoSeleccionado;
    if (tipo != null && l.idTipoEvento != null && l.idTipoEvento != tipo) {
      return false;
    }
    return true;
  }

  List<EdanLocalidad> get _filtradas {
    var list = _localidades;

    if (_modoConsolidacion) {
      // En modo consolidación SOLO se muestran las localidades que pueden
      // marcarse con el check: el resto es ruido y confunde.
      list = list.where(_esConsolidable).toList();
    } else if (_vistaActual == _VistaLocalidades.sinConsolidar) {
      list = list.where((l) => l.idEdan == null || l.idEdan == 0).toList();
    } else if (_vistaActual == _VistaLocalidades.consolidadas) {
      list = list.where((l) => l.idEdan != null && l.idEdan! > 0).toList();
    }

    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((l) {
        final nombre = l.nombre.toLowerCase();
        final tipo = (l.tipoEventoNombre ?? '').toLowerCase();
        final usuario = l.usuario?.nombre.toLowerCase() ?? '';
        return nombre.contains(q) || tipo.contains(q) || usuario.contains(q);
      }).toList();
    }

    // Más reciente arriba por FECHA DE LLENADO (sin llenado: por modificación).
    list.sort(compararRecientePrimero);

    return list;
  }

  int? get _tipoEventoSeleccionado {
    if (_seleccionadas.isEmpty) return null;
    for (final l in _localidades) {
      if (_seleccionadas.contains(l.idServer) && l.idTipoEvento != null) {
        return l.idTipoEvento;
      }
    }
    return null;
  }

  void _toggleSeleccion(int? idServer) {
    if (idServer == null) return;
    final localidad = _localidades.firstWhere((l) => l.idServer == idServer);
    final esAprobada = localidad.estadoLocalidad == UgrLocalidadEstado.aprobadoUgr;
    final esHuerfana = localidad.idEdan == null || localidad.idEdan == 0;
    if (!esAprobada || !esHuerfana) return;

    setState(() {
      if (_seleccionadas.contains(idServer)) {
        _seleccionadas.remove(idServer);
      } else {
        if (_seleccionadas.isEmpty) {
          _seleccionadas.add(idServer);
        } else {
          final tipoActual = _tipoEventoSeleccionado;
          if (localidad.idTipoEvento == tipoActual) {
            _seleccionadas.add(idServer);
          } else {
            showAppSnackBar(context, 
              const SnackBar(
                content: Text('Solo puede consolidar localidades del mismo tipo de evento'),
                backgroundColor: AppColors.pending,
              ),
            );
          }
        }
      }
    });
  }

  void _activarModoConsolidacion() {
    final aprobadas = _localidades.where((l) =>
        l.estadoLocalidad == UgrLocalidadEstado.aprobadoUgr &&
        (l.idEdan == null || l.idEdan == 0)).toList();
    if (aprobadas.isEmpty) {
      showAppSnackBar(context, 
        const SnackBar(
          content: Text('No hay localidades aprobadas sin consolidar para consolidar'),
          backgroundColor: AppColors.pending,
        ),
      );
      return;
    }
    setState(() {
      _modoConsolidacion = true;
      _seleccionadas.clear();
    });
    // El padre (ugr_screen) debe reconstruirse: oculta el FAB de crear y
    // re-evalua su PopScope del boton atras.
    widget.onVistaChanged?.call();
  }

  void _cancelarModoConsolidacion() {
    setState(() {
      _modoConsolidacion = false;
      _seleccionadas.clear();
    });
    widget.onVistaChanged?.call();
  }

  Future<void> _vistaPreviaConsolidacion() async {
    if (_seleccionadas.isEmpty) return;
    final seleccionadasList = _localidades
        .where((l) => _seleccionadas.contains(l.idServer))
        .toList();
    if (seleccionadasList.isEmpty) return;

    final tipoEvento = seleccionadasList.first.tipoEventoNombre ?? '';
    final totalPoblacion = seleccionadasList.fold<int>(
        0, (sum, l) => sum + l.totalPoblacionAfectada);
    final totalFamilias = seleccionadasList.fold<int>(
        0, (sum, l) => sum + l.totalFamiliasAfectadas);
    final totalDamnificadas = seleccionadasList.fold<int>(
        0, (sum, l) => sum + l.totalFamiliasDamnificadas);

    final edan = Edan(
      idDepartamento: seleccionadasList.first.idDepartamento,
      idProvincia: seleccionadasList.first.idProvincia,
      idMunicipio: seleccionadasList.first.idMunicipio,
      idTipoEvento: seleccionadasList.first.idTipoEvento,
      tipoEventoNombre: tipoEvento,
      fechaLlenado: seleccionadasList.first.fechaLlenado ?? '',
      fechaEvento: seleccionadasList.first.fechaEvento ?? '',
      horaEvento: seleccionadasList.first.horaEvento ?? '',
      totalPoblacionAfectada: totalPoblacion,
      totalFamiliasAfectadas: totalFamilias,
      totalFamiliasDamnificadas: totalDamnificadas,
      localidades: seleccionadasList,
      estado: 'aprobado ugr',
      idEstado: 3,
      esBorrador: false,
    );

    final confirmado = await Navigator.of(context).push<bool>(
      ugrRoute(UgrEdanPreviewScreen(edan: edan)),
    );

    if (confirmado == true && mounted) {
      await _consolidar(seleccionadasList);
    }
  }

  Future<void> _consolidar(List<EdanLocalidad> seleccionadas) async {
    final municipioId = _idMunicipio;
    if (municipioId == null) return;
    if (!ConnectivityService().isConnected) {
      if (mounted) {
        showAppSnackBar(context, 
          const SnackBar(content: Text('Sin conexión. Verifica tu red y reintenta.'), backgroundColor: AppColors.pending),
        );
      }
      return;
    }
    final idTipoEvento = seleccionadas.first.idTipoEvento;
    if (idTipoEvento == null) return;
    final localidadIds =
        seleccionadas.where((l) => l.idServer != null).map((l) => l.idServer!).toList();
    try {
      final edanData = await ApiService.instance.consolidar(
        idMunicipio: municipioId,
        idTipoEvento: idTipoEvento,
        localidadIds: localidadIds,
      );
      if (mounted) {
        final edan = Edan.fromJson(edanData);
        final usuarioId = AuthService.instance.currentToken?.userId;
        if (usuarioId != null) {
          final idLocal = await DatabaseHelper.instance.insertEdan(edan, usuarioId: usuarioId);
          final serverId = edan.idEdan ?? edan.idServer;
          if (idLocal > 0 && serverId != null) {
            await DatabaseHelper.instance.markEdanAsSynced(idLocal, serverId);
          }
          EdanSyncService.instance.recargarEdansMunicipio(
            idMunicipio: municipioId,
            usuarioId: usuarioId,
          );
        }
        showAppSnackBar(context, 
          const SnackBar(
            content: Text('EDAN consolidado correctamente'),
            backgroundColor: AppColors.aprobado,
          ),
        );
        _cancelarModoConsolidacion();
        _cargarDatos();
        widget.onConsolidado?.call();
        widget.onNavigateToEdan?.call();
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 
          SnackBar(content: Text('Error al consolidar: ${ApiService.traducirError(e)}'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _cambiarEstado(EdanLocalidad localidad, int nuevoEstado) async {
    final idLocalidad = localidad.idServer;
    if (idLocalidad == null) return;

    final estado = UgrLocalidadEstadoX.fromId(nuevoEstado);
    final esAprobar = estado == UgrLocalidadEstado.aprobadoUgr;
    final esRechazar = estado == UgrLocalidadEstado.rechazadoUgr;
    final accion = esAprobar ? 'Aprobar' : 'Rechazar';
    final color = estado.color;

    // Rechazar: el servidor EXIGE motivo (`observacion_estado`, 422 si
    // falta). El dialogo de motivo hace las veces de confirmacion.
    String? motivo;
    final bool confirmado;
    if (esRechazar) {
      motivo = await pedirMotivoRechazo(context);
      confirmado = motivo != null;
    } else {
      confirmado = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(
            esAprobar ? Icons.check_circle : Icons.cancel,
            size: 48,
            color: color,
          ),
          title: Text('$accion localidad'),
          content: Text(
            '¿Está seguro de que desea $accion esta localidad?',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: color),
              child: Text(accion),
            ),
          ],
        ),
      ) ??
          false;
    }
    // El setState/llamada que sigue debe correr DESPUES del teardown de la
    // ruta del dialogo (pop + continuacion en el mismo frame disparaban el
    // assert `_dependents.isEmpty`).
    await WidgetsBinding.instance.endOfFrame;
    if (confirmado != true || !mounted) return;

    if (!ConnectivityService().isConnected) {
      if (mounted) {
        showAppSnackBar(context, 
          const SnackBar(content: Text('Sin conexión. Verifica tu red y reintenta.'), backgroundColor: AppColors.pending),
        );
      }
      return;
    }
    try {
      await ApiService.instance.cambiarEstadoLocalidad(idLocalidad, nuevoEstado,
          observacion: motivo);
      if (esRechazar) {
        localidad.observacionEstado = motivo?.trim();
      }
      if (mounted) {
        showAppSnackBar(context, 
          SnackBar(
            content: Text('Estado cambiado a ${estado.label}'),
            backgroundColor: estado.color,
          ),
        );
        _cargarDatos();
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 
          SnackBar(content: Text(ApiService.traducirError(e)), backgroundColor: AppColors.error),
        );
      }
    }
  }

  /// Localidades disponibles en este dispositivo (offline): las que el wizard
  /// escribió en `localidades_offline` MÁS las recuperadas por el pull V2 en
  /// `formularios`. El mismo reporte puede estar en ambas tablas y comparte
  /// `idLocal` (uuid), así que se deduplica por ese id. Sin esto, un UGR que
  /// recupera sus reportes en un celular nuevo (pull V2) los vería solo online
  /// y no aparecerían al quedarse sin red.
  Future<List<EdanLocalidad>> _cargarLocalidadesLocales(int userId) async {
    final locales = <String, EdanLocalidad>{};
    final propias = await DatabaseHelper.instance.getLocalidades(userId);
    for (final l in propias) {
      final id = l.idLocal;
      if (id != null) locales[id] = l;
    }
    try {
      final v2 = await EdanStoreV2.instance.listarFormularios(usuarioId: userId);
      for (final l in v2) {
        final id = l.idLocal;
        if (id != null) locales[id] = l;
      }
    } catch (_) {}
    return locales.values.toList();
  }

  /// Resincroniza los flags `imp_*` desde `localidad_secciones_activas`
  /// (fuente autoritativa) o, si no hay fila local/secciones, desde los datos
  /// cargados en el modelo (unión con los gruesos del server/doc). Mismo
  /// proceso que los items RESP (sección 9.11): los badges del ítem reflejan
  /// lo realmente informado, aunque el flag grueso del documento esté viejo.
  Future<void> _resincronizarBadges(List<EdanLocalidad> localidades) async {
    if (localidades.isEmpty) return;
    final sincV2 = EdanLocalidadesEnvioV2Service();
    for (final loc in localidades) {
      await sincV2.aplicarFlagsDesdeSeccionesActivas(loc,
          unionConGuardados: true);
      // Paridad con el tab de RESP: los grupos gruesos (`grup_*`) confirmados
      // por el servidor se re-ORAN sobre el modelo, para que los badges del
      // ítem reflejen lo que el server tiene aunque el flag local esté viejo.
      await EdanStoreV2.instance.aplicarGruposServidorAlModelo(loc);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return PopScope(
      // Botón atrás físico: si hay modo consolidación activo, lo primero que
      // hace es salir de los checks (sin irse de la pantalla); solo cuando ya
      // no se está consolidando deja pasar el pop normal.
      canPop: !_modoConsolidacion,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancelarModoConsolidacion();
      },
      child: Column(
        children: [
          if (_resumen != null) _buildResumen(primary),
          if (_modoConsolidacion) _buildConsolidacionBar(primary),
          if (!_modoConsolidacion &&
              _error == null &&
              _vistaActual != _VistaLocalidades.galeria)
            _buildSearchField(primary),
          Expanded(
            child: _vistaActual == _VistaLocalidades.galeria
                ? _buildGaleria()
                : _error != null && _localidades.isEmpty
                    ? _buildErrorState(primary)
                    : _buildGroupedList(primary),
          ),
        ],
      ),
    );
  }

  /// Galería de fotos del municipio (widget compartido con el rol 7): todas
  /// las localidades del UGR, con el responsable de cada una, coordenadas de
  /// la fila dueña sobre cada miniatura y visor con zoom + compartir.
  Widget _buildGaleria() {
    final muni = _idMunicipio;
    if (muni == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'El usuario no tiene municipio asignado',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return EdanGaleriaView(
      key: _galeriaKey,
      showAutor: true,
      carga: () => EdanStoreV2.instance
          .listarFotosGaleriaPorMunicipio(idMunicipio: muni),
    );
  }

  Widget _buildErrorState(Color primary) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 56, color: AppColors.error.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            const Text(
              'Verifica tu conexión a internet',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                setState(() { _cargando = true; _error = null; });
                _cargarDatos();
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumen(Color primary) {
    final r = _resumen!;
    final total = r['total'] ?? 0;
    final huerfanas = r['huerfanas'] ?? r['total_huerfanas'] ?? 0;
    final consolidadas = r['consolidadas'] ?? r['total_consolidadas'] ?? 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _vistaActual = _VistaLocalidades.todos;
                      _modoConsolidacion = false;
                      _seleccionadas.clear();
                    });
                    widget.onVistaChanged?.call();
                  },
                  child: _ResumenChip(
                    label: 'Total',
                    value: '$total',
                    color: primary,
                    highlighted: _vistaActual == _VistaLocalidades.todos,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _vistaActual = _VistaLocalidades.sinConsolidar;
                      _modoConsolidacion = false;
                      _seleccionadas.clear();
                    });
                    widget.onVistaChanged?.call();
                  },
                  child: _ResumenChip(
                    label: 'Sin consolidar',
                    value: '$huerfanas',
                    color: AppColors.pending,
                    highlighted: _vistaActual == _VistaLocalidades.sinConsolidar,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _vistaActual = _VistaLocalidades.consolidadas;
                      _modoConsolidacion = false;
                      _seleccionadas.clear();
                    });
                    widget.onVistaChanged?.call();
                  },
                  child: _ResumenChip(
                    label: 'Consolidadas',
                    value: '$consolidadas',
                    color: AppColors.aprobado,
                    highlighted: _vistaActual == _VistaLocalidades.consolidadas,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // No es un filtro: es la OTRA vista del tab (fotos del
              // municipio con su responsable). Mismo gesto de cambio de vista.
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _vistaActual = _VistaLocalidades.galeria;
                      _modoConsolidacion = false;
                    });
                    widget.onVistaChanged?.call();
                  },
                  child: _ResumenChip(
                    label: 'Galería',
                    value: '📷',
                    color: Colors.teal,
                    highlighted:
                        _vistaActual == _VistaLocalidades.galeria,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(Color primary) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      color: AppColors.surface,
      child: TextField(
        onChanged: (value) => setState(() => _query = value),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Buscar por nombre, tipo o responsable...',
          prefixIcon: const Icon(Icons.search, size: 18),
          isDense: true,
          filled: true,
          fillColor: PaletteScope.of(context).background,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
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

  Widget _buildGroupedList(Color primary) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    final list = _filtradas;

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_on_outlined, size: 64, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              _modoConsolidacion
                  ? 'No hay más localidades consolidables con la selección actual'
                  : _query.isNotEmpty
                      ? 'Sin resultados'
                      : _vistaActual == _VistaLocalidades.sinConsolidar
                          ? 'No hay localidades sin consolidar'
                          : _vistaActual == _VistaLocalidades.consolidadas
                              ? 'No hay localidades consolidadas'
                              : 'No hay localidades',
              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_vistaActual == _VistaLocalidades.todos) {
      return _buildGroupedListTodos(list, primary);
    }

    final Map<String, List<EdanLocalidad>> grupos = {};
    for (final l in list) {
      final key = l.tipoEventoNombre ?? 'Otro evento';
      grupos.putIfAbsent(key, () => []).add(l);
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _cargarDatos,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
            itemCount: grupos.length,
            itemBuilder: (context, index) {
              final entries = grupos.entries.toList();
              final nombreEvento = entries[index].key;
              final localidadesGrupo = entries[index].value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildGrupoHeader(nombreEvento, localidadesGrupo.length, primary),
                  ...localidadesGrupo.map((localidad) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildLocalidadItem(localidad, primary),
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGroupedListTodos(List<EdanLocalidad> list, Color primary) {
    final sinConsolidar = list.where((l) => l.idEdan == null || l.idEdan == 0).toList();
    final consolidadas = list.where((l) => l.idEdan != null && l.idEdan! > 0).toList();

    final Map<String, List<EdanLocalidad>> gruposSin = {};
    for (final l in sinConsolidar) {
      final key = l.tipoEventoNombre ?? 'Otro evento';
      gruposSin.putIfAbsent(key, () => []).add(l);
    }

    final Map<String, List<EdanLocalidad>> gruposCon = {};
    for (final l in consolidadas) {
      final key = l.tipoEventoNombre ?? 'Otro evento';
      gruposCon.putIfAbsent(key, () => []).add(l);
    }

    final items = <_GroupedListEntry>[];
    if (gruposSin.isNotEmpty) {
      items.add(_GroupedListEntry.section('Sin consolidar', AppColors.pending, sinConsolidar.length));
      for (final e in gruposSin.entries) {
        items.add(_GroupedListEntry.group(e.key, e.value));
      }
    }
    if (gruposCon.isNotEmpty) {
      items.add(_GroupedListEntry.section('Consolidadas', AppColors.aprobado, consolidadas.length));
      for (final e in gruposCon.entries) {
        items.add(_GroupedListEntry.group(e.key, e.value));
      }
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _cargarDatos,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              if (item.isSection) {
                return _buildSeccionHeader(item.sectionLabel!, item.sectionColor!, primary, item.count);
              }
              final localidadesGrupo = item.localidades!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildGrupoHeader(item.groupName!, localidadesGrupo.length, primary),
                  ...localidadesGrupo.map((localidad) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildLocalidadItem(localidad, primary),
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSeccionHeader(String label, Color color, Color primary, [int? count]) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.7),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGrupoHeader(String nombreEvento, int count, Color primary) {
    final IconData icon = ugrEventoIcon(nombreEvento);
    final Color color = ugrEventoColor(nombreEvento, primary);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              nombreEvento,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalidadItem(EdanLocalidad localidad, Color primary) {
    final esAprobada = localidad.estadoLocalidad == UgrLocalidadEstado.aprobadoUgr;
    final esHuerfana = localidad.idEdan == null || localidad.idEdan == 0;
    final seleccionable = _modoConsolidacion && esAprobada && esHuerfana;
    final esBorrador = localidad.estadoLocalidad == UgrLocalidadEstado.borrador;
    final esMia = localidad.idUsuario == AuthService.instance.userId;
    return _LocalidadCard(
      localidad: localidad,
      primary: primary,
      usuario: localidad.usuario,
      impactos: EdanSeccionesRegistry.seccionesActivasLabelsCortos(localidad),
      modoConsolidacion: _modoConsolidacion,
      seleccionada: _seleccionadas.contains(localidad.idServer),
      seleccionable: seleccionable,
      onToggleSeleccion: () => _toggleSeleccion(localidad.idServer),
      onTap: () => _verDetalle(localidad),
      onAprobar: localidad.estadoLocalidad == UgrLocalidadEstado.enRevisionUgr
          ? () => _cambiarEstado(localidad, UgrLocalidadEstado.aprobadoUgr.id)
          : null,
      onRechazar: localidad.estadoLocalidad == UgrLocalidadEstado.enRevisionUgr
          ? () => _cambiarEstado(localidad, UgrLocalidadEstado.rechazadoUgr.id)
          : null,
      // Editar: borradores propios y TAMBIEN rechazados (la correccion del
      // rechazo se hace desde el propio listado, offline-first).
      onEdit: (esBorrador ||
                  localidad.estadoLocalidad ==
                      UgrLocalidadEstado.rechazadoUgr) &&
              esMia
          ? () => _editarLocalidad(localidad)
          : null,
      onDelete: esBorrador && esMia
          ? () => _eliminarLocalidad(localidad)
          : null,
      onLongPress: () => EdanJsonPreviewDialog.show(context, localidad),
    );
  }

  Future<void> _verDetalle(EdanLocalidad localidad) async {
    try {
      if (!mounted) return;
      if (localidad.estadoLocalidad == UgrLocalidadEstado.enviadoUgr &&
          localidad.idServer != null &&
          ConnectivityService().isConnected) {
        try {
          await ApiService.instance.cambiarEstadoLocalidad(
            localidad.idServer!,
            UgrLocalidadEstado.enRevisionUgr.id,
          );
          localidad.estadoLocalidad = UgrLocalidadEstado.enRevisionUgr;
        } catch (_) {}
      }
      if (!mounted) return;
      final estado = localidad.estadoLocalidad;
      final esAprobada = estado == UgrLocalidadEstado.aprobadoUgr ||
          estado == UgrLocalidadEstado.aprobadoAjuste;
      final esRechazada = estado == UgrLocalidadEstado.rechazadoUgr;

      // Si el reporte no está descargado localmente (p.ej. localidades de OTROS
      // usuarios del municipio), se pide el documento completo al servidor para
      // que la vista previa muestre las secciones y las FOTOS online
      // (`Image.network`). Para los reportes propios ya descargados se conserva
      // la copia local (permite verlos sin conexión y con fotos ya bajadas).
      EdanLocalidad docPreview = localidad;
      final uuidLocal = localidad.uuidEdanLocalidad ?? localidad.idLocal;
      final tieneLocalV2 = uuidLocal != null &&
          await EdanStoreV2.instance.cargarFormulario(uuidLocal) != null;
      if (!tieneLocalV2 &&
          ConnectivityService().isConnected &&
          localidad.idServer != null) {
        // APIs nuevas: `GET /formularios/{id}/completo` (cabecera 14 `imp_*` +
        // nodo `grupos` + 14 secciones + fotos). Sustituye al
        // `GET /localidades/{id}/documento` del grupo legado.
        final descargado = await EdanEnvioV2.descargar(
          localidad.idServer!.toString(),
          useId: true,
        );
        if (descargado != null) docPreview = descargado;
      }
      if (!mounted) return;

      final cambio = await Navigator.of(context).push<bool>(
        ugrRoute(EdanPreviewRespScreen(
          localidad: docPreview,
          modoUGR: true,
          onAprobar: esAprobada
              ? null
              : () async {
                  await ApiService.instance.cambiarEstadoLocalidad(
                    localidad.idServer!,
                    UgrLocalidadEstado.aprobadoUgr.id,
                  );
                  localidad.estadoLocalidad = UgrLocalidadEstado.aprobadoUgr;
                },
          onRechazar: (esAprobada || esRechazada)
              ? null
              : () async {
                  // El server exige motivo (observacion_estado) para rechazar.
                  final motivo = await pedirMotivoRechazo(context);
                  if (motivo == null) return;
                  // Continuar tras el teardown del dialogo (assert
                  // _dependents.isEmpty si se sigue en el mismo frame).
                  await WidgetsBinding.instance.endOfFrame;
                  await ApiService.instance.cambiarEstadoLocalidad(
                    localidad.idServer!,
                    UgrLocalidadEstado.rechazadoUgr.id,
                    observacion: motivo,
                  );
                  localidad.estadoLocalidad = UgrLocalidadEstado.rechazadoUgr;
                  localidad.observacionEstado = motivo;
                },
        ), palette: Palettes.rea),
      );
      if (mounted) {
        if (cambio == true) {
          await _cargarDatos();
        } else {
          setState(() {});
        }
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 
          SnackBar(content: Text(ApiService.traducirError(e)), backgroundColor: AppColors.error),
        );
      }
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
      await _cargarDatos();
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

    final db = DatabaseHelper.instance;
    final conectado = await ConnectivityService().checkNow();
    try {
      if (localidad.sincronizado && localidad.idServer != null && conectado) {
        // API nueva: `DELETE /api/v2/edan/formularios/{uuid_ref}` (cascada de
        // secciones, viviendas y fotos en el servidor). Sustituye al
        // `DELETE /localidades/{id}/documento` del grupo legado.
        final ref = localidad.uuidEdanLocalidad ??
            localidad.idLocal ??
            localidad.idServer!.toString();
        if (await EdanEnvioV2.borrar(ref)) {
          await db.deleteLocalidad(idLocal);
        } else {
          // Rechazada o micro-corte: se marca para el próximo `sincronizar()`,
          // así el borrado no se pierde ni queda la copia local colgando.
          await db.markLocalidadAsPendingDeletion(idLocal);
        }
        if (!mounted) return;
        showAppSnackBar(context, 
          const SnackBar(
            content: Text('Localidad eliminada del servidor'),
            backgroundColor: AppColors.aprobado,
          ),
        );
      } else if (localidad.sincronizado) {
        await db.markLocalidadAsPendingDeletion(idLocal);
        if (!mounted) return;
        showAppSnackBar(context, 
          const SnackBar(
            content: Text('Localidad marcada para eliminación. Se borrará al sincronizar.'),
            backgroundColor: AppColors.pending,
          ),
        );
      } else {
        await db.deleteLocalidad(idLocal);
        if (!mounted) return;
        showAppSnackBar(context, 
          const SnackBar(
            content: Text('Localidad eliminada'),
            backgroundColor: AppColors.aprobado,
          ),
        );
      }
      await _cargarDatos();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, 
        SnackBar(
          content: Text('Error al eliminar: $e'),
          backgroundColor: AppColors.rechazado,
        ),
      );
    }
  }

  /// Barra del modo consolidación: tarjeta compacta.
  ///
  /// Cabecera con icono + título 'Modo consolidación' + subtítulo de estado
  /// (dos líneas propias con todo el ancho: 'Seleccione localidades
  /// aprobadas' ya no se parte palabra por palabra) y ✕ de salida. Cuerpo: la
  /// única acción ('Vista previa EDAN') alineada a la derecha — sin caja
  /// 'Cancelar' que recortaba la palabra; para salir están el ✕, el botón
  /// atrás del sistema y los chips de vista.
  Widget _buildConsolidacionBar(Color primary) {
    final count = _seleccionadas.length;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      width: double.infinity,
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primary.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.layers, size: 16, color: primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Modo consolidación',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      count == 0
                          ? 'Toca las localidades aprobadas'
                          : '$count seleccionada${count == 1 ? '' : 's'} · '
                              'mismo evento',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Salir del modo consolidar',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close,
                    size: 20, color: AppColors.textSecondary),
                onPressed: _cancelarModoConsolidacion,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: count >= 1 ? _vistaPreviaConsolidacion : null,
              icon: const Icon(Icons.preview, size: 16),
              label: const Text('Vista previa EDAN',
                  style: TextStyle(fontSize: 12.5)),
              style: FilledButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.divider,
                disabledForegroundColor: AppColors.textSecondary,
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumenChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool highlighted;
  const _ResumenChip({required this.label, required this.value, required this.color, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: highlighted ? color.withValues(alpha: 0.18) : color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlighted ? color.withValues(alpha: 0.6) : color.withValues(alpha: 0.2),
          width: highlighted ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
          // Con 4 chips el ancho por chip es ~80dp: sin FittedBox, etiquetas
          // largas ('Sin consolidar') partían en dos líneas y la fila de
          // contadores quedaba desalineada.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                  fontSize: 10, color: color.withValues(alpha: 0.7)),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupedListEntry {
  final bool isSection;
  final String? sectionLabel;
  final Color? sectionColor;
  final int? count;
  final String? groupName;
  final List<EdanLocalidad>? localidades;

  _GroupedListEntry.section(this.sectionLabel, this.sectionColor, [this.count])
      : isSection = true,
        groupName = null,
        localidades = null;

  _GroupedListEntry.group(this.groupName, this.localidades)
      : isSection = false,
        sectionLabel = null,
        sectionColor = null,
        count = null;
}

class _LocalidadCard extends StatelessWidget {
  final EdanLocalidad localidad;
  final Color primary;
  final Usuario? usuario;
  final List<String> impactos;
  final bool modoConsolidacion;
  final bool seleccionada;
  final bool seleccionable;
  final VoidCallback onToggleSeleccion;
  final VoidCallback onTap;
  final VoidCallback? onAprobar;
  final VoidCallback? onRechazar;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onLongPress;

  const _LocalidadCard({
    required this.localidad,
    required this.primary,
    this.usuario,
    required this.impactos,
    required this.modoConsolidacion,
    required this.seleccionada,
    required this.seleccionable,
    required this.onToggleSeleccion,
    required this.onTap,
    this.onAprobar,
    this.onRechazar,
    this.onEdit,
    this.onDelete,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final estado = localidad.estadoLocalidad ?? UgrLocalidadEstado.borrador;
    final tipoEvento = localidad.tipoEventoNombre ?? 'Sin tipo';
    final nombre = localidad.nombre.isNotEmpty ? localidad.nombre : 'Sin nombre';
    final tipoLocalidad = localidad.tipoLocalidad;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: modoConsolidacion && seleccionable ? onToggleSeleccion : onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (modoConsolidacion && seleccionable)
                    Checkbox(
                      value: seleccionada,
                      onChanged: (_) => onToggleSeleccion(),
                      activeColor: primary,
                    ),
                  Expanded(
                    child: Text(
                      tipoLocalidad.isNotEmpty ? '$tipoLocalidad: $nombre' : nombre,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildSmallBadge(estado),
                  if (localidad.idServer == null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Pendiente',
                        style: TextStyle(fontSize: 10, color: Colors.orange.shade800),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.warning_amber, size: 14, color: AppColors.pending),
                  const SizedBox(width: 4),
                  Text(
                    tipoEvento,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.calendar_today, size: 12, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    localidad.fechaEvento ?? 'Sin fecha',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
              if (usuario != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Reportado por: ${usuario!.nombre}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              EdanMotivoRechazo(localidad: localidad),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.people, size: 12, color: AppColors.textSecondary),
                  const SizedBox(width: 3),
                  Text('${localidad.totalPoblacionAfectada}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(width: 10),
                  const Icon(Icons.home, size: 12, color: AppColors.textSecondary),
                  const SizedBox(width: 3),
                  Text('${localidad.totalFamiliasAfectadas} fam', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  if (localidad.totalFamiliasDamnificadas > 0) ...[
                    const SizedBox(width: 10),
                    const Icon(Icons.warning, size: 11, color: AppColors.rechazado),
                    const SizedBox(width: 3),
                    Text('${localidad.totalFamiliasDamnificadas} damn', style: const TextStyle(fontSize: 12, color: AppColors.rechazado)),
                  ],
                ],
              ),
              if (impactos.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: impactos.map((imp) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(imp, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: primary)),
                  )).toList(),
                ),
              ],
              if (!modoConsolidacion && (onAprobar != null || onRechazar != null)) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (onRechazar != null)
                      _buildActionButton(
                        icon: Icons.close,
                        label: 'Rechazar',
                        color: AppColors.rechazado,
                        onTap: onRechazar!,
                      ),
                    if (onRechazar != null && onAprobar != null) const SizedBox(width: 8),
                    if (onAprobar != null)
                      _buildActionButton(
                        icon: Icons.check,
                        label: 'Aprobar',
                        color: AppColors.aprobado,
                        onTap: onAprobar!,
                      ),
                  ],
                ),
              ],
              if (!modoConsolidacion && (onEdit != null || onDelete != null)) ...[
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
                    if (onEdit != null && onDelete != null) const SizedBox(width: 8),
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
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
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
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
