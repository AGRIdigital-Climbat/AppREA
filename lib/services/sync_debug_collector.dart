import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'sync_debug_config.dart';

/// Singleton que acumula entradas de depuración de cada llamada API
/// durante el proceso de sincronización.
///
/// Solo captura cuando [kSyncDebugMode] es `true`.
class SyncDebugCollector {
  SyncDebugCollector._();

  static final SyncDebugCollector instance = SyncDebugCollector._();

  /// Entradas de la sesión de sync actual.
  final ValueNotifier<List<SyncApiEntry>> entries = ValueNotifier([]);

  /// Fase actual (para asociar entradas de API a fases).
  String _currentPhase = '';
  String get currentPhase => _currentPhase;

  /// Timestamp del inicio del sync actual.
  DateTime? _syncStartTime;

  /// Si hay un sync en curso.
  bool get isActive => _syncStartTime != null;

  /// Inicia una nueva sesión de captura.
  void startSession() {
    _syncStartTime = DateTime.now();
    entries.value = [];
    _currentPhase = '';
  }

  /// Finaliza la sesión de captura.
  void endSession() {
    _syncStartTime = null;
    _currentPhase = '';
  }

  /// Establece la fase actual.
  void setPhase(String phase) {
    _currentPhase = phase;
  }

  /// Agrega una entrada de API. No-op si [kSyncDebugMode] es `false`.
  void add(SyncApiEntry entry) {
    if (!kSyncDebugMode) return;
    final current = List<SyncApiEntry>.from(entries.value);
    current.add(entry);
    entries.value = current;
  }

  /// Agrega una entrada de fase (marcador visual, no es una API).
  void addFase(String titulo) {
    if (!kSyncDebugMode) return;
    _currentPhase = titulo;
    add(SyncApiEntry(
      fase: titulo,
      metodo: '',
      endpoint: '─── $titulo ───',
      timestamp: DateTime.now(),
    ));
  }

  /// Agrega un diagnóstico local (sin llamada API) que muestra el estado
  /// de las localidades antes de intentar enviar o recibir datos.
  void addDiagnostico(String titulo, Map<String, dynamic> datos) {
    if (!kSyncDebugMode) return;
    add(SyncApiEntry(
      fase: _currentPhase,
      metodo: 'DIAGNÓSTICO',
      endpoint: titulo,
      timestamp: DateTime.now(),
      requestBody: datos,
    ));
  }

  /// Agrega un diagnóstico local POR ÍTEM (localidad → sección), con detalle
  /// estructurado ([detalleDiagnostico]) para que la pantalla de debug lo
  /// renderice de forma expandible en lugar de un JSON plano.
  void addDiagnosticoPerItem(String titulo, Map<String, dynamic> datos) {
    if (!kSyncDebugMode) return;
    add(SyncApiEntry(
      fase: _currentPhase,
      metodo: 'DIAGNÓSTICO',
      endpoint: titulo,
      timestamp: DateTime.now(),
      requestBody: datos,
      detalleDiagnostico: datos,
    ));
  }

  /// Agrega una entrada de diagnóstico por item a partir de una estructura ya
  /// construida (por localidad → sección), reutilizando el builder común.
  void addDiagnosticoItemDetalle(Map<String, dynamic> detalle) {
    if (!kSyncDebugMode) return;
    add(SyncApiEntry(
      fase: _currentPhase,
      metodo: 'DIAGNÓSTICO',
      endpoint: 'Ítem: ${detalle['nombre'] ?? detalle['id_local'] ?? ''}',
      timestamp: DateTime.now(),
      requestBody: detalle,
      detalleDiagnostico: detalle,
      localidadId: detalle['id_local']?.toString(),
    ));
  }

  /// Limpia todas las entradas.
  void clear() {
    entries.value = [];
    _currentPhase = '';
    _syncStartTime = null;
  }

  /// Exporta todas las entradas como texto formateado.
  String exportText() {
    final buffer = StringBuffer();
    buffer.writeln('=== DEPURACIÓN SYNC - ${DateTime.now()} ===');
    buffer.writeln();

    for (final entry in entries.value) {
      // Saltar separadores de fase
      if (entry.metodo.isEmpty) {
        buffer.writeln('');
        buffer.writeln('═══════════════════════════════════════');
        buffer.writeln('  ${entry.endpoint}');
        buffer.writeln('═══════════════════════════════════════');
        continue;
      }

      buffer.writeln('[${entry.statusIcon}] ${entry.metodo} ${entry.endpoint}');
      buffer.writeln('   Status: ${entry.statusCode ?? "N/A"} | ${entry.duracion?.inMilliseconds ?? "?"}ms');
      if (entry.error != null) buffer.writeln('   Error: ${entry.error}');
      if (entry.localidadId != null) buffer.writeln('   Localidad: ${entry.localidadId}');
      if (entry.seccion != null) buffer.writeln('   Sección: ${entry.seccion}');
      if (entry.fotos.isNotEmpty) buffer.writeln('   Fotos: ${entry.fotos.join(", ")}');
      if (entry.requestBody != null) {
        buffer.writeln('   Request:');
        buffer.writeln('   ${const JsonEncoder.withIndent('   ').convert(entry.requestBody)}');
      }
      if (entry.requestBodyRaw != null) {
        buffer.writeln('   Request (raw): ${entry.requestBodyRaw}');
      }
      if (entry.responseBody != null) {
        buffer.writeln('   Response:');
        buffer.writeln('   ${const JsonEncoder.withIndent('   ').convert(entry.responseBody)}');
      }
      buffer.writeln();
    }

    // Resumen
    final allEntries = entries.value.where((e) => e.metodo.isNotEmpty).toList();
    final ok = allEntries.where((e) => e.isOk).length;
    final errors = allEntries.where((e) => e.isError).length;
    buffer.writeln('═══════════════════════════════════════');
    buffer.writeln('Total: ${allEntries.length} llamadas API | ✓ $ok | ✗ $errors');
    buffer.writeln('═══════════════════════════════════════');

    return buffer.toString();
  }

  /// Estadísticas resumidas.
  SyncStats get stats {
    final allEntries = entries.value.where((e) => e.metodo.isNotEmpty).toList();
    final ok = allEntries.where((e) => e.isOk).length;
    final errors = allEntries.where((e) => e.isError).length;
    final totalDuration = allEntries.fold<Duration>(
      Duration.zero,
      (sum, e) => sum + (e.duracion ?? Duration.zero),
    );
    return SyncStats(
      total: allEntries.length,
      ok: ok,
      errors: errors,
      totalDuration: totalDuration,
    );
  }
}

class SyncStats {
  final int total;
  final int ok;
  final int errors;
  final Duration totalDuration;

  SyncStats({
    required this.total,
    required this.ok,
    required this.errors,
    required this.totalDuration,
  });
}
