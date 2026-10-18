import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import '../../../../providers/reporte_provider.dart';
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
  late final TextEditingController _nombreController;
  late final TextEditingController _fechaController;

  String? _hora12;
  String _ampm = '';
  int? _idTipoEvento;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rp = context.read<ReporteProvider>();
      // Catálogos generales (mismos para ambos roles, una vez por dispositivo):
      // si falta cualquiera de los que usa esta página, se baja el set completo.
      if (rp.tiposEvento.isEmpty || rp.tiposLocalidad.isEmpty) {
        rp.fetchAndCacheCatalogs();
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
        CustomTextField(
          label: 'Nombre de lugar *',
          hint: 'Ej: Las Lomas, San Bernardo',
          controller: _nombreController,
          textCapitalization: TextCapitalization.words,
        ),
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
    final opciones = catalogo.isNotEmpty
        ? catalogo.map((t) => t.nombre).toList()
        : kTiposLocalidadId.keys.toList();

    final actual = widget.localidad.tipoLocalidad;

    return _labeledDropdown(
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

  // ─── Tipo de evento ───

  Widget _buildTipoEvento(ReporteProvider rp) {
    final eventos = rp.tiposEvento;
    final nombreActual = _idTipoEvento != null
        ? rp.getTipoEventoNombre(_idTipoEvento!)
        : null;

    const placeholder = 'Seleccione';

    final nombres = (eventos.toList()
          ..sort((a, b) => a.nombre.compareTo(b.nombre)))
        .map((e) => e.nombre)
        .toList();
    // Un valor sin item correspondiente (catálogo aún no descargado, o id
    // obsoleto en un borrador reabierto) crasheaba el DropdownButtonFormField
    // — exige exactamente un item con ese value. Se agrega como item propio.
    if (nombreActual != null && !nombres.contains(nombreActual)) {
      nombres.add(nombreActual);
    }

    return _labeledDropdown(
      label: 'Evento extremo *',
      hint: 'Seleccione el tipo de evento',
      value: nombreActual,
      items: [
        const DropdownMenuItem<String>(
          value: placeholder,
          enabled: false,
          child: Text('Seleccione el tipo de evento'),
        ),
        ...nombres
            .map((n) => DropdownMenuItem<String>(value: n, child: Text(n))),
      ],
      onChanged: (v) {
        if (v == null || v == placeholder) return;
        final matches = eventos.where((e) => e.nombre == v);
        if (matches.isEmpty) return; // valor huérfano: no escribe
        final match = matches.first;
        setState(() => _idTipoEvento = match.idTipoEvento);
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

    // NOTA: `grupPoblacion` y `'grupProteccion'` son grupos INDEPENDIENTES en la
    // matriz. Antes desmarcar uno forzaba a apagar al otro, lo que destruía la
    // sección hermana y sus datos al volver a guardar. Ahora cada checkbox solo
    // siembra las filas vacías de SU sección y no toca al otro.
    add('En población', Icons.groups_outlined, l.grupPoblacion, (v) {
      l.grupPoblacion = v;
      _syncSecciones('grupPoblacion', v);
      if (v && l.impactoPoblacion.isEmpty) {
        // Semilla para page03 (grupos etarios). Si el usuario no llena nada,
        // el registro vacío no se envía: `toApiJson` filtra los no marcados.
        final rp = context.read<ReporteProvider>();
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
      // Al desmarcar NO se toca `'grupProteccion'`. Si protección ya tiene filas,
      // la sección sigue visible al reabrir vía `rutasConDatos` (auxiliar v31).
    });
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
        (v) {
      l.grupProteccion = v;
      _syncSecciones('grupProteccion', v);
      if (v && l.proteccion.isEmpty) {
        // Semilla para page10 (grupos vulnerables).
        final rp = context.read<ReporteProvider>();
        if (rp.gruposVulnerables.isNotEmpty) {
          l.proteccion =
              EdanLocalidad.proteccionDesdeCatalogo(rp.gruposVulnerables);
        }
      }
      // Al desmarcar NO se toca `grupPoblacion` (ver comentario arriba).
    });
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
