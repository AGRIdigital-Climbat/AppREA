import 'package:flutter/material.dart';
import '../config/theme.dart';
import 'edan.dart';

enum UgrEdanEstado {
  borrador,
  enviado,
  aprobado,
  rechazado,
  cerrado,
}

extension UgrEdanEstadoX on UgrEdanEstado {
  int get id => switch (this) {
        UgrEdanEstado.borrador => 1,
        UgrEdanEstado.enviado => 2,
        UgrEdanEstado.aprobado => 3,
        UgrEdanEstado.rechazado => 4,
        UgrEdanEstado.cerrado => 5,
      };

  String get label {
    switch (this) {
      case UgrEdanEstado.borrador:
        return 'Borrador';
      case UgrEdanEstado.enviado:
        return 'Enviado';
      case UgrEdanEstado.aprobado:
        return 'Aprobado';
      case UgrEdanEstado.rechazado:
        return 'Rechazado';
      case UgrEdanEstado.cerrado:
        return 'Cerrado';
    }
  }

  String get descripcion {
    switch (this) {
      case UgrEdanEstado.borrador:
        return 'Borrador inicial';
      case UgrEdanEstado.enviado:
        return 'Formulario enviado al servidor';
      case UgrEdanEstado.aprobado:
        return 'Formulario aprobado';
      case UgrEdanEstado.rechazado:
        return 'Formulario rechazado';
      case UgrEdanEstado.cerrado:
        return 'Formulario cerrado';
    }
  }

  Color get color {
    switch (this) {
      case UgrEdanEstado.borrador:
        return AppColors.closed;
      case UgrEdanEstado.enviado:
        return AppColors.enviado;
      case UgrEdanEstado.aprobado:
        return AppColors.aprobado;
      case UgrEdanEstado.rechazado:
        return AppColors.rechazado;
      case UgrEdanEstado.cerrado:
        return AppColors.closed;
    }
  }

  IconData get icon {
    switch (this) {
      case UgrEdanEstado.borrador:
        return Icons.edit_note;
      case UgrEdanEstado.enviado:
        return Icons.send;
      case UgrEdanEstado.aprobado:
        return Icons.verified;
      case UgrEdanEstado.rechazado:
        return Icons.cancel;
      case UgrEdanEstado.cerrado:
        return Icons.lock;
    }
  }

  bool get puedeEditar => switch (this) {
        UgrEdanEstado.borrador => true,
        UgrEdanEstado.enviado => false,
        UgrEdanEstado.aprobado => false,
        UgrEdanEstado.rechazado => true,
        UgrEdanEstado.cerrado => false,
      };

  bool get puedeEliminar => switch (this) {
        UgrEdanEstado.borrador => true,
        UgrEdanEstado.enviado => false,
        UgrEdanEstado.aprobado => false,
        UgrEdanEstado.rechazado => true,
        UgrEdanEstado.cerrado => false,
      };
}

extension UgrEdanEstadoFromInt on UgrEdanEstado {
  static UgrEdanEstado fromId(int? id) {
    return switch (id) {
      1 => UgrEdanEstado.borrador,
      2 => UgrEdanEstado.enviado,
      3 => UgrEdanEstado.aprobado,
      4 => UgrEdanEstado.rechazado,
      5 => UgrEdanEstado.cerrado,
      _ => UgrEdanEstado.borrador,
    };
  }
}

class UgrSeccion {
  final String nombre;
  final String descripcion;
  final IconData icon;
  final bool completada;

  const UgrSeccion({
    required this.nombre,
    required this.descripcion,
    required this.icon,
    required this.completada,
  });
}

class UgrHistorialEvento {
  final String titulo;
  final String fecha;
  final String usuario;
  final IconData icon;
  final Color color;

  const UgrHistorialEvento({
    required this.titulo,
    required this.fecha,
    required this.usuario,
    required this.icon,
    required this.color,
  });
}

class UgrEdan {
  final String id;
  final int? idEdan;
  final int? idLocal;
  final int? idServer;
  final bool sincronizado;
  final bool pendienteEliminacion;
  final bool esBorrador;
  final String codigo;
  final String tipoEvento;
  final String comunidad;
  final String municipio;
  final DateTime fechaCreacion;
  final List<UgrSeccion> secciones;
  final List<UgrHistorialEvento> historial;
  UgrEdanEstado estado;
  final String responsable;
  final String responsableCelular;
  final String responsableRol;
  final double lat;
  final double lon;
  final int localidades;
  final int fotos;
  final String descripcion;

  UgrEdan({
    required this.id,
    this.idEdan,
    this.idLocal,
    this.idServer,
    this.sincronizado = false,
    this.pendienteEliminacion = false,
    this.esBorrador = false,
    required this.codigo,
    required this.tipoEvento,
    required this.comunidad,
    required this.municipio,
    required this.fechaCreacion,
    required this.secciones,
    required this.historial,
    this.estado = UgrEdanEstado.borrador,
    this.responsable = '',
    this.responsableCelular = '',
    this.responsableRol = '',
    this.lat = 0.0,
    this.lon = 0.0,
    this.localidades = 0,
    this.fotos = 0,
    this.descripcion = '',
  });

  factory UgrEdan.fromEdan(
    Edan e, {
    required String municipioNombre,
    String? usuarioNombre,
  }) {
    final fecha = DateTime.tryParse(e.fechaLlenado) ??
        DateTime.tryParse(e.fechaEvento) ??
        DateTime.now();
    final idEstado = e.idEstado;
    final estado = UgrEdanEstadoFromInt.fromId(idEstado);
    final esBorrador = estado == UgrEdanEstado.borrador;

    final primeraLocalidad = e.localidades.isNotEmpty ? e.localidades.first : null;
    final lat = primeraLocalidad != null && primeraLocalidad.nombre.isNotEmpty 
        ? -16.5 
        : 0.0;
    final lon = primeraLocalidad != null && primeraLocalidad.nombre.isNotEmpty 
        ? -68.15 
        : 0.0;

    final seccionesBase = <UgrSeccion>[
      UgrSeccion(
        nombre: '01 · Datos generales',
        descripcion: 'Alcalde, ubicación, fechas y localidades',
        icon: Icons.description_outlined,
        completada: e.nombreAlcalde.trim().isNotEmpty &&
            e.fonoAlcalde.trim().isNotEmpty &&
            e.fechaLlenado.isNotEmpty &&
            e.fechaEvento.isNotEmpty &&
            e.idDepartamento != null &&
            e.idProvincia != null &&
            e.idMunicipio != null,
      ),
      UgrSeccion(
        nombre: '02 · Población afectada y damnificada',
        descripcion: 'Totales de población y familias',
        icon: Icons.groups_outlined,
        completada: e.totalPoblacionAfectada > 0 ||
            e.totalFamiliasAfectadas > 0 ||
            e.totalFamiliasDamnificadas > 0,
      ),
      UgrSeccion(
        nombre: '03 · Municipio afectado',
        descripcion: 'Tipo de evento, impacto y primera respuesta',
        icon: Icons.warning_amber_rounded,
        completada: e.idTipoEvento != null,
      ),
    ];

    final seccionesEspecificas = <UgrSeccion>[
      if (!esBorrador || e.localidades.any((l) => l.grupSalud))
        UgrSeccion(
          nombre: '04 · Salud',
          descripcion: 'Daños en servicios de salud y necesidades',
          icon: Icons.local_hospital_outlined,
          completada: e.localidades.any((l) =>
              l.grupSalud &&
              l.establecimientosSalud
                  .any((s) => s.nombreEstablecimiento.trim().isNotEmpty)),
        ),
      if (!esBorrador || e.localidades.any((l) => l.grupInfraestructura))
        UgrSeccion(
          nombre: '05 · Infraestructura',
          descripcion: 'Daños viales y en infraestructura pública',
          icon: Icons.route_outlined,
          completada: e.localidades.any((l) =>
              l.grupInfraestructura &&
              (l.danosViales.any((d) => d.viaPuente.trim().isNotEmpty) ||
                  l.danosInfraPublica
                      .any((d) => d.tipoEstructura.trim().isNotEmpty))),
        ),
      if (!esBorrador || e.localidades.any((l) => l.grupServicios))
        UgrSeccion(
          nombre: '06 · Servicios básicos',
          descripcion: 'Agua, luz, alcantarillado y comunicaciones',
          icon: Icons.water_drop_outlined,
          completada: e.localidades.any((l) =>
              l.grupServicios && l.serviciosBasicos.any((s) => s.tieneDatos)),
        ),
      if (!esBorrador || e.localidades.any((l) => l.grupEducacion))
        UgrSeccion(
          nombre: '07 · Educación',
          descripcion: 'Unidades educativas y afectación',
          icon: Icons.school_outlined,
          completada: e.localidades.any((l) =>
              l.grupEducacion &&
              l.unidadesEducativas.any((u) =>
                  u.nombreEstablecimiento.trim().isNotEmpty ||
                  u.estudiantes > 0 ||
                  u.profesores > 0 ||
                  u.administrativos > 0)),
        ),
      if (!esBorrador || e.localidades.any((l) => l.grupVivienda))
        UgrSeccion(
          nombre: '08 · Vivienda',
          descripcion: 'Daños parciales y totales por localidad',
          icon: Icons.home_outlined,
          completada: e.localidades.any((l) =>
              l.grupVivienda &&
              l.danosVivienda.any((v) => v.comunidad.trim().isNotEmpty)),
        ),
      if (!esBorrador || e.localidades.any((l) => l.grupAgropecuario))
        UgrSeccion(
          nombre: '09 · Agropecuario',
          descripcion: 'Agricultura, pecuario e infraestructura productiva',
          icon: Icons.grain,
          completada: e.localidades.any((l) =>
              l.grupAgropecuario &&
              (l.danosAgricultura
                      .any((a) => a.tipoCultivo.trim().isNotEmpty) ||
                  l.danosPecuarios.any((p) => p.especie.trim().isNotEmpty) ||
                  l.infraProductiva.any((i) => i.tipo.trim().isNotEmpty))),
        ),
      if (!esBorrador || e.localidades.any((l) => l.grupProteccion))
        UgrSeccion(
          nombre: '10 · Protección',
          descripcion: 'Población vulnerable y afectación por sexo',
          icon: Icons.volunteer_activism_outlined,
          completada: e.localidades.any((l) =>
              l.grupProteccion && l.proteccion.any((g) => g.tieneDatos)),
        ),
      if (!esBorrador || e.localidades.any((l) => l.grupNecesidades))
        UgrSeccion(
          nombre: '11 · Necesidades humanitarias',
          descripcion: 'Alimentos, refugio, higiene y otros',
          icon: Icons.inventory_2_outlined,
          completada: e.localidades.any((l) =>
              l.grupNecesidades && (l.necesidadHumanitaria?.algunaSeleccionada ?? false)),
        ),
      UgrSeccion(
        nombre: '13 · Responsable del formulario',
        descripcion: 'Nombre, cargo y contacto del responsable',
        icon: Icons.badge_outlined,
        completada: e.responsable.nombre.trim().isNotEmpty &&
            e.responsable.cargo.trim().isNotEmpty,
      ),
    ];

    final secciones = [...seccionesBase, ...seccionesEspecificas];
    final descripcion = _generarDescripcion(e);
    final historial = [
      UgrHistorialEvento(
        titulo: 'EDAN registrado como borrador',
        fecha: _fmtFecha(fecha),
        usuario: usuarioNombre ?? 'UGR',
        icon: Icons.edit_note,
        color: estado.color,
      ),
    ];
    return UgrEdan(
      id: e.idLocal?.toString() ?? e.codigoEdan,
      idEdan: e.idEdan ?? e.idServer,
      idLocal: e.idLocal,
      idServer: e.idServer,
      sincronizado: e.sincronizado,
      pendienteEliminacion: e.pendienteEliminacion,
      esBorrador: esBorrador,
      codigo: e.codigoEdan,
      tipoEvento: e.tipoEventoNombre ?? 'Evento',
      comunidad: _primerLocalidad(e.localidades),
      municipio: municipioNombre,
      fechaCreacion: fecha,
      secciones: secciones,
      historial: historial,
      estado: estado,
      responsable: e.responsable.nombre,
      responsableCelular: e.responsable.fono,
      responsableRol: e.responsable.cargo,
      lat: lat,
      lon: lon,
      localidades: e.localidadesAfectadas,
      fotos: 0,
      descripcion: descripcion,
    );
  }

  static String _generarDescripcion(Edan e) {
    final partes = <String>[];
    if (e.totalPoblacionAfectada > 0) {
      partes.add('${e.totalPoblacionAfectada} personas afectadas');
    }
    if (e.totalFamiliasDamnificadas > 0) {
      partes.add('${e.totalFamiliasDamnificadas} familias damnificadas');
    }
    if (e.localidadesAfectadas > 0) {
      partes.add('${e.localidadesAfectadas} localidades');
    }
    return partes.isNotEmpty ? partes.join(' · ') : 'Sin datos adicionales';
  }

  static String _primerLocalidad(List<EdanLocalidad> localidades) {
    for (final l in localidades) {
      if (l.nombre.trim().isNotEmpty) return l.etiquetaLugar;
    }
    return '';
  }

  int get seccionesCompletadas => secciones.where((s) => s.completada).length;

  int get seccionesTotal => secciones.length;

  String get tiempoRelativo => _tiempoRelativo(fechaCreacion);
}

class UgrIndicadores {
  final int localidadesPendientes;
  final int localidadesAprobadas;
  final int edanesConsolidados;
  final int edanesEnviados;

  const UgrIndicadores({
    required this.localidadesPendientes,
    required this.localidadesAprobadas,
    required this.edanesConsolidados,
    required this.edanesEnviados,
  });
}

class UgrActividad {
  final String texto;
  final String tiempo;
  final IconData icon;
  final Color color;

  const UgrActividad({
    required this.texto,
    required this.tiempo,
    required this.icon,
    required this.color,
  });
}

String _tiempoRelativo(DateTime fecha) {
  final diff = DateTime.now().difference(fecha);
  if (diff.inMinutes < 1) return 'Hace un momento';
  if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} minutos';
  if (diff.inHours < 24) {
    return 'Hace ${diff.inHours} hora${diff.inHours == 1 ? '' : 's'}';
  }
  return 'Hace ${diff.inDays} día${diff.inDays == 1 ? '' : 's'}';
}

String _fmtFecha(DateTime d) {
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
