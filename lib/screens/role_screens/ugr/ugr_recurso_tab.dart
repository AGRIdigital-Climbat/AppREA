import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
          onVerFirma: () => _verFirma(doc),
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
void _verFirma(Map<String, dynamic> doc) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _FirmaDialog(doc: doc, primary: PaletteScope.of(context).primary),
    );
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
  final VoidCallback onVerFirma;

  const _DocumentoCard({
    required this.doc,
    required this.primary,
    required this.onVer,
    required this.onDescargar,
    required this.onVerFirma,
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
    final firmaRaw = doc['tiene_firma_digital'];
    final bool? tieneFirma = firmaRaw is bool
        ? firmaRaw
        : firmaRaw is num
            ? firmaRaw == 1
            : firmaRaw is String
                ? firmaRaw.toLowerCase() == 'true'
                : null;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
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
                if (tieneFirma != null) ...[
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (tieneFirma ? AppColors.aprobado : AppColors.pending)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              tieneFirma ? Icons.verified_user : Icons.error_outline,
                              size: 11,
                              color: tieneFirma ? AppColors.aprobado : AppColors.pending,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              tieneFirma ? 'Firmado' : 'Sin firma',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: tieneFirma ? AppColors.aprobado : AppColors.pending,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (tieneFirma == true)
                  IconButton(
                    icon: const Icon(Icons.verified_user, size: 18),
                    color: primary,
                    onPressed: onVerFirma,
                    tooltip: 'Ver firma',
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
          ],
        ),
      ),
    );
  }
}

class _FirmaDialog extends StatelessWidget {
  final Map<String, dynamic> doc;
  final Color primary;

  const _FirmaDialog({required this.doc, required this.primary});

  static Map<String, dynamic> _resultadoFirma(Map<String, dynamic> d) {
    final raw = d['resultado_firma'] ?? d['resultadoFirma'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final dec = jsonDecode(raw);
        if (dec is Map) return Map<String, dynamic>.from(dec);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  static String _fecha(dynamic valor) {
    if (valor == null) return '';
    final s = valor.toString();
    if (s.trim().isEmpty) return '';
    try {
      final dt = DateTime.parse(s);
      return DateFormat('dd/MM/yyyy HH:mm').format(dt.toLocal());
    } catch (_) {
      return s;
    }
  }

  static String _cert(dynamic cert, String key, [String fallback = '']) {
    if (cert is! Map) return fallback;
    final v = cert[key];
    if (v == null) return fallback;
    final s = v.toString().trim();
    return s.isEmpty ? fallback : s;
  }

  static String _safeStr(dynamic v, [String fallback = '']) {
    if (v == null) return fallback;
    if (v is String) return v;
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final rf = _resultadoFirma(doc);
    final firmaOk = rf['finalizado'] != false && rf['tipoRespuesta'] == 'Exito';
    final numFirmas = rf['cantidad_firmas'];
    final firmasRaw = rf['firmas'];
    final firmas = firmasRaw is List
        ? firmasRaw.whereType<Map>().map((f) => Map<String, dynamic>.from(f)).toList()
        : <Map<String, dynamic>>[];
    final cantidad = (numFirmas is num && numFirmas.toInt() > 0)
        ? numFirmas.toInt()
        : firmas.length;
    final mensaje = rf['mensaje']?.toString() ?? '';
    final codigoHash = rf['codigoHash']?.toString() ?? '';
    final fechaValidacion =
        _fecha(doc['fecha_validacion_firma'] ?? doc['fechaValidacionFirma']);
    final nombreDoc = _safeStr(
      doc['nombre_documento'] ?? doc['nombreDocumento'],
      'Documento',
    );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Información de la firma digital',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(
                      Icons.close,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                nombreDoc,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _chipResumen(
                    text: firmaOk ? 'Firma válida' : 'Revisar firma',
                    color: firmaOk ? AppColors.aprobado : AppColors.pending,
                    icon: firmaOk ? Icons.check_circle : Icons.error_outline,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Firmas detectadas: $cantidad',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              if (fechaValidacion.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Validado: $fechaValidacion',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
              if (mensaje.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  mensaje,
                  style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                ),
              ],
              if (codigoHash.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text(
                  'Hash del documento',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  codigoHash,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
              if (firmas.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text(
                    'No hay información detallada de firmas registrada.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                )
              else ...[
                const SizedBox(height: 4),
                for (var i = 0; i < firmas.length; i++) _firmaCard(i, firmas[i]),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipResumen({
    required String text,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _firmaCard(int index, Map<String, dynamic> firma) {
    final valida = firma['noModificado'] == true && firma['cadenaConfianza'] == true;
    final cert = firma['certificado'];
    final firmante = _cert(cert, 'nombreSignatario');
    final ciSign = _cert(cert, 'ciSignatario');
    final ciNit = ciSign.isNotEmpty ? ciSign : _cert(cert, 'nitSignatario');

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Firma ${index + 1}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              _chipResumen(
                text: valida ? 'Válida' : 'Rechazada',
                color: valida ? AppColors.aprobado : AppColors.error,
                icon: valida ? Icons.check_circle : Icons.cancel,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _filaCert('Firmante', firmante),
          _filaCert('CI / NIT', ciNit),
          _filaCert('Cargo', _cert(cert, 'cargoSignatario')),
          _filaCert('Organización', _cert(cert, 'organizacionSignatario')),
          _filaCert('Correo electrónico', _cert(cert, 'correoElectronicoSignatario')),
          _filaCert('Fecha de firma', _fecha(firma['fechaFirma'])),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _checkChip('No modificado', firma['noModificado']),
              _checkChip('Cadena de confianza', firma['cadenaConfianza']),
              _checkChip('Firmado en vigencia', firma['firmadoDuranteVigencia']),
              _checkChip('Sello de tiempo', firma['timeStamp']),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filaCert(String label, String value) {
    final v = value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v.isEmpty ? '—' : v,
              style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkChip(String label, dynamic valor) {
    final bool? ok = valor is bool ? valor : (valor is num ? valor == 1 : null);
    final color = ok == null
        ? AppColors.textSecondary
        : ok
            ? AppColors.aprobado
            : AppColors.error;
    final text = ok == null ? '$label: n/d' : (ok ? '$label: Sí' : '$label: No');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
