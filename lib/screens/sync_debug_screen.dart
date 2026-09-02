import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/sync_debug_collector.dart';
import '../services/sync_debug_config.dart';

/// Pantalla de depuración visual de sincronización.
///
/// Muestra cada llamada API del sync con request/response, status, fotos, errores.
/// Solo visible cuando [kSyncDebugMode] es `true`.
class SyncDebugScreen extends StatefulWidget {
  const SyncDebugScreen({super.key});

  @override
  State<SyncDebugScreen> createState() => _SyncDebugScreenState();
}

class _SyncDebugScreenState extends State<SyncDebugScreen> {
  final ScrollController _scrollController = ScrollController();
  final collector = SyncDebugCollector.instance;

  @override
  void initState() {
    super.initState();
    collector.entries.addListener(_onEntriesChanged);
  }

  @override
  void dispose() {
    collector.entries.removeListener(_onEntriesChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onEntriesChanged() {
    if (mounted) setState(() {});
    // Auto-scroll al final
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clear() {
    collector.clear();
  }

  void _exportClipboard() {
    final text = collector.exportText();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Depuración copiada al portapapeles'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = collector.entries.value;
    final stats = collector.stats;
    final palette = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Depuración Sync'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Copiar todo',
            onPressed: entries.isEmpty ? null : _exportClipboard,
            icon: const Icon(Icons.copy),
          ),
          IconButton(
            tooltip: 'Limpiar',
            onPressed: entries.isEmpty ? null : _clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: entries.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bug_report, size: 64, color: palette.outline),
                  const SizedBox(height: 16),
                  Text(
                    'Sin datos de depuración',
                    style: TextStyle(
                      fontSize: 18,
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Presiona el botón de sincronizar\npara capturar las llamadas API',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.outline,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                _buildStatsHeader(stats, palette),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      // Separador de fase
                      if (entry.metodo.isEmpty) {
                        return _buildPhaseSeparator(entry, palette);
                      }
                      return _ApiEntryCard(entry: entry);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatsHeader(SyncStats stats, ColorScheme palette) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: palette.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(Icons.analytics_outlined, size: 16, color: palette.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            '${stats.total} llamadas',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: palette.onSurface,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '✓ ${stats.ok}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.green,
              ),
            ),
          ),
          if (stats.errors > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '✗ ${stats.errors}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.red,
                ),
              ),
            ),
          ],
          const Spacer(),
          Text(
            '${stats.totalDuration.inMilliseconds}ms',
            style: TextStyle(
              fontSize: 12,
              color: palette.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseSeparator(SyncApiEntry entry, ColorScheme palette) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              color: palette.outlineVariant,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              entry.endpoint.replaceAll('─── ', '').replaceAll(' ───', ''),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: palette.primary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              color: palette.outlineVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApiEntryCard extends StatefulWidget {
  final SyncApiEntry entry;

  const _ApiEntryCard({required this.entry});

  @override
  State<_ApiEntryCard> createState() => _ApiEntryCardState();
}

class _ApiEntryCardState extends State<_ApiEntryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final palette = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(entry, palette),
            if (_expanded) _buildDetails(entry, palette),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(SyncApiEntry entry, ColorScheme palette) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          // Status badge
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _statusBgColor(entry),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              entry.statusIcon,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _statusTextColor(entry),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Method + Endpoint
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: _methodColor(entry.metodo).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        entry.metodo,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _methodColor(entry.metodo),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _shortEndpoint(entry.endpoint),
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (entry.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      entry.error!,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.red,
                        fontStyle: FontStyle.italic,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          // Duration + expand icon
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                entry.duracion != null ? '${entry.duracion!.inMilliseconds}ms' : '',
                style: TextStyle(
                  fontSize: 10,
                  color: palette.outline,
                ),
              ),
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: palette.outline,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetails(SyncApiEntry entry, ColorScheme palette) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Full endpoint
          _buildDetailRow('Endpoint completo', entry.endpoint, palette),
          if (entry.statusCode != null)
            _buildDetailRow('Status HTTP', '${entry.statusCode}', palette),
          if (entry.localidadId != null)
            _buildDetailRow('Localidad', entry.localidadId!, palette),
          if (entry.seccion != null)
            _buildDetailRow('Sección', entry.seccion!, palette),
          if (entry.fotos.isNotEmpty)
            _buildFotos(entry.fotos, palette),
          if (entry.requestBody != null)
            _buildJsonSection('Request Body', entry.requestBody!, palette),
          if (entry.requestBodyRaw != null)
            _buildDetailRow('Request (raw)', entry.requestBodyRaw!, palette),
          if (entry.responseBody != null)
            _buildJsonSection('Response Body', entry.responseBody!, palette),
          if (entry.error != null)
            _buildDetailRow('Error', entry.error!, palette),
          const SizedBox(height: 4),
          Text(
            '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
            '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
            '${entry.timestamp.second.toString().padLeft(2, '0')}.'
            '${entry.timestamp.millisecond.toString().padLeft(3, '0')}',
            style: TextStyle(
              fontSize: 9,
              color: palette.outline,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, ColorScheme palette) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: palette.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: palette.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFotos(List<String> fotos, ColorScheme palette) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fotos (${fotos.length})',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: palette.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 4,
            runSpacing: 2,
            children: fotos.map((f) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                f.split('/').last,
                style: const TextStyle(
                  fontSize: 9,
                  fontFamily: 'monospace',
                  color: Colors.blue,
                ),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildJsonSection(String title, Map<String, dynamic> json, ColorScheme palette) {
    String formatted;
    try {
      formatted = const JsonEncoder.withIndent('  ').convert(json);
    } catch (_) {
      formatted = json.toString();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: palette.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: formatted));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('JSON copiado'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: Icon(Icons.copy, size: 12, color: palette.outline),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: palette.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: palette.outlineVariant),
            ),
            child: SelectableText(
              formatted,
              style: const TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusBgColor(SyncApiEntry entry) {
    if (entry.error != null) return Colors.red.withValues(alpha: 0.15);
    if (entry.statusCode == null) return Colors.grey.withValues(alpha: 0.15);
    if (entry.isOk) return Colors.green.withValues(alpha: 0.15);
    if (entry.statusCode! >= 400 && entry.statusCode! < 500) {
      return Colors.orange.withValues(alpha: 0.15);
    }
    return Colors.red.withValues(alpha: 0.15);
  }

  Color _statusTextColor(SyncApiEntry entry) {
    if (entry.error != null) return Colors.red;
    if (entry.statusCode == null) return Colors.grey;
    if (entry.isOk) return Colors.green;
    if (entry.statusCode! >= 400 && entry.statusCode! < 500) {
      return Colors.orange;
    }
    return Colors.red;
  }

  Color _methodColor(String method) {
    switch (method.toUpperCase()) {
      case 'GET': return Colors.blue;
      case 'POST': return Colors.green;
      case 'PUT': return Colors.orange;
      case 'DELETE': return Colors.red;
      case 'PATCH': return Colors.purple;
      default: return Colors.grey;
    }
  }

  String _shortEndpoint(String endpoint) {
    // Remove query params for display
    final uri = endpoint.split('?').first;
    // Remove base URL if present
    final path = uri.replaceFirst(RegExp(r'https?://[^/]+'), '');
    return path.isEmpty ? uri : path;
  }
}
