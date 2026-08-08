import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../../models/edan.dart';

class UgrEdanPreviewScreen extends StatelessWidget {
  final Edan edan;

  const UgrEdanPreviewScreen({super.key, required this.edan});

  void _confirmar(BuildContext context) {
    edan
      ..estado = 'enviado'
      ..idEstado = 1;
    Navigator.of(context).pop(edan);
  }

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    final incompletos = edan.incompletosPorSeccion;
    final incompletas = incompletos.keys.toSet();
    return Scaffold(
      backgroundColor: PaletteScope.of(context).background,
      appBar: AppBar(
        title: const Text(
          'Vista previa del EDAN',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildDocHeader(primary),
          const SizedBox(height: 16),
          if (incompletos.isNotEmpty) ...[
            _buildBannerIncompleto(incompletos),
            const SizedBox(height: 16),
          ],
          _seccion01(incompletas),
          _seccion02(incompletas),
          _seccion03(incompletas),
          _seccion04(incompletas),
          _seccion05(incompletas),
          _seccion06(incompletas),
          _seccion07(incompletas),
          _seccion08(incompletas),
          _seccion09(incompletas),
          _seccion10(incompletas),
          _seccion11(incompletas),
          _seccion13(incompletas),
          const SizedBox(height: 12),
          _buildDeclaracion(),
          const SizedBox(height: 24),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primary,
                  side: BorderSide(color: primary, width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  minimumSize: const Size(0, 56),
                ),
                child: const Text('Volver y Editar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: incompletos.isEmpty
                    ? () => _confirmar(context)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.divider,
                  disabledForegroundColor: AppColors.textSecondary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  minimumSize: const Size(0, 56),
                ),
                child: const Text('Confirmar y Enviar Evaluación'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBannerIncompleto(Map<String, List<String>> incompletos) {
    final detalle = incompletos.values
        .expand((v) => v)
        .take(3)
        .join(', ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.rechazado.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.rechazado, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 20, color: AppColors.rechazado),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'El EDAN tiene información incompleta. '
              'Complete lo marcado en rojo para poder enviarlo.\n'
              'Falta: $detalle…',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.rechazado,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocHeader(Color primary) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryDark, primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const Text(
            'EVALUACIÓN EDAN',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'SINAGER SAT',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.reaFooterText,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              edan.codigoEdan.isEmpty
                  ? 'EDAN / ${DateTime.now().year}'
                  : edan.codigoEdan,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          if (edan.tipoEventoNombre != null &&
              edan.tipoEventoNombre!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              edan.tipoEventoNombre!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.reaFooterText,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _seccion01(Set<String> incompletas) {
    return _DocSeccion(
      numero: '01',
      titulo: 'Datos generales',
      incompleta: incompletas.contains('01'),
      children: [
        _dg([
          _df('Alcalde', _v(edan.nombreAlcalde)),
          _df('Fono', _v(edan.fonoAlcalde)),
          _df('Departamento', _v(edan.departamentoNombre)),
          _df('Municipio', _v(edan.municipioNombre)),
          _df('Fecha llenado', _v(edan.fechaLlenado)),
          _df('Fecha evento', _v(edan.fechaEvento)),
          _df('Hora evento', _v(edan.horaEvento)),
          _df('Tipo de evento', _v(edan.tipoEventoNombre)),
          _df('Lugares afectados',
              edan.localidadesAfectadas > 0 ? '${edan.localidadesAfectadas}' : '-'),
        ]),
        _sh('Lugares (${edan.localidades.length})'),
        if (edan.localidades.isEmpty)
          _vacio()
        else
          ...edan.localidades.asMap().entries.map((entry) {
            final l = entry.value;
            return _tb([
              _tbRow('Lugar', _v(l.etiquetaLugar)),
              ..._impactosLocalidad(l).isNotEmpty
                  ? [
                      _tbRow('Impactos',
                          _impactosLocalidad(l).join(', ')),
                    ]
                  : [],
            ]);
          }),
      ],
    );
  }

  List<String> _impactosLocalidad(EdanLocalidad l) {
    return [
      if (l.impPoblacion) 'Población',
      if (l.impSalud) 'Salud',
      if (l.impInfraestructura) 'Infraestructura',
      if (l.impServicios) 'Servicios básicos',
      if (l.impEducacion) 'Educación',
      if (l.impVivienda) 'Vivienda',
      if (l.impAgropecuario) 'Agropecuario',
      if (l.impProteccion) 'Protección',
      if (l.impNecesidades) 'Necesidades humanitarias',
    ];
  }

  Widget _seccion02(Set<String> incompletas) {
    return _DocSeccion(
      numero: '02',
      titulo: 'Información total población afectada y damnificada',
      incompleta: incompletas.contains('02'),
      children: [
        _dg([
          _df('Población afectada',
              edan.totalPoblacionAfectada > 0 ? '${edan.totalPoblacionAfectada}' : '0'),
          _df('Familias afectadas',
              edan.totalFamiliasAfectadas > 0 ? '${edan.totalFamiliasAfectadas}' : '0'),
          _df('Familias damnificadas',
              edan.totalFamiliasDamnificadas > 0 ? '${edan.totalFamiliasDamnificadas}' : '0'),
        ]),
      ],
    );
  }

  Widget _seccion03(Set<String> incompletas) {
    final locs = edan.localidades.where((l) => l.impPoblacion).toList();
    return _DocSeccion(
      numero: '03',
      titulo: 'Impacto en la población',
      incompleta: incompletas.contains('03'),
      children: [
        _sh('Impacto en la población'),
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            final ip = l.impactoPoblacion;
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              _dg([
                _df('Fallecidos', '${ip.fallecidos}'),
                _df('Heridos', '${ip.heridos}'),
                _df('Desaparecidos', '${ip.desaparecidos}'),
              ]),
              ...ip.gruposEtarios.map((g) => _tb([
                    _tbRow('Grupo etario', _v(g.rango)),
                    _tbRow('Fallecidos', '${g.fallecidos}'),
                    _tbRow('Heridos', '${g.heridos}'),
                    _tbRow('Desaparecidos', '${g.desaparecidos}'),
                    if (g.observaciones.trim().isNotEmpty)
                      _tbRow('Observaciones', _v(g.observaciones)),
                  ])),
            ]);
          }),
        _sh('Necesidades primera respuesta'),
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final nr = entry.value.necesidadPrimeraRespuesta;
            return _bloqueLocalidad(i, entry.value.etiquetaLugar, [
              _tags([
                if (nr.busqueda) 'Búsqueda',
                if (nr.salvamento) 'Salvamento',
                if (nr.evacuacion) 'Evacuación',
              ]),
              if (nr.observaciones.trim().isNotEmpty)
                _df('Observaciones', nr.observaciones),
            ]);
          }),
      ],
    );
  }

  bool get _aplicaNecesidadesSalud {
    final t = (edan.tipoEventoNombre ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
    return t.contains('incendio') ||
        t.contains('inundacion') ||
        t.contains('sequia');
  }

  Widget _seccion04(Set<String> incompletas) {
    final locs = edan.localidades.where((l) => l.impSalud).toList();
    return _DocSeccion(
      numero: '04',
      titulo: 'Impacto en la salud',
      incompleta: incompletas.contains('04'),
      children: [
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            final ns = l.necesidadSalud;
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              _sh('Daños en servicios de salud (${l.establecimientosSalud.length})'),
              if (l.establecimientosSalud.isEmpty)
                _vacio()
              else
                ...l.establecimientosSalud.map((s) => _tb([
                      _tbRow('Nombre', _v(s.nombreEstablecimiento)),
                      _tbRow('Comunidad', _v(s.comunidad)),
                      _tbRow('Nivel', _v(s.nivelAtencion)),
                      _tags([
                        if (s.danoParcial) 'Daño parcial',
                        if (s.danoTotal) 'Daño total',
                      ]),
                      _tbRow('Médicos', '${s.medicosAfectados}'),
                      _tbRow('Enfermeras', '${s.enfermerasAfectados}'),
                      _tbRow('Otros', '${s.otrosAfectados}'),
                    ])),
              if (_aplicaNecesidadesSalud) ...[
                _sh('Necesidades en salud'),
                _tags([if (ns.botiquines) 'Botiquín']),
                if (ns.numeroPersonas > 0)
                  _df('Número de personas (atención inmediata)',
                      '${ns.numeroPersonas}'),
                if (ns.otrasNecesidades.trim().isNotEmpty)
                  _df('Otras necesidades', ns.otrasNecesidades),
                if (ns.observaciones.trim().isNotEmpty)
                  _df('Observaciones', ns.observaciones),
              ],
            ]);
          }),
      ],
    );
  }

  Widget _seccion05(Set<String> incompletas) {
    final locs = edan.localidades.where((l) => l.impInfraestructura).toList();
    return _DocSeccion(
      numero: '05',
      titulo: 'Impacto en infraestructuras',
      incompleta: incompletas.contains('05'),
      children: [
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              _sh('Vías y puentes (${l.danosViales.length})'),
              if (l.danosViales.isEmpty)
                _vacio()
              else
                ...l.danosViales.map((d) => _tb([
                      _tbRow('Vía', _v(d.viaPuente)),
                      _tbRow('Tramo', _v(d.tramo)),
                      _tags([
                        if (d.danoParcial) 'Parcial',
                        if (d.danoTotal) 'Total',
                      ]),
                      if (d.kmDanio > 0)
                        _tbRow('Km dañados',
                            '${d.kmDanio == d.kmDanio.roundToDouble() ? d.kmDanio.toInt() : d.kmDanio}'),
                    ])),
              _sh('Infraestructura pública (${l.danosInfraPublica.length})'),
              if (l.danosInfraPublica.isEmpty)
                _vacio()
              else
                ...l.danosInfraPublica.map((d) => _tb([
                      _tbRow('Comunidad', _v(d.comunidad)),
                      _tbRow('Tipo', _v(d.tipoEstructura)),
                      _tags([
                        if (d.danoParcial) 'Parcial',
                        if (d.danoTotal) 'Total',
                      ]),
                    ])),
            ]);
          }),
      ],
    );
  }

  Widget _seccion06(Set<String> incompletas) {
    final locs = edan.localidades.where((l) => l.impServicios).toList();
    return _DocSeccion(
      numero: '06',
      titulo: 'Impacto en servicios básicos',
      incompleta: incompletas.contains('06'),
      children: [
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            final afectados =
                l.serviciosBasicos.servicios.where((s) => s.tieneDatos).toList();
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              if (afectados.isEmpty)
                _vacio()
              else
                ...afectados.map((s) => _tb([
                      _tbRow('Servicio', s.etiqueta),
                      _tags([
                        if (s.danoParcial) 'Parcial',
                        if (s.danoTotal) 'Total',
                      ]),
                      if (s.necesidadesInmediatas.trim().isNotEmpty)
                        _tbRow('Necesidades inmediatas',
                            _v(s.necesidadesInmediatas)),
                      if (s.observaciones.trim().isNotEmpty)
                        _tbRow('Observaciones', _v(s.observaciones)),
                    ])),
            ]);
          }),
      ],
    );
  }

  Widget _seccion07(Set<String> incompletas) {
    final locs = edan.localidades.where((l) => l.impEducacion).toList();
    return _DocSeccion(
      numero: '07',
      titulo: 'Impacto en educación',
      incompleta: incompletas.contains('07'),
      children: [
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              _sh('Unidades educativas (${l.unidadesEducativas.length})'),
              if (l.unidadesEducativas.isEmpty)
                _vacio()
              else
                ...l.unidadesEducativas.map((u) => _tb([
                      _tbRow('Nombre', _v(u.nombreEstablecimiento)),
                      _tbRow('Comunidad', _v(u.comunidad)),
                      _tags([
                        if (u.danoParcial) 'Parcial',
                        if (u.danoTotal) 'Total',
                        if (u.suspensionClases == true) 'Suspensión de clases',
                        if (u.perdidaMaterial == true) 'Pérdida de material educativo',
                        if (u.funcionaAlbergue == true) 'Funciona como albergue',
                      ]),
                      if (u.estudiantes > 0 ||
                          u.profesores > 0 ||
                          u.administrativos > 0) ...[
                        _tbRow('Estudiantes', '${u.estudiantes}'),
                        _tbRow('Profesores', '${u.profesores}'),
                        _tbRow('Administrativos', '${u.administrativos}'),
                        _tbRow('Total afectados', '${u.totalAfectados}'),
                      ],
                      if (u.observaciones.trim().isNotEmpty)
                        _tbRow('Observaciones', _v(u.observaciones)),
                    ])),
            ]);
          }),
      ],
    );
  }

  Widget _seccion08(Set<String> incompletas) {
    final locs = edan.localidades.where((l) => l.impVivienda).toList();
    return _DocSeccion(
      numero: '08',
      titulo: 'Impacto en viviendas',
      incompleta: incompletas.contains('08'),
      children: [
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              if (l.danosVivienda.isEmpty)
                _vacio()
              else
                ...l.danosVivienda.map((v) => _tb([
                      _tbRow('Comunidad', _v(v.comunidad)),
                      _tags([
                        if (v.danoParcial > 0) 'Parcial',
                        if (v.danoTotal > 0) 'Total',
                      ]),
                      if (v.danoParcial > 0)
                        _tbRow('Nº de viviendas', '${v.danoParcial}')
                      else if (v.danoTotal > 0)
                        _tbRow('Nº de viviendas', '${v.danoTotal}'),
                      if (v.necesidadesInmediatas.trim().isNotEmpty)
                        _tbRow('Necesidades inmediatas', v.necesidadesInmediatas),
                      if (v.observaciones.trim().isNotEmpty)
                        _tbRow('Observaciones', v.observaciones),
                    ])),
            ]);
          }),
      ],
    );
  }

  Widget _seccion09(Set<String> incompletas) {
    final locs = edan.localidades.where((l) => l.impAgropecuario).toList();
    return _DocSeccion(
      numero: '09',
      titulo: 'Impacto agropecuario',
      incompleta: incompletas.contains('09'),
      children: [
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              _sh('Daños en agricultura'),
              if (l.danosAgricultura.isEmpty)
                _vacio()
              else
                ...l.danosAgricultura.map((a) => _tb([
                      _tbRow('Cultivo', _v(a.tipoCultivo)),
                      _dg([
                        _df('Has afectadas', '${a.hectareasAfectadas}'),
                        _df('Has perdidas', '${a.hectareasPerdidas}'),
                      ]),
                      if (a.necesidadesInmediatas.trim().isNotEmpty)
                        _tbRow('Necesidades', a.necesidadesInmediatas),
                    ])),
              _sh('Daños pecuarios'),
              if (l.danosPecuarios.isEmpty)
                _vacio()
              else
                ...l.danosPecuarios.map((p) => _tb([
                      _tbRow('Especie', _v(p.especie)),
                      _tbRow('Raza', _v(p.raza)),
                      _dg([
                        _df('Afectados', '${p.animalesAfectados}'),
                        _df('Muertos', '${p.animalesMuertos}'),
                      ]),
                    ])),
              _sh('Infraestructura productiva'),
              if (l.infraProductiva.isEmpty)
                _vacio()
              else
                ...l.infraProductiva.map((x) => _tb([
                      _tbRow('Tipo', _v(x.tipo)),
                      _tags([
                        if (x.danoParcial > 0) 'Parcial',
                        if (x.danoTotal > 0) 'Total',
                      ]),
                      if (x.danoParcial > 0)
                        _tbRow('Nº de infraestructuras afectadas',
                            '${x.danoParcial}')
                      else if (x.danoTotal > 0)
                        _tbRow('Nº de infraestructuras afectadas',
                            '${x.danoTotal}'),
                    ])),
            ]);
          }),
      ],
    );
  }

  Widget _seccion10(Set<String> incompletas) {
    final locs = edan.localidades.where((l) => l.impProteccion).toList();
    return _DocSeccion(
      numero: '10',
      titulo: 'Impacto en protección',
      incompleta: incompletas.contains('10'),
      children: [
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              ..._filasProteccion(l.proteccion.vulnerables),
            ]);
          }),
      ],
    );
  }

  List<Widget> _filasProteccion(EdanVulnerables v) {
    final grupos = <(String, EdanGrupoVulnerable)>[
      ('Niñas y niños', v.ninos),
      ('Adolescentes', v.adolescentes),
      ('Mujeres lactantes', v.mujeresLactantes),
      ('Mujeres embarazadas', v.mujeresEmbarazadas),
      ('Adultos mayores', v.adultosMayores),
      ('Personas con discapacidad', v.personasDiscapacidad),
      ('Personas con enfermedad crónica', v.personasEnfermedad),
    ];
    return [
      for (final g in grupos)
        if (g.$2.tieneDatos)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _tb([
              _tbRow('Grupo', g.$1),
              _dg([
                _df('Mujeres', '${g.$2.mujeres}'),
                _df('Hombres', '${g.$2.hombres}'),
                _df('Total', '${g.$2.total}'),
              ]),
              _tags([
                if (g.$2.apoyoPsicologico == true) 'Apoyo psicológico',
                if (g.$2.reposicionDocumentos == true) 'Reposición de documento',
              ]),
              if (g.$2.observaciones.trim().isNotEmpty)
                _tbRow('Observaciones', g.$2.observaciones),
            ]),
          ),
    ];
  }

  Widget _seccion11(Set<String> incompletas) {
    final locs = edan.localidades.where((l) => l.impNecesidades).toList();
    return _DocSeccion(
      numero: '11',
      titulo: 'Necesidades humanitarias',
      incompleta: incompletas.contains('11'),
      children: [
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            final n = l.necesidadHumanitaria;
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              _tags([
                if (n.alimentos) 'Alimentos',
                if (n.refugioVivienda) 'Refugio / vivienda',
                if (n.ropaCama) 'Ropa de cama',
                if (n.articulosHigiene) 'Artículos de higiene',
                if (n.articulosCocina) 'Artículos de cocina',
                if (n.prendasVestir) 'Prendas de vestir',
                if (n.herramientas) 'Herramientas',
                if (n.almacenamientoAgua) 'Almacenamiento de agua',
                if (n.banos) 'Baños',
              ]),
              if (n.obsAlimentos.trim().isNotEmpty)
                _df('Observaciones · Alimentos', n.obsAlimentos),
              if (n.obsRefugioVivienda.trim().isNotEmpty)
                _df('Observaciones · Refugio / vivienda', n.obsRefugioVivienda),
              if (n.obsRopaCama.trim().isNotEmpty)
                _df('Observaciones · Ropa de cama', n.obsRopaCama),
              if (n.obsArticulosHigiene.trim().isNotEmpty)
                _df('Observaciones · Artículos de higiene', n.obsArticulosHigiene),
              if (n.obsArticulosCocina.trim().isNotEmpty)
                _df('Observaciones · Artículos de cocina', n.obsArticulosCocina),
              if (n.obsPrendasVestir.trim().isNotEmpty)
                _df('Observaciones · Prendas de vestir', n.obsPrendasVestir),
              if (n.obsHerramientas.trim().isNotEmpty)
                _df('Observaciones · Herramientas', n.obsHerramientas),
              if (n.obsAlmacenamientoAgua.trim().isNotEmpty)
                _df('Observaciones · Almacenamiento de agua', n.obsAlmacenamientoAgua),
              if (n.obsBanos.trim().isNotEmpty)
                _df('Observaciones · Baños', n.obsBanos),
            ]);
          }),
      ],
    );
  }

  Widget _seccion13(Set<String> incompletas) {
    final r = edan.responsable;
    return _DocSeccion(
      numero: '13',
      titulo: 'Responsable',
      incompleta: incompletas.contains('13'),
      children: [
        _dg([
          _df('Nombre', _v(r.nombre)),
          _df('Cargo', _v(r.cargo)),
          _df('Fono', _v(r.fono)),
          _df('Correo', _v(r.correo)),
        ]),
      ],
    );
  }

  Widget _buildDeclaracion() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.pending.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.pending.withValues(alpha: 0.3)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, color: AppColors.pending, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Declaración jurada: La información presentada en este '
              'formulario EDAN tiene carácter de declaración jurada. La '
              'información proporcionada debe ser correcta y será verificada '
              'por las autoridades correspondientes.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _v(String? s) => (s == null || s.trim().isEmpty) ? '-' : s;

  Widget _vacio() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Text(
        'Sin registros.',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _df(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _dg(List<Widget> fields) {
    return Wrap(
      spacing: 20,
      runSpacing: 10,
      children: fields,
    );
  }

  Widget _tbRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tb(List<Widget> rows) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }

  Widget _bloqueLocalidad(int index, String nombre, List<Widget> children) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lugar ${index + 1}${nombre.trim().isNotEmpty ? ' · ${nombre.trim()}' : ''}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _tags(List<String> tags) {
    if (tags.isEmpty) return _vacio();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: tags
            .map((t) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    t,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _sh(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _DocSeccion extends StatelessWidget {
  final String numero;
  final String titulo;
  final bool incompleta;
  final List<Widget> children;

  const _DocSeccion({
    required this.numero,
    required this.titulo,
    required this.children,
    this.incompleta = false,
  });

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: incompleta ? AppColors.rechazado : AppColors.divider,
          width: incompleta ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: incompleta ? AppColors.rechazado : primary,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    numero,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (incompleta) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.rechazado.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.rechazado,
                            width: 1,
                          ),
                        ),
                        child: const Text(
                          'Incompleto',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.rechazado,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}
