import 'package:flutter/material.dart';
import '../config/theme.dart';
import 'edan.dart';
import 'reporte.dart';

enum UgrReporteEstado { pendiente, confirmado, rechazado }

extension UgrReporteEstadoX on UgrReporteEstado {
  String get label {
    switch (this) {
      case UgrReporteEstado.pendiente:
        return 'Pendiente';
      case UgrReporteEstado.confirmado:
        return 'Confirmado';
      case UgrReporteEstado.rechazado:
        return 'Rechazado';
    }
  }

  Color get color {
    switch (this) {
      case UgrReporteEstado.pendiente:
        return AppColors.pending;
      case UgrReporteEstado.confirmado:
        return AppColors.aprobado;
      case UgrReporteEstado.rechazado:
        return AppColors.rechazado;
    }
  }

  IconData get icon {
    switch (this) {
      case UgrReporteEstado.pendiente:
        return Icons.schedule;
      case UgrReporteEstado.confirmado:
        return Icons.check_circle;
      case UgrReporteEstado.rechazado:
        return Icons.cancel;
    }
  }
}

enum UgrEdanEstado {
  borrador,
  enEdicion,
  firmado,
  enviado,
  enRevision,
  observado,
  aprobado,
}

extension UgrEdanEstadoX on UgrEdanEstado {
  String get label {
    switch (this) {
      case UgrEdanEstado.borrador:
        return 'Borrador';
      case UgrEdanEstado.enEdicion:
        return 'En edición';
      case UgrEdanEstado.firmado:
        return 'Firmado';
      case UgrEdanEstado.enviado:
        return 'Enviado';
      case UgrEdanEstado.enRevision:
        return 'En revisión';
      case UgrEdanEstado.observado:
        return 'Observado';
      case UgrEdanEstado.aprobado:
        return 'Aprobado';
    }
  }

  Color get color {
    switch (this) {
      case UgrEdanEstado.borrador:
        return AppColors.closed;
      case UgrEdanEstado.enEdicion:
        return AppColors.inProgress;
      case UgrEdanEstado.firmado:
        return AppColors.enRevision;
      case UgrEdanEstado.enviado:
        return AppColors.enviado;
      case UgrEdanEstado.enRevision:
        return AppColors.pending;
      case UgrEdanEstado.observado:
        return AppColors.rechazado;
      case UgrEdanEstado.aprobado:
        return AppColors.aprobado;
    }
  }

  IconData get icon {
    switch (this) {
      case UgrEdanEstado.borrador:
        return Icons.edit_note;
      case UgrEdanEstado.enEdicion:
        return Icons.edit;
      case UgrEdanEstado.firmado:
        return Icons.draw;
      case UgrEdanEstado.enviado:
        return Icons.send;
      case UgrEdanEstado.enRevision:
        return Icons.visibility;
      case UgrEdanEstado.observado:
        return Icons.feedback;
      case UgrEdanEstado.aprobado:
        return Icons.verified;
    }
  }
}

class UgrReporte {
  final String id;
  final int? idReporte;
  final String tipoEvento;
  final String comunidad;
  final String municipio;
  final String responsable;
  final DateTime fechaEvento;
  final String descripcion;
  final double lat;
  final double lon;
  final int fotos;
  final int videos;
  final int documentos;
  UgrReporteEstado estado;

  UgrReporte({
    required this.id,
    this.idReporte,
    required this.tipoEvento,
    required this.comunidad,
    required this.municipio,
    required this.responsable,
    required this.fechaEvento,
    required this.descripcion,
    required this.lat,
    required this.lon,
    this.fotos = 0,
    this.videos = 0,
    this.documentos = 0,
    this.estado = UgrReporteEstado.pendiente,
  });

  factory UgrReporte.fromServer(Reporte r) {
    DateTime fecha = DateTime.tryParse(r.fechaEvento) ?? DateTime.now();
    if (r.horaEvento != null && r.horaEvento!.isNotEmpty) {
      final partes = r.horaEvento!.split(':');
      if (partes.isNotEmpty) {
        final h = int.tryParse(partes[0]);
        final m = partes.length > 1 ? int.tryParse(partes[1]) : null;
        if (h != null) {
          fecha = DateTime(
            fecha.year,
            fecha.month,
            fecha.day,
            h,
            m ?? 0,
          );
        }
      }
    }
    final estado = switch (r.idEstado) {
      3 => UgrReporteEstado.confirmado,
      4 => UgrReporteEstado.rechazado,
      _ => UgrReporteEstado.pendiente,
    };
    return UgrReporte(
      id: r.idReporte?.toString() ?? '',
      idReporte: r.idReporte,
      tipoEvento: r.tipoEvento?.nombre ?? 'Evento',
      comunidad: r.comunidad,
      municipio: r.municipio?.nombre ?? '',
      responsable: r.usuario?.nombre ?? 'Reportador',
      fechaEvento: fecha,
      descripcion: r.descripcion ?? '',
      lat: r.coordenadaLat ?? 0.0,
      lon: r.coordenadaLon ?? 0.0,
      fotos: (r.fotografia != null && r.fotografia!.isNotEmpty) ? 1 : 0,
      videos: 0,
      documentos: 0,
      estado: estado,
    );
  }

  String get tiempoRelativo => _tiempoRelativo(fechaEvento);
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
  final String codigo;
  final String tipoEvento;
  final String comunidad;
  final String municipio;
  final DateTime fechaCreacion;
  final List<UgrSeccion> secciones;
  final List<UgrHistorialEvento> historial;
  UgrEdanEstado estado;

  UgrEdan({
    required this.codigo,
    required this.tipoEvento,
    required this.comunidad,
    required this.municipio,
    required this.fechaCreacion,
    required this.secciones,
    required this.historial,
    this.estado = UgrEdanEstado.borrador,
  });

  factory UgrEdan.fromEdan(
    Edan e, {
    required String municipioNombre,
    String? usuarioNombre,
  }) {
    final fecha = DateTime.tryParse(e.fechaLlenado) ??
        DateTime.tryParse(e.fechaEvento) ??
        DateTime.now();
    final estado = switch (e.estado) {
      'enviado' => UgrEdanEstado.enviado,
      'observado' => UgrEdanEstado.observado,
      'aprobado' => UgrEdanEstado.aprobado,
      'en_revision' || 'enRevision' => UgrEdanEstado.enRevision,
      _ => UgrEdanEstado.borrador,
    };

    final secciones = [
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
      UgrSeccion(
        nombre: '04 · Salud',
        descripcion: 'Daños en servicios de salud y necesidades',
        icon: Icons.local_hospital_outlined,
        completada: e.localidades.any((l) =>
            l.impSalud &&
            l.establecimientosSalud
                .any((s) => s.nombreEstablecimiento.trim().isNotEmpty)),
      ),
      UgrSeccion(
        nombre: '05 · Infraestructura',
        descripcion: 'Daños viales y en infraestructura pública',
        icon: Icons.route_outlined,
        completada: e.localidades.any((l) =>
            l.impInfraestructura &&
            (l.danosViales.any((d) => d.viaPuente.trim().isNotEmpty) ||
                l.danosInfraPublica
                    .any((d) => d.tipoEstructura.trim().isNotEmpty))),
      ),
      UgrSeccion(
        nombre: '06 · Servicios básicos',
        descripcion: 'Agua, luz, alcantarillado y comunicaciones',
        icon: Icons.water_drop_outlined,
        completada: e.localidades.any((l) =>
            l.impServicios && l.serviciosBasicos.algunaSeleccionada),
      ),
      UgrSeccion(
        nombre: '07 · Educación',
        descripcion: 'Unidades educativas y afectación',
        icon: Icons.school_outlined,
        completada: e.localidades.any((l) =>
            l.impEducacion &&
            l.unidadesEducativas
                .any((u) => u.nombreEstablecimiento.trim().isNotEmpty)),
      ),
      UgrSeccion(
        nombre: '08 · Vivienda',
        descripcion: 'Daños parciales y totales por localidad',
        icon: Icons.home_outlined,
        completada: e.localidades.any((l) =>
            l.impVivienda &&
            l.danosVivienda.any((v) => v.comunidad.trim().isNotEmpty)),
      ),
      UgrSeccion(
        nombre: '09 · Agropecuario',
        descripcion: 'Agricultura, pecuario e infraestructura productiva',
        icon: Icons.grain,
        completada: e.localidades.any((l) =>
            l.impAgropecuario &&
            (l.danosAgricultura
                    .any((a) => a.tipoCultivo.trim().isNotEmpty) ||
                l.danosPecuarios.any((p) => p.especie.trim().isNotEmpty) ||
                l.infraProductiva.any((i) => i.tipo.trim().isNotEmpty))),
      ),
      UgrSeccion(
        nombre: '10 · Protección',
        descripcion: 'Población vulnerable y afectación por sexo',
        icon: Icons.volunteer_activism_outlined,
        completada: e.localidades.any((l) =>
            l.impProteccion &&
            (l.proteccion.vulnerables.algunoPositivo ||
                l.proteccion.mujeres > 0 ||
                l.proteccion.hombres > 0)),
      ),
      UgrSeccion(
        nombre: '11 · Necesidades humanitarias',
        descripcion: 'Alimentos, refugio, higiene y otros',
        icon: Icons.inventory_2_outlined,
        completada: e.necesidadHumanitaria.algunaSeleccionada,
      ),
      UgrSeccion(
        nombre: '13 · Responsable del formulario',
        descripcion: 'Nombre, cargo y contacto del responsable',
        icon: Icons.badge_outlined,
        completada: e.responsable.nombre.trim().isNotEmpty &&
            e.responsable.cargo.trim().isNotEmpty,
      ),
    ];
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
      codigo: e.codigoEdan,
      tipoEvento: e.tipoEventoNombre ?? 'Evento',
      comunidad: _primerLocalidad(e.localidades),
      municipio: municipioNombre,
      fechaCreacion: fecha,
      secciones: secciones,
      historial: historial,
      estado: estado,
    );
  }

  static String _primerLocalidad(List<EdanLocalidad> localidades) {
    for (final l in localidades) {
      if (l.nombre.trim().isNotEmpty) return l.nombre;
    }
    return '';
  }

  int get seccionesCompletadas => secciones.where((s) => s.completada).length;

  int get seccionesTotal => secciones.length;

  String get tiempoRelativo => _tiempoRelativo(fechaCreacion);
}

class UgrIndicadores {
  final int reportesNuevos;
  final int reportesConfirmados;
  final int edanEnEdicion;
  final int edanObservados;
  final int edanEnviados;

  const UgrIndicadores({
    required this.reportesNuevos,
    required this.reportesConfirmados,
    required this.edanEnEdicion,
    required this.edanObservados,
    required this.edanEnviados,
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
