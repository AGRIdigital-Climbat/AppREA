import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
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
      version: 6,
      onCreate: _createDatabase,
      onUpgrade: _onUpgrade,
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
        ultimo_error TEXT
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
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE reportes_offline ADD COLUMN es_borrador INTEGER DEFAULT 0');
    }
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
      'departamento_id': data['id_departamento'] as int,
      'provincia_id': data['id_provincia'] as int,
      'municipio_id': data['id_municipio'] as int,
      'comunidad': data['comunidad'] as String,
      'departamento_nombre': data['departamento']?['nombre'] as String?,
      'provincia_nombre': data['provincia']?['nombre'] as String?,
      'municipio_nombre': data['municipio']?['nombre'] as String?,
      'fecha_evento': data['fecha_evento'] as String,
      'hora_evento': data['hora_evento'] as String?,
      'tipo_evento_id': data['id_tipo_evento'] as int,
      'coordenada_lat': double.tryParse(data['coordenada_lat']?.toString() ?? ''),
      'coordenada_lon': double.tryParse(data['coordenada_lon']?.toString() ?? ''),
      'descripcion': data['descripcion'] as String?,
      'estado_id': data['id_estado'] as int? ?? 1,
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
}
