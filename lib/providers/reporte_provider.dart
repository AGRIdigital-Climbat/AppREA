import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/reporte.dart';
import '../models/reporte_offline.dart';
import '../models/departamento.dart';
import '../models/provincia.dart';
import '../models/municipio.dart';
import '../models/municipio_geojson.dart';
import '../services/database_helper.dart';
import '../services/api_service.dart';
import '../services/sync_manager.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';

enum CrearReporteResult { enviado, pendiente, borrador }

class ReporteProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final ApiService _api = ApiService.instance;
  final SyncManager _syncManager = SyncManager.instance;

  List<ReporteOffline> _reportes = [];
  List<Departamento> _departamentos = [];
  List<Provincia> _provincias = [];
  List<Municipio> _municipios = [];
  List<Estado> _estados = [];
  List<Categoria> _categorias = [];
  List<TipoEvento> _tiposEvento = [];
  MunicipioGeojson? _municipioGeojson;
  int _pendingCount = 0;
  bool _isLoading = false;
  bool _isLoadingProvincias = false;
  bool _isLoadingMunicipios = false;

  List<ReporteOffline> get reportes => _reportes;
  List<Departamento> get departamentos => _departamentos;
  List<Provincia> get provincias => _provincias;
  List<Municipio> get municipios => _municipios;
  List<Estado> get estados => _estados;
  List<Categoria> get categorias => _categorias;
  List<TipoEvento> get tiposEvento => _tiposEvento;
  MunicipioGeojson? get municipioGeojson => _municipioGeojson;
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
    await loadCatalogsLocal();

    if (AuthService.instance.isAuthenticated) {
      await loadGeography();

      if (_reportes.isEmpty) {
        await fetchAndCacheCatalogs();
        await syncAllFromServer();
      } else {
        await fetchAndCacheCatalogs();
        _syncManager.pullServerUpdates().then((_) => loadReportes());
      }
      descargarImagenesPendientes();
    }
  }

  Future<void> loadReportes() async {
    _isLoading = true;
    notifyListeners();

    try {
      final userId = AuthService.instance.userId;
      if (userId != null) {
        _reportes = await _db.getReportes(userId);
        _pendingCount = _reportes.where((r) => r.necesitaSync).length;
      }
    } catch (e) {
      debugPrint('[loadReportes] Error: $e');
      _reportes = [];
      _pendingCount = 0;
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

  Future<void> loadMunicipios(int idProvincia, int idDepartamento) async {
    _isLoadingMunicipios = true;
    _municipios = [];
    notifyListeners();
    try {
      _municipios = await _api.getMunicipios(
        idProvincia: idProvincia,
        idDepartamento: idDepartamento,
      );
    } catch (e) {
      // Manejar error silenciosamente
    }
    _isLoadingMunicipios = false;
    notifyListeners();
  }

  Future<void> loadCatalogsLocal() async {
    try {
      final estadosData = await _db.getEstadosLocal();
      _estados = estadosData.map((e) => Estado.fromJson(e)).toList();
    } catch (_) {
      _estados = [];
    }

    try {
      final categoriasData = await _db.getCategoriasLocal();
      _categorias = categoriasData.map((c) => Categoria.fromJson(c)).toList();
    } catch (_) {
      _categorias = [];
    }

    try {
      final tiposData = await _db.getTiposEventoLocal();
      _tiposEvento = tiposData.map((t) => TipoEvento.fromJson(t)).toList();
    } catch (_) {
      _tiposEvento = [];
    }

    try {
      final idMunicipio = AuthService.instance.currentToken?.idMunicipio;
      if (idMunicipio != null) {
        final geojsonRow = await _db.getMunicipioGeojsonLocal(idMunicipio);
        if (geojsonRow != null && geojsonRow['geojson'] != null) {
          _municipioGeojson = MunicipioGeojson.fromJson(
            jsonDecode(geojsonRow['geojson'] as String) as Map<String, dynamic>,
          );
        }
      }
    } catch (_) {
      _municipioGeojson = null;
    }

    notifyListeners();
  }

  Future<Map<String, int>> fetchAndCacheCatalogs() async {
    int estadosCount = 0;
    int categoriasCount = 0;
    int tiposCount = 0;

    try {
      final estados = await _api.getEstados();
      _estados = estados;
      await _db.saveEstados(
          estados.map((e) => {'id_estado': e.idEstado, 'nombre': e.nombre, 'descripcion': e.descripcion, 'orden': e.orden}).toList());
      estadosCount = estados.length;
    } catch (_) {}

    try {
      final categorias = await _api.getCategorias();
      _categorias = categorias;
      await _db.saveCategorias(
          categorias.map((c) => {'id_categoria': c.idCategoria, 'nombre': c.nombre, 'descripcion': c.descripcion, 'orden': c.orden}).toList());
      categoriasCount = categorias.length;
    } catch (_) {}

    try {
      final tipos = await _api.getTiposEvento();
      _tiposEvento = tipos;
      await _db.saveTiposEvento(
          tipos.map((t) => {'id_tipo_evento': t.idTipoEvento, 'nombre': t.nombre}).toList());
      tiposCount = tipos.length;
    } catch (_) {}

    await _downloadAndCacheMunicipioGeojson();

    notifyListeners();
    return {'estados': estadosCount, 'categorias': categoriasCount, 'tipos': tiposCount};
  }

  Future<void> _downloadAndCacheMunicipioGeojson() async {
    try {
      final token = AuthService.instance.currentToken;
      if (token == null || token.idMunicipio == null) return;

      List<Municipio> municipios;
      try {
        municipios = await _api.getMunicipios(
          idProvincia: token.idProvincia,
          idDepartamento: token.idDepartamento,
        );
      } catch (_) {
        municipios = await _api.getMunicipios();
      }

      Municipio? match;
      for (final m in municipios) {
        if (m.id == token.idMunicipio) {
          match = m;
          break;
        }
      }
      if (match == null) return;

      final feature = await _api.getMunicipioGeojson(match.codigoIne);
      final geojson = MunicipioGeojson.fromJson(feature);

      await _db.saveMunicipioGeojson(
        municipioId: token.idMunicipio!,
        codigoIne: match.codigoIne,
        nombre: geojson.nombre,
        geojson: jsonEncode(feature),
      );

      _municipioGeojson = geojson;
      notifyListeners();
    } catch (_) {
      // Silencioso: no rompe el flujo de catálogos
    }
  }

  String getEstadoNombre(int id) {
    final match = _estados.where((e) => e.idEstado == id);
    return match.isNotEmpty ? match.first.nombre : 'Desconocido';
  }

  String getTipoEventoNombre(int id) {
    final match = _tiposEvento.where((t) => t.idTipoEvento == id);
    return match.isNotEmpty ? match.first.nombre : 'Desconocido';
  }

  String getCategoriaNombre(int id) {
    final match = _categorias.where((c) => c.idCategoria == id);
    return match.isNotEmpty ? match.first.nombre : 'Otra';
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

  Future<CrearReporteResult> crearReporteConEnvio(ReporteOffline reporte) async {
    await _db.insertReporte(reporte);

    final userId = AuthService.instance.userId;
    if (userId == null) {
      _pendingCount++;
      notifyListeners();
      await loadReportes();
      return CrearReporteResult.pendiente;
    }

    final reportes = await _db.getReportes(userId);
    final inserted = reportes.lastWhere(
      (r) => r.fechaCreacion.isAtSameMomentAs(reporte.fechaCreacion),
      orElse: () => reporte,
    );

    if (!ConnectivityService().isConnected || inserted.idLocal == null) {
      _pendingCount++;
      notifyListeners();
      await loadReportes();
      return CrearReporteResult.pendiente;
    }

    try {
      final hasLocalImage = inserted.imagenes != null && inserted.imagenes!.isNotEmpty;

      if (hasLocalImage) {
        final data = inserted.toApiFormat();
        data['categorias'] = inserted.categorias?.toString();
        final response = await _api.createReporteConFoto(
          filePath: inserted.imagenes!.first,
          data: data,
        );
        await _db.updateEstado(inserted.idLocal!, response.idEstado, response.estado?.nombre);
        await _db.markAsSynced(inserted.idLocal!, response.idReporte!);
        if (response.fotografia != null) {
          await _db.saveFotografiaServerPath(inserted.idLocal!, response.fotografia!);
        }
      } else {
        final data = inserted.toApiFormat();
        if (inserted.fotografiaServerPath != null) {
          data['fotografia'] = inserted.fotografiaServerPath;
        }
        final response = await _api.createReporte(data);
        await _db.updateEstado(inserted.idLocal!, response.idEstado, response.estado?.nombre);
        await _db.markAsSynced(inserted.idLocal!, response.idReporte!);
      }

      await loadReportes();
      return CrearReporteResult.enviado;
    } catch (e) {
      debugPrint('[crearReporteConEnvio] Error enviando reporte: $e');
      _pendingCount++;
      notifyListeners();
      await loadReportes();
      return CrearReporteResult.pendiente;
    }
  }

  Future<void> actualizarReporte(ReporteOffline reporte) async {
    await _db.updateReporte(reporte);

    if (ConnectivityService().isConnected) {
      await _syncManager.syncPendingReports();
    }

    await loadReportes();
  }

  Future<void> guardarBorrador(ReporteOffline reporte) async {
    final borrador = ReporteOffline(
      idLocal: reporte.idLocal,
      idServer: reporte.idServer,
      usuarioId: reporte.usuarioId,
      departamentoId: reporte.departamentoId,
      provinciaId: reporte.provinciaId,
      municipioId: reporte.municipioId,
      comunidad: reporte.comunidad,
      departamentoNombre: reporte.departamentoNombre,
      provinciaNombre: reporte.provinciaNombre,
      municipioNombre: reporte.municipioNombre,
      fechaEvento: reporte.fechaEvento,
      horaEvento: reporte.horaEvento,
      tipoEventoId: reporte.tipoEventoId,
      coordenadaLat: reporte.coordenadaLat,
      coordenadaLon: reporte.coordenadaLon,
      descripcion: reporte.descripcion,
      estadoId: reporte.estadoId,
      categorias: reporte.categorias,
      imagenes: reporte.imagenes,
      esBorrador: true,
      sincronizado: false,
      pendienteEliminacion: false,
      pendienteActualizacion: false,
      fechaCreacion: reporte.fechaCreacion,
    );

    if (borrador.idLocal != null) {
      await _db.updateReporte(borrador);
    } else {
      await _db.insertReporte(borrador);
    }
    await loadReportes();
  }

  Future<void> eliminarReporte(int idLocal) async {
    await _syncManager.deleteReporte(idLocal);
    await loadReportes();
  }

  Future<void> sincronizarPendientes() async {
    await _syncManager.syncPendingReports();
    await loadReportes();
    descargarImagenesPendientes();
  }

  Future<void> descargarImagenesPendientes() async {
    try {
      final userId = AuthService.instance.userId;
      if (userId == null) return;

      final reportes = await _db.getReportesSinDescargar(userId);
      if (reportes.isEmpty) return;

      final appDir = await getApplicationDocumentsDirectory();
      final reportesDir = Directory('${appDir.path}/reportes');
      if (!await reportesDir.exists()) {
        await reportesDir.create(recursive: true);
      }

      for (final reporte in reportes) {
        if (reporte.fotografiaServerPath == null ||
            reporte.fotografiaServerPath!.isEmpty) continue;

        try {
          final serverPath = reporte.fotografiaServerPath!;
          final fileName = '${reporte.idServer}_${serverPath.split('/').last}';
          final savePath = '${reportesDir.path}/$fileName';

          final downloaded = await _api.downloadImage(serverPath, savePath);
          if (downloaded != null) {
            await _db.updateReporteLocalImage(reporte.idServer!, downloaded);
            await _db.marcarImagenDescargada(reporte.idLocal!);
          }
        } catch (_) {
          // No marcar — queda pendiente para el próximo intento
        }
      }
    } catch (_) {
      // Error general — no bloquea la app
    }
  }

  Future<int> refreshFromServer() async {
    final result = await syncAllFromServer();
    await fetchAndCacheCatalogs();
    await loadCatalogsLocal();
    descargarImagenesPendientes();
    return result['reportes'] ?? 0;
  }

  Future<Map<String, int>> syncAllFromServer() async {
    int reportesCount = 0;
    int imagenesCount = 0;

    try {
      final userId = AuthService.instance.userId;
      if (userId == null) return {'reportes': 0, 'imagenes': 0};

      final appDir = await getApplicationDocumentsDirectory();
      final reportesDir = Directory('${appDir.path}/reportes');

      int skip = 0;
      const limit = 50;
      bool hasMore = true;

      while (hasMore) {
        final batch = await _api.getMisReportes(
          idUsuario: userId,
          skip: skip,
          limit: limit,
        );

        if (batch.isEmpty) {
          hasMore = false;
          break;
        }

        for (final data in batch) {
          await _db.upsertReportFromServer(userId, data);
          reportesCount++;

          final serverPath = data['fotografia'] as String?;
          if (serverPath != null && serverPath.isNotEmpty) {
            final existing = await _db.getReporteByServerId(data['id_reporte'] as int);
            final hasLocalImage = existing != null &&
                existing.imagenes != null &&
                existing.imagenes!.isNotEmpty;

            if (!hasLocalImage) {
              final fileName = '${data['id_reporte']}_${serverPath.split('/').last}';
              final savePath = '${reportesDir.path}/$fileName';

              final downloaded = await _api.downloadImage(serverPath, savePath);
              if (downloaded != null) {
                await _db.updateReporteLocalImage(data['id_reporte'] as int, downloaded);
                final reporte = await _db.getReporteByServerId(data['id_reporte'] as int);
                if (reporte != null) {
                  await _db.marcarImagenDescargada(reporte.idLocal!);
                }
                imagenesCount++;
              }
            }
          }
        }

        if (batch.length < limit) {
          hasMore = false;
        } else {
          skip += limit;
        }
      }

    } catch (e) {
      debugPrint('[syncAllFromServer] ERROR: $e');
    }

    await loadReportes();
    return {'reportes': reportesCount, 'imagenes': imagenesCount};
  }

  @override
  void dispose() {
    _pendingSubscription?.cancel();
    super.dispose();
  }

  void clearData() {
    _pendingSubscription?.cancel();
    _pendingSubscription = null;
    _reportes = [];
    _departamentos = [];
    _provincias = [];
    _municipios = [];
    _estados = [];
    _categorias = [];
    _tiposEvento = [];
    _municipioGeojson = null;
    _pendingCount = 0;
    _isLoading = false;
    _isLoadingProvincias = false;
    _isLoadingMunicipios = false;
    notifyListeners();
  }
}
