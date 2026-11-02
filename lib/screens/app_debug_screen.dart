import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/app_logger.dart';

/// Visor del registro global de la app (últimas 24 h).
///
/// Estructura en tres zonas, sin solapes:
///   1. **Panel de estado** — contadores por categoría, errores y rango.
///   2. **Filtros** — búsqueda + chips de categoría + chips de nivel +
///      interruptor «Solo errores».
///   3. **Línea de tiempo** — tarjetas con acento de color por nivel,
///       cabecera compacta (hora, título, categoría, pantalla) y detalle
///       expandible con REQUEST / RESPONSE / ERROR / STACK completos.
///
/// El AppBar ofrece: copiar todo (filtrado), descargar `.txt`, compartir,
/// limpiar y refrescar.
class AppDebugScreen extends StatefulWidget {
  const AppDebugScreen({super.key});

  @override
  State<AppDebugScreen> createState() => _AppDebugScreenState();
}

class _AppDebugScreenState extends State<AppDebugScreen> {
  static const int _tamPagina = 200;

  final AppLogger _log = AppLogger.instance;
  final TextEditingController _busqueda = TextEditingController();

  List<LogEntry> _entradas = const [];
  Map<String, Object?> _resumen = const {};
  final Set<int> _expandidas = {};

  bool _cargando = false;
  bool _hayMas = false;
  int _offset = 0;
  Timer? _autoRefresh;

  AppLogCategoria? _categoria;
  AppLogLevel? _nivel;
  bool _soloErrores = false;
  bool _auto = true;

  @override
  void initState() {
    super.initState();
    _recargar(reset: true);
    _autoRefresh = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_auto && mounted) _recargar(reset: true, silencioso: true);
    });
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _recargar({
    bool reset = false,
    bool silencioso = false,
  }) async {
    if (reset) _offset = 0;
    if (!silencioso) setState(() => _cargando = true);
    try {
      final nuevas = await _log.consultar(
        categoria: _categoria,
        nivel: _nivel,
        soloErrores: _soloErrores,
        texto: _busqueda.text,
        limit: _tamPagina,
        offset: _offset,
      );
      final resumen = await _log.resumen();
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _resumen = resumen;
        _entradas = reset ? nuevas : [..._entradas, ...nuevas];
        _hayMas = nuevas.length == _tamPagina;
        _offset += nuevas.length;
      });
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
      if (!silencioso && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al leer el registro: $e')),
        );
      }
    }
  }

  // ── acciones ──────────────────────────────────────────────────────────────

  Future<String> _textoExportado() => _log.exportarTexto(
        categoria: _categoria,
        nivel: _nivel,
        soloErrores: _soloErrores,
        texto: _busqueda.text,
      );

  Future<void> _copiarTodo() async {
    final texto = await _textoExportado();
    await Clipboard.setData(ClipboardData(text: texto));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Registro filtrado copiado al portapapeles')),
    );
  }

  Future<void> _copiarEntrada(LogEntry e) async {
    await Clipboard.setData(ClipboardData(text: e.aTexto()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Entrada copiada')),
    );
  }

  Future<File> _guardarTxt() async {
    final texto = await _textoExportado();
    final dir = await getApplicationDocumentsDirectory();
    final carpeta = Directory('${dir.path}${Platform.pathSeparator}rea_logs');
    if (!await carpeta.exists()) await carpeta.create(recursive: true);
    final n = DateTime.now();
    String dos(int v) => v.toString().padLeft(2, '0');
    final nombre = 'registro_${n.year}${dos(n.month)}${dos(n.day)}'
        '_${dos(n.hour)}${dos(n.minute)}${dos(n.second)}.txt';
    final archivo = File('${carpeta.path}${Platform.pathSeparator}$nombre');
    await archivo.writeAsString(texto, flush: true);
    return archivo;
  }

  Future<void> _descargar() async {
    try {
      final archivo = await _guardarTxt();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Guardado: ${archivo.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    }
  }

  Future<void> _compartir() async {
    File? archivo;
    try {
      archivo = await _guardarTxt();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(archivo.path)],
          subject: 'Registro EDAN (últimas 24 h)',
        ),
      );
    } catch (e) {
      final ruta = archivo?.path ?? '(no se pudo escribir)';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Compartir no disponible ($e).\n'
              'Archivo guardado en: $ruta'),
        ),
      );
    }
  }

  Future<void> _limpiar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Vaciar el registro?'),
        content: const Text(
          'Se borrarán TODAS las entradas de las últimas 24 h. '
          'La captura continuará normalmente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Vaciar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _log.limpiar();
      _expandidas.clear();
      await _recargar(reset: true);
    }
  }

  int _total() => _resumen['total'] is int ? _resumen['total'] as int : 0;

  int _conteo(Map<String, Object?> mapa, String clave) {
    final v = mapa[clave];
    return v is int ? v : 0;
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F2937),
        foregroundColor: Colors.white,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Registro de la app',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15),
            ),
            Text(
              '24 h · detalle completo',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: Color(0xFFB9C4D0)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _auto ? 'Auto-refresco ON (3 s)' : 'Auto-refresco OFF',
            icon: Icon(_auto
                ? Icons.pause_circle_outline
                : Icons.play_circle_outline),
            onPressed: () => setState(() => _auto = !_auto),
          ),
          IconButton(
            tooltip: 'Refrescar',
            icon: const Icon(Icons.refresh),
            onPressed: () => _recargar(reset: true),
          ),
          PopupMenuButton<String>(
            tooltip: 'Exportar / limpiar',
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              switch (v) {
                case 'copiar':
                  _copiarTodo();
                case 'txt':
                  _descargar();
                case 'compartir':
                  _compartir();
                case 'vaciar':
                  _limpiar();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'copiar',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.copy_all_outlined, size: 20),
                  title: Text('Copiar todo lo filtrado'),
                ),
              ),
              PopupMenuItem(
                value: 'txt',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.download_outlined, size: 20),
                  title: Text('Descargar .txt'),
                ),
              ),
              PopupMenuItem(
                value: 'compartir',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.ios_share, size: 20),
                  title: Text('Compartir .txt'),
                ),
              ),
              PopupMenuItem(
                value: 'vaciar',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_sweep_outlined, size: 20,
                      color: Colors.red),
                  title: Text('Vaciar registro',
                      style: TextStyle(color: Colors.red)),
                ),
              ),
            ],
          ),
        ],
      ),
      body: !_log.habilitado
          ? const _PanelDeshabilitado()
          : SafeArea(
              child: Column(
                children: [
                  _panelEstado(),
                  _filtros(),
                  const Divider(height: 1, thickness: 1),
                  Expanded(child: _lista()),
                ],
              ),
            ),
    );
  }

  // ── 1. panel de estado ────────────────────────────────────────────────────

  Widget _panelEstado() {
    final porNivel = _resumen['por_nivel'];
    final porCat = _resumen['por_categoria'];
    final err = porNivel is Map<String, Object?>
        ? _conteo(porNivel, 'ERROR')
        : 0;
    final api =
        porCat is Map<String, Object?> ? _conteo(porCat, 'API') : 0;
    final sql =
        porCat is Map<String, Object?> ? _conteo(porCat, 'SQL') : 0;
    final sync =
        porCat is Map<String, Object?> ? _conteo(porCat, 'SYNC') : 0;
    final desde = _resumen['desde'];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _stat('Total', _total(), const Color(0xFF1F2937)),
              const SizedBox(width: 8),
              _stat('Errores', err, Colors.red),
              const SizedBox(width: 8),
              _stat('API', api, Colors.blue),
              const SizedBox(width: 8),
              _stat('SQL', sql, Colors.teal),
              const SizedBox(width: 8),
              _stat('Sync', sync, Colors.purple),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            desde is DateTime
                ? 'Rango guardado: desde ${_fechaCorta(desde)} · '
                    'retención 24 h'
                : 'Sin entradas todavía — la app captura en tiempo real.',
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _stat(String etiqueta, int valor, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$valor',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                etiqueta.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 2. filtros ────────────────────────────────────────────────────────────

  Widget _filtros() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        children: [
          TextField(
            controller: _busqueda,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Buscar en títulos, URLs, bodies, errores…',
              hintStyle: const TextStyle(fontSize: 12),
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _busqueda.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _busqueda.clear();
                        _recargar(reset: true);
                      },
                    )
                  : null,
              isDense: true,
              filled: true,
              fillColor: const Color(0xFFF3F5F7),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _recargar(reset: true),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chipCat(Icons.filter_alt, 'TODAS', null),
                _chipCat(Icons.wifi_tethering, 'API', AppLogCategoria.api),
                _chipCat(Icons.storage, 'SQL', AppLogCategoria.sql),
                _chipCat(Icons.sync, 'SYNC', AppLogCategoria.sync),
                _chipCat(Icons.navigation, 'NAV', AppLogCategoria.nav),
                _chipCat(Icons.bug_report, 'ERROR', AppLogCategoria.error),
                _chipCat(Icons.apps, 'APP', AppLogCategoria.app),
                _chipCat(Icons.lock, 'AUTH', AppLogCategoria.auth),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chipNivel('TODO', null),
                _chipNivel('DEBUG', AppLogLevel.debug),
                _chipNivel('INFO', AppLogLevel.info),
                _chipNivel('WARN', AppLogLevel.warn),
                _chipNivel('ERROR', AppLogLevel.error),
                const SizedBox(width: 2),
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  avatar: Icon(
                    _soloErrores ? Icons.error : Icons.error_outline,
                    size: 15,
                    color: _soloErrores ? Colors.red : Colors.black45,
                  ),
                  label: const Text('SOLO ERRORES',
                      style: TextStyle(fontSize: 10)),
                  backgroundColor: _soloErrores
                      ? Colors.red.withValues(alpha: 0.12)
                      : null,
                  onPressed: () {
                    setState(() => _soloErrores = !_soloErrores);
                    _recargar(reset: true);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipCat(IconData icon, String texto, AppLogCategoria? c) {
    final sel = _categoria == c;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        avatar: Icon(icon,
            size: 15, color: sel ? _colorCategoria(c) : Colors.black45),
        label: Text(texto, style: const TextStyle(fontSize: 11)),
        selected: sel,
        onSelected: (_) {
          setState(() => _categoria = c);
          _recargar(reset: true);
        },
      ),
    );
  }

  Widget _chipNivel(String texto, AppLogLevel? n) {
    final sel = _nivel == n;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        label: Text(texto, style: const TextStyle(fontSize: 10)),
        selected: sel,
        onSelected: (_) {
          setState(() => _nivel = n);
          _recargar(reset: true);
        },
      ),
    );
  }

  // ── 3. línea de tiempo ────────────────────────────────────────────────────

  Widget _lista() {
    if (_entradas.isEmpty && !_cargando) {
      return RefreshIndicator(
        onRefresh: () => _recargar(reset: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'Sin entradas para este filtro',
                style: TextStyle(color: Colors.black54),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _recargar(reset: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: _entradas.length + (_hayMas ? 1 : 0),
        itemBuilder: (_, i) {
          if (i >= _entradas.length) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: TextButton.icon(
                  onPressed: _cargando ? null : () => _recargar(reset: false),
                  icon: const Icon(Icons.expand_more, size: 18),
                  label: Text(_cargando ? 'Cargando…' : 'Cargar más'),
                ),
              ),
            );
          }
          return _fila(_entradas[i]);
        },
      ),
    );
  }

  Widget _fila(LogEntry e) {
    final abierta = _expandidas.contains(e.id);
    final acento = e.esError ? Colors.red : _colorCategoria(e.categoria);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        elevation: 0.5,
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: acento),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cabecera compacta
                    InkWell(
                      onTap: () => setState(() =>
                          abierta ? _expandidas.remove(e.id) : _expandidas.add(e.id)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                        child: Row(
                          children: [
                            Text(
                              _horaExacta(e.timestamp),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _badge(e.nivel.name, _colorNivel(e.nivel)),
                            const SizedBox(width: 6),
                            Icon(_iconoCategoria(e.categoria),
                                size: 14, color: acento),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                e.titulo,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: e.esError
                                      ? Colors.red.shade900
                                      : Colors.black87,
                                ),
                              ),
                            ),
                            Icon(
                              abierta
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 20,
                              color: Colors.black38,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!abierta && (e.pantalla != null || e.url != null))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                        child: Text(
                          [
                            if (e.pantalla != null) e.pantalla!,
                            if (e.url != null) _urlResumida(e.url!),
                            if (e.detalle != null && e.detalle!.length < 80)
                              e.detalle!,
                          ].join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black45),
                        ),
                      ),
                    if (abierta) _detalle(e, acento),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detalle(LogEntry e, Color acento) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _miniChip('pantalla', e.pantalla),
                      _miniChip('estado', e.estado?.toString()),
                      _miniChip('dur', e.durMs != null ? '${e.durMs} ms' : null),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Copiar esta entrada',
                  icon: const Icon(Icons.copy, size: 17),
                  onPressed: () => _copiarEntrada(e),
                ),
              ],
            ),
          ),
          if (e.url != null) _bloque('URL', e.url!, acento),
          if (e.detalle != null && e.detalle!.isNotEmpty)
            _bloque('Detalle', e.detalle!, acento),
          if (e.request != null && e.request!.isNotEmpty)
            _bloque('Request', e.request!, acento),
          if (e.response != null && e.response!.isNotEmpty)
            _bloque('Response', e.response!, acento),
          if (e.error != null && e.error!.isNotEmpty)
            _bloque('Error', e.error!, Colors.red),
          if (e.stack != null && e.stack!.isNotEmpty)
            _bloque('Stack', e.stack!, Colors.red),
        ],
      ),
    );
  }

  Widget _miniChip(String etiqueta, String? valor) {
    if (valor == null || valor.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5F7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$etiqueta: $valor',
        style: const TextStyle(fontSize: 10.5, color: Colors.black87),
      ),
    );
  }

  Widget _bloque(String etiqueta, String contenido, Color acento) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: acento.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              etiqueta.toUpperCase(),
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: acento,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 300),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                contenido,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  static String _horaExacta(DateTime t) {
    String dos(int v) => v.toString().padLeft(2, '0');
    return '${dos(t.hour)}:${dos(t.minute)}:${dos(t.second)}'
        '.${t.millisecond.toString().padLeft(3, '0')}';
  }

  static String _fechaCorta(DateTime t) {
    String dos(int v) => v.toString().padLeft(2, '0');
    return '${dos(t.day)}/${dos(t.month)} ${dos(t.hour)}:${dos(t.minute)}';
  }

  static String _urlResumida(String url) {
    final i = url.indexOf('/api/v2');
    final corta = i >= 0 ? url.substring(i + 7) : url;
    return corta.length > 60 ? '${corta.substring(0, 57)}…' : corta;
  }

  static IconData _iconoCategoria(AppLogCategoria c) {
    switch (c) {
      case AppLogCategoria.api:
        return Icons.wifi_tethering;
      case AppLogCategoria.sql:
        return Icons.storage;
      case AppLogCategoria.sync:
        return Icons.sync;
      case AppLogCategoria.nav:
        return Icons.navigation;
      case AppLogCategoria.error:
        return Icons.bug_report;
      case AppLogCategoria.app:
        return Icons.apps;
      case AppLogCategoria.auth:
        return Icons.lock;
    }
  }

  static Color _colorCategoria(AppLogCategoria? c) {
    switch (c) {
      case AppLogCategoria.api:
        return Colors.blue;
      case AppLogCategoria.sql:
        return Colors.teal;
      case AppLogCategoria.sync:
        return Colors.purple;
      case AppLogCategoria.nav:
        return Colors.cyan.shade700;
      case AppLogCategoria.error:
        return Colors.red;
      case AppLogCategoria.app:
        return Colors.green;
      case AppLogCategoria.auth:
        return Colors.amber.shade700;
      case null:
        return Colors.black45;
    }
  }

  static Color _colorNivel(AppLogLevel n) {
    switch (n) {
      case AppLogLevel.debug:
        return Colors.blueGrey;
      case AppLogLevel.info:
        return Colors.green;
      case AppLogLevel.warn:
        return Colors.orange;
      case AppLogLevel.error:
        return Colors.red;
    }
  }
}

class _PanelDeshabilitado extends StatelessWidget {
  const _PanelDeshabilitado();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.report_gmailerrorred_outlined,
                size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            const Text(
              'El registro global está DESHABILITADO',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'No se pudo abrir su base de datos al arrancar la app.\n'
              'Reinicia la app para reintentar.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
