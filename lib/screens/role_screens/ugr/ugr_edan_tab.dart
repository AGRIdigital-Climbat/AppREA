import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../../models/edan.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/database_helper.dart';
import '../../../services/edan_sync_service.dart';
import 'ugr_edan_preview_screen.dart';
import 'ugr_recurso_tab.dart';
import 'ugr_route.dart';

class UgrEdanTab extends StatefulWidget {
  const UgrEdanTab({super.key});

  @override
  State<UgrEdanTab> createState() => UgrEdanTabState();
}

class UgrEdanTabState extends State<UgrEdanTab>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _edanesServidor = [];
  bool _cargando = true;
  String _query = '';
  late TabController _tabController;
  final _recursoTabKey = GlobalKey<UgrRecursoTabState>();

  int get edanesCount => _edanesServidor.length;

  void refresh() {
    _cargarEdanesServidor();
    _recursoTabKey.currentState?.refresh();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    _syncNotifier = EdanSyncService.instance.sincronizandoMunicipio;
    _syncNotifier!.addListener(_onSyncMunicipioChanged);
    _cargarEdanesServidor();
  }

  ValueNotifier<bool>? _syncNotifier;

  void _onSyncMunicipioChanged() {
    if (!_syncNotifier!.value && mounted) {
      _cargarEdanesServidor();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _cargarEdanesServidor();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _syncNotifier?.removeListener(_onSyncMunicipioChanged);
    super.dispose();
  }

  int? get _idMunicipio => AuthService.instance.currentToken?.idMunicipio;

  Future<void> _cargarEdanesServidor() async {
    final municipioId = _idMunicipio;
    if (municipioId == null) {
      if (mounted) setState(() => _cargando = false);
      return;
    }
    if (!ConnectivityService().isConnected) {
      try {
        final edanes = await DatabaseHelper.instance.getEdansByMunicipio(municipioId);
        if (mounted) {
          setState(() {
            _edanesServidor = edanes.map((e) => _EdanServidorCard.edanToCardMap(e)).toList();
            _cargando = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _cargando = false);
      }
      return;
    }
    try {
      final data = await ApiService.instance.listarEdansPorMunicipio(municipioId);
      if (!mounted) return;
      setState(() {
        _edanesServidor = data;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar EDANs: ${ApiService.traducirError(e)}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _edanesFiltrados {
    var list = _edanesServidor;
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((e) {
        final codigo = _extractStr(e['codigo_edan'] ?? e['codigoEdan']).toLowerCase();
        final municipio = _extractStr(
            e['municipio_nombre'] ?? e['municipioNombre'] ?? e['municipio']).toLowerCase();
        return codigo.contains(q) || municipio.contains(q);
      }).toList();
    }
    return list;
  }

  static String _extractStr(dynamic v, [String fallback = '']) {
    if (v == null) return fallback;
    if (v is String) return v;
    if (v is Map) return '${v['nombre'] ?? v['name'] ?? fallback}';
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return Column(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: EdanSyncService.instance.sincronizandoMunicipio,
          builder: (context, sincronizando, _) => sincronizando
              ? _buildSyncMunicipioBanner(primary)
              : const SizedBox.shrink(),
        ),
        Container(
          color: AppColors.surface,
          child: TabBar(
            controller: _tabController,
            labelColor: primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: primary,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            tabs: const [
              Tab(text: 'EDANs'),
              Tab(text: 'Recursos'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildEdanTabContent(primary),
              UgrRecursoTab(key: _recursoTabKey),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEdanTabContent(Color primary) {
    return Column(
      children: [
        _buildSearchField(primary),
        Expanded(child: _buildEdanList(primary)),
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
              'Sincronizando EDANs del municipio…',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(Color primary) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: AppColors.surface,
      child: TextField(
        onChanged: (value) => setState(() => _query = value),
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Buscar código o municipio...',
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

  Widget _buildEdanList(Color primary) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final list = _edanesFiltrados;
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.assignment_outlined, size: 64, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              _query.isNotEmpty ? 'Sin resultados para la búsqueda' : 'No hay EDANs en este municipio',
              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
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
        final edan = list[index];
        return _EdanServidorCard(
          edan: edan,
          onTap: () => _verDetalleEdan(edan),
        );
      },
    );
  }

  static bool _esBorrador(Edan e) {
    final estLower = e.estado.trim().toLowerCase();
    return estLower == 'borrador' || (estLower.isEmpty && e.idEstado == 1);
  }

  Future<void> _verDetalleEdan(Map<String, dynamic> edan) async {
    final idEdan = edan['id_edan'];
    if (idEdan == null) return;
    if (!ConnectivityService().isConnected) {
      try {
        final idLocal = edan['id_local'] as int?;
        Edan? edanModel;
        if (idLocal != null) {
          edanModel = await DatabaseHelper.instance.getEdanByIdLocal(idLocal);
        }
        edanModel ??= Edan.fromJson(edan);
        if (!mounted) return;
        await Navigator.of(context).push(
          ugrRoute(UgrEdanPreviewScreen(edan: edanModel, soloLectura: !_esBorrador(edanModel), esConsolidado: true)),
        );
        if (mounted) await _cargarEdanesServidor();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sin conexión. Verifica tu red y reintenta.'), backgroundColor: AppColors.pending),
          );
        }
      }
      return;
    }
    try {
      final detalle = await ApiService.instance.getEdanById(idEdan);
      final edanModel = Edan.fromJson(detalle);
      if (!mounted) return;
      await Navigator.of(context).push(
        ugrRoute(UgrEdanPreviewScreen(edan: edanModel, soloLectura: !_esBorrador(edanModel), esConsolidado: true)),
      );
      if (mounted) await _cargarEdanesServidor();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar EDAN: ${ApiService.traducirError(e)}'), backgroundColor: AppColors.error),
        );
      }
    }
  }
}

class _EdanServidorCard extends StatelessWidget {
  final Map<String, dynamic> edan;
  final VoidCallback onTap;

  const _EdanServidorCard({required this.edan, required this.onTap});

  static Map<String, dynamic> edanToCardMap(Edan e) => {
        'id_edan': e.idEdan,
        'id_local': e.idLocal,
        'codigo_edan': e.codigoEdan,
        'tipo_evento_nombre': e.tipoEventoNombre ?? '',
        'municipio_nombre': e.municipioNombre ?? '',
        'estado': e.estado,
        'total_localidades': e.localidades.length,
        'total_poblacion_afectada': e.totalPoblacionAfectada,
        'fecha_evento': e.fechaEvento,
      };

  static String _safeStr(dynamic v, [String fallback = '']) {
    if (v == null) return fallback;
    if (v is String) return v;
    if (v is Map) return '${v['nombre'] ?? v['name'] ?? fallback}';
    return '$v';
  }

  static int _safeInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is Map) return _safeInt(v['id']);
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final codigo = _safeStr(edan['codigo_edan'] ?? edan['codigoEdan'], 'Sin codigo');
    final tipoEvento = _safeStr(
        edan['tipo_evento_nombre'] ?? edan['tipoEventoNombre'] ?? edan['tipo_evento']);
    final municipio = _safeStr(
        edan['municipio_nombre'] ?? edan['municipioNombre'] ?? edan['municipio']);
    final estado = _safeStr(edan['estado']);
    final localidades = _safeInt(edan['total_localidades']);
    final poblacion = _safeInt(edan['total_poblacion_afectada']);
    final fechaEvento = _safeStr(edan['fecha_evento'] ?? edan['fechaEvento']);

    final estadoColor = _estadoColor(estado);

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
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: estadoColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      codigo,
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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: estadoColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: estadoColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      estado,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: estadoColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (tipoEvento.isNotEmpty || municipio.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Text(
                    [tipoEvento, municipio].where((s) => s.isNotEmpty).join(' · '),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(width: 20),
                  Expanded(
                    child: Text(
                      [
                        if (localidades != 0)
                          '$localidades localidad${localidades == 1 ? '' : 'es'}',
                        if (poblacion != 0)
                          '$poblacion pers.',
                        if (fechaEvento.isNotEmpty)
                          fechaEvento,
                      ].join(' · '),
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

  Color _estadoColor(String estado) {
    switch (estado.toLowerCase()) {
      case 'borrador':
        return AppColors.pending;
      case 'enviado':
        return AppColors.inProgress;
      case 'aprobado':
      case 'aprobado ugr':
        return AppColors.aprobado;
      case 'rechazado':
        return AppColors.rechazado;
      case 'cerrado':
        return AppColors.closed;
      default:
        return AppColors.textSecondary;
    }
  }
}
