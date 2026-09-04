import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import 'edan_boton_sacar_foto.dart';
import 'edan_dialog_helper.dart';
import 'edan_item_card.dart';
import 'edan_subsection_header.dart';
import 'edan_aviso.dart';

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

  void _agregar() {
    final v = EdanDanoVivienda();
    _editar(v, esNuevo: true);
  }

  Future<void> _editar(EdanDanoVivienda v,
      {bool esNuevo = false}) async {
    _comunidad.text = v.comunidad.isNotEmpty
        ? v.comunidad
        : widget.localidad.nombre;
    _parcial.text = v.danoParcial > 0 ? '${v.danoParcial}' : '';
    _total.text = v.danoTotal > 0 ? '${v.danoTotal}' : '';
    _nec.text = v.necesidadesInmediatas;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          title: const Text('Daño en viviendas'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _campoTitulo('Localidad'),
                const SizedBox(height: 6),
                TextField(controller: _comunidad),
                const SizedBox(height: 12),
                _campoTitulo('N° Viviendas con daño parcial'),
                const SizedBox(height: 6),
                TextField(controller: _parcial, keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
                const SizedBox(height: 12),
                _campoTitulo('N° Viviendas con daño total'),
                const SizedBox(height: 6),
                TextField(controller: _total, keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
                const SizedBox(height: 12),
                _campoTitulo('Necesidades inmediatas'),
                const SizedBox(height: 6),
                TextField(controller: _nec, maxLines: 2),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (!mounted || saved != true) return;

    setState(() {
      v.comunidad = _comunidad.text;
      v.danoParcial = int.tryParse(_parcial.text) ?? 0;
      v.danoTotal = int.tryParse(_total.text) ?? 0;
      v.necesidadesInmediatas = _nec.text;
      if (esNuevo) widget.localidad.danosVivienda.add(v);
    });
  }

  Future<void> _foto(EdanDanoVivienda v) async {
    final ok = await EdanBotonSacarFoto.mostrarSheetFoto(
      context,
      fotos: v.fotos,
      latActual: v.coordenadaLat,
      lonActual: v.coordenadaLon,
      seccion: 'Viviendas',
      idLocal: widget.localidad.idLocal,
      idSeccion: v.idSeccion,
      idEdanLocalidad: widget.localidad.idServer ?? widget.localidad.idEdan,
      onCoordenadasCapturadas: (lat, lon) {
        v.coordenadaLat = lat;
        v.coordenadaLon = lon;
      },
      onFotoGuardada: (path) => v.fotografia = path,
    );
    if (!ok || !mounted) return;
    setState(() {});
  }

  Future<void> _eliminar(EdanDanoVivienda v) async {
    final ok = await eliminarItemSeccion(
      context,
      localidad: widget.localidad,
      idSeccion: v.idSeccion,
      rutaV2: 'danos-vivienda',
      tablaSqlite: 'seccion_danos_vivienda',
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
        EdanAvisoAfectaciones(
          texto: 'Presiona en agregar para registrar la afectación en una '
              'vivienda. Puedes agregar más de una.',
        ),
        const SizedBox(height: 10),
        EdanSubsectionHeader(
          titulo: 'Daños en viviendas',
          icono: Icons.home_outlined,
          onAgregar: _agregar,
          itemCount: l.danosVivienda.length,
        ),
        const SizedBox(height: 10),
        ...l.danosVivienda.map((v) => EdanItemCard(
                titulo: v.comunidad.isEmpty ? widget.localidad.nombre : v.comunidad,
                subtitulo: [
                  if (v.danoParcial > 0) '${v.danoParcial} parcial',
                  if (v.danoTotal > 0) '${v.danoTotal} total',
                ].join(' · '),
                icono: Icons.home_outlined,
                onEditar: () => _editar(v),
                onEliminar: () => _eliminar(v),
                onRespaldar: () => _foto(v),
                onCambiarFoto: () => _foto(v),
                respaldo: v,
                seccionRespaldo: 'Viviendas',
                onFotoEliminada: () => setState(() {}),
              )),
      ],
    );
  }
}
