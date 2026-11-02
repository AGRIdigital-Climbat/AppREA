import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../models/edan.dart';
import '../api/edan_api_v2.dart';
import '../app_logger.dart';
import '../auth_service.dart';
import '../sync/edan_sync_engine_v2.dart';
import 'edan_store_v2.dart';

/// Envío **inmediato** de UNA localidad por las APIs nuevas de EDAN.
///
/// Sustituye a `EdanDocumentoSyncService.enviarLocalidadDocumento`, que usaba
/// el grupo legado `EDAN_LOCALIDADES`:
///   * `POST/PUT /api/v2/edan/localidades/…/documento`  →  `POST /formularios/completo`
///   * `POST /api/v2/edan/upload` (fotos)               →  `POST /fotografias`
///
/// Concentrarlo aquí garantiza que el botón "Enviar" del dashboard, la pestaña
/// de localidades y el sincronizador de fondo ([EdanSyncEngineV2.sincronizar])
/// armen SIEMPRE el mismo payload ([EdanSyncEngineV2.prepararPayloadCompleto])
/// y dejen los mismos marcadores de confirmación.
class EdanEnvioV2 {
  EdanEnvioV2._();

  /// TEMP DIAG (borrar): motivo del último fallo de [enviar] (status HTTP +
  /// detail), para mostrarlo en el snackbar mientras se depura el bug de
  /// `danos_agricultura`. Se resetea en cada llamada.
  static String? ultimoErrorDiagnostico;

  /// Empuja [localidad] y sus fotos. Devuelve `false` si no hay nada que
  /// enviar o si el servidor rechazó; en ese caso la localidad queda
  /// `pendiente_push = 1` y el próximo `sincronizar()` la reintenta.
  ///
  /// [idEdanLocalidadEstado] es el estado destino (p. ej. enviado_ugr = 2); se
  /// escribe en `formularios` **antes** de armar el payload, para que el
  /// documento que recibe el servidor ya traiga el estado nuevo.
  static Future<bool> enviar(
    EdanLocalidad localidad, {
    required int idEdanLocalidadEstado,
  }) async {
    final store = EdanStoreV2.instance;
    var uuid = localidad.uuidEdanLocalidad ?? localidad.idLocal;
    if (uuid == null || uuid.isEmpty) return false;

    // Reporte sin cabecera V2 (borrador muy viejo o importado por otro camino):
    // se materializa desde el modelo para poder usar `/completo`.
    if (await store.cargarFormulario(uuid) == null) {
      await store.guardarFormulario(
        localidad,
        usuarioId: localidad.idUsuario ?? 0,
      );
      uuid = localidad.uuidEdanLocalidad ?? uuid;
    }

    // `proteccion` necesita el `id_grupo_vulnerable_catalogo` real; si el
    // listado lo resolvió en memoria, se persiste en `filas_seccion` antes de
    // enviar (el payload se construye desde SQLite, no desde el modelo).
    await _persistirProteccionResuelta(store, uuid, localidad);

    Directory? dirFotos;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      // Única carpeta de fotos (capturas y descargas): `report_photos/`.
      dirFotos = Directory('${appDir.path}/report_photos');
      await dirFotos.create(recursive: true);
    } catch (_) {
      dirFotos = null; // sin disco: el motor omite la descarga de fotos
    }

    AppLogger.instance.sync(
      titulo: 'Enviar EDAN: inicio',
      detalle: 'uuid=$uuid destino_estado=$idEdanLocalidadEstado',
    );

    final engine = EdanSyncEngineV2(
      api: EdanApiV2(),
      dirFotos: dirFotos,
      // Igual que `sincronizar()`: el watermark y el push se restringen al
      // dueño (sin esto, el envío inmediato usaba comportamiento global y
      // en equipos multi-usuario divergía del sync normal).
      usuarioId: AuthService.instance.userId,
    );
    final ok = await engine.enviarLocalidad(
      uuid,
      idEdanLocalidadEstado: idEdanLocalidadEstado,
    );
    ultimoErrorDiagnostico = ok ? null : engine.ultimoErrorDiagnostico; // TEMP DIAG (borrar)
    AppLogger.instance.sync(
      titulo: 'Enviar EDAN: ${ok ? 'CONFIRMADO' : 'FALLÓ'}',
      detalle: 'uuid=$uuid destino_estado=$idEdanLocalidadEstado'
          '${ok ? '' : ' error=${engine.ultimoErrorDiagnostico ?? 'sin detalle'}'}',
      nivel: ok ? AppLogLevel.info : AppLogLevel.error,
    );

    if (ok) {
      localidad
        ..uuidEdanLocalidad = uuid
        ..idEdanLocalidadEstado = idEdanLocalidadEstado
        ..sincronizado = true
        ..pendienteActualizacion = false
        ..editado = false;
    }
    return ok;
  }

  /// Descarga el documento canónico de una localidad por
  /// `GET /api/v2/edan/formularios/{uuid}/completo`, lo deja en SQLite y
  /// devuelve el modelo listo para la vista previa.
  ///
  /// Reemplaza a `ApiService.obtenerDocumento`
  /// (`GET /localidades/{id}/documento`, grupo legado `EDAN_LOCALIDADES`).
  /// Primero se aplica con el motor (cabecera + nodo `grupos`) y DESPUÉS se
  /// relee con la misma fuente que usan el badge, el wizard y el JSON de
  /// depuración ([EdanSeccionesFuente]): así la preview del reporte de OTRO
  /// usuario muestra exactamente lo que vería su dueño, y queda cacheada para
  /// verse offline.
  ///
  /// [useId] = `true` cuando la referencia es el `id_server` numérico en vez
  /// del uuid. Devuelve `null` si no hay red, el recurso no existe o el
  /// servidor rechaza.
  static Future<EdanLocalidad?> descargar(
    String referencia, {
    bool useId = false,
  }) async {
    if (referencia.isEmpty) return null;
    final api = EdanApiV2();
    final doc = <String, dynamic>{};
    try {
      final resp =
          await api.obtenerFormularioCompleto(referencia, useId: useId);
      final data = resp.data;
      if (data == null) return null;
      doc.addAll(data);
      await EdanSyncEngineV2(api: api).aplicarDocumentoCompleto(data);
    } on EdanApiError {
      return null;
    } on SocketException {
      return null;
    }

    final uuid = doc['uuid_edan_localidad']?.toString() ?? referencia;
    final store = EdanStoreV2.instance;
    final loc = await store.cargarFormulario(uuid);
    if (loc == null) return null;
    await store.cargarSecciones(loc);
    return loc;
  }

  /// Borra una localidad del servidor por
  /// `DELETE /api/v2/edan/formularios/{uuid_ref}` (cascada: secciones,
  /// viviendas y fotos). Reemplazo de
  /// `DELETE /api/v2/edan/localidades/{id}/documento` (grupo legado).
  ///
  /// `[uuid_ref]` acepta uuid o `id_server` numérico. Devuelve `false` si el
  /// servidor rechaza o no hay red; en ese caso el llamador debe dejar la
  /// localidad marcada `pendiente_eliminacion` para reintentar al sincronizar.
  static Future<bool> borrar(String uuidRef) async {
    if (uuidRef.isEmpty) return false;
    try {
      await EdanApiV2().eliminarFormulario(uuidRef);
      return true;
    } on EdanApiError {
      return false;
    } on EdanApiConflict {
      return false;
    } on SocketException {
      return false;
    }
  }

  /// Escribe en `filas_seccion` los `id_grupo_vulnerable_catalogo` que la UI
  /// haya resuelto desde el catálogo en memoria.
  static Future<void> _persistirProteccionResuelta(
    EdanStoreV2 store,
    String uuid,
    EdanLocalidad localidad,
  ) async {
    if (localidad.proteccion.every((g) => g.idGrupoVulnerableCatalogo != null)) {
      return;
    }
    final conId = localidad.proteccion
        .where((g) => g.idGrupoVulnerableCatalogo != null)
        .length;
    if (conId == 0) return;
    await store.guardarFilas(uuid, ['proteccion'], localidad);
  }
}
