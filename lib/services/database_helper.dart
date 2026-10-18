import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/edan.dart';
import '../models/id_seccion_helper.dart';
import 'edan_secciones_registry.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._();
  static DatabaseHelper get instance => _instance;

  /// Ruta alterna del archivo SQLite. Solo la usan las pruebas: en producción
  /// siempre es `<dir de la app>/rea_database.db`, y abrir la base real de un
  /// dispositivo desde un test dejaría datos de prueba en la app del usuario.
  @visibleForTesting
  static String? rutaDePrueba;

  /// Cierra el handle para que otra ruta pueda abrirse. Solo pruebas.
  @visibleForTesting
  Future<void> cerrarParaPrueba() async {
    await _database?.close();
    _database = null;
  }

  DatabaseHelper._();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Versión del esquema que crea/migra [_onUpgrade]. **Única fuente**: la
  /// comparan `openDatabase` y los tests que verifican que la BD de prueba es
  /// la misma de la app (históricamente estos se quedaban en 30 y fallaban al
  /// migrar a 32).
  static const int versionEsquema = 41;

  Future<Database> _initDatabase() async {
    final path =
        rutaDePrueba ?? join(await _localDbPath(), 'rea_database.db');
    return await openDatabase(
      path,
      version: versionEsquema,
      onCreate: _createDatabase,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
    );
  }

  /// Ruta de la base de datos según la plataforma:
  /// - Desktop (Windows/Linux): AppData dir de path_provider (necesario con
  ///   `sqflite_common_ffi`, ya que `getDatabasesPath()` no funciona ahí).
  /// - Móvil (Android/iOS): `getDatabasesPath()` estándar de sqflite.
  Future<String> _localDbPath() async {
    if (Platform.isWindows || Platform.isLinux) {
      final dir = await getApplicationSupportDirectory();
      return dir.path;
    }
    return await getDatabasesPath();
  }

  Future<void> _createDatabase(Database db, int version) async {
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
      CREATE TABLE catalogo_grupo_etario (
        id_grupo_etario INTEGER PRIMARY KEY,
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
        grup_poblacion INTEGER DEFAULT 0,
        grup_salud INTEGER DEFAULT 0,
        grup_infraestructura INTEGER DEFAULT 0,
        grup_servicios INTEGER DEFAULT 0,
        grup_educacion INTEGER DEFAULT 0,
        grup_vivienda INTEGER DEFAULT 0,
        grup_agropecuario INTEGER DEFAULT 0,
        grup_proteccion INTEGER DEFAULT 0,
        grup_necesidades INTEGER DEFAULT 0,
        id_edan_localidad_estado INTEGER,
        estado_localidad TEXT,
        datos_json TEXT NOT NULL,
        sincronizado INTEGER DEFAULT 0,
        pendiente_eliminacion INTEGER DEFAULT 0,
        pendiente_actualizacion INTEGER DEFAULT 0,
        editado INTEGER DEFAULT 0,
        fecha_creacion TEXT NOT NULL,
        fecha_modificacion TEXT,
        intentos_sync INTEGER DEFAULT 0,
        ultimo_error TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE localidad_seccion_sync (
        id_local TEXT NOT NULL,
        seccion TEXT NOT NULL,
        modificada INTEGER DEFAULT 0,
        fecha_modificacion TEXT,
        PRIMARY KEY (id_local, seccion)
      )
    ''');

    // Instalación limpia: tablas de sección RESP con el esquema v21 (alineado
    // al backend v2). Las tablas base (UGR) ya se crearon arriba.
    // Primero creamos las 14 tablas base (v20) y luego recreamos las 5 que
    // requieren el esquema v21 corregido.
    await _crearTablasSeccionV20(db);
    await _recrearTablasSeccionV21(db);

    // Tabla de secciones activas (checkboxes del wizard → secciones del JSON).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS localidad_secciones_activas (
        id_local TEXT NOT NULL,
        seccion TEXT NOT NULL,
        activa INTEGER DEFAULT 1,
        PRIMARY KEY (id_local, seccion)
      )
    ''');

    // Schema V2 (v30): formularios, filas de sección, viviendas, fotos y colas.
    await _crearTablasV2(db);
  }

  Future<void> _crearTablasV2(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS formularios (
        uuid_edan_localidad TEXT PRIMARY KEY,
        id_server INTEGER,
        localidad TEXT NOT NULL DEFAULT '',
        id_municipio INTEGER,
        id_departamento INTEGER,
        id_provincia INTEGER,
        id_tipo_evento INTEGER,
        id_tipo_localidad INTEGER,
        id_edan_localidad_estado INTEGER,
        fecha_llenado TEXT,
        fecha_evento TEXT,
        hora_evento TEXT,
        total_poblacion_afectada INTEGER NOT NULL DEFAULT 0,
        total_familias_afectadas INTEGER NOT NULL DEFAULT 0,
        total_familias_damnificadas INTEGER NOT NULL DEFAULT 0,
        grup_poblacion INTEGER NOT NULL DEFAULT 0,
        grup_salud INTEGER NOT NULL DEFAULT 0,
        grup_infraestructura INTEGER NOT NULL DEFAULT 0,
        grup_servicios INTEGER NOT NULL DEFAULT 0,
        grup_educacion INTEGER NOT NULL DEFAULT 0,
        grup_vivienda INTEGER NOT NULL DEFAULT 0,
        grup_agropecuario INTEGER NOT NULL DEFAULT 0,
        grup_proteccion INTEGER NOT NULL DEFAULT 0,
        grup_necesidades INTEGER NOT NULL DEFAULT 0,
        secciones_activas_json TEXT NOT NULL DEFAULT '[]',
        fecha_modificacion TEXT,
        estado_local TEXT NOT NULL DEFAULT 'borrador',
        id_usuario INTEGER,
        datos_json TEXT,
        datos_json_servidor TEXT,
        pendiente_push INTEGER NOT NULL DEFAULT 0,
        sync_state TEXT NOT NULL DEFAULT 'pending_create',
        pending_submit INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        estado_destino INTEGER,
        firma_contenido TEXT,
        firma_enviada TEXT,
        usuario_nombre TEXT,
        usuario_login TEXT,
        id_rol INTEGER,
        usuario_rol TEXT,
        estado_nombre TEXT,
        tipo_evento_nombre TEXT,
        tipo_localidad_nombre TEXT,
        departamento_nombre TEXT,
        departamento_codigo TEXT,
        provincia_nombre TEXT,
        provincia_codigo TEXT,
        municipio_nombre TEXT,
        municipio_codigo TEXT,
        id_edan INTEGER,
        edan_codigo TEXT
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_formularios_id_server
        ON formularios(id_server) WHERE id_server IS NOT NULL
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS filas_seccion (
        uuid_registro TEXT PRIMARY KEY,
        uuid_edan_localidad TEXT NOT NULL,
        tipo TEXT NOT NULL,
        datos_json TEXT NOT NULL,
        fecha_modificacion_local TEXT,
        estado_sync TEXT NOT NULL DEFAULT 'pendiente',
        remote_id INTEGER,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_filas_form
        ON filas_seccion(uuid_edan_localidad, tipo)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS viviendas (
        uuid_registro TEXT PRIMARY KEY,
        uuid_dano_vivienda TEXT NOT NULL,
        tipo_dano TEXT NOT NULL CHECK (tipo_dano IN ('TOTAL','PARCIAL')),
        coordenada_lat REAL,
        coordenada_lon REAL,
        fotografia TEXT,
        fecha_modificacion_local TEXT,
        estado_sync TEXT NOT NULL DEFAULT 'pendiente',
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_viv_dano
        ON viviendas(uuid_dano_vivienda)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS fotografias (
        uuid_fotografia TEXT PRIMARY KEY,
        uuid_edan_localidad TEXT NOT NULL,
        tipo_entidad TEXT NOT NULL,
        uuid_registro TEXT NOT NULL,
        ruta_local TEXT,
        ruta_servidor TEXT,
        sha256 TEXT,
        borrado_logico INTEGER NOT NULL DEFAULT 0,
        fecha_modificacion TEXT,
        remote_id INTEGER,
        file_name TEXT,
        mime_type TEXT,
        size_bytes INTEGER,
        upload_state TEXT NOT NULL DEFAULT 'pending',
        is_deleted INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        last_error TEXT,
        intentos_descarga INTEGER NOT NULL DEFAULT 0,
        fecha_proximo_intento TEXT
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_fotos_registro
        ON fotografias(tipo_entidad, uuid_registro)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cola_sincronizacion (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tabla TEXT NOT NULL,
        uuid_registro TEXT NOT NULL,
        accion TEXT NOT NULL,
        estado TEXT NOT NULL,
        intentos INTEGER NOT NULL DEFAULT 0,
        ultimo_error TEXT,
        fecha_proximo_intento TEXT,
        fecha_registro TEXT NOT NULL DEFAULT (datetime('now')),
        operation_uuid TEXT,
        idempotency_key TEXT,
        depends_on TEXT,
        payload_json TEXT
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_cola
        ON cola_sincronizacion(tabla, uuid_registro, accion)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cola_fotos (
        uuid_fotografia TEXT PRIMARY KEY,
        ruta_local TEXT NOT NULL,
        tipo_entidad TEXT,
        uuid_registro TEXT,
        sha256 TEXT,
        estado TEXT NOT NULL,
        intentos INTEGER NOT NULL DEFAULT 0,
        ultimo_error TEXT,
        fecha_proximo_intento TEXT,
        file_name TEXT,
        mime_type TEXT,
        size_bytes INTEGER,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    // Tabla AUXILIAR (v31): matriz grupo × secciones por localidad.
    // NO es dato del formulario: no entra en `datos_json` ni en el payload del
    // servidor. Registra qué secciones están activas y POR QUÉ, de modo que al
    // reabrir un borrador se pueda mostrar una sección aunque el usuario haya
    // desmarcado su grupo, si es que esa sección tiene datos reales.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS secciones_grupos_local (
        uuid_edan_localidad TEXT NOT NULL,
        seccion TEXT NOT NULL,
        grupo TEXT,
        origen TEXT NOT NULL DEFAULT 'usuario',
        activa INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY (uuid_edan_localidad, seccion)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sgl_local
        ON secciones_grupos_local(uuid_edan_localidad)
    ''');

    // Tabla AUXILIAR (v32): los 9 `grup_*` de una localidad, con DOS columnas
    // de propósito distinto (PLAN_APP_EDAN_OFFLINE_V2 §4.2):
    //   · `seleccion_usuario` — lo que tildó el usuario en page01. Gobierna
    //     qué secciones se muestran al crear/editar.
    //   · `grup_servidor`     — caché del nodo `grupos` que devuelve el
    //     GET /formularios/{uuid}/completo (y el pull). El servidor lo deriva
    //     como OR de las secciones miembro; es solo lectura.
    // La matriz grupo × secciones vive en `edan_secciones_registry.dart`; aquí
    // solo se persiste el cruce.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS grupos_local (
        uuid_edan_localidad TEXT NOT NULL,
        grupo TEXT NOT NULL,
        seleccion_usuario INTEGER NOT NULL DEFAULT 0,
        grup_servidor INTEGER,
        PRIMARY KEY (uuid_edan_localidad, grupo)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_grupos_local
        ON grupos_local(uuid_edan_localidad)
    ''');
  }

  /// Diseño limpio (v40): el esquema V2 se define UNA vez en
  /// `_crearTablasV2` / `_createDatabase`. No hay cadena de migraciones
  /// ALTER: cualquier versión anterior se alinea con DROP + CREATE limpio
  /// de las tablas V2 (los catálogos y auxiliares se conservan). Sincronizar
  /// antes de instalar: lo no subido se pierde en el alineamiento.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 41) {
      await db.execute('DROP TABLE IF EXISTS formularios');
      await db.execute('DROP TABLE IF EXISTS filas_seccion');
      await db.execute('DROP TABLE IF EXISTS viviendas');
      await db.execute('DROP TABLE IF EXISTS cola_sincronizacion');
      await db.execute('DROP TABLE IF EXISTS fotografias');
      await db.execute('DROP TABLE IF EXISTS cola_fotos');
      await _crearTablasV2(db);
      return;
    }
  }

  /// Crea las 14 tablas de sección v2 (Modelo A) + carrete de fotos.
  /// Cada tabla replica el backend (mismas columnas) y agrega columnas locales:
  ///   - `editado`            : 1 = fila pendiente de envío / 0 = sincronizada
  ///   - `marcado_borrar`     : 1 = emitir DELETE
  ///   - `insertada_en_server`: 0 = INSERT (id_seccion nuevo) / 1 = UPDATE
  Future<void> _crearTablasSeccionV20(Database db) async {
    // ===== Secciones 1:N con foto =====
    await db.execute('''
      CREATE TABLE IF NOT EXISTS seccion_impacto_poblacion (
        id_seccion TEXT PRIMARY KEY,
        id_local TEXT,
        id_edan_localidad INTEGER,
        id_grupo_etario INTEGER,
        rango TEXT,
        fallecidos INTEGER,
        heridos INTEGER,
        desaparecidos INTEGER,
        observaciones TEXT,
        editado INTEGER DEFAULT 0,
        marcado_borrar INTEGER DEFAULT 0,
        insertada_en_server INTEGER DEFAULT 0,
        fecha_modificacion_local TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS seccion_salud_establecimientos (
        id_seccion TEXT PRIMARY KEY,
        id_local TEXT,
        id_edan_localidad INTEGER,
        nombre_establecimiento TEXT,
        comunidad TEXT,
        nivel_atencion TEXT,
        id_nivel_atencion INTEGER,
        dano_parcial INTEGER,
        dano_total INTEGER,
        medicos_afectados INTEGER,
        observaciones TEXT,
        fotografia TEXT,
        coordenada_lat REAL,
        coordenada_lon REAL,
        editado INTEGER DEFAULT 0,
        marcado_borrar INTEGER DEFAULT 0,
        insertada_en_server INTEGER DEFAULT 0,
        fecha_modificacion_local TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS seccion_danos_viales (
        id_seccion TEXT PRIMARY KEY,
        id_local TEXT,
        id_edan_localidad INTEGER,
        via INTEGER,
        puente INTEGER,
        tramo TEXT,
        dano_parcial INTEGER,
        dano_total INTEGER,
        km_danio REAL,
        necesidades_inmediatas TEXT,
        observaciones TEXT,
        fotografia TEXT,
        coordenada_lat REAL,
        coordenada_lon REAL,
        editado INTEGER DEFAULT 0,
        marcado_borrar INTEGER DEFAULT 0,
        insertada_en_server INTEGER DEFAULT 0,
        fecha_modificacion_local TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS seccion_danos_infra_publica (
        id_seccion TEXT PRIMARY KEY,
        id_local TEXT,
        id_edan_localidad INTEGER,
        comunidad TEXT,
        tipo_estructura TEXT,
        dano_parcial INTEGER,
        dano_total INTEGER,
        necesidades_inmediatas TEXT,
        observaciones TEXT,
        fotografia TEXT,
        coordenada_lat REAL,
        coordenada_lon REAL,
        editado INTEGER DEFAULT 0,
        marcado_borrar INTEGER DEFAULT 0,
        insertada_en_server INTEGER DEFAULT 0,
        fecha_modificacion_local TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS seccion_servicios_basicos (
        id_seccion TEXT PRIMARY KEY,
        id_local TEXT,
        id_edan_localidad INTEGER,
        tipo TEXT,
        dano_parcial INTEGER,
        dano_total INTEGER,
        necesidades_inmediatas TEXT,
        observaciones TEXT,
        fotografia TEXT,
        coordenada_lat REAL,
        coordenada_lon REAL,
        editado INTEGER DEFAULT 0,
        marcado_borrar INTEGER DEFAULT 0,
        insertada_en_server INTEGER DEFAULT 0,
        fecha_modificacion_local TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS seccion_unidades_educativas (
        id_seccion TEXT PRIMARY KEY,
        id_local TEXT,
        id_edan_localidad INTEGER,
        nombre_establecimiento TEXT,
        comunidad TEXT,
        nivel_educativo TEXT,
        dano_parcial INTEGER,
        dano_total INTEGER,
        suspension_clases INTEGER,
        estudiantes INTEGER,
        docentes INTEGER,
        observaciones TEXT,
        fotografia TEXT,
        coordenada_lat REAL,
        coordenada_lon REAL,
        editado INTEGER DEFAULT 0,
        marcado_borrar INTEGER DEFAULT 0,
        insertada_en_server INTEGER DEFAULT 0,
        fecha_modificacion_local TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS seccion_danos_vivienda (
        id_seccion TEXT PRIMARY KEY,
        id_local TEXT,
        id_edan_localidad INTEGER,
        comunidad TEXT,
        dano_parcial INTEGER,
        dano_total INTEGER,
        necesidades_inmediatas TEXT,
        observaciones TEXT,
        fotografia TEXT,
        coordenada_lat REAL,
        coordenada_lon REAL,
        editado INTEGER DEFAULT 0,
        marcado_borrar INTEGER DEFAULT 0,
        insertada_en_server INTEGER DEFAULT 0,
        fecha_modificacion_local TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS seccion_danos_agricultura (
        id_seccion TEXT PRIMARY KEY,
        id_local TEXT,
        id_edan_localidad INTEGER,
        id_cultivo INTEGER,
        tipo_cultivo TEXT,
        hectareas_afectadas INTEGER,
        hectareas_perdidas INTEGER,
        necesidades_inmediatas TEXT,
        observaciones TEXT,
        fotografia TEXT,
        coordenada_lat REAL,
        coordenada_lon REAL,
        editado INTEGER DEFAULT 0,
        marcado_borrar INTEGER DEFAULT 0,
        insertada_en_server INTEGER DEFAULT 0,
        fecha_modificacion_local TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS seccion_danos_pecuarios (
        id_seccion TEXT PRIMARY KEY,
        id_local TEXT,
        id_edan_localidad INTEGER,
        id_especie INTEGER,
        especie TEXT,
        raza TEXT,
        animales_afectados INTEGER,
        animales_muertos INTEGER,
        necesidades_inmediatas TEXT,
        observaciones TEXT,
        fotografia TEXT,
        coordenada_lat REAL,
        coordenada_lon REAL,
        editado INTEGER DEFAULT 0,
        marcado_borrar INTEGER DEFAULT 0,
        insertada_en_server INTEGER DEFAULT 0,
        fecha_modificacion_local TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS seccion_infra_productiva (
        id_seccion TEXT PRIMARY KEY,
        id_local TEXT,
        id_edan_localidad INTEGER,
        tipo TEXT,
        comunidad TEXT,
        dano_parcial INTEGER,
        dano_total INTEGER,
        necesidades_inmediatas TEXT,
        observaciones TEXT,
        fotografia TEXT,
        coordenada_lat REAL,
        coordenada_lon REAL,
        editado INTEGER DEFAULT 0,
        marcado_borrar INTEGER DEFAULT 0,
        insertada_en_server INTEGER DEFAULT 0,
        fecha_modificacion_local TEXT
      )
    ''');
    // ===== Secciones 1:N sin foto =====
    await db.execute('''
      CREATE TABLE IF NOT EXISTS seccion_proteccion (
        id_seccion TEXT PRIMARY KEY,
        id_local TEXT,
        id_edan_localidad INTEGER,
        id_grupo_vulnerable_catalogo INTEGER,
        grupo_vulnerable TEXT,
        mujeres INTEGER,
        hombres INTEGER,
        apoyo_psicologico INTEGER,
        observaciones TEXT,
        editado INTEGER DEFAULT 0,
        marcado_borrar INTEGER DEFAULT 0,
        insertada_en_server INTEGER DEFAULT 0,
        fecha_modificacion_local TEXT
      )
    ''');
    // ===== Secciones 1:1 (objeto único por localidad) =====
    await db.execute('''
      CREATE TABLE IF NOT EXISTS seccion_primera_respuesta (
        id_seccion TEXT PRIMARY KEY,
        id_local TEXT,
        id_edan_localidad INTEGER,
        busqueda INTEGER,
        salvamento INTEGER,
        evacuacion INTEGER,
        observaciones TEXT,
        editado INTEGER DEFAULT 0,
        marcado_borrar INTEGER DEFAULT 0,
        insertada_en_server INTEGER DEFAULT 0,
        fecha_modificacion_local TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS seccion_necesidad_salud (
        id_seccion TEXT PRIMARY KEY,
        id_local TEXT,
        id_edan_localidad INTEGER,
        numero_personas INTEGER,
        otras_necesidades TEXT,
        observaciones TEXT,
        editado INTEGER DEFAULT 0,
        marcado_borrar INTEGER DEFAULT 0,
        insertada_en_server INTEGER DEFAULT 0,
        fecha_modificacion_local TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS seccion_necesidad_humanitaria (
        id_seccion TEXT PRIMARY KEY,
        id_local TEXT,
        id_edan_localidad INTEGER,
        alimentos INTEGER,
        refugio_vivienda INTEGER,
        ropa_cama INTEGER,
        articulos_higiene INTEGER,
        articulos_cocina INTEGER,
        prendas_vestir INTEGER,
        herramientas INTEGER,
        almacenamiento_agua INTEGER,
        banos INTEGER,
        obs_alimentos TEXT,
        obs_refugio_vivienda TEXT,
        obs_ropa_cama TEXT,
        obs_articulos_higiene TEXT,
        obs_articulos_cocina TEXT,
        obs_prendas_vestir TEXT,
        obs_herramientas TEXT,
        obs_almacenamiento_agua TEXT,
        obs_banos TEXT,
        editado INTEGER DEFAULT 0,
        marcado_borrar INTEGER DEFAULT 0,
        insertada_en_server INTEGER DEFAULT 0,
        fecha_modificacion_local TEXT
      )
    ''');
    // ===== Carrete de fotos (desacopla binarios del guardado de sección) =====
    await db.execute('''
      CREATE TABLE IF NOT EXISTS foto_pendiente (
        id_foto TEXT PRIMARY KEY,
        id_local TEXT,
        id_edan_localidad INTEGER,
        id_seccion TEXT,
        ruta_local_archivo TEXT,
        coordenada_lat REAL,
        coordenada_lon REAL,
        subida INTEGER DEFAULT 0,
        path_servidor TEXT,
        descargada INTEGER DEFAULT 0,
        ruta_descarga TEXT,
        intentos_subida INTEGER DEFAULT 0,
        intentos_descarga INTEGER DEFAULT 0,
        ultimo_error TEXT
      )
    ''');
    // ===== foto_pendiente_v2: schema limpio para upload/download =====
    await db.execute('''
      CREATE TABLE IF NOT EXISTS foto_pendiente_v2 (
        id_foto TEXT PRIMARY KEY,
        id_local TEXT NOT NULL,
        id_seccion TEXT NOT NULL,
        ruta_local_archivo TEXT,
        path_servidor TEXT,
        latitud REAL,
        longitud REAL,
        subida INTEGER DEFAULT 0,
        descargada INTEGER DEFAULT 0,
        intentos INTEGER DEFAULT 0,
        ultimo_error TEXT,
        fecha_creacion TEXT NOT NULL
      )
    ''');
  }

  /// Migración v21: recrea desde cero las tablas de sección RESP cuyas columnas
  /// no coincidían con las claves emitidas por el modelo (`toApiJson`), causa de
  /// `DatabaseException: no column named ...` en `guardarFilasSeccion`.
  /// Columnas alineadas al schema v2 del backend (schemas.py / OpenAPI v2):
  ///   - seccion_salud_establecimientos : + enfermeras_afectadas, otros_afectados
  ///   - seccion_servicios_basicos      : - afectado (campo local, ya no se emite)
  ///   - seccion_unidades_educativas    : docentes->profesores, + administrativos,
  ///                                      - nivel_educativo (schema v2 no lo usa)
  ///   - seccion_proteccion             : + total, reposicion_documentos, - grupo_vulnerable
  ///   - seccion_necesidad_salud        : - botiquines (campo local, ya no se emite)
  /// Se conservan las columnas de edición/sync (`editado`, `marcado_borrar`,
  /// `insertada_en_server`) para saber qué filas reenviar al editar.
  /// NOTA: recrear pierde las filas locales pendientes de envío de estas 5 tablas.
  /// Rol 6 UGR (localidades_offline/datos_json/localidad_seccion_sync) intacto.
  Future<void> _recrearTablasSeccionV21(Database db) async {
    await db.execute('DROP TABLE IF EXISTS seccion_salud_establecimientos');
    await db.execute('''
      CREATE TABLE seccion_salud_establecimientos (
        id_seccion TEXT PRIMARY KEY,
        id_local TEXT,
        id_edan_localidad INTEGER,
        nombre_establecimiento TEXT,
        comunidad TEXT,
        nivel_atencion TEXT,
        dano_parcial INTEGER,
        dano_total INTEGER,
        medicos_afectados INTEGER,
        enfermeras_afectadas INTEGER,
        otros_afectados INTEGER,
        coordenada_lat REAL,
        coordenada_lon REAL,
        editado INTEGER DEFAULT 0,
        marcado_borrar INTEGER DEFAULT 0,
        insertada_en_server INTEGER DEFAULT 0,
        fecha_modificacion_local TEXT
      )
    ''');

    await db.execute('DROP TABLE IF EXISTS seccion_servicios_basicos');
    await db.execute('''
      CREATE TABLE seccion_servicios_basicos (
        id_seccion TEXT PRIMARY KEY,
        id_local TEXT,
        id_edan_localidad INTEGER,
        tipo TEXT,
        dano_parcial INTEGER,
        dano_total INTEGER,
        necesidades_inmediatas TEXT,
        observaciones TEXT,
        fotografia TEXT,
        coordenada_lat REAL,
        coordenada_lon REAL,
        editado INTEGER DEFAULT 0,
        marcado_borrar INTEGER DEFAULT 0,
        insertada_en_server INTEGER DEFAULT 0,
        fecha_modificacion_local TEXT
      )
    ''');

    await db.execute('DROP TABLE IF EXISTS seccion_unidades_educativas');
    await db.execute('''
      CREATE TABLE seccion_unidades_educativas (
        id_seccion TEXT PRIMARY KEY,
        id_local TEXT,
        id_edan_localidad INTEGER,
        nombre_establecimiento TEXT,
        comunidad TEXT,
        dano_parcial INTEGER,
        dano_total INTEGER,
        suspension_clases INTEGER,
        perdida_material INTEGER,
        funciona_albergue INTEGER,
        estudiantes INTEGER,
        profesores INTEGER,
        administrativos INTEGER,
        observaciones TEXT,
        fotografia TEXT,
        coordenada_lat REAL,
        coordenada_lon REAL,
        editado INTEGER DEFAULT 0,
        marcado_borrar INTEGER DEFAULT 0,
        insertada_en_server INTEGER DEFAULT 0,
        fecha_modificacion_local TEXT
      )
    ''');

    await db.execute('DROP TABLE IF EXISTS seccion_proteccion');
    await db.execute('''
      CREATE TABLE seccion_proteccion (
        id_seccion TEXT PRIMARY KEY,
        id_local TEXT,
        id_edan_localidad INTEGER,
        id_grupo_vulnerable_catalogo INTEGER,
        mujeres INTEGER,
        hombres INTEGER,
        total INTEGER,
        apoyo_psicologico INTEGER,
        reposicion_documentos INTEGER,
        observaciones TEXT,
        editado INTEGER DEFAULT 0,
        marcado_borrar INTEGER DEFAULT 0,
        insertada_en_server INTEGER DEFAULT 0,
        fecha_modificacion_local TEXT
      )
    ''');

    // Unicidad de catálogo en las secciones "caso especial" (protección e
    // impacto): un mismo grupo no puede figurar DOS veces para la misma
    // localidad, aunque cada fila arrastre un id_seccion distinto.
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_seccion_proteccion_grupo
        ON seccion_proteccion (id_local, id_grupo_vulnerable_catalogo)
        WHERE id_local IS NOT NULL AND id_grupo_vulnerable_catalogo IS NOT NULL
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_seccion_impacto_grupo
        ON seccion_impacto_poblacion (id_local, id_grupo_etario)
        WHERE id_local IS NOT NULL AND id_grupo_etario IS NOT NULL
    ''');

    await db.execute('DROP TABLE IF EXISTS seccion_necesidad_salud');
    await db.execute('''
      CREATE TABLE seccion_necesidad_salud (
        id_seccion TEXT PRIMARY KEY,
        id_local TEXT,
        id_edan_localidad INTEGER,
        numero_personas INTEGER,
        otras_necesidades TEXT,
        observaciones TEXT,
        editado INTEGER DEFAULT 0,
        marcado_borrar INTEGER DEFAULT 0,
        insertada_en_server INTEGER DEFAULT 0,
        fecha_modificacion_local TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pendientes_eliminar (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_local TEXT NOT NULL,
        id_server INTEGER,
        id_seccion TEXT NOT NULL,
        ruta_v2 TEXT NOT NULL,
        tabla_sqlite TEXT NOT NULL,
        insertada_en_server INTEGER DEFAULT 0,
        sincronizado INTEGER DEFAULT 0,
        fecha_creacion TEXT NOT NULL
      )
    ''');
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
    // Reparo idempotente: el pull guardaba `filas_seccion.tipo` con nombre de
    // TABLA (`danos_agricultura`) y toda la app lee RUTA (`danos-agricultura`).
    // Renombra solo las filas afectadas (caso Urubo en vivo); las que ya están
    // en forma ruta no se tocan. Corre en cada apertura: es barato y cubre
    // equipos que ya descargaron antes del fix.
    await repararTiposFilaSeccion(db);
  }

  /// Mapa TABLA del servidor → RUTA v2 local para `filas_seccion.tipo`.
  /// Debe coincidir con `EdanSeccionesRegistry` (hay test de paridad que lo
  /// verifica; la duplicación evita un import circular registry↔helper).
  static const Map<String, String> mapaTablaARuta = {
    'impacto_poblacion': 'impacto-poblacion',
    'salud_establecimientos': 'salud-establecimientos',
    'danos_viales': 'danos-viales',
    'danos_infra_publica': 'danos-infra-publica',
    'servicios_basicos': 'servicios-basicos',
    'unidades_educativas': 'unidades-educativas',
    'danos_vivienda': 'danos-vivienda',
    'danos_agricultura': 'danos-agricultura',
    'danos_pecuario': 'danos-pecuarios',
    'infra_productiva': 'infra-productiva',
    'proteccion': 'proteccion',
    'primera_respuesta': 'primera-respuesta',
    'salud_necesidades': 'necesidad-salud',
    'necesidades_humanitarias': 'necesidad-humanitaria',
  };

  /// Renombra en `filas_seccion.tipo` los nombres de tabla a rutas v2.
  /// Idempotente y seguro: solo actualiza filas cuyo `tipo` sea exactamente
  /// una clave del mapa. Devuelve cuántas filas reparó.
  static Future<int> repararTiposFilaSeccion(DatabaseExecutor db) async {
    var reparadas = 0;
    for (final e in mapaTablaARuta.entries) {
      reparadas += await db.rawUpdate(
        'UPDATE filas_seccion SET tipo = ? WHERE tipo = ?',
        [e.value, e.key],
      );
    }
    return reparadas;
  }




















  Future<void> saveEstados(List<Map<String, dynamic>> estados) async {
    final db = await database;
    final batch = db.batch();
    for (final e in estados) {
      batch.insert(
        'catalogo_estados',
        e,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
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
      batch.insert(
        'catalogo_categorias',
        c,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
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
      batch.insert(
        'catalogo_tipos_evento',
        t,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
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
      batch.insert(
        'catalogo_tipo_localidad',
        t,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
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
      batch.insert(
        'catalogo_estados_edan',
        e,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
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
      batch.insert(
        'catalogo_cultivos',
        c,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
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
      batch.insert(
        'catalogo_pecuario_grupos',
        g,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
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
      batch.insert(
        'catalogo_grupo_vulnerable',
        g,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getGruposVulnerablesLocal() async {
    final db = await database;
    return await db.query('catalogo_grupo_vulnerable', orderBy: 'orden ASC');
  }

  Future<void> saveGruposEtarios(List<Map<String, dynamic>> grupos) async {
    final db = await database;
    final batch = db.batch();
    for (final g in grupos) {
      batch.insert(
        'catalogo_grupo_etario',
        g,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getGruposEtariosLocal() async {
    final db = await database;
    return await db.query('catalogo_grupo_etario', orderBy: 'orden ASC');
  }

  Future<void> saveDepartamentos(
    List<Map<String, dynamic>> departamentos,
  ) async {
    final db = await database;
    final batch = db.batch();
    for (final d in departamentos) {
      batch.insert(
        'catalogo_departamentos',
        d,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
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
      batch.insert(
        'catalogo_provincias',
        p,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
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
      batch.insert(
        'catalogo_municipios',
        m,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
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
      batch.insert(
        'catalogo_tipos_repositorio',
        t,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getTiposRepositorioLocal() async {
    final db = await database;
    return await db.query(
      'catalogo_tipos_repositorio',
      where: 'activo = 1',
      orderBy: 'orden ASC, nombre ASC',
    );
  }



  Future<void> saveMunicipioGeojson({
    required int municipioId,
    required String codigoIne,
    String? nombre,
    required String geojson,
  }) async {
    final db = await database;
    await db.insert('municipio_geojson', {
      'municipio_id': municipioId,
      'codigo_ine': codigoIne,
      'nombre': nombre,
      'geojson': geojson,
      'fecha_actualizacion': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getMunicipioGeojsonLocal(
    int municipioId,
  ) async {
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
      where:
          '(sincronizado = 0 OR pendiente_actualizacion = 1) AND pendiente_eliminacion = 0',
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

  Future<int> updateEdanSyncAttempts(
    int idLocal,
    int intentos,
    String error,
  ) async {
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
    await db.delete('sincronizaciones');
    await db.delete('catalogo_estados');
    await db.delete('catalogo_categorias');
    await db.delete('catalogo_tipos_evento');
    await db.delete('catalogo_estados_edan');
    await db.delete('catalogo_cultivos');
    await db.delete('catalogo_pecuario_grupos');
    await db.delete('catalogo_grupo_vulnerable');
    await db.delete('catalogo_grupo_etario');
    await db.delete('catalogo_tipos_repositorio');
    await db.delete('municipio_geojson');
    await db.delete('edans_offline');
    await db.delete('localidades_offline');
    await db.delete('foto_pendiente_v2');
    await db.delete('pendientes_eliminar');
    await db.delete('formularios');
    await db.delete('filas_seccion');
    await db.delete('viviendas');
    await db.delete('fotografias');
    await db.delete('cola_sincronizacion');
    await db.delete('cola_fotos');
    await db.delete('config');
    _database = null;
  }

  Future<int?> getLastSyncDate() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT valor FROM config WHERE clave = ?',
      ['ultima_sync'],
    );
    if (result.isEmpty) return null;
    return int.tryParse(result.first['valor']?.toString() ?? '');
  }

  Future<void> saveLastSyncDate(int timestamp) async {
    await setConfig('ultima_sync', timestamp.toString());
  }

  /// Lee un valor de configuración genérico.
  Future<String?> getConfig(String clave) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT valor FROM config WHERE clave = ?',
      [clave],
    );
    if (result.isEmpty) return null;
    return result.first['valor']?.toString();
  }

  /// Escribe un valor de configuración genérico.
  Future<void> setConfig(String clave, String valor) async {
    final db = await database;
    await db.rawInsert(
      'INSERT OR REPLACE INTO config (clave, valor) VALUES (?, ?)',
      [clave, valor],
    );
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

  /// Mapeo público de una fila `localidades_offline` a modelo (Etapa 5: el
  /// listado unificado lo usa para las filas legacy sin contraparte V2).
  EdanLocalidad localidadFromRow(Map<String, dynamic> row) =>
      _localidadFromRow(row);

  EdanLocalidad _localidadFromRow(Map<String, dynamic> row) {
    final datos = jsonDecode(row['datos_json'] as String);
    final loc = EdanLocalidad.fromJson(Map<String, dynamic>.from(datos as Map));
    loc.idLocal = row['id_local'] as String;
    loc.idServer = _toInt(row['id_server']);
    loc.idEdan = _toInt(row['id_edan']);
    loc.idUsuario = _toInt(row['usuario_id']);
    loc.idEdanLocalidadEstado = _toInt(row['id_edan_localidad_estado']);
    loc.estadoLocalidad = _estadoLocalidadFromNombre(
      row['estado_localidad'] as String?,
    );
    loc.sincronizado = _toBool(row['sincronizado']);
    loc.pendienteEliminacion = _toBool(row['pendiente_eliminacion']);
    loc.pendienteActualizacion = _toBool(row['pendiente_actualizacion']);
    loc.editado = _toBool(row['editado']);
    if (row['fecha_modificacion'] != null) {
      loc.fechaModificacion = row['fecha_modificacion'] as String;
    }
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
    // Toda lectura desde SQLite pasa por aquí. Deduplica por `id_seccion` para
    // que un `datos_json` con duplicados nunca se propague a la UI.
    loc.deduplicarSecciones();
    return loc;
  }

  UgrLocalidadEstado? _estadoLocalidadFromNombre(String? nombre) {
    if (nombre == null) return null;
    final n = nombre.toLowerCase();
    if (n.contains('borrador')) return UgrLocalidadEstado.borrador;
    if (n.contains('enviado')) return UgrLocalidadEstado.enviadoUgr;
    if (n.contains('revision')) return UgrLocalidadEstado.enRevisionUgr;
    if (n.contains('aprobado') && n.contains('ajuste'))
      return UgrLocalidadEstado.aprobadoAjuste;
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
    // NO se llama `recalcularFlagsImpacto()` aquí. Ese método deriva los 9
    // flags gruesos a partir de los datos reales; al ejecutarse durante el
    // GUARDADO local (primer insert del wizard) los pisaba a `false` porque
    // las secciones aún estaban vacías, y al reabrir el borrador las páginas
    // 03–11 desaparecían aunque los datos sí estaban en `filas_seccion`.
    //
    // Los flags de grupo `grup_*` son responsabilidad del usuario (los
    // checkboxes de page01, persistidos en la auxiliar `secciones_grupos_local`);
    // los de sección `imp_*` se derivan de los datos al ENVIAR, en
    // `EdanSeccionesFuente` / `EdanLocalidadesEnvioV2Service`.
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
      'grup_poblacion': localidad.grupPoblacion ? 1 : 0,
      'grup_salud': localidad.grupSalud ? 1 : 0,
      'grup_infraestructura': localidad.grupInfraestructura ? 1 : 0,
      'grup_servicios': localidad.grupServicios ? 1 : 0,
      'grup_educacion': localidad.grupEducacion ? 1 : 0,
      'grup_vivienda': localidad.grupVivienda ? 1 : 0,
      'grup_agropecuario': localidad.grupAgropecuario ? 1 : 0,
      'grup_proteccion': localidad.grupProteccion ? 1 : 0,
      'grup_necesidades': localidad.grupNecesidades ? 1 : 0,
      'id_edan_localidad_estado': localidad.idEdanLocalidadEstado,
      'estado_localidad': localidad.estadoLocalidad?.label,
      'datos_json': jsonEncode(localidad.toJson()),
      'sincronizado': 0,
      'pendiente_eliminacion': 0,
      'pendiente_actualizacion': localidad.pendienteActualizacion ? 1 : 0,
      'editado': 1,
      'fecha_creacion': now,
      'fecha_modificacion': now,
      'intentos_sync': 0,
    };
    try {
      await db.insert(
        'localidades_offline',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint(
        '[insertLocalidad] Error insertando localidad ${localidad.idLocal}: $e',
      );
      rethrow;
    }
    return row['id_local'] as String;
  }

  Future<List<EdanLocalidad>> getLocalidades(int usuarioId) async {
    final db = await database;
    final maps = await db.query(
      'localidades_offline',
      where: 'usuario_id = ? AND pendiente_eliminacion = 0',
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

  Future<List<EdanLocalidad>> getLocalidadesPendientesUsuario(
    int usuarioId,
  ) async {
    final db = await database;
    final maps = await db.query(
      'localidades_offline',
      where:
          'usuario_id = ? AND sincronizado = 0 AND pendiente_eliminacion = 0',
      whereArgs: [usuarioId],
      orderBy: 'fecha_creacion DESC',
    );
    return maps.map((map) => _localidadFromRow(map)).toList();
  }

  Future<List<EdanLocalidad>> getUnsyncedLocalidades() async {
    final db = await database;
    final maps = await db.query(
      'localidades_offline',
      where:
          '(sincronizado = 0 OR pendiente_actualizacion = 1) AND pendiente_eliminacion = 0',
      orderBy: 'fecha_creacion ASC',
    );
    return maps.map((map) => _localidadFromRow(map)).toList();
  }

  Future<int> countLocalidadesPendientesSync() async {
    await _asegurarPendientesEliminar();
    final db = await database;
    // Cuenta localidades con cambios sin subir: cabecera editada,
    // marcadas para eliminar, o con deletes de ítems 1:N en la cola offline.
    // La condición de cola excluye las ya contadas por eliminación completa.
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM localidades_offline lo '
      'WHERE (lo.editado = 1 AND lo.pendiente_eliminacion = 0) '
      'OR (lo.pendiente_eliminacion = 1) '
      'OR (lo.pendiente_eliminacion = 0 AND EXISTS ('
      '  SELECT 1 FROM pendientes_eliminar pe '
      '  WHERE pe.sincronizado = 0 AND pe.id_local = lo.id_local'
      '))',
    );
    if (result.isEmpty) return 0;
    return (result.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<int> updateLocalidad(
    EdanLocalidad localidad, {
    String? preserveFechaModificacion,
  }) async {
    if (localidad.idLocal == null) return 0;
    final db = await database;
    return await db.update(
      'localidades_offline',
      _localidadToRow(localidad, fechaModificacion: preserveFechaModificacion),
      where: 'id_local = ?',
      whereArgs: [localidad.idLocal],
    );
  }

  /// Actualiza solo la columna `datos_json` de una localidad (para reemplazar
  /// paths del servidor por paths locales de fotos descargadas).
  Future<int> updateLocalidadJson(String idLocal, String datosJson) async {
    final db = await database;
    return await db.update(
      'localidades_offline',
      {'datos_json': datosJson},
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Map<String, dynamic> _localidadToRow(
    EdanLocalidad l, {
    String? fechaModificacion,
    bool? sincronizado,
    bool? pendienteActualizacion,
    bool? pendienteEliminacion,
  }) {
    final fecha = fechaModificacion ?? DateTime.now().toIso8601String();
    l.fechaModificacion = fecha;
    return {
      'id_server': l.idServer,
      'id_edan': l.idEdan,
      'es_huerfana': l.esHuerfana ? 1 : 0,
      'id_tipo_localidad': l.idTipoLocalidad,
      'id_tipo_evento': l.idTipoEvento,
      'id_departamento': l.idDepartamento,
      'id_provincia': l.idProvincia,
      'id_municipio': l.idMunicipio,
      'departamento_nombre': l.departamentoNombre,
      'provincia_nombre': l.provinciaNombre,
      'municipio_nombre': l.municipioNombre,
      'localidad': l.nombre,
      'fecha_llenado': l.fechaLlenado,
      'fecha_evento': l.fechaEvento,
      'hora_evento': l.horaEvento,
      'total_poblacion_afectada': l.totalPoblacionAfectada,
      'total_familias_afectadas': l.totalFamiliasAfectadas,
      'total_familias_damnificadas': l.totalFamiliasDamnificadas,
      'grup_poblacion': l.grupPoblacion ? 1 : 0,
      'grup_salud': l.grupSalud ? 1 : 0,
      'grup_infraestructura': l.grupInfraestructura ? 1 : 0,
      'grup_servicios': l.grupServicios ? 1 : 0,
      'grup_educacion': l.grupEducacion ? 1 : 0,
      'grup_vivienda': l.grupVivienda ? 1 : 0,
      'grup_agropecuario': l.grupAgropecuario ? 1 : 0,
      'grup_proteccion': l.grupProteccion ? 1 : 0,
      'grup_necesidades': l.grupNecesidades ? 1 : 0,
      'id_edan_localidad_estado': l.idEdanLocalidadEstado,
      'estado_localidad': l.estadoLocalidad?.label,
      'datos_json': jsonEncode(l.toJson()),
      'sincronizado': (sincronizado ?? l.sincronizado) ? 1 : 0,
      'pendiente_actualizacion':
          (pendienteActualizacion ?? l.pendienteActualizacion) ? 1 : 0,
      'pendiente_eliminacion': (pendienteEliminacion ?? l.pendienteEliminacion)
          ? 1
          : 0,
      'editado': l.editado ? 1 : 0,
      'fecha_modificacion': fecha,
    };
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
        'editado': 0,
        'intentos_sync': 0,
        'ultimo_error': null,
        'fecha_modificacion': DateTime.now().toIso8601String(),
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  /// Marca sincronizada conservando la fecha_modificacion del servidor
  /// (autoridad de tiempo para LWW). No la sobrescribe con DateTime.now().
  /// NO toca pendiente_eliminacion — si está marcada para eliminar, se conserva.
  Future<int> markLocalidadAsSyncedConFecha(
    String idLocal,
    int idServer,
    String fechaModificacion,
  ) async {
    final db = await database;
    return await db.update(
      'localidades_offline',
      {
        'id_server': idServer,
        'sincronizado': 1,
        'pendiente_actualizacion': 0,
        'editado': 0,
        'intentos_sync': 0,
        'ultimo_error': null,
        'fecha_modificacion': fechaModificacion,
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  /// Marca la cabecera de una localidad con editado=1.
  Future<void> marcarCabeceraEditada(String idLocal) async {
    final db = await database;
    await db.update(
      'localidades_offline',
      {'editado': 1},
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  /// Recalcula el flag editado de la cabecera: 1 si alguna tabla de sección
  /// tiene al menos una fila con editado=1 para [idLocal]; 0 en caso contrario.
  Future<void> sincronizarFlagEditadoCabecera(String idLocal) async {
    final db = await database;
    var editado = 0;
    for (final tabla in EdanSeccionesRegistry.tablasSqlite()) {
      final maps = await db.rawQuery(
        'SELECT 1 FROM $tabla WHERE id_local = ? AND editado = 1 LIMIT 1',
        [idLocal],
      );
      if (maps.isNotEmpty) {
        editado = 1;
        break;
      }
    }
    await db.update(
      'localidades_offline',
      {'editado': editado},
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  // ========== Tracking de secciones v2 (localidad_seccion_sync) ==========

  /// Inserta o actualiza la fila de una sección marcándola como modificada
  /// localmente (candidata a subir) con su fecha local para LWW.
  Future<void> marcarSeccionModificada(
    String idLocal,
    String seccion, {
    String? fecha,
  }) async {
    final db = await database;
    await db.insert('localidad_seccion_sync', {
      'id_local': idLocal,
      'seccion': seccion,
      'modificada': 1,
      'fecha_modificacion': fecha ?? DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Marca varias secciones como modificadas (p. ej. las de una página del
  /// wizard). La cabecera se marca con la pseudo-ruta `cabecera`.
  Future<void> marcarSeccionesModificadas(
    String idLocal,
    List<String> secciones, {
    String? fecha,
  }) async {
    for (final s in secciones) {
      await marcarSeccionModificada(idLocal, s, fecha: fecha);
    }
  }

  /// Marca una sección como sincronizada (ya subida). OPCIONAL conservar la
  /// fecha local si se pasa [fecha].
  Future<void> marcarSeccionSincronizada(
    String idLocal,
    String seccion, {
    String? fecha,
  }) async {
    final db = await database;
    final fechaFinal = fecha ?? DateTime.now().toIso8601String();
    await db.update(
      'localidad_seccion_sync',
      {'modificada': 0, 'fecha_modificacion': fechaFinal},
      where: 'id_local = ? AND seccion = ?',
      whereArgs: [idLocal, seccion],
    );
  }

  /// Marca todas las secciones de una localidad como sincronizadas.
  Future<void> marcarTodasSeccionesSincronizadas(String idLocal) async {
    final db = await database;
    await db.update(
      'localidad_seccion_sync',
      {'modificada': 0},
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  /// Limpia la marca `modificada=1` solo para las rutas específicas enviadas.
  Future<void> clearSeccionesModificadas(
    String idLocal,
    Set<String> rutas,
  ) async {
    final db = await database;
    for (final ruta in rutas) {
      await db.update(
        'localidad_seccion_sync',
        {'modificada': 0},
        where: 'id_local = ? AND seccion = ?',
        whereArgs: [idLocal, ruta],
      );
    }
  }

  /// Secciones marcadas como modificadas localmente (candidatas a subir).
  Future<List<String>> getSeccionesModificadas(String idLocal) async {
    final db = await database;
    final maps = await db.query(
      'localidad_seccion_sync',
      columns: ['seccion'],
      where: 'id_local = ? AND modificada = 1',
      whereArgs: [idLocal],
    );
    return maps.map((m) => m['seccion'] as String).toList();
  }

  /// Fecha local de modificación de una sección (para LWW en conflictos).
  Future<String?> getSeccionFechaModificacion(
    String idLocal,
    String seccion,
  ) async {
    final db = await database;
    final maps = await db.query(
      'localidad_seccion_sync',
      columns: ['fecha_modificacion'],
      where: 'id_local = ? AND seccion = ?',
      whereArgs: [idLocal, seccion],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return maps.first['fecha_modificacion'] as String?;
  }

  /// Reemplaza la localidad local con la copia íntegra del servidor y
  /// conserva la fecha del servidor (autoridad de tiempo, evita regresión LWW).
  /// Limpia los flags de sección. [fechaServer] prevalece; si es null usa
  /// `localidad.fechaModificacion`.
  Future<int> reemplazarLocalidadDesdeServer(
    EdanLocalidad localidad, {
    String? fechaServer,
    int? idServer,
  }) async {
    if (localidad.idLocal == null) return 0;
    final db = await database;
    final fecha =
        fechaServer ??
        localidad.fechaModificacion ??
        DateTime.now().toIso8601String();
    final row = _localidadToRow(
      localidad,
      fechaModificacion: fecha,
      sincronizado: true,
    );
    row['id_server'] = idServer ?? localidad.idServer;
    row['pendiente_actualizacion'] = 0;
    row['pendiente_eliminacion'] = 0;
    row['editado'] = 0;
    final result = await db.update(
      'localidades_offline',
      row,
      where: 'id_local = ?',
      whereArgs: [localidad.idLocal],
    );
    await marcarTodasSeccionesSincronizadas(localidad.idLocal!);
    return result;
  }

  Future<int> markLocalidadAsPendingDeletion(String idLocal) async {
    final db = await database;
    return await db.update(
      'localidades_offline',
      {
        'pendiente_eliminacion': 1,
        'fecha_modificacion': DateTime.now().toIso8601String(),
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<int> updateLocalidadSyncAttempts(
    String idLocal,
    int intentos,
    String error,
  ) async {
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

  Future<int> updateLocalidadEstado(String idLocal, int idEstado) async {
    final db = await database;
    UgrLocalidadEstado? estado;
    for (final e in UgrLocalidadEstado.values) {
      if (e.id == idEstado) {
        estado = e;
        break;
      }
    }
    return await db.update(
      'localidades_offline',
      {
        'id_edan_localidad_estado': idEstado,
        'estado_localidad': estado?.label,
        'fecha_modificacion': DateTime.now().toIso8601String(),
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
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
    return generarIdLocal();
  }

  // ========== Tablas de sección (Modelo A v20) ==========

  /// Guarda (upsert por `id_seccion`) las filas de una sección en su tabla.
  ///
  /// - [marcarEditado=true] (default): marca `editado=1` → candidata a envío
  ///   (usado por el wizard al guardar cambios del usuario).
  /// - [marcarEditado=false]: marca `editado=0` → sincronizada con servidor
  ///   (usado tras pull con `?modo=comprimido`).
  ///
  /// Si [idEdanLocalidad] no es null, lo propaga a las filas recién escritas.
  Future<void> guardarFilasSeccion(
    String tabla,
    String idLocal,
    List<Map<String, dynamic>> filas, {
    int? idEdanLocalidad,
    bool marcarEditado = true,
  }) async {
    final db = await database;
    final batch = db.batch();
    final editadoValor = marcarEditado ? 1 : 0;
    for (final fila in filas) {
      final idSeccion = fila['id_seccion']?.toString();
      if (idSeccion == null || idSeccion.isEmpty) continue;
      final row = Map<String, dynamic>.from(fila);
      row['id_local'] = idLocal;
      if (idEdanLocalidad != null) row['id_edan_localidad'] = idEdanLocalidad;
      row['editado'] = editadoValor;
      // Determinar insertada_en_server:
      // - marcarEditado=false (datos del servidor tras pull): ya existen,
      //   marcar siempre insertada_en_server=1.
      // - marcarEditado=true (cambios locales): mantener la bandera si la fila
      //   ya estaba sincronizada en el server, o 0 si es nueva (INSERT).
      if (!marcarEditado) {
        row['insertada_en_server'] = 1;
      } else {
        final existente = await db.query(
          tabla,
          columns: ['insertada_en_server'],
          where: 'id_seccion = ?',
          whereArgs: [idSeccion],
          limit: 1,
        );
        row['insertada_en_server'] =
            (existente.isNotEmpty &&
                existente.first['insertada_en_server'] == 1)
            ? 1
            : 0;
      }
      row.remove('marcado_borrar');
      row.remove('_fecha_modificacion');
      row['fecha_modificacion_local'] = DateTime.now()
          .toUtc()
          .toIso8601String();
      batch.insert(tabla, row, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    if (idEdanLocalidad != null) {
      await propagarIdEdanAUnicaTabla(tabla, idLocal, idEdanLocalidad);
    }
  }

  /// Lee las filas con `editado=1` de una sección (las que faltan enviar).
  Future<List<Map<String, dynamic>>> leerFilasEditadas(
    String tabla,
    String idLocal,
  ) async {
    final db = await database;
    final maps = await db.query(
      tabla,
      where: 'id_local = ? AND editado = 1',
      whereArgs: [idLocal],
    );
    return maps;
  }

  /// Lee TODAS las filas de una sección para una localidad (sin filtrar por
  /// editado/borrado). Se usa para detectar el "vaciado" de una sección 1:1:
  /// si quedó vacía pero existía una fila sincronizada, hay que marcarla
  /// para DELETE en el próximo envío.
  Future<List<Map<String, dynamic>>> leerFilasSeccion(
    String tabla,
    String idLocal,
  ) async {
    final db = await database;
    return db.query(tabla, where: 'id_local = ?', whereArgs: [idLocal]);
  }

  /// Elimina las filas de una tabla de secci�n que ya no est�n en el modelo
  /// actual (las que el usuario quit� del array 1:N al guardar en el wizard).
  ///
  /// - Filas con `insertada_en_server=1` se marcan `marcado_borrar=1` para que
  ///   el pr�ximo push las DELETE en el servidor.
  /// - Filas con `insertada_en_server=0` se eliminan localmente (nunca llegaron
  ///   al servidor).
  ///
  /// [idsAConserver] es el conjunto de `id_seccion` que S� est�n en el modelo
  /// actual y no deben tocarse.
  Future<void> limpiarFilasFaltantesEnSeccion(
    String tabla,
    String idLocal,
    Set<String> idsAConserver,
  ) async {
    final db = await database;
    final existentes = await db.query(
      tabla,
      columns: ['id_seccion', 'insertada_en_server'],
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
    for (final fila in existentes) {
      final idSeccion = fila['id_seccion']?.toString() ?? '';
      if (idSeccion.isEmpty || idsAConserver.contains(idSeccion)) continue;
      final insertadaEnServer = fila['insertada_en_server'] == 1;
      if (insertadaEnServer) {
        await db.update(
          tabla,
          {'marcado_borrar': 1},
          where: 'id_seccion = ?',
          whereArgs: [idSeccion],
        );
      } else {
        await db.delete(tabla, where: 'id_seccion = ?', whereArgs: [idSeccion]);
      }
    }
  }

  /// Elimina TODAS las filas de las 14 tablas de sección para una localidad.
  /// Se llama antes de `popularSeccionesDesdeServer` tras un PULL con
  /// `?modo=comprimido` para que solo queden en SQLite las secciones que
  /// el servidor devolvió (las que tienen datos reales).
  Future<void> limpiarSeccionesLocalidad(String idLocal) async {
    final db = await database;
    final batch = db.batch();
    for (final tabla in EdanSeccionesRegistry.tablasSqlite()) {
      batch.delete(tabla, where: 'id_local = ?', whereArgs: [idLocal]);
    }
    await batch.commit(noResult: true);
  }

  /// Actualiza el campo `fotografia` de una fila de sección (para guardar el
  /// path del server después de subir la foto).
  Future<void> marcarFotografiaSeccion(
    String tabla,
    String idLocal,
    String idSeccion,
    String fotografia,
  ) async {
    final db = await database;
    await db.update(
      tabla,
      {'fotografia': fotografia},
      where: 'id_local = ? AND id_seccion = ?',
      whereArgs: [idLocal, idSeccion],
    );
  }

  /// Marca una fila de sección como sincronizada (editado=0, insertada en
  /// servidor). Se inserta al UPSERT como fila nueva (INSERT) la primera vez,
  /// y como UPDATE en ediciones reutilizando el MISMO id_seccion.
  Future<void> marcarFilaSeccionSincronizada(
    String tabla,
    String idSeccion, {
    bool insertadaEnServer = true,
  }) async {
    final db = await database;
    await db.update(
      tabla,
      {'editado': 0, 'insertada_en_server': insertadaEnServer ? 1 : 0},
      where: 'id_seccion = ?',
      whereArgs: [idSeccion],
    );
  }

  /// Marca todas las filas editadas de una sección como sincronizadas.
  Future<void> marcarFilasSeccionSincronizadas(
    String tabla,
    String idLocal,
  ) async {
    final db = await database;
    await db.update(
      tabla,
      {'editado': 0, 'insertada_en_server': 1},
      where: 'id_local = ? AND editado = 1',
      whereArgs: [idLocal],
    );
  }

  /// Marca una fila de sección borrada (`marcado_borrar=1`). Se usa al eliminar
  /// un ítem 1:N localmente; se elimina del servidor en el siguiente envío.
  Future<void> marcarFilaSeccionBorrada(String tabla, String idSeccion) async {
    final db = await database;
    await db.update(
      tabla,
      {'marcado_borrar': 1},
      where: 'id_seccion = ?',
      whereArgs: [idSeccion],
    );
  }

  /// Lee las filas marcadas para borrar de una sección.
  Future<List<Map<String, dynamic>>> leerFilasBorradas(
    String tabla,
    String idLocal,
  ) async {
    final db = await database;
    final maps = await db.query(
      tabla,
      where: 'id_local = ? AND marcado_borrar = 1',
      whereArgs: [idLocal],
    );
    return maps;
  }

  /// Elimina localmente una fila de sección (tras borrado confirmado el server).
  Future<void> eliminarFilaSeccion(String tabla, String idSeccion) async {
    final db = await database;
    await db.delete(tabla, where: 'id_seccion = ?', whereArgs: [idSeccion]);
  }

  // ========== Cola de deletes offline (pendientes_eliminar) ==========

  /// Garantiza que la tabla `pendientes_eliminar` exista. Crea la tabla bajo
  /// demanda si falta (por ejemplo, en bases inicializadas en una versión alta
  /// cuyo onCreate/migración no la crearon). Idempotente y no borra datos.
  Future<void> _asegurarPendientesEliminar() async {
    final db = await database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pendientes_eliminar (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_local TEXT NOT NULL,
        id_server INTEGER,
        id_seccion TEXT NOT NULL,
        ruta_v2 TEXT NOT NULL,
        tabla_sqlite TEXT NOT NULL,
        insertada_en_server INTEGER DEFAULT 0,
        sincronizado INTEGER DEFAULT 0,
        fecha_creacion TEXT NOT NULL
      )
    ''');
  }

  /// Registra un delete pendiente para procesarlo en el próximo sync.
  Future<void> agregarPendienteEliminar({
    required String idLocal,
    int? idServer,
    required String idSeccion,
    required String rutaV2,
    required String tablaSqlite,
    required bool insertadaEnServer,
  }) async {
    await _asegurarPendientesEliminar();
    final db = await database;
    await db.insert('pendientes_eliminar', {
      'id_local': idLocal,
      'id_server': idServer,
      'id_seccion': idSeccion,
      'ruta_v2': rutaV2,
      'tabla_sqlite': tablaSqlite,
      'insertada_en_server': insertadaEnServer ? 1 : 0,
      'sincronizado': 0,
      'fecha_creacion': DateTime.now().toIso8601String(),
    });
  }

  /// Lee todos los deletes pendientes no sincronizados.
  Future<List<Map<String, dynamic>>> leerPendientesEliminar() async {
    await _asegurarPendientesEliminar();
    final db = await database;
    return await db.query(
      'pendientes_eliminar',
      where: 'sincronizado = 0',
      orderBy: 'fecha_creacion ASC',
    );
  }

  /// Marca un delete pendiente como sincronizado.
  Future<void> marcarPendienteEliminadoSincronizado(int id) async {
    final db = await database;
    await db.update(
      'pendientes_eliminar',
      {'sincronizado': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Elimina un registro de la cola de pendientes (ya procesado).
  Future<void> eliminarPendienteEliminar(int id) async {
    final db = await database;
    await db.delete('pendientes_eliminar', where: 'id = ?', whereArgs: [id]);
  }


  // ========== Secciones activas (checkbox → secciones del JSON) ==========

  /// Marca secciones como activas (1) para una localidad.
  Future<void> activarSecciones(String idLocal, List<String> secciones) async {
    final db = await database;
    for (final s in secciones) {
      await db.insert(
        'localidad_secciones_activas',
        {'id_local': idLocal, 'seccion': s, 'activa': 1},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Desmarca secciones (0) para una localidad.
  Future<void> desactivarSecciones(
    String idLocal,
    List<String> secciones,
  ) async {
    final db = await database;
    for (final s in secciones) {
      await db.update(
        'localidad_secciones_activas',
        {'activa': 0},
        where: 'id_local = ? AND seccion = ?',
        whereArgs: [idLocal, s],
      );
    }
  }

  /// Reemplaza el set completo de secciones activas ( para pull/sync).
  Future<void> reemplazarSeccionesActivas(
    String idLocal,
    List<String> activas,
  ) async {
    final db = await database;
    await db.delete(
      'localidad_secciones_activas',
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
    for (final s in activas) {
      await db.insert('localidad_secciones_activas', {
        'id_local': idLocal,
        'seccion': s,
        'activa': 1,
      });
    }
  }

  /// Lee las secciones activas de una localidad.
  Future<List<String>> leerSeccionesActivas(String idLocal) async {
    final db = await database;
    final maps = await db.query(
      'localidad_secciones_activas',
      columns: ['seccion'],
      where: 'id_local = ? AND activa = 1',
      whereArgs: [idLocal],
    );
    return maps.map((m) => m['seccion'] as String).toList();
  }

  /// Propaga el `id_edan_localidad` a TODAS las secciones de una localidad
  /// (puente offline→online del Modelo A). Se llama una sola vez tras subir la
  /// cabecera.
  Future<void> propagarIdEdanASecciones(String idLocal, int idEdan) async {
    for (final tabla in EdanSeccionesRegistry.tablasSqlite()) {
      await propagarIdEdanAUnicaTabla(tabla, idLocal, idEdan);
    }
  }

  Future<void> propagarIdEdanAUnicaTabla(
    String tabla,
    String idLocal,
    int idEdan,
  ) async {
    final db = await database;
    await db.update(
      tabla,
      {'id_edan_localidad': idEdan},
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  /// Limpia todo el contenido de las tablas de sección y del carrete (borrado
  /// completo de una localidad).
  Future<void> limpiarSeccionesDeLocalidad(String idLocal) async {
    final db = await database;
    for (final tabla in EdanSeccionesRegistry.tablasSqlite()) {
      await db.delete(tabla, where: 'id_local = ?', whereArgs: [idLocal]);
    }
    await db.delete(
      'foto_pendiente',
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  // ========== Carrete de fotos (foto_pendiente) ==========

  /// Registra una foto local pendiente de subir. Si [idFoto] ya existe lo
  /// reemplaza; de lo contrario lo genera.
  /// Si [pathServidor] se provee, la foto viene del server (descargada=0,
  /// path_servidor=pathServidor) para que sea descargada offline.
  Future<String> insertarFotoPendiente({
    String? idFoto,
    String? idLocal,
    int? idEdanLocalidad,
    String? idSeccion,
    required String rutaLocalArchivo,
    double? lat,
    double? lon,
    String? pathServidor,
  }) async {
    final db = await database;
    final idFotoFinal = idFoto ?? generarIdLocal();
    await db.insert('foto_pendiente', {
      'id_foto': idFotoFinal,
      'id_local': idLocal,
      'id_edan_localidad': idEdanLocalidad,
      'id_seccion': idSeccion,
      'ruta_local_archivo': rutaLocalArchivo,
      'coordenada_lat': lat,
      'coordenada_lon': lon,
      'subida': pathServidor != null && pathServidor.isNotEmpty ? 1 : 0,
      'descargada': pathServidor != null ? 0 : 1,
      'path_servidor': pathServidor,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return idFotoFinal;
  }

  /// Fotos pendientes de subir (con retry: intentos < [maxIntentos]).
  Future<List<Map<String, dynamic>>> leerFotosPendientesSubida({
    int maxIntentos = 3,
  }) async {
    final db = await database;
    return await db.query(
      'foto_pendiente',
      where: 'subida = 0 AND intentos_subida < ?',
      whereArgs: [maxIntentos],
    );
  }

  /// Fotos pendientes de descarga (con retry: intentos < [maxIntentos]).
  Future<List<Map<String, dynamic>>> leerFotosPendientesDescarga({
    int maxIntentos = 3,
  }) async {
    final db = await database;
    return await db.query(
      'foto_pendiente',
      where:
          'descargada = 0 AND path_servidor IS NOT NULL '
          'AND path_servidor != "" '
          'AND intentos_descarga < ?',
      whereArgs: [maxIntentos],
    );
  }

  /// Marca una foto como subida guardando el path del servidor.
  Future<void> marcarFotoSubida(String idFoto, String pathServidor) async {
    final db = await database;
    await db.update(
      'foto_pendiente',
      {
        'subida': 1,
        'path_servidor': pathServidor,
        'intentos_subida': 0,
        'ultimo_error': null,
      },
      where: 'id_foto = ?',
      whereArgs: [idFoto],
    );
  }

  /// Marca una foto como descargada con el path local.
  Future<void> marcarFotoDescargada(String idFoto, String rutaDescarga) async {
    final db = await database;
    await db.update(
      'foto_pendiente',
      {
        'descargada': 1,
        'ruta_descarga': rutaDescarga,
        'intentos_descarga': 0,
        'ultimo_error': null,
      },
      where: 'id_foto = ?',
      whereArgs: [idFoto],
    );
  }

  /// Incrementa el contador de intentos de subida y registra el error.
  Future<void> marcarErrorSubida(String idFoto, String error) async {
    final db = await database;
    await db.rawUpdate(
      '''
      UPDATE foto_pendiente
      SET intentos_subida = intentos_subida + 1,
          ultimo_error = ?
      WHERE id_foto = ?
    ''',
      [error, idFoto],
    );
  }

  /// Incrementa el contador de intentos de descarga y registra el error.
  Future<void> marcarErrorDescarga(String idFoto, String error) async {
    final db = await database;
    await db.rawUpdate(
      '''
      UPDATE foto_pendiente
      SET intentos_descarga = intentos_descarga + 1,
          ultimo_error = ?
      WHERE id_foto = ?
    ''',
      [error, idFoto],
    );
  }

  /// Busca foto_pendiente por id_seccion (para关联ar con la tabla de sección).
  Future<Map<String, dynamic>?> buscarFotoPorSeccion(String idSeccion) async {
    final db = await database;
    final maps = await db.query(
      'foto_pendiente',
      where: 'id_seccion = ?',
      whereArgs: [idSeccion],
      limit: 1,
    );
    return maps.isEmpty ? null : maps.first;
  }

  // =====================================================================
  //  foto_pendiente_v2 — métodos para el nuevo schema limpio
  // =====================================================================

  /// Inserta una foto en la tabla v2.
  Future<String> insertarFotoPendienteV2({
    String? idFoto,
    required String idLocal,
    required String idSeccion,
    String? rutaLocalArchivo,
    String? pathServidor,
    double? lat,
    double? lon,
  }) async {
    final db = await database;
    final idFotoFinal = idFoto ?? generarIdLocal();
    await db.insert('foto_pendiente_v2', {
      'id_foto': idFotoFinal,
      'id_local': idLocal,
      'id_seccion': idSeccion,
      'ruta_local_archivo': rutaLocalArchivo,
      'path_servidor': pathServidor,
      'latitud': lat,
      'longitud': lon,
      'subida': pathServidor != null && pathServidor.isNotEmpty ? 1 : 0,
      'descargada': pathServidor != null && pathServidor.isNotEmpty ? 0 : 1,
      'intentos': 0,
      'fecha_creacion': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return idFotoFinal;
  }

  /// Fotos pendientes de upload (subida = 0, intentos < 3).
  Future<List<Map<String, dynamic>>> leerFotosPendientesUploadV2({
    int maxIntentos = 3,
  }) async {
    final db = await database;
    return await db.query(
      'foto_pendiente_v2',
      where: 'subida = 0 AND intentos < ?',
      whereArgs: [maxIntentos],
    );
  }

  /// Fotos pendientes de download (descargada = 0, path_servidor existe).
  Future<List<Map<String, dynamic>>> leerFotosPendientesDownloadV2({
    int maxIntentos = 3,
  }) async {
    final db = await database;
    return await db.query(
      'foto_pendiente_v2',
      where:
          'descargada = 0 AND path_servidor IS NOT NULL '
          'AND path_servidor != "" AND intentos < ?',
      whereArgs: [maxIntentos],
    );
  }

  /// Marca una foto como subida exitosamente.
  Future<void> marcarFotoSubidaV2(String idFoto, String pathServidor) async {
    final db = await database;
    await db.update(
      'foto_pendiente_v2',
      {
        'subida': 1,
        'path_servidor': pathServidor,
        'intentos': 0,
        'ultimo_error': null,
      },
      where: 'id_foto = ?',
      whereArgs: [idFoto],
    );
  }

  /// Marca una foto como descargada exitosamente.
  Future<void> marcarFotoDescargadaV2(String idFoto, String rutaLocal) async {
    final db = await database;
    await db.update(
      'foto_pendiente_v2',
      {
        'descargada': 1,
        'ruta_local_archivo': rutaLocal,
        'intentos': 0,
        'ultimo_error': null,
      },
      where: 'id_foto = ?',
      whereArgs: [idFoto],
    );
  }

  /// Registra error de upload/download e incrementa intentos.
  Future<void> marcarFotoErrorV2(String idFoto, String error) async {
    final db = await database;
    await db.rawUpdate(
      '''
      UPDATE foto_pendiente_v2
      SET intentos = intentos + 1, ultimo_error = ?
      WHERE id_foto = ?
    ''',
      [error, idFoto],
    );
  }

  /// Busca foto_v2 por id_seccion.
  Future<Map<String, dynamic>?> buscarFotoV2PorSeccion(String idSeccion) async {
    final db = await database;
    final maps = await db.query(
      'foto_pendiente_v2',
      where: 'id_seccion = ?',
      whereArgs: [idSeccion],
      limit: 1,
    );
    return maps.isEmpty ? null : maps.first;
  }

  /// Elimina los registros de `foto_pendiente_v2` de una sección y devuelve las
  /// rutas locales asociadas para que el llamador borre los archivos. Evita
  /// dejar fotos huérfanas (archivo en disco + subida pendiente) cuando se
  /// elimina el ítem de sección dueño de la foto.
  Future<List<String>> eliminarFotosDeSeccionV2(
    String idLocal,
    String idSeccion,
  ) async {
    final db = await database;
    final rows = await db.query(
      'foto_pendiente_v2',
      columns: ['ruta_local_archivo'],
      where: 'id_local = ? AND id_seccion = ?',
      whereArgs: [idLocal, idSeccion],
    );
    await db.delete(
      'foto_pendiente_v2',
      where: 'id_local = ? AND id_seccion = ?',
      whereArgs: [idLocal, idSeccion],
    );
    return rows
        .map((r) => r['ruta_local_archivo'] as String?)
        .whereType<String>()
        .where((r) => r.isNotEmpty)
        .toList();
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
