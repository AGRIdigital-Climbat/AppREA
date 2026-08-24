import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/theme.dart';
import '../../../models/edan.dart';
import '../../../services/api_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/database_helper.dart';

class UgrRecursoUploadScreen extends StatefulWidget {
  final Edan edan;

  const UgrRecursoUploadScreen({
    super.key,
    required this.edan,
  });

  @override
  State<UgrRecursoUploadScreen> createState() => _UgrRecursoUploadScreenState();
}

class _UgrRecursoUploadScreenState extends State<UgrRecursoUploadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _observacionesController = TextEditingController();
  File? _selectedFile;
  String? _fileName;
  int? _selectedTipoId;
  List<Map<String, dynamic>> _tiposDocumento = [];
  bool _cargandoTipos = false;
  bool _subiendo = false;

  Edan get edan => widget.edan;

  @override
  void initState() {
    super.initState();
    _cargarTiposDocumento();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  Future<void> _cargarTiposDocumento() async {
    if (mounted) setState(() => _cargandoTipos = true);
    try {
      List<Map<String, dynamic>> tipos = [];
      if (ConnectivityService().isConnected) {
        try {
          tipos = await ApiService.instance.listarTiposRepositorio();
          debugPrint('[UploadTipos] API returned ${tipos.length} items');
          if (tipos.isNotEmpty) debugPrint('[UploadTipos] First item keys: ${tipos.first.keys.toList()}');
        } catch (e) {
          debugPrint('[UploadTipos] API failed: $e, trying cache...');
          tipos = await DatabaseHelper.instance.getTiposRepositorioLocal();
          debugPrint('[UploadTipos] Cache returned ${tipos.length} items');
        }
      } else {
        tipos = await DatabaseHelper.instance.getTiposRepositorioLocal();
        debugPrint('[UploadTipos] Offline, cache returned ${tipos.length} items');
      }
      if (mounted) {
        setState(() {
          _tiposDocumento = tipos;
          _cargandoTipos = false;
        });
      }
    } catch (e) {
      debugPrint('[UploadTipos] Error: $e');
      if (mounted) setState(() => _cargandoTipos = false);
    }
  }

  Future<void> _seleccionarArchivo() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result.isNotEmpty) {
        final file = result.first;
        if (file.path != null) {
          setState(() {
            _selectedFile = File(file.path!);
            _fileName = file.name;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al seleccionar archivo: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _subirDocumento() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona un archivo PDF primero.'),
          backgroundColor: AppColors.pending,
        ),
      );
      return;
    }

    if (_selectedTipoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona un tipo de documento.'),
          backgroundColor: AppColors.pending,
        ),
      );
      return;
    }

    if (edan.idDepartamento == null || edan.idProvincia == null || edan.idMunicipio == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El EDAN no tiene ubicación completa.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (!ConnectivityService().isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sin conexión. Verifica tu red y reintenta.'),
          backgroundColor: AppColors.pending,
        ),
      );
      return;
    }

    setState(() => _subiendo = true);

    try {
      final fechaDocumento = DateFormat('yyyy-MM-dd').format(DateTime.now());

      await ApiService.instance.subirDocumentoEdan(
        idEdan: edan.idEdan!,
        filePath: _selectedFile!.path,
        idTipoDocumento: _selectedTipoId!,
        nombreDocumento: _nombreController.text.trim(),
        fechaDocumento: fechaDocumento,
        idDepartamento: edan.idDepartamento!,
        idProvincia: edan.idProvincia!,
        idMunicipio: edan.idMunicipio!,
        observaciones: _observacionesController.text.trim().isEmpty
            ? null
            : _observacionesController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Documento subido exitosamente.'),
            backgroundColor: AppColors.aprobado,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al subir: ${ApiService.traducirError(e)}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return Scaffold(
      backgroundColor: PaletteScope.of(context).background,
      appBar: AppBar(
        title: const Text(
          'Subir documento',
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
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.assignment, color: primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'EDAN: ${edan.codigoEdan}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _seleccionarArchivo,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _selectedFile != null
                      ? AppColors.aprobado.withValues(alpha: 0.08)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _selectedFile != null
                        ? AppColors.aprobado
                        : AppColors.divider,
                    width: _selectedFile != null ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _selectedFile != null
                          ? Icons.picture_as_pdf
                          : Icons.cloud_upload_outlined,
                      size: 48,
                      color: _selectedFile != null
                          ? AppColors.aprobado
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _selectedFile != null
                          ? _fileName!
                          : 'Seleccionar archivo PDF',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _selectedFile != null
                            ? AppColors.aprobado
                            : AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedFile != null
                          ? 'Toca para cambiar'
                          : 'Toca para seleccionar',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Nombre del documento',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nombreController,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              decoration: InputDecoration(
                hintText: 'Ej: Resolución Alcaldía No. 001',
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.all(12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Tipo de documento',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            if (_cargandoTipos)
              const Center(child: CircularProgressIndicator(strokeWidth: 2))
            else
              DropdownButtonFormField<int>(
                initialValue: _selectedTipoId,
                isExpanded: true,
                decoration: InputDecoration(
                  hintText: 'Seleccionar tipo...',
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: primary, width: 1.5),
                  ),
                ),
                items: _tiposDocumento.map((tipo) {
                  final id = tipo['id_tipo_documento'] ?? tipo['id'];
                  final nombre = tipo['nombre'] ?? 'Sin nombre';
                  return DropdownMenuItem<int>(
                    value: id as int?,
                    child: Text(
                      '$nombre',
                      style: const TextStyle(fontSize: 14),
                    ),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _selectedTipoId = value),
              ),
            const SizedBox(height: 20),
            const Text(
              'Observaciones (opcional)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _observacionesController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Notas sobre el documento...',
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.all(12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _subiendo ? null : _subirDocumento,
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
                child: _subiendo
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Subir documento'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
