import 'dart:async';
import '../models/reporte_offline.dart';
import '../services/database_helper.dart';
import '../services/api_service.dart';
import '../services/connectivity_service.dart';

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

  Future<void> syncPendingReports() async {
    if (_isSyncing) return;
    if (!_connectivity.isConnected) return;

    _isSyncing = true;

    try {
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
  }

  Future<void> _syncSingleReport(ReporteOffline reporte) async {
    if (reporte.idServer != null) {
      if (reporte.pendienteEliminacion) {
        await _api.deleteReporte(reporte.idServer!);
        await _db.markAsDeleted(reporte.idLocal!);
      } else if (reporte.pendienteActualizacion) {
        await _api.updateReporte(reporte.idServer!, reporte.toApiFormat());
        await _db.markAsSynced(reporte.idLocal!, reporte.idServer!);
      }
    } else {
      final response = await _api.createReporte(reporte.toApiFormat());
      await _db.markAsSynced(reporte.idLocal!, response.idReporte!);
    }
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
    await _db.markAsPendingDeletion(idLocal);
    _pendingCountController.add(await _getPendingCount());

    if (_connectivity.isConnected) {
      await syncPendingReports();
    }
  }

  Future<void> updateReporte(ReporteOffline reporte) async {
    await _db.updateReporte(reporte);
    await _db.markAsPendingUpdate(reporte.idLocal!);
    _pendingCountController.add(await _getPendingCount());

    if (_connectivity.isConnected) {
      await syncPendingReports();
    }
  }
}
