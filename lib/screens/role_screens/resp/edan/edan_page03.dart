import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../models/edan.dart';
import '../../../../providers/reporte_provider.dart';

/// Página 03: Impacto en la población (grupos etarios + primera respuesta).
///
/// Muestra una lista de checkboxes por grupo etario (como la página 01).
/// Al marcar una edad se despliegan inline los campos numéricos del grupo.
class EdanPage03 extends StatefulWidget {
  final EdanLocalidad localidad;

  const EdanPage03({super.key, required this.localidad});

  @override
  State<EdanPage03> createState() => _EdanPage03State();
}

class _GrupoControllers {
  final fallecidos = TextEditingController();
  final heridos = TextEditingController();
  final desaparecidos = TextEditingController();
  final observaciones = TextEditingController();
}

class _EdanPage03State extends State<EdanPage03> {
  final Map<String, _GrupoControllers> _controllers = {};
  final _obsPrimeraRespuesta = TextEditingController();

  @override
  void initState() {
    super.initState();
    _obsPrimeraRespuesta.text =
        widget.localidad.necesidadPrimeraRespuesta?.observaciones ?? '';
    _obsPrimeraRespuesta.addListener(_onObsPrimeraRespuesta);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final rp = context.read<ReporteProvider>();
      await rp.fetchGruposEtariosIfNeeded();
      _asegurarImpacto(
          rp.gruposEtarios.map((g) {
        return {
          'id_grupo_etario': g.idGrupoEtario,
          'nombre': g.nombre,
        };
      }).toList());
      if (mounted) setState(() {});
    });
  }

  void _onObsPrimeraRespuesta() {
    final n = widget.localidad.necesidadPrimeraRespuesta;
    if (n != null) n.observaciones = _obsPrimeraRespuesta.text;
    setState(() {});
  }

  @override
  void dispose() {
    _obsPrimeraRespuesta.dispose();
    for (final c in _controllers.values) {
      c.fallecidos.dispose();
      c.heridos.dispose();
      c.desaparecidos.dispose();
      c.observaciones.dispose();
    }
    super.dispose();
  }

  List<EdanGrupoEtario> get _grupos =>
      widget.localidad.impactoPoblacion.isNotEmpty
          ? widget.localidad.impactoPoblacion[0].gruposEtarios
          : const <EdanGrupoEtario>[];

  void _asegurarImpacto(List<dynamic> catalogo) {
    final l = widget.localidad;
    if (l.impactoPoblacion.isEmpty) {
      l.impactoPoblacion
          .add(EdanImpactoPoblacion(gruposEtarios: EdanImpactoPoblacion.gruposDesdeCatalogo(catalogo)));
    } else if (l.impactoPoblacion[0].gruposEtarios.isEmpty) {
      l.impactoPoblacion[0].gruposEtarios
          .addAll(EdanImpactoPoblacion.gruposDesdeCatalogo(catalogo));
    }
  }

  _GrupoControllers _ctrl(EdanGrupoEtario g) {
    final key = g.rango;
    final c = _controllers.putIfAbsent(key, _GrupoControllers.new);
    // Sincronizar con el modelo al primer acceso
    if (g.fallecidos > 0 && c.fallecidos.text != '${g.fallecidos}') {
      c.fallecidos.text = '${g.fallecidos}';
    }
    if (g.heridos > 0 && c.heridos.text != '${g.heridos}') {
      c.heridos.text = '${g.heridos}';
    }
    if (g.desaparecidos > 0 && c.desaparecidos.text != '${g.desaparecidos}') {
      c.desaparecidos.text = '${g.desaparecidos}';
    }
    if (g.observaciones.isNotEmpty && c.observaciones.text != g.observaciones) {
      c.observaciones.text = g.observaciones;
    }
    return c;
  }

  void _sincronizarTotales() {
    final l = widget.localidad;
    if (l.impactoPoblacion.isEmpty) return;
    final ip = l.impactoPoblacion[0];
    ip.fallecidos =
        ip.gruposEtarios.fold<int>(0, (acc, g) => acc + g.fallecidos);
    ip.heridos = ip.gruposEtarios.fold<int>(0, (acc, g) => acc + g.heridos);
    ip.desaparecidos =
        ip.gruposEtarios.fold<int>(0, (acc, g) => acc + g.desaparecidos);
    ip.grupoEtario = 'Total';
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.localidad;
    final necesidad = l.necesidadPrimeraRespuesta!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Impacto en la población por grupo etario',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Marque los grupos etarios afectados y registre el número de individuos según las categorias.',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 12),
        for (final g in _grupos) _grupoEtarioBlock(g),
        const SizedBox(height: 18),
        const Text(
          'Necesidades de primera respuesta',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 6),
        _checkPrimeraRespuesta(
          label: 'Búsqueda y rescate',
          icono: Icons.search_outlined,
          color: const Color(0xFF2563EB),
          value: necesidad.busqueda,
          onChanged: (v) => setState(() => necesidad.busqueda = v),
        ),
        _checkPrimeraRespuesta(
          label: 'Salvamento',
          icono: Icons.health_and_safety_outlined,
          color: const Color(0xFF059669),
          value: necesidad.salvamento,
          onChanged: (v) => setState(() => necesidad.salvamento = v),
        ),
        _checkPrimeraRespuesta(
          label: 'Evacuación',
          icono: Icons.directions_run_outlined,
          color: const Color(0xFFEA580C),
          value: necesidad.evacuacion,
          onChanged: (v) => setState(() => necesidad.evacuacion = v),
        ),
        _campoTitulo(
          titulo: 'Observaciones',
          child: TextField(
            controller: _obsPrimeraRespuesta,
            maxLines: 2,
            decoration: _inputDecor(hint: 'Ej: Recursos solicitados a la UGR'),
          ),
        ),
      ],
    );
  }

  Widget _checkPrimeraRespuesta({
    required String label,
    required IconData icono,
    required Color color,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: value ? color : const Color(0xFFE2E8F0), width: value ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Checkbox(
                  value: value,
                  onChanged: (v) => onChanged(v ?? false),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  activeColor: color,
                ),
                const SizedBox(width: 12),
                Icon(icono, size: 20, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _grupoEtarioBlock(EdanGrupoEtario g) {
    final marcado = g.marcado;
    final applied = _ctrl(g);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            title: Text(
              g.rango.isEmpty ? 'Grupo etario' : g.rango,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            value: marcado,
            onChanged: (v) {
              setState(() {
                if (v == true) {
                  g.marcado = true;
                } else {
                  g.marcado = false;
                  g.fallecidos = 0;
                  g.heridos = 0;
                  g.desaparecidos = 0;
                  g.observaciones = '';
                  applied.fallecidos.clear();
                  applied.heridos.clear();
                  applied.desaparecidos.clear();
                  applied.observaciones.clear();
                }
                _sincronizarTotales();
              });
            },
          ),
          if (marcado)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _camposGrupo(g, applied),
            ),
        ],
      ),
    );
  }

  Widget _camposGrupo(EdanGrupoEtario g, _GrupoControllers c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _campoNum(c.heridos, 'N° Heridos', Icons.medical_services_outlined,
            const Color(0xFF2563EB), (v) {
          g.heridos = int.tryParse(v.trim()) ?? 0;
          _onEdit();
        }, hint: 'Ej: 18'),
        const SizedBox(height: 10),
        _campoNum(c.fallecidos, 'N° Fallecidos', Icons.person_off_outlined,
            const Color(0xFFC0392B), (v) {
          g.fallecidos = int.tryParse(v.trim()) ?? 0;
          _onEdit();
        }, hint: 'Ej: 6'),
        const SizedBox(height: 10),
        _campoNum(c.desaparecidos, 'N° Desaparecidos',
            Icons.person_search_outlined, const Color(0xFF8B5CF6), (v) {
          g.desaparecidos = int.tryParse(v.trim()) ?? 0;
          _onEdit();
        }, hint: 'Ej: 2'),
        const SizedBox(height: 10),
        _campoTitulo(
          titulo: 'Observaciones',
          child: TextField(
            controller: c.observaciones,
            maxLines: 2,
            decoration: _inputDecor(hint: 'Ej: Menores trasladados'),
            onChanged: (v) {
              g.observaciones = v;
              setState(() {});
            },
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecor({String? hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: Color(0xFFE2E8F0)),
      ),
    );
  }

  void _onEdit() {
    _sincronizarTotales();
    setState(() {});
  }

  Widget _campoNum(TextEditingController c, String label, IconData icono,
      Color tituloColor, ValueChanged<String> onChanged, {String? hint}) {
    return _campoTitulo(
      titulo: label,
      icono: icono,
      tituloColor: tituloColor,
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: _inputDecor(hint: hint),
        onChanged: onChanged,
      ),
    );
  }

  Widget _campoTitulo({
    required String titulo,
    IconData? icono,
    Color tituloColor = const Color(0xFF334155),
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icono != null) ...[
              Icon(icono, size: 16, color: tituloColor),
              const SizedBox(width: 4),
            ],
            Text(
              titulo,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: tituloColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
