import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import '../../../../models/id_seccion_helper.dart';
import 'edan_boton_sacar_foto.dart';
import 'edan_dialog_helper.dart';
import 'edan_item_card.dart';
import 'edan_subsection_header.dart';
import 'edan_aviso.dart';

const _tiposEstructura = [
  'Oficinas públicas',
  'Mercados',
  'Coliseo abierto',
  'Coliseo cerrado',
  'Estadio',
  'Plaza',
  'Parque',
  'Cancha de futbol',
  'Poli-deportivo',
];
const _tipoOtros = 'Otros';

/// Página 05: Impacto en infraestructuras (vías y puentes + infra pública).
class EdanPage05 extends StatefulWidget {
  final EdanLocalidad localidad;

  const EdanPage05({super.key, required this.localidad});

  @override
  State<EdanPage05> createState() => _EdanPage05State();
}

class _EdanPage05State extends State<EdanPage05> {
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
  String? _tipoVial;
  String? _tipoEstructuraSel;

  @override
  void dispose() {
    _tramo.dispose();
    _km.dispose();
    _nec.dispose();
    _tipo.dispose();
    _comunidad.dispose();
    _obs.dispose();
    super.dispose();
  }
  void _agregarVial() {
    final v = EdanDanoVial(idSeccion: nuevoIdDanoVial());
    _editarVial(v, esNuevo: true);
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

  Future<void> _editarVial(EdanDanoVial v,
      {bool esNuevo = false}) async {
    _tipoVial = v.viaPuente.isEmpty ? null : v.viaPuente;
    _tramo.text = v.tramo;
    _km.text = v.kmDanio > 0 ? '${v.kmDanio}' : '';
    _nec.text = v.necesidadesInmediatas;
    _parcialVial = v.danoParcial;
    _totalVial = v.danoTotal;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          title: const Text('Daño de vía o puente'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _campoTitulo('Tipo de vía o puente'),
                const SizedBox(height: 6),
                RadioGroup<String>(
                  groupValue: _tipoVial,
                  onChanged: (x) => setLocal(() => _tipoVial = x),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _RadioVial(valor: 'Carretera', etiqueta: 'Carretera'),
                      _RadioVial(valor: 'Camino', etiqueta: 'Camino'),
                      _RadioVial(valor: 'Túnel', etiqueta: 'Túnel'),
                      _RadioVial(valor: 'Puente', etiqueta: 'Puente'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _campoTitulo('Tramo / Tramo'),
                const SizedBox(height: 6),
                TextField(
                  controller: _tramo,
                  decoration: const InputDecoration(hintText: 'Ej: Tramo 1'),
                ),
                const SizedBox(height: 12),
                _campoTitulo('Tipo de daño'),
                const SizedBox(height: 6),
                RadioGroup<String>(
                  groupValue: _danoVialSeleccion(),
                  onChanged: (x) => setLocal(() {
                    _parcialVial = x == 'parcial';
                    _totalVial = x == 'total';
                  }),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _RadioVial(valor: 'parcial', etiqueta: 'Daño parcial'),
                      _RadioVial(valor: 'total', etiqueta: 'Daño total'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _campoTitulo('N° Km de daño'),
                const SizedBox(height: 6),
                TextField(
                  controller: _km,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(hintText: 'Ej: 3.5'),
                ),
                const SizedBox(height: 12),
                _campoTitulo('Necesidades inmediatas'),
                const SizedBox(height: 6),
                TextField(
                  controller: _nec,
                  maxLines: 2,
                  decoration: const InputDecoration(hintText: 'Ej: Maquinaria para despeje'),
                ),
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
      v.viaPuente = _tipoVial ?? '';
      v.tramo = _tramo.text;
      v.kmDanio = double.tryParse(_km.text) ?? 0;
      v.danoParcial = _parcialVial;
      v.danoTotal = _totalVial;
      v.necesidadesInmediatas = _nec.text;
      if (esNuevo) widget.localidad.danosViales.add(v);
    });
  }

  String? _danoVialSeleccion() {
    if (_parcialVial) return 'parcial';
    if (_totalVial) return 'total';
    return null;
  }

  String? _danoInfraSeleccion() {
    if (_parcialInfra) return 'parcial';
    if (_totalInfra) return 'total';
    return null;
  }

  void _agregarInfra() {
    final i = EdanDanoInfraPublica(idSeccion: nuevoIdDanoInfraPublica());
    _editarInfra(i, esNuevo: true);
  }

  Future<void> _editarInfra(EdanDanoInfraPublica i,
      {bool esNuevo = false}) async {
    _tipoEstructuraSel = _tiposEstructura.contains(i.tipoEstructura)
        ? i.tipoEstructura
        : (i.tipoEstructura.isEmpty ? null : _tipoOtros);
    _tipo.text = _tipoEstructuraSel == _tipoOtros ? i.tipoEstructura : '';
    _comunidad.text = i.comunidad.isNotEmpty
        ? i.comunidad
        : widget.localidad.nombre;
    _obs.text = i.observaciones;
    _parcialInfra = i.danoParcial;
    _totalInfra = i.danoTotal;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          title: const Text('Infraestructura pública'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _campoTitulo('Localidad'),
                const SizedBox(height: 6),
                TextField(
                  controller: _comunidad,
                  decoration: const InputDecoration(hintText: 'Ej: San José'),
                ),
                const SizedBox(height: 12),
                _campoTitulo('Tipo de estructura'),
                const SizedBox(height: 6),
                RadioGroup<String>(
                  groupValue: _tipoEstructuraSel,
                  onChanged: (x) => setLocal(() => _tipoEstructuraSel = x),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final t in _tiposEstructura)
                        _RadioVial(valor: t, etiqueta: t),
                      const _RadioVial(valor: _tipoOtros, etiqueta: 'Otros'),
                    ],
                  ),
                ),
                if (_tipoEstructuraSel == _tipoOtros) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _tipo,
                    decoration: const InputDecoration(
                        hintText: 'Ej: Biblioteca municipal'),
                  ),
                ],
                const SizedBox(height: 12),
                _campoTitulo('Magnitud de daño'),
                const SizedBox(height: 6),
                RadioGroup<String>(
                  groupValue: _danoInfraSeleccion(),
                  onChanged: (x) => setLocal(() {
                    _parcialInfra = x == 'parcial';
                    _totalInfra = x == 'total';
                  }),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _RadioVial(valor: 'parcial', etiqueta: 'Daño parcial'),
                      _RadioVial(valor: 'total', etiqueta: 'Daño total'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _campoTitulo('Observaciones'),
                const SizedBox(height: 6),
                TextField(
                  controller: _obs,
                  maxLines: 2,
                  decoration: const InputDecoration(hintText: 'Ej: Requiere evaluación estructural'),
                ),
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
      i.tipoEstructura = _tipoEstructuraSel == _tipoOtros
          ? _tipo.text.trim()
          : (_tipoEstructuraSel ?? '');
      i.comunidad = _comunidad.text;
      i.danoParcial = _parcialInfra;
      i.danoTotal = _totalInfra;
      i.observaciones = _obs.text;
      if (esNuevo) widget.localidad.danosInfraPublica.add(i);
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

  Future<void> _fotoVial(EdanDanoVial v) async {
    final ok = await EdanBotonSacarFoto.mostrarSheetFoto(
      context,
      fotos: v.fotos,
      latActual: v.coordenadaLat,
      lonActual: v.coordenadaLon,
      seccion: 'Vías y puentes',
      onCoordenadasCapturadas: (lat, lon) {
        v.coordenadaLat = lat;
        v.coordenadaLon = lon;
      },
    );
    if (!ok || !mounted) return;
    setState(() {});
  }

  Future<void> _fotoInfra(EdanDanoInfraPublica i) async {
    final ok = await EdanBotonSacarFoto.mostrarSheetFoto(
      context,
      fotos: i.fotos,
      latActual: i.coordenadaLat,
      lonActual: i.coordenadaLon,
      seccion: 'Infraestructura pública',
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
        EdanAvisoAfectaciones(
          texto: 'Presiona en agregar para registrar la afectación en una '
              'vía o puente. Puedes agregar más de uno.',
        ),
        const SizedBox(height: 10),
        EdanSubsectionHeader(
          titulo: 'Daños de vias y/o puentes',
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
              onRespaldar: () => _fotoVial(v),
              onCambiarFoto: () => _fotoVial(v),
              respaldo: v,
              seccionRespaldo: 'Vías y puentes',
              onFotoEliminada: () => setState(() {}),
            )),
        const SizedBox(height: 18),
        EdanAvisoAfectaciones(
          texto: 'Presiona en agregar para registrar la afectación en '
              'infraestructura pública. Puedes agregar más de una.',
        ),
        const SizedBox(height: 10),
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
              onRespaldar: () => _fotoInfra(i),
              onCambiarFoto: () => _fotoInfra(i),
              respaldo: i,
              seccionRespaldo: 'Infraestructura pública',
              onFotoEliminada: () => setState(() {}),
            )),
      ],
    );
  }
}

/// Fila de radio excluyente (Vía/Puente, tipo de daño) dentro de un RadioGroup.
class _RadioVial extends StatelessWidget {
  final String valor;
  final String etiqueta;

  const _RadioVial({required this.valor, required this.etiqueta});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => RadioGroup.maybeOf<String>(context)?.onChanged.call(valor),
      child: Row(
        children: [
          Radio<String>(
            value: valor,
            activeColor: AppColors.primary,
          ),
          Expanded(
            child: Text(etiqueta,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}
