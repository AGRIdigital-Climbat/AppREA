import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import '../../../../providers/reporte_provider.dart';
import '../../../../services/api_service.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/database_helper.dart';
import '../../../../services/edan/edan_store.dart';
import '../../../../services/edan_secciones_registry.dart';
import '../../../../widgets/custom_text_field.dart';

/// Página 01: Datos generales de la localidad.
///
/// Incluye: ubicación geográfica (cascada), tipo de lugar, nombre,
/// fecha/hora del evento, tipo de evento e impactos.
class EdanPage01 extends StatefulWidget {
  final EdanLocalidad localidad;
  final VoidCallback? onImpactosCambio;

  /// Avisa al wizard que el modelo cambió sin reconstruir la lista de
  /// páginas (gate del botón Siguiente): lo llaman los listeners de texto y
  /// los selectores que escriben en `localidad` y que [onImpactosCambio] no
  /// cubre (checkboxes ya van por su propio canal hacia `rebuild`).
  final VoidCallback? onCambio;

  /// Store V2 inyectado (solo RESP). Cuando está presente, los checkboxes de
  /// impacto escriben en la tabla auxiliar v31 `secciones_grupos_local`; sin
  /// store se cae al camino legacy `localidad_secciones_activas`.
  final EdanStore? store;

  const EdanPage01({
    super.key,
    required this.localidad,
    this.onImpactosCambio,
    this.onCambio,
    this.store,
  });

  @override
  State<EdanPage01> createState() => _EdanPage01State();
}

class _EdanPage01State extends State<EdanPage01> {
  static const Map<String, List<String>> _tiposPrioritariosPorDepartamento = {
    'la paz': ['Ayllu', 'Comunidad', 'OTB', 'Barrio', 'Zona', 'Distrito', 'Localidad', 'Central agraria'],
    'oruro': ['Ayllu', 'Comunidad', 'OTB', 'Barrio', 'Zona', 'Distrito', 'Localidad', 'Central agraria'],
    'potosí': ['Ayllu', 'Comunidad', 'OTB', 'Barrio', 'Zona', 'Distrito', 'Localidad', 'Central agraria'],
    'cochabamba': ['Comunidad', 'OTB', 'Barrio', 'Zona', 'Distrito', 'Localidad', 'Central agraria'],
    'chuquisaca': ['Comunidad', 'OTB', 'Barrio', 'Zona', 'Distrito', 'Localidad', 'Central agraria'],
    'tarija': ['Comunidad', 'Capitanía', 'Territorio indígena', 'TIOC/TCO', 'OTB', 'Barrio', 'Zona', 'Distrito', 'Localidad', 'Central agraria'],
    'santa cruz': ['Capitanía', 'Territorio indígena', 'TIOC/TCO', 'Comunidad', 'Barrio', 'Zona', 'Distrito', 'Localidad', 'Central agraria'],
    'beni': ['Capitanía', 'Territorio indígena', 'TIOC/TCO', 'Comunidad', 'Barrio', 'Zona', 'Distrito', 'Localidad', 'Central agraria'],
    'pando': ['Capitanía', 'Territorio indígena', 'TIOC/TCO', 'Comunidad', 'Barrio', 'Zona', 'Distrito', 'Localidad', 'Central agraria'],
  };
  late final TextEditingController _nombreController;
  late final TextEditingController _fechaController;

  String? _hora12;
  String _ampm = '';
  int? _idTipoEvento;
  bool _mostrarTodosTiposLocalidad = false;

  String _ambitoLugar = 'rural'; // 'urbano' | 'rural' (default rural)
  // Recurrencia local del "Evento extremo" (100% de la app, por usuario, en
  // SharedPreferences): los tipos mas usados suben a un grupo propio del
  // dropdown. Nunca viaja al servidor ni toca el catalogo.
  Map<int, int> _freqEventos = {};
  List<Map<String, dynamic>> _listaLugares = [];
  bool _cargandoLista = false;
  bool _mostrarLista = false;
  String? _nombreSeleccionado;
  /// Secuencia de carga: al cambiar de ambito se invalida cualquier corrida
  /// en curso para que NO pinte la lista del ambito anterior en el nuevo
  /// (era la causa de que rural/urbano "se mezclaran" en el panel).
  int _cargaListaSeq = 0;

  /// Reabriendo un borrador, `ambitoLugar` (transitorio) arranca en 'rural'.
  /// Si el nombre guardado coincide SOLO con el catalogo local de manzanos,
  /// se corrige a 'urbano' ANTES de cargar la lista, para que chip y listado
  /// queden coherentes. Sin catalogo local en cache, no se toca nada.
  Future<void> _inferirAmbitoDesdeNombreGuardado() async {
    final l = widget.localidad;
    final nombre = l.nombre.trim().toLowerCase();
    final idMun = l.idMunicipio;
    if (nombre.isEmpty || idMun == null) return;
    try {
      final rp = context.read<ReporteProvider>();
      final manz =
          await rp.getLugaresLocales(urbano: true, idMunicipio: idMun);
      if (!mounted) return;
      final esManzana = manz.any((e) =>
          (e['nombre']?.toString().trim().toLowerCase() ?? '') == nombre);
      if (!esManzana) return;
      final com =
          await rp.getLugaresLocales(urbano: false, idMunicipio: idMun);
      if (!mounted) return;
      final esComunidad = com.any((e) =>
          (e['nombre']?.toString().trim().toLowerCase() ?? '') == nombre);
      if (esComunidad) return; // ambiguo: se queda con el default (rural)
      setState(() {
        _ambitoLugar = 'urbano';
        l.ambitoLugar = 'urbano';
      });
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    final l = widget.localidad;
    final token = AuthService.instance.currentToken;

    if (l.idDepartamento == null && token != null) {
      l.idDepartamento = token.idDepartamento;
      l.departamentoNombre = token.departamentoNombre;
      l.idProvincia = token.idProvincia;
      l.provinciaNombre = token.provinciaNombre;
      l.idMunicipio = token.idMunicipio;
      l.municipioNombre = token.municipioNombre;
    }

    _idTipoEvento = l.idTipoEvento;
    _ambitoLugar = l.ambitoLugar == 'urbano' ? 'urbano' : 'rural';
    if (l.nombre.isNotEmpty &&
        (l.viviendasCenso > 0 || l.poblacionCenso > 0 || l.hogaresCenso > 0)) {
      _nombreSeleccionado = l.nombre;
    }

    _nombreController = TextEditingController(text: l.nombre);
    _fechaController = TextEditingController(text: _fmtDate(l.fechaEvento));

    if (l.horaEvento != null && l.horaEvento!.isNotEmpty) {
      _hora12 = _extractHour12(l.horaEvento!);
      _ampm = _extractAmPm(l.horaEvento!);
    }

    _nombreController.addListener(() {
      l.nombre = _nombreController.text;
      widget.onCambio?.call();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final rp = context.read<ReporteProvider>();
      unawaited(_cargarFrecuenciaEventos());
      // Catálogos generales (mismos para ambos roles, una vez por dispositivo):
      // si falta cualquiera de los que usa esta página, se baja el set completo.
      if (rp.tiposEvento.isEmpty || rp.tiposLocalidad.isEmpty) {
        rp.fetchAndCacheCatalogs();
      }
      // Antes de cargar la lista: si el nombre guardado es un manzano del
      // catalogo local, corregir el ambito (al reabrir un borrador el campo
      // transitorio arranca en 'rural' y podria quedar mal marcado).
      await _inferirAmbitoDesdeNombreGuardado();
      if (!mounted) return;
      // Apenas entramos: cargar la lista de lugares (manzanos/comunidades)
      // del municipio para que el selector ya tenga opciones visibles.
      unawaited(_cargarLista());
      // Borrador reabierto: los campos de censo son transitorios y se
      // perdieron; dejar el promedio del municipio listo para page02.
      if (widget.localidad.nombre.isNotEmpty &&
          (widget.localidad.personasPorHogarCenso ?? 0) <= 0) {
        unawaited(_asegurarPphMunicipio());
      }
    });
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _fechaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.localidad;
    final rp = context.watch<ReporteProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Ubicación:'),
        const SizedBox(height: 8),
        _buildGeografiaInformativa(l),
        const SizedBox(height: 18),
        const Divider(color: AppColors.divider, thickness: 1, height: 1),
        const SizedBox(height: 18),

        _sectionTitle('Afectación:'),
        const SizedBox(height: 8),
        _buildTipoLocalidad(rp),
        const SizedBox(height: 10),
        _buildNombreLugar(rp),
        const SizedBox(height: 10),
        _buildTipoEvento(rp),
        const SizedBox(height: 10),
        CustomTextField(
          label: 'Fecha de ocurrencia *',
          hint: 'dd/mm/aaaa',
          controller: _fechaController,
          readOnly: true,
          onTap: _pickFecha,
        ),
        const SizedBox(height: 10),
        _buildHora(),
        const SizedBox(height: 18),
        const Divider(color: AppColors.divider, thickness: 1, height: 1),
        const SizedBox(height: 18),

        _sectionTitle('Afectaciones y necesidades:'),
        const SizedBox(height: 8),
        _avisoAfectaciones(),
        const SizedBox(height: 10),
        ..._impactos(l),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    final primary = PaletteScope.of(context).primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: primary, width: 4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: primary,
          letterSpacing: 0.3,
        ),
      ),
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
              'Marca las casillas de las categorías afectadas por el evento. '
              'Mas adelante completa los detalles.',
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

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
    );
  }

  Widget _labeledDropdown({
    String label = '',
    bool labelResuelto = false,
    required String hint,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    final Widget dropdown = DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: PaletteScope.of(context).primary, width: 2),
        ),
      ),
      items: items,
      onChanged: onChanged,
    );

    if (labelResuelto || label.isEmpty) return dropdown;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        const SizedBox(height: 8),
        dropdown,
      ],
    );
  }

  // ─── Geografía informativa ───

  Widget _buildGeografiaInformativa(EdanLocalidad l) {
    final filas = <(String, String?)>[
      ('Departamento', l.departamentoNombre),
      ('Provincia', l.provinciaNombre),
      ('Municipio', l.municipioNombre),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          for (int i = 0; i < filas.length; i++) ...[
            if (i > 0) const Divider(color: AppColors.divider, height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      filas[i].$1,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      filas[i].$2?.isNotEmpty == true
                          ? filas[i].$2!
                          : '—',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Tipo de lugar ───

  Widget _buildTipoLocalidad(ReporteProvider rp) {
    final catalogo = rp.tiposLocalidad;
    final allOpciones = catalogo.isNotEmpty
        ? catalogo.map((t) => t.nombre).toList()
        : kTiposLocalidadId.keys.toList();

    // Filtrar por departamento cuando hay mapeo y no se pidió "ver todos".
    final depNombre = (widget.localidad.departamentoNombre ?? '').toLowerCase();
    final prioritarios = _tiposPrioritariosPorDepartamento[depNombre];
    List<String> opciones = allOpciones;
    if (!_mostrarTodosTiposLocalidad && prioritarios != null && prioritarios.isNotEmpty) {
      final set = prioritarios.map((e) => e.toLowerCase()).toSet();
      final filtrados = allOpciones
          .where((o) => set.contains(o.toLowerCase()))
          .toList();
      if (filtrados.isNotEmpty) opciones = filtrados;
    }

    final actual = widget.localidad.tipoLocalidad;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => setState(
              () => _mostrarTodosTiposLocalidad = !_mostrarTodosTiposLocalidad,
            ),
            child: Text(
              _mostrarTodosTiposLocalidad
                  ? 'Mostrar solo los de mi departamento'
                  : 'Mostrar todos los tipos',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
        const SizedBox(height: 4),
        _labeledDropdown(
          label: 'Organización territorial *',
          hint: 'Seleccione',
          value: actual.isNotEmpty ? actual : null,
          items: opciones.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() => widget.localidad.tipoLocalidad = v);
            widget.localidad.idTipoLocalidad = tipoLocalidadIdPorNombre(v);
            widget.onCambio?.call();
          },
        ),
      ],
    );
  }

  // ─── Hora del evento ───

  Widget _buildHora() {
    final horas =
        List<String>.generate(12, (i) => (i + 1).toString().padLeft(2, '0'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Hora de ocurrencia *'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _labeledDropdown(
                labelResuelto: true,
                hint: 'Seleccione',
                value: _hora12,
                items: horas
                    .map((h) => DropdownMenuItem(value: h, child: Text('$h:00')))
                    .toList(),
                onChanged: (v) {
                  setState(() => _hora12 = v);
                  _syncHora();
                },
              ),
            ),
            const SizedBox(width: 10),
            _ampmBtn('AM'),
            const SizedBox(width: 4),
            _ampmBtn('PM'),
          ],
        ),
        if (_ampm.isEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFB300)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: Color(0xFFB26A00)),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Seleccione si es AM o PM',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFB26A00),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _ampmBtn(String label) {
    final selected = _ampm == label;
    return GestureDetector(
      onTap: () {
        setState(() => _ampm = label);
        _syncHora();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color:
              selected ? PaletteScope.of(context).primary : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? PaletteScope.of(context).primary
                : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  void _syncHora() {
    if (_hora12 == null || _ampm.isEmpty) return;
    widget.localidad.horaEvento = _horaIso();
    widget.onCambio?.call();
  }

  String _horaIso() {
    if (_hora12 == null) return '';
    if (_ampm.isEmpty) return '';
    var h = int.parse(_hora12!);
    if (_ampm == 'PM' && h != 12) h += 12;
    if (_ampm == 'AM' && h == 12) h = 0;
    return '${h.toString().padLeft(2, '0')}:00';
  }

  // ─── Nombre de lugar (Urbano/Rural + censo) ───

  /// Tope SOLO de lo que se pinta de golpe (no de busqueda): al escribir se
  /// filtra toda la lista cargada del municipio y luego se muestran hasta
  /// estos items. La busqueda es local, asi que tambien funciona offline.
  static const int _kMaxItemsLista = 50;

  Widget _buildNombreLugar(ReporteProvider rp) {
    final l = widget.localidad;
    final texto = _nombreController.text.trim().toLowerCase();
    final filtrados = texto.isEmpty
        ? _listaLugares
        : _listaLugares
            .where((e) =>
                (e['nombre']?.toString().toLowerCase() ?? '').contains(texto))
            .toList();
    final visibles = filtrados.length > _kMaxItemsLista
        ? filtrados.sublist(0, _kMaxItemsLista)
        : filtrados;
    final mostrar = _mostrarLista &&
        (_cargandoLista ||
            _listaLugares.isNotEmpty ||
            _nombreController.text.trim().isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Ámbito: ',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Urbano'),
              selected: _ambitoLugar == 'urbano',
              onSelected: (_) => _onAmbitoCambiado('urbano'),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Rural'),
              selected: _ambitoLugar == 'rural',
              onSelected: (_) => _onAmbitoCambiado('rural'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        CustomTextField(
          label: 'Nombre de lugar *',
          hint: _ambitoLugar == 'urbano'
              ? 'Buscar manzano o seleccionar de la lista'
              : 'Buscar comunidad o seleccionar de la lista',
          controller: _nombreController,
          textCapitalization: TextCapitalization.words,
          onTap: () => setState(() => _mostrarLista = true),
          suffixIcon: IconButton(
            icon: Icon(
              _mostrarLista ? Icons.expand_less : Icons.expand_more,
              color: AppColors.textSecondary,
            ),
            onPressed: () => setState(() => _mostrarLista = !_mostrarLista),
          ),
          onChanged: (v) {
            setState(() {
              _mostrarLista = true;
              // Si el usuario edita el nombre tras seleccionar uno, los datos
              // del censo ya no corresponden: se limpian.
              if (_nombreSeleccionado != null && v != _nombreSeleccionado) {
                _nombreSeleccionado = null;
                _limpiarCenso();
              }
            });
          },
        ),
        if (mostrar) _buildListaLugares(visibles, filtrados.length),
        // Resumen compacto SOLO cuando hay seleccion del listado con datos
        // del censo (no aparece con textos libres "Otro").
        if (_nombreSeleccionado != null &&
            (l.poblacionCenso > 0 ||
                l.hogaresCenso > 0 ||
                (l.personasPorHogarCenso ?? 0) > 0))
          Padding(
            padding: const EdgeInsets.only(top: 5, left: 2),
            child: Text(
              [
                if (l.poblacionCenso > 0) 'Población: ${l.poblacionCenso}',
                if (l.hogaresCenso > 0) 'Hogares: ${l.hogaresCenso}',
                if ((l.personasPorHogarCenso ?? 0) > 0)
                  'Integrantes/hogar: ${l.personasPorHogarCenso}',
              ].join('  ·  '),
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildListaLugares(
      List<Map<String, dynamic>> visibles, int totalFiltrados) {
    final cargandoVacio = _cargandoLista && _listaLugares.isEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: cargandoVacio
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              itemCount: visibles.length +
                  (totalFiltrados > visibles.length ? 1 : 0) +
                  (totalFiltrados == 0 ? 1 : 0) +
                  1,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                if (i < visibles.length) {
                  final item = visibles[i];
                  return ListTile(
                    dense: true,
                    title: Text(item['nombre']?.toString() ?? ''),
                    onTap: () => _seleccionarLugar(item),
                  );
                }
                if (totalFiltrados > visibles.length && i == visibles.length) {
                  return Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'Mostrando ${visibles.length} de $totalFiltrados. Escribe para filtrar…',
                      style: const TextStyle(
                          fontSize: 11, fontStyle: FontStyle.italic),
                    ),
                  );
                }
                if (totalFiltrados == 0 && i == visibles.length) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(10, 8, 10, 0),
                    child: Text(
                      'Sin coincidencias: usa «Otro» abajo para confirmar.',
                      style:
                          TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                    ),
                  );
                }
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.edit_outlined, size: 18),
                  title: Text(_nombreController.text.trim().isEmpty
                      ? 'Otro (escribe el nombre en el campo)'
                      : 'Otro: usar «${_nombreController.text.trim()}»'),
                  onTap: _confirmarOtro,
                );
              },
            ),
    );
  }

  /// "Otro" SIN dialogo: el texto escrito en el campo ES el nombre final.
  /// Solo se cierra el listado y se descartan los datos de censo (el lugar
  /// no existe en el listado del municipio). Sin rutas que abrir/cerrar, se
  /// elimina la fuente del assert `_dependents.isEmpty` del framework.
  void _confirmarOtro() {
    final texto = _nombreController.text.trim();
    setState(() {
      _mostrarLista = false;
      _nombreSeleccionado = null;
      _limpiarCenso();
      if (texto.isNotEmpty) widget.localidad.nombre = texto;
    });
    // Sin sector censal: el respaldo de page02 sera el promedio del
    // municipio (si hay red); lo dejamos preparado aqui, en memoria.
    unawaited(_asegurarPphMunicipio());
    widget.onCambio?.call();
  }

  void _onAmbitoCambiado(String ambito) {
    if (_ambitoLugar == ambito) return;
    setState(() {
      _ambitoLugar = ambito;
      widget.localidad.ambitoLugar = ambito;
      _nombreSeleccionado = null;
      _limpiarCenso();
      _listaLugares = [];
      _mostrarLista = true;
    });
    unawaited(_cargarLista());
    widget.onCambio?.call();
  }

  /// Carga la lista COMPLETA del municipio (manzanos si urbano, comunidades
  /// si rural). Primero usa el catalogo local (v42, funciona offline); luego
  /// refresca por red y re-cachea. La busqueda en linea filtra sobre esta
  /// lista en memoria, sin hacer mas pedidos.
  ///
  /// El token `seq` invalida resultados de una corrida anterior (p. ej. el
  /// usuario cambio de ambito mientras la red respondia): solo la ultima
  /// corrida pinta la lista, evitando mezclar comunidades y manzanos.
  Future<void> _cargarLista() async {
    final idMun = widget.localidad.idMunicipio;
    if (idMun == null) return;
    final seq = ++_cargaListaSeq;
    final rp = context.read<ReporteProvider>();
    final urbano = _ambitoLugar == 'urbano';
    setState(() => _cargandoLista = true);
    try {
      // 1) Catalogo local (si ya se descargo con el catalogo inicial/perfil).
      final locales =
          await rp.getLugaresLocales(urbano: urbano, idMunicipio: idMun);
      if (!mounted || seq != _cargaListaSeq) return;
      if (locales.isNotEmpty) {
        setState(() => _listaLugares = locales);
      }

      // 2) Refresco por red (silencioso si falla: lo local sigue sirviendo).
      final data = urbano
          ? await ApiService.instance.getManzanosPorMunicipio(idMun)
          : await ApiService.instance.getComunidadesPorMunicipio(idMun);
      if (!mounted || seq != _cargaListaSeq) return;
      data.sort((a, b) => (a['nombre']?.toString() ?? '')
          .compareTo(b['nombre']?.toString() ?? ''));
      setState(() => _listaLugares = data);
      // Re-cachear en el catalogo local para la proxima (offline).
      unawaited(urbano
          ? DatabaseHelper.instance.saveManzanosLocal(data)
          : DatabaseHelper.instance.saveComunidadesLocal(data));
    } catch (_) {
      // Sin red y sin cache: el panel mostrara "Sin coincidencias" + Otro.
    } finally {
      if (mounted && seq == _cargaListaSeq) {
        setState(() => _cargandoLista = false);
        // Borrador reabierto: el censo del lugar es transitorio y se perdio.
        // Restaurarlo buscandolo por nombre en el catalogo local (offline)
        // para que page02 use el promedio PROPIO del lugar, no el respaldo.
        _restaurarCensoDesdeCatalogo();
      }
    }
  }

  /// Busca el nombre guardado del lugar en la lista ya cargada (catalogo
  /// local o red) y, si coincide exactamente, aplica sus datos de censo como
  /// si el usuario lo acabara de seleccionar. Condicion: solo cuando el
  /// modelo aun no tiene censo (recien reabierto) y no hay seleccion previa
  /// en esta sesion. Silencioso si el nombre es un "Otro" que no esta en el
  /// catalogo: page02 seguira con municipio > nacional.
  void _restaurarCensoDesdeCatalogo() {
    final l = widget.localidad;
    final nombre = l.nombre.trim();
    if (nombre.isEmpty || _nombreSeleccionado != null) return;
    final yaTieneCenso = l.viviendasCenso > 0 ||
        l.poblacionCenso > 0 ||
        l.hogaresCenso > 0 ||
        (l.personasPorHogarCenso ?? 0) > 0;
    if (yaTieneCenso) return;
    final n = nombre.toLowerCase();
    for (final item in _listaLugares) {
      if ((item['nombre']?.toString().trim().toLowerCase() ?? '') == n) {
        _seleccionarLugar(item); // aplica censo + ambito + onCambio
        return;
      }
    }
  }

  void _seleccionarLugar(Map<String, dynamic> item) {
    final nombre = item['nombre']?.toString() ?? '';
    setState(() {
      _mostrarLista = false;
      _nombreSeleccionado = nombre;
      _nombreController.text = nombre;
      widget.localidad.nombre = nombre;
      widget.localidad.ambitoLugar = _ambitoLugar;
      widget.localidad.viviendasCenso =
          (item['viviendas'] as num?)?.toInt() ?? 0;
      widget.localidad.poblacionCenso =
          ((item['personas'] ?? item['poblacion']) as num?)?.toInt() ?? 0;
      widget.localidad.hogaresCenso = (item['hogares'] as num?)?.toInt() ?? 0;
      widget.localidad.personasPorHogarCenso =
          (item['personas_por_hogar'] as num?)?.toInt();
      widget.localidad.codigoIneCenso =
          _ambitoLugar == 'rural' ? item['codigo_ine']?.toString() : null;
    });
    // Comunidad: refinar la poblacion con el endpoint especifico.
    if (_ambitoLugar == 'rural' &&
        (widget.localidad.codigoIneCenso ?? '').isNotEmpty) {
      unawaited(_refrescarComunidad(widget.localidad.codigoIneCenso!));
    }
    // Sector sin promedio de personas por hogar (pasa en varios manzanos/
    // comunidades del censo): dejar listo el promedio del municipio para el
    // autocalculo de page02. Solo se consulta cuando hace falta.
    if ((widget.localidad.personasPorHogarCenso ?? 0) <= 0) {
      unawaited(_asegurarPphMunicipio());
    }
    widget.onCambio?.call();
  }

  void _limpiarCenso() {
    widget.localidad.viviendasCenso = 0;
    widget.localidad.poblacionCenso = 0;
    widget.localidad.hogaresCenso = 0;
    widget.localidad.personasPorHogarCenso = null;
    widget.localidad.codigoIneCenso = null;
  }

  /// Busca el promedio de personas por hogar del MUNICIPIO (RAM -> prefs ->
  /// red, via provider; sin SQL). page02 lo usa como respaldo cuando el
  /// sector no trae el suyo. Silencioso: si nunca hubo red para este
  /// municipio, page02 usara el promedio nacional.
  /// Clave de recurrencia por usuario (dos responsables en el mismo equipo
  /// ven sus propios eventos frecuentes).
  String? get _claveFrecuencia {
    final uid = AuthService.instance.userId;
    return uid == null ? null : 'evento_frecuencia_$uid';
  }

  Future<void> _cargarFrecuenciaEventos() async {
    final clave = _claveFrecuencia;
    if (clave == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(clave);
      if (raw == null) return;
      final dec = jsonDecode(raw) as Map<String, dynamic>;
      final mapa = <int, int>{
        for (final e in dec.entries)
          if (int.tryParse(e.key) != null) int.parse(e.key): (e.value as num).toInt(),
      };
      if (mapa.isNotEmpty && mounted) {
        setState(() => _freqEventos = mapa);
      }
    } catch (_) {}
  }

  Future<void> _guardarFrecuenciaEventos() async {
    final clave = _claveFrecuencia;
    if (clave == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        clave,
        jsonEncode(_freqEventos.map((k, v) => MapEntry('$k', v))),
      );
    } catch (_) {}
  }

  Future<void> _asegurarPphMunicipio() async {
    final l = widget.localidad;
    final idMun = l.idMunicipio;
    if (idMun == null) return;
    if ((l.pphMunicipioCenso ?? 0) > 0) return;
    final m = await context.read<ReporteProvider>().getCensoMunicipio(idMun);
    if (!mounted || m == null) return;
    setState(() {
      l.pphMunicipioCenso = (m['personas_por_hogar'] as num?)?.toInt();
      l.pphMunicipioNombre = m['nombre']?.toString();
    });
  }

  Future<void> _refrescarComunidad(String codigoIne) async {
    try {
      final data = await ApiService.instance.getComunidadPoblacion(codigoIne);
      if (!mounted) return;
      setState(() {
        widget.localidad.viviendasCenso = (data['viviendas'] as num?)?.toInt() ?? widget.localidad.viviendasCenso;
        widget.localidad.poblacionCenso = (data['poblacion'] as num?)?.toInt() ?? widget.localidad.poblacionCenso;
        widget.localidad.hogaresCenso = (data['hogares'] as num?)?.toInt() ?? widget.localidad.hogaresCenso;
        widget.localidad.personasPorHogarCenso =
            (data['personas_por_hogar'] as num?)?.toInt() ?? widget.localidad.personasPorHogarCenso;
      });
    } catch (_) {}
  }

  // ─── Tipo de evento ───

  Widget _buildTipoEvento(ReporteProvider rp) {
    final eventos = rp.tiposEvento;
    final nombreActual = _idTipoEvento != null
        ? rp.getTipoEventoNombre(_idTipoEvento!)
        : null;

    const placeholder = 'Seleccione';

    final ordenados = eventos.toList()
      ..sort((a, b) => a.nombre.compareTo(b.nombre));

    // Con historial de uso: dos grupos dentro del mismo dropdown ("MÁS
    // FRECUENTES" = top 5 por cantidad de selecciones, ordenados desc;
    // "OTROS EVENTOS" = el resto del catalogo oficial).
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: placeholder,
        enabled: false,
        child: Text('Seleccione el tipo de evento'),
      ),
    ];
    final valoresUsados = <String>{};

    DropdownMenuItem<String> itemEvento(String nombre) {
      valoresUsados.add(nombre);
      return DropdownMenuItem<String>(
        value: nombre,
        child: Text(nombre),
      );
    }

    DropdownMenuItem<String> cabecera(String titulo) => DropdownMenuItem<String>(
          enabled: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              titulo,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        );

    final frecuentes = ordenados
        .where((e) => (_freqEventos[e.idTipoEvento] ?? 0) > 0)
        .toList()
      ..sort((a, b) {
        final porCount = (_freqEventos[b.idTipoEvento] ?? 0)
            .compareTo(_freqEventos[a.idTipoEvento] ?? 0);
        return porCount != 0 ? porCount : a.nombre.compareTo(b.nombre);
      });
    final top = frecuentes.take(5).toList();

    if (_freqEventos.isNotEmpty && top.isNotEmpty) {
      items.add(cabecera('MÁS FRECUENTES'));
      items.addAll(top.map((e) => itemEvento(e.nombre)));
      items.add(cabecera('OTROS EVENTOS'));
      final topIds = top.map((e) => e.idTipoEvento).toSet();
      items.addAll(ordenados
          .where((e) => !topIds.contains(e.idTipoEvento))
          .map((e) => itemEvento(e.nombre)));
    } else {
      // Sin historial (primera vez) o catalogo sin coincidencias: igual
      // que siempre, una sola lista alfabetica.
      items.addAll(ordenados.map((e) => itemEvento(e.nombre)));
    }

    // Un valor sin item correspondiente (catálogo aún no descargado, o id
    // obsoleto en un borrador reabierto) crasheaba el DropdownButtonFormField
    // — exige exactamente un item con ese value. Se agrega como item propio.
    if (nombreActual != null && !valoresUsados.contains(nombreActual)) {
      items.add(itemEvento(nombreActual));
    }

    return _labeledDropdown(
      label: 'Evento extremo *',
      hint: 'Seleccione el tipo de evento',
      value: nombreActual,
      items: items,
      onChanged: (v) {
        if (v == null || v == placeholder) return;
        final matches = eventos.where((e) => e.nombre == v);
        if (matches.isEmpty) return; // valor huérfano: no escribe
        final match = matches.first;
        setState(() {
          _idTipoEvento = match.idTipoEvento;
          // Recurrencia local: esta eleccion sube al grupo "Más frecuentes".
          _freqEventos[match.idTipoEvento] =
              (_freqEventos[match.idTipoEvento] ?? 0) + 1;
        });
        unawaited(_guardarFrecuenciaEventos());
        widget.localidad.idTipoEvento = match.idTipoEvento;
        widget.localidad.tipoEventoNombre = v;
        widget.onCambio?.call();
      },
    );
  }

  // ─── Fecha ───

  Future<void> _pickFecha() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked != null && mounted) {
      final iso =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() => _fechaController.text = _fmtDate(iso));
      widget.localidad.fechaEvento = iso;
      widget.onCambio?.call();
    }
  }

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final parts = iso.split('-');
      if (parts.length == 3) return '${parts[2]}/${parts[1]}/${parts[0]}';
    } catch (_) {}
    return iso;
  }

  String _extractHour12(String isoTime) {
    try {
      final h = int.parse(isoTime.split(':').first);
      if (h == 0) return '12';
      if (h > 12) return (h - 12).toString().padLeft(2, '0');
      return h.toString().padLeft(2, '0');
    } catch (_) {
      return '12';
    }
  }

  String _extractAmPm(String isoTime) {
    try {
      final h = int.parse(isoTime.split(':').first);
      return h >= 12 ? 'PM' : 'AM';
    } catch (_) {
      return 'AM';
    }
  }

  // ─── Impactos ───

  List<Widget> _impactos(EdanLocalidad l) {
    final items = <Widget>[];

    void add(String label, IconData icono, bool value,
        ValueChanged<bool> onChanged) {
      items.add(_checkAfectacion(
        label: label,
        icono: icono,
        value: value,
        onChanged: (v) {
          onChanged(v);
          setState(() {});
          widget.onImpactosCambio?.call();
        },
      ));
    }

    Future<void> _syncSecciones(String checkboxKey, bool activar) async {
      final secciones = EdanSeccionesRegistry.checkboxSecciones[checkboxKey];
      if (secciones == null || secciones.isEmpty) return;

      // Al destildar, el modelo se vacía EN EL ACTO (display + snapshot
      // coherentes de inmediato): el grupo manda y sus filas ya no van.
      if (!activar) {
        try {
          widget.localidad.vaciarSecciones(secciones);
        } catch (_) {}
      }

      // ── Camino V2 (RESP): tabla auxiliar v31 ──
      // `secciones_grupos_local` es la fuente de verdad de "qué secciones
      // existen"; `formularios.secciones_activas_json` solo queda como vista
      // derivada para el sync engine.
      final store = widget.store;
      if (store != null) {
        final uuid = widget.localidad.uuidEdanLocalidad ??
            (widget.localidad.idLocal?.isNotEmpty == true
                ? widget.localidad.idLocal
                : null);
        if (uuid == null) return;
        if (activar) {
          await store.activarSecciones(uuid, secciones);
        } else {
          await store.desactivarSecciones(uuid, secciones);
          // Purga de filas huérfanas (DB + D si estaban confirmadas + fotos):
          // lo destildado no viaja al servidor, así que tampoco queda local.
          // El guardado completo lo reintenta (purgarInactivas) por si esta
          // llamada pierde la carrera contra un Guardar inmediato.
          try {
            await store.purgarSecciones(uuid, secciones);
          } catch (e) {
            debugPrint('[page01] purga al destildar omitida: $e');
          }
        }
        return;
      }

      // ── Camino Legacy (UGR/IA): localidad_secciones_activas ──
      final idLocal = widget.localidad.idLocal;
      if (idLocal == null || idLocal.isEmpty) return;
      final db = DatabaseHelper.instance;
      if (activar) {
        await db.activarSecciones(idLocal, secciones);
      } else {
        await db.desactivarSecciones(idLocal, secciones);
      }
    }

    // REGLA (2026-10-18, producto): 'En población' y 'Necesidades en
    // protección' forman una unidad en esta pantalla — se marcan y se
    // desmarcan JUNTOS. Al desmarcar, `vaciarSecciones`/purga (con su `D`
    // si ya estaban sincronizadas) destruye también los datos de la sección
    // hermana: así el JSON del POST sigue fiel a `grup* true ⇒ manda datos`
    // (un grupo desactivado no puede quedar con filas vivas por el otro).
    // En la matriz, la auxiliar `secciones_grupos_local` y el wire siguen
    // siendo grupos separados: un borrador restaurado del servidor con una
    // sola sección activa se muestra tal cual hasta que el usuario toque un
    // checkbox, que acopla ambos estados.
    void _toggleDemograficos(bool v) {
      l.grupPoblacion = v;
      l.grupProteccion = v;
      _syncSecciones('grupPoblacion', v);
      _syncSecciones('grupProteccion', v);
      if (!v) return;
      final rp = context.read<ReporteProvider>();
      if (l.impactoPoblacion.isEmpty) {
        // Semilla para page03 (grupos etarios). Si el usuario no llena nada,
        // el registro vacío no se envía: el filtro de filas vacías lo deja
        // fuera del payload y `toApiJson` no emite grupos sin marcar.
        l.impactoPoblacion.add(EdanImpactoPoblacion(
          gruposEtarios: EdanImpactoPoblacion.gruposDesdeCatalogo(
              rp.gruposEtarios
                  .map((g) => {
                        'id_grupo_etario': g.idGrupoEtario,
                        'nombre': g.nombre,
                      })
                  .toList()),
        ));
      }
      if (l.proteccion.isEmpty) {
        // Semilla para page10: con catálogo aún no descargado,
        // `proteccionDesdeCatalogo([])` devuelve los 8 defaults — una
        // sección activa jamás debe quedar sin filas que marcar.
        l.proteccion =
            EdanLocalidad.proteccionDesdeCatalogo(rp.gruposVulnerables);
      }
    }

    add('En población', Icons.groups_outlined, l.grupPoblacion,
        (v) => _toggleDemograficos(v));
    add('En salud', Icons.local_hospital_outlined, l.grupSalud, (v) {
      l.grupSalud = v;
      _syncSecciones('grupSalud', v);
    });
    add('En infraestructuras', Icons.location_city_outlined,
        l.grupInfraestructura, (v) {
      l.grupInfraestructura = v;
      _syncSecciones('grupInfraestructura', v);
    });
    add('En servicios básicos', Icons.home_work_outlined, l.grupServicios, (v) {
      l.grupServicios = v;
      _syncSecciones('grupServicios', v);
      if (v && l.serviciosBasicos.isEmpty) {
        l.serviciosBasicos.addAll([
          EdanServicioBasicoDetalle(tipo: 'energia_electrica'),
          EdanServicioBasicoDetalle(tipo: 'agua_potable'),
          EdanServicioBasicoDetalle(tipo: 'alcantarillado'),
          EdanServicioBasicoDetalle(tipo: 'gas_domiciliario'),
          EdanServicioBasicoDetalle(tipo: 'telecomunicaciones'),
        ]);
      }
    });
    add('En educación', Icons.school_outlined, l.grupEducacion, (v) {
      l.grupEducacion = v;
      _syncSecciones('grupEducacion', v);
    });
    add('En viviendas', Icons.home_outlined, l.grupVivienda, (v) {
      l.grupVivienda = v;
      _syncSecciones('grupVivienda', v);
    });
    add('En agropecuaria', Icons.agriculture_outlined, l.grupAgropecuario, (v) {
      l.grupAgropecuario = v;
      _syncSecciones('grupAgropecuario', v);
    });
    add('Necesidades en protección', Icons.shield_outlined, l.grupProteccion,
        (v) => _toggleDemograficos(v));
    add('Necesidades humanitarias', Icons.volunteer_activism_outlined,
        l.grupNecesidades, (v) {
      l.grupNecesidades = v;
      _syncSecciones('grupNecesidades', v);
    });
    return items;
  }

  Widget _checkAfectacion({
    required String label,
    required IconData icono,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final color = PaletteScope.of(context).primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
              color: value ? color : const Color(0xFFE2E8F0),
              width: value ? 1.5 : 1),
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
}
