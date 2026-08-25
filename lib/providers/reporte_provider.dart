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
  List<Estado> _estadosEdan = [];
  List<Categoria> _categorias = [];
  List<TipoEvento> _tiposEvento = [];
  List<TipoLocalidad> _tiposLocalidad = [];
  List<Cultivo> _cultivos = [];
  List<PecuarioGrupo> _pecuarioGrupos = [];
  List<GrupoVulnerableCatalogo> _gruposVulnerables = [];
  List<Map<String, dynamic>> _tiposRepositorio = [];
  MunicipioGeojson? _municipioGeojson;
  int _pendingCount = 0;
  bool _isLoading = false;
  bool _isLoadingProvincias = false;
  bool _isLoadingMunicipios = false;
  bool _isInitializing = false;
  String _downloadPhase = '';

  List<ReporteOffline> get reportes => _reportes;
  List<Departamento> get departamentos => _departamentos;
  List<Provincia> get provincias => _provincias;
  List<Municipio> get municipios => _municipios;
  List<Estado> get estados => _estados;
  List<Estado> get estadosEdan => _estadosEdan;
  List<Categoria> get categorias => _categorias;
  List<TipoEvento> get tiposEvento => _tiposEvento;
  List<TipoLocalidad> get tiposLocalidad => _tiposLocalidad;
  List<Cultivo> get cultivos => _cultivos;
  List<PecuarioGrupo> get pecuarioGrupos => _pecuarioGrupos;
  List<GrupoVulnerableCatalogo> get gruposVulnerables => _gruposVulnerables;
  List<Map<String, dynamic>> get tiposRepositorio => _tiposRepositorio;
  MunicipioGeojson? get municipioGeojson => _municipioGeojson;
  int get pendingCount => _pendingCount;
  bool get isLoading => _isLoading;
  bool get isLoadingProvincias => _isLoadingProvincias;
  bool get isLoadingMunicipios => _isLoadingMunicipios;
  bool get isInitializing => _isInitializing;
  String get downloadPhase => _downloadPhase;

  StreamSubscription<int>? _pendingSubscription;

  Future<void> initialize() async {
    _isInitializing = true;
    _downloadPhase = 'Cargando datos locales...';
    notifyListeners();

    _pendingSubscription =
        _syncManager.pendingCountStream.listen((count) {
      _pendingCount = count;
      notifyListeners();
    });

    await loadReportes();
    _downloadPhase = 'Cargando catálogos locales...';
    notifyListeners();
    await loadCatalogsLocal();

    if (AuthService.instance.isAuthenticated) {
      _downloadPhase = 'Descargando departamentos...';
      notifyListeners();
      await loadGeography();

      _downloadPhase = 'Descargando catálogos del servidor...';
      notifyListeners();
      await fetchAndCacheCatalogs();
    }

    _downloadPhase = '';
    _isInitializing = false;
    notifyListeners();
  }

  Future<void> initializeResp() async {
    _isInitializing = true;
    _downloadPhase = '';
    notifyListeners();

    await initialize();

    if (AuthService.instance.isAuthenticated) {
      _downloadPhase = 'Descargando reportes del servidor...';
      notifyListeners();
      if (_reportes.isEmpty) {
        await syncAllFromServer();
      } else {
        _syncManager.pullServerUpdates().then((_) => loadReportes());
      }
      _downloadPhase = 'Descargando imágenes...';
      notifyListeners();
      descargarImagenesPendientes();
    }

    _downloadPhase = '';
    _isInitializing = false;
    notifyListeners();
  }

  Future<void> initializeUgr() async {
    _isInitializing = true;
    _downloadPhase = '';
    notifyListeners();

    await initialize();

    if (AuthService.instance.isAuthenticated) {
      _downloadPhase = 'Descargando estados EDAN...';
      notifyListeners();
      await _fetchAndCacheEstadosEdan();
    }

    _downloadPhase = '';
    _isInitializing = false;
    notifyListeners();
  }

  Future<void> _fetchAndCacheEstadosEdan() async {
    try {
      final estados = await _api.getEstadosEdan();
      final mapeados = estados.map((e) {
        return {
          'id_estado': e['id_estado'] ?? e['id'] ?? 0,
          'nombre': e['nombre'] ?? e['descripcion'] ?? 'Desconocido',
          'descripcion': e['descripcion'],
          'orden': e['orden'],
        };
      }).toList();
      _estadosEdan = mapeados
          .map((e) => Estado.fromJson(e))
          .where((e) => e.idEstado != 0)
          .toList();
      await _db.saveEstadosEdan(
          _estadosEdan.map((e) => {
                'id_estado': e.idEstado,
                'nombre': e.nombre,
                'descripcion': e.descripcion,
                'orden': e.orden,
              }).toList());
    } catch (_) {}
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
      // Cachear en SQLite para offline
      await _db.saveDepartamentos(
          _departamentos.map((d) => d.toJson()).toList());
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
      // Cachear en SQLite para offline
      await _db.saveProvincias(
          _provincias.map((p) => p.toJson()).toList());
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
      // Cachear en SQLite para offline
      await _db.saveMunicipios(
          _municipios.map((m) => m.toJson()).toList());
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
      final tiposLocalidadData = await _db.getTiposLocalidadLocal();
      _tiposLocalidad = tiposLocalidadData
          .map((t) => TipoLocalidad.fromJson(t))
          .toList();
    } catch (_) {
      _tiposLocalidad = [];
    }

    try {
      final estadosEdanData = await _db.getEstadosEdanLocal();
      _estadosEdan = estadosEdanData.map((e) => Estado.fromJson(e)).toList();
    } catch (_) {
      _estadosEdan = [];
    }

    try {
      final cultivosData = await _db.getCultivosLocal();
      _cultivos = cultivosData.map((c) => Cultivo.fromJson(c)).toList();
    } catch (_) {
      _cultivos = [];
    }

    try {
      final pecuarioData = await _db.getPecuarioGruposLocal();
      _pecuarioGrupos = pecuarioData.map((p) => PecuarioGrupo.fromJson(p)).toList();
    } catch (_) {
      _pecuarioGrupos = [];
    }

    try {
      final gruposData = await _db.getGruposVulnerablesLocal();
      _gruposVulnerables = gruposData.map((g) => GrupoVulnerableCatalogo.fromJson(g)).toList();
    } catch (_) {
      _gruposVulnerables = [];
    }

    try {
      _tiposRepositorio = await _db.getTiposRepositorioLocal();
    } catch (_) {
      _tiposRepositorio = [];
    }

    // Cachear catálogos geográficos desde SQLite (offline)
    try {
      final depData = await _db.getDepartamentosLocal();
      if (depData.isNotEmpty) {
        _departamentos = depData.map((d) => Departamento.fromJson(d)).toList();
      }
    } catch (_) {}
    try {
      final provData = await _db.getProvinciasLocal();
      if (provData.isNotEmpty) {
        _provincias = provData.map((p) => Provincia.fromJson(p)).toList();
      }
    } catch (_) {}
    try {
      final munData = await _db.getMunicipiosLocal();
      if (munData.isNotEmpty) {
        _municipios = munData.map((m) => Municipio.fromJson(m)).toList();
      }
    } catch (_) {}

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

    try {
      final tiposLocalidad = await _api.getTipoLocalidad();
      _tiposLocalidad = tiposLocalidad;
      await _db.saveTiposLocalidad(tiposLocalidad
          .map((t) => {
                'id_tipo_localidad': t.idTipoLocalidad,
                'nombre': t.nombre,
                'descripcion': t.descripcion,
                'orden': t.orden,
              })
          .toList());
      tiposCount += tiposLocalidad.length;
    } catch (_) {}

    try {
      final cultivos = await _api.getCultivos();
      _cultivos = cultivos;
      await _db.saveCultivos(
          cultivos.map((c) => {'id_cultivo': c.idCultivo, 'nombre': c.nombre, 'grupo': c.grupo}).toList());
    } catch (_) {}

    try {
      final pecuarioGrupos = await _api.getPecuarioGrupos();
      _pecuarioGrupos = pecuarioGrupos;
      await _db.savePecuarioGrupos(
          pecuarioGrupos.map((p) => {'id_pecuario_grupo': p.idPecuarioGrupo, 'nombre': p.nombre, 'grupo': p.grupo}).toList());
    } catch (_) {}

    try {
      final gruposVulnerables = await _api.getGruposVulnerables();
      _gruposVulnerables = gruposVulnerables;
      await _db.saveGruposVulnerables(
          gruposVulnerables.map((g) => {
            'id_grupo_vulnerable': g.idGrupoVulnerable,
            'codigo': g.codigo,
            'nombre': g.nombre,
            'descripcion': g.descripcion,
            'orden': g.orden,
            'activo': g.activo ? 1 : 0,
          }).toList());
    } catch (_) {
      try {
        final gruposData = await _db.getGruposVulnerablesLocal();
        _gruposVulnerables = gruposData
            .map((g) => GrupoVulnerableCatalogo.fromJson(g))
            .toList();
      } catch (_) {
        _gruposVulnerables = [];
      }
    }

    try {
      final tiposRepositorio = await _api.listarTiposRepositorio();
      _tiposRepositorio = tiposRepositorio;
      await _db.saveTiposRepositorio(
          tiposRepositorio.map((t) => {
                'id_tipo_documento': t['id_tipo_documento'] ?? t['id'],
                'codigo': t['codigo'] ?? '',
                'nombre': t['nombre'] ?? '',
                'descripcion': t['descripcion'],
                'orden': t['orden'] ?? 0,
                'activo': (t['activo'] == true || t['activo'] == 1) ? 1 : 0,
                'extensiones_permitidas': t['extensiones_permitidas'] ?? 'pdf',
                'tamano_maximo_bytes': t['tamano_maximo_bytes'] ?? 52428800,
              }).toList());
    } catch (_) {}

    await _downloadAndCacheMunicipioGeojson();

    notifyListeners();
    return {'estados': estadosCount, 'categorias': categoriasCount, 'tipos': tiposCount};
  }

  /// Descarga SOLO gruposVulnerables si está vacío
  Future<void> fetchGruposVulnerablesIfNeeded() async {
    if (_gruposVulnerables.isNotEmpty) return;

    try {
      final gruposVulnerables = await _api.getGruposVulnerables();
      _gruposVulnerables = gruposVulnerables;
      await _db.saveGruposVulnerables(
          gruposVulnerables.map((g) => {
            'id_grupo_vulnerable': g.idGrupoVulnerable,
            'codigo': g.codigo,
            'nombre': g.nombre,
            'descripcion': g.descripcion,
            'orden': g.orden,
            'activo': g.activo ? 1 : 0,
          }).toList());
      notifyListeners();
    } catch (_) {
      try {
        final gruposData = await _db.getGruposVulnerablesLocal();
        _gruposVulnerables = gruposData
            .map((g) => GrupoVulnerableCatalogo.fromJson(g))
            .toList();
        notifyListeners();
      } catch (_) {
        _gruposVulnerables = [];
      }
    }
  }

  Future<Map<String, int>> fetchAndCacheCatalogsEdan() async {
    int estadosCount = 0;
    int tiposCount = 0;

    try {
      final estados = await _api.getEstadosEdan();
      final mapeados = estados.map((e) {
        return {
          'id_estado': e['id_estado'] ?? e['id'] ?? 0,
          'nombre': e['nombre'] ?? e['descripcion'] ?? 'Desconocido',
          'descripcion': e['descripcion'],
          'orden': e['orden'],
        };
      }).toList();
      _estadosEdan = mapeados
          .map((e) => Estado.fromJson(e))
          .where((e) => e.idEstado != 0)
          .toList();
      await _db.saveEstadosEdan(
          _estadosEdan.map((e) => {
                'id_estado': e.idEstado,
                'nombre': e.nombre,
                'descripcion': e.descripcion,
                'orden': e.orden,
              }).toList());
      estadosCount = _estadosEdan.length;
    } catch (_) {}

    try {
      final tipos = await _api.getTiposEvento();
      _tiposEvento = tipos;
      await _db.saveTiposEvento(
          tipos.map((t) => {'id_tipo_evento': t.idTipoEvento, 'nombre': t.nombre}).toList());
      tiposCount = tipos.length;
    } catch (_) {}

    try {
      final tiposRepositorio = await _api.listarTiposRepositorio();
      _tiposRepositorio = tiposRepositorio;
      await _db.saveTiposRepositorio(
          tiposRepositorio.map((t) => {
                'id_tipo_documento': t['id_tipo_documento'] ?? t['id'],
                'codigo': t['codigo'] ?? '',
                'nombre': t['nombre'] ?? '',
                'descripcion': t['descripcion'],
                'orden': t['orden'] ?? 0,
                'activo': (t['activo'] == true || t['activo'] == 1) ? 1 : 0,
                'extensiones_permitidas': t['extensiones_permitidas'] ?? 'pdf',
                'tamano_maximo_bytes': t['tamano_maximo_bytes'] ?? 52428800,
              }).toList());
    } catch (_) {}

    await _downloadAndCacheMunicipioGeojson();

    try {
      final gruposVulnerables = await _api.getGruposVulnerables();
      _gruposVulnerables = gruposVulnerables;
      await _db.saveGruposVulnerables(
          gruposVulnerables.map((g) => {
            'id_grupo_vulnerable': g.idGrupoVulnerable,
            'codigo': g.codigo,
            'nombre': g.nombre,
            'descripcion': g.descripcion,
            'orden': g.orden,
            'activo': g.activo ? 1 : 0,
          }).toList());
    } catch (_) {
      try {
        final gruposData = await _db.getGruposVulnerablesLocal();
        _gruposVulnerables = gruposData
            .map((g) => GrupoVulnerableCatalogo.fromJson(g))
            .toList();
      } catch (_) {
        _gruposVulnerables = [];
      }
    }

    notifyListeners();
    return {'estados': estadosCount, 'tipos': tiposCount};
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
      final raw = (feature['data'] ?? feature) as Map<String, dynamic>;
      final geojson = MunicipioGeojson.fromJson(raw);

      await _db.saveMunicipioGeojson(
        municipioId: token.idMunicipio!,
        codigoIne: match.codigoIne,
        nombre: geojson.nombre,
        geojson: jsonEncode(raw),
      );

      _municipioGeojson = geojson;
      notifyListeners();
    } catch (_) {
      // Silencioso: no rompe el flujo de catálogos
    }
  }

  Future<void> ensureMunicipioGeojson() async {
    if (_municipioGeojson != null) return;
    await _downloadAndCacheMunicipioGeojson();
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
            reporte.fotografiaServerPath!.isEmpty) {
          continue;
        }

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
    _tiposLocalidad = [];
    _tiposRepositorio = [];
    _municipioGeojson = null;
    _pendingCount = 0;
    _isLoading = false;
    _isLoadingProvincias = false;
    _isLoadingMunicipios = false;
    notifyListeners();
  }
}
