import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/edan.dart';
import '../models/reporte_offline.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._();
  static DatabaseHelper get instance => _instance;
  DatabaseHelper._();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'rea_database.db');
    return await openDatabase(
      path,
      version: 17,
      onCreate: _createDatabase,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
    );
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE reportes_offline (
        id_local INTEGER PRIMARY KEY AUTOINCREMENT,
        id_server INTEGER,
        usuario_id INTEGER NOT NULL,
        departamento_id INTEGER NOT NULL,
        provincia_id INTEGER NOT NULL,
        municipio_id INTEGER NOT NULL,
        comunidad TEXT NOT NULL,
        departamento_nombre TEXT,
        provincia_nombre TEXT,
        municipio_nombre TEXT,
        fecha_evento TEXT NOT NULL,
        hora_evento TEXT,
        tipo_evento_id INTEGER NOT NULL,
        coordenada_lat REAL,
        coordenada_lon REAL,
        descripcion TEXT,
        estado_id INTEGER DEFAULT 1,
        estado_nombre TEXT,
        categorias TEXT,
        imagenes TEXT,
        fotografia_server_path TEXT,
        sincronizado INTEGER DEFAULT 0,
        pendiente_eliminacion INTEGER DEFAULT 0,
        pendiente_actualizacion INTEGER DEFAULT 0,
        es_borrador INTEGER DEFAULT 0,
        fecha_creacion TEXT NOT NULL,
        fecha_modificacion TEXT,
        intentos_sync INTEGER DEFAULT 0,
        ultimo_error TEXT,
        imagen_descargada INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE borradores (
        id_borrador INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario_id INTEGER NOT NULL,
        datos_formulario TEXT NOT NULL,
        imagenes_paths TEXT,
        fecha_creacion TEXT NOT NULL,
        fecha_modificacion TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sincronizaciones (
        id_sync INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha_sync TEXT NOT NULL,
        reportes_enviados INTEGER DEFAULT 0,
        reportes_fallidos INTEGER DEFAULT 0,
        detalles TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE catalogo_estados (
        id_estado INTEGER PRIMARY KEY,
        nombre TEXT NOT NULL,
        descripcion TEXT,
        orden INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE catalogo_categorias (
        id_categoria INTEGER PRIMARY KEY,
        nombre TEXT NOT NULL,
        descripcion TEXT,
        orden INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE catalogo_tipos_evento (
        id_tipo_evento INTEGER PRIMARY KEY,
        nombre TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE catalogo_tipo_localidad (
        id_tipo_localidad INTEGER PRIMARY KEY,
        nombre TEXT NOT NULL,
        descripcion TEXT,
        orden INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE catalogo_estados_edan (
        id_estado INTEGER PRIMARY KEY,
        nombre TEXT NOT NULL,
        descripcion TEXT,
        orden INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE catalogo_cultivos (
        id_cultivo INTEGER PRIMARY KEY,
        nombre TEXT NOT NULL,
        grupo TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE catalogo_pecuario_grupos (
        id_pecuario_grupo INTEGER PRIMARY KEY,
        nombre TEXT NOT NULL,
        grupo TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE catalogo_grupo_vulnerable (
        id_grupo_vulnerable INTEGER PRIMARY KEY,
        codigo TEXT NOT NULL,
        nombre TEXT NOT NULL,
        descripcion TEXT,
        orden INTEGER,
        activo INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE catalogo_departamentos (
        id INTEGER PRIMARY KEY,
        codigo_ine TEXT,
        nombre TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE catalogo_provincias (
        id INTEGER PRIMARY KEY,
        codigo_ine TEXT,
        id_departamento INTEGER,
        nombre TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE catalogo_municipios (
        id INTEGER PRIMARY KEY,
        codigo_ine TEXT,
        id_departamento INTEGER,
        id_provincia INTEGER,
        nombre TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE catalogo_tipos_repositorio (
        id_tipo_documento INTEGER PRIMARY KEY,
        codigo TEXT NOT NULL,
        nombre TEXT NOT NULL,
        descripcion TEXT,
        orden INTEGER DEFAULT 0,
        activo INTEGER DEFAULT 1,
        extensiones_permitidas TEXT DEFAULT 'pdf',
        tamano_maximo_bytes INTEGER DEFAULT 52428800
      )
    ''');

    await db.execute('''
      CREATE TABLE municipio_geojson (
        municipio_id INTEGER PRIMARY KEY,
        codigo_ine TEXT NOT NULL,
        nombre TEXT,
        geojson TEXT NOT NULL,
        fecha_actualizacion TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE config (
        clave TEXT PRIMARY KEY,
        valor TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE edans_offline (
        id_local INTEGER PRIMARY KEY AUTOINCREMENT,
        id_server INTEGER,
        id_edan INTEGER,
        usuario_id INTEGER NOT NULL,
        codigo_edan TEXT,
        municipio_id INTEGER,
        municipio_nombre TEXT,
        fecha_evento TEXT,
        fecha_llenado TEXT,
        id_estado INTEGER DEFAULT 1,
        estado_edan TEXT DEFAULT 'borrador',
        datos_json TEXT NOT NULL,
        sincronizado INTEGER DEFAULT 0,
        pendiente_eliminacion INTEGER DEFAULT 0,
        pendiente_actualizacion INTEGER DEFAULT 0,
        es_borrador INTEGER DEFAULT 0,
        fecha_creacion TEXT NOT NULL,
        fecha_modificacion TEXT,
        intentos_sync INTEGER DEFAULT 0,
        ultimo_error TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE localidades_offline (
        id_local TEXT PRIMARY KEY,
        id_server INTEGER,
        id_edan INTEGER,
        es_huerfana INTEGER DEFAULT 1,
        usuario_id INTEGER NOT NULL,
        id_tipo_localidad INTEGER,
        id_tipo_evento INTEGER,
        id_departamento INTEGER,
        id_provincia INTEGER,
        id_municipio INTEGER,
        departamento_nombre TEXT,
        provincia_nombre TEXT,
        municipio_nombre TEXT,
        localidad TEXT,
        fecha_llenado TEXT,
        fecha_evento TEXT,
        hora_evento TEXT,
        total_poblacion_afectada INTEGER DEFAULT 0,
        total_familias_afectadas INTEGER DEFAULT 0,
        total_familias_damnificadas INTEGER DEFAULT 0,
        imp_poblacion INTEGER DEFAULT 0,
        imp_salud INTEGER DEFAULT 0,
        imp_infraestructura INTEGER DEFAULT 0,
        imp_servicios INTEGER DEFAULT 0,
        imp_educacion INTEGER DEFAULT 0,
        imp_vivienda INTEGER DEFAULT 0,
        imp_agropecuario INTEGER DEFAULT 0,
        imp_proteccion INTEGER DEFAULT 0,
        imp_necesidades INTEGER DEFAULT 0,
        id_edan_localidad_estado INTEGER,
        estado_localidad TEXT,
        datos_json TEXT NOT NULL,
        sincronizado INTEGER DEFAULT 0,
        pendiente_eliminacion INTEGER DEFAULT 0,
        pendiente_actualizacion INTEGER DEFAULT 0,
        fecha_creacion TEXT NOT NULL,
        fecha_modificacion TEXT,
        intentos_sync INTEGER DEFAULT 0,
        ultimo_error TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE reportes_offline ADD COLUMN departamento_nombre TEXT');
      await db.execute('ALTER TABLE reportes_offline ADD COLUMN provincia_nombre TEXT');
      await db.execute('ALTER TABLE reportes_offline ADD COLUMN municipio_nombre TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE reportes_offline ADD COLUMN estado_nombre TEXT');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE reportes_offline ADD COLUMN fotografia_server_path TEXT');
    }
    if (oldVersion < 5) {
      await db.execute('CREATE TABLE catalogo_estados (id_estado INTEGER PRIMARY KEY, nombre TEXT NOT NULL, descripcion TEXT, orden INTEGER)');
      await db.execute('CREATE TABLE catalogo_categorias (id_categoria INTEGER PRIMARY KEY, nombre TEXT NOT NULL, descripcion TEXT, orden INTEGER)');
      await db.execute('CREATE TABLE catalogo_tipos_evento (id_tipo_evento INTEGER PRIMARY KEY, nombre TEXT NOT NULL)');
    }
    if (oldVersion < 12) {
      await db.execute('CREATE TABLE catalogo_tipo_localidad (id_tipo_localidad INTEGER PRIMARY KEY, nombre TEXT NOT NULL, descripcion TEXT, orden INTEGER)');
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE reportes_offline ADD COLUMN es_borrador INTEGER DEFAULT 0');
    }
    if (oldVersion < 7) {
      await db.execute('ALTER TABLE reportes_offline ADD COLUMN imagen_descargada INTEGER DEFAULT 0');
    }
    if (oldVersion < 8) {
      await db.execute('''
        CREATE TABLE edans_offline (
          id_local INTEGER PRIMARY KEY AUTOINCREMENT,
          id_server INTEGER,
          id_edan INTEGER,
          usuario_id INTEGER NOT NULL,
          codigo_edan TEXT,
          municipio_id INTEGER,
          municipio_nombre TEXT,
          fecha_evento TEXT,
          fecha_llenado TEXT,
          id_estado INTEGER DEFAULT 1,
          estado_edan TEXT DEFAULT 'borrador',
          datos_json TEXT NOT NULL,
          sincronizado INTEGER DEFAULT 0,
          pendiente_eliminacion INTEGER DEFAULT 0,
          pendiente_actualizacion INTEGER DEFAULT 0,
          es_borrador INTEGER DEFAULT 0,
          fecha_creacion TEXT NOT NULL,
          fecha_modificacion TEXT,
          intentos_sync INTEGER DEFAULT 0,
          ultimo_error TEXT
        )
      ''');
    }
    if (oldVersion < 9) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS config (
          clave TEXT PRIMARY KEY,
          valor TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 10) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS catalogo_estados_edan (
          id_estado INTEGER PRIMARY KEY,
          nombre TEXT NOT NULL,
          descripcion TEXT,
          orden INTEGER
        )
      ''');
    }
    if (oldVersion < 11) {
      // Migración v11: limpiar datos viejos y crear tabla localidades_offline
      // según decisión de diseño: dropear tablas edans_offline y recrear
      await db.execute('DROP TABLE IF EXISTS edans_offline');
      await db.execute('''
        CREATE TABLE edans_offline (
          id_local INTEGER PRIMARY KEY AUTOINCREMENT,
          id_server INTEGER,
          id_edan INTEGER,
          usuario_id INTEGER NOT NULL,
          codigo_edan TEXT,
          municipio_id INTEGER,
          municipio_nombre TEXT,
          fecha_evento TEXT,
          fecha_llenado TEXT,
          id_estado INTEGER DEFAULT 1,
          estado_edan TEXT DEFAULT 'borrador',
          datos_json TEXT NOT NULL,
          sincronizado INTEGER DEFAULT 0,
          pendiente_eliminacion INTEGER DEFAULT 0,
          pendiente_actualizacion INTEGER DEFAULT 0,
          es_borrador INTEGER DEFAULT 0,
          fecha_creacion TEXT NOT NULL,
          fecha_modificacion TEXT,
          intentos_sync INTEGER DEFAULT 0,
          ultimo_error TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE localidades_offline (
          id_local TEXT PRIMARY KEY,
          id_server INTEGER,
          id_edan INTEGER,
          es_huerfana INTEGER DEFAULT 1,
          usuario_id INTEGER NOT NULL,
          id_tipo_localidad INTEGER,
          id_tipo_evento INTEGER,
          id_departamento INTEGER,
          id_provincia INTEGER,
          id_municipio INTEGER,
          localidad TEXT,
          fecha_llenado TEXT,
          fecha_evento TEXT,
          hora_evento TEXT,
          total_poblacion_afectada INTEGER DEFAULT 0,
          total_familias_afectadas INTEGER DEFAULT 0,
          total_familias_damnificadas INTEGER DEFAULT 0,
          imp_poblacion INTEGER DEFAULT 0,
          imp_salud INTEGER DEFAULT 0,
          imp_infraestructura INTEGER DEFAULT 0,
          imp_servicios INTEGER DEFAULT 0,
          imp_educacion INTEGER DEFAULT 0,
          imp_vivienda INTEGER DEFAULT 0,
          imp_agropecuario INTEGER DEFAULT 0,
          imp_proteccion INTEGER DEFAULT 0,
          imp_necesidades INTEGER DEFAULT 0,
          id_edan_localidad_estado INTEGER,
          estado_localidad TEXT,
          datos_json TEXT NOT NULL,
          sincronizado INTEGER DEFAULT 0,
          pendiente_eliminacion INTEGER DEFAULT 0,
          pendiente_actualizacion INTEGER DEFAULT 0,
          fecha_creacion TEXT NOT NULL,
          fecha_modificacion TEXT,
          intentos_sync INTEGER DEFAULT 0,
          ultimo_error TEXT
        )
      ''');
    }
    if (oldVersion < 13) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS catalogo_cultivos (
          id_cultivo INTEGER PRIMARY KEY,
          nombre TEXT NOT NULL,
          grupo TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS catalogo_pecuario_grupos (
          id_pecuario_grupo INTEGER PRIMARY KEY,
          nombre TEXT NOT NULL,
          grupo TEXT
        )
      ''');
    }
    if (oldVersion < 14) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS catalogo_grupo_vulnerable (
          id_grupo_vulnerable INTEGER PRIMARY KEY,
          codigo TEXT NOT NULL,
          nombre TEXT NOT NULL,
          descripcion TEXT,
          orden INTEGER,
          activo INTEGER DEFAULT 1
        )
      ''');
    }
    if (oldVersion < 15) {
      await db.execute('ALTER TABLE localidades_offline ADD COLUMN departamento_nombre TEXT');
      await db.execute('ALTER TABLE localidades_offline ADD COLUMN provincia_nombre TEXT');
      await db.execute('ALTER TABLE localidades_offline ADD COLUMN municipio_nombre TEXT');
    }
    if (oldVersion < 16) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS catalogo_departamentos (
          id INTEGER PRIMARY KEY,
          codigo_ine TEXT,
          nombre TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS catalogo_provincias (
          id INTEGER PRIMARY KEY,
          codigo_ine TEXT,
          id_departamento INTEGER,
          nombre TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS catalogo_municipios (
          id INTEGER PRIMARY KEY,
          codigo_ine TEXT,
          id_departamento INTEGER,
          id_provincia INTEGER,
          nombre TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 17) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS catalogo_tipos_repositorio (
          id_tipo_documento INTEGER PRIMARY KEY,
          codigo TEXT NOT NULL,
          nombre TEXT NOT NULL,
          descripcion TEXT,
          orden INTEGER DEFAULT 0,
          activo INTEGER DEFAULT 1,
          extensiones_permitidas TEXT DEFAULT 'pdf',
          tamano_maximo_bytes INTEGER DEFAULT 52428800
        )
      ''');
    }
  }

  Future<void> _onOpen(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS municipio_geojson (
        municipio_id INTEGER PRIMARY KEY,
        codigo_ine TEXT NOT NULL,
        nombre TEXT,
        geojson TEXT NOT NULL,
        fecha_actualizacion TEXT
      )
    ''');
  }

  Future<int> insertReporte(ReporteOffline reporte) async {
    final db = await database;
    return await db.insert('reportes_offline', reporte.toMap());
  }

  Future<List<ReporteOffline>> getReportes(int usuarioId) async {
    final db = await database;
    final maps = await db.query(
      'reportes_offline',
      where: 'usuario_id = ?',
      whereArgs: [usuarioId],
      orderBy: 'fecha_creacion DESC',
    );
    return maps.map((map) => ReporteOffline.fromMap(map)).toList();
  }

  Future<List<ReporteOffline>> getUnsyncedReports() async {
    final db = await database;
    final maps = await db.query(
      'reportes_offline',
      where: 'sincronizado = 0 AND es_borrador = 0',
      orderBy: 'fecha_creacion ASC',
    );
    return maps.map((map) => ReporteOffline.fromMap(map)).toList();
  }

  Future<int> markAsSynced(int idLocal, int idServer) async {
    final db = await database;
    return await db.update(
      'reportes_offline',
      {
        'id_server': idServer,
        'sincronizado': 1,
        'pendiente_eliminacion': 0,
        'pendiente_actualizacion': 0,
        'fecha_modificacion': DateTime.now().toIso8601String(),
        'intentos_sync': 0,
        'ultimo_error': null,
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<int> updateEstado(int idLocal, int? estadoId, String? estadoNombre) async {
    final db = await database;
    return await db.update(
      'reportes_offline',
      {
        'estado_id':? estadoId,
        'estado_nombre':? estadoNombre,
        'fecha_modificacion': DateTime.now().toIso8601String(),
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<void> updateFromServer(int idLocal, {
    int? estadoId,
    String? estadoNombre,
    String? departamentoNombre,
    String? provinciaNombre,
    String? municipioNombre,
  }) async {
    final db = await database;
    final updates = <String, dynamic>{
      'fecha_modificacion': DateTime.now().toIso8601String(),
    };
    if (estadoId != null) updates['estado_id'] = estadoId;
    if (estadoNombre != null) updates['estado_nombre'] = estadoNombre;
    if (departamentoNombre != null) updates['departamento_nombre'] = departamentoNombre;
    if (provinciaNombre != null) updates['provincia_nombre'] = provinciaNombre;
    if (municipioNombre != null) updates['municipio_nombre'] = municipioNombre;
    if (updates.length <= 1) return;
    await db.update('reportes_offline', updates, where: 'id_local = ?', whereArgs: [idLocal]);
  }

  Future<ReporteOffline?> getReporteByServerId(int idServer) async {
    final db = await database;
    final maps = await db.query('reportes_offline', where: 'id_server = ?', whereArgs: [idServer], limit: 1);
    if (maps.isEmpty) return null;
    return ReporteOffline.fromMap(maps.first);
  }

  Future<ReporteOffline?> getReporteByIdLocal(int idLocal) async {
    final db = await database;
    final maps = await db.query('reportes_offline', where: 'id_local = ?', whereArgs: [idLocal], limit: 1);
    if (maps.isEmpty) return null;
    return ReporteOffline.fromMap(maps.first);
  }

  Future<List<ReporteOffline>> getSyncedReports(int usuarioId) async {
    final db = await database;
    final maps = await db.query(
      'reportes_offline',
      where: 'usuario_id = ? AND sincronizado = 1',
      whereArgs: [usuarioId],
    );
    return maps.map((map) => ReporteOffline.fromMap(map)).toList();
  }

  Future<bool> updateEstadoByServerId(int idServer, int estadoId, String estadoNombre) async {
    final db = await database;
    final result = await db.update(
      'reportes_offline',
      {
        'estado_id': estadoId,
        'estado_nombre': estadoNombre,
        'fecha_modificacion': DateTime.now().toIso8601String(),
      },
      where: 'id_server = ?',
      whereArgs: [idServer],
    );
    return result > 0;
  }

  Future<int> markAsDeleted(int idLocal) async {
    final db = await database;
    return await db.delete(
      'reportes_offline',
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<int> updateSyncAttempts(int idLocal, int intentos, String error) async {
    final db = await database;
    return await db.update(
      'reportes_offline',
      {
        'intentos_sync': intentos,
        'ultimo_error': error,
        'fecha_modificacion': DateTime.now().toIso8601String(),
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<int> markAsPendingDeletion(int idLocal) async {
    final db = await database;
    return await db.update(
      'reportes_offline',
      {
        'pendiente_eliminacion': 1,
        'sincronizado': 0,
        'fecha_modificacion': DateTime.now().toIso8601String(),
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<int> markAsPendingUpdate(int idLocal) async {
    final db = await database;
    return await db.update(
      'reportes_offline',
      {
        'pendiente_actualizacion': 1,
        'sincronizado': 0,
        'fecha_modificacion': DateTime.now().toIso8601String(),
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<int> saveSyncHistory(int enviados, int fallidos) async {
    final db = await database;
    return await db.insert('sincronizaciones', {
      'fecha_sync': DateTime.now().toIso8601String(),
      'reportes_enviados': enviados,
      'reportes_fallidos': fallidos,
    });
  }

  Future<int> updateReporte(ReporteOffline reporte) async {
    final db = await database;
    return await db.update(
      'reportes_offline',
      reporte.toMap(),
      where: 'id_local = ?',
      whereArgs: [reporte.idLocal],
    );
  }

  Future<int> deleteReporte(int idLocal) async {
    final db = await database;
    return await db.delete(
      'reportes_offline',
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<int> updateLocationNames(int idLocal, {
    String? departamentoNombre,
    String? provinciaNombre,
    String? municipioNombre,
  }) async {
    final data = <String, dynamic>{
      'fecha_modificacion': DateTime.now().toIso8601String(),
    };
    if (departamentoNombre != null) data['departamento_nombre'] = departamentoNombre;
    if (provinciaNombre != null) data['provincia_nombre'] = provinciaNombre;
    if (municipioNombre != null) data['municipio_nombre'] = municipioNombre;
    final db = await database;
    return await db.update('reportes_offline', data, where: 'id_local = ?', whereArgs: [idLocal]);
  }

  Future<int> saveFotografiaServerPath(int idLocal, String path) async {
    final db = await database;
    return await db.update(
      'reportes_offline',
      {
        'fotografia_server_path': path,
        'fecha_modificacion': DateTime.now().toIso8601String(),
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<void> saveEstados(List<Map<String, dynamic>> estados) async {
    final db = await database;
    final batch = db.batch();
    for (final e in estados) {
      batch.insert('catalogo_estados', e,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getEstadosLocal() async {
    final db = await database;
    return await db.query('catalogo_estados', orderBy: 'orden ASC');
  }

  Future<void> saveCategorias(List<Map<String, dynamic>> categorias) async {
    final db = await database;
    final batch = db.batch();
    for (final c in categorias) {
      batch.insert('catalogo_categorias', c,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCategoriasLocal() async {
    final db = await database;
    return await db.query('catalogo_categorias', orderBy: 'orden ASC');
  }

  Future<void> saveTiposEvento(List<Map<String, dynamic>> tipos) async {
    final db = await database;
    final batch = db.batch();
    for (final t in tipos) {
      batch.insert('catalogo_tipos_evento', t,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getTiposEventoLocal() async {
    final db = await database;
    return await db.query('catalogo_tipos_evento');
  }

  Future<void> saveTiposLocalidad(List<Map<String, dynamic>> tipos) async {
    final db = await database;
    final batch = db.batch();
    for (final t in tipos) {
      batch.insert('catalogo_tipo_localidad', t,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getTiposLocalidadLocal() async {
    final db = await database;
    return await db.query('catalogo_tipo_localidad', orderBy: 'orden ASC');
  }

  Future<void> saveEstadosEdan(List<Map<String, dynamic>> estados) async {
    final db = await database;
    final batch = db.batch();
    for (final e in estados) {
      batch.insert('catalogo_estados_edan', e,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getEstadosEdanLocal() async {
    final db = await database;
    return await db.query('catalogo_estados_edan', orderBy: 'orden ASC');
  }

  Future<void> saveCultivos(List<Map<String, dynamic>> cultivos) async {
    final db = await database;
    final batch = db.batch();
    for (final c in cultivos) {
      batch.insert('catalogo_cultivos', c,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCultivosLocal() async {
    final db = await database;
    return await db.query('catalogo_cultivos', orderBy: 'nombre ASC');
  }

  Future<void> savePecuarioGrupos(List<Map<String, dynamic>> grupos) async {
    final db = await database;
    final batch = db.batch();
    for (final g in grupos) {
      batch.insert('catalogo_pecuario_grupos', g,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getPecuarioGruposLocal() async {
    final db = await database;
    return await db.query('catalogo_pecuario_grupos', orderBy: 'nombre ASC');
  }

  Future<void> saveGruposVulnerables(List<Map<String, dynamic>> grupos) async {
    final db = await database;
    final batch = db.batch();
    for (final g in grupos) {
      batch.insert('catalogo_grupo_vulnerable', g,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getGruposVulnerablesLocal() async {
    final db = await database;
    return await db.query('catalogo_grupo_vulnerable', orderBy: 'orden ASC');
  }

  Future<void> saveDepartamentos(List<Map<String, dynamic>> departamentos) async {
    final db = await database;
    final batch = db.batch();
    for (final d in departamentos) {
      batch.insert('catalogo_departamentos', d,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getDepartamentosLocal() async {
    final db = await database;
    return await db.query('catalogo_departamentos', orderBy: 'nombre ASC');
  }

  Future<void> saveProvincias(List<Map<String, dynamic>> provincias) async {
    final db = await database;
    final batch = db.batch();
    for (final p in provincias) {
      batch.insert('catalogo_provincias', p,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getProvinciasLocal() async {
    final db = await database;
    return await db.query('catalogo_provincias', orderBy: 'nombre ASC');
  }

  Future<void> saveMunicipios(List<Map<String, dynamic>> municipios) async {
    final db = await database;
    final batch = db.batch();
    for (final m in municipios) {
      batch.insert('catalogo_municipios', m,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getMunicipiosLocal() async {
    final db = await database;
    return await db.query('catalogo_municipios', orderBy: 'nombre ASC');
  }

  Future<void> saveTiposRepositorio(List<Map<String, dynamic>> tipos) async {
    final db = await database;
    final batch = db.batch();
    for (final t in tipos) {
      batch.insert('catalogo_tipos_repositorio', t,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getTiposRepositorioLocal() async {
    final db = await database;
    return await db.query('catalogo_tipos_repositorio',
        where: 'activo = 1', orderBy: 'orden ASC, nombre ASC');
  }

  Future<bool> upsertReportFromServer(int usuarioId, Map<String, dynamic> data) async {
    final db = await database;
    final idServer = data['id_reporte'] as int?;
    if (idServer == null) return false;

    final existing = await db.query(
      'reportes_offline',
      where: 'id_server = ?',
      whereArgs: [idServer],
      limit: 1,
    );

    final categorias = data['categorias'] != null
        ? (data['categorias'] as List)
            .map((c) => c is Map ? (c['id_categoria'] ?? c['id']) as int : c as int)
            .toList()
        : null;

    final row = {
      'usuario_id': usuarioId,
      'id_server': idServer,
      'departamento_id': (data['id_departamento'] as num?)?.toInt() ?? 0,
      'provincia_id': (data['id_provincia'] as num?)?.toInt() ?? 0,
      'municipio_id': (data['id_municipio'] as num?)?.toInt() ?? 0,
      'comunidad': (data['comunidad'] as String?) ?? '',
      'departamento_nombre': data['departamento']?['nombre'] as String?,
      'provincia_nombre': data['provincia']?['nombre'] as String?,
      'municipio_nombre': data['municipio']?['nombre'] as String?,
      'fecha_evento': (data['fecha_evento'] as String?) ?? DateTime.now().toIso8601String(),
      'hora_evento': data['hora_evento'] as String?,
      'tipo_evento_id': (data['id_tipo_evento'] as num?)?.toInt() ?? 0,
      'coordenada_lat': double.tryParse(data['coordenada_lat']?.toString() ?? ''),
      'coordenada_lon': double.tryParse(data['coordenada_lon']?.toString() ?? ''),
      'descripcion': data['descripcion'] as String?,
      'estado_id': (data['id_estado'] as num?)?.toInt() ?? 1,
      'estado_nombre': data['estado']?['nombre'] as String?,
      'categorias': categorias != null ? jsonEncode(categorias) : null,
      'fotografia_server_path': data['fotografia'] as String?,
      'sincronizado': 1,
      'pendiente_eliminacion': 0,
      'pendiente_actualizacion': 0,
      'fecha_creacion': data['fecha_reporte'] as String? ?? DateTime.now().toIso8601String(),
      'fecha_modificacion': DateTime.now().toIso8601String(),
      'intentos_sync': 0,
      'ultimo_error': null,
    };

    if (existing.isNotEmpty) {
      final idLocal = existing.first['id_local'] as int;
      row['id_local'] = idLocal;
      row['imagenes'] = existing.first['imagenes'];
      await db.update('reportes_offline', row, where: 'id_local = ?', whereArgs: [idLocal]);
    } else {
      await db.insert('reportes_offline', row);
    }
    return true;
  }

  Future<void> updateReporteLocalImage(int idServer, String localPath) async {
    final db = await database;
    final existing = await db.query(
      'reportes_offline',
      where: 'id_server = ?',
      whereArgs: [idServer],
      limit: 1,
    );
    if (existing.isEmpty) return;
    final idLocal = existing.first['id_local'] as int;
    final currentImages = existing.first['imagenes'] as String?;
    final imageList = currentImages != null
        ? List<String>.from(jsonDecode(currentImages))
        : <String>[];
    if (!imageList.contains(localPath)) {
      imageList.add(localPath);
    }
    await db.update(
      'reportes_offline',
      {'imagenes': jsonEncode(imageList)},
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<void> saveMunicipioGeojson({
    required int municipioId,
    required String codigoIne,
    String? nombre,
    required String geojson,
  }) async {
    final db = await database;
    await db.insert(
      'municipio_geojson',
      {
        'municipio_id': municipioId,
        'codigo_ine': codigoIne,
        'nombre': nombre,
        'geojson': geojson,
        'fecha_actualizacion': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getMunicipioGeojsonLocal(int municipioId) async {
    final db = await database;
    final maps = await db.query(
      'municipio_geojson',
      where: 'municipio_id = ?',
      whereArgs: [municipioId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return maps.first;
  }

  Future<List<ReporteOffline>> getReportesSinDescargar(int usuarioId) async {
    final db = await database;
    final maps = await db.query(
      'reportes_offline',
      where: 'usuario_id = ? AND fotografia_server_path IS NOT NULL AND imagen_descargada = 0 AND (imagenes IS NULL OR imagenes = ?)',
      whereArgs: [usuarioId, '[]'],
    );
    return maps.map((map) => ReporteOffline.fromMap(map)).toList();
  }

  Future<void> marcarImagenDescargada(int idLocal) async {
    final db = await database;
    await db.update(
      'reportes_offline',
      {'imagen_descargada': 1},
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Edan _edanFromRow(Map<String, dynamic> row) {
    final datos = jsonDecode(row['datos_json'] as String);
    final edan = Edan.fromJson(Map<String, dynamic>.from(datos as Map));
    edan.idLocal = row['id_local'] as int;
    edan.idServer = row['id_server'] as int?;
    edan.idEdan = row['id_edan'] as int?;
    edan.sincronizado = _toBool(row['sincronizado']);
    edan.pendienteEliminacion = _toBool(row['pendiente_eliminacion']);
    edan.pendienteActualizacion = _toBool(row['pendiente_actualizacion']);
    edan.esBorrador = _toBool(row['es_borrador']);
    return edan;
  }

  Future<int> insertEdan(
    Edan edan, {
    required int usuarioId,
    String? municipioNombre,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final row = {
      'id_server': edan.idServer,
      'id_edan': edan.idEdan,
      'usuario_id': usuarioId,
      'codigo_edan': edan.codigoEdan,
      'municipio_id': edan.idMunicipio,
      'municipio_nombre': municipioNombre ?? edan.municipioNombre,
      'fecha_evento': edan.fechaEvento,
      'fecha_llenado': edan.fechaLlenado,
      'id_estado': edan.idEstado,
      'estado_edan': edan.estado,
      'datos_json': jsonEncode(edan.toJson()),
      'sincronizado': 0,
      'pendiente_eliminacion': 0,
      'pendiente_actualizacion': 0,
      'es_borrador': edan.estado == 'borrador' ? 1 : 0,
      'fecha_creacion': now,
      'fecha_modificacion': now,
      'intentos_sync': 0,
    };
    final idLocal = await db.insert('edans_offline', row);
    edan.idLocal = idLocal;
    return idLocal;
  }

  Future<List<Edan>> getEdans(int usuarioId) async {
    final db = await database;
    final maps = await db.query(
      'edans_offline',
      where: 'usuario_id = ?',
      whereArgs: [usuarioId],
      orderBy: 'fecha_creacion DESC',
    );
    return maps.map((map) => _edanFromRow(map)).toList();
  }

  Future<List<Edan>> getUnsyncedEdans() async {
    final db = await database;
    final maps = await db.query(
      'edans_offline',
      where: '(sincronizado = 0 OR pendiente_actualizacion = 1) AND pendiente_eliminacion = 0',
      orderBy: 'fecha_creacion ASC',
    );
    return maps.map((map) => _edanFromRow(map)).toList();
  }

  Future<int> countEdansPendientesSync() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM edans_offline '
      'WHERE ((sincronizado = 0 OR pendiente_actualizacion = 1) AND pendiente_eliminacion = 0) '
      'OR pendiente_eliminacion = 1',
    );
    if (result.isEmpty) return 0;
    return (result.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<int> updateEdan(Edan edan) async {
    if (edan.idLocal == null) return 0;
    final db = await database;
    return await db.update(
      'edans_offline',
      {
        'id_server': edan.idServer,
        'id_edan': edan.idEdan,
        'codigo_edan': edan.codigoEdan,
        'municipio_id': edan.idMunicipio,
        'municipio_nombre': edan.municipioNombre,
        'fecha_evento': edan.fechaEvento,
        'fecha_llenado': edan.fechaLlenado,
        'id_estado': edan.idEstado,
        'estado_edan': edan.estado,
        'datos_json': jsonEncode(edan.toJson()),
        'sincronizado': 0,
        'pendiente_actualizacion': 1,
        'es_borrador': edan.estado == 'borrador' ? 1 : 0,
        'fecha_modificacion': DateTime.now().toIso8601String(),
      },
      where: 'id_local = ?',
      whereArgs: [edan.idLocal],
    );
  }

  Future<int> deleteEdan(int idLocal) async {
    final db = await database;
    return await db.delete(
      'edans_offline',
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<int> markEdanAsSynced(int idLocal, int idServer) async {
    final db = await database;
    return await db.update(
      'edans_offline',
      {
        'id_server': idServer,
        'id_edan': idServer,
        'sincronizado': 1,
        'pendiente_eliminacion': 0,
        'pendiente_actualizacion': 0,
        'intentos_sync': 0,
        'ultimo_error': null,
        'fecha_modificacion': DateTime.now().toIso8601String(),
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<int> markEdanAsPendingDeletion(int idLocal) async {
    final db = await database;
    return await db.update(
      'edans_offline',
      {
        'pendiente_eliminacion': 1,
        'sincronizado': 0,
        'fecha_modificacion': DateTime.now().toIso8601String(),
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<int> updateEdanSyncAttempts(int idLocal, int intentos, String error) async {
    final db = await database;
    return await db.update(
      'edans_offline',
      {
        'intentos_sync': intentos,
        'ultimo_error': error,
        'fecha_modificacion': DateTime.now().toIso8601String(),
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<int> countEdansPorMunicipioAnio(int municipioId, int year) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM edans_offline '
      'WHERE municipio_id = ? AND fecha_llenado LIKE ?',
      [municipioId, '$year-%'],
    );
    if (result.isEmpty) return 0;
    return (result.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<List<Edan>> getEdansByMunicipio(int municipioId) async {
    final db = await database;
    final maps = await db.query(
      'edans_offline',
      where: 'municipio_id = ? AND pendiente_eliminacion = 0',
      whereArgs: [municipioId],
      orderBy: 'fecha_creacion DESC',
    );
    return maps.map((map) => _edanFromRow(map)).toList();
  }

  Future<String?> getCodigoIneMunicipio(int municipioId) async {
    final db = await database;
    final maps = await db.query(
      'municipio_geojson',
      columns: ['codigo_ine'],
      where: 'municipio_id = ?',
      whereArgs: [municipioId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return maps.first['codigo_ine']?.toString();
  }

  Future<String> generarSiguienteCodigoEdan({
    required int year,
    required int municipioId,
    required String codigoIne,
  }) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT MAX(CAST(SUBSTR(codigo_edan, -3) AS INTEGER)) AS max_n '
      'FROM edans_offline WHERE codigo_edan LIKE ?',
      ['$codigoIne/$year-%'],
    );
    final maxN = result.isNotEmpty && result.first['max_n'] != null
        ? int.tryParse(result.first['max_n'].toString()) ?? 0
        : 0;
    return '$codigoIne/$year/${(maxN + 1).toString().padLeft(3, '0')}';
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('reportes_offline');
    await db.delete('borradores');
    await db.delete('sincronizaciones');
    await db.delete('catalogo_estados');
    await db.delete('catalogo_categorias');
    await db.delete('catalogo_tipos_evento');
    await db.delete('catalogo_estados_edan');
    await db.delete('catalogo_cultivos');
    await db.delete('catalogo_pecuario_grupos');
    await db.delete('catalogo_grupo_vulnerable');
    await db.delete('catalogo_tipos_repositorio');
    await db.delete('municipio_geojson');
    await db.delete('edans_offline');
    await db.delete('localidades_offline');
    _database = null;
  }

  Future<int?> getLastSyncDate() async {
    final db = await database;
    final result = await db.rawQuery('SELECT valor FROM config WHERE clave = ?', ['ultima_sync']);
    if (result.isEmpty) return null;
    return int.tryParse(result.first['valor']?.toString() ?? '');
  }

  Future<void> saveLastSyncDate(int timestamp) async {
    final db = await database;
    await db.rawInsert('''
      INSERT OR REPLACE INTO config (clave, valor) VALUES (?, ?)
    ''', ['ultima_sync', timestamp]);
  }

  Future<Edan?> getEdanByServerId(int idServer) async {
    final db = await database;
    final maps = await db.query(
      'edans_offline',
      where: 'id_server = ?',
      whereArgs: [idServer],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return _edanFromRow(maps.first);
  }

  Future<Edan?> getEdanByIdLocal(int idLocal) async {
    final db = await database;
    final maps = await db.query(
      'edans_offline',
      where: 'id_local = ?',
      whereArgs: [idLocal],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return _edanFromRow(maps.first);
  }

  Future<List<Edan>> getEdansPendingDeletion() async {
    final db = await database;
    final maps = await db.query(
      'edans_offline',
      where: 'pendiente_eliminacion = 1',
      orderBy: 'fecha_creacion ASC',
    );
    return maps.map((map) => _edanFromRow(map)).toList();
  }

  // ========== LOCALIDADES_OFFLINE CRUD ==========

  EdanLocalidad _localidadFromRow(Map<String, dynamic> row) {
    final datos = jsonDecode(row['datos_json'] as String);
    final loc = EdanLocalidad.fromJson(Map<String, dynamic>.from(datos as Map));
    loc.idLocal = row['id_local'] as String;
    loc.idServer = _toInt(row['id_server']);
    loc.idEdan = _toInt(row['id_edan']);
    loc.idUsuario = _toInt(row['usuario_id']);
    loc.idEdanLocalidadEstado = _toInt(row['id_edan_localidad_estado']);
    loc.estadoLocalidad = _estadoLocalidadFromNombre(row['estado_localidad'] as String?);
    loc.sincronizado = _toBool(row['sincronizado']);
    loc.pendienteEliminacion = _toBool(row['pendiente_eliminacion']);
    loc.pendienteActualizacion = _toBool(row['pendiente_actualizacion']);
    // Fallback: resolver nombres desde columnas si datos_json no los tiene
    if (loc.departamentoNombre == null || loc.departamentoNombre!.isEmpty) {
      loc.departamentoNombre = row['departamento_nombre'] as String?;
    }
    if (loc.provinciaNombre == null || loc.provinciaNombre!.isEmpty) {
      loc.provinciaNombre = row['provincia_nombre'] as String?;
    }
    if (loc.municipioNombre == null || loc.municipioNombre!.isEmpty) {
      loc.municipioNombre = row['municipio_nombre'] as String?;
    }
    return loc;
  }

  UgrLocalidadEstado? _estadoLocalidadFromNombre(String? nombre) {
    if (nombre == null) return null;
    final n = nombre.toLowerCase();
    if (n.contains('borrador')) return UgrLocalidadEstado.borrador;
    if (n.contains('enviado')) return UgrLocalidadEstado.enviadoUgr;
    if (n.contains('revision')) return UgrLocalidadEstado.enRevisionUgr;
    if (n.contains('aprobado') && n.contains('ajuste')) return UgrLocalidadEstado.aprobadoAjuste;
    if (n.contains('aprobado')) return UgrLocalidadEstado.aprobadoUgr;
    if (n.contains('rechazado')) return UgrLocalidadEstado.rechazadoUgr;
    return null;
  }

  Future<String> insertLocalidad(
    EdanLocalidad localidad, {
    required int usuarioId,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    localidad.fechaModificacion = now;
    final row = {
      'id_local': localidad.idLocal ?? _generateUuid(),
      'id_server': localidad.idServer,
      'id_edan': localidad.idEdan,
      'es_huerfana': localidad.esHuerfana ? 1 : 0,
      'usuario_id': usuarioId,
      'id_tipo_localidad': localidad.idTipoLocalidad,
      'id_tipo_evento': localidad.idTipoEvento,
      'id_departamento': localidad.idDepartamento,
      'id_provincia': localidad.idProvincia,
      'id_municipio': localidad.idMunicipio,
      'departamento_nombre': localidad.departamentoNombre,
      'provincia_nombre': localidad.provinciaNombre,
      'municipio_nombre': localidad.municipioNombre,
      'localidad': localidad.nombre,
      'fecha_llenado': localidad.fechaLlenado,
      'fecha_evento': localidad.fechaEvento,
      'hora_evento': localidad.horaEvento,
      'total_poblacion_afectada': localidad.totalPoblacionAfectada,
      'total_familias_afectadas': localidad.totalFamiliasAfectadas,
      'total_familias_damnificadas': localidad.totalFamiliasDamnificadas,
      'imp_poblacion': localidad.impPoblacion ? 1 : 0,
      'imp_salud': localidad.impSalud ? 1 : 0,
      'imp_infraestructura': localidad.impInfraestructura ? 1 : 0,
      'imp_servicios': localidad.impServicios ? 1 : 0,
      'imp_educacion': localidad.impEducacion ? 1 : 0,
      'imp_vivienda': localidad.impVivienda ? 1 : 0,
      'imp_agropecuario': localidad.impAgropecuario ? 1 : 0,
      'imp_proteccion': localidad.impProteccion ? 1 : 0,
      'imp_necesidades': localidad.impNecesidades ? 1 : 0,
      'id_edan_localidad_estado': localidad.idEdanLocalidadEstado,
      'estado_localidad': localidad.estadoLocalidad?.label,
      'datos_json': jsonEncode(localidad.toJson()),
      'sincronizado': 0,
      'pendiente_eliminacion': 0,
      'pendiente_actualizacion': 0,
      'fecha_creacion': now,
      'fecha_modificacion': now,
      'intentos_sync': 0,
    };
    try {
      await db.insert('localidades_offline', row, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      debugPrint('[insertLocalidad] Error insertando localidad ${localidad.idLocal}: $e');
      rethrow;
    }
    return row['id_local'] as String;
  }

  Future<List<EdanLocalidad>> getLocalidades(int usuarioId) async {
    final db = await database;
    final maps = await db.query(
      'localidades_offline',
      where: 'usuario_id = ?',
      whereArgs: [usuarioId],
      orderBy: 'fecha_creacion DESC',
    );
    return maps.map((map) => _localidadFromRow(map)).toList();
  }

  Future<List<EdanLocalidad>> getLocalidadesHuerfanas(int usuarioId) async {
    final db = await database;
    final maps = await db.query(
      'localidades_offline',
      where: 'usuario_id = ? AND id_edan IS NULL',
      whereArgs: [usuarioId],
      orderBy: 'fecha_creacion DESC',
    );
    return maps.map((map) => _localidadFromRow(map)).toList();
  }

  Future<List<EdanLocalidad>> getLocalidadesPendientesUsuario(int usuarioId) async {
    final db = await database;
    final maps = await db.query(
      'localidades_offline',
      where: 'usuario_id = ? AND sincronizado = 0 AND pendiente_eliminacion = 0',
      whereArgs: [usuarioId],
      orderBy: 'fecha_creacion DESC',
    );
    return maps.map((map) => _localidadFromRow(map)).toList();
  }

  Future<List<EdanLocalidad>> getUnsyncedLocalidades() async {
    final db = await database;
    final maps = await db.query(
      'localidades_offline',
      where: '(sincronizado = 0 OR pendiente_actualizacion = 1) AND pendiente_eliminacion = 0',
      orderBy: 'fecha_creacion ASC',
    );
    return maps.map((map) => _localidadFromRow(map)).toList();
  }

  Future<int> countLocalidadesPendientesSync() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM localidades_offline '
      'WHERE (sincronizado = 0 AND pendiente_eliminacion = 0) '
      'OR pendiente_eliminacion = 1',
    );
    if (result.isEmpty) return 0;
    return (result.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<int> updateLocalidad(EdanLocalidad localidad) async {
    if (localidad.idLocal == null) return 0;
    final db = await database;
    final now = DateTime.now().toIso8601String();
    localidad.fechaModificacion = now;
    return await db.update(
      'localidades_offline',
      {
        'id_server': localidad.idServer,
        'id_edan': localidad.idEdan,
        'es_huerfana': localidad.esHuerfana ? 1 : 0,
        'id_tipo_localidad': localidad.idTipoLocalidad,
        'id_tipo_evento': localidad.idTipoEvento,
        'id_departamento': localidad.idDepartamento,
        'id_provincia': localidad.idProvincia,
        'id_municipio': localidad.idMunicipio,
        'departamento_nombre': localidad.departamentoNombre,
        'provincia_nombre': localidad.provinciaNombre,
        'municipio_nombre': localidad.municipioNombre,
        'localidad': localidad.nombre,
        'fecha_llenado': localidad.fechaLlenado,
        'fecha_evento': localidad.fechaEvento,
        'hora_evento': localidad.horaEvento,
        'total_poblacion_afectada': localidad.totalPoblacionAfectada,
        'total_familias_afectadas': localidad.totalFamiliasAfectadas,
        'total_familias_damnificadas': localidad.totalFamiliasDamnificadas,
        'imp_poblacion': localidad.impPoblacion ? 1 : 0,
        'imp_salud': localidad.impSalud ? 1 : 0,
        'imp_infraestructura': localidad.impInfraestructura ? 1 : 0,
        'imp_servicios': localidad.impServicios ? 1 : 0,
        'imp_educacion': localidad.impEducacion ? 1 : 0,
        'imp_vivienda': localidad.impVivienda ? 1 : 0,
        'imp_agropecuario': localidad.impAgropecuario ? 1 : 0,
        'imp_proteccion': localidad.impProteccion ? 1 : 0,
        'imp_necesidades': localidad.impNecesidades ? 1 : 0,
        'id_edan_localidad_estado': localidad.idEdanLocalidadEstado,
        'estado_localidad': localidad.estadoLocalidad?.label,
        'datos_json': jsonEncode(localidad.toJson()),
        'sincronizado': 0,
        'pendiente_actualizacion': 1,
        'pendiente_eliminacion': localidad.pendienteEliminacion ? 1 : 0,
        'fecha_modificacion': now,
      },
      where: 'id_local = ?',
      whereArgs: [localidad.idLocal],
    );
  }

  Future<int> deleteLocalidad(String idLocal) async {
    final db = await database;
    return await db.delete(
      'localidades_offline',
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<int> markLocalidadAsSynced(String idLocal, int idServer) async {
    final db = await database;
    return await db.update(
      'localidades_offline',
      {
        'id_server': idServer,
        'sincronizado': 1,
        'pendiente_eliminacion': 0,
        'pendiente_actualizacion': 0,
        'intentos_sync': 0,
        'ultimo_error': null,
        'fecha_modificacion': DateTime.now().toIso8601String(),
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<int> markLocalidadAsPendingDeletion(String idLocal) async {
    final db = await database;
    return await db.update(
      'localidades_offline',
      {
        'pendiente_eliminacion': 1,
        'sincronizado': 0,
        'fecha_modificacion': DateTime.now().toIso8601String(),
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<int> updateLocalidadSyncAttempts(String idLocal, int intentos, String error) async {
    final db = await database;
    return await db.update(
      'localidades_offline',
      {
        'intentos_sync': intentos,
        'ultimo_error': error,
        'fecha_modificacion': DateTime.now().toIso8601String(),
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<EdanLocalidad?> getLocalidadByIdLocal(String idLocal) async {
    final db = await database;
    final maps = await db.query(
      'localidades_offline',
      where: 'id_local = ?',
      whereArgs: [idLocal],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return _localidadFromRow(maps.first);
  }

  Future<List<EdanLocalidad>> getLocalidadesPendingDeletion() async {
    final db = await database;
    final maps = await db.query(
      'localidades_offline',
      where: 'pendiente_eliminacion = 1',
      orderBy: 'fecha_creacion ASC',
    );
    return maps.map((map) => _localidadFromRow(map)).toList();
  }

  String _generateUuid() {
    return '${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
  }

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  bool _toBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    return value.toString().toLowerCase() == 'true';
  }
}
