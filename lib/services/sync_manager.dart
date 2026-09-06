import 'dart:async';

class SyncManager {
  static final SyncManager _instance = SyncManager._();
  static SyncManager get instance => _instance;
  SyncManager._();

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  final StreamController<int> _pendingCountController =
      StreamController<int>.broadcast();
  Stream<int> get pendingCountStream => _pendingCountController.stream;

  void reset() {
    _isSyncing = false;
    _pendingCountController.add(0);
  }
}