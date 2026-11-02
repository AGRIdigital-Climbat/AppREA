import 'package:flutter/material.dart';
import '../../../../models/edan.dart';

/// Página 11: Necesidades humanitarias.
///
/// Lista de checkboxes por necesidad (como la página 03/10). Al marcar una
/// necesidad se despliega inline su campo de observaciones (obs_*); al
/// desmarcarla colapsa y se limpia la observación.
class EdanPage11 extends StatefulWidget {
  final EdanLocalidad localidad;

  /// Notifica al wizard que los datos cambiaron para que reevalúe el botón
  /// Siguiente de ESTA página. No reconstruye la lista de páginas.
  final VoidCallback? onCambio;

  const EdanPage11({super.key, required this.localidad, this.onCambio});

  @override
  State<EdanPage11> createState() => _EdanPage11State();
}

class _EdanPage11State extends State<EdanPage11> {
  /// Toda mutación de datos pasa por `setState` en esta página, así que
  /// el override notifica al wizard en un solo punto (coalescido por él).
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    widget.onCambio?.call();
  }
  final Map<String, TextEditingController> _obs = {};

  @override
  void dispose() {
    for (final c in _obs.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _obsCtrl(String key, String modelo) {
    final c = _obs.putIfAbsent(key, TextEditingController.new);
    if (modelo.isNotEmpty && c.text != modelo) c.text = modelo;
    return c;
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.localidad.necesidadHumanitaria!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ayuda humanitaria requerida',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Marque las necesidades de ayuda humanitaria que requiere la población afectada.',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 12),
        _bloque(
          key: 'alimentos',
          label: 'Alimentos',
          icono: Icons.restaurant_outlined,
          color: const Color(0xFF059669),
          hint: 'Ej: víveres, agua potable',
          valor: n.alimentos,
          onValor: (v) {
            if (!v) {
              _obsCtrl('alimentos', n.obsAlimentos).clear();
              n.obsAlimentos = '';
            }
            setState(() => n.alimentos = v);
          },
          obsCtrl: _obsCtrl('alimentos', n.obsAlimentos),
          onObs: (v) => setState(() => n.obsAlimentos = v),
        ),
        _bloque(
          key: 'refugio_vivienda',
          label: 'Refugio / vivienda',
          icono: Icons.house_outlined,
          color: const Color(0xFF2563EB),
          hint: 'Ej: carpas, techo provisional',
          valor: n.refugioVivienda,
          onValor: (v) {
            if (!v) {
              _obsCtrl('refugio_vivienda', n.obsRefugioVivienda).clear();
              n.obsRefugioVivienda = '';
            }
            setState(() => n.refugioVivienda = v);
          },
          obsCtrl: _obsCtrl('refugio_vivienda', n.obsRefugioVivienda),
          onObs: (v) => setState(() => n.obsRefugioVivienda = v),
        ),
        _bloque(
          key: 'ropa_cama',
          label: 'Ropa de cama',
          icono: Icons.bed_outlined,
          color: const Color(0xFF8B5CF6),
          hint: 'Ej: colchones, frazadas',
          valor: n.ropaCama,
          onValor: (v) {
            if (!v) {
              _obsCtrl('ropa_cama', n.obsRopaCama).clear();
              n.obsRopaCama = '';
            }
            setState(() => n.ropaCama = v);
          },
          obsCtrl: _obsCtrl('ropa_cama', n.obsRopaCama),
          onObs: (v) => setState(() => n.obsRopaCama = v),
        ),
        _bloque(
          key: 'articulos_higiene',
          label: 'Artículos de higiene',
          icono: Icons.soap_outlined,
          color: const Color(0xFF0D9488),
          hint: 'Ej: jabón, papel, pasta dental',
          valor: n.articulosHigiene,
          onValor: (v) {
            if (!v) {
              _obsCtrl('articulos_higiene', n.obsArticulosHigiene).clear();
              n.obsArticulosHigiene = '';
            }
            setState(() => n.articulosHigiene = v);
          },
          obsCtrl: _obsCtrl('articulos_higiene', n.obsArticulosHigiene),
          onObs: (v) => setState(() => n.obsArticulosHigiene = v),
        ),
        _bloque(
          key: 'articulos_cocina',
          label: 'Artículos de cocina',
          icono: Icons.soup_kitchen_outlined,
          color: const Color(0xFFEA580C),
          hint: 'Ej: ollas, vajilla, garrafa',
          valor: n.articulosCocina,
          onValor: (v) {
            if (!v) {
              _obsCtrl('articulos_cocina', n.obsArticulosCocina).clear();
              n.obsArticulosCocina = '';
            }
            setState(() => n.articulosCocina = v);
          },
          obsCtrl: _obsCtrl('articulos_cocina', n.obsArticulosCocina),
          onObs: (v) => setState(() => n.obsArticulosCocina = v),
        ),
        _bloque(
          key: 'prendas_vestir',
          label: 'Prendas de vestir',
          icono: Icons.checkroom_outlined,
          color: const Color(0xFFDB2777),
          hint: 'Ej: ropa por talla y edad',
          valor: n.prendasVestir,
          onValor: (v) {
            if (!v) {
              _obsCtrl('prendas_vestir', n.obsPrendasVestir).clear();
              n.obsPrendasVestir = '';
            }
            setState(() => n.prendasVestir = v);
          },
          obsCtrl: _obsCtrl('prendas_vestir', n.obsPrendasVestir),
          onObs: (v) => setState(() => n.obsPrendasVestir = v),
        ),
        _bloque(
          key: 'herramientas',
          label: 'Herramientas',
          icono: Icons.handyman_outlined,
          color: const Color(0xFFD97706),
          hint: 'Ej: palas, picos, carretillas',
          valor: n.herramientas,
          onValor: (v) {
            if (!v) {
              _obsCtrl('herramientas', n.obsHerramientas).clear();
              n.obsHerramientas = '';
            }
            setState(() => n.herramientas = v);
          },
          obsCtrl: _obsCtrl('herramientas', n.obsHerramientas),
          onObs: (v) => setState(() => n.obsHerramientas = v),
        ),
        _bloque(
          key: 'almacenamiento_agua',
          label: 'Almacenamiento de agua',
          icono: Icons.water_drop_outlined,
          color: const Color(0xFF0284C7),
          hint: 'Ej: tanques, bidones',
          valor: n.almacenamientoAgua,
          onValor: (v) {
            if (!v) {
              _obsCtrl('almacenamiento_agua', n.obsAlmacenamientoAgua).clear();
              n.obsAlmacenamientoAgua = '';
            }
            setState(() => n.almacenamientoAgua = v);
          },
          obsCtrl: _obsCtrl('almacenamiento_agua', n.obsAlmacenamientoAgua),
          onObs: (v) => setState(() => n.obsAlmacenamientoAgua = v),
        ),
        _bloque(
          key: 'banos',
          label: 'Baños',
          icono: Icons.wc_outlined,
          color: const Color(0xFF475569),
          hint: 'Ej: baños portátiles, letrinas',
          valor: n.banos,
          onValor: (v) {
            if (!v) {
              _obsCtrl('banos', n.obsBanos).clear();
              n.obsBanos = '';
            }
            setState(() => n.banos = v);
          },
          obsCtrl: _obsCtrl('banos', n.obsBanos),
          onObs: (v) => setState(() => n.obsBanos = v),
        ),
      ],
    );
  }

  Widget _bloque({
    required String key,
    required String label,
    required IconData icono,
    required Color color,
    required String hint,
    required bool valor,
    required ValueChanged<bool> onValor,
    required TextEditingController obsCtrl,
    required ValueChanged<String> onObs,
  }) {
    // Card (Material) en lugar de Container decorado: el `CheckboxListTile`
    // pinta su fondo y su ripple sobre el Material más cercano; con un
    // BoxDecoration en medio quedaban invisibles (aviso del framework).
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: const Color(0xFFF8FAFC),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: color,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            title: Row(
              children: [
                Icon(icono, size: 20, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
              ],
            ),
            value: valor,
            onChanged: (v) => onValor(v ?? false),
          ),
          if (valor)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _campoTitulo(
                titulo: 'Observaciones',
                child: TextField(
                  controller: obsCtrl,
                  maxLines: 2,
                  decoration: _inputDecor(hint: hint),
                  onChanged: onObs,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _campoTitulo({required String titulo, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 6),
        child,
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