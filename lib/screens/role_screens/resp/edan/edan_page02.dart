import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../models/edan.dart';
import '../../../../widgets/custom_text_field.dart';

/// Página 02: Totales de población afectada y damnificada.
class EdanPage02 extends StatefulWidget {
  final EdanLocalidad localidad;

  /// Avisa al wizard que el modelo cambió (gate del botón Siguiente) sin
  /// reconstruir la lista de páginas.
  final VoidCallback? onCambio;

  const EdanPage02({
    super.key,
    required this.localidad,
    this.onCambio,
  });

  @override
  State<EdanPage02> createState() => _EdanPage02State();
}

class _EdanPage02State extends State<EdanPage02> {
  late final TextEditingController _poblacion;
  late final TextEditingController _familiasAfectadas;
  late final TextEditingController _familiasDamnificadas;

  @override
  void initState() {
    super.initState();
    final l = widget.localidad;
    _poblacion = TextEditingController(
      text: l.totalPoblacionAfectada > 0 ? '${l.totalPoblacionAfectada}' : '',
    );
    _familiasAfectadas = TextEditingController(
      text: l.totalFamiliasAfectadas > 0 ? '${l.totalFamiliasAfectadas}' : '',
    );
    _familiasDamnificadas = TextEditingController(
      text: l.totalFamiliasDamnificadas > 0
          ? '${l.totalFamiliasDamnificadas}'
          : '',
    );
    _poblacion.addListener(_onPoblacion);
    _familiasAfectadas.addListener(_onFamiliasAfectadas);
    _familiasDamnificadas.addListener(_onFamiliasDamnificadas);
  }

  void _onPoblacion() {
    widget.localidad.totalPoblacionAfectada =
        int.tryParse(_poblacion.text) ?? 0;
    widget.onCambio?.call();
  }

  void _onFamiliasAfectadas() {
    widget.localidad.totalFamiliasAfectadas =
        int.tryParse(_familiasAfectadas.text) ?? 0;
    widget.onCambio?.call();
  }

  void _onFamiliasDamnificadas() {
    widget.localidad.totalFamiliasDamnificadas =
        int.tryParse(_familiasDamnificadas.text) ?? 0;
    widget.onCambio?.call();
  }

  @override
  void dispose() {
    _poblacion.dispose();
    _familiasAfectadas.dispose();
    _familiasDamnificadas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomTextField(
          label: 'N° Total de familias damnificadas *',
          hint: 'Ej: 10',
          controller: _familiasDamnificadas,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: 14),
        CustomTextField(
          label: 'N° Total de familias afectadas *',
          hint: 'Ej: 15',
          controller: _familiasAfectadas,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: 14),
        CustomTextField(
          label: 'N° Población total afectada *',
          hint: 'Ej: 75',
          controller: _poblacion,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
      ],
    );
  }
}
