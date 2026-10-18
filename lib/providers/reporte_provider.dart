import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/reporte.dart';
import '../models/departamento.dart';
import '../models/provincia.dart';
import '../models/municipio.dart';
import '../models/municipio_geojson.dart';
import '../services/database_helper.dart';
import '../services/api_service.dart';
import '../services/edan/edan_store_v2.dart';
import '../services/sync_manager.dart';
import '../services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReporteProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final ApiService _api = ApiService.instance;
  final SyncManager _syncManager = SyncManager.instance;

  /// Marca por DISPOSITIVO: ¿los catálogos generales ya se bajaron y guardaron?
  static const String _kCatalogsSyncKey = 'catalogs_generales_sync';

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
  List<GrupoEtarioCatalogo> _gruposEtarios = [];
  List<Map<String, dynamic>> _tiposRepositorio = [];
  MunicipioGeojson? _municipioGeojson;
  int _pendingCount = 0;
  bool _isLoading = false;
  bool _isLoadingGeografia = false;
  bool _isLoadingProvincias = false;
  bool _isLoadingMunicipios = false;
  bool _isInitializing = false;
  bool _isDescargandoCatalogos = false;
  bool _catalogsAllOk = true;
  bool _geoError = false;
  bool _provinciasError = false;
  bool _municipiosError = false;
  String _downloadPhase = '';

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
  List<GrupoEtarioCatalogo> get gruposEtarios => _gruposEtarios;
  List<Map<String, dynamic>> get tiposRepositorio => _tiposRepositorio;
  MunicipioGeojson? get municipioGeojson => _municipioGeojson;
  int get pendingCount => _pendingCount;
  bool get isLoading => _isLoading;
  bool get isLoadingGeografia => _isLoadingGeografia;
  bool get isLoadingProvincias => _isLoadingProvincias;
  bool get isLoadingMunicipios => _isLoadingMunicipios;
  bool get isInitializing => _isInitializing;
  bool get isDescargandoCatalogos => _isDescargandoCatalogos;
  bool get geoError => _geoError;
  bool get provinciasError => _provinciasError;
  bool get municipiosError => _municipiosError;
  String get downloadPhase => _downloadPhase;

  /// Fases de descarga de catálogos en orden: el progreso se deriva de la
  /// fase actual (sin tocar los 10 pasos). `null` = sin descarga en curso.
  static const List<String> fasesCatalogos = [
    'Descargando tipos de evento...',
    'Descargando tipos de localidad...',
    'Descargando cultivos...',
    'Descargando grupos pecuarios...',
    'Descargando grupos vulnerables...',
    'Descargando grupos etarios...',
    'Descargando tipos de repositorio...',
    'Descargando estados de localidad...',
    'Descargando estados EDAN...',
  ];

  /// 0..1 mientras se descargan catálogos; `null` en otro caso.
  double? get progresoCatalogos {
    final i = fasesCatalogos.indexOf(_downloadPhase);
    if (i < 0) return null;
    return (i + 1) / (fasesCatalogos.length + 1);
  }

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

    _downloadPhase = 'Cargando catálogos locales...';
    notifyListeners();
    await loadCatalogsLocal();

    // Arranque offline-first (arquitectura §23): la UI se pinta con SQLite
    // de inmediato; la red (geografía + catálogos) corre en segundo plano
    // sin bloquear la primera pintura. Al terminar se avisa al store para
    // que las pestañas recarguen nombres de catálogo.
    _downloadPhase = '';
    _isInitializing = false;
    notifyListeners();

    if (AuthService.instance.isAuthenticated) {
      unawaited(_cargarRedEnSegundoPlano());
    }
  }

  /// Geografía + catálogos del servidor en segundo plano. Nunca bloquea la
  /// UI; al terminar avisa vía `EdanStoreV2.catalogosVersion` para que las
  /// pestañas recarguen los nombres resueltos por catálogo.
  Future<void> _cargarRedEnSegundoPlano() async {
    try {
      await loadGeography();
      await _descargarCatalogosGenerales();
    } catch (_) {
      // Sin red: queda lo local; el botón "Actualizar catálogos" del Perfil
      // y el próximo arranque lo reintentan.
    }
    EdanStoreV2.instance.avisarCatalogos();
  }

  /// Baja y guarda en SQLite los catalogos generales (compartidos por los roles
  /// 6 y 7) UNA SOLA VEZ por dispositivo (marca `catalogs_generales_sync`). En
  /// reaperturas se leen de SQLite; el boton "Actualizar catalogos" del Perfil
  /// los vuelve a descargar a mano.
  Future<void> _descargarCatalogosGenerales() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kCatalogsSyncKey) ?? false) return;
    await fetchAndCacheCatalogs();
    if (_catalogsAllOk) {
      await prefs.setBool(_kCatalogsSyncKey, true);
    }
  }

  Future<void> initializeResp() async {
    _isInitializing = true;
    _downloadPhase = '';
    notifyListeners();

    await initialize();

    _downloadPhase = '';
    _isInitializing = false;
    notifyListeners();
  }

  Future<void> initializeUgr() async {
    _isInitializing = true;
    _downloadPhase = '';
    notifyListeners();

    await initialize();

    _downloadPhase = '';
    _isInitializing = false;
    notifyListeners();
  }

  Future<void> loadGeography() async {
    _isLoadingGeografia = true;
    _geoError = false;
    notifyListeners();
    try {
      final departamentos = await _api.getDepartamentos();
      // Cachear en SQLite para offline
      await _db.saveDepartamentos(
          departamentos.map((d) => d.toJson()).toList());
      // Solo reemplazar la lista en memoria si la red respondió: un fallo
      // no debe vaciar lo ya cargado desde SQLite.
      _departamentos = departamentos;
    } catch (e) {
      _geoError = true;
    }
    _isLoadingGeografia = false;
    notifyListeners();
  }

  Future<void> loadProvincias(int idDepartamento) async {
    _isLoadingProvincias = true;
    _provinciasError = false;
    final previas = _provincias;
    _provincias = [];
    _municipios = [];
    notifyListeners();
    try {
      _provincias = await _api.getProvincias(idDepartamento: idDepartamento);
      // Cachear en SQLite para offline
      await _db.saveProvincias(
          _provincias.map((p) => p.toJson()).toList());
    } catch (e) {
      _provinciasError = true;
      // Sin red se conserva lo que había en memoria.
      _provincias = previas;
    }
    _isLoadingProvincias = false;
    notifyListeners();
  }

  Future<void> loadMunicipios(int idProvincia, int idDepartamento) async {
    _isLoadingMunicipios = true;
    _municipiosError = false;
    final previos = _municipios;
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
      _municipiosError = true;
      // Sin red se conserva lo que había en memoria.
      _municipios = previos;
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
      final gruposEtariosData = await _db.getGruposEtariosLocal();
      _gruposEtarios = gruposEtariosData
          .map((g) => GrupoEtarioCatalogo.fromJson(g))
          .toList();
    } catch (_) {
      _gruposEtarios = [];
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
    int tiposCount = 0;
    int estadosCount = 0;
    _catalogsAllOk = true;
    _isDescargandoCatalogos = true;
    notifyListeners();

    try {
      _downloadPhase = 'Descargando tipos de evento...';
      notifyListeners();
      final tipos = await _api.getTiposEvento();
      _tiposEvento = tipos;
      await _db.saveTiposEvento(
          tipos.map((t) => {'id_tipo_evento': t.idTipoEvento, 'nombre': t.nombre}).toList());
      tiposCount = tipos.length;
    } catch (_) {
      _catalogsAllOk = false;
    }

    try {
      _downloadPhase = 'Descargando tipos de localidad...';
      notifyListeners();
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
    } catch (_) {
      _catalogsAllOk = false;
    }

    try {
      _downloadPhase = 'Descargando cultivos...';
      notifyListeners();
      final cultivos = await _api.getCultivos();
      _cultivos = cultivos;
      await _db.saveCultivos(
          cultivos.map((c) => {'id_cultivo': c.idCultivo, 'nombre': c.nombre, 'grupo': c.grupo}).toList());
    } catch (_) {
      _catalogsAllOk = false;
    }

    try {
      _downloadPhase = 'Descargando grupos pecuarios...';
      notifyListeners();
      final pecuarioGrupos = await _api.getPecuarioGrupos();
      _pecuarioGrupos = pecuarioGrupos;
      await _db.savePecuarioGrupos(
          pecuarioGrupos.map((p) => {'id_pecuario_grupo': p.idPecuarioGrupo, 'nombre': p.nombre, 'grupo': p.grupo}).toList());
    } catch (_) {
      _catalogsAllOk = false;
    }

    try {
      _downloadPhase = 'Descargando grupos vulnerables...';
      notifyListeners();
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
      _catalogsAllOk = false;
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
      _downloadPhase = 'Descargando grupos etarios...';
      notifyListeners();
      final gruposEtarios = await _api.getGruposEtarios();
      _gruposEtarios = gruposEtarios;
      await _db.saveGruposEtarios(
          gruposEtarios.map((g) => {
                'id_grupo_etario': g.idGrupoEtario,
                'codigo': g.codigo,
                'nombre': g.nombre,
                'descripcion': g.descripcion,
                'orden': g.orden,
                'activo': g.activo ? 1 : 0,
              }).toList());
    } catch (_) {
      _catalogsAllOk = false;
      try {
        final gruposEtariosData = await _db.getGruposEtariosLocal();
        _gruposEtarios = gruposEtariosData
            .map((g) => GrupoEtarioCatalogo.fromJson(g))
            .toList();
      } catch (_) {
        _gruposEtarios = [];
      }
    }

    try {
      _downloadPhase = 'Descargando tipos de repositorio...';
      notifyListeners();
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
    } catch (_) {
      _catalogsAllOk = false;
    }

    // Estados de localidad (borrador/enviado/aprobado/rechazado...). Catalogo
    // general: el endpoint devuelve id_edan_localidad_estado + descripcion.
    try {
      _downloadPhase = 'Descargando estados de localidad...';
      notifyListeners();
      final estadosLocalidad = await _api.getLocalidadesEstado();
      final mapeados = estadosLocalidad.map((e) {
        return {
          'id_estado':
              e['id_edan_localidad_estado'] ?? e['id_estado'] ?? e['id'] ?? 0,
          'nombre': e['nombre'] ?? e['descripcion'] ?? 'Desconocido',
          'descripcion': e['descripcion'],
          'orden': e['orden'],
        };
      }).toList();
      _estados = mapeados
          .map((e) => Estado.fromJson(e))
          .where((e) => e.idEstado != 0)
          .toList();
      await _db.saveEstados(_estados
          .map((e) => {
                'id_estado': e.idEstado,
                'nombre': e.nombre,
                'descripcion': e.descripcion,
                'orden': e.orden,
              })
          .toList());
      estadosCount = _estados.length;
    } catch (_) {
      _catalogsAllOk = false;
    }

    // Estados EDAN (los usa el UGR para aprobar/rechazar). Tambien general.
    try {
      _downloadPhase = 'Descargando estados EDAN...';
      notifyListeners();
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
    } catch (_) {
      _catalogsAllOk = false;
    }

    await _downloadAndCacheMunicipioGeojson();

    _downloadPhase = '';
    _isDescargandoCatalogos = false;
    notifyListeners();
    return {'estados': estadosCount, 'tipos': tiposCount};
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

  /// Descarga SOLO grupos etarios si está vacío (catálogo v2).
  Future<void> fetchGruposEtariosIfNeeded() async {
    if (_gruposEtarios.isNotEmpty) return;

    try {
      final gruposEtarios = await _api.getGruposEtarios();
      _gruposEtarios = gruposEtarios;
      await _db.saveGruposEtarios(
          gruposEtarios.map((g) => {
            'id_grupo_etario': g.idGrupoEtario,
            'codigo': g.codigo,
            'nombre': g.nombre,
            'descripcion': g.descripcion,
            'orden': g.orden,
            'activo': g.activo ? 1 : 0,
          }).toList());
      notifyListeners();
    } catch (_) {
      try {
        final gruposEtariosData = await _db.getGruposEtariosLocal();
        _gruposEtarios = gruposEtariosData
            .map((g) => GrupoEtarioCatalogo.fromJson(g))
            .toList();
        notifyListeners();
      } catch (_) {
        _gruposEtarios = [];
      }
    }
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

      final feature = await _api.getMunicipioGeojson(match.id);
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

  @override
  void dispose() {
    _pendingSubscription?.cancel();
    super.dispose();
  }

  void clearData() {
    _pendingSubscription?.cancel();
    _pendingSubscription = null;
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
