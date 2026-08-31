import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../models/edan.dart';
import '../../../../models/id_seccion_helper.dart';
import 'edan_boton_sacar_foto.dart';
import 'edan_dialog_helper.dart';
import 'edan_item_card.dart';
import 'edan_subsection_header.dart';

/// Página 05: Impacto en infraestructuras (vías y puentes + infra pública).
class EdanPage05 extends StatefulWidget {
  final EdanLocalidad localidad;

  const EdanPage05({super.key, required this.localidad});

  @override
  State<EdanPage05> createState() => _EdanPage05State();
}

class _EdanPage05State extends State<EdanPage05> {
  final _viaPuente = TextEditingController();
  final _tramo = TextEditingController();
  final _km = TextEditingController();
  final _nec = TextEditingController();
  final _tipo = TextEditingController();
  final _comunidad = TextEditingController();
  final _obs = TextEditingController();
  bool _parcialVial = false;
  bool _totalVial = false;
  bool _parcialInfra = false;
  bool _totalInfra = false;

  @override
  void dispose() {
    _viaPuente.dispose();
    _tramo.dispose();
    _km.dispose();
    _nec.dispose();
    _tipo.dispose();
    _comunidad.dispose();
    _obs.dispose();
    super.dispose();
  }
  void _agregarVial() {
    final v = EdanDanoVial(idSeccion: generarIdSeccion('sv'));
    setState(() => widget.localidad.danosViales.add(v));
    _editarVial(v);
  }

  Future<void> _editarVial(EdanDanoVial v) async {
    _viaPuente.text = v.viaPuente;
    _tramo.text = v.tramo;
    _km.text = v.kmDanio > 0 ? '${v.kmDanio}' : '';
    _nec.text = v.necesidadesInmediatas;
    _parcialVial = v.danoParcial;
    _totalVial = v.danoTotal;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          title: const Text('Daño vial / puente'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: _viaPuente, decoration: const InputDecoration(labelText: 'Vía o puente')),
                const SizedBox(height: 8),
                TextField(controller: _tramo, decoration: const InputDecoration(labelText: 'Tramo')),
                const SizedBox(height: 8),
                TextField(controller: _km, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'N° Km de daño')),
                const SizedBox(height: 8),
                EdanCheckRow(label: 'Daño parcial', value: _parcialVial,
                    onChanged: (x) => setLocal(() => _parcialVial = x)),
                EdanCheckRow(label: 'Daño total', value: _totalVial,
                    onChanged: (x) => setLocal(() => _totalVial = x)),
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
      v.viaPuente = _viaPuente.text;
      v.tramo = _tramo.text;
      v.kmDanio = double.tryParse(_km.text) ?? 0;
      v.danoParcial = _parcialVial;
      v.danoTotal = _totalVial;
      v.necesidadesInmediatas = _nec.text;
    });
  }

  void _agregarInfra() {
    final i = EdanDanoInfraPublica(idSeccion: generarIdSeccion('di'));
    setState(() => widget.localidad.danosInfraPublica.add(i));
    _editarInfra(i);
  }

  Future<void> _editarInfra(EdanDanoInfraPublica i) async {
    _tipo.text = i.tipoEstructura;
    _comunidad.text = i.comunidad;
    _obs.text = i.observaciones;
    _parcialInfra = i.danoParcial;
    _totalInfra = i.danoTotal;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          title: const Text('Infraestructura pública'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: _tipo, decoration: const InputDecoration(labelText: 'Tipo de estructura')),
                const SizedBox(height: 8),
                TextField(controller: _comunidad, decoration: const InputDecoration(labelText: 'Comunidad')),
                const SizedBox(height: 8),
                EdanCheckRow(label: 'Daño parcial', value: _parcialInfra,
                    onChanged: (x) => setLocal(() => _parcialInfra = x)),
                EdanCheckRow(label: 'Daño total', value: _totalInfra,
                    onChanged: (x) => setLocal(() => _totalInfra = x)),
                const SizedBox(height: 8),
                TextField(controller: _obs, maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Observaciones')),
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
      i.tipoEstructura = _tipo.text;
      i.comunidad = _comunidad.text;
      i.danoParcial = _parcialInfra;
      i.danoTotal = _totalInfra;
      i.observaciones = _obs.text;
    });
  }

  Future<void> _eliminarVial(EdanDanoVial v) async {
    final ok = await confirmarEliminacion(
      context,
      titulo: '¿Eliminar vía o puente?',
      mensaje: 'Se eliminará el registro "${v.viaPuente}".',
    );
    if (!ok || !mounted) return;
    setState(() => widget.localidad.danosViales.remove(v));
  }

  Future<void> _eliminarInfra(EdanDanoInfraPublica i) async {
    final ok = await confirmarEliminacion(
      context,
      titulo: '¿Eliminar infraestructura?',
      mensaje: 'Se eliminará el registro de daño a infraestructura pública.',
    );
    if (!ok || !mounted) return;
    setState(() => widget.localidad.danosInfraPublica.remove(i));
  }

  Future<void> _capturarRespaldoVial(EdanDanoVial v) async {
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

  Future<void> _capturarRespaldoInfra(EdanDanoInfraPublica i) async {
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

  @override
  Widget build(BuildContext context) {
    final l = widget.localidad;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EdanSubsectionHeader(
          titulo: 'Daños viales y puentes',
          icono: Icons.construction,
          onAgregar: _agregarVial,
          itemCount: l.danosViales.length,
        ),
        const SizedBox(height: 10),
        ...l.danosViales.map((v) => EdanItemCard(
              titulo: v.viaPuente.isEmpty ? 'Vía/puente' : v.viaPuente,
              subtitulo: [
                if (v.tramo.isNotEmpty) v.tramo,
                if (v.kmDanio > 0) '${v.kmDanio} km',
                if (v.danoParcial) 'Parcial',
                if (v.danoTotal) 'Total',
              ].join(' · '),
              icono: Icons.construction,
              onEditar: () => _editarVial(v),
              onEliminar: () => _eliminarVial(v),
              onRespaldar: () => _capturarRespaldoVial(v),
              respaldo: v,
              seccionRespaldo: 'Vías y puentes',
              onFotoEliminada: () => setState(() {}),
            )),
        const SizedBox(height: 18),
        EdanSubsectionHeader(
          titulo: 'Infraestructura pública',
          icono: Icons.apartment_outlined,
          onAgregar: _agregarInfra,
          itemCount: l.danosInfraPublica.length,
        ),
        const SizedBox(height: 10),
        ...l.danosInfraPublica.map((i) => EdanItemCard(
              titulo: i.tipoEstructura.isEmpty ? 'Estructura' : i.tipoEstructura,
              subtitulo: [
                if (i.comunidad.isNotEmpty) i.comunidad,
                if (i.danoParcial) 'Parcial',
                if (i.danoTotal) 'Total',
              ].join(' · '),
              icono: Icons.apartment_outlined,
              onEditar: () => _editarInfra(i),
              onEliminar: () => _eliminarInfra(i),
              onRespaldar: () => _capturarRespaldoInfra(i),
              respaldo: i,
              seccionRespaldo: 'Infraestructura pública',
              onFotoEliminada: () => setState(() {}),
            )),
      ],
    );
  }
}
