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
          _seccion01(),
          _seccion02(),
          _seccion03(),
          _seccion04(),
          _seccion05(),
          _seccion06(),
          _seccion07(),
          _seccion08(),
          _seccion09(),
          _seccion10(),
          _seccion11(),
          _seccion13(),
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
                onPressed: () => _confirmar(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
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

  Widget _seccion01() {
    return _DocSeccion(
      numero: '01',
      titulo: 'Datos Generales',
      children: [
        _dg([
          _df('Alcalde', _v(edan.nombreAlcalde)),
          _df('Fono', _v(edan.fonoAlcalde)),
          _df('Departamento', _v(edan.departamentoNombre)),
          _df('Municipio', _v(edan.municipioNombre)),
          _df('Fecha llenado', _v(edan.fechaLlenado)),
          _df('Fecha evento', _v(edan.fechaEvento)),
          _df('Hora evento', _v(edan.horaEvento)),
          _df('Localidades afectadas',
              edan.localidadesAfectadas > 0 ? '${edan.localidadesAfectadas}' : '-'),
        ]),
        _sh('Localidades (${edan.localidades.length})'),
        if (edan.localidades.isEmpty)
          _vacio()
        else
          ...edan.localidades.asMap().entries.map((entry) {
            final l = entry.value;
            return _tb([
              _tbRow('Tipo', _v(l.tipoLocalidad)),
              _tbRow('Nombre', _v(l.nombre)),
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
    ];
  }

  Widget _seccion02() {
    return _DocSeccion(
      numero: '02',
      titulo: 'Población Afectada y Damnificada',
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

  Widget _seccion03() {
    final locs = edan.localidades.where((l) => l.impPoblacion).toList();
    return _DocSeccion(
      numero: '03',
      titulo: 'Municipio Afectado',
      children: [
        _df('Tipo de evento', _v(edan.tipoEventoNombre)),
        _sh('Impacto en la población'),
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            final ip = l.impactoPoblacion;
            return _bloqueLocalidad(i, l.nombre, [
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
                  ])),
              if (ip.observaciones.trim().isNotEmpty)
                _df('Observaciones', ip.observaciones),
            ]);
          }),
        _sh('Necesidades primera respuesta'),
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final nr = entry.value.necesidadPrimeraRespuesta;
            return _bloqueLocalidad(i, entry.value.nombre, [
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

  Widget _seccion04() {
    final locs = edan.localidades.where((l) => l.impSalud).toList();
    return _DocSeccion(
      numero: '04',
      titulo: 'Salud',
      children: [
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            final ns = l.necesidadSalud;
            return _bloqueLocalidad(i, l.nombre, [
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
              _sh('Necesidades en salud'),
              _tags([if (ns.botiquines) 'Botiquines']),
              if (ns.atencionInmediata > 0)
                _df('Atención inmediata', '${ns.atencionInmediata}'),
              if (ns.otrasNecesidades.trim().isNotEmpty)
                _df('Otras necesidades', ns.otrasNecesidades),
              if (ns.observaciones.trim().isNotEmpty)
                _df('Observaciones', ns.observaciones),
            ]);
          }),
      ],
    );
  }

  Widget _seccion05() {
    final locs = edan.localidades.where((l) => l.impInfraestructura).toList();
    return _DocSeccion(
      numero: '05',
      titulo: 'Infraestructura',
      children: [
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            return _bloqueLocalidad(i, l.nombre, [
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

  Widget _seccion06() {
    final locs = edan.localidades.where((l) => l.impServicios).toList();
    return _DocSeccion(
      numero: '06',
      titulo: 'Servicios Básicos',
      children: [
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            final sb = l.serviciosBasicos;
            return _bloqueLocalidad(i, l.nombre, [
              _tags([
                if (sb.luzElectrica) 'Energía eléctrica',
                if (sb.aguaPotable) 'Agua potable',
                if (sb.alcantarillado) 'Alcantarillado',
                if (sb.gasDomiciliario) 'Gas domiciliario',
                if (sb.telecomunicaciones) 'Telecomunicaciones',
              ]),
              _tags([
                if (sb.danoParcial) 'Daño parcial',
                if (sb.danoTotal) 'Daño total',
              ]),
              if (sb.necesidadesInmediatas.trim().isNotEmpty)
                _df('Necesidades inmediatas', sb.necesidadesInmediatas),
              if (sb.observaciones.trim().isNotEmpty)
                _df('Observaciones', sb.observaciones),
            ]);
          }),
      ],
    );
  }

  Widget _seccion07() {
    final locs = edan.localidades.where((l) => l.impEducacion).toList();
    return _DocSeccion(
      numero: '07',
      titulo: 'Educación',
      children: [
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            final ae = l.afectacionEducativa;
            return _bloqueLocalidad(i, l.nombre, [
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
                        if (u.suspensionClases) 'Suspensión de clases',
                        if (u.perdidaMaterial) 'Pérdida de material',
                        if (u.funcionaAlbergue) 'Funciona como albergue',
                      ]),
                    ])),
              _sh('Afectación educativa'),
              _dg([
                _df('Estudiantes', '${ae.estudiantes}'),
                _df('Profesores', '${ae.profesores}'),
                _df('Administrativos', '${ae.administrativos}'),
                _df('Total', '${ae.totalAfectados}'),
              ]),
              if (ae.observaciones.trim().isNotEmpty)
                _df('Observaciones', ae.observaciones),
            ]);
          }),
      ],
    );
  }

  Widget _seccion08() {
    final locs = edan.localidades.where((l) => l.impVivienda).toList();
    return _DocSeccion(
      numero: '08',
      titulo: 'Vivienda',
      children: [
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            return _bloqueLocalidad(i, l.nombre, [
              if (l.danosVivienda.isEmpty)
                _vacio()
              else
                ...l.danosVivienda.map((v) => _tb([
                      _tbRow('Comunidad', _v(v.comunidad)),
                      _dg([
                        _df('Daño parcial', '${v.danoParcial}'),
                        _df('Daño total', '${v.danoTotal}'),
                      ]),
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

  Widget _seccion09() {
    final locs = edan.localidades.where((l) => l.impAgropecuario).toList();
    return _DocSeccion(
      numero: '09',
      titulo: 'Agropecuario',
      children: [
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            return _bloqueLocalidad(i, l.nombre, [
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
                        if (x.danoParcial) 'Parcial',
                        if (x.danoTotal) 'Total',
                      ]),
                    ])),
            ]);
          }),
      ],
    );
  }

  Widget _seccion10() {
    final locs = edan.localidades.where((l) => l.impProteccion).toList();
    return _DocSeccion(
      numero: '10',
      titulo: 'Protección',
      children: [
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            final p = l.proteccion;
            final v = p.vulnerables;
            return _bloqueLocalidad(i, l.nombre, [
              _sh('Población en situación de mayor vulnerabilidad'),
              _dg([
                _df('Niños', '${v.ninos}'),
                _df('Adolescentes', '${v.adolescentes}'),
                _df('Lactantes', '${v.mujeresLactantes}'),
                _df('Embarazadas', '${v.mujeresEmbarazadas}'),
                _df('Adultos mayores', '${v.adultosMayores}'),
                _df('Discapacidad', '${v.personasDiscapacidad}'),
                _df('Enfermedad', '${v.personasEnfermedad}'),
              ]),
              _sh('Afectación por sexo'),
              _dg([
                _df('Mujeres', '${p.mujeres}'),
                _df('Hombres', '${p.hombres}'),
                _df('Total', '${p.total}'),
              ]),
              if (p.necesidades.trim().isNotEmpty)
                _df('Necesidades de protección', p.necesidades),
              if (p.apoyoPsicosocial.trim().isNotEmpty)
                _df('Apoyo psicosocial', p.apoyoPsicosocial),
              _tags([if (p.reposicionDocumentos) 'Reposición de documentos']),
              if (p.observaciones.trim().isNotEmpty)
                _df('Observaciones', p.observaciones),
            ]);
          }),
      ],
    );
  }

  Widget _seccion11() {
    final nh = edan.necesidadHumanitaria;
    return _DocSeccion(
      numero: '11',
      titulo: 'Necesidades Humanitarias',
      children: [
        _tags([
          if (nh.alimentos) 'Alimentos',
          if (nh.refugioVivienda) 'Refugio / vivienda',
          if (nh.ropaCama) 'Ropa de cama',
          if (nh.articulosHigiene) 'Artículos de higiene',
          if (nh.articulosCocina) 'Artículos de cocina',
          if (nh.prendasVestir) 'Prendas de vestir',
          if (nh.herramientas) 'Herramientas',
          if (nh.almacenamientoAgua) 'Almacenamiento de agua',
          if (nh.banos) 'Baños',
        ]),
        if (nh.observaciones.trim().isNotEmpty)
          _df('Observaciones', nh.observaciones),
      ],
    );
  }

  Widget _seccion13() {
    final r = edan.responsable;
    return _DocSeccion(
      numero: '13',
      titulo: 'Responsable',
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
            'Localidad ${index + 1}${nombre.trim().isNotEmpty ? ' · ${nombre.trim()}' : ''}',
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
  final List<Widget> children;

  const _DocSeccion({
    required this.numero,
    required this.titulo,
    required this.children,
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
        border: Border.all(color: AppColors.divider),
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
                  color: primary,
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
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
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
