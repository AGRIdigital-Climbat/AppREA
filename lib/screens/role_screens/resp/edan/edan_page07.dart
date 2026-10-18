import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import '../../../../services/edan/edan_store.dart';
import 'edan_boton_sacar_foto.dart';
import 'edan_dialog_helper.dart';
import 'edan_item_card.dart';
import 'edan_subsection_header.dart';
import 'edan_aviso.dart';

/// Página 07: Impacto en educación (unidades educativas afectadas).
class EdanPage07 extends StatefulWidget {
  final EdanLocalidad localidad;

  /// Notifica al wizard que los datos cambiaron para que reevalúe el botón
  /// Siguiente de ESTA página. No reconstruye la lista de páginas.
  final VoidCallback? onCambio;
  final EdanStore? store;

  const EdanPage07({super.key, required this.localidad, this.store, this.onCambio});

  @override
  State<EdanPage07> createState() => _EdanPage07State();
}

class _EdanPage07State extends State<EdanPage07> {
  /// Toda mutación de datos pasa por `setState` en esta página, así que
  /// el override notifica al wizard en un solo punto (coalescido por él).
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    widget.onCambio?.call();
  }
  final _nombre = TextEditingController();
  final _comunidad = TextEditingController();
  final _estudiantes = TextEditingController();
  final _profesores = TextEditingController();
  final _administrativos = TextEditingController();
  bool _parcial = false;
  bool _total = false;
  bool _suspension = false;

  @override
  void initState() {
    super.initState();
    _hidratarFotos();
  }

  Future<void> _hidratarFotos() async {
    final cambio = await EdanBotonSacarFoto.hidratarFotosDeItems(
      widget.store,
      widget.localidad.unidadesEducativas,
    );
    if (cambio && mounted) setState(() {});
  }

  @override
  void dispose() {
    _nombre.dispose();
    _comunidad.dispose();
    _estudiantes.dispose();
    _profesores.dispose();
    _administrativos.dispose();
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

  Widget _avisoSumaPersonas() {
    final l = widget.localidad;
    final suma = l.sumaUnidadesEducativas;
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
              'La suma de personas afectadas ($suma) supera el total de población afectada (${l.totalPoblacionAfectada}). '
              'Verifica los datos antes de continuar.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B4A00), height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  void _agregar() {
    final u = EdanDanoUnidadEducativa();
    _editar(u, esNuevo: true);
  }

  Future<void> _editar(EdanDanoUnidadEducativa u,
      {bool esNuevo = false}) async {
    _nombre.text = u.nombreEstablecimiento;
    _comunidad.text = u.comunidad.isNotEmpty
        ? u.comunidad
        : widget.localidad.nombre;
    _estudiantes.text = u.estudiantes > 0 ? '${u.estudiantes}' : '';
    _profesores.text = u.profesores > 0 ? '${u.profesores}' : '';
    _administrativos.text = u.administrativos > 0 ? '${u.administrativos}' : '';
    _parcial = u.danoParcial;
    _total = u.danoTotal;
    _suspension = u.suspensionClases ?? false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          title: const Text('Unidad educativa'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _campoTitulo('Nombre'),
                const SizedBox(height: 6),
                TextField(controller: _nombre),
                const SizedBox(height: 12),
                _campoTitulo('Localidad'),
                const SizedBox(height: 6),
                TextField(controller: _comunidad),
                const SizedBox(height: 12),
                _campoTitulo('N° Estudiantes'),
                const SizedBox(height: 6),
                TextField(controller: _estudiantes, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
                const SizedBox(height: 12),
                _campoTitulo('N° Profesores'),
                const SizedBox(height: 6),
                TextField(controller: _profesores, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
                const SizedBox(height: 12),
                _campoTitulo('N° Administrativos'),
                const SizedBox(height: 6),
                TextField(controller: _administrativos, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
                const SizedBox(height: 4),
                EdanCheckRow(label: 'Daño parcial', value: _parcial,
                    onChanged: (x) => setLocal(() => _parcial = x)),
                EdanCheckRow(label: 'Daño total', value: _total,
                    onChanged: (x) => setLocal(() => _total = x)),
                EdanCheckRow(label: 'Suspensión de clases', value: _suspension,
                    onChanged: (x) => setLocal(() => _suspension = x)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () {
                  if (_nombre.text.isEmpty && _comunidad.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No hay datos para guardar')),
                    );
                    Navigator.pop(ctx, false);
                  } else {
                    Navigator.pop(ctx, true);
                  }
                }, child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (!mounted || saved != true) return;

    setState(() {
      u.nombreEstablecimiento = _nombre.text;
      u.comunidad = _comunidad.text;
      u.estudiantes = int.tryParse(_estudiantes.text) ?? 0;
      u.profesores = int.tryParse(_profesores.text) ?? 0;
      u.administrativos = int.tryParse(_administrativos.text) ?? 0;
      u.danoParcial = _parcial;
      u.danoTotal = _total;
      u.suspensionClases = _suspension;
      if (esNuevo) widget.localidad.unidadesEducativas.add(u);
    });
  }

  Future<void> _foto(EdanDanoUnidadEducativa u) async {
    final uuid = EdanBotonSacarFoto.asegurarUuidRegistro(u);
    final ok = await EdanBotonSacarFoto.mostrarSheetFoto(
      context,
      fotos: u.fotos,
      latActual: u.coordenadaLat,
      lonActual: u.coordenadaLon,
      seccion: 'Educación',
      idLocal: widget.localidad.idLocal,
      idSeccion: uuid,
      idEdanLocalidad: widget.localidad.idServer ?? widget.localidad.idEdan,
      onCoordenadasCapturadas: (lat, lon) {
        u.coordenadaLat = lat;
        u.coordenadaLon = lon;
      },
      onFotoGuardada: (path) => u.fotografia = path,
      store: widget.store,
      uuidRegistro: uuid,
      rutaSeccion: 'unidades-educativas',
    );
    if (!ok || !mounted) return;
    setState(() {});
  }

  Future<void> _eliminar(EdanDanoUnidadEducativa u) async {
    final ok = await eliminarItemSeccion(
      context,
      localidad: widget.localidad,
      idSeccion: u.idSeccion,
      rutaV2: 'unidades-educativas',
      tablaSqlite: 'seccion_unidades_educativas',
      titulo: '¿Eliminar unidad educativa?',
      mensaje: 'Se eliminará el registro "${u.nombreEstablecimiento}".',
      store: widget.store,
    );
    if (!ok || !mounted) return;
    final uuid = u.idSeccion;
    setState(() => widget.localidad.unidadesEducativas.remove(u));
    await EdanBotonSacarFoto.purgarFotosDeItem(widget.store, uuid);
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.localidad;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EdanAvisoAfectaciones(
          texto: 'Presiona en agregar para registrar la afectación en una '
              'unidad educativa. Puedes agregar más de una.',
        ),
        const SizedBox(height: 10),
        _avisoSumaPersonas(),
        EdanSubsectionHeader(
          titulo: 'Unidades educativas afectadas',
          icono: Icons.school_outlined,
          onAgregar: _agregar,
          itemCount: l.unidadesEducativas.length,
        ),
        const SizedBox(height: 10),
        ...l.unidadesEducativas.map((u) => EdanItemCard(
                titulo: u.nombreEstablecimiento.isEmpty
                    ? 'Unidad educativa'
                    : u.nombreEstablecimiento,
                subtitulo: [
                  if (u.comunidad.isNotEmpty) u.comunidad,
                  if (u.estudiantes > 0) '${u.estudiantes} estud.',
                  if (u.danoParcial) 'Parcial',
                  if (u.danoTotal) 'Total',
                ].join(' · '),
                icono: Icons.school_outlined,
                onEditar: () => _editar(u),
                onEliminar: () => _eliminar(u),
                onRespaldar: () => _foto(u),
                onCambiarFoto: () => _foto(u),
                respaldo: u,
                seccionRespaldo: 'Educación',
                onFotoEliminada: () => setState(() {}),
              )),
      ],
    );
  }
}
