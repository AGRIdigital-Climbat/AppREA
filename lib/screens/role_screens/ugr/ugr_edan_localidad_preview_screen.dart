import 'dart:io';

import 'package:flutter/material.dart';
import '../../../config/api_config.dart';
import '../../../config/theme.dart';
import '../../../models/edan.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/connectivity_service.dart';

class UgrEdanLocalidadPreviewScreen extends StatefulWidget {
  final EdanLocalidad localidad;

  const UgrEdanLocalidadPreviewScreen({
    super.key,
    required this.localidad,
  });

  @override
  State<UgrEdanLocalidadPreviewScreen> createState() =>
      _UgrEdanLocalidadPreviewScreenState();
}

class _UgrEdanLocalidadPreviewScreenState
    extends State<UgrEdanLocalidadPreviewScreen> {
  bool _procesando = false;

  EdanLocalidad get localidad => widget.localidad;

  bool get _puedeActuar =>
      localidad.estadoLocalidad == UgrLocalidadEstado.enRevisionUgr &&
      localidad.idServer != null;

  void _mostrarConfirmacion(String accion, Color color, VoidCallback onConfirmar) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          accion == 'Aprobar' ? Icons.check_circle : Icons.cancel,
          color: color,
          size: 48,
        ),
        title: Text('$accion localidad'),
        content: Text(
          '¿Estás seguro de que deseas $accion esta localidad?',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onConfirmar();
            },
            style: TextButton.styleFrom(foregroundColor: color),
            child: Text(accion),
          ),
        ],
      ),
    );
  }

  Future<void> _aprobar() async {
    if (!ConnectivityService().isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sin conexión. Verifica tu red y reintenta.'),
            backgroundColor: AppColors.pending,
          ),
        );
      }
      return;
    }
    setState(() => _procesando = true);
    try {
      await ApiService.instance.cambiarEstadoLocalidad(
        localidad.idServer!,
        UgrLocalidadEstado.aprobadoUgr.id,
      );
      localidad.estadoLocalidad = UgrLocalidadEstado.aprobadoUgr;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Localidad aprobada'),
            backgroundColor: AppColors.aprobado,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${ApiService.traducirError(e)}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _rechazar() async {
    if (!ConnectivityService().isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sin conexión. Verifica tu red y reintenta.'),
            backgroundColor: AppColors.pending,
          ),
        );
      }
      return;
    }
    setState(() => _procesando = true);
    try {
      await ApiService.instance.cambiarEstadoLocalidad(
        localidad.idServer!,
        UgrLocalidadEstado.rechazadoUgr.id,
      );
      localidad.estadoLocalidad = UgrLocalidadEstado.rechazadoUgr;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Localidad rechazada'),
            backgroundColor: AppColors.rechazado,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${ApiService.traducirError(e)}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    localidad.deduplicarSecciones();

    final seccionesVisibles = <String>{
      '01',
      '13',
      if (localidad.impPoblacion) '03',
      if (localidad.impSalud) '04',
      if (localidad.impInfraestructura) '05',
      if (localidad.impServicios) '06',
      if (localidad.impEducacion) '07',
      if (localidad.impVivienda) '08',
      if (localidad.impAgropecuario) '09',
      if (localidad.impProteccion) '10',
      if (localidad.impNecesidades) '11',
    };

    return Scaffold(
      backgroundColor: PaletteScope.of(context).background,
      appBar: AppBar(
        title: const Text(
          'Vista previa del reporte',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildDocHeader(primary),
          const SizedBox(height: 16),
          if (seccionesVisibles.contains('01')) _seccion01(),
          _seccion02(),
          if (seccionesVisibles.contains('03')) _seccion03(),
          if (seccionesVisibles.contains('04')) _seccion04(),
          if (seccionesVisibles.contains('05')) _seccion05(),
          if (seccionesVisibles.contains('06')) _seccion06(),
          if (seccionesVisibles.contains('07')) _seccion07(),
          if (seccionesVisibles.contains('08')) _seccion08(),
          if (seccionesVisibles.contains('09')) _seccion09(),
          if (seccionesVisibles.contains('10')) _seccion10(),
          if (seccionesVisibles.contains('11')) _seccion11(),
          if (seccionesVisibles.contains('13')) _seccion13(),
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
        child: _puedeActuar
            ? Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _procesando ? null : () => _mostrarConfirmacion('Rechazar', AppColors.rechazado, _rechazar),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.rechazado,
                        side: const BorderSide(color: AppColors.rechazado),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        minimumSize: const Size(0, 56),
                      ),
                      child: _procesando
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.rechazado))
                          : const Text('Rechazar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _procesando ? null : () => _mostrarConfirmacion('Aprobar', AppColors.aprobado, _aprobar),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.aprobado,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        minimumSize: const Size(0, 56),
                      ),
                      child: _procesando
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Aprobar'),
                    ),
                  ),
                ],
              )
            : SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size(0, 56),
                  ),
                  child: const Text('Cerrar'),
                ),
              ),
      ),
    );
  }

  Widget _buildDocHeader(Color primary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
            'SINAGER-SAT',
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
              localidad.idEdan != null ? 'EDAN / ${localidad.idEdan}' : 'Reporte local',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          if (localidad.tipoEventoNombre != null &&
              localidad.tipoEventoNombre!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              localidad.tipoEventoNombre!,
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
      titulo: 'Datos generales',
      children: [
        _dg([
          _df('Departamento', _v(localidad.departamentoNombre)),
          _df('Provincia', _v(localidad.provinciaNombre)),
          _df('Municipio', _v(localidad.municipioNombre)),
          _df('Localidad', _v(localidad.nombre)),
          _df('Tipo localidad', _v(localidad.tipoLocalidad)),
          _df('Fecha llenado', _v(localidad.fechaLlenado)),
          _df('Fecha evento', _v(localidad.fechaEvento)),
          _df('Hora evento', _v(localidad.horaEvento)),
          _df('Tipo de evento', _v(localidad.tipoEventoNombre)),
        ]),
        _sh('Impactos'),
        _tags(_impactosLocalidad()),
      ],
    );
  }

  List<String> _impactosLocalidad() {
    return [
      if (localidad.impPoblacion) 'Población',
      if (localidad.impSalud) 'Salud',
      if (localidad.impInfraestructura) 'Infraestructura',
      if (localidad.impServicios) 'Servicios básicos',
      if (localidad.impEducacion) 'Educación',
      if (localidad.impVivienda) 'Vivienda',
      if (localidad.impAgropecuario) 'Agropecuario',
      if (localidad.impProteccion) 'Protección',
      if (localidad.impNecesidades) 'Necesidades humanitarias',
    ];
  }

  Widget _seccion02() {
    return _DocSeccion(
      numero: '02',
      titulo: 'Información total población afectada y damnificada',
      children: [
        _dg([
          _df('Población afectada',
              localidad.totalPoblacionAfectada > 0 ? '${localidad.totalPoblacionAfectada}' : '0'),
          _df('Familias afectadas',
              localidad.totalFamiliasAfectadas > 0 ? '${localidad.totalFamiliasAfectadas}' : '0'),
          _df('Familias damnificadas',
              localidad.totalFamiliasDamnificadas > 0 ? '${localidad.totalFamiliasDamnificadas}' : '0'),
        ]),
      ],
    );
  }

  Widget _seccion03() {
    final ip = localidad.impactoPoblacion.isNotEmpty ? localidad.impactoPoblacion[0] : null;
    return _DocSeccion(
      numero: '03',
      titulo: 'Impacto en la población',
      children: [
        _sh('Impacto en la población'),
        _tb([
          if (ip != null) ...[
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
          ] else
            _vacio(),
        ]),
        _sh('Necesidades primera respuesta'),
        _tb([
          _tags([
            if (localidad.necesidadPrimeraRespuesta?.busqueda ?? false) 'Búsqueda',
            if (localidad.necesidadPrimeraRespuesta?.salvamento ?? false) 'Salvamento',
            if (localidad.necesidadPrimeraRespuesta?.evacuacion ?? false) 'Evacuación',
          ]),
          if (localidad.necesidadPrimeraRespuesta?.observaciones != null &&
              localidad.necesidadPrimeraRespuesta!.observaciones.trim().isNotEmpty)
            _df('Observaciones', localidad.necesidadPrimeraRespuesta!.observaciones),
        ]),
      ],
    );
  }

  bool get _aplicaNecesidadesSalud {
    final t = (localidad.tipoEventoNombre ?? '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[áÁ]'), 'a')
        .replaceAll(RegExp(r'[éÉ]'), 'e')
        .replaceAll(RegExp(r'[íÍ]'), 'i')
        .replaceAll(RegExp(r'[óÓ]'), 'o')
        .replaceAll(RegExp(r'[úÚ]'), 'u');
    return t.contains('incendio') || t.contains('inundacion') || t.contains('sequia');
  }

  Widget _seccion04() {
    final ns = localidad.necesidadSalud;
    return _DocSeccion(
      numero: '04',
      titulo: 'Impacto en la salud',
      children: [
        _sh('Daños en servicios de salud (${localidad.establecimientosSalud.length})'),
        if (localidad.establecimientosSalud.isEmpty)
          _vacio()
        else
          ...localidad.establecimientosSalud.map((s) => _tb([
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
                _FotosDe(
                  fotos: s.fotos,
                  servidor: s.fotografia,
                  coordenadaLat: s.coordenadaLat,
                  coordenadaLon: s.coordenadaLon,
                  seccion: 'Salud',
                ),
              ])),
        if (_aplicaNecesidadesSalud) ...[
          _sh('Necesidades en salud'),
          _tags([if (ns?.botiquines ?? false) 'Botiquín']),
          if ((ns?.numeroPersonas ?? 0) > 0)
            _df('Número de personas (atención inmediata)', '${ns?.numeroPersonas ?? 0}'),
          if (ns?.otrasNecesidades != null && ns!.otrasNecesidades.trim().isNotEmpty)
            _df('Otras necesidades', ns.otrasNecesidades),
          if (ns?.observaciones != null && ns!.observaciones.trim().isNotEmpty)
            _df('Observaciones', ns.observaciones),
        ],
      ],
    );
  }

  Widget _seccion05() {
    return _DocSeccion(
      numero: '05',
      titulo: 'Impacto en infraestructuras',
      children: [
        _sh('Vías y puentes (${localidad.danosViales.length})'),
        if (localidad.danosViales.isEmpty)
          _vacio()
        else
          ...localidad.danosViales.map((d) => _tb([
                _tbRow('Vía', _v(d.viaPuente)),
                _tbRow('Tramo', _v(d.tramo)),
                _tags([
                  if (d.danoParcial) 'Parcial',
                  if (d.danoTotal) 'Total',
                ]),
                if (d.kmDanio > 0)
                  _tbRow('Km dañados',
                      '${d.kmDanio == d.kmDanio.roundToDouble() ? d.kmDanio.toInt() : d.kmDanio}'),
                _FotosDe(
                  fotos: d.fotos,
                  servidor: d.fotografia,
                  coordenadaLat: d.coordenadaLat,
                  coordenadaLon: d.coordenadaLon,
                  seccion: 'Vías y puentes',
                ),
              ])),
        _sh('Infraestructura pública (${localidad.danosInfraPublica.length})'),
        if (localidad.danosInfraPublica.isEmpty)
          _vacio()
        else
          ...localidad.danosInfraPublica.map((d) => _tb([
                _tbRow('Comunidad', _v(d.comunidad)),
                _tbRow('Tipo', _v(d.tipoEstructura)),
                _tags([
                  if (d.danoParcial) 'Parcial',
                  if (d.danoTotal) 'Total',
                ]),
                _FotosDe(
                  fotos: d.fotos,
                  servidor: d.fotografia,
                  coordenadaLat: d.coordenadaLat,
                  coordenadaLon: d.coordenadaLon,
                  seccion: 'Infraestructura pública',
                ),
              ])),
      ],
    );
  }

  Widget _seccion06() {
    return _DocSeccion(
      numero: '06',
      titulo: 'Impacto en servicios básicos',
      children: [
        if (localidad.serviciosBasicos.isEmpty)
          _vacio()
        else
          ...localidad.serviciosBasicos.map((s) => _tb([
                _tbRow('Servicio', s.etiqueta),
                _tags([
                  if (s.danoParcial) 'Parcial',
                  if (s.danoTotal) 'Total',
                ]),
                if (s.necesidadesInmediatas.trim().isNotEmpty)
                  _tbRow('Necesidades inmediatas', _v(s.necesidadesInmediatas)),
                if (s.observaciones.trim().isNotEmpty)
                  _tbRow('Observaciones', _v(s.observaciones)),
              ])),
      ],
    );
  }

  Widget _seccion07() {
    return _DocSeccion(
      numero: '07',
      titulo: 'Impacto en educación',
      children: [
        _sh('Unidades educativas (${localidad.unidadesEducativas.length})'),
        if (localidad.unidadesEducativas.isEmpty)
          _vacio()
        else
          ...localidad.unidadesEducativas.map((u) => _tb([
                _tbRow('Nombre', _v(u.nombreEstablecimiento)),
                _tbRow('Comunidad', _v(u.comunidad)),
                _tags([
                  if (u.danoParcial) 'Parcial',
                  if (u.danoTotal) 'Total',
                  if (u.suspensionClases == true) 'Suspensión de clases',
                  if (u.perdidaMaterial == true) 'Pérdida de material educativo',
                  if (u.funcionaAlbergue == true) 'Funciona como albergue',
                ]),
                if (u.estudiantes > 0 || u.profesores > 0 || u.administrativos > 0) ...[
                  _tbRow('Estudiantes', '${u.estudiantes}'),
                  _tbRow('Profesores', '${u.profesores}'),
                  _tbRow('Administrativos', '${u.administrativos}'),
                  _tbRow('Total afectados', '${u.totalAfectados}'),
                ],
                if (u.observaciones.trim().isNotEmpty)
                  _tbRow('Observaciones', _v(u.observaciones)),
                _FotosDe(
                  fotos: u.fotos,
                  servidor: u.fotografia,
                  coordenadaLat: u.coordenadaLat,
                  coordenadaLon: u.coordenadaLon,
                  seccion: 'Educación',
                ),
              ])),
      ],
    );
  }

  Widget _seccion08() {
    return _DocSeccion(
      numero: '08',
      titulo: 'Impacto en viviendas',
      children: [
        if (localidad.danosVivienda.isEmpty)
          _vacio()
        else
          ...localidad.danosVivienda.map((v) => _tb([
                _tbRow('Comunidad', _v(v.comunidad)),
                _tags([
                  if (v.danoParcial > 0) 'Parcial',
                  if (v.danoTotal > 0) 'Total',
                ]),
                if (v.danoParcial > 0)
                  _tbRow('Parcial', '${v.danoParcial} viviendas'),
                if (v.danoTotal > 0)
                  _tbRow('Total', '${v.danoTotal} viviendas'),
                if (v.necesidadesInmediatas.trim().isNotEmpty)
                  _tbRow('Necesidades inmediatas', v.necesidadesInmediatas),
                if (v.observaciones.trim().isNotEmpty)
                  _tbRow('Observaciones', v.observaciones),
                _FotosDe(
                  fotos: v.fotos,
                  servidor: v.fotografia,
                  coordenadaLat: v.coordenadaLat,
                  coordenadaLon: v.coordenadaLon,
                  seccion: 'Viviendas',
                ),
              ])),
      ],
    );
  }

  Widget _seccion09() {
    return _DocSeccion(
      numero: '09',
      titulo: 'Impacto agropecuario',
      children: [
        _sh('Daños en agricultura'),
        if (localidad.danosAgricultura.isEmpty)
          _vacio()
        else
          ...localidad.danosAgricultura.map((a) => _tb([
                _tbRow('Cultivo', _v(a.tipoCultivo)),
                _dg([
                  _df('Has afectadas', '${a.hectareasAfectadas}'),
                  _df('Has perdidas', '${a.hectareasPerdidas}'),
                ]),
                if (a.necesidadesInmediatas.trim().isNotEmpty)
                  _tbRow('Necesidades', a.necesidadesInmediatas),
                _FotosDe(
                  fotos: a.fotos,
                  servidor: a.fotografia,
                  coordenadaLat: a.coordenadaLat,
                  coordenadaLon: a.coordenadaLon,
                  seccion: 'Agricultura',
                ),
              ])),
        _sh('Daños pecuarios'),
        if (localidad.danosPecuarios.isEmpty)
          _vacio()
        else
          ...localidad.danosPecuarios.map((p) => _tb([
                _tbRow('Especie', _v(p.especie)),
                _tbRow('Raza', _v(p.raza)),
                _dg([
                  _df('Afectados', '${p.animalesAfectados}'),
                  _df('Muertos', '${p.animalesMuertos}'),
                ]),
                _FotosDe(
                  fotos: p.fotos,
                  servidor: p.fotografia,
                  coordenadaLat: p.coordenadaLat,
                  coordenadaLon: p.coordenadaLon,
                  seccion: 'Pecuarios',
                ),
              ])),
        _sh('Infraestructura productiva'),
        if (localidad.infraProductiva.isEmpty)
          _vacio()
        else
          ...localidad.infraProductiva.map((x) => _tb([
                _tbRow('Tipo', _v(x.tipo)),
                _tags([
                  if (x.danoParcial > 0) 'Parcial',
                  if (x.danoTotal > 0) 'Total',
                ]),
                if (x.danoParcial > 0)
                  _tbRow('Parcial', '${x.danoParcial} infraestructuras'),
                if (x.danoTotal > 0)
                  _tbRow('Total', '${x.danoTotal} infraestructuras'),
                _FotosDe(
                  fotos: x.fotos,
                  servidor: x.fotografia,
                  coordenadaLat: x.coordenadaLat,
                  coordenadaLon: x.coordenadaLon,
                  seccion: 'Infraestructura productiva',
                ),
              ])),
      ],
    );
  }

  Widget _seccion10() {
    return _DocSeccion(
      numero: '10',
      titulo: 'Impacto en protección',
      children: [
        ..._filasProteccion(localidad.proteccion),
      ],
    );
  }

  List<Widget> _filasProteccion(List<EdanGrupoVulnerable> grupos) {
    final conDatos = grupos.where((g) => g.tieneDatos).toList();
    if (conDatos.isEmpty) return [_vacio()];
    return [
      for (var i = 0; i < conDatos.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _tb([
            _tbRow('Grupo', conDatos[i].nombreGrupo ?? 'Grupo ${i + 1}'),
            _dg([
              _df('Mujeres', '${conDatos[i].mujeres}'),
              _df('Hombres', '${conDatos[i].hombres}'),
              _df('Total', '${conDatos[i].total}'),
            ]),
            _tags([
              if (conDatos[i].apoyoPsicologico == true) 'Apoyo psicológico',
              if (conDatos[i].reposicionDocumentos == true) 'Reposición de documento',
            ]),
            if (conDatos[i].observaciones.trim().isNotEmpty)
              _tbRow('Observaciones', conDatos[i].observaciones),
          ]),
        ),
    ];
  }

  Widget _seccion11() {
    final n = localidad.necesidadHumanitaria ?? EdanNecesidadHumanitaria();
    return _DocSeccion(
      numero: '11',
      titulo: 'Necesidades humanitarias',
      children: [
        _tb([
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
          if (n.obsAlimentos.trim().isNotEmpty) _df('Observaciones · Alimentos', n.obsAlimentos),
          if (n.obsRefugioVivienda.trim().isNotEmpty) _df('Observaciones · Refugio / vivienda', n.obsRefugioVivienda),
          if (n.obsRopaCama.trim().isNotEmpty) _df('Observaciones · Ropa de cama', n.obsRopaCama),
          if (n.obsArticulosHigiene.trim().isNotEmpty) _df('Observaciones · Artículos de higiene', n.obsArticulosHigiene),
          if (n.obsArticulosCocina.trim().isNotEmpty) _df('Observaciones · Artículos de cocina', n.obsArticulosCocina),
          if (n.obsPrendasVestir.trim().isNotEmpty) _df('Observaciones · Prendas de vestir', n.obsPrendasVestir),
          if (n.obsHerramientas.trim().isNotEmpty) _df('Observaciones · Herramientas', n.obsHerramientas),
          if (n.obsAlmacenamientoAgua.trim().isNotEmpty) _df('Observaciones · Almacenamiento de agua', n.obsAlmacenamientoAgua),
          if (n.obsBanos.trim().isNotEmpty) _df('Observaciones · Baños', n.obsBanos),
        ]),
      ],
    );
  }

  Widget _seccion13() {
    final r = localidad.responsable;
    return _DocSeccion(
      numero: '13',
      titulo: 'Responsable',
      children: [
        _dg([
          if (r != null) ...[
            _df('Nombre', _v(r.nombre)),
            _df('Cargo', _v(r.cargo)),
            _df('Fono', _v(r.fono)),
            _df('Correo', _v(r.correo)),
          ] else ...[
            _df('Nombre', '-'),
            _df('Cargo', '-'),
            _df('Fono', '-'),
            _df('Correo', '-'),
          ],
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

  Widget _tags(List<String> tags) {
    if (tags.isEmpty) return _vacio();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: tags
            .map((t) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
        border: Border.all(color: AppColors.divider, width: 1),
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

class _FotosDe extends StatelessWidget {
  final List<EdanFoto> fotos;
  final String? servidor;
  final double coordenadaLat;
  final double coordenadaLon;
  final String? seccion;

  const _FotosDe({
    required this.fotos,
    this.servidor,
    this.coordenadaLat = 0,
    this.coordenadaLon = 0,
    this.seccion,
  });

  String _fotoUrl(String serverPath) =>
      '${ApiConfig.baseUrl}/upload/descargar/${Uri.encodeComponent(serverPath)}';

  Map<String, String> get _fotoHeaders => {
        'Authorization':
            'Bearer ${AuthService.instance.currentToken?.accessToken ?? ''}',
      };

  Widget _imagenDeFoto(EdanFoto? foto, {BoxFit fit = BoxFit.cover}) {
    if (foto != null &&
        foto.ruta.trim().isNotEmpty &&
        File(foto.ruta).existsSync()) {
      return Image.file(
        File(foto.ruta),
        fit: fit,
        errorBuilder: (_, _, _) => _fotoPlaceholder(),
      );
    }
    final server = servidor;
    if (server != null && server.trim().isNotEmpty) {
      return Image.network(
        _fotoUrl(server),
        headers: _fotoHeaders,
        fit: fit,
        errorBuilder: (_, _, _) => _fotoPlaceholder(),
      );
    }
    return _fotoPlaceholder();
  }

  Widget _fotoPlaceholder() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: AppColors.background,
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported_outlined,
        size: 28,
        color: AppColors.textSecondary,
      ),
    );
  }

  void _verFotoFullscreen(BuildContext context, EdanFoto? foto) {
    final lat = (foto != null && foto.latitud != 0) ? foto.latitud : coordenadaLat;
    final lon = (foto != null && foto.longitud != 0) ? foto.longitud : coordenadaLon;
    final precision = foto?.precision ?? 0;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (dialogCtx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Center(
                  child: _imagenDeFoto(foto, fit: BoxFit.contain),
                ),
              ),
            ),
            if (seccion != null)
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Respaldo - $seccion',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                ),
              ),
            ),
            if (lat != 0 || lon != 0)
              Positioned(
                left: 12,
                right: 12,
                bottom: MediaQuery.of(dialogCtx).padding.bottom + 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on, size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}',
                          style: const TextStyle(fontSize: 12, color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (precision > 0)
                        Text(
                          '±${precision.toStringAsFixed(0)}m',
                          style: const TextStyle(fontSize: 12, color: Colors.white),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final server = servidor;
    final tieneRemota = server != null && server.trim().isNotEmpty;
    if (fotos.isEmpty && !tieneRemota) return const SizedBox.shrink();

    final List<EdanFoto?> fotosAMostrar = fotos.isNotEmpty ? fotos : [null];

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: fotosAMostrar.map((foto) {
          final lat = (foto != null && foto.latitud != 0) ? foto.latitud : coordenadaLat;
          final lon = (foto != null && foto.longitud != 0) ? foto.longitud : coordenadaLon;
          final precision = foto?.precision ?? 0;
          return GestureDetector(
            onTap: () => _verFotoFullscreen(context, foto),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 96,
                    height: 96,
                    child: _imagenDeFoto(foto),
                  ),
                ),
                if (lat != 0 || lon != 0) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 96,
                    child: Text(
                      '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}'
                      '${precision > 0 ? ' ±${precision.round()}m' : ''}',
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
