import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import '../../../../models/id_seccion_helper.dart';
import 'edan_boton_sacar_foto.dart';
import 'edan_dialog_helper.dart';
import 'edan_item_card.dart';
import 'edan_subsection_header.dart';

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
  // ─── Agricultura ───
  void _agregarAgricultura() {
    final a = EdanDanoAgricultura(idSeccion: generarIdSeccion('ag'));
    setState(() => widget.localidad.danosAgricultura.add(a));
    _editarAgricultura(a);
  }

  Future<void> _editarAgricultura(EdanDanoAgricultura a) async {
    final cultivo = TextEditingController(text: a.tipoCultivo);
    final afectadas = TextEditingController(text: a.hectareasAfectadas > 0 ? '${a.hectareasAfectadas}' : '');
    final perdidas = TextEditingController(text: a.hectareasPerdidas > 0 ? '${a.hectareasPerdidas}' : '');
    final nec = TextEditingController(text: a.necesidadesInmediatas);

    await _dialogo(
      titulo: 'Daño en cultivo',
      campos: [
        TextField(controller: cultivo, decoration: const InputDecoration(labelText: 'Tipo de cultivo')),
      ],
      labels: {
        afectadas: 'N° Hectáreas afectadas',
        perdidas: 'N° Hectáreas perdidas',
      },
      nec: nec,
    );

    if (!mounted) return;
    setState(() {
      a.tipoCultivo = cultivo.text;
      a.hectareasAfectadas = int.tryParse(afectadas.text) ?? 0;
      a.hectareasPerdidas = int.tryParse(perdidas.text) ?? 0;
      a.necesidadesInmediatas = nec.text;
    });
    cultivo.dispose();
    afectadas.dispose();
    perdidas.dispose();
    nec.dispose();
  }

  // ─── Pecuario ───
  void _agregarPecuario() {
    final p = EdanDanoPecuario(idSeccion: generarIdSeccion('pc'));
    setState(() => widget.localidad.danosPecuarios.add(p));
    _editarPecuario(p);
  }

  Future<void> _editarPecuario(EdanDanoPecuario p) async {
    final especie = TextEditingController(text: p.especie);
    final raza = TextEditingController(text: p.raza);
    final afectados = TextEditingController(text: p.animalesAfectados > 0 ? '${p.animalesAfectados}' : '');
    final muertos = TextEditingController(text: p.animalesMuertos > 0 ? '${p.animalesMuertos}' : '');
    final nec = TextEditingController(text: p.necesidadesInmediatas);

    await _dialogo(
      titulo: 'Daño en especie pecuaria',
      campos: [
        TextField(controller: especie, decoration: const InputDecoration(labelText: 'Especie')),
        TextField(controller: raza, decoration: const InputDecoration(labelText: 'Raza')),
      ],
      labels: {
        afectados: 'N° Animales afectados',
        muertos: 'N° Animales muertos',
      },
      nec: nec,
    );

    if (!mounted) return;
    setState(() {
      p.especie = especie.text;
      p.raza = raza.text;
      p.animalesAfectados = int.tryParse(afectados.text) ?? 0;
      p.animalesMuertos = int.tryParse(muertos.text) ?? 0;
      p.necesidadesInmediatas = nec.text;
    });
    especie.dispose();
    raza.dispose();
    afectados.dispose();
    muertos.dispose();
    nec.dispose();
  }

  // ─── Infraestructura productiva ───
  void _agregarInfra() {
    final i = EdanInfraProductiva(idSeccion: generarIdSeccion('ip'));
    setState(() => widget.localidad.infraProductiva.add(i));
    _editarInfra(i);
  }

  Future<void> _editarInfra(EdanInfraProductiva i) async {
    final tipo = TextEditingController(text: i.tipo);
    final parcial = TextEditingController(text: i.danoParcial > 0 ? '${i.danoParcial}' : '');
    final total = TextEditingController(text: i.danoTotal > 0 ? '${i.danoTotal}' : '');

    await _dialogo(
      titulo: 'Infraestructura productiva',
      campos: [
        TextField(controller: tipo, decoration: const InputDecoration(labelText: 'Tipo')),
      ],
      labels: {
        parcial: 'N° Daño parcial',
        total: 'N° Daño total',
      },
      nec: null,
    );

    if (!mounted) return;
    setState(() {
      i.tipo = tipo.text;
      i.danoParcial = int.tryParse(parcial.text) ?? 0;
      i.danoTotal = int.tryParse(total.text) ?? 0;
    });
    tipo.dispose();
    parcial.dispose();
    total.dispose();
  }

  Future<void> _dialogo({
    required String titulo,
    required List<Widget> campos,
    required Map<TextEditingController, String> labels,
    required TextEditingController? nec,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          title: Text(titulo),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...campos,
                const SizedBox(height: 12),
                ...labels.entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: e.key,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(labelText: e.value),
                      ),
                    )),
                if (nec != null) ...[
                  const SizedBox(height: 8),
                  TextField(controller: nec, maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Necesidades inmediatas')),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Guardar')),
          ],
        ),
      ),
    );
  }

  Future<void> _capturarRespaldoAgricultura(EdanDanoAgricultura a) async {
    final ok = await EdanBotonSacarFoto.capturarRespaldo(
      context,
      fotos: a.fotos,
      latActual: a.coordenadaLat,
      lonActual: a.coordenadaLon,
      onCoordenadasCapturadas: (lat, lon) {
        a.coordenadaLat = lat;
        a.coordenadaLon = lon;
      },
    );
    if (!ok || !mounted) return;
    setState(() {});
  }

  Future<void> _capturarRespaldoPecuario(EdanDanoPecuario p) async {
    final ok = await EdanBotonSacarFoto.capturarRespaldo(
      context,
      fotos: p.fotos,
      latActual: p.coordenadaLat,
      lonActual: p.coordenadaLon,
      onCoordenadasCapturadas: (lat, lon) {
        p.coordenadaLat = lat;
        p.coordenadaLon = lon;
      },
    );
    if (!ok || !mounted) return;
    setState(() {});
  }

  Future<void> _capturarRespaldoInfra(EdanInfraProductiva i) async {
    final ok = await EdanBotonSacarFoto.capturarRespaldo(
      context,
      fotos: i.fotos,
      latActual: i.coordenadaLat,
      lonActual: i.coordenadaLon,
      onCoordenadasCapturadas: (lat, lon) {
        i.coordenadaLat = lat;
        i.coordenadaLon = lon;
      },
    );
    if (!ok || !mounted) return;
    setState(() {});
  }

  Future<void> _eliminarAgricultura(EdanDanoAgricultura a) async {
    final ok = await confirmarEliminacion(
      context,
      titulo: '¿Eliminar cultivo?',
      mensaje: 'Se eliminará el registro de "${a.tipoCultivo}".',
    );
    if (!ok || !mounted) return;
    setState(() => widget.localidad.danosAgricultura.remove(a));
  }

  Future<void> _eliminarPecuario(EdanDanoPecuario p) async {
    final ok = await confirmarEliminacion(
      context,
      titulo: '¿Eliminar especie?',
      mensaje: 'Se eliminará el registro de "${p.especie}".',
    );
    if (!ok || !mounted) return;
    setState(() => widget.localidad.danosPecuarios.remove(p));
  }

  Future<void> _eliminarInfra(EdanInfraProductiva i) async {
    final ok = await confirmarEliminacion(
      context,
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
          items: l.danosAgricultura.map((a) => EdanItemCard(
                titulo: a.tipoCultivo.isEmpty ? 'Cultivo' : a.tipoCultivo,
                subtitulo: [
                  if (a.hectareasAfectadas > 0) '${a.hectareasAfectadas} ha afectadas',
                  if (a.hectareasPerdidas > 0) '${a.hectareasPerdidas} ha perdidas',
                ].join(' · '),
                icono: Icons.agriculture_outlined,
                onEditar: () => _editarAgricultura(a),
                onEliminar: () => _eliminarAgricultura(a),
                onRespaldar: () => _capturarRespaldoAgricultura(a),
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
                onRespaldar: () => _capturarRespaldoPecuario(p),
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
          items: l.infraProductiva.map((i) => EdanItemCard(
                titulo: i.tipo.isEmpty ? 'Infraestructura' : i.tipo,
                subtitulo: [
                  if (i.danoParcial > 0) 'Parcial',
                  if (i.danoTotal > 0) 'Total',
                ].join(' · '),
                icono: Icons.factory_outlined,
                onEditar: () => _editarInfra(i),
                onEliminar: () => _eliminarInfra(i),
                onRespaldar: () => _capturarRespaldoInfra(i),
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
    required List<Widget> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
