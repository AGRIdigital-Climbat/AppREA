import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import '../../../../models/id_seccion_helper.dart';
import 'edan_boton_sacar_foto.dart';
import 'edan_dialog_helper.dart';
import 'edan_item_card.dart';
import 'edan_subsection_header.dart';

/// Página 07: Impacto en educación (unidades educativas afectadas).
class EdanPage07 extends StatefulWidget {
  final EdanLocalidad localidad;

  const EdanPage07({super.key, required this.localidad});

  @override
  State<EdanPage07> createState() => _EdanPage07State();
}

class _EdanPage07State extends State<EdanPage07> {
  final _nombre = TextEditingController();
  final _comunidad = TextEditingController();
  final _estudiantes = TextEditingController();
  final _profesores = TextEditingController();
  final _administrativos = TextEditingController();
  bool _parcial = false;
  bool _total = false;
  bool _suspension = false;

  @override
  void dispose() {
    _nombre.dispose();
    _comunidad.dispose();
    _estudiantes.dispose();
    _profesores.dispose();
    _administrativos.dispose();
    super.dispose();
  }

  void _agregar() {
    final u = EdanDanoUnidadEducativa(idSeccion: generarIdSeccion('ue'));
    setState(() => widget.localidad.unidadesEducativas.add(u));
    _editar(u);
  }

  Future<void> _editar(EdanDanoUnidadEducativa u) async {
    _nombre.text = u.nombreEstablecimiento;
    _comunidad.text = u.comunidad;
    _estudiantes.text = u.estudiantes > 0 ? '${u.estudiantes}' : '';
    _profesores.text = u.profesores > 0 ? '${u.profesores}' : '';
    _administrativos.text = u.administrativos > 0 ? '${u.administrativos}' : '';
    _parcial = u.danoParcial;
    _total = u.danoTotal;
    _suspension = u.suspensionClases ?? false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          title: const Text('Unidad educativa'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: _nombre, decoration: const InputDecoration(labelText: 'Nombre')),
                const SizedBox(height: 8),
                TextField(controller: _comunidad, decoration: const InputDecoration(labelText: 'Comunidad')),
                const SizedBox(height: 8),
                _num(_estudiantes, 'N° Estudiantes'),
                _num(_profesores, 'N° Profesores'),
                _num(_administrativos, 'N° Administrativos'),
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (!mounted) return;

    setState(() {
      u.nombreEstablecimiento = _nombre.text;
      u.comunidad = _comunidad.text;
      u.estudiantes = int.tryParse(_estudiantes.text) ?? 0;
      u.profesores = int.tryParse(_profesores.text) ?? 0;
      u.administrativos = int.tryParse(_administrativos.text) ?? 0;
      u.danoParcial = _parcial;
      u.danoTotal = _total;
      u.suspensionClases = _suspension;
    });
  }

  Future<void> _capturarRespaldo(EdanDanoUnidadEducativa u) async {
    final ok = await EdanBotonSacarFoto.capturarRespaldo(
      context,
      fotos: u.fotos,
      latActual: u.coordenadaLat,
      lonActual: u.coordenadaLon,
      onCoordenadasCapturadas: (lat, lon) {
        u.coordenadaLat = lat;
        u.coordenadaLon = lon;
      },
    );
    if (!ok || !mounted) return;
    setState(() {});
  }

  Future<void> _eliminar(EdanDanoUnidadEducativa u) async {
    final ok = await confirmarEliminacion(
      context,
      titulo: '¿Eliminar unidad educativa?',
      mensaje: 'Se eliminará el registro "${u.nombreEstablecimiento}".',
    );
    if (!ok || !mounted) return;
    setState(() => widget.localidad.unidadesEducativas.remove(u));
  }

  Widget _num(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l = widget.localidad;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EdanSubsectionHeader(
          titulo: 'Unidades educativas afectadas',
          icono: Icons.school_outlined,
          onAgregar: _agregar,
          itemCount: l.unidadesEducativas.length,
        ),
        const SizedBox(height: 10),
        if (l.unidadesEducativas.isEmpty)
          const Text(
            'Toca "Agregar" para registrar una unidad educativa.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          )
        else
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
                onRespaldar: () => _capturarRespaldo(u),
                respaldo: u,
                seccionRespaldo: 'Educación',
                onFotoEliminada: () => setState(() {}),
              )),
      ],
    );
  }
}
