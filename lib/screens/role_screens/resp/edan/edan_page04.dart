import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import '../../../../models/id_seccion_helper.dart';
import 'edan_boton_sacar_foto.dart';
import 'edan_dialog_helper.dart';
import 'edan_item_card.dart';
import 'edan_subsection_header.dart';

/// Página 04: Impacto en la salud (establecimientos + necesidad de salud).
class EdanPage04 extends StatefulWidget {
  final EdanLocalidad localidad;

  const EdanPage04({super.key, required this.localidad});

  @override
  State<EdanPage04> createState() => _EdanPage04State();
}

class _EdanPage04State extends State<EdanPage04> {
  late final TextEditingController _personas;

  final _nombre = TextEditingController();
  final _comunidad = TextEditingController();
  final _medicos = TextEditingController();
  final _enfermeras = TextEditingController();
  final _otros = TextEditingController();
  String? _nivel;
  bool _danoParcial = false;
  bool _danoTotal = false;
  bool _personal = false;

  @override
  void initState() {
    super.initState();
    _personas = TextEditingController(
        text: widget.localidad.necesidadSalud!.numeroPersonas > 0
            ? '${widget.localidad.necesidadSalud!.numeroPersonas}'
            : '');
    _personas.addListener(() => widget.localidad.necesidadSalud!.numeroPersonas =
        int.tryParse(_personas.text) ?? 0);
  }

  @override
  void dispose() {
    _personas.dispose();
    _nombre.dispose();
    _comunidad.dispose();
    _medicos.dispose();
    _enfermeras.dispose();
    _otros.dispose();
    super.dispose();
  }

  void _agregar() {
    final est = EdanEstablecimientoSalud(idSeccion: generarIdSeccion('es'));
    setState(() => widget.localidad.establecimientosSalud.add(est));
    _editar(est);
  }

  Future<void> _editar(EdanEstablecimientoSalud est) async {
    _nombre.text = est.nombreEstablecimiento;
    _comunidad.text = est.comunidad.isNotEmpty
        ? est.comunidad
        : widget.localidad.nombre;
    _medicos.text = est.medicosAfectados > 0 ? '${est.medicosAfectados}' : '';
    _enfermeras.text =
        est.enfermerasAfectados > 0 ? '${est.enfermerasAfectados}' : '';
    _otros.text = est.otrosAfectados > 0 ? '${est.otrosAfectados}' : '';
    _danoParcial = est.danoParcial;
    _danoTotal = est.danoTotal;
    _nivel = est.nivelAtencion.isNotEmpty ? est.nivelAtencion : null;
    _personal = est.medicosAfectados > 0 ||
        est.enfermerasAfectados > 0 ||
        est.otrosAfectados > 0;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          title: const Text('Establecimiento de salud'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _campoTitulo('Comunidad'),
                TextField(controller: _comunidad),
                const SizedBox(height: 12),
                _campoTitulo('Nombre del establecimiento'),
                TextField(controller: _nombre),
                const SizedBox(height: 12),
                _campoTitulo('Nivel de atención'),
                const SizedBox(height: 6),
                RadioGroup<String>(
                  groupValue: _nivel,
                  onChanged: (v) => setLocal(() => _nivel = v),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _RadioNivel(valor: '1er Nivel', etiqueta: '1er Nivel'),
                      _RadioNivel(valor: '2do Nivel', etiqueta: '2do Nivel'),
                      _RadioNivel(valor: '3er Nivel', etiqueta: '3er Nivel'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _campoTitulo('Nivel de daño en la infraestructura'),
                const SizedBox(height: 6),
                RadioGroup<String>(
                  groupValue: _danoSeleccion(_danoParcial, _danoTotal),
                  onChanged: (v) => setLocal(() {
                    _danoParcial = v == 'parcial';
                    _danoTotal = v == 'total';
                  }),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _RadioNivel(valor: 'parcial', etiqueta: 'Daño parcial'),
                      _RadioNivel(valor: 'total', etiqueta: 'Daño total'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                EdanCheckTarjeta(
                  label: '¿Existe personal de salud afectada?',
                  icono: Icons.medical_services_outlined,
                  value: _personal,
                  onChanged: (v) => setLocal(() => _personal = v),
                ),
                if (_personal) ...[
                  _campoNum(_medicos, 'N° Médicos afectados'),
                  const SizedBox(height: 8),
                  _campoNum(_enfermeras, 'N° Enfermeras afectadas'),
                  const SizedBox(height: 8),
                  _campoNum(_otros, 'N° Otros afectados'),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;

    setState(() {
      est.nombreEstablecimiento = _nombre.text;
      est.comunidad = _comunidad.text;
      est.nivelAtencion = _nivel ?? '';
      est.danoParcial = _danoParcial;
      est.danoTotal = _danoTotal;
      est.medicosAfectados = _personal ? int.tryParse(_medicos.text) ?? 0 : 0;
      est.enfermerasAfectados =
          _personal ? int.tryParse(_enfermeras.text) ?? 0 : 0;
      est.otrosAfectados = _personal ? int.tryParse(_otros.text) ?? 0 : 0;
    });
  }

  Future<void> _eliminar(EdanEstablecimientoSalud est) async {
    final ok = await confirmarEliminacion(
      context,
      titulo: '¿Eliminar establecimiento?',
      mensaje: 'Se eliminará el registro de salud "${est.nombreEstablecimiento}".',
    );
    if (!ok || !mounted) return;
    setState(() => widget.localidad.establecimientosSalud.remove(est));
  }

  Future<void> _capturarRespaldo(EdanEstablecimientoSalud est) async {
    final ok = await EdanBotonSacarFoto.capturarRespaldo(
      context,
      fotos: est.fotos,
      latActual: est.coordenadaLat,
      lonActual: est.coordenadaLon,
      onCoordenadasCapturadas: (lat, lon) {
        est.coordenadaLat = lat;
        est.coordenadaLon = lon;
      },
    );
    if (!ok || !mounted) return;
    setState(() {});
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

  String? _danoSeleccion(bool parcial, bool total) {
    if (parcial) return 'parcial';
    if (total) return 'total';
    return null;
  }

  Widget _campoNum(TextEditingController c, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _campoTitulo(label),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.localidad;
    final necesidad = l.necesidadSalud!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _avisoAfectaciones(),
        const SizedBox(height: 10),
        EdanSubsectionHeader(
          titulo: 'Establecimientos de salud',
          icono: Icons.local_hospital_outlined,
          onAgregar: _agregar,
          itemCount: l.establecimientosSalud.length,
        ),
        const SizedBox(height: 10),
        ...l.establecimientosSalud.map((e) => EdanItemCard(
              titulo: e.nombreEstablecimiento.isEmpty
                  ? 'Sin nombre'
                  : e.nombreEstablecimiento,
              subtitulo: [
                if (e.comunidad.isNotEmpty) e.comunidad,
                if (e.nivelAtencion.isNotEmpty) e.nivelAtencion,
                if (e.danoParcial) 'Daño parcial',
                if (e.danoTotal) 'Daño total',
              ].join(' · '),
              icono: Icons.local_hospital_outlined,
              onEditar: () => _editar(e),
              onEliminar: () => _eliminar(e),
              onRespaldar: () => _capturarRespaldo(e),
              respaldo: e,
              seccionRespaldo: 'Salud',
              onFotoEliminada: () => setState(() {}),
            )),
        const SizedBox(height: 18),
        const Text(
          'Necesidad de salud',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        EdanCheckRow(
          label: 'Requiere botiquines',
          value: necesidad.botiquines,
          onChanged: (v) =>
              setState(() => widget.localidad.necesidadSalud!.botiquines = v),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _personas,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'N° Personas'),
        ),
      ],
    );
  }

  Widget _avisoAfectaciones() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFB300)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: Color(0xFFB26A00)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Presiona en agregar para registrar la afectación en un '
              'establecimiento de salud. Puedes agregar más de uno.',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF6B4A00),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de radio excluyente para el nivel de atención dentro de un RadioGroup.
class _RadioNivel extends StatelessWidget {
  final String valor;
  final String etiqueta;

  const _RadioNivel({required this.valor, required this.etiqueta});

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
