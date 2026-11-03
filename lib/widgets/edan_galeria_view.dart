import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../config/api_config.dart';
import '../config/theme.dart';
import '../models/edan.dart';
import '../screens/role_screens/resp/edan/edan_boton_sacar_foto.dart';
import '../services/api/edan_api_v2.dart';
import '../services/api_service.dart';
import '../services/edan/edan_store_v2.dart';
import '../services/edan_secciones_registry.dart';
import '../services/app_logger_ui.dart';

/// Galería de fotos EDAN compartida por el rol 7 (sus localidades) y el rol 6
/// (localidades del municipio, con autor): fotos agrupadas por localidad,
/// coordenadas de la fila dueña sobre cada miniatura (foto y coordenada van
/// siempre juntas), badge de tipo de evento al lado del estado, filtro por
/// localidad con sheet buscable (escala a 100+), y visor reutilizado del
/// wizard ([EdanBotonSacarFoto.verFotoCompleta]: zoom + coordenadas +
/// compartir).
///
/// La fuente de datos la inyecta el llamador por [carga]:
/// `listarFotosGaleria(usuarioId)` (RESP) o
/// `listarFotosGaleriaPorMunicipio(idMunicipio)` (UGR, `showAutor: true`).
class EdanGaleriaView extends StatefulWidget {
  const EdanGaleriaView({
    super.key,
    required this.carga,
    this.showAutor = false,
  });

  final Future<List<EdanFotoGaleria>> Function() carga;

  /// Mostrar el responsable de cada localidad (UGR ve fotos de todos).
  final bool showAutor;

  @override
  State<EdanGaleriaView> createState() => EdanGaleriaViewState();
}

class EdanGaleriaViewState extends State<EdanGaleriaView>
    with WidgetsBindingObserver {
  List<EdanFotoGaleria> _fotos = const [];
  bool _cargando = true;
  String? _errorCarga;

  /// uuid de la localidad seleccionada como filtro (`null` = todas).
  String? _filtroUuid;

  /// Fotos cuya descarga está en vuelo (spinners sobre la miniatura).
  final Set<String> _descargando = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    EdanStoreV2.instance.datosVersion.addListener(_cargar);
    EdanStoreV2.instance.primeraDescarga.addListener(_cargar);
    _cargar();
  }

  @override
  void dispose() {
    EdanStoreV2.instance.datosVersion.removeListener(_cargar);
    EdanStoreV2.instance.primeraDescarga.removeListener(_cargar);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _cargar();
  }

  void refresh() => _cargar();

  Future<void> _cargar() async {
    try {
      final fotos = await widget.carga();
      if (!mounted) return;
      setState(() {
        _fotos = fotos;
        _errorCarga = null;
        _cargando = false;
        // Si la localidad del filtro desapareció (borrada/sync), se limpia
        // para no dejar un filtro invisible vaciando la pantalla.
        if (_filtroUuid != null &&
            !fotos.any((f) => f.uuidEdanLocalidad == _filtroUuid)) {
          _filtroUuid = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _errorCarga = e.toString();
      });
    }
  }

  List<_GrupoLocalidad> get _grupos {
    final g = agruparFotosPorLocalidad(_fotos);
    return [
      for (final e in g.entries)
        _GrupoLocalidad(
          uuid: e.key,
          nombre: e.value.first.nombreLocalidad,
          estado: _estadoDe(e.value.first.idEstadoLocalidad),
          tipoEventoNombre: e.value.first.tipoEventoNombre,
          autor: widget.showAutor ? e.value.first.nombreAutor : null,
          fotos: e.value,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_fotos.isEmpty) {
      return RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 60),
            Icon(
              Icons.photo_library_outlined,
              size: 56,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              _errorCarga != null
                  ? 'No se pudo leer la galería'
                  : 'Aún no hay fotos',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _errorCarga ??
                  'Las fotos aparecen aquí al capturarlas en el formulario '
                      'o al sincronizar con el UGR.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    final grupos = _grupos;
    final visibles = _filtroUuid == null
        ? grupos
        : grupos.where((g) => g.uuid == _filtroUuid).toList();

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          _encabezado(grupos.length),
          const SizedBox(height: 10),
          if (visibles.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Sin fotos para la localidad seleccionada',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          for (final g in visibles) ...[
            _seccionLocalidad(g),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  // ── encabezado + filtro ───────────────────────────────────────────────────

  Widget _encabezado(int totalLocalidades) {
    final filtrando = _filtroUuid != null;
    final nombreFiltro = filtrando
        ? _fotos
            .firstWhere((f) => f.uuidEdanLocalidad == _filtroUuid)
            .nombreLocalidad
        : null;
    return Row(
      children: [
        Expanded(
          child: Text(
            '${_fotos.length} foto${_fotos.length == 1 ? '' : 's'} '
            'en $totalLocalidades localidad${totalLocalidades == 1 ? '' : 'es'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (filtrando)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Quitar filtro',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _filtroUuid = null),
          ),
        ActionChip(
          visualDensity: VisualDensity.compact,
          avatar: Icon(
            Icons.tune,
            size: 16,
            color: PaletteScope.of(context).primary,
          ),
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              nombreFiltro ?? 'Todas las localidades',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          onPressed: _abrirSelector,
        ),
      ],
    );
  }

  /// Sheet de filtro: buscador + lista completa (escala a 100+ localidades,
  /// a diferencia de unos chips horizontales). Regresa el uuid elegido o
  /// `''` para "Todas"; `null` si se cancela.
  Future<void> _abrirSelector() async {
    final elegido = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SelectorLocalidadSheet(
        grupos: _grupos,
        total: _fotos.length,
        seleccionado: _filtroUuid,
        showAutor: widget.showAutor,
      ),
    );
    if (elegido == null || !mounted) return;
    setState(() => _filtroUuid = elegido.isEmpty ? null : elegido);
  }

  // ── secciones ─────────────────────────────────────────────────────────────

  Widget _seccionLocalidad(_GrupoLocalidad g) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    g.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (g.tipoEventoNombre != null &&
                    g.tipoEventoNombre!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _badge(
                      icon: Icons.campaign_outlined,
                      texto: g.tipoEventoNombre!,
                      color: Colors.indigo,
                    ),
                  ),
                _badge(
                  icon: Icons.circle,
                  texto: g.estado.label,
                  color: g.estado.color,
                ),
                const SizedBox(width: 8),
                // En el UGR cada foto es de un responsable distinto: el autor
                // acompaña al contador para no robarle ancho al nombre.
                Text(
                  g.autor != null && g.autor!.isNotEmpty
                      ? '${g.cantidad} 📷 · ${g.autor}'
                      : '${g.cantidad} 📷',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.78,
              ),
              itemCount: g.fotos.length,
              itemBuilder: (_, i) => _miniatura(g.fotos[i]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge({
    required IconData icon,
    required String texto,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: icon == Icons.circle ? 8 : 12, color: color),
          const SizedBox(width: 4),
          Text(
            texto,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ── miniatura + visor (compartido con el wizard) ──────────────────────────

  Widget _miniatura(EdanFotoGaleria f) {
    final enDescarga = _descargando.contains(f.uuidFotografia);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        // Foto sin archivo local: primero se baja (la coordenada ya viene en
        // su fila dueña); con archivo, el visor se abre directo.
        if (!f.tieneArchivoLocal && f.tieneRemoto) {
          _descargarYVer(f);
        } else {
          _abrirVisor(f, rutaForzada: null);
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _imagen(f),
            if (enDescarga)
              Container(
                color: Colors.black38,
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                color: Colors.black.withValues(alpha: 0.55),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            etiquetaTipoEntidad(f.tipoEntidad),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 9, color: Colors.white),
                          ),
                        ),
                        if (!enDescarga &&
                            !f.tieneArchivoLocal &&
                            f.tieneRemoto)
                          const Icon(Icons.cloud_download_outlined,
                              size: 11, color: Colors.white70),
                      ],
                    ),
                    // Foto y coordenada van juntas: si la fila dueña tiene
                    // captura GPS, se muestra siempre sobre la miniatura.
                    if (f.coordenadaTexto != null)
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              size: 9, color: Colors.white70),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              f.coordenadaTexto!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 8, color: Colors.white70),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagen(EdanFotoGaleria f) {
    if (f.tieneArchivoLocal) {
      return Image.file(
        File(f.rutaLocal!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    if (f.tieneRemoto) {
      return Image.network(
        urlRemotaFoto(f),
        fit: BoxFit.cover,
        headers: _headersFoto(),
        errorBuilder: (_, _, _) => _placeholder(),
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : Container(color: Colors.grey.shade200, child: _spinner()),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      color: Colors.grey.shade200,
      child: Icon(Icons.no_photography_outlined,
          size: 22, color: Colors.grey.shade500),
    );
  }

  Widget _spinner() => const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );

  /// Mismo visor del wizard: zoom, coordenadas, precisión y compartir.
  void _abrirVisor(EdanFotoGaleria f, {required String? rutaForzada}) {
    final ruta = rutaForzada ?? (f.tieneArchivoLocal ? f.rutaLocal : null);
    final foto = EdanFoto(
      ruta: ruta ?? '',
      latitud: f.coordenadaLat ?? 0,
      longitud: f.coordenadaLon ?? 0,
      uuidFotografia: f.uuidFotografia,
      tipoEntidad: f.tipoEntidad,
      uuidRegistro: f.uuidRegistro,
    );
    final titulo = [
      f.nombreLocalidad,
      etiquetaTipoEntidad(f.tipoEntidad),
      if (f.nombreAutor != null && f.nombreAutor!.isNotEmpty) f.nombreAutor!,
    ].join(' · ');
    EdanBotonSacarFoto.verFotoCompleta(
      context,
      fotos: [foto],
      fotografia: f.tieneRemoto ? f.rutaServidor : null,
      coordenadaLat: f.coordenadaLat ?? 0,
      coordenadaLon: f.coordenadaLon ?? 0,
      // Contexto completo en el chip (sin la palabra 'Respaldo', que es del
      // wizard): localidad · sección (· autor en el UGR).
      titulo: titulo,
      soloLectura: true,
    );
  }

  /// Baja los bytes a `report_photos/` (tmp + rename, extensión real),
  /// marca `ruta_local` y abre el visor con el archivo ya local.
  Future<void> _descargarYVer(EdanFotoGaleria f) async {
    setState(() => _descargando.add(f.uuidFotografia));
    try {
      final bytes = await EdanApiV2().descargarBytesFoto(
        uuidFotografia: f.uuidFotografia,
        rutaArchivo: f.rutaServidor,
      );
      if (bytes == null || bytes.isEmpty) {
        throw StateError('el servidor no devolvió la imagen');
      }
      final dir = await getApplicationDocumentsDirectory();
      final carpeta = Directory('${dir.path}/report_photos');
      if (!await carpeta.exists()) await carpeta.create(recursive: true);
      final nombre = '${f.uuidFotografia}${_extension(f.rutaServidor)}';
      final tmp = File('${carpeta.path}/$nombre.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      final archivo = File('${carpeta.path}/$nombre');
      if (await archivo.exists()) await archivo.delete();
      await tmp.rename(archivo.path);
      await EdanStoreV2.instance
          .setFotoRutaLocal(f.uuidFotografia, archivo.path);
      if (!mounted) return;
      setState(() => _descargando.remove(f.uuidFotografia));
      _cargar();
      _abrirVisor(f, rutaForzada: archivo.path);
    } catch (e) {
      if (!mounted) return;
      setState(() => _descargando.remove(f.uuidFotografia));
      showAppSnackBar(context, 
        SnackBar(
          content: Text('No se pudo descargar la foto: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  static String _extension(String? rutaServidor) {
    final r = rutaServidor ?? '';
    final sinQuery = r.split('?').first;
    final punto = sinQuery.lastIndexOf('.');
    if (punto > sinQuery.lastIndexOf('/') &&
        punto > 0 &&
        sinQuery.length - punto <= 6) {
      return sinQuery.substring(punto);
    }
    return '.jpg';
  }
}

// ── helpers puros (testeables) ─────────────────────────────────────────────

/// Una localidad con sus fotos, para secciones y para el sheet de filtro.
class _GrupoLocalidad {
  final String uuid;
  final String nombre;
  final UgrLocalidadEstado estado;
  final String? tipoEventoNombre;
  final String? autor;
  final List<EdanFotoGaleria> fotos;

  _GrupoLocalidad({
    required this.uuid,
    required this.nombre,
    required this.estado,
    required this.fotos,
    this.tipoEventoNombre,
    this.autor,
  });

  int get cantidad => fotos.length;
}

/// Agrupa fotos vivas por localidad preservando el orden de entrada
/// (la consulta ya ordena por localidad alfabética). Clave: uuid de la
/// localidad; valor: sus fotos (más nuevas primero).
Map<String, List<EdanFotoGaleria>> agruparFotosPorLocalidad(
  List<EdanFotoGaleria> fotos,
) {
  final grupos = <String, List<EdanFotoGaleria>>{};
  for (final f in fotos) {
    grupos.putIfAbsent(f.uuidEdanLocalidad, () => []).add(f);
  }
  return grupos;
}

/// URL estática del servidor para una `ruta_servidor` (`/uploads/reports/…`).
String urlRemotaFoto(EdanFotoGaleria f) {
  final base = Uri.parse(ApiConfig.baseUrl);
  var ruta = f.rutaServidor ?? '';
  if (!ruta.startsWith('/')) ruta = '/$ruta';
  return '${base.scheme}://${base.host}$ruta';
}

Map<String, String>? _headersFoto() {
  final token = ApiService.instance.token;
  return token == null ? null : {'Authorization': 'Bearer $token'};
}

/// Etiqueta en español del dueño de la foto (`tipo_entidad` de la tabla
/// `fotografias`: tabla corta del servidor, `vivienda` o `cabecera`).
String etiquetaTipoEntidad(String? tipoEntidad) {
  const nombres = <String, String>{
    'impacto_poblacion': 'Población afectada',
    'salud_establecimientos': 'Establecimientos de salud',
    'establecimientos_salud': 'Establecimientos de salud',
    'danos_viales': 'Daños viales',
    'danos_infra_publica': 'Infraestructura pública',
    'servicios_basicos': 'Servicios básicos',
    'unidades_educativas': 'Unidades educativas',
    'danos_vivienda': 'Daños en vivienda',
    'danos_agricultura': 'Daños en agricultura',
    'danos_pecuarios': 'Daños en pecuario',
    'infra_productiva': 'Infraestructura productiva',
    'proteccion': 'Protección',
    'primera_respuesta': 'Primera respuesta',
    'necesidad_primera_respuesta': 'Primera respuesta',
    'salud_necesidades': 'Necesidades de salud',
    'necesidad_salud': 'Necesidades de salud',
    'necesidades_humanitarias': 'Necesidades humanitarias',
    'necesidad_humanitaria': 'Necesidades humanitarias',
    'vivienda': 'Vivienda',
    'cabecera': 'Datos generales',
  };
  final t = tipoEntidad ?? '';
  if (t.isEmpty) return 'Foto';
  final directo = nombres[t];
  if (directo != null) return directo;
  // Variantes: el servidor a veces manda la ruta v2 (`danos-viales`).
  final porRuta = EdanSeccionesRegistry.porRuta(t);
  if (porRuta != null) {
    return nombres[porRuta.tabla] ?? nombres[porRuta.llaveJson] ?? t;
  }
  final fallback = EdanSeccionesRegistry.rutaDesdeTabla(t);
  return nombres[fallback] ?? t.replaceAll('_', ' ');
}

UgrLocalidadEstado _estadoDe(int id) =>
    UgrLocalidadEstado.values.firstWhere(
      (e) => e.id == id,
      orElse: () => UgrLocalidadEstado.borrador,
    );

// ── sheet de selección de localidad (escala a 100+) ───────────────────────

class _SelectorLocalidadSheet extends StatefulWidget {
  const _SelectorLocalidadSheet({
    required this.grupos,
    required this.total,
    this.seleccionado,
    this.showAutor = false,
  });

  final List<_GrupoLocalidad> grupos;
  final int total;
  final String? seleccionado;
  final bool showAutor;

  @override
  State<_SelectorLocalidadSheet> createState() =>
      _SelectorLocalidadSheetState();
}

class _SelectorLocalidadSheetState extends State<_SelectorLocalidadSheet> {
  String _query = '';

  List<_GrupoLocalidad> get _filtrados {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.grupos;
    return widget.grupos
        .where((g) => g.nombre.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Filtrar por localidad',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText:
                      'Buscar entre ${widget.grupos.length} localidades…',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView(
                children: [
                  if (_query.trim().isEmpty)
                    ListTile(
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor:
                            Colors.blueGrey.withValues(alpha: 0.12),
                        child: const Icon(Icons.public,
                            size: 18, color: Colors.blueGrey),
                      ),
                      title: const Text(
                        'Todas las localidades',
                        style: TextStyle(fontSize: 13.5),
                      ),
                      subtitle: Text(
                        '${widget.total} fotos',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: widget.seleccionado == null
                          ? Icon(Icons.check_circle,
                              size: 20,
                              color: PaletteScope.of(context).primary)
                          : null,
                      onTap: () => Navigator.pop(context, ''),
                    ),
                  for (final g in filtrados)
                    ListTile(
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor:
                            g.estado.color.withValues(alpha: 0.12),
                        child: Icon(Icons.photo_library,
                            size: 16, color: g.estado.color),
                      ),
                      title: Text(
                        g.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5),
                      ),
                      subtitle: Text(
                        '${[
                              g.estado.label,
                              if (g.tipoEventoNombre != null &&
                                  g.tipoEventoNombre!.isNotEmpty)
                                g.tipoEventoNombre!,
                              if (widget.showAutor &&
                                  g.autor != null &&
                                  g.autor!.isNotEmpty)
                                g.autor!,
                            ].join(' · ')}  —  '
                            '${g.cantidad} foto${g.cantidad == 1 ? '' : 's'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: widget.seleccionado == g.uuid
                          ? Icon(Icons.check_circle,
                              size: 20,
                              color: PaletteScope.of(context).primary)
                          : null,
                      onTap: () => Navigator.pop(context, g.uuid),
                    ),
                  if (filtrados.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Ninguna localidad coincide con la búsqueda',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
