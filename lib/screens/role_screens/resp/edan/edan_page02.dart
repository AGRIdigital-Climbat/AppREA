import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import '../../../../providers/reporte_provider.dart';
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

  /// "Familias afectadas" se autocalcula dividiendo la poblacion introducida
  /// entre `personasPorHogarCenso` (page01). Solo se rinde ante el usuario
  /// cuando este escribe un valor DISTINTO del calculado; borrar/escribir el
  /// mismo numero no desactiva el control.
  bool _familiasAfectadasManual = false;
  /// Ultimo valor puesto por el autocalculo (referencia para detectar una
  /// edicion realmente manual).
  String? _ultimoAutoFamilias;
  /// Texto que indica CON QUE promedio se esta haciendo el calculo
  /// (comunidad/manzano, municipio o nacional). Solo visible en modo auto.
  String? _textoFuentePph;

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

    // Al abrir la pagina (o un borrador con poblacion pero familias vacias):
    // asegurar el promedio del municipio si el sector no trajo el suyo y
    // correr la insercion automatica (el listener de poblacion solo dispara
    // cuando el usuario teclea).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_asegurarYAutocalcular());
    });
  }

  Future<void> _asegurarYAutocalcular() async {
    final l = widget.localidad;
    // Si el sector no trajo promedio, getCensoMunicipio lo toma de RAM ->
    // SharedPreferences -> red (offline desde arranque si ya se guardo).
    if (!_familiasAfectadasManual &&
        (l.personasPorHogarCenso ?? 0) <= 0 &&
        (l.pphMunicipioCenso ?? 0) <= 0 &&
        l.idMunicipio != null) {
      final m = await context
          .read<ReporteProvider>()
          .getCensoMunicipio(l.idMunicipio!);
      if (m != null && mounted) {
        l.pphMunicipioCenso = (m['personas_por_hogar'] as num?)?.toInt();
        l.pphMunicipioNombre = m['nombre']?.toString();
      }
    }
    if (!mounted) return;
    if (!_familiasAfectadasManual &&
        _familiasAfectadas.text.isEmpty &&
        l.totalPoblacionAfectada > 0) {
      _autosugerirFamiliasAfectadas(l.totalPoblacionAfectada);
    }
    setState(() {}); // pinta el texto de la fuente aunque no hubiera calculo
  }

  void _onPoblacion() {
    final valor = int.tryParse(_poblacion.text) ?? 0;
    widget.localidad.totalPoblacionAfectada = valor;
    _autosugerirFamiliasAfectadas(valor);
    setState(() {});
    widget.onCambio?.call();
  }

  /// Familias afectadas = poblacion / personas_por_hogar (techo).
  /// Prioridad del divisor:
  ///  1) el promedio del SECTOR elegido en page01 (comunidad o manzano);
  ///  2) si el sector no lo trae, el del MUNICIPIO (RAM, via provider);
  ///  3) si tampoco hay, el promedio nacional (5), criterio de la ayuda.
  /// Se rinde solo ante una edicion manual con valor DISTINTO al calculado.
  void _autosugerirFamiliasAfectadas(int poblacion) {
    if (_familiasAfectadasManual) return;
    final l = widget.localidad;
    final sector = l.personasPorHogarCenso ?? 0;
    final municipio = l.pphMunicipioCenso ?? 0;
    final tipo = l.ambitoLugar == 'urbano' ? 'manzano' : 'comunidad';
    final nombreLugar = l.nombre.trim();
    // Como se nombra al lugar en el texto: «KUCHU TAMBO» o "el manzano" /
    // "la comunidad" cuando aun no hay nombre.
    final lugarTexto = nombreLugar.isNotEmpty
        ? '«$nombreLugar»'
        : (tipo == 'manzano' ? 'el manzano' : 'la comunidad');
    final int pph;
    if (sector > 0) {
      pph = sector;
      _textoFuentePph =
          'Automático: población ÷ $pph (promedio del Censo 2024 de $lugarTexto).';
    } else if (municipio > 0) {
      pph = municipio;
      final muni = (l.pphMunicipioNombre ?? '').trim();
      _textoFuentePph = 'Automático: población ÷ $pph. Este lugar no tiene '
          'promedio propio; se usa el del municipio'
          '${muni.isNotEmpty ? ' $muni' : ''} (Censo 2024).';
    } else {
      pph = 5;
      _textoFuentePph = 'Automático: población ÷ $pph (promedio nacional; '
          'este lugar aún no tiene dato del Censo 2024).';
    }
    final texto = poblacion <= 0 ? '' : '${(poblacion / pph).ceil()}';
    _ultimoAutoFamilias = texto;
    if (_familiasAfectadas.text != texto) {
      _familiasAfectadas.text = texto; // su listener sincroniza el modelo
    }
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
    final l = widget.localidad;
    // Nivel 1 de control con el censo 2024 (page01): la poblacion afectada
    // no deberia superar lo registrado. Solo se avisa (rojo) cuando se
    // supera; con censo desconocido (0) no hay control.
    final censo = l.poblacionCenso;
    final valorPoblacion = int.tryParse(_poblacion.text) ?? 0;
    final superaCenso = censo > 0 && valorPoblacion > censo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomTextField(
          label: 'N° Población total afectada *',
          hint: 'Ej: 75',
          controller: _poblacion,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          errorText: superaCenso
              ? 'La cantidad es mayor a la registrada en el censo 2024 ($censo)'
              : null,
        ),
        const SizedBox(height: 14),
        CustomTextField(
          label: 'N° Total de familias afectadas *',
          hint: 'Ej: 15',
          controller: _familiasAfectadas,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          // Solo una edicion con valor distinto del calculado desactiva el
          // autocalculo (tocar/borrar/reingresar el mismo numero no lo rompe).
          onChanged: (_) => setState(() => _familiasAfectadasManual =
              _familiasAfectadas.text != (_ultimoAutoFamilias ?? '')),
        ),
        // Mientras el campo es auto, decir CON QUE promedio se calcula.
        if (!_familiasAfectadasManual && _textoFuentePph != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: Text(
              _textoFuentePph!,
              style: const TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        const SizedBox(height: 14),
        CustomTextField(
          label: 'N° Total de familias damnificadas *',
          hint: 'Ej: 10',
          controller: _familiasDamnificadas,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: 6),
        _buildAyudaDefiniciones(),
      ],
    );
  }

  /// Cuadro de ayuda MUY sutil (colapsado por defecto, tipografia pequena):
  /// definiciones operativas de los tres campos. Titulo azul tipo enlace.
  Widget _buildAyudaDefiniciones() {
    final Color azul = Colors.blue.shade700;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        iconColor: azul,
        collapsedIconColor: azul,
        leading: Icon(Icons.info_outline, size: 16, color: azul),
        title: Text(
          'Haz click para conocer las definiciones',
          style: TextStyle(fontSize: 12, color: azul),
        ),
        children: const [
          _DefinicionFila(
            concepto: 'Población afectada',
            texto: 'personas con daños o pérdidas indirectas (salud, bienes, '
                'medios de vida). Criterio: total de habitantes perjudicados, '
                'sin distinción de edad.',
          ),
          _DefinicionFila(
            concepto: 'Familias afectadas',
            texto: 'células familiares con perjuicios indirectos. Criterio: '
                'familias registradas o estimadas (población ÷ 5, promedio '
                'nacional; sujeto al promedio de la comunidad, manzano o '
                'municipio).',
          ),
          _DefinicionFila(
            concepto: 'Familias damnificadas',
            texto: 'familias con daños directos que dejaron sus viviendas o '
                'medios de vida inhabitables. Criterio: base para definir '
                'albergues y raciones de primera necesidad.',
          ),
        ],
      ),
    );
  }
}

/// Fila de definicion del cuadro de ayuda: concepto en negrita + texto
/// secundario pequeno.
class _DefinicionFila extends StatelessWidget {
  final String concepto;
  final String texto;

  const _DefinicionFila({required this.concepto, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(
            fontSize: 11,
            height: 1.35,
            color: AppColors.textSecondary,
          ),
          children: [
            TextSpan(
              text: '$concepto: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: texto),
          ],
        ),
      ),
    );
  }
}
