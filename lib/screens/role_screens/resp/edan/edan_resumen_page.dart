import 'package:flutter/material.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';

/// Página de resumen / vista previa del formulario.
///
/// Muestra un resumen legible de la información registrada en cada sección.
/// Solo desde esta página se permite el envío (el cambio de estado a
/// "Enviado UGR" ocurre en el botón Enviar del wizard).
class EdanResumenPage extends StatelessWidget {
  final EdanLocalidad localidad;
  final Map<String, bool> seccionesCompletas;

  const EdanResumenPage({
    super.key,
    required this.localidad,
    required this.seccionesCompletas,
  });

  @override
  Widget build(BuildContext context) {
    final l = localidad;
    final cards = <Widget>[
      _tarjeta(context, '01 · Datos generales', Icons.place_outlined,
          'completa' == _estado('01'), _datosGenerales(l)),
      _tarjeta(context, '02 · Totales', Icons.people_outline,
          seccionesCompletas['02'] ?? false, _totales(l)),
      if (l.impPoblacion)
        _tarjeta(context, '03 · Impacto en la población', Icons.groups_outlined,
            seccionesCompletas['03'] ?? false, _impactoPoblacion(l)),
      if (l.impSalud)
        _tarjeta(context, '04 · Impacto en la salud', Icons.local_hospital_outlined,
            seccionesCompletas['04'] ?? false, _salud(l)),
      if (l.impInfraestructura)
        _tarjeta(context, '05 · Infraestructura', Icons.construction,
            seccionesCompletas['05'] ?? false, _infra(l)),
      if (l.impServicios)
        _tarjeta(context, '06 · Servicios básicos', Icons.home_work_outlined,
            seccionesCompletas['06'] ?? false, _servicios(l)),
      if (l.impEducacion)
        _tarjeta(context, '07 · Educación', Icons.school_outlined,
            seccionesCompletas['07'] ?? false, _educacion(l)),
      if (l.impVivienda)
        _tarjeta(context, '08 · Viviendas', Icons.home_outlined,
            seccionesCompletas['08'] ?? false, _vivienda(l)),
      if (l.impAgropecuario)
        _tarjeta(context, '09 · Agropecuario', Icons.agriculture_outlined,
            seccionesCompletas['09'] ?? false, _agro(l)),
      if (l.impProteccion)
        _tarjeta(context, '10 · Protección', Icons.people_outline,
            seccionesCompletas['10'] ?? false, _proteccion(l)),
      if (l.impNecesidades)
        _tarjeta(context, '11 · Necesidades humanitarias', Icons.handshake_outlined,
            seccionesCompletas['11'] ?? false, _necesidades(l)),
      _tarjeta(context, '13 · Responsable', Icons.badge_outlined,
          seccionesCompletas['13'] ?? false, _responsable(l)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Resumen de la evaluación',
          style: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        const Text(
          'Revise la información antes de enviar. Puede volver a cualquier '
          'sección tocando "Anterior".',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 14),
        ...cards,
        const SizedBox(height: 8),
        const Text(
          'Al presionar "Enviar", el formulario cambiará a estado "Enviado UGR".',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  String _estado(String sec) => seccionesCompletas[sec] ?? false ? 'completa' : 'incompleta';

  Widget _tarjeta(BuildContext context, String titulo, IconData icono, bool completa, List<String> lineas) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: completa ? const Color(0xFF4CAF50) : AppColors.divider,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono,
              size: 20,
              color: completa ? const Color(0xFF4CAF50) : PaletteScope.of(context).primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary),
                      ),
                    ),
                    Icon(
                      completa ? Icons.check_circle : Icons.error_outline,
                      size: 16,
                      color: completa ? const Color(0xFF4CAF50) : const Color(0xFFF44336),
                    ),
                  ],
                ),
                if (lineas.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('Sin datos registrados.',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  )
                else
                  for (final linea in lineas)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(linea,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<String> _datosGenerales(EdanLocalidad l) => [
        if (l.nombre.isNotEmpty) 'Localidad: ${l.nombre}',
        if (l.tipoLocalidad.isNotEmpty) 'Tipo: ${l.tipoLocalidad}',
        if ((l.departamentoNombre ?? '').isNotEmpty)
          'Ubicación: ${l.departamentoNombre}, ${l.provinciaNombre ?? ''}',
      ];

  List<String> _totales(EdanLocalidad l) => [
        if (l.totalPoblacionAfectada > 0) 'Población afectada: ${l.totalPoblacionAfectada}',
        if (l.totalFamiliasAfectadas > 0) 'Familias afectadas: ${l.totalFamiliasAfectadas}',
        if (l.totalFamiliasDamnificadas > 0) 'Familias damnificadas: ${l.totalFamiliasDamnificadas}',
      ];

  List<String> _impactoPoblacion(EdanLocalidad l) => [
        for (final p in l.impactoPoblacion)
          '${p.grupoEtario.isEmpty ? 'Grupo' : p.grupoEtario}: '
              '${p.fallecidos} fallecidos, ${p.heridos} heridos, ${p.desaparecidos} desaparecidos',
      ];

  List<String> _salud(EdanLocalidad l) => [
        for (final e in l.establecimientosSalud)
          '${e.nombreEstablecimiento.isEmpty ? 'Sin nombre' : e.nombreEstablecimiento}'
              '${e.danoTotal ? ' (total)' : e.danoParcial ? ' (parcial)' : ''}',
        if ((l.necesidadSalud?.numeroPersonas ?? 0) > 0)
          'Personas con necesidad de salud: ${l.necesidadSalud?.numeroPersonas}',
      ];

  List<String> _infra(EdanLocalidad l) => [
        for (final d in l.danosViales)
          '${d.viaPuente.isEmpty ? 'Vía/puente' : d.viaPuente}'
              '${d.danoTotal ? ' (total)' : d.danoParcial ? ' (parcial)' : ''}',
        for (final i in l.danosInfraPublica)
          '${i.tipoEstructura.isEmpty ? 'Estructura' : i.tipoEstructura}'
              '${i.danoTotal ? ' (total)' : i.danoParcial ? ' (parcial)' : ''}',
      ];

  List<String> _servicios(EdanLocalidad l) => [
        for (final s in l.serviciosBasicos)
          if (s.afectado || s.danoParcial || s.danoTotal)
            '${s.etiqueta}${s.danoTotal ? ' (total)' : s.danoParcial ? ' (parcial)' : ''}',
      ];

  List<String> _educacion(EdanLocalidad l) => [
        for (final u in l.unidadesEducativas)
          '${u.nombreEstablecimiento.isEmpty ? 'Unidad' : u.nombreEstablecimiento}'
              '${u.estudiantes > 0 ? ' (${u.estudiantes} estud.)' : ''}',
      ];

  List<String> _vivienda(EdanLocalidad l) => [
        for (final v in l.danosVivienda)
          '${v.comunidad.isEmpty ? 'Comunidad' : v.comunidad}: '
              '${v.danoParcial} parcial, ${v.danoTotal} total',
      ];

  List<String> _agro(EdanLocalidad l) => [
        for (final a in l.danosAgricultura)
          '${a.tipoCultivo}: ${a.hectareasAfectadas} ha afectadas, ${a.hectareasPerdidas} ha perdidas',
        for (final p in l.danosPecuarios)
          '${p.especie}: ${p.animalesAfectados} afectados',
        for (final i in l.infraProductiva)
          '${i.tipo}: ${i.danoTotal > 0 ? 'total' : i.danoParcial > 0 ? 'parcial' : ''}',
      ];

  List<String> _proteccion(EdanLocalidad l) => [
        for (final g in l.proteccion)
          if (g.tieneDatos) '${g.nombreGrupo}: ${g.mujeres} M, ${g.hombres} H',
      ];

  List<String> _necesidades(EdanLocalidad l) {
    final n = l.necesidadHumanitaria!;
    return [
      if (n.alimentos) 'Alimentos',
      if (n.refugioVivienda) 'Refugio / vivienda',
      if (n.ropaCama) 'Ropa de cama',
      if (n.articulosHigiene) 'Art. higiene',
      if (n.articulosCocina) 'Art. cocina',
      if (n.prendasVestir) 'Prendas de vestir',
      if (n.herramientas) 'Herramientas',
      if (n.almacenamientoAgua) 'Almac. agua',
      if (n.banos) 'Baños',
    ];
  }

  List<String> _responsable(EdanLocalidad l) {
    final r = l.responsable;
    return [
      if (r != null && r.nombre.isNotEmpty) 'Responsable: ${r.nombre}',
      if (r != null && r.cargo.isNotEmpty) 'Cargo: ${r.cargo}',
      if (r != null && r.fono.isNotEmpty) 'Teléfono: ${r.fono}',
    ];
  }
}
