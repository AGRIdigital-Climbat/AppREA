import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import '../../../../models/reporte.dart';
import '../../../../providers/reporte_provider.dart';
import 'edan_boton_sacar_foto.dart';
import 'edan_dialog_helper.dart';
import 'edan_item_card.dart';
import 'edan_subsection_header.dart';
import 'edan_aviso.dart';

/// Página 09: Impacto agropecuario.
///
/// Contiene tres grupos de ítems, cada uno con su propio [id_seccion]:
/// - daños en agricultura (cultivos)
/// - daños en pecuarios
/// - infraestructura productiva
class EdanPage09 extends StatefulWidget {
  final EdanLocalidad localidad;

  const EdanPage09({super.key, required this.localidad});

  @override
  State<EdanPage09> createState() => _EdanPage09State();
}

class _EdanPage09State extends State<EdanPage09> {
  final _afectadasAg = TextEditingController();
  final _perdidasAg = TextEditingController();
  final _necAg = TextEditingController();
  final _obsAg = TextEditingController();
  final _razaPc = TextEditingController();
  final _afectadosPc = TextEditingController();
  final _muertosPc = TextEditingController();
  final _necPc = TextEditingController();
  final _tipoIp = TextEditingController();
  final _parcialIp = TextEditingController();
  final _totalIp = TextEditingController();

  @override
  void dispose() {
    _afectadasAg.dispose();
    _perdidasAg.dispose();
    _necAg.dispose();
    _obsAg.dispose();
    _razaPc.dispose();
    _afectadosPc.dispose();
    _muertosPc.dispose();
    _necPc.dispose();
    _tipoIp.dispose();
    _parcialIp.dispose();
    _totalIp.dispose();
    super.dispose();
  }

  // ─── Agricultura ───
  void _agregarAgricultura() {
    final a = EdanDanoAgricultura();
    _editarAgricultura(a, esNuevo: true);
  }

  Future<void> _editarAgricultura(EdanDanoAgricultura a,
      {bool esNuevo = false}) async {
    final cultivos =
        Provider.of<ReporteProvider>(context, listen: false).cultivos;
    _afectadasAg.text =
        a.hectareasAfectadas > 0 ? '${a.hectareasAfectadas}' : '';
    _perdidasAg.text = a.hectareasPerdidas > 0 ? '${a.hectareasPerdidas}' : '';
    _necAg.text = a.necesidadesInmediatas;
    _obsAg.text = a.observaciones;
    int? selCultivo =
        cultivos.any((c) => c.idCultivo == a.idCultivo) ? a.idCultivo : null;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          title: const Text('Daño en cultivo'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _campoTitulo('Tipo de cultivo'),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () => _abrirSelectorCultivos(
                    ctx,
                    cultivos,
                    selCultivo,
                    (v) => setLocal(() => selCultivo = v),
                  ),
                  child: InputDecorator(
                    isEmpty:
                        !cultivos.any((c) => c.idCultivo == selCultivo),
                    decoration: const InputDecoration(
                        hintText: 'Seleccione un cultivo'),
                    child: Text(
                      cultivos.where((c) => c.idCultivo == selCultivo).isNotEmpty
                          ? cultivos
                              .firstWhere((c) => c.idCultivo == selCultivo)
                              .nombre
                          : '',
                      style: TextStyle(
                        fontSize: 14,
                        color: selCultivo != null
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _campoTitulo('N° Hectáreas afectadas'),
                const SizedBox(height: 6),
                TextField(
                  controller: _afectadasAg,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(hintText: 'Ej: 8'),
                ),
                const SizedBox(height: 12),
                _campoTitulo('N° Hectáreas perdidas'),
                const SizedBox(height: 6),
                TextField(
                  controller: _perdidasAg,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(hintText: 'Ej: 3'),
                ),
                const SizedBox(height: 12),
                _campoTitulo('Necesidades inmediatas'),
                const SizedBox(height: 6),
                TextField(
                  controller: _necAg,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      hintText: 'Ej: Semillas, fertilizantes'),
                ),
                const SizedBox(height: 12),
                _campoTitulo('Observaciones'),
                const SizedBox(height: 6),
                TextField(
                  controller: _obsAg,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      hintText: 'Ej: Cultivo de maíz sin regadío'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar')),
          ],
        ),
      ),
    );

    if (!mounted || saved != true) return;
    setState(() {
      final sel = cultivos.where((c) => c.idCultivo == selCultivo);
      a.idCultivo = selCultivo;
      a.tipoCultivo = sel.isNotEmpty ? sel.first.nombre : '';
      a.hectareasAfectadas = int.tryParse(_afectadasAg.text) ?? 0;
      a.hectareasPerdidas = int.tryParse(_perdidasAg.text) ?? 0;
      a.necesidadesInmediatas = _necAg.text;
      a.observaciones = _obsAg.text;
      if (esNuevo) widget.localidad.danosAgricultura.add(a);
    });
  }

  // ─── Pecuario ───
  void _agregarPecuario() {
    final p = EdanDanoPecuario();
    _editarPecuario(p, esNuevo: true);
  }

  Future<void> _editarPecuario(EdanDanoPecuario p,
      {bool esNuevo = false}) async {
    final grupos = Provider.of<ReporteProvider>(context, listen: false)
        .pecuarioGrupos;
    _razaPc.text = p.raza;
    _afectadosPc.text =
        p.animalesAfectados > 0 ? '${p.animalesAfectados}' : '';
    _muertosPc.text = p.animalesMuertos > 0 ? '${p.animalesMuertos}' : '';
    _necPc.text = p.necesidadesInmediatas;
    int? selEspecie = grupos.any((g) => g.idPecuarioGrupo == p.idEspecie)
        ? p.idEspecie
        : null;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          title: const Text('Daño en especie pecuaria'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _campoTitulo('Especie'),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () => _abrirSelectorEspecie(
                    ctx,
                    grupos,
                    selEspecie,
                    (v) => setLocal(() => selEspecie = v),
                  ),
                  child: InputDecorator(
                    isEmpty: !grupos.any((g) => g.idPecuarioGrupo == selEspecie),
                    decoration: const InputDecoration(
                        hintText: 'Seleccione una especie'),
                    child: Text(
                      grupos.where((g) => g.idPecuarioGrupo == selEspecie).isNotEmpty
                          ? grupos
                              .firstWhere((g) => g.idPecuarioGrupo == selEspecie)
                              .nombre
                          : '',
                      style: TextStyle(
                        fontSize: 14,
                        color: selEspecie != null
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _campoTitulo('Raza'),
                const SizedBox(height: 6),
                TextField(
                  controller: _razaPc,
                  decoration: const InputDecoration(hintText: 'Ej: Holstein'),
                ),
                const SizedBox(height: 12),
                _campoTitulo('N° Animales afectados'),
                const SizedBox(height: 6),
                TextField(
                  controller: _afectadosPc,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(hintText: 'Ej: 40'),
                ),
                const SizedBox(height: 12),
                _campoTitulo('N° Animales muertos'),
                const SizedBox(height: 6),
                TextField(
                  controller: _muertosPc,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(hintText: 'Ej: 5'),
                ),
                const SizedBox(height: 12),
                _campoTitulo('Necesidades inmediatas'),
                const SizedBox(height: 6),
                TextField(
                  controller: _necPc,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      hintText: 'Ej: Concentrado, sal mineral, forraje'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar')),
          ],
        ),
      ),
    );

    if (!mounted || saved != true) return;
    setState(() {
      final sel = grupos.where((g) => g.idPecuarioGrupo == selEspecie);
      p.idEspecie = selEspecie;
      p.especie = sel.isNotEmpty ? sel.first.nombre : '';
      p.raza = _razaPc.text;
      p.animalesAfectados = int.tryParse(_afectadosPc.text) ?? 0;
      p.animalesMuertos = int.tryParse(_muertosPc.text) ?? 0;
      p.necesidadesInmediatas = _necPc.text;
      if (esNuevo) widget.localidad.danosPecuarios.add(p);
    });
  }

  // ─── Infraestructura productiva ───
  void _agregarInfra() {
    final i = EdanInfraProductiva();
    _editarInfra(i, esNuevo: true);
  }

  Future<void> _editarInfra(EdanInfraProductiva i,
      {bool esNuevo = false}) async {
    _tipoIp.text = i.tipo;
    _parcialIp.text = i.danoParcial > 0 ? '${i.danoParcial}' : '';
    _totalIp.text = i.danoTotal > 0 ? '${i.danoTotal}' : '';

    final saved = await _dialogo(
      titulo: 'Infraestructura productiva',
      camposTexto: {
        _tipoIp: 'Tipo',
      },
      labels: {
        _parcialIp: 'N° Daño parcial',
        _totalIp: 'N° Daño total',
      },
      nec: null,
      hints: {
        _tipoIp: 'Ej: Almacén, silo, galpón',
        _parcialIp: 'Ej: 2',
        _totalIp: 'Ej: 1',
      },
    );

    if (!mounted || !saved) return;
    setState(() {
      i.tipo = _tipoIp.text;
      i.danoParcial = int.tryParse(_parcialIp.text) ?? 0;
      i.danoTotal = int.tryParse(_totalIp.text) ?? 0;
      if (esNuevo) widget.localidad.infraProductiva.add(i);
    });
  }

  Future<void> _abrirSelectorCultivos(
    BuildContext ctx,
    List<Cultivo> cultivos,
    int? actual,
    void Function(int?) onSeleccion,
  ) async {
    final sorted =
        (cultivos.toList()..sort((x, y) => x.nombre.compareTo(y.nombre)));
    final seleccion = await showModalBottomSheet<int>(
      context: ctx,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Tipo de cultivo',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: sorted.length,
                itemBuilder: (context, i) {
                  final c = sorted[i];
                  return ListTile(
                    title: Text(c.nombre),
                    trailing: c.idCultivo == actual
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () => Navigator.pop(sheetCtx, c.idCultivo),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    onSeleccion(seleccion);
  }

  Future<void> _abrirSelectorEspecie(
    BuildContext ctx,
    List<PecuarioGrupo> grupos,
    int? actual,
    void Function(int?) onSeleccion,
  ) async {
    final sorted =
        (grupos.toList()..sort((x, y) => x.nombre.compareTo(y.nombre)));
    final seleccion = await showModalBottomSheet<int>(
      context: ctx,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Especie',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: sorted.length,
                itemBuilder: (context, i) {
                  final g = sorted[i];
                  return ListTile(
                    title: Text(g.nombre),
                    trailing: g.idPecuarioGrupo == actual
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () => Navigator.pop(sheetCtx, g.idPecuarioGrupo),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    onSeleccion(seleccion);
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

  Future<bool> _dialogo({
    required String titulo,
    required Map<TextEditingController, String> camposTexto,
    required Map<TextEditingController, String> labels,
    required TextEditingController? nec,
    Map<TextEditingController, String>? hints,
  }) async {
    Widget input(
      TextEditingController c,
      String label, {
      TextInputType? kb,
      List<TextInputFormatter>? fmt,
      bool multiline = false,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _campoTitulo(label),
          const SizedBox(height: 6),
          TextField(
            controller: c,
            keyboardType: kb,
            inputFormatters: fmt,
            maxLines: multiline ? 3 : 1,
            decoration: InputDecoration(hintText: hints?[c]),
          ),
          const SizedBox(height: 12),
        ],
      );
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          title: Text(titulo),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...camposTexto.entries
                    .map((e) => input(e.key, e.value)),
                ...labels.entries.map((e) => input(
                      e.key,
                      e.value,
                      kb: TextInputType.number,
                      fmt: [FilteringTextInputFormatter.digitsOnly],
                    )),
                if (nec != null) input(nec, 'Necesidades inmediatas', multiline: true),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
                  onPressed: () {
                    final tieneDatos = camposTexto.keys.any((controller) => controller.text.isNotEmpty);
                    if (!tieneDatos) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No hay datos para guardar')),
                      );
                      Navigator.pop(ctx, false);
                    } else {
                      Navigator.pop(ctx, true);
                    }
                  },
                  child: const Text('Guardar')),
          ],
        ),
      ),
    );
    return saved ?? false;
  }

  Future<void> _fotoAgricultura(EdanDanoAgricultura a) async {
    final ok = await EdanBotonSacarFoto.mostrarSheetFoto(
      context,
      fotos: a.fotos,
      latActual: a.coordenadaLat,
      lonActual: a.coordenadaLon,
      seccion: 'Agricultura',
      idLocal: widget.localidad.idLocal,
      idSeccion: a.idSeccion,
      idEdanLocalidad: widget.localidad.idServer ?? widget.localidad.idEdan,
      onCoordenadasCapturadas: (lat, lon) {
        a.coordenadaLat = lat;
        a.coordenadaLon = lon;
      },
      onFotoGuardada: (path) => a.fotografia = path,
    );
    if (!ok || !mounted) return;
    setState(() {});
  }

  Future<void> _fotoPecuario(EdanDanoPecuario p) async {
    final ok = await EdanBotonSacarFoto.mostrarSheetFoto(
      context,
      fotos: p.fotos,
      latActual: p.coordenadaLat,
      lonActual: p.coordenadaLon,
      seccion: 'Pecuario',
      idLocal: widget.localidad.idLocal,
      idSeccion: p.idSeccion,
      idEdanLocalidad: widget.localidad.idServer ?? widget.localidad.idEdan,
      onCoordenadasCapturadas: (lat, lon) {
        p.coordenadaLat = lat;
        p.coordenadaLon = lon;
      },
      onFotoGuardada: (path) => p.fotografia = path,
    );
    if (!ok || !mounted) return;
    setState(() {});
  }

  Future<void> _fotoInfra(EdanInfraProductiva i) async {
    final ok = await EdanBotonSacarFoto.mostrarSheetFoto(
      context,
      fotos: i.fotos,
      latActual: i.coordenadaLat,
      lonActual: i.coordenadaLon,
      seccion: 'Infraestructura productiva',
      idLocal: widget.localidad.idLocal,
      idSeccion: i.idSeccion,
      idEdanLocalidad: widget.localidad.idServer ?? widget.localidad.idEdan,
      onCoordenadasCapturadas: (lat, lon) {
        i.coordenadaLat = lat;
        i.coordenadaLon = lon;
      },
      onFotoGuardada: (path) => i.fotografia = path,
    );
    if (!ok || !mounted) return;
    setState(() {});
  }

  Future<void> _eliminarAgricultura(EdanDanoAgricultura a) async {
    final ok = await eliminarItemSeccion(
      context,
      localidad: widget.localidad,
      idSeccion: a.idSeccion,
      rutaV2: 'danos-agricultura',
      tablaSqlite: 'seccion_danos_agricultura',
      titulo: '¿Eliminar cultivo?',
      mensaje: 'Se eliminará el registro de "${a.tipoCultivo}".',
    );
    if (!ok || !mounted) return;
    setState(() => widget.localidad.danosAgricultura.remove(a));
  }

  Future<void> _eliminarPecuario(EdanDanoPecuario p) async {
    final ok = await eliminarItemSeccion(
      context,
      localidad: widget.localidad,
      idSeccion: p.idSeccion,
      rutaV2: 'danos-pecuarios',
      tablaSqlite: 'seccion_danos_pecuarios',
      titulo: '¿Eliminar especie?',
      mensaje: 'Se eliminará el registro de "${p.especie}".',
    );
    if (!ok || !mounted) return;
    setState(() => widget.localidad.danosPecuarios.remove(p));
  }

  Future<void> _eliminarInfra(EdanInfraProductiva i) async {
    final ok = await eliminarItemSeccion(
      context,
      localidad: widget.localidad,
      idSeccion: i.idSeccion,
      rutaV2: 'infra-productiva',
      tablaSqlite: 'seccion_infra_productiva',
      titulo: '¿Eliminar infraestructura?',
      mensaje: 'Se eliminará el registro de "${i.tipo}" infraestructura productiva.',
    );
    if (!ok || !mounted) return;
    setState(() => widget.localidad.infraProductiva.remove(i));
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.localidad;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _bloque(
          titulo: 'Daños en agricultura',
          icono: Icons.agriculture_outlined,
          count: l.danosAgricultura.length,
          onAgregar: _agregarAgricultura,
          aviso: 'Presiona en agregar para registrar la afectación en '
              'agricultura. Puedes agregar más de uno.',
          items: l.danosAgricultura.map((a) => EdanItemCard(
                titulo: a.tipoCultivo.isEmpty ? 'Cultivo' : a.tipoCultivo,
                subtitulo: [
                  if (a.hectareasAfectadas > 0) '${a.hectareasAfectadas} ha afectadas',
                  if (a.hectareasPerdidas > 0) '${a.hectareasPerdidas} ha perdidas',
                ].join(' · '),
                icono: Icons.agriculture_outlined,
                onEditar: () => _editarAgricultura(a),
                onEliminar: () => _eliminarAgricultura(a),
                onRespaldar: () => _fotoAgricultura(a),
                onCambiarFoto: () => _fotoAgricultura(a),
                respaldo: a,
                seccionRespaldo: 'Agricultura',
                onFotoEliminada: () => setState(() {}),
              )).toList(),
        ),
        _bloque(
          titulo: 'Daños en pecuarios',
          icono: Icons.pets_outlined,
          count: l.danosPecuarios.length,
          onAgregar: _agregarPecuario,
          aviso: 'Presiona en agregar para registrar la afectación en '
              'pecuarios. Puedes agregar más de uno.',
          items: l.danosPecuarios.map((p) => EdanItemCard(
                titulo: p.especie.isEmpty ? 'Especie' : p.especie,
                subtitulo: [
                  if (p.raza.isNotEmpty) p.raza,
                  if (p.animalesAfectados > 0) '${p.animalesAfectados} afectados',
                  if (p.animalesMuertos > 0) '${p.animalesMuertos} muertos',
                ].join(' · '),
                icono: Icons.pets_outlined,
                onEditar: () => _editarPecuario(p),
                onEliminar: () => _eliminarPecuario(p),
                onRespaldar: () => _fotoPecuario(p),
                onCambiarFoto: () => _fotoPecuario(p),
                respaldo: p,
                seccionRespaldo: 'Pecuario',
                onFotoEliminada: () => setState(() {}),
              )).toList(),
        ),
        _bloque(
          titulo: 'Infraestructura productiva',
          icono: Icons.factory_outlined,
          count: l.infraProductiva.length,
          onAgregar: _agregarInfra,
          aviso: 'Presiona en agregar para registrar la afectación en '
              'infraestructura productiva. Puedes agregar más de una.',
          items: l.infraProductiva.map((i) => EdanItemCard(
                titulo: i.tipo.isEmpty ? 'Infraestructura' : i.tipo,
                subtitulo: [
                  if (i.danoParcial > 0) 'Parcial',
                  if (i.danoTotal > 0) 'Total',
                ].join(' · '),
                icono: Icons.factory_outlined,
                onEditar: () => _editarInfra(i),
                onEliminar: () => _eliminarInfra(i),
                onRespaldar: () => _fotoInfra(i),
                onCambiarFoto: () => _fotoInfra(i),
                respaldo: i,
                seccionRespaldo: 'Infraestructura productiva',
                onFotoEliminada: () => setState(() {}),
              )).toList(),
        ),
      ],
    );
  }

  Widget _bloque({
    required String titulo,
    required IconData icono,
    required int count,
    required VoidCallback onAgregar,
    required String aviso,
    required List<Widget> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EdanAvisoAfectaciones(texto: aviso),
        const SizedBox(height: 10),
        EdanSubsectionHeader(
          titulo: titulo,
          icono: icono,
          onAgregar: onAgregar,
          itemCount: count,
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Sin registros.',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          )
        else
          ...items,
        const SizedBox(height: 16),
      ],
    );
  }
}
