import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../providers/reporte_provider.dart';
import '../../../services/api_service.dart';
import '../../../services/connectivity_service.dart';

class UgrRecursoTab extends StatefulWidget {
  const UgrRecursoTab({super.key});

  @override
  State<UgrRecursoTab> createState() => UgrRecursoTabState();
}

class UgrRecursoTabState extends State<UgrRecursoTab> {
  List<Map<String, dynamic>> _documentos = [];
  List<Map<String, dynamic>> _tiposDocumento = [];
  bool _cargando = true;
  String _query = '';
  int? _filtroTipoId;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  void refresh() => _cargarDatos();

  Future<void> _cargarDatos() async {
    if (!ConnectivityService().isConnected) {
      if (mounted) setState(() => _cargando = false);
      return;
    }
    if (mounted) setState(() => _cargando = true);
    try {
      final rp = context.read<ReporteProvider>();
      final tiposFromProvider = rp.tiposRepositorio;
      final documentos = await ApiService.instance.filtrarDocumentos();
      if (mounted) {
        setState(() {
          _documentos = documentos;
          _tiposDocumento = tiposFromProvider;
          _cargando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<Map<String, dynamic>> get _documentosFiltrados {
    var list = _documentos;
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((d) {
        final nombre = _safeStr(d['nombre_documento'] ?? d['nombreDocumento']).toLowerCase();
        return nombre.contains(q);
      }).toList();
    }
    if (_filtroTipoId != null) {
      list = list.where((d) {
        final tipoId = d['id_tipo_documento'] ?? d['idTipoDocumento'];
        return tipoId == _filtroTipoId;
      }).toList();
    }
    return list;
  }

  static String _safeStr(dynamic v, [String fallback = '']) {
    if (v == null) return fallback;
    if (v is String) return v;
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return Column(
      children: [
        _buildSearchAndFilter(primary),
        Expanded(child: _buildDocumentList(primary)),
      ],
    );
  }

  Widget _buildSearchAndFilter(Color primary) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: AppColors.surface,
      child: Column(
        children: [
          TextField(
            onChanged: (value) => setState(() => _query = value),
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Buscar documento o EDAN...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              filled: true,
              fillColor: PaletteScope.of(context).background,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChip(
                  label: 'Todos',
                  selected: _filtroTipoId == null,
                  onTap: () => setState(() => _filtroTipoId = null),
                ),
                ..._tiposDocumento.map((tipo) {
                  final id = tipo['id_tipo_documento'] ?? tipo['idTipoDocumento'] ?? tipo['id'];
                  final nombre = tipo['nombre'] ?? tipo['descripcion'] ?? '';
                  return _FilterChip(
                    label: '$nombre',
                    selected: _filtroTipoId == id,
                    onTap: () => setState(() => _filtroTipoId = id),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentList(Color primary) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final list = _documentosFiltrados;
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_off, size: 64, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              _query.isNotEmpty || _filtroTipoId != null
                  ? 'Sin resultados para la búsqueda'
                  : 'No hay documentos en el repositorio',
              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final doc = list[index];
        return           _DocumentoCard(
          doc: doc,
          primary: primary,
          onVer: () => _abrirDocumento(doc),
          onDescargar: () => _descargarDocumento(doc),
        );
      },
    );
  }

  Future<void> _abrirDocumento(Map<String, dynamic> doc) async {
    try {
      final idDoc = doc['id_documento'] ?? doc['idDocumento'];
      if (idDoc == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/documentos_edan');
      await cacheDir.create(recursive: true);
      final file = File('${cacheDir.path}/$idDoc.pdf');

      if (!await file.exists()) {
        final bytes = await ApiService.instance.descargarDocRepositorio(idDoc);
        await file.writeAsBytes(bytes);
      }

      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo abrir: ${result.message}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al abrir: ${ApiService.traducirError(e)}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _descargarDocumento(Map<String, dynamic> doc) async {
    try {
      final idDoc = doc['id_documento'] ?? doc['idDocumento'];
      if (idDoc == null) return;
      final bytes = await ApiService.instance.descargarDocRepositorio(idDoc);
      final dir = await getApplicationDocumentsDirectory();
      final fileName = doc['nombre_documento'] ?? doc['nombreDocumento'] ?? 'documento_$idDoc.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Descargado: $fileName'),
            backgroundColor: AppColors.aprobado,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al descargar: ${ApiService.traducirError(e)}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? primary.withValues(alpha: 0.12) : AppColors.background,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? primary : AppColors.divider,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? primary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _DocumentoCard extends StatelessWidget {
  final Map<String, dynamic> doc;
  final Color primary;
  final VoidCallback onVer;
  final VoidCallback onDescargar;

  const _DocumentoCard({
    required this.doc,
    required this.primary,
    required this.onVer,
    required this.onDescargar,
  });

  static String _safeStr(dynamic v, [String fallback = '']) {
    if (v == null) return fallback;
    if (v is String) return v;
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final nombre = _safeStr(doc['nombre_documento'] ?? doc['nombreDocumento'], 'documento.pdf');
    final tipoRaw = doc['tipo_documento'] ?? doc['tipo'];
    final tipo = tipoRaw is Map ? (tipoRaw['nombre'] ?? '') : _safeStr(tipoRaw);
    final fecha = _safeStr(doc['fecha_documento'] ?? doc['fechaDocumento']);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.picture_as_pdf, color: AppColors.error, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nombre,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (tipo.isNotEmpty) tipo,
                      if (fecha.isNotEmpty) fecha,
                    ].join(' · '),
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.visibility, size: 18),
              color: primary,
              onPressed: onVer,
              tooltip: 'Ver',
            ),
            IconButton(
              icon: const Icon(Icons.download, size: 18),
              color: AppColors.textSecondary,
              onPressed: onDescargar,
              tooltip: 'Descargar',
            ),
          ],
        ),
      ),
    );
  }
}
