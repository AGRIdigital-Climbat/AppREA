import 'package:flutter/material.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import '../../../../models/edan_registro_v2.dart';
import '../../../../services/edan/edan_store.dart';
import '../../../../services/edan/edan_uuid_helper.dart';
import 'edan_boton_sacar_foto.dart';
import 'edan_dialog_helper.dart';
import 'edan_aviso.dart';
import 'edan_vivienda_sheet.dart';

/// Página 08: Impacto en viviendas (daño parcial y total).
///
/// Una **única fila padre** ([EdanDanoVivienda]) por localidad: se capturan una
/// sola vez la comunidad/localidad, las necesidades inmediatas y las
/// observaciones. Las viviendas afectadas viven como detalle 1:N
/// ([EdanVivienda]) con su tipo de daño (TOTAL/PARCIAL), coordenadas y foto
/// propias (hoja inferior [EdanViviendaSheet]). Los contadores de viviendas con
/// daño total/parcial se **derivan** del detalle y son de solo lectura.
///
/// Con [store] (V2) las fotos de cada vivienda se registran en
/// `fotografias`/`cola_fotos` con `tipo_entidad='vivienda'` para que el motor
/// las suba por el sub-recurso de viviendas.
class EdanPage08 extends StatefulWidget {
  final EdanLocalidad localidad;

  /// Notifica al wizard que los datos cambiaron para que reevalúe el botón
  /// Siguiente de ESTA página. No reconstruye la lista de páginas.
  final VoidCallback? onCambio;

  /// Store V2 inyectado (solo RESP). Si es `null`, las fotos usan el flujo
  /// legacy (UGR/IA).
  final EdanStore? store;

  const EdanPage08({super.key, required this.localidad, this.store, this.onCambio});

  @override
  State<EdanPage08> createState() => _EdanPage08State();
}

class _EdanPage08State extends State<EdanPage08> {
  /// Toda mutación de datos pasa por `setState` en esta página, así que
  /// el override notifica al wizard en un solo punto (coalescido por él).
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    widget.onCambio?.call();
  }
  /// Única fila padre. `null` mientras el usuario no capture nada (así no se
  /// marca la sección como afectada sin datos).
  EdanDanoVivienda? _fila;

  late final TextEditingController _comunidad;
  late final TextEditingController _nec;
  late final TextEditingController _obs;

  @override
  void initState() {
    super.initState();
    final filas = widget.localidad.danosVivienda;
    _fila = filas.isNotEmpty ? filas.first : null;
    _comunidad = TextEditingController(
      text: (_fila?.comunidad.isNotEmpty ?? false)
          ? _fila!.comunidad
          : widget.localidad.nombre,
    );
    _nec = TextEditingController(text: _fila?.necesidadesInmediatas ?? '');
    _obs = TextEditingController(text: _fila?.observaciones ?? '');
  }

  @override
  void dispose() {
    _comunidad.dispose();
    _nec.dispose();
    _obs.dispose();
    super.dispose();
  }

  /// Devuelve la única fila padre, creándola (y agregándola al modelo) la
  /// primera vez que el usuario captura algo.
  EdanDanoVivienda _asegurarFila() {
    var fila = _fila;
    if (fila == null) {
      fila = EdanDanoVivienda();
      widget.localidad.danosVivienda.add(fila);
      _fila = fila;
    }
    if (fila.comunidad.isEmpty) {
      fila.comunidad = _comunidad.text.isNotEmpty
          ? _comunidad.text
          : widget.localidad.nombre;
    }
    return fila;
  }

  // ── Viviendas 1:N ──

  void _agregarVivienda() {
    // uuid propio ANTES de capturar la foto: el registro en `fotografias`/
    // `cola_fotos` se asocia a este uuid (dueña = la vivienda).
    final fila = _asegurarFila();
    final viv = EdanVivienda(
      uuidRegistro: EdanUuidHelper.generarUuidRegistro(),
      uuidDanoVivienda: fila.idSeccion,
    );
    _editarVivienda(fila, viv, esNuevo: true);
  }

  /// Abre la hoja inferior de la vivienda (tipo de daño + coordenadas + foto)
  /// y aplica el resultado. Con [widget.store] (V2) la foto se registra en
  /// `fotografias`/`cola_fotos` con `tipo_entidad='vivienda'` para que el motor
  /// la suba por el sub-recurso de viviendas.
  Future<void> _editarVivienda(EdanDanoVivienda fila, EdanVivienda viv,
      {bool esNuevo = false}) async {
    // Asegurar identidad propia por si la vivienda viene sin uuid.
    viv.uuidRegistro ??= EdanUuidHelper.generarUuidRegistro();
    viv.uuidDanoVivienda ??= fila.idSeccion;

    final res = await EdanViviendaSheet.mostrar(
      context,
      vivienda: viv,
      store: widget.store,
      esNuevo: esNuevo,
    );
    if (!mounted || res == null) return;

    setState(() {
      viv.tipoDano = res.tipoDano;
      viv.coordenadaLat = res.coordenadaLat;
      viv.coordenadaLon = res.coordenadaLon;
      viv.fotografia = res.fotografia;
      if (esNuevo) fila.viviendas.add(viv);
    });
  }

  Future<void> _eliminarVivienda(EdanVivienda viv) async {
    final fila = _fila;
    if (fila == null) return;
    final ok = await confirmarEliminacion(
      context,
      titulo: '¿Eliminar vivienda?',
      mensaje: 'Se quitará esta vivienda del detalle.',
    );
    if (!ok || !mounted) return;
    await _purgarFotosVivienda(viv);
    if (!mounted) return;
    setState(() => fila.viviendas.remove(viv));
  }

  /// Purga las fotos asociadas a la vivienda (registro local + archivo) para no
  /// dejar huérfanos en `fotografias`/`cola_fotos` al eliminarla.
  Future<void> _purgarFotosVivienda(EdanVivienda viv) async {
    final store = widget.store;
    final uuid = viv.uuidRegistro;
    if (store == null || uuid == null || uuid.isEmpty) return;
    try {
      final fotos = await store.cargarFotosDeEntidad('vivienda', uuid);
      for (final f in fotos) {
        final idFoto = f.uuidFotografia;
        if (idFoto != null && idFoto.isNotEmpty) {
          await store.borrarFoto(idFoto);
        }
      }
    } catch (_) {
      // Silencioso: el borrado de la vivienda sigue aunque falle la foto.
    }
  }

  Widget _campoTitulo(String titulo) {
    return Text(
      titulo,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _encabezado(),
        const SizedBox(height: 10),
        _filaForm(),
      ],
    );
  }

  Widget _encabezado() {
    final color = PaletteScope.of(context).primary;
    return Row(
      children: [
        Icon(Icons.home_outlined, color: color, size: 20),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Daños en viviendas',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _filaForm() {
    final viviendas = _fila?.viviendas ?? const <EdanVivienda>[];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _campoTitulo('Localidad'),
          const SizedBox(height: 6),
          TextField(
            controller: _comunidad,
            onChanged: (v) => _asegurarFila().comunidad = v,
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.localidad.nombre,
            ),
          ),
          const SizedBox(height: 12),
          _campoTitulo('Necesidades inmediatas'),
          const SizedBox(height: 6),
          TextField(
            controller: _nec,
            maxLines: 2,
            onChanged: (v) => _asegurarFila().necesidadesInmediatas = v,
          ),
          const SizedBox(height: 12),
          _campoTitulo('Observaciones'),
          const SizedBox(height: 6),
          TextField(
            controller: _obs,
            maxLines: 2,
            onChanged: (v) => _asegurarFila().observaciones = v,
          ),
          const SizedBox(height: 16),
          _contadores(),
          const SizedBox(height: 16),
          _listaViviendas(viviendas),
        ],
      ),
    );
  }

  Widget _contadores() {
    return Row(
      children: [
        Expanded(
          child: _contador(
            'Total viviendas con daño total',
            _fila?.viviendasTotal ?? 0,
            AppColors.error,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _contador(
            'Total viviendas con daño parcial',
            _fila?.viviendasParcial ?? 0,
            const Color(0xFFB26A00),
          ),
        ),
      ],
    );
  }

  Widget _contador(String titulo, int valor, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            '$valor',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _listaViviendas(List<EdanVivienda> viviendas) {
    final fila = _fila;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (viviendas.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Sin viviendas registradas. Agrega una para registrar su daño.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        if (fila != null)
          ...viviendas.map((viv) => _viviendaTile(fila, viv)),
        const SizedBox(height: 8),
        const EdanAvisoAfectaciones(
          texto: 'Presiona en agregar para registrar la afectación en una '
              'vivienda. Puedes agregar más de una.',
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _agregarVivienda,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Agregar vivienda'),
            style: FilledButton.styleFrom(
              backgroundColor: PaletteScope.of(context).primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _viviendaTile(EdanDanoVivienda fila, EdanVivienda viv) {
    final esTotal = viv.tipoDano == EdanViviendaTipo.total;
    final color = esTotal ? AppColors.error : const Color(0xFFB26A00);
    final tieneFoto = viv.fotografia != null && viv.fotografia!.isNotEmpty;
    final tieneCoords = viv.coordenadaLat != 0 || viv.coordenadaLon != 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _editarVivienda(fila, viv),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              if (tieneFoto)
                EdanFotoMiniatura(
                  fotografia: viv.fotografia,
                  width: 40,
                  height: 40,
                  onTap: () => _editarVivienda(fila, viv),
                  onRetomar: () => _editarVivienda(fila, viv),
                )
              else
                Icon(
                  esTotal ? Icons.house_siding_outlined : Icons.home_work_outlined,
                  size: 18,
                  color: color,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      esTotal ? 'TOTAL' : 'PARCIAL',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tieneCoords
                          ? '${viv.coordenadaLat.toStringAsFixed(5)}, '
                              '${viv.coordenadaLon.toStringAsFixed(5)}'
                          : 'Sin coordenadas',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                    if (!tieneFoto) ...[
                      const SizedBox(height: 2),
                      const Text(
                        'Sin foto — tocar para capturar',
                        style: TextStyle(fontSize: 11, color: Color(0xFFD97706)),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textSecondary),
                onSelected: (op) {
                  switch (op) {
                    case 'editar':
                      _editarVivienda(fila, viv);
                    case 'eliminar':
                      _eliminarVivienda(viv);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'editar', child: Text('Editar')),
                  PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
