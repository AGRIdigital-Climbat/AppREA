import '../../models/edan.dart';
import '../api_service.dart';
import '../connectivity_service.dart';
import '../database_helper.dart';

/// Retro-trae el motivo de rechazo (`observacion_estado`) para items que los
/// listados muestran en "Rechazado UGR" pero cuya fila ligera del servidor no
/// incluyo el campo (p. ej. `sync/pull`, `/formularios/estados` o
/// `municipio/{id}` cuando aun no lo serializan).
///
/// Reglas (para no molestar al usuario ni al servidor):
///  * SOLO online; sin red retorna de inmediato (offline-first intacto).
///  * Maximo [tope] peticiones por pasada (10 por defecto).
///  * Cada `idServer` se intenta UNA vez por sesion: evitar reintentos en
///    cada scroll/recarga cuando el server no tiene motivo.
///  * Actualiza el modelo en memoria (la tarjeta pinta el motivo al instante)
///    y persiste en SQLite la columna `observacion_estado` si la fila V2
///    existe en el dispositivo. Esa columna NUNCA viaja en el payload.
class EdanMotivoBackfill {
  EdanMotivoBackfill._();

  static final Set<int> _intentados = {};

  /// Devuelve `true` si al menos un item recibio motivo (el llamador hace
  /// setState para repintar las tarjetas).
  static Future<bool> ejecutar(
    List<EdanLocalidad> items, {
    int tope = 10,
  }) async {
    if (items.isEmpty) return false;
    if (!ConnectivityService().isConnected) return false;

    final pendientes = items
        .where((l) =>
            l.estadoLocalidad == UgrLocalidadEstado.rechazadoUgr &&
            (l.observacionEstado ?? '').trim().isEmpty &&
            l.idServer != null &&
            !_intentados.contains(l.idServer))
        .take(tope)
        .toList();
    if (pendientes.isEmpty) return false;

    var huboCambios = false;
    for (final l in pendientes) {
      final idServer = l.idServer!;
      _intentados.add(idServer);
      try {
        final data = await ApiService.instance.getLocalidad(idServer);
        dynamic obs = data['observacion_estado'];
        if (obs == null && data['cabecera'] is Map) {
          obs = (data['cabecera'] as Map)['observacion_estado'];
        }
        final texto = (obs?.toString() ?? '').trim();
        if (texto.isEmpty) continue;

        // En memoria: la tarjeta ya pintara el motivo tras el setState.
        l.observacionEstado = texto;
        // Persistente (si la fila V2 vive en este dispositivo): sobrevive a
        // la recarga de la lista y al proximo arranque.
        final uuid = l.uuidEdanLocalidad;
        if (uuid != null && uuid.isNotEmpty) {
          try {
            await DatabaseHelper.instance
                .actualizarObservacionEstado(uuid, texto);
          } catch (_) {}
        }
        huboCambios = true;
      } catch (_) {
        // Silencioso: es un extra estetico, nunca rompe la lista.
      }
    }
    return huboCambios;
  }
}
