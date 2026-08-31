import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import '../../../../models/id_seccion_helper.dart';
import 'edan_boton_sacar_foto.dart';
import 'edan_dialog_helper.dart';
import 'edan_item_card.dart';
import 'edan_subsection_header.dart';

/// Página 08: Impacto en viviendas (daño parcial y total).
class EdanPage08 extends StatefulWidget {
  final EdanLocalidad localidad;

  const EdanPage08({super.key, required this.localidad});

  @override
  State<EdanPage08> createState() => _EdanPage08State();
}

class _EdanPage08State extends State<EdanPage08> {
  final _comunidad = TextEditingController();
  final _parcial = TextEditingController();
  final _total = TextEditingController();
  final _nec = TextEditingController();

  @override
  void dispose() {
    _comunidad.dispose();
    _parcial.dispose();
    _total.dispose();
    _nec.dispose();
    super.dispose();
  }

  void _agregar() {
    final v = EdanDanoVivienda(idSeccion: generarIdSeccion('dv'));
    setState(() => widget.localidad.danosVivienda.add(v));
    _editar(v);
  }

  Future<void> _editar(EdanDanoVivienda v) async {
    _comunidad.text = v.comunidad;
    _parcial.text = v.danoParcial > 0 ? '${v.danoParcial}' : '';
    _total.text = v.danoTotal > 0 ? '${v.danoTotal}' : '';
    _nec.text = v.necesidadesInmediatas;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          title: const Text('Daño en viviendas'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: _comunidad, decoration: const InputDecoration(labelText: 'Comunidad')),
                const SizedBox(height: 8),
                TextField(controller: _parcial, keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'N° Viviendas con daño parcial')),
                const SizedBox(height: 8),
                TextField(controller: _total, keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'N° Viviendas con daño total')),
                const SizedBox(height: 8),
                TextField(controller: _nec, maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Necesidades inmediatas')),
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
    if (!mounted) return;

    setState(() {
      v.comunidad = _comunidad.text;
      v.danoParcial = int.tryParse(_parcial.text) ?? 0;
      v.danoTotal = int.tryParse(_total.text) ?? 0;
      v.necesidadesInmediatas = _nec.text;
    });
  }

  Future<void> _capturarRespaldo(EdanDanoVivienda v) async {
    final ok = await EdanBotonSacarFoto.capturarRespaldo(
      context,
      fotos: v.fotos,
      latActual: v.coordenadaLat,
      lonActual: v.coordenadaLon,
      onCoordenadasCapturadas: (lat, lon) {
        v.coordenadaLat = lat;
        v.coordenadaLon = lon;
      },
    );
    if (!ok || !mounted) return;
    setState(() {});
  }

  Future<void> _eliminar(EdanDanoVivienda v) async {
    final ok = await confirmarEliminacion(
      context,
      titulo: '¿Eliminar vivienda?',
      mensaje: 'Se eliminará el registro de daño en viviendas.',
    );
    if (!ok || !mounted) return;
    setState(() => widget.localidad.danosVivienda.remove(v));
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.localidad;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EdanSubsectionHeader(
          titulo: 'Daños en viviendas',
          icono: Icons.home_outlined,
          onAgregar: _agregar,
          itemCount: l.danosVivienda.length,
        ),
        const SizedBox(height: 10),
        if (l.danosVivienda.isEmpty)
          const Text(
            'Toca "Agregar" para registrar daños en viviendas.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          )
        else
          ...l.danosVivienda.map((v) => EdanItemCard(
                titulo: v.comunidad.isEmpty ? 'Comunidad' : v.comunidad,
                subtitulo: [
                  if (v.danoParcial > 0) '${v.danoParcial} parcial',
                  if (v.danoTotal > 0) '${v.danoTotal} total',
                ].join(' · '),
                icono: Icons.home_outlined,
                onEditar: () => _editar(v),
                onEliminar: () => _eliminar(v),
                onRespaldar: () => _capturarRespaldo(v),
                respaldo: v,
                seccionRespaldo: 'Viviendas',
                onFotoEliminada: () => setState(() {}),
              )),
      ],
    );
  }
}
