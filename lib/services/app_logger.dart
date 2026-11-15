import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common/sqflite_logger.dart';

import 'sync_debug_config.dart';

/// Niveles de una entrada del registro global de la app.
enum AppLogLevel { debug, info, warn, error }

/// Categorías de una entrada del registro global.
///
/// Cada punto de captura de la app usa una: [api] (llamadas HTTP), [sql]
/// (toda sentencia que pasa por sqflite), [sync] (fases y diagnósticos del
/// motor V2), [nav] (pantallas que se abren/cierran), [error] (excepciones
/// globales), [app] (arranque, red, sesión) y [auth] (login/logout).
enum AppLogCategoria { api, sql, sync, nav, error, app, auth }

String _nombreNivel(AppLogLevel n) => n.name.toUpperCase();

String _nombreCategoria(AppLogCategoria c) => c.name.toUpperCase();

/// Una entrada leída desde la base de datos de logs.
///
/// Todos los campos de texto guardan el contenido COMPLETO (request, response,
/// error, stack): el visor muestra todo el detalle y nada se recorta.
class LogEntry {
  final int id;
  final DateTime timestamp;
  final AppLogLevel nivel;
  final AppLogCategoria categoria;
  final String titulo;
  final String? detalle;
  final String? metodo;
  final String? url;
  final int? estado;
  final int? durMs;
  final String? request;
  final String? response;
  final String? error;
  final String? stack;
  final String? pantalla;

  /// `true` si el código >= 400 es un resultado **esperado** (p. ej. una foto
  /// legacy que ya no existe en el servidor). Se registra igual (status, cuerpo
  /// y todo el detalle), pero NO cuenta como error: queda fuera del filtro
  /// «solo errores» y del nivel `error`.
  final bool esperado;

  const LogEntry({
    required this.id,
    required this.timestamp,
    required this.nivel,
    required this.categoria,
    required this.titulo,
    this.detalle,
    this.metodo,
    this.url,
    this.estado,
    this.durMs,
    this.request,
    this.response,
    this.error,
    this.stack,
    this.pantalla,
    this.esperado = false,
  });

  factory LogEntry.fromMap(Map<String, Object?> m) => LogEntry(
        id: m['id'] as int,
        timestamp: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int),
        nivel: AppLogLevel.values.firstWhere(
          (e) => e.name == (m['nivel'] as String).toLowerCase(),
          orElse: () => AppLogLevel.info,
        ),
        categoria: AppLogCategoria.values.firstWhere(
          (e) => e.name == (m['categoria'] as String).toLowerCase(),
          orElse: () => AppLogCategoria.app,
        ),
        titulo: m['titulo'] as String,
        detalle: m['detalle'] as String?,
        metodo: m['metodo'] as String?,
        url: m['url'] as String?,
        estado: m['estado'] as int?,
        durMs: m['dur_ms'] as int?,
        request: m['request'] as String?,
        response: m['response'] as String?,
        error: m['error'] as String?,
        stack: m['stack'] as String?,
        pantalla: m['pantalla'] as String?,
        esperado: (m['esperado'] as int? ?? 0) == 1,
      );

  bool get esError =>
      nivel == AppLogLevel.error ||
      (!esperado &&
          ((estado != null && estado! >= 400) || error != null));

  /// Versión de texto completo, usada por copiar/exportar/compartir.
  String aTexto() {
    final sb = StringBuffer();
    sb.writeln(
      '${_selloCompleto(timestamp)} [${_nombreNivel(nivel)}] '
      '[${_nombreCategoria(categoria)}] $titulo',
    );
    if (pantalla != null && pantalla!.isNotEmpty) {
      sb.writeln('  pantalla : $pantalla');
    }
    if (metodo != null || url != null) {
      final partes = <String>[];
      if (metodo != null) partes.add(metodo!);
      if (url != null) partes.add(enmascararUrl(url!));
      if (estado != null) partes.add('→ $estado');
      if (durMs != null) partes.add('${durMs}ms');
      sb.writeln('  http     : ${partes.join(' ')}');
    }
    if (detalle != null && detalle!.isNotEmpty) {
      sb.writeln('  detalle  : ${scrubUrls(detalle!)}');
    }
    if (esperado) {
      sb.writeln('  nota     : fallo esperado (no cuenta como error)');
    }
    if (request != null && request!.isNotEmpty) {
      sb.writeln('  REQUEST  :');
      sb.writeln(_sangria(request!));
    }
    if (response != null && response!.isNotEmpty) {
      sb.writeln('  RESPONSE :');
      sb.writeln(_sangria(response!));
    }
    if (error != null && error!.isNotEmpty) {
      sb.writeln('  ERROR    : $error');
    }
    if (stack != null && stack!.isNotEmpty) {
      sb.writeln('  STACK    :');
      sb.writeln(_sangria(stack!));
    }
    return sb.toString();
  }

  static String _sangria(String texto) =>
      texto.split('\n').map((l) => '    $l').join('\n');

  static String _selloCompleto(DateTime t) {
    String dos(int v) => v.toString().padLeft(2, '0');
    String tres(int v) => v.toString().padLeft(3, '0');
    return '${t.year}-${dos(t.month)}-${dos(t.day)} '
        '${dos(t.hour)}:${dos(t.minute)}:${dos(t.second)}.${tres(t.millisecond)}';
  }
}

/// Registro global y persistente de TODO lo que hace la app durante las
/// últimas 24 horas.
///
/// Diseñado para monitorear fallos en dispositivo real sin depender de ADB:
/// cada HTTP (request y respuesta completos), cada sentencia SQLite (SQL +
/// argumentos), cada clic, cada pantalla abierta, cada fase del sync y cada
/// error con su stack se guardan en `rea_app_logs.db`. Nada se trunca: los
/// campos TEXT guardan el contenido íntegro. (Única excepción intencionada:
/// la contraseña de `POST /auth/login` se guarda como `***`, porque un
/// monitor no necesita leer claves en claro.)
///
/// La retención es de exactamente 1 día: al arrancar y cada 10 minutos se
/// purgan las entradas con más de 24 h.
///
/// Por defecto está DESACTIVADO (no-op puro) para no afectar a los tests.
/// [inicializar] lo enciende desde `main.dart` antes de `runApp`.
class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  /// Retención del log: 1 día.
  static const Duration retencion = Duration(hours: 24);

  /// Intervalo de volcado de la cola a disco.
  static const Duration _intervaloFlush = Duration(milliseconds: 400);

  /// Máximo de entradas en cola antes de forzar un flush inmediato.
  static const int _maxCola = 2000;

  /// Techo duro de entradas en la tabla (por si el purgado falla o el día fue
  /// muy intenso): se conservan las N más nuevas.
  static const int _maxFilas = 200000;

  /// Ruta alterna solo para pruebas (mismo patrón que DatabaseHelper).
  @visibleForTesting
  static String? rutaDePrueba;

  Database? _db;
  bool _habilitado = false;
  bool _iniciando = false;

  /// Cola de filas pendientes de insertar.
  final List<Map<String, Object?>> _cola = [];
  Timer? _flushTimer;
  Timer? _purgaTimer;

  /// Factory original (sin envolver) para abrir la BD de logs y para restaurar
  /// en pruebas. El wrap de SQL se pone sobre la factory GLOBAL, y la BD de
  /// logs se abre con esta, sin envoltorios → sin recursión.
  DatabaseFactory? _factoryOriginal;

  /// Ruta del archivo de la BD de logs (null si no inicializado).
  String? _rutaBd;

  /// Contador de entradas descartadas por colas desbordadas (nunca pasa en
  /// operación normal; si pasa, se deja constancia en el propio log).
  int _descartadas = 0;

  bool get habilitado => _habilitado;

  String? get rutaBd => _rutaBd;

  /// Última pantalla conocida (la fija el observador de navegación / la UI).
  String? pantallaActual;

  /// Inicializa el logger:
  ///  1. abre `rea_app_logs.db` con la factory cruda,
  ///  2. purga lo mayor a 24 h,
  ///  3. envuelve la factory global de sqflite con [SqfliteDatabaseFactoryLogger]
  ///     para capturar TODA sentencia SQL (con argumentos y resultados),
  ///  4. arranca los timers de flush y purga.
  ///
  /// Ante cualquier error queda deshabilitado (no-op) y devuelve la causa;
  /// la app sigue funcionando normal.
  Future<String?> inicializar() async {
    if (_iniciando) return null;
    _iniciando = true;
    try {
      _factoryOriginal = databaseFactoryOrNull ?? databaseFactory;

      final path = rutaDePrueba ?? await _rutaArchivoLog();
      _db = await _abrirBdLogs(path);
      _rutaBd = path;
      await _purgar();

      // Envolver la factory global: toda BD abierta DESPUÉS de aquí pasa por
      // el colector SQL. La propia BD de logs se abrió con la cruda.
      try {
        // ignore: experimental_member_use
        databaseFactory = SqfliteDatabaseFactoryLogger(
          databaseFactory,
          options: SqfliteLoggerOptions(
            type: SqfliteDatabaseFactoryLoggerType.all,
            log: _onEventoSql,
          ),
        );
      } catch (_) {
        // Si la plataforma no permite envolver (factory no estándar), se
        // pierde solo la captura SQL; el resto sigue operativo.
      }

      _flushTimer = Timer.periodic(_intervaloFlush, (_) => _flush());
      _purgaTimer = Timer.periodic(
        const Duration(minutes: 10),
        (_) => _purgar(),
      );
      _habilitado = true;
      return path;
    } catch (e, s) {
      _habilitado = false;
      // ignore: avoid_print
      print('[AppLogger] deshabilitado: $e\n$s');
      return null;
    } finally {
      _iniciando = false;
    }
  }

  /// Cierra y desactiva. Solo pruebas.
  @visibleForTesting
  Future<void> apagarParaPrueba() async {
    _habilitado = false;
    _flushTimer?.cancel();
    _purgaTimer?.cancel();
    _flushTimer = null;
    _purgaTimer = null;
    if (_cola.isNotEmpty) {
      await _flush();
    }
    await _db?.close();
    _db = null;
    _rutaBd = null;
    final original = _factoryOriginal;
    if (original != null) {
      try {
        databaseFactory = original;
      } catch (_) {}
    }
    _factoryOriginal = null;
    _descartadas = 0;
  }

  Future<String> _rutaArchivoLog() async {
    String dirPath;
    if (Platform.isWindows || Platform.isLinux) {
      final dir = await getApplicationSupportDirectory();
      dirPath = dir.path;
    } else {
      dirPath = await getDatabasesPath();
    }
    return p.join(dirPath, 'rea_app_logs.db');
  }

  Future<Database> _abrirBdLogs(String path) {
    final factory = _factoryOriginal ?? databaseFactory;
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        singleInstance: true,
        onCreate: (db, v) async {
          await db.execute('''
            CREATE TABLE logs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              ts INTEGER NOT NULL,
              nivel TEXT NOT NULL,
              categoria TEXT NOT NULL,
              titulo TEXT NOT NULL,
              detalle TEXT,
              metodo TEXT,
              url TEXT,
              estado INTEGER,
              dur_ms INTEGER,
              request TEXT,
              response TEXT,
              error TEXT,
              stack TEXT,
              pantalla TEXT,
              esperado INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('CREATE INDEX idx_logs_ts ON logs(ts)');
          await db.execute('CREATE INDEX idx_logs_cat ON logs(categoria, nivel)');
        },
        // v2: columna `esperado` (>=400 previstos, p. ej. foto legacy ya
        // borrada del servidor) que quedan fuera del filtro «solo errores».
        onUpgrade: (db, desde, _) async {
          if (desde < 2) {
            await db.execute(
              'ALTER TABLE logs ADD COLUMN esperado INTEGER NOT NULL DEFAULT 0',
            );
          }
        },
      ),
    );
  }

  // ── Captura ────────────────────────────────────────────────────────────────

  /// Registra una llamada HTTP con request y response COMPLETOS.
  ///
  /// [request] y [response] se guardan tal cual (texto largo o JSON). El único
  /// contenido que se sustituye es la contraseña de login (`***`), y los
  /// cuerpos binarios (fotos bajadas) se describen con su tamaño en vez de
  /// volcar megas de bytes.
  ///
  /// [esErrorEsperado]: úsalo cuando un `>= 400` sea un resultado **previsto**
  /// por la lógica de negocio (descarga de una foto legacy que ya no existe en
  /// el servidor, `HEAD` opcional, etc.). El status y el cuerpo se registran
  /// igual, pero NO se fuerza el nivel `error` y la entrada queda excluida del
  /// filtro «solo errores» (campo `esperado` en la BD).
  void api({
    required String metodo,
    required String url,
    int? estado,
    Duration? duracion,
    String? request,
    String? response,
    String? error,
    StackTrace? stack,
    AppLogLevel nivel = AppLogLevel.info,
    String? nota,
    bool esErrorEsperado = false,
  }) {
    final esFallo = !esErrorEsperado &&
        (error != null || (estado != null && estado >= 400));
    _encolar(
      nivel: esFallo ? AppLogLevel.error : nivel,
      categoria: AppLogCategoria.api,
      titulo:
          '$metodo ${_urlCorto(url)}${estado != null ? ' → $estado' : ''}',
      detalle: nota,
      metodo: metodo,
      url: url,
      estado: estado,
      durMs: duracion?.inMilliseconds,
      request: _limpiarSecreto(request),
      response: response,
      error: error,
      stack: stack?.toString(),
      esperado: esErrorEsperado &&
          (error != null || (estado != null && estado >= 400)),
    );
  }

  /// Registra una acción de sincronización (fases, diagnósticos).
  void sync({
    required String titulo,
    String? detalle,
    String? request,
    String? response,
    AppLogLevel nivel = AppLogLevel.info,
  }) {
    _encolar(
      nivel: nivel,
      categoria: AppLogCategoria.sync,
      titulo: titulo,
      detalle: detalle,
      request: request,
      response: response,
    );
  }

  /// Registra navegación entre pantallas.
  void nav({
    required String titulo,
    String? pantalla,
    AppLogLevel nivel = AppLogLevel.info,
  }) {
    if (pantalla != null && pantalla.isNotEmpty) {
      pantallaActual = pantalla;
    }
    _encolar(
      nivel: nivel,
      categoria: AppLogCategoria.nav,
      titulo: titulo,
      pantalla: pantalla,
    );
  }

  /// Registra arranque, estado de red, sesión u otros eventos de plataforma.
  void app({
    required String titulo,
    String? detalle,
    AppLogLevel nivel = AppLogLevel.info,
  }) {
    _encolar(
      nivel: nivel,
      categoria: AppLogCategoria.app,
      titulo: titulo,
      detalle: detalle,
    );
  }

  /// Registra un evento de autenticación (login/logout/registro).
  void auth({
    required String titulo,
    String? detalle,
    AppLogLevel nivel = AppLogLevel.info,
  }) {
    _encolar(
      nivel: nivel,
      categoria: AppLogCategoria.auth,
      titulo: titulo,
      detalle: detalle,
    );
  }

  /// Registra un error global con su stack COMPLETO.
  ///
  /// El ruido cosmético del framework ([esRuidoCosmetico]) se descarta: son
  /// quejas de debug sin acción posible que llenan el visor sin informar nada.
  void error({
    required String titulo,
    Object? exception,
    StackTrace? stack,
    String? contexto,
  }) {
    if (esRuidoCosmetico(exception) || esRuidoCosmetico(titulo)) return;
    _encolar(
      nivel: AppLogLevel.error,
      categoria: AppLogCategoria.error,
      titulo: titulo,
      detalle: contexto ?? exception?.toString(),
      error: exception?.toString() ?? titulo,
      stack: stack?.toString(),
    );
  }

  /// Quejas **cosméticas** conocidas del framework (avisos de debug que no
  /// rompen nada ni requieren acción del usuario). No deben llenar el registro.
  /// Si aparece una nueva, se corrige el widget causante y se añade aquí.
  static const List<String> ruidoCosmeticoConocido = [
    'ListTile background color or ink splashes may be invisible',
  ];

  /// ¿[error] es una de las quejas cosméticas de [ruidoCosmeticoConocido]?
  static bool esRuidoCosmetico(Object? error) {
    if (error == null) return false;
    final t = error.toString();
    return ruidoCosmeticoConocido.any(t.contains);
  }

  /// Punto de paso del envoltorio de sqflite: captura TODA sentencia SQL con
  /// sus argumentos y su resultado, sin recortar nada.
  void _onEventoSql(SqfliteLoggerEvent event) {
    if (!_habilitado) return;
    try {
      if (event is SqfliteLoggerSqlEvent) {
        _capturarSql(
          nombre: event.name,
          sql: event.sql,
          argumentos: event.arguments,
          resultado: event.result,
          durMs: event.sw?.elapsed.inMilliseconds,
          error: event.error,
        );
      } else if (event is SqfliteLoggerBatchEvent) {
        final ops = event.operations;
        _encolar(
          nivel: event.error != null ? AppLogLevel.error : AppLogLevel.debug,
          categoria: AppLogCategoria.sql,
          titulo: 'SQL batch (${ops.length} ops)',
          detalle: ops.isNotEmpty ? _tablaDe(ops.first.sql) : null,
          request: jsonEncode(ops.map((o) => _opMap(o)).toList()),
          error: event.error?.toString(),
          durMs: event.sw?.elapsed.inMilliseconds,
        );
      } else if (event is SqfliteLoggerDatabaseOpenEvent) {
        _encolar(
          nivel: AppLogLevel.info,
          categoria: AppLogCategoria.sql,
          titulo: 'BD abierta (${event.path?.split('/').last ?? '?'})',
        );
      } else if (event is SqfliteLoggerDatabaseCloseEvent) {
        _encolar(
          nivel: AppLogLevel.info,
          categoria: AppLogCategoria.sql,
          titulo: 'BD cerrada (#${event.databaseId})',
        );
      }
    } catch (_) {
      // Nunca dejar morir la app por el logger.
    }
  }

  Map<String, Object?> _opMap(SqfliteLoggerBatchOperation o) => {
        'op': o.name,
        'sql': o.sql,
        if (o.arguments != null) 'args': o.arguments.toString(),
        if (o.result != null) 'result': o.result.toString(),
      };

  void _capturarSql({
    required String nombre,
    required String sql,
    Object? argumentos,
    Object? resultado,
    int? durMs,
    Object? error,
  }) {
    final esLectura = sql.trimLeft().toUpperCase().startsWith('SELECT');
    _encolar(
      nivel: error != null ? AppLogLevel.error : AppLogLevel.debug,
      categoria: AppLogCategoria.sql,
      titulo: 'SQL $nombre → ${_tablaDe(sql)}',
      detalle: esLectura ? 'lectura' : 'escritura',
      request: jsonEncode({
        'sql': sql,
        if (argumentos != null) 'args': argumentos.toString(),
      }),
      response: resultado != null
          ? jsonEncode({'result': resultado.toString()})
          : null,
      error: error?.toString(),
      durMs: durMs,
    );
  }

  /// Saca la tabla implicada (`INSERT INTO x`, `UPDATE x`, `FROM x`) para que
  /// el listado sea legible. Si no la reconoce, devuelve '?'.
  static final RegExp _reTabla = RegExp(
    r'(?:INTO|UPDATE|FROM|TABLE)\s+([A-Za-z0-9_]+)',
    caseSensitive: false,
  );

  String _tablaDe(String sql) {
    final m = _reTabla.firstMatch(sql);
    return m?.group(1) ?? '?';
  }

  // ── Cola y persistencia ───────────────────────────────────────────────────

  void _encolar({
    required AppLogLevel nivel,
    required AppLogCategoria categoria,
    required String titulo,
    String? detalle,
    String? metodo,
    String? url,
    int? estado,
    int? durMs,
    String? request,
    String? response,
    String? error,
    String? stack,
    String? pantalla,
    bool esperado = false,
  }) {
    if (!_habilitado) return;
    if (_cola.length >= _maxCola) {
      _flush();
      if (_cola.length >= _maxCola) {
        _descartadas++;
        return;
      }
    }
    _cola.add({
      'ts': DateTime.now().millisecondsSinceEpoch,
      'nivel': _nombreNivel(nivel),
      'categoria': _nombreCategoria(categoria),
      'titulo': titulo,
      'detalle': detalle,
      'metodo': metodo,
      'url': url,
      'estado': estado,
      'dur_ms': durMs,
      'request': request,
      'response': response,
      'error': error,
      'stack': stack,
      'pantalla': pantalla ?? pantallaActual,
      'esperado': esperado ? 1 : 0,
    });
  }

  Future<void> _flush() async {
    if (_cola.isEmpty) return;
    final db = _db;
    if (db == null) {
      // Sin BD (logger caído) no hay dónde persistir: se descarta la cola
      // para no crecer en memoria ni bloquear `esperarFlush`.
      _descartadas += _cola.length;
      _cola.clear();
      return;
    }
    final lote = List<Map<String, Object?>>.from(_cola);
    _cola.clear();
    try {
      final batch = db.batch();
      for (final fila in lote) {
        batch.insert('logs', fila);
      }
      await batch.commit(noResult: true);
      if (_descartadas > 0) {
        _encolar(
          nivel: AppLogLevel.warn,
          categoria: AppLogCategoria.app,
          titulo: 'Logger: $_descartadas entradas descartadas por desborde',
        );
        _descartadas = 0;
      }
    } catch (_) {
      // El logger jamás rompe la app: si la BD falla, se reintenta luego.
      _cola.insertAll(0, lote);
      if (_cola.length > _maxCola) {
        _cola.removeRange(0, _cola.length - _maxCola);
      }
    }
  }

  /// Fuerza el volcado de la cola a disco (para exportaciones y para leer en
  /// la pantalla de debug justo después de una acción).
  Future<void> esperarFlush() async {
    for (var intento = 0; _cola.isNotEmpty && intento < 5; intento++) {
      await _flush();
    }
  }

  /// Ejecuta la purga de retención ya (sin esperar al timer). Solo pruebas.
  @visibleForTesting
  Future<void> purgarParaPrueba() => _purgar();

  /// Inserta una fila con `ts` arbitrario (para simular entradas antiguas).
  /// Solo pruebas.
  @visibleForTesting
  Future<void> insertarFilaParaPrueba(Map<String, Object?> fila) async {
    await _db?.insert('logs', fila);
  }

  Future<void> _purgar() async {
    final db = _db;
    if (db == null) return;
    try {
      final corte =
          DateTime.now().subtract(retencion).millisecondsSinceEpoch;
      await db.delete('logs', where: 'ts < ?', whereArgs: [corte]);
      // Techo duro: conservar las _maxFilas más nuevas.
      final total = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM logs'),
      );
      if (total != null && total > _maxFilas) {
        await db.rawDelete(
          'DELETE FROM logs WHERE id NOT IN '
          '(SELECT id FROM logs ORDER BY id DESC LIMIT ?)',
          [_maxFilas],
        );
      }
    } catch (_) {}
  }

  // ── Consultas para el visor ───────────────────────────────────────────────

  Future<List<LogEntry>> consultar({
    AppLogCategoria? categoria,
    AppLogLevel? nivel,
    String? texto,
    int limit = 200,
    int offset = 0,
    bool soloErrores = false,
  }) async {
    final db = _db;
    if (db == null) return const [];
    await esperarFlush();
    final where = <String>[];
    final args = <Object?>[];
    if (categoria != null) {
      where.add('categoria = ?');
      args.add(_nombreCategoria(categoria));
    }
    if (nivel != null) {
      where.add('nivel = ?');
      args.add(_nombreNivel(nivel));
    }
    if (soloErrores) {
      where.add(
        "(nivel = 'ERROR' OR "
        '(esperado = 0 AND (error IS NOT NULL OR estado >= 400)))',
      );
    }
    if (texto != null && texto.trim().isNotEmpty) {
      final t = '%${texto.trim()}%';
      where.add(
        '(titulo LIKE ? OR detalle LIKE ? OR url LIKE ? OR request LIKE ? '
        'OR response LIKE ? OR error LIKE ?)',
      );
      args.addAll([t, t, t, t, t, t]);
    }
    final rows = await db.query(
      'logs',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'ts DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(LogEntry.fromMap).toList();
  }

  /// Total y conteos por categoría/nivel de lo almacenado (últimas 24 h).
  Future<Map<String, Object?>> resumen() async {
    final db = _db;
    if (db == null) return const {};
    await esperarFlush();
    final total = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM logs'),
        ) ??
        0;
    final porNivel = await db.rawQuery(
      'SELECT nivel, COUNT(*) AS n FROM logs GROUP BY nivel',
    );
    final porCategoria = await db.rawQuery(
      'SELECT categoria, COUNT(*) AS n FROM logs GROUP BY categoria',
    );
    final extremos = await db.rawQuery(
      'SELECT MIN(ts) AS desde, MAX(ts) AS hasta FROM logs',
    );
    final desde = (extremos.first['desde'] as int?);
    final hasta = (extremos.first['hasta'] as int?);
    return {
      'total': total,
      'por_nivel': {
        for (final r in porNivel) r['nivel'] as String: r['n'] as int,
      },
      'por_categoria': {
        for (final r in porCategoria)
          r['categoria'] as String: r['n'] as int,
      },
      'desde': desde == null ? null : DateTime.fromMillisecondsSinceEpoch(desde),
      'hasta': hasta == null ? null : DateTime.fromMillisecondsSinceEpoch(hasta),
    };
  }

  /// Exporta TODO el contenido actual (filtrable) como texto completo, sin
  /// recortar cuerpos. Orden cronológico ascendente.
  Future<String> exportarTexto({
    AppLogCategoria? categoria,
    AppLogLevel? nivel,
    String? texto,
    bool soloErrores = false,
  }) async {
    final db = _db;
    if (db == null) return '(log deshabilitado)';
    await esperarFlush();
    final where = <String>[];
    final args = <Object?>[];
    if (categoria != null) {
      where.add('categoria = ?');
      args.add(_nombreCategoria(categoria));
    }
    if (nivel != null) {
      where.add('nivel = ?');
      args.add(_nombreNivel(nivel));
    }
    if (soloErrores) {
      where.add(
        "(nivel = 'ERROR' OR "
        '(esperado = 0 AND (error IS NOT NULL OR estado >= 400)))',
      );
    }
    if (texto != null && texto.trim().isNotEmpty) {
      final t = '%${texto.trim()}%';
      where.add(
        '(titulo LIKE ? OR detalle LIKE ? OR url LIKE ? OR request LIKE ? '
        'OR response LIKE ? OR error LIKE ?)',
      );
      args.addAll([t, t, t, t, t, t]);
    }
    final rows = await db.query(
      'logs',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'ts ASC, id ASC',
    );
    final sb = StringBuffer();
    sb.writeln('═══ REGISTRO DE LA APP EDAN (últimas 24 h) ═══');
    sb.writeln('Generado: ${DateTime.now()}');
    sb.writeln('Plataforma: $defaultTargetPlatform '
        '${kReleaseMode ? '(release)' : '(debug/profile)'}');
    sb.writeln('Entradas: ${rows.length}');
    sb.writeln('═══════════════════════════════════════════════');
    sb.writeln();
    for (final r in rows) {
      sb.writeln(LogEntry.fromMap(r).aTexto());
    }
    return sb.toString();
  }

  /// Borra TODAS las entradas (acción manual del visor).
  Future<void> limpiar() async {
    await _db?.delete('logs');
  }

  // ── utilidades ───────────────────────────────────────────────────────────

  /// Recorta la URL solo a su ruta (`https://x/api/v2/edan/…` → `/edan/…`)
  /// para el TÍTULO; la URL completa se guarda igual en el campo `url`.
  static String _urlCorto(String url) {
    final i = url.indexOf('/api/v2');
    // Sin prefijo conocido (otro host, RAG, estáticos): se enmascara el
    // dominio en lugar de mostrarlo crudo en el titulo.
    return i >= 0 ? url.substring(i + 7) : enmascararUrl(url);
  }

  /// Sustituye contraseñas por `***` en bodies JSON. No trunca: solo oculta
  /// el secreto.
  static String? _limpiarSecreto(String? body) {
    if (body == null) return null;
    return body.replaceAllMapped(
      RegExp(r'("contrasena"\s*:\s*)"([^"]*)"', caseSensitive: false),
      (m) => '${m.group(1)}"***"',
    );
  }
}
