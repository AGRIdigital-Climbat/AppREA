import 'dart:async';
import 'package:flutter/material.dart';
import '../models/reporte_offline.dart';
import '../models/departamento.dart';
import '../models/provincia.dart';
import '../models/municipio.dart';
import '../services/database_helper.dart';
import '../services/api_service.dart';
import '../services/sync_manager.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';

class ReporteProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final ApiService _api = ApiService.instance;
  final SyncManager _syncManager = SyncManager.instance;

  List<ReporteOffline> _reportes = [];
  List<Departamento> _departamentos = [];
  List<Provincia> _provincias = [];
  List<Municipio> _municipios = [];
  int _pendingCount = 0;
  bool _isLoading = false;
  bool _isLoadingProvincias = false;
  bool _isLoadingMunicipios = false;

  List<ReporteOffline> get reportes => _reportes;
  List<Departamento> get departamentos => _departamentos;
  List<Provincia> get provincias => _provincias;
  List<Municipio> get municipios => _municipios;
  int get pendingCount => _pendingCount;
  bool get isLoading => _isLoading;
  bool get isLoadingProvincias => _isLoadingProvincias;
  bool get isLoadingMunicipios => _isLoadingMunicipios;

  StreamSubscription<int>? _pendingSubscription;

  Future<void> initialize() async {
    _pendingSubscription =
        _syncManager.pendingCountStream.listen((count) {
      _pendingCount = count;
      notifyListeners();
    });

    await loadReportes();
    if (AuthService.instance.isAuthenticated) {
      await loadGeography();
    }
  }

  Future<void> loadReportes() async {
    _isLoading = true;
    notifyListeners();

    final userId = AuthService.instance.userId;
    if (userId != null) {
      _reportes = await _db.getReportes(userId);
      _pendingCount = _reportes.where((r) => r.necesitaSync).length;
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadGeography() async {
    try {
      _departamentos = await _api.getDepartamentos();
      notifyListeners();
    } catch (e) {
      // Manejar error silenciosamente
    }
  }

  Future<void> loadProvincias(int idDepartamento) async {
    _isLoadingProvincias = true;
    _provincias = [];
    _municipios = [];
    notifyListeners();
    try {
      _provincias = await _api.getProvincias(idDepartamento: idDepartamento);
    } catch (e) {
      // Manejar error silenciosamente
    }
    _isLoadingProvincias = false;
    notifyListeners();
  }

  Future<void> loadMunicipios(int idProvincia) async {
    _isLoadingMunicipios = true;
    _municipios = [];
    notifyListeners();
    try {
      _municipios = await _api.getMunicipios(idProvincia: idProvincia);
    } catch (e) {
      // Manejar error silenciosamente
    }
    _isLoadingMunicipios = false;
    notifyListeners();
  }

  Future<void> crearReporte(ReporteOffline reporte) async {
    await _db.insertReporte(reporte);
    _pendingCount++;
    notifyListeners();

    await loadReportes();

    if (ConnectivityService().isConnected) {
      await _syncManager.syncPendingReports();
    }
  }

  Future<void> eliminarReporte(int idLocal) async {
    await _syncManager.deleteReporte(idLocal);
    await loadReportes();
  }

  Future<void> sincronizarPendientes() async {
    await _syncManager.syncPendingReports();
    await loadReportes();
  }

  @override
  void dispose() {
    _pendingSubscription?.cancel();
    super.dispose();
  }
}
