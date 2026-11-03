import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import 'edan_boton_sacar_foto.dart';

/// Página de resumen / vista previa del formulario.
///
/// Es una **vista de solo lectura**: nunca edita ni borra datos. Muestra un
/// resumen legible de toda la información registrada en cada sección,
/// incluyendo las fotos de respaldo (al tocarlas se abre el visor sin botón
/// de eliminar, usando `soloLectura`).
///
/// Solo se listan las secciones habilitadas según las banderas `imp*` de la
/// localidad (igual que el wizard las arma). El envío (cambio de estado a
/// "Enviado UGR") ocurre en el botón Enviar del wizard.
class EdanResumenPage extends StatefulWidget {
  final EdanLocalidad localidad;
  final Map<String, bool> seccionesCompletas;

  const EdanResumenPage({
    super.key,
    required this.localidad,
    required this.seccionesCompletas,
  });

  /// Calcula el mapa de secciones completas para una localidad.
  /// Retorna `true` solo si la sección tiene datos REALES, no solo
  /// porque el flag imp_* esté activado en page01.
  static Map<String, bool> calcularSeccionesCompletas(EdanLocalidad l) {
    return {
      '01': l.nombre.trim().isNotEmpty && l.idTipoEvento != null,
      '02': l.totalPoblacionAfectada > 0 ||
          l.totalFamiliasAfectadas > 0 ||
          l.totalFamiliasDamnificadas > 0,
      if (l.grupPoblacion)
        '03': _seccionTieneDatos03(l) && l.sumaGruposEtarios <= l.totalPoblacionAfectada,
      if (l.grupSalud)
        '04': _seccionTieneDatos04(l) &&
            (l.sumaSaludPersonal + (l.necesidadSalud?.numeroPersonas ?? 0)) <= l.totalPoblacionAfectada,
      if (l.grupInfraestructura) '05': _seccionTieneDatos05(l),
      if (l.grupServicios) '06': _seccionTieneDatos06(l),
      if (l.grupEducacion)
        '07': _seccionTieneDatos07(l) && l.sumaUnidadesEducativas <= l.totalPoblacionAfectada,
      if (l.grupVivienda) '08': _seccionTieneDatos08(l),
      if (l.grupAgropecuario) '09': _seccionTieneDatos09(l),
      if (l.grupProteccion)
        '10': _seccionTieneDatos10(l) && l.sumaProteccion <= l.totalPoblacionAfectada,
      if (l.grupNecesidades) '11': _seccionTieneDatos11(l),
      '13': (l.responsable?.nombre.trim().isNotEmpty ?? false) &&
          (l.responsable?.cargo.trim().isNotEmpty ?? false),
    };
  }

  /// Retorna true si el formulario está completo (todas las secciones
  /// activadas tienen datos reales).
  static bool formularioCompleto(EdanLocalidad l) {
    final secciones = calcularSeccionesCompletas(l);
    return secciones.values.every((completa) => completa);
  }

  static bool _seccionTieneDatos03(EdanLocalidad l) {
    return l.impactoPoblacion.any((i) => i.tieneDatosGlobales) ||
        (l.necesidadPrimeraRespuesta?.tieneDatos ?? false);
  }

  static bool _seccionTieneDatos04(EdanLocalidad l) {
    return l.establecimientosSalud.isNotEmpty ||
        (l.necesidadSalud?.tieneDatos ?? false);
  }

  static bool _seccionTieneDatos05(EdanLocalidad l) {
    return l.danosViales.isNotEmpty || l.danosInfraPublica.isNotEmpty;
  }

  static bool _seccionTieneDatos06(EdanLocalidad l) {
    return l.serviciosBasicos.any((s) => s.tieneDatos);
  }

  static bool _seccionTieneDatos07(EdanLocalidad l) {
    return l.unidadesEducativas.isNotEmpty;
  }

  static bool _seccionTieneDatos08(EdanLocalidad l) {
    return l.danosVivienda.isNotEmpty;
  }

  static bool _seccionTieneDatos09(EdanLocalidad l) {
    return l.danosAgricultura.isNotEmpty ||
        l.danosPecuarios.isNotEmpty ||
        l.infraProductiva.isNotEmpty;
  }

  static bool _seccionTieneDatos10(EdanLocalidad l) {
    return l.proteccion.any((g) => g.tieneDatos);
  }

  static bool _seccionTieneDatos11(EdanLocalidad l) {
    return l.necesidadHumanitaria?.tieneDatos ?? false;
  }

  @override
  State<EdanResumenPage> createState() => _EdanResumenPageState();
}

class _EdanResumenPageState extends State<EdanResumenPage> {
  // Todas las secciones visibles se expanden por defecto en el primer build.
  final Set<String> _expandidas = <String>{};
  final Set<String> _seccionesInicializadas = <String>{};

  EdanLocalidad get _l => widget.localidad;

  @override
  Widget build(BuildContext context) {
    final l = _l;

    final secciones = <_Seccion>[
      _Seccion('01', 'Datos generales', Icons.place_outlined, _completa('01'),
          _datosGenerales(l)),
      _Seccion('02', 'Población damnificada y afectada', Icons.people_outline, _completa('02'),
          _totales(l)),
      if (l.grupPoblacion)
        _Seccion('03', 'Impacto en la población', Icons.groups_outlined,
            _completa('03'), _impactoPoblacion(l)),
      if (l.grupSalud)
        _Seccion('04', 'Impacto en la salud', Icons.local_hospital_outlined,
            _completa('04'), _salud(l)),
      if (l.grupInfraestructura)
        _Seccion('05', 'Impacto en infraestructuras', Icons.construction,
            _completa('05'), _infra(l)),
      if (l.grupServicios)
        _Seccion('06', 'Impacto en servicios básicos',
            Icons.home_work_outlined, _completa('06'), _servicios(l)),
      if (l.grupEducacion)
        _Seccion('07', 'Impacto en educación', Icons.school_outlined,
            _completa('07'), _educacion(l)),
      if (l.grupVivienda)
        _Seccion('08', 'Impacto en viviendas', Icons.home_outlined,
            _completa('08'), _vivienda(l)),
      if (l.grupAgropecuario)
        _Seccion('09', 'Impacto agropecuario', Icons.agriculture_outlined,
            _completa('09'), _agro(l)),
      if (l.grupProteccion)
        _Seccion('10', 'Impacto en protección', Icons.shield_outlined,
            _completa('10'), _proteccion(l)),
      if (l.grupNecesidades)
        _Seccion('11', 'Necesidades humanitarias',
            Icons.volunteer_activism_outlined, _completa('11'), _necesidades(l)),
      _Seccion('13', 'Responsable', Icons.badge_outlined, _completa('13'),
          _responsable(l)),
    ];

    // Expandir por defecto TODAS las secciones visibles (solo la primera vez,
    // para no intervenir con el toggle manual posterior del usuario).
    for (final s in secciones) {
      if (_seccionesInicializadas.add(s.key)) {
        _expandidas.add(s.key);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.visibility_outlined,
                size: 20, color: AppColors.secondary),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Vista previa de la evaluación',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary),
              ),
            ),
          ] ,
        ),
        const SizedBox(height: 2),
        const Padding(
          padding: EdgeInsets.only(left: 28),
          child: Text(
            'Solo lectura. Revise la información antes de enviar; puede '
            'volver a las secciones para modificar.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: 14),
        for (final s in secciones) _tarjetaSeccion(s),
        const SizedBox(height: 8),
        if (_puedeEnviar())
          const Padding(
            padding: EdgeInsets.only(left: 28),
            child: Text(
              'Al presionar "Enviar", el formulario cambiará a estado '
              '"Enviado UGR".',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
      ],
    );
  }

  bool _completa(String key) => widget.seccionesCompletas[key] ?? false;

  /// Solo se puede enviar desde los estados borrador (id=1) y rechazadoUgr
  /// (id=4); en el resto (enviadoUgr, aprobadoUgr, aprobadoAjuste,
  /// enRevisionUgr) el mensaje de "Enviar" no debe mostrarse.
  bool _puedeEnviar() {
    final e = _l.estadoLocalidad;
    return e == UgrLocalidadEstado.borrador ||
        e == UgrLocalidadEstado.rechazadoUgr;
  }

  // ─────────────────────────── Tarjeta sección ───────────────────────────

  Widget _tarjetaSeccion(_Seccion s) {
    final color = _colorSeccion(s.key);
    final expandida = _expandidas.contains(s.key);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: s.completa
              ? const Color(0xFF4CAF50)
              : AppColors.divider,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() {
              if (expandida) {
                _expandidas.remove(s.key);
              } else {
                _expandidas.add(s.key);
              }
            }),
            child: Container(
              color: color.withValues(alpha: 0.06),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(s.icono, size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.titulo,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          s.completa
                              ? 'Sección completada'
                              : 'Sección pendiente',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: s.completa
                                ? const Color(0xFF4CAF50)
                                : color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expandida
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (expandida) _cuerpo(s),
        ],
      ),
    );
  }

  Widget _cuerpo(_Seccion s) {
    if (s.lineas.isEmpty) {
      return Container(
        width: double.infinity,
        color: const Color(0xFFF8FAFC),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Sección no marcada, actualmente sin datos, solo marque si es '
                'necesario.',
                style:
                    TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < s.lineas.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            _LineaWidget(linea: s.lineas[i]),
          ],
        ],
      ),
    );
  }

  Color _colorSeccion(String key) {
    switch (key) {
      case '01':
        return const Color(0xFF0D47A1);
      case '02':
        return const Color(0xFF6D4C41);
      case '03':
        return const Color(0xFF2563EB);
      case '04':
        return const Color(0xFFC0392B);
      case '05':
        return const Color(0xFF7F1D1D);
      case '06':
        return const Color(0xFF0E7490);
      case '07':
        return const Color(0xFF7C3AED);
      case '08':
        return const Color(0xFFB45309);
      case '09':
        return const Color(0xFF15803D);
      case '10':
        return const Color(0xFF9D174D);
      case '11':
        return const Color(0xFF4338CA);
      case '13':
        return const Color(0xFF334155);
      default:
        return AppColors.primary;
    }
  }

  // ─────────────────────────── Secciones ─────────────────────────

  List<_Linea> _datosGenerales(EdanLocalidad l) {
    final lineas = <_Linea>[];
    void par(String label, String? v) {
      final t = (v ?? '').trim();
      if (t.isNotEmpty) lineas.add(_Linea.par(label, t));
    }

    par('Localidad', l.etiquetaLugar);
    par('Tipo', l.tipoLocalidad);
    par('Departamento', l.departamentoNombre);
    par('Provincia', l.provinciaNombre);
    par('Municipio', l.municipioNombre);
    par('Fecha de llenado', l.fechaLlenado);
    par('Fecha del evento', l.fechaEvento);
    par('Hora del evento', l.horaEvento);
    final tipo = (l.tipoEventoNombre ?? '').trim();
    if (tipo.isNotEmpty) lineas.add(_Linea.badge('Tipo de evento', tipo));
    return lineas;
  }

  List<_Linea> _totales(EdanLocalidad l) => [
        if (l.totalPoblacionAfectada > 0)
          _Linea.par('Población afectada', '${l.totalPoblacionAfectada}'),
        if (l.totalFamiliasAfectadas > 0)
          _Linea.par('Familias afectadas', '${l.totalFamiliasAfectadas}'),
        if (l.totalFamiliasDamnificadas > 0)
          _Linea.par('Familias damnificadas',
              '${l.totalFamiliasDamnificadas}'),
      ];

  List<_Linea> _impactoPoblacion(EdanLocalidad l) {
    final lineas = <_Linea>[];
    if (l.impactoPoblacion.isNotEmpty) {
      lineas.add(const _Linea.titulo('Grupos de edad'));
      // Contrato del set EXACTO 1-4 (§20.10.E): la vista muestra SIEMPRE los
      // 4 grupos, rellenos con 0 donde no hay datos. Con la forma V2 (wrapper
      // con grupos anidados) se toma el anidado; con la plana legacy (una fila
      // por rango) cada fila aporta su grupo.
      final anidados = <EdanGrupoEtario>[
        for (final p in l.impactoPoblacion) ...p.gruposEtarios,
      ];
      final fuentes = anidados.isNotEmpty
          ? anidados
          : [
              for (final p in l.impactoPoblacion)
                EdanGrupoEtario(
                  rango: p.grupoEtario,
                  fallecidos: p.fallecidos,
                  heridos: p.heridos,
                  desaparecidos: p.desaparecidos,
                  observaciones: p.observaciones,
                  marcado: p.tieneDatosGlobales ||
                      p.observaciones.trim().isNotEmpty,
                  idGrupoEtarioCatalogo:
                      EdanGrupoEtario.resolverIdGrupoEtario(p.grupoEtario),
                ),
            ];
      final grupos = EdanGrupoEtario.completarSet4(fuentes);
      for (final g in grupos) {
        lineas.add(_Linea.subcard([
          _Linea.par('Rango', g.rango),
          _Linea.par('Fallecidos', '${g.fallecidos}'),
          _Linea.par('Heridos', '${g.heridos}'),
          _Linea.par('Desaparecidos', '${g.desaparecidos}'),
          if (g.observaciones.trim().isNotEmpty)
            _Linea.par('Observaciones', g.observaciones.trim()),
        ]));
      }

      // Total desglosado (suma de los 4 slots mostrados).
      var tf = 0;
      var th = 0;
      var td = 0;
      for (final g in grupos) {
        tf += g.fallecidos;
        th += g.heridos;
        td += g.desaparecidos;
      }
      final total = tf + th + td;
      if (total > 0) {
        lineas.add(const _Linea.titulo('total población'));
        if (tf > 0) lineas.add(_Linea.par('Fallecidos', '$tf'));
        if (th > 0) lineas.add(_Linea.par('Heridos', '$th'));
        if (td > 0) lineas.add(_Linea.par('Desaparecidos', '$td'));
        lineas.add(_Linea.par('Total afectados', '$total'));
      }
    }

    final hayPrimera = l.impPrimeraRespuesta &&
        (l.necesidadPrimeraRespuesta?.algunaSeleccionada ?? false);
    if (hayPrimera) {
      final nr = l.necesidadPrimeraRespuesta!;
      lineas.add(const _Linea.titulo('Necesidades de primera respuesta'));
      final req = <String>[
        if (nr.busqueda) 'Búsqueda',
        if (nr.salvamento) 'Salvamento',
        if (nr.evacuacion) 'Evacuación',
      ];
      if (req.isNotEmpty)
        lineas.add(_Linea.par('Requiere', req.join(', ')));
      if (nr.observaciones.trim().isNotEmpty)
        lineas.add(_Linea.par('Observaciones', nr.observaciones));
    }
    return lineas;
  }

  List<_Linea> _salud(EdanLocalidad l) {
    final lineas = <_Linea>[];
    final conEstabl =
        l.impSaludEstablecimientos && l.establecimientosSalud.isNotEmpty;
    final conNec =
        l.impNecesidadSalud && (l.necesidadSalud?.numeroPersonas ?? 0) > 0;

    if (conEstabl) {
      lineas.add(const _Linea.titulo('Establecimientos de salud'));
      for (final e in l.establecimientosSalud) {
        lineas.add(_Linea.subcard([
          _Linea.par(
              'Nombre', e.nombreEstablecimiento.isEmpty ? 'Sin nombre' : e.nombreEstablecimiento),
          if (e.comunidad.trim().isNotEmpty)
            _Linea.par('Localidad', e.comunidad),
          if (e.nivelAtencion.trim().isNotEmpty)
            _Linea.par('Nivel de atención', e.nivelAtencion),
          if (e.danoTotal) _Linea.par('Estado', 'Daño total'),
          if (e.danoParcial) _Linea.par('Estado', 'Daño parcial'),
          if (e.medicosAfectados > 0)
            _Linea.par('Médicos afectados', '${e.medicosAfectados}'),
          if (e.enfermerasAfectados > 0)
            _Linea.par('Enfermeras afectadas', '${e.enfermerasAfectados}'),
          if (e.otrosAfectados > 0)
            _Linea.par('Otros afectados', '${e.otrosAfectados}'),
          ..._fotoLineas(e, 'Establecimiento'),
        ]));
      }

      // Total desglosado salud
      var tmed = 0;
      var tenf = 0;
      var tot = 0;
      for (final e in l.establecimientosSalud) {
        tmed += e.medicosAfectados;
        tenf += e.enfermerasAfectados;
        tot += e.otrosAfectados;
      }
      final tPersonal = tmed + tenf + tot;
      if (tPersonal > 0) {
        lineas.add(const _Linea.titulo('total salud'));
        if (tmed > 0) lineas.add(_Linea.par('Médicos', '$tmed'));
        if (tenf > 0) lineas.add(_Linea.par('Enfermeras', '$tenf'));
        if (tot > 0) lineas.add(_Linea.par('Otros', '$tot'));
        lineas.add(_Linea.par('Total personal', '$tPersonal'));
      }
    }

    if (conNec) {
      final n = l.necesidadSalud!;
      lineas.add(const _Linea.titulo('Necesidad de salud'));
      if (n.numeroPersonas > 0)
        lineas.add(_Linea.par('Personas', '${n.numeroPersonas}'));
      if (n.botiquines) lineas.add(_Linea.par('Botiquines', 'Sí'));
      if (n.otrasNecesidades.trim().isNotEmpty)
        lineas.add(_Linea.par('Otras necesidades', n.otrasNecesidades));
      if (n.observaciones.trim().isNotEmpty)
        lineas.add(_Linea.par('Observaciones', n.observaciones));
    }
    return lineas;
  }

  List<_Linea> _infra(EdanLocalidad l) {
    final lineas = <_Linea>[];
    final conViales = l.impDanosViales && l.danosViales.isNotEmpty;
    final conPublica =
        l.impDanosInfraPublica && l.danosInfraPublica.isNotEmpty;

    if (conViales) {
      lineas.add(const _Linea.titulo('Daños en vías y puentes'));
      for (final d in l.danosViales) {
        lineas.add(_Linea.subcard([
          _Linea.par('Vía / puente',
              d.viaPuente.isEmpty ? 'Sin especificar' : d.viaPuente),
          if (d.tramo.trim().isNotEmpty) _Linea.par('Tramo', d.tramo),
          if (d.danoTotal) _Linea.par('Estado', 'Total'),
          if (d.danoParcial) _Linea.par('Estado', 'Parcial'),
          if (d.kmDanio > 0) _Linea.par('Km de daño', '${d.kmDanio}'),
          if (d.necesidadesInmediatas.trim().isNotEmpty)
            _Linea.par('Necesidades', d.necesidadesInmediatas),
          if (d.observaciones.trim().isNotEmpty)
            _Linea.par('Observaciones', d.observaciones),
          ..._fotoLineas(d, 'Vía/puente'),
        ]));
      }
    }

    if (conPublica) {
      lineas.add(const _Linea.titulo('Daños en infraestructura pública'));
      for (final i in l.danosInfraPublica) {
        lineas.add(_Linea.subcard([
          _Linea.par(
              'Estructura',
              i.tipoEstructura.isEmpty
                  ? 'Sin especificar'
                  : i.tipoEstructura),
          if (i.comunidad.trim().isNotEmpty)
            _Linea.par('Localidad', i.comunidad),
          if (i.danoTotal) _Linea.par('Estado', 'Total'),
          if (i.danoParcial) _Linea.par('Estado', 'Parcial'),
          if (i.observaciones.trim().isNotEmpty)
            _Linea.par('Observaciones', i.observaciones),
          ..._fotoLineas(i, 'Infraestructura'),
        ]));
      }
    }

    // Total desglosado infraestructura
    if (conViales || conPublica) {
      final tv = l.danosViales.length;
      final tvTotal = l.danosViales.where((v) => v.danoTotal).length;
      final tvParcial = l.danosViales.where((v) => v.danoParcial).length;
      final tk = l.danosViales.fold<double>(0, (a, v) => a + v.kmDanio);
      final ti = l.danosInfraPublica.length;
      final tiTotal = l.danosInfraPublica.where((e) => e.danoTotal).length;
      final tiParcial = l.danosInfraPublica.where((e) => e.danoParcial).length;

      if (tv > 0 || ti > 0) {
        lineas.add(const _Linea.titulo('total infraestructura'));
        if (tv > 0) {
          lineas.add(_Linea.par('Vías/puentes afectados', '$tv'));
          if (tvTotal > 0) lineas.add(_Linea.par('Daño total', '$tvTotal'));
          if (tvParcial > 0) lineas.add(_Linea.par('Daño parcial', '$tvParcial'));
          if (tk > 0) lineas.add(_Linea.par('Km de daño', '${tk.toStringAsFixed(1)}'));
        }
        if (ti > 0) {
          lineas.add(_Linea.par('Infraestructura pública', '$ti'));
          if (tiTotal > 0) lineas.add(_Linea.par('Daño total', '$tiTotal'));
          if (tiParcial > 0) lineas.add(_Linea.par('Daño parcial', '$tiParcial'));
        }
      }
    }
    return lineas;
  }

  List<_Linea> _servicios(EdanLocalidad l) {
    final lineas = <_Linea>[];
    for (final s in l.serviciosBasicos) {
      if (!s.afectado && !s.tieneDatos) continue;
      lineas.add(_Linea.subcard([
        _Linea.par('Servicio', s.etiqueta),
        if (s.danoTotal) _Linea.par('Estado', 'Total'),
        if (s.danoParcial) _Linea.par('Estado', 'Parcial'),
        if (s.necesidadesInmediatas.trim().isNotEmpty)
          _Linea.par('Necesidades', s.necesidadesInmediatas),
        if (s.observaciones.trim().isNotEmpty)
          _Linea.par('Observaciones', s.observaciones),
        ..._fotoLineas(s, 'Servicio'),
      ]));
    }
    // Total desglosado servicios
    final totalAfectados = l.serviciosBasicos.where((s) => s.afectado).length;
    final totalTotal = l.serviciosBasicos.where((s) => s.danoTotal).length;
    final totalParcial = l.serviciosBasicos.where((s) => s.danoParcial).length;
    if (totalAfectados > 0) {
      lineas.add(const _Linea.titulo('total servicios'));
      lineas.add(_Linea.par('Servicios afectados', '$totalAfectados'));
      if (totalTotal > 0) lineas.add(_Linea.par('Daño total', '$totalTotal'));
      if (totalParcial > 0) lineas.add(_Linea.par('Daño parcial', '$totalParcial'));
    }
    return lineas;
  }

  List<_Linea> _educacion(EdanLocalidad l) {
    final lineas = <_Linea>[];
    for (final u in l.unidadesEducativas) {
      lineas.add(_Linea.subcard([
        _Linea.par(
            'Unidad',
            u.nombreEstablecimiento.isEmpty
                ? 'Sin nombre'
                : u.nombreEstablecimiento),
        if (u.comunidad.trim().isNotEmpty)
          _Linea.par('Localidad', u.comunidad),
        if (u.danoTotal) _Linea.par('Estado', 'Total'),
        if (u.danoParcial) _Linea.par('Estado', 'Parcial'),
        if (u.totalAfectados > 0)
          _Linea.par('Total afectados',
              '${u.totalAfectados} (estudiantes ${u.estudiantes}, '
              'profesores ${u.profesores}, administrativos '
              '${u.administrativos})'),
        if (u.observaciones.trim().isNotEmpty)
          _Linea.par('Observaciones', u.observaciones),
        ..._fotoLineas(u, 'Educación'),
      ]));
    }
    // Total desglosado educación
    if (l.unidadesEducativas.isNotEmpty) {
      var te = 0;
      var tp = 0;
      var ta = 0;
      for (final u in l.unidadesEducativas) {
        te += u.estudiantes;
        tp += u.profesores;
        ta += u.administrativos;
      }
      final total = te + tp + ta;
      if (total > 0) {
        lineas.add(const _Linea.titulo('total educación'));
        if (te > 0) lineas.add(_Linea.par('Estudiantes', '$te'));
        if (tp > 0) lineas.add(_Linea.par('Profesores', '$tp'));
        if (ta > 0) lineas.add(_Linea.par('Administrativos', '$ta'));
        lineas.add(_Linea.par('Total afectados', '$total'));
      }
      lineas.add(_Linea.par('Unidades afectadas', '${l.unidadesEducativas.length}'));
    }
    return lineas;
  }

  List<_Linea> _vivienda(EdanLocalidad l) {
    final lineas = <_Linea>[];
    // Contadores por fila: con detalle 1:N se derivan de las viviendas
    // (TOTAL/PARCIAL); sin detalle se conservan los manuales `dano_*`.
    int parcialDe(EdanDanoVivienda v) =>
        v.viviendas.isNotEmpty ? v.viviendasParcial : v.danoParcial;
    int totalDe(EdanDanoVivienda v) =>
        v.viviendas.isNotEmpty ? v.viviendasTotal : v.danoTotal;

    for (final v in l.danosVivienda) {
      final parcial = parcialDe(v);
      final total = totalDe(v);
      // Detalle 1:N: cada vivienda hija muestra su daño, coordenadas y SU
      // propia foto (en el flujo V2 la foto vive en la hija, no en el padre;
      // el resumen solo pintaba al padre y la foto desaparecía — bug
      // 2026-11-02). `_Linea.fotos` acepta `foto: null` + `fotografia` (ruta
      // local o de servidor): la miniatura y el visor compartido resuelven
      // igual que en las demás secciones.
      final hijas = <_Linea>[];
      for (var i = 0; i < v.viviendas.length; i++) {
        final viv = v.viviendas[i];
        final tieneFoto = (viv.fotografia ?? '').isNotEmpty;
        final conCoords = viv.coordenadaLat != 0 || viv.coordenadaLon != 0;
        hijas.add(_Linea.subcard([
          _Linea.par('Vivienda ${i + 1}', viv.tipoDano.name.toUpperCase()),
          if (!tieneFoto && conCoords)
            _Linea.par(
              'Coordenadas',
              '${viv.coordenadaLat.toStringAsFixed(5)}, '
              '${viv.coordenadaLon.toStringAsFixed(5)}',
            ),
          if (tieneFoto)
            _Linea.fotos(
              seccion: 'Viviendas',
              foto: null,
              fotografia: viv.fotografia,
              coordenadaLat: viv.coordenadaLat,
              coordenadaLon: viv.coordenadaLon,
            ),
        ]));
      }
      lineas.add(_Linea.subcard([
        _Linea.par('Localidad',
            v.comunidad.isEmpty ? 'No especificada' : v.comunidad),
        if (parcial > 0) _Linea.par('Daño parcial', '$parcial'),
        if (total > 0) _Linea.par('Daño total', '$total'),
        if (v.necesidadesInmediatas.trim().isNotEmpty)
          _Linea.par('Necesidades', v.necesidadesInmediatas),
        if (v.observaciones.trim().isNotEmpty)
          _Linea.par('Observaciones', v.observaciones),
        ..._fotoLineas(v, 'Vivienda'),
        ...hijas,
      ]));
    }
    // Total desglosado vivienda
    if (l.danosVivienda.isNotEmpty) {
      var tParcial = 0;
      var tTotal = 0;
      for (final v in l.danosVivienda) {
        tParcial += parcialDe(v);
        tTotal += totalDe(v);
      }
      final tAfectadas = tParcial + tTotal;
      if (tAfectadas > 0) {
        lineas.add(const _Linea.titulo('total vivienda'));
        if (tParcial > 0) lineas.add(_Linea.par('Daño parcial', '$tParcial'));
        if (tTotal > 0) lineas.add(_Linea.par('Daño total', '$tTotal'));
        lineas.add(_Linea.par('Total viviendas afectadas', '$tAfectadas'));
      }
    }
    return lineas;
  }

  List<_Linea> _agro(EdanLocalidad l) {
    final lineas = <_Linea>[];

    if (l.impDanosAgricultura && l.danosAgricultura.isNotEmpty) {
      lineas.add(const _Linea.titulo('Daños en cultivos'));
      for (final a in l.danosAgricultura) {
        lineas.add(_Linea.subcard([
          _Linea.par(
              'Cultivo', a.tipoCultivo.isEmpty ? 'Sin especificar' : a.tipoCultivo),
          if (a.hectareasAfectadas > 0)
            _Linea.par('Ha afectadas', '${a.hectareasAfectadas}'),
          if (a.hectareasPerdidas > 0)
            _Linea.par('Ha perdidas', '${a.hectareasPerdidas}'),
          if (a.necesidadesInmediatas.trim().isNotEmpty)
            _Linea.par('Necesidades', a.necesidadesInmediatas),
          if (a.observaciones.trim().isNotEmpty)
            _Linea.par('Observaciones', a.observaciones),
          ..._fotoLineas(a, 'Cultivos'),
        ]));
      }
    }

    if (l.impDanosPecuarios && l.danosPecuarios.isNotEmpty) {
      lineas.add(const _Linea.titulo('Daños pecuarios'));
      for (final p in l.danosPecuarios) {
        lineas.add(_Linea.subcard([
          _Linea.par('Especie',
              p.especie.isEmpty ? 'Sin especificar' : p.especie),
          if (p.raza.trim().isNotEmpty) _Linea.par('Raza', p.raza),
          if (p.animalesAfectados > 0)
            _Linea.par('Animales afectados', '${p.animalesAfectados}'),
          if (p.animalesMuertos > 0)
            _Linea.par('Animales muertos', '${p.animalesMuertos}'),
          if (p.necesidadesInmediatas.trim().isNotEmpty)
            _Linea.par('Necesidades', p.necesidadesInmediatas),
          ..._fotoLineas(p, 'Pecuario'),
        ]));
      }
    }

    if (l.impInfraProductiva && l.infraProductiva.isNotEmpty) {
      lineas.add(const _Linea.titulo('Infraestructura productiva'));
      for (final i in l.infraProductiva) {
        lineas.add(_Linea.subcard([
          _Linea.par('Tipo', i.tipo.isEmpty ? 'Sin especificar' : i.tipo),
          if (i.danoParcial > 0) _Linea.par('Daño parcial', '${i.danoParcial}'),
          if (i.danoTotal > 0) _Linea.par('Daño total', '${i.danoTotal}'),
          ..._fotoLineas(i, 'Infra productiva'),
        ]));
      }
    }

    // Total desglosado agropecuario
    final hayAgro = l.impDanosAgricultura && l.danosAgricultura.isNotEmpty;
    final hayPec = l.impDanosPecuarios && l.danosPecuarios.isNotEmpty;
    final hayInfraP = l.impInfraProductiva && l.infraProductiva.isNotEmpty;
    if (hayAgro || hayPec || hayInfraP) {
      lineas.add(const _Linea.titulo('total agropecuario'));
      if (hayAgro) {
        var tha = 0;
        var thp = 0;
        for (final a in l.danosAgricultura) {
          tha += a.hectareasAfectadas;
          thp += a.hectareasPerdidas;
        }
        if (tha > 0) lineas.add(_Linea.par('Ha afectadas', '$tha'));
        if (thp > 0) lineas.add(_Linea.par('Ha perdidas', '$thp'));
        lineas.add(_Linea.par('Cultivos', '${l.danosAgricultura.length}'));
      }
      if (hayPec) {
        var taa = 0;
        var tam = 0;
        for (final p in l.danosPecuarios) {
          taa += p.animalesAfectados;
          tam += p.animalesMuertos;
        }
        if (taa > 0) lineas.add(_Linea.par('Animales afectados', '$taa'));
        if (tam > 0) lineas.add(_Linea.par('Animales muertos', '$tam'));
        lineas.add(_Linea.par('Especies', '${l.danosPecuarios.length}'));
      }
      if (hayInfraP) {
        var tip = 0;
        var tit = 0;
        for (final i in l.infraProductiva) {
          tip += i.danoParcial;
          tit += i.danoTotal;
        }
        if (tip > 0) lineas.add(_Linea.par('Infra parcial', '$tip'));
        if (tit > 0) lineas.add(_Linea.par('Infra total', '$tit'));
        lineas.add(_Linea.par('Infra productiva', '${l.infraProductiva.length}'));
      }
    }
    return lineas;
  }

  List<_Linea> _proteccion(EdanLocalidad l) {
    final lineas = <_Linea>[];
    // Contrato del set EXACTO 1-8 (§20.11): la vista muestra SIEMPRE los 8
    // grupos vulnerables, rellenos con 0 donde no hay datos.
    final grupos = EdanGrupoVulnerable.completarSet8(l.proteccion);
    for (final g in grupos) {
      String siNo(bool? v) => v == null ? '—' : (v ? 'Sí' : 'No');
      lineas.add(_Linea.subcard([
        _Linea.par(
            'Grupo',
            (g.nombreGrupo?.trim().isNotEmpty ?? false)
                ? g.nombreGrupo!.trim()
                : 'Grupo vulnerable'),
        _Linea.par('N° Mujeres', '${g.mujeres}'),
        _Linea.par('N° Hombres', '${g.hombres}'),
        _Linea.par('Total', '${g.total}'),
        _Linea.par('¿Apoyo psicológico?', siNo(g.apoyoPsicologico)),
        _Linea.par('¿Reposición de documentos?', siNo(g.reposicionDocumentos)),
        if (g.observaciones.trim().isNotEmpty)
          _Linea.par('Observaciones', g.observaciones),
      ]));
    }
    // Total desglosado protección (solo grupos con datos).
    final gruposConDatos = l.proteccion.where((g) => g.tieneDatos).toList();
    if (gruposConDatos.isNotEmpty) {
      var tm = 0;
      var th = 0;
      for (final g in gruposConDatos) {
        tm += g.mujeres;
        th += g.hombres;
      }
      final tp = tm + th;
      if (tp > 0) {
        lineas.add(const _Linea.titulo('total protección'));
        if (tm > 0) lineas.add(_Linea.par('Mujeres', '$tm'));
        if (th > 0) lineas.add(_Linea.par('Hombres', '$th'));
        lineas.add(_Linea.par('Total personas', '$tp'));
      }
      lineas.add(_Linea.par('Grupos con datos', '${gruposConDatos.length}'));
    }
    return lineas;
  }

  List<_Linea> _necesidades(EdanLocalidad l) {
    final n = l.necesidadHumanitaria;
    if (n == null) return [];
    final items = <(String, String)>[
      if (n.alimentos) ('Alimentos', n.obsAlimentos),
      if (n.refugioVivienda) ('Refugio / vivienda', n.obsRefugioVivienda),
      if (n.ropaCama) ('Ropa de cama', n.obsRopaCama),
      if (n.articulosHigiene) ('Artículos de higiene', n.obsArticulosHigiene),
      if (n.articulosCocina) ('Artículos de cocina', n.obsArticulosCocina),
      if (n.prendasVestir) ('Prendas de vestir', n.obsPrendasVestir),
      if (n.herramientas) ('Herramientas', n.obsHerramientas),
      if (n.almacenamientoAgua)
        ('Almacenamiento de agua', n.obsAlmacenamientoAgua),
      if (n.banos) ('Baños', n.obsBanos),
    ];
    final lineas = <_Linea>[
      for (final it in items)
        _Linea.par(it.$1,
            it.$2.trim().isNotEmpty ? it.$2 : 'Requiere'),
    ];
    // Total desglosado necesidades
    if (items.isNotEmpty) {
      lineas.add(const _Linea.titulo('total necesidades'));
      lineas.add(_Linea.par('Necesidades marcadas', '${items.length}'));
    }
    return lineas;
  }

  List<_Linea> _responsable(EdanLocalidad l) {
    final r = l.responsable;
    final lineas = <_Linea>[
      // Autor REAL del servidor (nodo `usuario` disgregado). Distinto del
      // responsable declarante (page13): quién registró el formulario.
      if (l.usuario != null && l.usuario!.nombre.trim().isNotEmpty)
        _Linea.par('Registrado por', l.usuario!.nombre),
      if (l.usuario != null && l.usuario!.usuario.trim().isNotEmpty)
        _Linea.par('Cuenta', l.usuario!.usuario),
      if (l.usuario?.rol != null &&
          l.usuario!.rol!.nombre.trim().isNotEmpty)
        _Linea.par('Rol', l.usuario!.rol!.nombre),
    ];
    if (r == null) return lineas;
    return [
      ...lineas,
      if (r.nombre.trim().isNotEmpty) _Linea.par('Nombre', r.nombre),
      if (r.cargo.trim().isNotEmpty) _Linea.par('Cargo', r.cargo),
      if (r.fono.trim().isNotEmpty) _Linea.par('Teléfono', r.fono),
      if (r.correo.trim().isNotEmpty) _Linea.par('Correo', r.correo),
    ];
  }

  List<_Linea> _fotoLineas(EdanFotoHolder item, String seccion) {
    final tieneLocal =
        item.fotos.isNotEmpty &&
        item.fotos.any((f) => File(f.ruta).existsSync());
    final tieneRemota = (item.fotografia ?? '').isNotEmpty;
    if (!tieneLocal && !tieneRemota) return [];
    return [
      _Linea.fotos(
        seccion: seccion,
        foto: item.fotos.isNotEmpty ? item.fotos.first : null,
        fotografia: item.fotografia,
        coordenadaLat: item.coordenadaLat,
        coordenadaLon: item.coordenadaLon,
      ),
    ];
  }
}

// ─────────────────────────────── Modelo UI ───────────────────────────────

class _Seccion {
  final String key;
  final String titulo;
  final IconData icono;
  final bool completa;
  final List<_Linea> lineas;

  _Seccion(this.key, this.titulo, this.icono, this.completa, this.lineas);
}

/// Una línea de contenido del resumen: etiqueta/valor, un subtítulo, una
/// subcard agrupada o una galería de fotos.
class _Linea {
  const _Linea.par(this.etiqueta, this.valor)
      : seccion = null,
        foto = null,
        fotografia = null,
        coordenadaLat = 0,
        coordenadaLon = 0,
        titulo = null,
        subcards = null,
        badgeEtiqueta = null,
        badgeValor = null;
  const _Linea.titulo(this.titulo)
      : seccion = null,
        foto = null,
        fotografia = null,
        coordenadaLat = 0,
        coordenadaLon = 0,
        etiqueta = null,
        valor = null,
        subcards = null,
        badgeEtiqueta = null,
        badgeValor = null;
  const _Linea.subcard(this.subcards)
      : seccion = null,
        foto = null,
        fotografia = null,
        coordenadaLat = 0,
        coordenadaLon = 0,
        etiqueta = null,
        valor = null,
        titulo = null,
        badgeEtiqueta = null,
        badgeValor = null;
  const _Linea.badge(this.badgeEtiqueta, this.badgeValor)
      : seccion = null,
        foto = null,
        fotografia = null,
        coordenadaLat = 0,
        coordenadaLon = 0,
        etiqueta = null,
        valor = null,
        titulo = null,
        subcards = null;
  const _Linea.fotos({
    required this.seccion,
    this.foto,
    this.fotografia,
    required this.coordenadaLat,
    required this.coordenadaLon,
  })  : etiqueta = null,
        valor = null,
        titulo = null,
        subcards = null,
        badgeEtiqueta = null,
        badgeValor = null;

  final String? seccion;
  final EdanFoto? foto;
  final String? fotografia;
  final double coordenadaLat;
  final double coordenadaLon;
  final String? etiqueta;
  final String? valor;
  final String? titulo;
  final List<_Linea>? subcards;
  final String? badgeEtiqueta;
  final String? badgeValor;

  bool get esFoto =>
      (fotografia?.isNotEmpty ?? false) ||
      seccion != null &&
          foto != null;
  bool get esSubcard => subcards != null;
  bool get esTitulo => titulo != null;
  bool get esBadge => badgeValor != null;
}

class _LineaWidget extends StatelessWidget {
  final _Linea linea;
  const _LineaWidget({required this.linea});

  @override
  Widget build(BuildContext context) {
    if (linea.esFoto) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Fotografía de respaldo',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            GrillaFotos(
              foto: linea.foto,
              fotografia: linea.fotografia,
              coordenadaLat: linea.coordenadaLat,
              coordenadaLon: linea.coordenadaLon,
              seccion: linea.seccion ?? '',
            ),
          ],
        ),
      );
    }
    if (linea.esSubcard) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < linea.subcards!.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              _LineaWidget(linea: linea.subcards![i]),
            ],
          ],
        ),
      );
    }
    if (linea.esTitulo) {
      return Text(
        linea.titulo!.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: AppColors.textSecondary,
        ),
      );
    }
    if (linea.esBadge) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              linea.badgeEtiqueta ?? '',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary),
            ),
          ),
          Expanded(child: _BadgeChip(texto: linea.badgeValor!)),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            linea.etiqueta ?? '',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary),
          ),
        ),
        Expanded(
          child: Text(
            linea.valor ?? '',
            style:
                const TextStyle(fontSize: 12, color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final String texto;
  const _BadgeChip({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF2563EB),
        ),
      ),
    );
  }
}

class GrillaFotos extends StatelessWidget {
  final EdanFoto? foto;
  final String? fotografia;
  final double coordenadaLat;
  final double coordenadaLon;
  final String seccion;

  const GrillaFotos({
    super.key,
    required this.foto,
    required this.fotografia,
    required this.coordenadaLat,
    required this.coordenadaLon,
    required this.seccion,
  });

  @override
  Widget build(BuildContext context) {
    final conCoords = (coordenadaLat != 0 || coordenadaLon != 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            EdanFotoMiniatura(
              foto: foto,
              fotografia: fotografia,
              width: 72,
              height: 72,
              onTap: () => EdanBotonSacarFoto.verFotoCompleta(
                context,
                fotos: foto != null ? [foto!] : <EdanFoto>[],
                fotografia: fotografia,
                coordenadaLat: coordenadaLat,
                coordenadaLon: coordenadaLon,
                seccion: seccion,
                soloLectura: true,
              ),
            ),
          ],
        ),
        if (conCoords) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.location_on_outlined, size: 12, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                'Lat: ${coordenadaLat.toStringAsFixed(5)} · Lon: ${coordenadaLon.toStringAsFixed(5)}',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
