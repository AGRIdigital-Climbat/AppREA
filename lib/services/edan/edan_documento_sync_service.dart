import 'package:flutter/foundation.dart';

import '../api_service.dart';
import '../database_helper.dart';

/// Cola de borrados del camino LEGADO (UGR / Asistente IA), que persiste en
/// `localidades_offline` + `seccion_*` y `pendientes_eliminar`.
///
/// El envío de EDANs **ya no pasa por aquí**: el RESP usa las APIs nuevas
/// (`POST /api/v2/edan/formularios/completo` para el documento y
/// `POST /api/v2/edan/fotografias` para las fotos), orquestadas por
/// [EdanEnvioV2] y `EdanSyncEngineV2`. Se retiraron de esta clase
/// `enviarLocalidadDocumento` (`POST/PUT /localidades/…/documento` +
/// `POST /upload`), `listarMisReportes`, `eliminarFilasAntesDelPush`,
/// `eliminarLocalidadDocumento` y `_subirFotosCarrete`.
///
/// Lo que queda es Propagar los DELETE por fila de sección que el usuario hizo
/// estando offline; es el único paso del flujo legacy que todavía no tiene
/// equivalente V2 porque el UGR/IA sigue escribiendo en las tablas viejas
/// (riesgo R6 del plan).
class EdanDocumentoSyncService {
  EdanDocumentoSyncService({ApiService? api, DatabaseHelper? db})
      : _api = api ?? ApiService.instance,
        _db = db ?? DatabaseHelper.instance;

  final ApiService _api;
  final DatabaseHelper _db;

  /// Procesa la cola de deletes offline (`pendientes_eliminar`).
  ///
  /// Nunca lanza: ante cualquier fallo aislado, se registra y se continúa, para
  /// no abortar el resto de la cola.
  Future<void> procesarColaDeletes() async {
    List<Map<String, dynamic>> pendientes;
    try {
      pendientes = await _db.leerPendientesEliminar();
    } catch (e) {
      debugPrint('[DocSync] procesarColaDeletes: no se pudo leer la cola: $e');
      return;
    }
    if (pendientes.isEmpty) return;

    debugPrint('[DocSync] Procesando ${pendientes.length} deletes en cola');
    for (final p in pendientes) {
      final id = p['id'] as int;
      final idServer = p['id_server'] as int?;
      final idSeccion = p['id_seccion']?.toString() ?? '';
      final rutaV2 = p['ruta_v2']?.toString() ?? '';
      final tablaSqlite = p['tabla_sqlite']?.toString() ?? '';
      final insertadaEnServer = p['insertada_en_server'] == 1;

      if (idSeccion.isEmpty || rutaV2.isEmpty) {
        await _db.eliminarPendienteEliminar(id);
        continue;
      }

      // DELETE al servidor solo si la fila estaba sincronizada.
      if (insertadaEnServer && idServer != null) {
        try {
          final res = await _api.deleteSeccionItem(
            idLocalidad: '$idServer',
            rutaSeccion: rutaV2,
            idSeccion: idSeccion,
          );
          if (res.success) {
            debugPrint('[DocSync] DELETE cola OK $idSeccion ($rutaV2)');
          } else if (res.notFound) {
            // El item nunca existió en el servidor (o ya no está): es seguro
            // descartar el borrado local y quitar el pendiente de la cola.
            debugPrint('[DocSync] DELETE cola 404 (inexistente) $idSeccion '
                '($rutaV2) → se descarta: ${res.detalle}');
          } else {
            debugPrint('[DocSync] DELETE cola falló $idSeccion ($rutaV2): '
                '${res.detalle}');
            continue; // No marcar como sincronizado si falló
          }
        } catch (e) {
          debugPrint('[DocSync] Error DELETE cola $idSeccion: $e');
          continue;
        }
      }

      // Borrar localmente la fila de sección (si aún existe).
      if (tablaSqlite.isNotEmpty) {
        try {
          await _db.eliminarFilaSeccion(tablaSqlite, idSeccion);
        } catch (_) {}
      }

      await _db.marcarPendienteEliminadoSincronizado(id);
      await _db.eliminarPendienteEliminar(id);
    }
  }
}
