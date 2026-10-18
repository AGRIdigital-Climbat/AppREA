import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import '../../../../providers/reporte_provider.dart';

/// Página 10: Impacto en protección (grupos vulnerables por sexo).
///
/// Lista de checkboxes por grupo vulnerable (como la página 03). Al marcar un
/// grupo se despliegan inline los campos del grupo. Dos grupos (cuyo nombre
/// contiene "Mujeres") ocultan visiblemente el campo "N° Hombres".
class EdanPage10 extends StatefulWidget {
  final EdanLocalidad localidad;

  /// Notifica al wizard que los datos cambiaron para que reevalúe el botón
  /// Siguiente de ESTA página. No reconstruye la lista de páginas.
  final VoidCallback? onCambio;

  const EdanPage10({super.key, required this.localidad, this.onCambio});

  @override
  State<EdanPage10> createState() => _EdanPage10State();
}

class _GrupoControllers {
  final mujeres = TextEditingController();
  final hombres = TextEditingController();
  final total = TextEditingController();
  final observaciones = TextEditingController();
}

class _EdanPage10State extends State<EdanPage10> {
  /// Toda mutación de datos pasa por `setState` en esta página, así que
  /// el override notifica al wizard en un solo punto (coalescido por él).
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    widget.onCambio?.call();
  }
  final Map<String, _GrupoControllers> _controllers = {};
  final Set<String> _expandidas = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final rp = context.read<ReporteProvider>();
      await rp.fetchGruposVulnerablesIfNeeded();
      // Garantiza id_grupo_vulnerable_catalogo (desde el catálogo de la API)
      // para que se persista en la BD local y se envíe al servidor.
      final catalogo = rp.gruposVulnerables;
      if (catalogo.isNotEmpty) {
        final l = widget.localidad;
        // Emparejar por NOMBRE, nunca por índice: el orden del catálogo puede
        // cambiar entre dispositivos o tras una actualización, y el emparejado
        // por posición asignaba un `id_grupo_vulnerable` equivocado a cada
        // grupo.
        final idPorNombre = <String, int>{
          for (final c in catalogo) _normNombre(c.nombre): c.idGrupoVulnerable,
        };
        for (final g in l.proteccion) {
          if (g.idGrupoVulnerableCatalogo != null) continue;
          final nombre = g.nombreGrupo;
          if (nombre == null || nombre.isEmpty) continue;
          final id = idPorNombre[_normNombre(nombre)];
          if (id != null) g.idGrupoVulnerableCatalogo = id;
        }
      }
      if (mounted) setState(() {});
    });
  }

  /// Normaliza un nombre de grupo para comparar sin depender de mayúsculas ni
  /// espacios dobles.
  static String _normNombre(String s) =>
      s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.mujeres.dispose();
      c.hombres.dispose();
      c.total.dispose();
      c.observaciones.dispose();
    }
    super.dispose();
  }

  String _key(EdanGrupoVulnerable g) =>
      g.idSeccion ?? g.nombreGrupo ?? 'grupo';

  bool _esSoloMujeres(EdanGrupoVulnerable g) =>
      (g.nombreGrupo?.toLowerCase().contains('mujeres') ?? false);

  bool _marcado(EdanGrupoVulnerable g) =>
      g.tieneDatos || _expandidas.contains(_key(g));

  _GrupoControllers _ctrl(EdanGrupoVulnerable g) {
    final c = _controllers.putIfAbsent(_key(g), _GrupoControllers.new);
    if (g.mujeres > 0 && c.mujeres.text != '${g.mujeres}') {
      c.mujeres.text = '${g.mujeres}';
    }
    if (g.hombres > 0 && c.hombres.text != '${g.hombres}') {
      c.hombres.text = '${g.hombres}';
    }
    if (g.total > 0 && c.total.text != '${g.total}') {
      c.total.text = '${g.total}';
    }
    if (g.observaciones.isNotEmpty &&
        c.observaciones.text != g.observaciones) {
      c.observaciones.text = g.observaciones;
    }
    return c;
  }

  void _sincronizarTotal(_GrupoControllers c, EdanGrupoVulnerable g) {
    c.total.text = g.total > 0 ? '${g.total}' : '';
  }

  void _limpiarGrupo(EdanGrupoVulnerable g, _GrupoControllers c) {
    g.mujeres = 0;
    g.hombres = 0;
    g.apoyoPsicologico = null;
    g.reposicionDocumentos = null;
    g.observaciones = '';
    c.mujeres.clear();
    c.hombres.clear();
    c.total.clear();
    c.observaciones.clear();
    _expandidas.remove(_key(g));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Población vulnerable por grupo y sexo',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Marque los grupos vulnerables afectados y registre el número de personas según las categorías.',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 12),
        for (final g in widget.localidad.proteccion) _grupoVulnerableBlock(g),
        _avisoSumaPersonas(),
      ],
    );
  }

  Widget _avisoSumaPersonas() {
    final l = widget.localidad;
    final suma = l.sumaProteccion;
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
              'La suma de personas vulnerables ($suma) supera el total de población afectada (${l.totalPoblacionAfectada}). '
              'Verifica los datos antes de continuar.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B4A00), height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grupoVulnerableBlock(EdanGrupoVulnerable g) {
    final marcado = _marcado(g);
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
              g.nombreGrupo ?? 'Grupo vulnerable',
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
                  _expandidas.add(_key(g));
                } else {
                  _limpiarGrupo(g, applied);
                }
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

  Widget _camposGrupo(EdanGrupoVulnerable g, _GrupoControllers c) {
    final soloMujeres = _esSoloMujeres(g);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _campoNum(c.mujeres, 'N° Mujeres', 'Ej: 15', (v) {
                g.mujeres = int.tryParse(v.trim()) ?? 0;
                _sincronizarTotal(c, g);
                setState(() {});
              }),
            ),
            const SizedBox(width: 10),
            if (!soloMujeres)
              Expanded(
                child: _campoNum(c.hombres, 'N° Hombres', 'Ej: 10', (v) {
                  g.hombres = int.tryParse(v.trim()) ?? 0;
                  _sincronizarTotal(c, g);
                  setState(() {});
                }),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _campoNum(c.total, 'Total', 'Ej: 25', (_) {}, readOnly: true),
        const SizedBox(height: 10),
        _preguntaSiNo(
          titulo: '¿Requiere apoyo psicosocial?',
          valor: g.apoyoPsicologico,
          onChanged: (v) => setState(() => g.apoyoPsicologico = v),
        ),
        const SizedBox(height: 10),
        _preguntaSiNo(
          titulo: '¿Requiere reposición de documento de identidad?',
          valor: g.reposicionDocumentos,
          onChanged: (v) => setState(() => g.reposicionDocumentos = v),
        ),
        const SizedBox(height: 10),
        _campoTitulo(
          titulo: 'Observaciones',
          child: TextField(
            controller: c.observaciones,
            maxLines: 2,
            decoration: _inputDecor(hint: 'Ej: Necesita acompañamiento'),
            onChanged: (v) {
              g.observaciones = v;
              setState(() {});
            },
          ),
        ),
      ],
    );
  }

  Widget _preguntaSiNo({
    required String titulo,
    required bool? valor,
    required ValueChanged<bool?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _campoTitulo(titulo: titulo),
        const SizedBox(height: 6),
        RadioGroup<String>(
          groupValue: valor == null ? null : (valor ? 'si' : 'no'),
          onChanged: (x) => onChanged(x == 'si'),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RadioVulnerable(valor: 'si', etiqueta: 'Sí'),
              _RadioVulnerable(valor: 'no', etiqueta: 'No'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _campoNum(
    TextEditingController controller,
    String label,
    String hint,
    ValueChanged<String> onChanged, {
    bool readOnly = false,
  }) {
    return _campoTitulo(
      titulo: label,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        readOnly: readOnly,
        decoration: _inputDecor(hint: hint),
        onChanged: onChanged,
      ),
    );
  }

  Widget _campoTitulo({required String titulo, Widget? child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        if (child != null) ...[
          const SizedBox(height: 6),
          child,
        ],
      ],
    );
  }

  InputDecoration _inputDecor({String? hint}) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      hintText: hint,
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
}

/// Fila de radio excluyente dentro de un RadioGroup (página 10 — protección).
class _RadioVulnerable extends StatelessWidget {
  final String valor;
  final String etiqueta;

  const _RadioVulnerable({required this.valor, required this.etiqueta});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => RadioGroup.maybeOf<String>(context)?.onChanged.call(valor),
      child: Row(
        children: [
          Radio<String>(value: valor, activeColor: AppColors.primary),
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