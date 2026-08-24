import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../models/reporte_offline.dart';
import '../providers/auth_provider.dart';
import '../providers/reporte_provider.dart';
import '../widgets/custom_button.dart';
import '../widgets/reporte_documento.dart';

class ReportePreviewScreen extends StatelessWidget {
  final int departamentoId;
  final int provinciaId;
  final int municipioId;
  final String comunidad;
  final String departamentoNombre;
  final String provinciaNombre;
  final String municipioNombre;
  final String fechaEvento;
  final String fechaEventoDisplay;
  final String horaEvento;
  final int tipoEventoId;
  final String descripcion;
  final List<String> imagenes;
  final List<int> categorias;
  final double? latitud;
  final double? longitud;
  final DateTime fechaCreacion;
  final ReporteOffline? reporteExistente;

  ReportePreviewScreen({
    super.key,
    required this.departamentoId,
    required this.provinciaId,
    required this.municipioId,
    required this.comunidad,
    required this.departamentoNombre,
    required this.provinciaNombre,
    required this.municipioNombre,
    required this.fechaEvento,
    required this.fechaEventoDisplay,
    required this.horaEvento,
    required this.tipoEventoId,
    required this.descripcion,
    required this.imagenes,
    required this.categorias,
    this.latitud,
    this.longitud,
    DateTime? fechaCreacion,
    this.reporteExistente,
  }) : fechaCreacion = fechaCreacion ?? DateTime.now();

  String _getTipoEvento(int id, ReporteProvider rp) {
    return rp.getTipoEventoNombre(id);
  }

  String _getCategoriaNombre(int id, ReporteProvider rp) {
    return rp.getCategoriaNombre(id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Vista Previa del Reporte'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildDocument(context),
            const SizedBox(height: 20),
            CustomButton(
              text: 'Enviar reporte',
              onPressed: () => _showConfirmDialog(context),
              icon: Icons.send,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _saveDraft(context),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Guardar como borrador'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange.shade700,
                  side: BorderSide(color: Colors.orange.shade300),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Volver y editar'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildDocument(BuildContext context) {
    final rp = context.read<ReporteProvider>();

    final secciones = <ReporteDocSeccion>[
      ReporteDocSeccion(
        titulo: 'UBICACION',
        campos: [
          ReporteDocCampo('Departamento', departamentoNombre.isNotEmpty ? departamentoNombre : '--'),
          ReporteDocCampo('Provincia', provinciaNombre.isNotEmpty ? provinciaNombre : '--'),
          ReporteDocCampo('Municipio', municipioNombre.isNotEmpty ? municipioNombre : '--'),
          ReporteDocCampo('Comunidad', comunidad.isNotEmpty ? comunidad : '--'),
        ],
      ),
      ReporteDocSeccion(
        titulo: 'DATOS DEL EVENTO',
        campos: [
          ReporteDocCampo('Fecha del evento', fechaEventoDisplay),
          ReporteDocCampo('Hora del evento', horaEvento.isNotEmpty ? horaEvento : '--'),
          ReporteDocCampo('Tipo de evento', _getTipoEvento(tipoEventoId, rp)),
          if (descripcion.isNotEmpty) ReporteDocCampo('Descripcion', descripcion),
        ],
      ),
      ReporteDocSeccion(
        titulo: 'UBICACION GEOGRAFICA',
        campos: [
          ReporteDocCampo('Latitud', latitud != null ? latitud!.toStringAsFixed(6) : '--'),
          ReporteDocCampo('Longitud', longitud != null ? longitud!.toStringAsFixed(6) : '--'),
        ],
        contenido: latitud != null && longitud != null
            ? ReporteDocMapa(lat: latitud!, lon: longitud!)
            : null,
      ),
      ReporteDocSeccion(
        titulo: 'EVIDENCIA FOTOGRAFICA',
        campos: imagenes.isEmpty
            ? const [ReporteDocCampo('Fotografia', 'Sin evidencia fotografica')]
            : const [],
        contenido: imagenes.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(imagenes.first),
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 200,
                    color: AppColors.surface,
                    child: const Center(
                      child: Text('Error al cargar la imagen',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  ),
                ),
              )
            : null,
      ),
      ReporteDocSeccion(
        titulo: 'CATEGORIAS DE AFECTACION',
        campos: categorias.isEmpty
            ? const [ReporteDocCampo('Categorias', 'Sin categorias seleccionadas')]
            : const [],
        contenido: categorias.isNotEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: categorias
                    .map((c) => Padding(
                          padding: const EdgeInsets.only(left: 12, bottom: 4),
                          child: Text(
                            '  - ${_getCategoriaNombre(c, rp)}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ))
                    .toList(),
              )
            : null,
      ),
      const ReporteDocSeccion(
        titulo: 'ESTADO',
        campos: [ReporteDocCampo('Estado', 'Pendiente')],
      ),
    ];

    return ReporteDocumento(
      titulo: 'REPORTE DE EVENTO ADVERSO',
      subtitulo: 'PRE-EDAN - SINAGER-SAT',
      fechaCabecera: fechaEventoDisplay,
      secciones: secciones,
      footerNota: 'Este reporte sera verificado por el equipo SINAGER-SAT.',
      footerFecha:
          'Fecha de creacion: ${DateFormat("dd/MM/yyyy HH:mm").format(fechaCreacion)}',
    );
  }

  void _showConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: AppColors.pending,
          size: 40,
        ),
        title: const Text(
          'Verificar informacion',
          textAlign: TextAlign.center,
        ),
        content: const Text(
          'Los datos ingresados seran verificados por el equipo de SINAGER-SAT. '
          'Asegurese de que toda la informacion sea correcta antes de enviar.',
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Volver'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _submitReport(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Enviar reporte'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitReport(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    final reporteProvider = context.read<ReporteProvider>();

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.primary),
                SizedBox(height: 16),
                Text('Enviando reporte...'),
              ],
            ),
          ),
        ),
      ),
    );

    if (reporteExistente != null) {
      final reporteActualizado = ReporteOffline(
        idLocal: reporteExistente!.idLocal,
        idServer: reporteExistente!.idServer,
        usuarioId: reporteExistente!.usuarioId,
        departamentoId: departamentoId,
        provinciaId: provinciaId,
        municipioId: municipioId,
        comunidad: comunidad,
        departamentoNombre: departamentoNombre.isNotEmpty ? departamentoNombre : null,
        provinciaNombre: provinciaNombre.isNotEmpty ? provinciaNombre : null,
        municipioNombre: municipioNombre.isNotEmpty ? municipioNombre : null,
        fechaEvento: fechaEvento,
        horaEvento: horaEvento,
        tipoEventoId: tipoEventoId,
        coordenadaLat: latitud,
        coordenadaLon: longitud,
        descripcion: descripcion,
        categorias: categorias.isNotEmpty ? categorias : null,
        imagenes: imagenes.isNotEmpty ? imagenes : null,
        estadoId: reporteExistente!.estadoId,
        fotografiaServerPath: reporteExistente!.fotografiaServerPath,
        sincronizado: false,
        pendienteEliminacion: false,
        pendienteActualizacion: true,
        fechaCreacion: reporteExistente!.fechaCreacion,
      );

      await reporteProvider.actualizarReporte(reporteActualizado);

      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reporte actualizado'),
            backgroundColor: AppColors.completed,
          ),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } else {
      final reporte = ReporteOffline(
        usuarioId: authProvider.userId!,
        departamentoId: departamentoId,
        provinciaId: provinciaId,
        municipioId: municipioId,
        comunidad: comunidad,
        departamentoNombre: departamentoNombre.isNotEmpty ? departamentoNombre : null,
        provinciaNombre: provinciaNombre.isNotEmpty ? provinciaNombre : null,
        municipioNombre: municipioNombre.isNotEmpty ? municipioNombre : null,
        fechaEvento: fechaEvento,
        horaEvento: horaEvento,
        tipoEventoId: tipoEventoId,
        coordenadaLat: latitud,
        coordenadaLon: longitud,
        descripcion: descripcion,
        categorias: categorias.isNotEmpty ? categorias : null,
        imagenes: imagenes.isNotEmpty ? imagenes : null,
        fechaCreacion: DateTime.now(),
      );

      final result = await reporteProvider.crearReporteConEnvio(reporte);

      if (context.mounted) {
        Navigator.of(context).pop();

        String message;
        Color bgColor;

        switch (result) {
          case CrearReporteResult.enviado:
            message = 'Reporte enviado correctamente';
            bgColor = AppColors.completed;
            break;
          case CrearReporteResult.pendiente:
            message = 'Reporte guardado como pendiente';
            bgColor = AppColors.pending;
            break;
          case CrearReporteResult.borrador:
            message = 'Borrador guardado. Puede editarlo o enviarlo cuando quiera';
            bgColor = Colors.orange.shade700;
            break;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: bgColor,
          ),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  Future<void> _saveDraft(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    final reporteProvider = context.read<ReporteProvider>();

    if (!context.mounted) return;

    final reporte = ReporteOffline(
      usuarioId: authProvider.userId!,
      departamentoId: departamentoId,
      provinciaId: provinciaId,
      municipioId: municipioId,
      comunidad: comunidad,
      departamentoNombre: departamentoNombre.isNotEmpty ? departamentoNombre : null,
      provinciaNombre: provinciaNombre.isNotEmpty ? provinciaNombre : null,
      municipioNombre: municipioNombre.isNotEmpty ? municipioNombre : null,
      fechaEvento: fechaEvento,
      horaEvento: horaEvento,
      tipoEventoId: tipoEventoId,
      coordenadaLat: latitud,
      coordenadaLon: longitud,
      descripcion: descripcion,
      categorias: categorias.isNotEmpty ? categorias : null,
      imagenes: imagenes.isNotEmpty ? imagenes : null,
      esBorrador: true,
      fechaCreacion: DateTime.now(),
    );

    await reporteProvider.guardarBorrador(reporte);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Borrador guardado. Puede editarlo o enviarlo cuando quiera'),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }
}
