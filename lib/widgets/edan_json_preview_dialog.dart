import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/theme.dart';
import '../models/edan.dart';
import '../services/api/edan_api_v2.dart';
import '../services/database_helper.dart';
import '../services/edan/edan_localidades_envio_v2_service.dart';
import '../services/sync/edan_sync_engine_v2.dart';
import '../services/app_logger_ui.dart';

/// Depurador del ciclo EDAN (long-press en las tarjetas de localidad).
///
/// Dos pestañas grandes, una por tipo de dato, con un conmutador GET/POST
/// dentro de cada una:
///
///  * **Datos**
///    - **GET**: el documento CRUDO del servidor
///      (`GET /api/v2/edan/formularios/{uuid}/completo`): la caché local
///      (`formularios.datos_json_servidor`, columna v34) o el resultado en vivo
///      con el botón *Refrescar* (🔄).
///    - **POST**: exactamente el `body` de
///      `POST /api/v2/edan/formularios/completo`, tal cual lo codifica y envía
///      el motor (mismo mapa y mismo `jsonEncode`), **sin envoltorios**.
///  * **Fotos**
///    - **GET**: la clave `fotos[]` del documento del servidor.
///    - **POST**: los `multipart` pendientes de
///      `POST /api/v2/edan/fotografias` (uno por foto).
///
/// Sirve para depurar todo el ciclo: crear completo, crear incompleto,
/// recuperar, leer, mostrar local con las APIs nuevas y ver el JSON de fotos
/// GET y POST del registro. Es de solo lectura: nunca sube fotos; el
/// *Refrescar* solo persiste la caché GET cuando la localidad NO está sucia
/// (misma guardia `pendiente_push`/cola que el sync), así que un borrador en
/// edición no se pisa.
class EdanJsonPreviewDialog {
  EdanJsonPreviewDialog._();

  static Future<void> show(BuildContext context, EdanLocalidad localidad) async {
    final nombre = localidad.nombre.isNotEmpty ? localidad.nombre : 'Sin nombre';

    showDialog(
      context: context,
      builder: (_) => _JsonPreviewBody(localidad: localidad, titulo: nombre),
    );
  }
}

class _JsonPreviewBody extends StatefulWidget {
  final EdanLocalidad localidad;
  final String titulo;

  const _JsonPreviewBody({required this.localidad, required this.titulo});

  @override
  State<_JsonPreviewBody> createState() => _JsonPreviewBodyState();
}

class _JsonPreviewBodyState extends State<_JsonPreviewBody> {
  static const JsonEncoder _enc = JsonEncoder.withIndent('  ');

  // Nivel 1: 0 = Datos, 1 = Fotos.
  int _nivel1 = 0;
  // Nivel 2: 0 = GET, 1 = POST.
  int _nivel2 = 0;

  String? _uuid;
  Map<String, Object?>? _row; // fila `formularios` (null en legacy)
  int? _idServer;

  // ── GET ──
  Map<String, dynamic>? _docGet;
  String _fuenteGet = 'caché'; // 'caché' | 'vivo'
  bool _loadingGet = true;
  String? _errorGet;

  // ── POST ──
  Map<String, dynamic>? _payloadPost;
  List<Map<String, dynamic>> _fotosPost = const [];
  bool _loadingPost = true;
  String? _errorPost;
  bool _legacyPost = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  /// Texto JSON de la vista activa (crudo, sin envoltorios). `''` si vacío.
  String get _textoActivo {
    // Datos · GET — documento del servidor tal cual llega.
    if (_nivel1 == 0 && _nivel2 == 0) {
      return _docGet != null ? _enc.convert(_docGet) : '';
    }
    // Datos · POST — body exacto de /formularios/completo.
    if (_nivel1 == 0 && _nivel2 == 1) {
      return _payloadPost != null ? _enc.convert(_payloadPost) : '';
    }
    // Fotos · GET — la clave fotos[] del documento del servidor.
    if (_nivel1 == 1 && _nivel2 == 0) {
      final fotos = _docGet?['fotos'];
      return fotos != null ? _enc.convert(fotos) : '';
    }
    // Fotos · POST — multipart pendientes de /fotografias.
    return _fotosPost.isNotEmpty ? _enc.convert(_fotosPost) : '';
  }

  bool get _loadingActivo => _nivel2 == 0 ? _loadingGet : _loadingPost;
  String? get _errorActivo => _nivel2 == 0 ? _errorGet : _errorPost;

  String? get _vacioActivo {
    if (_nivel1 == 0 && _nivel2 == 0) {
      return 'Sin documento GET. Toca 🔄 para traerlo del servidor '
          '(requiere red).';
    }
    if (_nivel1 == 1 && _nivel2 == 0) {
      return 'Sin fotos en el documento del servidor. Toca 🔄 para traerlo.';
    }
    if (_nivel1 == 1 && _nivel2 == 1) {
      return 'Sin fotos pendientes de subir.';
    }
    return 'Sin datos que mostrar.';
  }

  Future<void> _cargar() async {
    _uuid = widget.localidad.idLocal;
    final db = DatabaseHelper.instance;
    if (_uuid != null && _uuid!.isNotEmpty) {
      final rows = await (await db.database).query(
        'formularios',
        where: 'uuid_edan_localidad = ?',
        whereArgs: [_uuid],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        _row = rows.first;
        _idServer = (_row!['id_server'] as num?)?.toInt();
      }
    }
    await Future.wait([_cargarGetCache(), _cargarPost()]);
    if (mounted) setState(() => _loadingGet = false);
  }

  /// Caché GET: el documento crudo que dejó el último `GET /completo` (pull o
  /// *Refrescar*). `null` si nunca se sincronizó por las APIs nuevas.
  Future<void> _cargarGetCache() async {
    final crudo = _row?['datos_json_servidor'];
    if (crudo is! String || crudo.isEmpty) return;
    try {
      final d = jsonDecode(crudo);
      if (d is Map) {
        _docGet = Map<String, dynamic>.from(d);
        _fuenteGet = 'caché';
      }
    } catch (_) {
      // documento corrupto: se ignora (el GET tab ofrecerá Refrescar).
    }
  }

  Future<void> _cargarPost() async {
    try {
      if (_row != null && _uuid != null) {
        _payloadPost = await EdanSyncEngineV2.prepararPayloadCompleto(
          _uuid!,
          _row!,
          dbHelper: DatabaseHelper.instance,
        );
        _fotosPost = await _describirFotos();
      } else {
        // Sin cabecera V2 (reporte UGR/IA legado): no hay payload `/completo`
        // que mostrar. Se imprime el modelo local cargado desde las tablas
        // `seccion_*`, rotulado como tal porque NO es lo que se enviaría.
        await EdanLocalidadesEnvioV2Service()
            .cargarSeccionesDesdeSQLite(widget.localidad);
        _payloadPost = widget.localidad.toApiJson();
        _legacyPost = true;
      }
    } catch (e) {
      _errorPost = e.toString();
    } finally {
      if (mounted) setState(() => _loadingPost = false);
    }
  }

  /// Descriptor de cada `POST /fotografias` multipart pendiente (solo
  /// lectura: resuelve el `tipo_entidad` sin escribir en la cola).
  Future<List<Map<String, dynamic>>> _describirFotos() async {
    final uuid = _uuid;
    if (uuid == null) return const [];
    final filas = await EdanSyncEngineV2.fotosPendientesDeLocalidad(
      uuid,
      dbHelper: DatabaseHelper.instance,
    );
    final out = <Map<String, dynamic>>[];
    for (final f in filas) {
      final tipo = await EdanSyncEngineV2.resolverTipoEntidadSoloLectura(
        f,
        dbHelper: DatabaseHelper.instance,
      );
      final ruta = f['ruta_local'] as String? ?? '';
      int? bytes;
      try {
        final file = File(ruta);
        if (await file.exists()) bytes = await file.length();
      } catch (_) {}
      out.add({
        'endpoint': 'POST /api/v2/edan/fotografias',
        'multipart': {
          'uuid_fotografia': f['uuid_fotografia'],
          'tipo_entidad': tipo,
          'uuid_registro': f['uuid_registro'],
          'archivo': {
            'path': ruta,
            'existe': bytes != null,
            if (bytes != null) 'bytes': bytes,
            if (f['sha256'] != null) 'sha256': f['sha256'],
          },
        },
        'estado': f['estado'],
        'ultimo_error': ?f['ultimo_error'],
      });
    }
    return out;
  }

  /// GET en vivo. Muestra el documento recibido de inmediato y, best-effort,
  /// persiste la caché vía `aplicarDocumentoCompleto` (que normaliza
  /// secciones y escribe `datos_json_servidor`; se omite si la localidad está
  /// sucia, para no pisar un borrador en edición).
  Future<void> _refrescarGet() async {
    final uuid = _uuid;
    if (uuid == null) return;
    setState(() {
      _loadingGet = true;
      _errorGet = null;
    });
    try {
      final api = EdanApiV2();
      var resp = await api.obtenerFormularioCompleto(uuid);
      if (!resp.ok && _idServer != null) {
        // Fallback: si el uuid no está en el servidor, probar por id.
        resp = await api.obtenerFormularioCompleto('$_idServer', useId: true);
      }
      if (!resp.ok || resp.data == null) {
        throw EdanApiError(
          statusCode: resp.statusCode,
          detail: resp.message ?? 'HTTP ${resp.statusCode}',
        );
      }
      final doc = resp.data!;
      try {
        await EdanSyncEngineV2(api: api).aplicarDocumentoCompleto(doc);
      } catch (_) {
        // best-effort: el POST/GET del diálogo no depende de la persistencia.
      }
      if (!mounted) return;
      setState(() {
        _docGet = doc;
        _fuenteGet = 'vivo';
        _loadingGet = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorGet = e.toString();
        _loadingGet = false;
      });
    }
  }

  void _copiar(String texto, String mensaje) {
    if (texto.isEmpty) return;
    Clipboard.setData(ClipboardData(text: texto));
    showAppSnackBar(context, 
      SnackBar(
        content: Text(mensaje),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final texto = _textoActivo;
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78,
          maxWidth: 520,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context, texto),
            const Divider(height: 1),
            _toolbar(),
            const Divider(height: 1),
            // Origen page01 (solo informativo, NO viaja): lo tildado en los
            // checks (columnas `grup_*` de SQLite) frente a lo que realmente
            // se envía (`imp_*` del payload = grupos CON datos). Evita la
            // confusión "marqué el grupo pero no sale en el JSON": `grup_*`
            // nunca viaja por contrato (el servidor lo deriva; enviarlo da
            // 400). Solo vista Datos·POST.
            if (_nivel1 == 0 && _nivel2 == 1) _bannerOrigenGrupos(),
            Flexible(
              child: _cuerpo(
                loading: _loadingActivo,
                error: _errorActivo,
                texto: texto.isEmpty ? null : texto,
                vacio: _vacioActivo,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String texto) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
      child: Row(
        children: [
          const Icon(Icons.data_object, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Depurador JSON EDAN',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  widget.titulo,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Copiar JSON de la vista',
            onPressed:
                texto.isNotEmpty ? () => _copiar(texto, 'JSON copiado') : null,
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _toolbar() {
    IconData icon;
    String badge;
    String endpoint;
    if (_nivel1 == 0 && _nivel2 == 0) {
      icon = _fuenteGet == 'vivo' ? Icons.cloud_done : Icons.offline_pin;
      badge = _fuenteGet;
      endpoint =
          'GET /api/v2/edan/formularios/${_uuid ?? '<sin uuid>'}/completo';
    } else if (_nivel1 == 0) {
      icon = _legacyPost ? Icons.warning_amber : Icons.upload;
      badge = _legacyPost ? 'legacy' : 'body';
      endpoint = _legacyPost
          ? 'modelo local (sin formulario V2: nada por /completo)'
          : 'POST /api/v2/edan/formularios/completo';
    } else if (_nivel2 == 0) {
      icon = Icons.photo_library_outlined;
      badge = 'doc[fotos]';
      endpoint =
          'GET /api/v2/edan/formularios/${_uuid ?? '<sin uuid>'}/completo → fotos[]';
    } else {
      icon = Icons.upload;
      badge = '${_fotosPost.length}';
      endpoint = 'POST /api/v2/edan/fotografias (multipart)';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
      child: Column(
        children: [
          Row(
            children: [
              _segmento(
                etiquetas: const ['DATOS', 'FOTOS'],
                seleccionado: _nivel1,
                onTap: (i) => setState(() => _nivel1 = i),
              ),
              const Spacer(),
              _segmento(
                etiquetas: const ['GET', 'POST'],
                seleccionado: _nivel2,
                onTap: (i) => setState(() => _nivel2 = i),
              ),
              SizedBox(
                width: 40,
                child: _nivel2 == 0
                    ? IconButton(
                        icon: const Icon(Icons.refresh, size: 18),
                        tooltip: 'Refrescar (GET en vivo)',
                        onPressed: _loadingGet ? null : _refrescarGet,
                      )
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _badge(icon, badge),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  endpoint,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _segmento({
    required List<String> etiquetas,
    required int seleccionado,
    required ValueChanged<int> onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < etiquetas.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: i == seleccionado
                      ? AppColors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  etiquetas[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: i == seleccionado
                        ? Colors.white
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cuerpo({
    required bool loading,
    required String? error,
    required String? texto,
    String? vacio,
  }) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Cargando JSON...'),
          ],
        ),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 32),
            const SizedBox(height: 8),
            const Text(
              'Error al obtener el JSON',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              error,
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    if (texto == null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          vacio ?? 'Sin datos que mostrar.',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        texto,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          height: 1.5,
        ),
      ),
    );
  }

  /// Banner informativo (no parte del payload): compara lo tildado en
  /// page01 (columnas `grup_*` de SQLite) con lo que el payload realmente
  /// envía (`imp_*` = grupos con datos). Solo Datos·POST.
  Widget _bannerOrigenGrupos() {
    const grupos = [
      'grup_poblacion',
      'grup_salud',
      'grup_infraestructura',
      'grup_servicios',
      'grup_educacion',
      'grup_vivienda',
      'grup_agropecuario',
      'grup_proteccion',
      'grup_necesidades',
    ];
    final tildados = <String>[];
    final fila = _row;
    if (fila != null) {
      for (final g in grupos) {
        if ((fila[g] as num?)?.toInt() == 1) tildados.add(g);
      }
    }
    final impEnviados = <String>[];
    final payload = _payloadPost;
    if (payload != null) {
      for (final k in payload.keys) {
        if (k.startsWith('imp_') && payload[k] == true) {
          impEnviados.add(k);
        }
      }
    }
    final texto = tildados.isEmpty
        ? 'Ningún grupo tildado en page01.'
        : 'Tildados en page01: ${tildados.join(', ')}'
            '${impEnviados.isEmpty ? ' → (sin datos: no viajan)' : ' → envían: ${impEnviados.join(', ')}'}';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        'Solo informativo (no viaja): $texto',
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _badge(IconData icon, String texto) {    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            texto,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
