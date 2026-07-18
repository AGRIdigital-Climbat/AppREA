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
      version: 1,
      onCreate: _createDatabase,
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
        fecha_evento TEXT NOT NULL,
        hora_evento TEXT,
        tipo_evento_id INTEGER NOT NULL,
        coordenada_lat REAL,
        coordenada_lon REAL,
        descripcion TEXT,
        estado_id INTEGER DEFAULT 1,
        categorias TEXT,
        imagenes TEXT,
        sincronizado INTEGER DEFAULT 0,
        pendiente_eliminacion INTEGER DEFAULT 0,
        pendiente_actualizacion INTEGER DEFAULT 0,
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
      where: 'sincronizado = 0',
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
}
