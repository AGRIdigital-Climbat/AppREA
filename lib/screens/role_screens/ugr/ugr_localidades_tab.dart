import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../../models/edan.dart';
import '../../../models/usuario.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/database_helper.dart';
import '../../../services/edan/edan_localidades_envio_v2_service.dart';
import '../../../services/edan_secciones_registry.dart';
import '../../../services/edan_sync_service.dart';
import 'ugr_edan_preview_screen.dart';
import 'ugr_evento.dart';
import 'ugr_route.dart';
import '../resp/edan/edan_form_wizard.dart';
import '../resp/edan/edan_preview_resp_screen.dart';
import '../../../widgets/edan_json_preview_dialog.dart';

enum _VistaLocalidades { todos, sinConsolidar, consolidadas }

class UgrLocalidadesTab extends StatefulWidget {
  final VoidCallback? onVistaChanged;
  final VoidCallback? onConsolidado;
  final VoidCallback? onNavigateToEdan;
  const UgrLocalidadesTab({super.key, this.onVistaChanged, this.onConsolidado, this.onNavigateToEdan});

  @override
  State<UgrLocalidadesTab> createState() => UgrLocalidadesTabState();
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

  void refresh() => _cargarDatos();

  bool get mostrarFabConsolidar =>
      !_modoConsolidacion &&
      (_vistaActual == _VistaLocalidades.sinConsolidar || _vistaActual == _VistaLocalidades.todos) &&
      _localidades.where((l) => l.idEdan == null || l.idEdan == 0).isNotEmpty;

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
          final pendientes =
              await DatabaseHelper.instance.getLocalidadesPendientesUsuario(userId);
          await _resincronizarBadges(pendientes);
          if (mounted) {
            setState(() {
              _localidades = pendientes;
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

      // DEBUG TEMPORAL — diagnosticar consolidadas
      debugPrint('[Localidades] resumen keys: ${resumen.keys.toList()}');
      debugPrint('[Localidades] resumen: $resumen');
      if (data.isNotEmpty) {
        debugPrint('[Localidades] primera localidad keys: ${data[0].keys.toList()}');
        debugPrint('[Localidades] id_edan raw: ${data[0]['id_edan']} type: ${data[0]['id_edan'].runtimeType}');
        debugPrint('[Localidades] edan raw: ${data[0]['edan']}');
        debugPrint('[Localidades] es_huerfana: ${data[0]['es_huerfana']}');
      }
      final conApi = localidades.where((l) => l.idEdan != null && l.idEdan! > 0).toList();
      debugPrint('[Localidades] consolidadas from API: ${conApi.length}');
      for (final c in conApi) {
        debugPrint('[Localidades]   - ${c.nombre} idEdan=${c.idEdan}');
      }
      // FIN DEBUG

      final userId = AuthService.instance.userId;
      if (userId != null) {
        try {
          final pendientes =
              await DatabaseHelper.instance.getLocalidadesPendientesUsuario(userId);
          final apiIds = localidades.map((l) => l.idServer).toSet();
          final nuevas =
              pendientes.where((l) => !apiIds.contains(l.idServer)).toList();
          localidades.addAll(nuevas);
        } catch (_) {}
      }

      await _resincronizarBadges(localidades);

      localidades.sort((a, b) {
        final fa = a.fechaModificacion ?? '';
        final fb = b.fechaModificacion ?? '';
        return fb.compareTo(fa);
      });
      if (mounted) {
        setState(() {
          _localidades = localidades;
          _resumen = resumen;
          _cargando = false;
          _error = null;
        });
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

  List<EdanLocalidad> get _filtradas {
    var list = _localidades;

    if (_vistaActual == _VistaLocalidades.sinConsolidar) {
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

    list.sort((a, b) {
      final fa = a.fechaModificacion ?? '';
      final fb = b.fechaModificacion ?? '';
      return fb.compareTo(fa);
    });

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
            ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(
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
  }

  void _cancelarModoConsolidacion() {
    setState(() {
      _modoConsolidacion = false;
      _seleccionadas.clear();
    });
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
        ScaffoldMessenger.of(context).showSnackBar(
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
        ScaffoldMessenger.of(context).showSnackBar(
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
        ScaffoldMessenger.of(context).showSnackBar(
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
    final accion = esAprobar ? 'Aprobar' : 'Rechazar';
    final color = estado.color;

    final confirmado = await showDialog<bool>(
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
    );
    if (confirmado != true || !mounted) return;

    if (!ConnectivityService().isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sin conexión. Verifica tu red y reintenta.'), backgroundColor: AppColors.pending),
        );
      }
      return;
    }
    try {
      await ApiService.instance.cambiarEstadoLocalidad(idLocalidad, nuevoEstado);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Estado cambiado a ${estado.label}'),
            backgroundColor: estado.color,
          ),
        );
        _cargarDatos();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.traducirError(e)), backgroundColor: AppColors.error),
        );
      }
    }
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return Column(
      children: [
        if (_resumen != null) _buildResumen(primary),
        if (_modoConsolidacion) _buildConsolidacionBar(primary),
        if (!_modoConsolidacion && _error == null) _buildSearchField(primary),
        Expanded(child: _error != null && _localidades.isEmpty
            ? _buildErrorState(primary)
            : _buildGroupedList(primary)),
      ],
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
              _query.isNotEmpty
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
      onEdit: esBorrador && esMia
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
      final cambio = await Navigator.of(context).push<bool>(
        ugrRoute(EdanPreviewRespScreen(
          localidad: localidad,
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
                  await ApiService.instance.cambiarEstadoLocalidad(
                    localidad.idServer!,
                    UgrLocalidadEstado.rechazadoUgr.id,
                  );
                  localidad.estadoLocalidad = UgrLocalidadEstado.rechazadoUgr;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.traducirError(e)), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _editarLocalidad(EdanLocalidad localidad) async {
    final result = await Navigator.of(context).push<bool>(
      ugrRoute(
        EdanFormWizard(edanAEditar: Edan.desdeLocalidad(localidad)),
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
        await ApiService.instance.eliminarLocalidadDocumento(localidad.idServer!);
        await db.deleteLocalidad(idLocal);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Localidad eliminada del servidor'),
            backgroundColor: AppColors.aprobado,
          ),
        );
      } else if (localidad.sincronizado) {
        await db.markLocalidadAsPendingDeletion(idLocal);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Localidad marcada para eliminación. Se borrará al sincronizar.'),
            backgroundColor: AppColors.pending,
          ),
        );
      } else {
        await db.deleteLocalidad(idLocal);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Localidad eliminada'),
            backgroundColor: AppColors.aprobado,
          ),
        );
      }
      await _cargarDatos();
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

  Widget _buildConsolidacionBar(Color primary) {
    final count = _seleccionadas.length;
    return Container(
      width: double.infinity,
      color: primary.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 18, color: primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              count > 0 ? '$count seleccionada(s)' : 'Seleccione localidades aprobadas',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primary),
            ),
          ),
          FilledButton.icon(
            onPressed: count >= 1 ? _vistaPreviaConsolidacion : null,
            icon: const Icon(Icons.preview, size: 18),
            label: const Text('Vista previa EDAN'),
            style: FilledButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.divider,
              disabledForegroundColor: AppColors.textSecondary,
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
          Text(label, style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.7))),
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
