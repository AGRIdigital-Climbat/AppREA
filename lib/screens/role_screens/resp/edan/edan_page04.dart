import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import '../../../../services/edan/edan_store.dart';
import 'edan_boton_sacar_foto.dart';
import 'edan_dialog_helper.dart';
import 'edan_item_card.dart';
import 'edan_aviso.dart';
import 'edan_subsection_header.dart';
import '../../../../services/app_logger_ui.dart';

/// Página 04: Impacto en la salud (establecimientos + necesidad de salud).
class EdanPage04 extends StatefulWidget {
  final EdanLocalidad localidad;

  /// Notifica al wizard que los datos cambiaron para que reevalúe el botón
  /// Siguiente de ESTA página. No reconstruye la lista de páginas.
  final VoidCallback? onCambio;
  final EdanStore? store;

  const EdanPage04({super.key, required this.localidad, this.store, this.onCambio});

  @override
  State<EdanPage04> createState() => _EdanPage04State();
}

class _EdanPage04State extends State<EdanPage04> {
  /// Toda mutación de datos pasa por `setState` en esta página, así que
  /// el override notifica al wizard en un solo punto (coalescido por él).
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    widget.onCambio?.call();
  }
  late final TextEditingController _personas;
  late final TextEditingController _otras;
  late final TextEditingController _obsSalud;

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
    _hidratarFotos();
    // `fromJson` deja el objeto en `null` si `necesidad_salud` no era un Map
    // (p.j. un borrador importado con la clave ausente). Antes los `!` de
    // abajo rompían la pantalla al instante; ahora se siembra perezosamente.
    final ns = widget.localidad.necesidadSalud ??= EdanNecesidadSalud();
    _personas = TextEditingController(
        text: ns.numeroPersonas > 0 ? '${ns.numeroPersonas}' : '');
    _otras = TextEditingController(text: ns.otrasNecesidades);
    _obsSalud = TextEditingController(text: ns.observaciones);
    _personas.addListener(() {
      final n = int.tryParse(_personas.text) ?? 0;
      ns.numeroPersonas = n;
      ns.botiquines = n > 0;
    });
    _otras.addListener(() => ns.otrasNecesidades = _otras.text);
    _obsSalud.addListener(() => ns.observaciones = _obsSalud.text);
  }

  @override
  void dispose() {
    _personas.dispose();
    _otras.dispose();
    _obsSalud.dispose();
    _nombre.dispose();
    _comunidad.dispose();
    _medicos.dispose();
    _enfermeras.dispose();
    _otros.dispose();
    super.dispose();
  }

  void _agregar() {
    final est = EdanEstablecimientoSalud();
    _editar(est, esNuevo: true);
  }

  Future<void> _editar(EdanEstablecimientoSalud est,
      {bool esNuevo = false}) async {
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

    final saved = await showDialog<bool>(
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
                _campoTitulo('Localidad'),
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
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                if (_nombre.text.isEmpty && _comunidad.text.isEmpty) {
                  showAppSnackBar(context, 
                    const SnackBar(content: Text('No hay datos para guardar')),
                  );
                  Navigator.pop(ctx, false);
                } else {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || saved != true) return;

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
      if (esNuevo) widget.localidad.establecimientosSalud.add(est);
    });
  }

  Future<void> _eliminar(EdanEstablecimientoSalud est) async {
    final ok = await eliminarItemSeccion(
      context,
      localidad: widget.localidad,
      idSeccion: est.idSeccion,
      rutaV2: 'salud-establecimientos',
      tablaSqlite: 'seccion_salud_establecimientos',
      titulo: '¿Eliminar establecimiento?',
      mensaje: 'Se eliminará el registro de salud "${est.nombreEstablecimiento}".',
      store: widget.store,
    );
    if (!ok || !mounted) return;
    final uuid = est.idSeccion;
    setState(() => widget.localidad.establecimientosSalud.remove(est));
    await EdanBotonSacarFoto.purgarFotosDeItem(widget.store, uuid);
  }

  Future<void> _hidratarFotos() async {
    final cambio = await EdanBotonSacarFoto.hidratarFotosDeItems(
      widget.store,
      widget.localidad.establecimientosSalud,
    );
    if (cambio && mounted) setState(() {});
  }

  Future<void> _foto(EdanEstablecimientoSalud est) async {
    final uuid = EdanBotonSacarFoto.asegurarUuidRegistro(est);
    final ok = await EdanBotonSacarFoto.mostrarSheetFoto(
      context,
      fotos: est.fotos,
      latActual: est.coordenadaLat,
      lonActual: est.coordenadaLon,
      seccion: 'Salud',
      idLocal: widget.localidad.idLocal,
      idSeccion: uuid,
      idEdanLocalidad: widget.localidad.idServer ?? widget.localidad.idEdan,
      onCoordenadasCapturadas: (lat, lon) {
        est.coordenadaLat = lat;
        est.coordenadaLon = lon;
      },
      onFotoGuardada: (path) => est.fotografia = path,
      store: widget.store,
      uuidRegistro: uuid,
      rutaSeccion: 'salud-establecimientos',
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

  Widget _avisoSumaPersonas() {
    final l = widget.localidad;
    final suma = l.sumaSaludPersonal + (l.necesidadSalud?.numeroPersonas ?? 0);
    if (suma <= 0 || suma <= l.totalPoblacionAfectada) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFB300)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_outlined, size: 18, color: Color(0xFFB26A00)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'La suma de personas ($suma) supera el total de población afectada (${l.totalPoblacionAfectada}). '
              'Verifica los datos antes de continuar.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B4A00), height: 1.35),
            ),
          ),
        ],
      ),
    );
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EdanAvisoAfectaciones(
          texto: 'Presiona en agregar para registrar la afectación en un '
              'establecimiento de salud. Puedes agregar más de uno.',
        ),
        const SizedBox(height: 10),
        _avisoSumaPersonas(),
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
              onRespaldar: () => _foto(e),
              onCambiarFoto: () => _foto(e),
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
        const Text(
          'Botiquín',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Número de personas que requieren atención inmediata',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'N° Personas',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _personas,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            hintText: '0',
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: AppColors.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: AppColors.divider),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Otras necesidades',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _otras,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'Escribe otras necesidades',
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: AppColors.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: AppColors.divider),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Observaciones',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _obsSalud,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'Escribe observaciones',
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: AppColors.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: AppColors.divider),
            ),
          ),
        ),
      ],
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
