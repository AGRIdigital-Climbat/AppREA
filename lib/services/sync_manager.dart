import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/reporte.dart';
import '../models/reporte_offline.dart';
import '../services/database_helper.dart';
import '../services/api_service.dart';
import '../services/connectivity_service.dart';
import '../services/auth_service.dart';
import '../services/edan_sync_service.dart';

class SyncManager {
  static final SyncManager _instance = SyncManager._();
  static SyncManager get instance => _instance;
  SyncManager._();

  final DatabaseHelper _db = DatabaseHelper.instance;
  final ApiService _api = ApiService.instance;
  final ConnectivityService _connectivity = ConnectivityService();

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  final StreamController<int> _pendingCountController =
      StreamController<int>.broadcast();
  Stream<int> get pendingCountStream => _pendingCountController.stream;

  /// Returns count of updated reports, or -1 on error.
  Future<int> pullServerUpdates() async {
    if (!_connectivity.isConnected) {
      debugPrint('[pullServerUpdates] No hay conexion');
      return -1;
    }

    try {
      final userId = AuthService.instance.userId;
      if (userId == null) {
        debugPrint('[pullServerUpdates] userId es null');
        return -1;
      }

      debugPrint('[pullServerUpdates] Consultando mis-resumen para userId=$userId');
      final serverData = await _api.getMisResumenReportes(idUsuario: userId, limit: 200);
      debugPrint('[pullServerUpdates] Respuesta: ${serverData.length} reportes');

      final localEstados = await _db.getEstadosLocal();
      final estadoMap = <int, String>{};
      for (final e in localEstados) {
        estadoMap[e['id_estado'] as int] = e['nombre'] as String;
      }
      debugPrint('[pullServerUpdates] Catalogo de estados: ${estadoMap.length} items');

      int updatedCount = 0;
      for (final item in serverData) {
        final idReporte = item['id_reporte'] as int?;
        final idEstado = item['id_estado'] as int?;
        if (idReporte == null || idEstado == null) continue;

        final estadoNombre = estadoMap[idEstado] ?? 'Desconocido';
        debugPrint('[pullServerUpdates] Reporte $idReporte -> estado $idEstado ($estadoNombre)');
        final changed = await _db.updateEstadoByServerId(idReporte, idEstado, estadoNombre);
        if (changed) updatedCount++;
      }

      debugPrint('[pullServerUpdates] Total actualizados: $updatedCount');
      return updatedCount;
    } catch (e, stack) {
      debugPrint('[pullServerUpdates] ERROR: $e');
      debugPrint('[pullServerUpdates] STACK: $stack');
      return -1;
    }
  }

  Future<void> syncPendingReports() async {
    if (_isSyncing) return;
    if (!_connectivity.isConnected) return;

    _isSyncing = true;

    try {
      await pullServerUpdates();

      final pendingReports = await _db.getUnsyncedReports();

      if (pendingReports.isEmpty) {
        _isSyncing = false;
        return;
      }

      pendingReports.sort((a, b) => a.fechaCreacion.compareTo(b.fechaCreacion));

      int enviados = 0;
      int fallidos = 0;

      for (final reporte in pendingReports) {
        try {
          await _syncSingleReport(reporte);
          enviados++;
        } catch (e) {
          fallidos++;
          await _handleSyncError(reporte, e.toString());
        }
      }

      await _db.saveSyncHistory(enviados, fallidos);
      _pendingCountController.add(await _getPendingCount());
    } finally {
      _isSyncing = false;
    }

    try {
      await EdanSyncService.instance.sincronizar();
    } catch (e) {
      debugPrint('[syncPendingReports] Error sincronizando EDANs: $e');
    }
  }

  Future<void> _syncSingleReport(ReporteOffline reporte) async {
    final Reporte? response;

    if (reporte.idServer != null) {
      if (reporte.pendienteEliminacion) {
        await _api.deleteReporte(reporte.idServer!);
        await _db.markAsDeleted(reporte.idLocal!);
        return;
      } else if (reporte.pendienteActualizacion) {
        final data = reporte.toApiFormat();
        if (reporte.fotografiaServerPath != null) {
          data['fotografia'] = reporte.fotografiaServerPath;
        }
        response = await _api.updateReporte(reporte.idServer!, data);
        await _db.updateEstado(reporte.idLocal!, response.idEstado, response.estado?.nombre);
        await _db.markAsSynced(reporte.idLocal!, reporte.idServer!);
      } else {
        return;
      }
    } else {
      if (reporte.pendienteEliminacion) {
        await _db.markAsDeleted(reporte.idLocal!);
        return;
      }

      final hasLocalImage = reporte.imagenes != null && reporte.imagenes!.isNotEmpty;

      if (hasLocalImage) {
        final data = _buildMultipartFields(reporte);
        response = await _api.createReporteConFoto(
          filePath: reporte.imagenes!.first,
          data: data,
        );
      } else {
        final data = reporte.toApiFormat();
        if (reporte.fotografiaServerPath != null) {
          data['fotografia'] = reporte.fotografiaServerPath;
        }
        response = await _api.createReporte(data);
      }

      await _db.updateEstado(reporte.idLocal!, response.idEstado, response.estado?.nombre);
      await _db.markAsSynced(reporte.idLocal!, response.idReporte!);
    }

    if (response.fotografia != null && reporte.fotografiaServerPath == null) {
      await _db.saveFotografiaServerPath(reporte.idLocal!, response.fotografia!);
    }

    if (response.departamento?.nombre != null ||
        response.provincia?.nombre != null ||
        response.municipio?.nombre != null) {
      await _db.updateLocationNames(
        reporte.idLocal!,
        departamentoNombre: response.departamento?.nombre,
        provinciaNombre: response.provincia?.nombre,
        municipioNombre: response.municipio?.nombre,
      );
    }
  }

  Map<String, dynamic> _buildMultipartFields(ReporteOffline reporte) {
    return {
      'id_usuario': reporte.usuarioId,
      'id_departamento': reporte.departamentoId,
      'id_provincia': reporte.provinciaId,
      'id_municipio': reporte.municipioId,
      'comunidad': reporte.comunidad,
      'fecha_evento': reporte.fechaEvento,
      'hora_evento': reporte.horaEvento,
      'id_tipo_evento': reporte.tipoEventoId,
      'coordenada_lat': reporte.coordenadaLat,
      'coordenada_lon': reporte.coordenadaLon,
      'descripcion': reporte.descripcion,
      'id_estado': reporte.estadoId,
      'categorias': reporte.categorias?.toString(),
    };
  }

  Future<void> _handleSyncError(ReporteOffline reporte, String error) async {
    final newAttempts = reporte.intentosSync + 1;
    await _db.updateSyncAttempts(reporte.idLocal!, newAttempts, error);
  }

  Future<int> _getPendingCount() async {
    final pending = await _db.getUnsyncedReports();
    return pending.length;
  }

  Future<void> deleteReporte(int idLocal) async {
    final reporte = await _db.getReporteByIdLocal(idLocal);

    if (reporte != null && reporte.idServer == null) {
      await _db.markAsDeleted(idLocal);
    } else {
      await _db.markAsPendingDeletion(idLocal);
      if (_connectivity.isConnected) {
        await syncPendingReports();
      }
    }

    _pendingCountController.add(await _getPendingCount());
  }

  Future<void> updateReporte(ReporteOffline reporte) async {
    await _db.updateReporte(reporte);
    await _db.markAsPendingUpdate(reporte.idLocal!);
    _pendingCountController.add(await _getPendingCount());

    if (_connectivity.isConnected) {
      await syncPendingReports();
    }
  }

  void reset() {
    _isSyncing = false;
    _pendingCountController.add(0);
  }
}
