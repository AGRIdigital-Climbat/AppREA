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

  @override
  State<EdanResumenPage> createState() => _EdanResumenPageState();
}

class _EdanResumenPageState extends State<EdanResumenPage> {
  final Set<String> _expandidas = <String>{'01'};

  EdanLocalidad get _l => widget.localidad;

  @override
  Widget build(BuildContext context) {
    final l = _l;

    final secciones = <_Seccion>[
      _Seccion('01', 'Datos generales', Icons.place_outlined, _completa('01'),
          _datosGenerales(l)),
      _Seccion('02', 'Totales', Icons.people_outline, _completa('02'),
          _totales(l)),
      if (l.impPoblacion)
        _Seccion('03', 'Impacto en la población', Icons.groups_outlined,
            _completa('03'), _impactoPoblacion(l)),
      if (l.impSalud)
        _Seccion('04', 'Impacto en la salud', Icons.local_hospital_outlined,
            _completa('04'), _salud(l)),
      if (l.impInfraestructura)
        _Seccion('05', 'Impacto en infraestructuras', Icons.construction,
            _completa('05'), _infra(l)),
      if (l.impServicios)
        _Seccion('06', 'Impacto en servicios básicos',
            Icons.home_work_outlined, _completa('06'), _servicios(l)),
      if (l.impEducacion)
        _Seccion('07', 'Impacto en educación', Icons.school_outlined,
            _completa('07'), _educacion(l)),
      if (l.impVivienda)
        _Seccion('08', 'Impacto en viviendas', Icons.home_outlined,
            _completa('08'), _vivienda(l)),
      if (l.impAgropecuario)
        _Seccion('09', 'Impacto agropecuario', Icons.agriculture_outlined,
            _completa('09'), _agro(l)),
      if (l.impProteccion)
        _Seccion('10', 'Impacto en protección', Icons.shield_outlined,
            _completa('10'), _proteccion(l)),
      if (l.impNecesidades)
        _Seccion('11', 'Necesidades humanitarias',
            Icons.volunteer_activism_outlined, _completa('11'), _necesidades(l)),
      _Seccion('13', 'Responsable', Icons.badge_outlined, _completa('13'),
          _responsable(l)),
    ];

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
    final ubicacion = [
      l.departamentoNombre ?? '',
      l.provinciaNombre ?? '',
      l.municipioNombre ?? '',
    ].where((e) => e.trim().isNotEmpty).join(', ');
    par('Ubicación', ubicacion);
    par('Fecha de llenado', l.fechaLlenado);
    par('Fecha del evento', _deFechaHora(l.fechaEvento, l.horaEvento));
    par('Tipo de evento', l.tipoEventoNombre);
    return lineas;
  }

  String _deFechaHora(String? fecha, String? hora) {
    final f = (fecha ?? '').trim();
    final h = (hora ?? '').trim();
    if (f.isEmpty) return h;
    if (h.isEmpty) return f;
    return '$f $h';
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
      for (final p in l.impactoPoblacion) {
        final sub = <_Linea>[
          if (p.grupoEtario.trim().isNotEmpty)
            _Linea.par('Rango', p.grupoEtario),
          if (p.fallecidos > 0) _Linea.par('Fallecidos', '${p.fallecidos}'),
          if (p.heridos > 0) _Linea.par('Heridos', '${p.heridos}'),
          if (p.desaparecidos > 0)
            _Linea.par('Desaparecidos', '${p.desaparecidos}'),
          if (p.observaciones.trim().isNotEmpty)
            _Linea.par('Observaciones', p.observaciones),
        ];
        if (sub.isNotEmpty) lineas.add(_Linea.subcard(sub));
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
    return lineas;
  }

  List<_Linea> _vivienda(EdanLocalidad l) {
    final lineas = <_Linea>[];
    for (final v in l.danosVivienda) {
      lineas.add(_Linea.subcard([
        _Linea.par('Localidad',
            v.comunidad.isEmpty ? 'No especificada' : v.comunidad),
        if (v.danoParcial > 0) _Linea.par('Daño parcial', '${v.danoParcial}'),
        if (v.danoTotal > 0) _Linea.par('Daño total', '${v.danoTotal}'),
        if (v.necesidadesInmediatas.trim().isNotEmpty)
          _Linea.par('Necesidades', v.necesidadesInmediatas),
        if (v.observaciones.trim().isNotEmpty)
          _Linea.par('Observaciones', v.observaciones),
        ..._fotoLineas(v, 'Vivienda'),
      ]));
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
    return lineas;
  }

  List<_Linea> _proteccion(EdanLocalidad l) {
    final lineas = <_Linea>[];
    for (final g in l.proteccion) {
      if (!g.tieneDatos) continue;
      lineas.add(_Linea.subcard([
        _Linea.par('Grupo', g.nombreGrupo ?? 'Grupo vulnerable'),
        if (g.mujeres > 0) _Linea.par('N° Mujeres', '${g.mujeres}'),
        if (g.hombres > 0) _Linea.par('N° Hombres', '${g.hombres}'),
        if (g.total > 0) _Linea.par('Total', '${g.total}'),
        if (g.apoyoPsicologico == true)
          _Linea.par('¿Apoyo psicológico?', 'Sí'),
        if (g.reposicionDocumentos == true)
          _Linea.par('¿Reposición de documentos?', 'Sí'),
        if (g.observaciones.trim().isNotEmpty)
          _Linea.par('Observaciones', g.observaciones),
      ]));
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
    return [
      for (final it in items)
        _Linea.par(it.$1,
            it.$2.trim().isNotEmpty ? it.$2 : 'Requiere'),
    ];
  }

  List<_Linea> _responsable(EdanLocalidad l) {
    final r = l.responsable;
    if (r == null) return [];
    return [
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
        subcards = null;
  const _Linea.titulo(this.titulo)
      : seccion = null,
        foto = null,
        fotografia = null,
        coordenadaLat = 0,
        coordenadaLon = 0,
        etiqueta = null,
        valor = null,
        subcards = null;
  const _Linea.subcard(this.subcards)
      : seccion = null,
        foto = null,
        fotografia = null,
        coordenadaLat = 0,
        coordenadaLon = 0,
        etiqueta = null,
        valor = null,
        titulo = null;
  const _Linea.fotos({
    required this.seccion,
    this.foto,
    this.fotografia,
    required this.coordenadaLat,
    required this.coordenadaLon,
  })  : etiqueta = null,
        valor = null,
        titulo = null,
        subcards = null;

  final String? seccion;
  final EdanFoto? foto;
  final String? fotografia;
  final double coordenadaLat;
  final double coordenadaLon;
  final String? etiqueta;
  final String? valor;
  final String? titulo;
  final List<_Linea>? subcards;

  bool get esFoto =>
      (fotografia?.isNotEmpty ?? false) ||
      seccion != null &&
          foto != null;
  bool get esSubcard => subcards != null;
  bool get esTitulo => titulo != null;
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
    return Wrap(
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
    );
  }
}
