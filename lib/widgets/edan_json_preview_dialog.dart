import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';
import '../models/edan.dart';
import '../services/edan/edan_documento_service.dart';
import '../services/edan/edan_localidades_envio_v2_service.dart';

/// Muestra un dialog con el JSON completo que se enviaría en POST/PUT `/documento`.
///
/// Se invoca con un long press en las tarjetas de localidad.
class EdanJsonPreviewDialog {
  EdanJsonPreviewDialog._();

  static Future<void> show(BuildContext context, EdanLocalidad localidad) async {
    final nombre = localidad.nombre.isNotEmpty ? localidad.nombre : 'Sin nombre';

    showDialog(
      context: context,
      builder: (_) => _JsonPreviewBody(localidad: localidad, titulo: nombre),
    );
  }
}

class _JsonPreviewBody extends StatefulWidget {
  final EdanLocalidad localidad;
  final String titulo;

  const _JsonPreviewBody({required this.localidad, required this.titulo});

  @override
  State<_JsonPreviewBody> createState() => _JsonPreviewBodyState();
}

class _JsonPreviewBodyState extends State<_JsonPreviewBody> {
  String? _jsonString;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _generar();
  }

  Future<void> _generar() async {
    try {
      final sincV2 = EdanLocalidadesEnvioV2Service();
      await sincV2.cargarSeccionesDesdeSQLite(widget.localidad);
      final doc =
          await EdanDocumentoService.instance.construirDocumento(widget.localidad);
      final encoder = JsonEncoder.withIndent('  ');
      setState(() {
        _jsonString = encoder.convert(doc);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
          maxWidth: 500,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  Icon(Icons.data_object, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'JSON POST/PUT',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.titulo,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Copiar',
                    onPressed: _jsonString != null
                        ? () {
                            Clipboard.setData(
                                ClipboardData(text: _jsonString!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('JSON copiado al portapapeles'),
                                backgroundColor: AppColors.primary,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // ── Body ──
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Generando JSON...'),
                        ],
                      ),
                    )
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.error_outline,
                                  color: AppColors.error, size: 32),
                              const SizedBox(height: 8),
                              Text(
                                'Error al generar JSON',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _error!,
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.textSecondary),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(
                            _jsonString!,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              height: 1.5,
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
