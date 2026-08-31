import 'package:flutter/material.dart';
import '../../../../models/edan.dart';
import 'edan_dialog_helper.dart';

/// Página 11: Necesidades humanitarias.
class EdanPage11 extends StatefulWidget {
  final EdanLocalidad localidad;

  const EdanPage11({super.key, required this.localidad});

  @override
  State<EdanPage11> createState() => _EdanPage11State();
}

class _EdanPage11State extends State<EdanPage11> {
  @override
  Widget build(BuildContext context) {
    final n = widget.localidad.necesidadHumanitaria!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _check('Alimentos', n.alimentos, (v) => setState(() => n.alimentos = v)),
        _check('Refugio / vivienda', n.refugioVivienda, (v) => setState(() => n.refugioVivienda = v)),
        _check('Ropa de cama', n.ropaCama, (v) => setState(() => n.ropaCama = v)),
        _check('Artículos de higiene', n.articulosHigiene, (v) => setState(() => n.articulosHigiene = v)),
        _check('Artículos de cocina', n.articulosCocina, (v) => setState(() => n.articulosCocina = v)),
        _check('Prendas de vestir', n.prendasVestir, (v) => setState(() => n.prendasVestir = v)),
        _check('Herramientas', n.herramientas, (v) => setState(() => n.herramientas = v)),
        _check('Almacenamiento de agua', n.almacenamientoAgua, (v) => setState(() => n.almacenamientoAgua = v)),
        _check('Baños', n.banos, (v) => setState(() => n.banos = v)),
      ],
    );
  }

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) {
    return EdanCheckRow(label: label, value: value, onChanged: onChanged);
  }
}
