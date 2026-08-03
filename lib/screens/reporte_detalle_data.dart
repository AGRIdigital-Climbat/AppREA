import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/reporte.dart';
import '../models/reporte_offline.dart';
import '../models/ugr_models.dart';
import '../providers/reporte_provider.dart';

enum ReporteDetalleFuente { offline, server, ugr }

class ReporteDetalle {
  final ReporteDetalleFuente fuente;
  final String tipoEventoNombre;
  final String fechaEvento;
  final String? horaEvento;
  final String? descripcion;
  final List<String> categoriaNombres;
  final String? departamentoNombre;
  final int departamentoId;
  final String? provinciaNombre;
  final int provinciaId;
  final String? municipioNombre;
  final int municipioId;
  final String comunidad;
  final String? responsable;
  final String? responsableCelular;
  final String? responsableRol;
  final double? lat;
  final double? lon;
  final String? fotoLocalPath;
  final String? fotoServerPath;
  final int fotos;
  final int videos;
  final int documentos;
  final String? estadoNombre;
  final bool sincronizado;
  final bool esBorrador;
  final int intentosSync;
  final String? ultimoError;
  final DateTime fechaCreacion;
  final DateTime? fechaModificacion;
  final String? fechaReporte;
  final int? idLocal;
  final int? idServer;

  const ReporteDetalle({
    required this.fuente,
    required this.tipoEventoNombre,
    required this.fechaEvento,
    this.horaEvento,
    this.descripcion,
    this.categoriaNombres = const [],
    this.departamentoNombre,
    this.departamentoId = 0,
    this.provinciaNombre,
    this.provinciaId = 0,
    this.municipioNombre,
    this.municipioId = 0,
    this.comunidad = '',
    this.responsable,
    this.responsableCelular,
    this.responsableRol,
    this.lat,
    this.lon,
    this.fotoLocalPath,
    this.fotoServerPath,
    this.fotos = 0,
    this.videos = 0,
    this.documentos = 0,
    this.estadoNombre,
    this.sincronizado = true,
    this.esBorrador = false,
    this.intentosSync = 0,
    this.ultimoError,
    required this.fechaCreacion,
    this.fechaModificacion,
    this.fechaReporte,
    this.idLocal,
    this.idServer,
  });

  factory ReporteDetalle.fromOffline(
    ReporteOffline reporte,
    BuildContext context,
  ) {
    final provider = context.read<ReporteProvider>();
    return ReporteDetalle(
      fuente: ReporteDetalleFuente.offline,
      tipoEventoNombre: provider.getTipoEventoNombre(reporte.tipoEventoId),
      fechaEvento: reporte.fechaEvento,
      horaEvento: reporte.horaEvento,
      descripcion: reporte.descripcion,
      categoriaNombres: (reporte.categorias ?? [])
          .map((id) => provider.getCategoriaNombre(id))
          .toList(),
      departamentoNombre: reporte.departamentoNombre,
      departamentoId: reporte.departamentoId,
      provinciaNombre: reporte.provinciaNombre,
      provinciaId: reporte.provinciaId,
      municipioNombre: reporte.municipioNombre,
      municipioId: reporte.municipioId,
      comunidad: reporte.comunidad,
      lat: reporte.coordenadaLat,
      lon: reporte.coordenadaLon,
      fotoLocalPath: (reporte.imagenes != null && reporte.imagenes!.isNotEmpty)
          ? reporte.imagenes!.first
          : null,
      estadoNombre: reporte.estadoNombre,
      sincronizado: reporte.sincronizado,
      esBorrador: reporte.esBorrador,
      intentosSync: reporte.intentosSync,
      ultimoError: reporte.ultimoError,
      fechaCreacion: reporte.fechaCreacion,
      fechaModificacion: reporte.fechaModificacion,
      idLocal: reporte.idLocal,
      idServer: reporte.idServer,
    );
  }

  factory ReporteDetalle.fromServer(Reporte reporte) {
    return ReporteDetalle(
      fuente: ReporteDetalleFuente.server,
      tipoEventoNombre: reporte.tipoEvento?.nombre ?? 'Sin tipo',
      fechaEvento: reporte.fechaEvento,
      horaEvento: reporte.horaEvento,
      descripcion: reporte.descripcion,
      categoriaNombres:
          (reporte.categorias ?? []).map((c) => c.nombre).toList(),
      departamentoNombre: reporte.departamento?.nombre,
      departamentoId: reporte.idDepartamento,
      provinciaNombre: reporte.provincia?.nombre,
      provinciaId: reporte.idProvincia,
      municipioNombre: reporte.municipio?.nombre,
      municipioId: reporte.idMunicipio,
      comunidad: reporte.comunidad,
      responsable: reporte.usuario?.nombre,
      responsableCelular: reporte.usuario?.celular,
      responsableRol: reporte.usuario?.rol?.nombre,
      lat: reporte.coordenadaLat,
      lon: reporte.coordenadaLon,
      fotoServerPath: reporte.fotografia,
      estadoNombre: reporte.estado?.nombre,
      sincronizado: true,
      fechaCreacion:
          DateTime.tryParse(reporte.fechaReporte ?? '') ?? DateTime.now(),
      fechaReporte: reporte.fechaReporte,
      idServer: reporte.idReporte,
    );
  }

  factory ReporteDetalle.fromUgr(UgrReporte reporte) {
    return ReporteDetalle(
      fuente: ReporteDetalleFuente.ugr,
      tipoEventoNombre: reporte.tipoEvento,
      fechaEvento: DateFormat('dd/MM/yyyy HH:mm').format(reporte.fechaEvento),
      descripcion: reporte.descripcion,
      municipioNombre: reporte.municipio,
      comunidad: reporte.comunidad,
      responsable: reporte.responsable,
      lat: reporte.lat,
      lon: reporte.lon,
      fotos: reporte.fotos,
      videos: reporte.videos,
      documentos: reporte.documentos,
      estadoNombre: reporte.estado.label,
      sincronizado: true,
      fechaCreacion: reporte.fechaEvento,
    );
  }
}
