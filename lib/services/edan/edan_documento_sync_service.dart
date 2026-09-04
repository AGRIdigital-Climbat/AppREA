import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/edan.dart';
import '../api_service.dart';
import '../database_helper.dart';
import '../edan_secciones_registry.dart';
import '../sync_debug_collector.dart';
import '../sync_debug_config.dart';
import 'edan_documento_service.dart';
import 'edan_localidades_envio_v2_service.dart';

/// Orquestador de sincronización EDAN "todo-en-uno" (grupo v2, `/documento`).
///
/// Reemplaza el envío por secciones (cabecera + POST por sección + DELETE) por
/// el contrato simétrico del backend:
///   1. Subir el carrete de fotos primero (`foto/subir`) → paths servidos.
///   2. Construir el documento compacto (solo secciones con datos / flag true).
///   3. `POST /localidades/documento` (crea/upsert por `id_local`) o
///      `PUT /localidades/{id}/documento` (actualiza, nunca crea).
///   4. Persistir `id_edan_localidad`, marcar todo sincronizado.
///
/// El persistir a SQLite (tablas normalizadas por sección) lo hace el wizard a
/// través de [EdanLocalidadesEnvioV2Service.guardarSecciones]; aquí solo se
/// serializa (el JSON nace de SQLite/modelo) y se envía el documento.
class EdanDocumentoSyncService {
  EdanDocumentoSyncService({ApiService? api, DatabaseHelper? db})
      : _api = api ?? ApiService.instance,
        _db = db ?? DatabaseHelper.instance;

  final ApiService _api;
  final DatabaseHelper _db;

  /// Punto de entrada: sube el carrete y envía el documento todo-en-uno.
  ///
  /// Devuelve `true` si el documento se envió correctamente (POST o PUT) y se
  /// conocen su `id_edan_localidad`. No gestiona el GET/pull (eso lo hace el
  /// flujo de sincronización central); solo sube cambios locales.
  ///
  /// Si [skipFotos] es `true`, omite la subida de fotos (útil cuando ya se
  /// subieron en una fase anterior de la sincronización).
  Future<bool> enviarLocalidadDocumento(EdanLocalidad localidad, {bool skipFotos = false}) async {
    final idLocal = localidad.idLocal;
    if (idLocal == null || idLocal.isEmpty) {
      debugPrint('[DocSync] Localidad sin id_local: ${localidad.nombre}');
      return false;
    }

    // 1. Intentar subir fotos primero. Si falla, se envía igual el EDAN.
    var fotosSubidas = false;
    if (!skipFotos) {
      // Asegurar que el debug visual registre esta sesión y la fase de fotos:
      // el "longpress"/Enviar no pasa por el startSession del sync central, y
      // así el upload de fotos queda visible al inicio del envío.
      if (kSyncDebugMode && !SyncDebugCollector.instance.isActive) {
        SyncDebugCollector.instance.startSession();
      }
      SyncDebugCollector.instance.addFase('Subir fotos');
      try {
        await _subirFotosCarrete(localidad);
        fotosSubidas = true;
      } catch (e) {
        debugPrint('[DocSync] Error subiendo fotos, se envía EDAN sin fotos: $e');
      }
    }

    // 2. Cargar secciones desde tablas normalizadas para que
    //    recalcularFlagsImpacto() tenga los datos reales.
    final sincV2 = EdanLocalidadesEnvioV2Service();
    await sincV2.cargarSeccionesDesdeSQLite(localidad);

    // 3. Construir el documento compacto (secciones activas → flags).
    final documento =
        await EdanDocumentoService.instance.construirDocumento(localidad);

    // 3. PUT si ya existe en servidor (idServer válido); POST si es nueva.
    //    PUT usa id_local (UUID) en el path — el backend lo resuelve.
    Map<String, dynamic> resp;
    final tieneIdServer = localidad.idServer != null && localidad.idServer! > 0;
    if (tieneIdServer) {
      resp = await _api.actualizarDocumento(idLocal, documento);
    } else {
      resp = await _api.crearDocumento(documento);
    }

    // El servidor puede devolver el documento igual pero con un bloque
    // `_errores` indicando que rechazó ciertas secciones (p. ej. violación
    // de unicidad en una 1:1). Si hay errores, NO marcar el envío como OK:
    // se reporta fallido para que quede visible y se pueda corregir.
    final errores = _erroresServidor(resp);
    if (errores.isNotEmpty) {
      debugPrint('[DocSync] El servidor reportó errores (${errores.length}): '
          '$errores');
      SyncDebugCollector.instance.addDiagnostico(
        'Errores del servidor en ${tieneIdServer ? "PUT" : "POST"} documento',
        {'_errores': errores},
      );
      return false;
    }

    // 4. Persistir referencias del servidor.
    final idEdan = _intId(resp['id_edan_localidad']);
    if (idEdan != null) localidad.idServer = idEdan;
    final fecha = resp['fecha_modificacion'];
    if (fecha is String && fecha.isNotEmpty) {
      localidad.fechaModificacion = fecha;
    }
    await _db.updateLocalidad(localidad);

    // 5. Si las fotos no se subieron antes, reintentarlas y corregir el
    //    documento en el servidor con los paths reales.
    if (!skipFotos && !fotosSubidas && localidad.idServer != null && localidad.idServer! > 0) {
      try {
        await _subirFotosCarrete(localidad);
        final recargada = await _db.getLocalidadByIdLocal(idLocal);
        if (recargada != null) {
          final docCorregido = await EdanDocumentoService.instance
              .construirDocumento(recargada);
          await _api.actualizarDocumento(idLocal, docCorregido);
          debugPrint('[DocSync] Documento corregido con fotos post-PUT');
        }
      } catch (e) {
        debugPrint('[DocSync] Error corrigiendo fotos post-PUT: $e');
      }
    }

    return true;
  }

  /// Procesa la cola de deletes offline (`pendientes_eliminar`).
  /// Se ejecuta ANTES de cualquier otro paso de sync para asegurar que los
  /// deletes se procesen con prioridad alta.
  ///
  /// Nunca lanza: ante cualquier fallo aislado de la cola, se registra y se
  /// continúa, para no abortar el push del documento completo.
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

      // DELETE al servidor solo si la fila estaba sync
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

      // Borrar localmente la fila de sección (si aún existe)
      if (tablaSqlite.isNotEmpty) {
        try {
          await _db.eliminarFilaSeccion(tablaSqlite, idSeccion);
        } catch (_) {}
      }

      // Marcar como sincronizado y eliminar de la cola
      await _db.marcarPendienteEliminadoSincronizado(id);
      await _db.eliminarPendienteEliminar(id);
    }
  }

  /// Elimina filas marcadas con `marcado_borrar=1` en el servidor y localmente.
  ///
  /// Solo actúa sobre filas que el usuario borró localmente.
  /// - Si `insertada_en_server=1` → DELETE al backend (el server las tenía).
  /// - Si `insertada_en_server=0` → solo borrado local (nunca llegó al server).
  ///
  /// Se llama ANTES de `enviarLocalidadDocumento` para que el documento
  /// resultante solo contenga las filas que realmente existen en SQLite.
  Future<void> eliminarFilasAntesDelPush(EdanLocalidad localidad) async {
    final idLocal = localidad.idLocal;
    if (idLocal == null || idLocal.isEmpty) return;

    final idServer = localidad.idServer;

    for (final desc in EdanSeccionesRegistry.secciones) {
      if (desc.tipo != EdanSeccionTipo.unoAN) continue; // solo 1:N tienen filas
      final tabla = desc.tablaSqlite;

      try {
        final filasBorradas = await _db.leerFilasBorradas(tabla, idLocal);
        if (filasBorradas.isEmpty) continue;

        for (final fila in filasBorradas) {
          final idSeccion = fila['id_seccion']?.toString();
          if (idSeccion == null || idSeccion.isEmpty) continue;

          final insertadaEnServer = fila['insertada_en_server'] == 1;

          if (insertadaEnServer && idServer != null) {
            // Filas que SÍ estaban en el server → DELETE al backend.
            // Un 404 (item ya no existe) se considera borrado OK.
            final res = await _api.deleteSeccionItem(
              idLocalidad: '$idServer',
              rutaSeccion: desc.rutaV2,
              idSeccion: idSeccion,
            );
            if (res.success || res.notFound) {
              debugPrint('[DocSync] DELETE server $idSeccion '
                  '(${desc.rutaV2}) → ${res.success ? 'OK' : '404'}');
            } else {
              debugPrint('[DocSync] DELETE falló $idSeccion '
                  '(${desc.rutaV2}): ${res.detalle}');
            }
          }

          // Siempre borrar localmente
          await _db.eliminarFilaSeccion(tabla, idSeccion);
        }
      } catch (e) {
        debugPrint('[DocSync] Error eliminando filas marcadas en $tabla: $e');
      }
    }
  }

  /// Elimina físicamente la localidad completa en el servidor usando el
  /// contrato todo-en-uno (DELETE `/localidades/{id}/documento`).
  ///
  /// [referencia] es `id_edan_localidad` (int) o `id_local` (UUID), ambos
  /// aceptados por el backend.
  ///
  /// Devuelve:
  ///   - `true`  si se eliminó correctamente.
  ///   - `false` si la localidad está consolidada en un EDAN (no es huérfana)
  ///     → 403; el móvil NO debe borrar la fila local.
  ///
  /// Lanza si es un error distinto a la regla de negocio 403.
  Future<bool> eliminarLocalidadDocumento(Object referencia) async {
    try {
      final resp = await _api.eliminarLocalidadDocumento(referencia);
      return resp['message'] != null || resp.isNotEmpty;
    } on LocalidadConsolidadaException {
      debugPrint('Localidad consolidada en EDAN, no se elimina la fila local: '
          '$referencia');
      return false;
    }
  }

  /// Trae TODOS los reportes del usuario en una sola llamada
  /// (`GET /localidades/mis-reportes?modo=comprimido`).
  ///
  /// Cada ítem es un documento compacto (cabecera + flags `imp_*` + solo
  /// secciones con datos), idéntico al shape que produce `construirDocumento`.
  /// Se parsea con [EdanDocumentoService.parsearDocumento] y se devuelve la
  /// lista de localidades con su `fecha_modificacion` para aplicar LWW.
  Future<List<EdanLocalidad>> listarMisReportes({
    required int idUsuario,
    bool? soloHuerfanas,
    int skip = 0,
    int limit = 1000,
  }) async {
    final raw = await _api.getLocalidadesMisReportes(
      idUsuario: idUsuario,
      soloHuerfanas: soloHuerfanas,
      skip: skip,
      limit: limit,
      modoComprimido: true,
    );
    final listas = <EdanLocalidad>[];
    for (final item in raw) {
      try {
        final local =
            EdanDocumentoService.parsearDocumento(item);
        listas.add(local);
      } catch (e) {
        debugPrint('[DocSync] Error parseando mis-reportes: $e');
      }
    }
    return listas;
  }

  /// Sube el carrete de fotos pendientes de TODAS las secciones con foto de la
  /// localidad, leyendo la cola unificada `foto_pendiente_v2` (la misma que usa
  /// la sincronización RESP). Así no hay doble fuente de fotos ni re-subidas.
  Future<void> _subirFotosCarrete(EdanLocalidad localidad) async {
    final db = DatabaseHelper.instance;
    final idLocal = localidad.idLocal;
    if (idLocal == null) return;

    final pendientes = await db.leerFotosPendientesUploadV2();
    final fotos = pendientes.where((f) => f['id_local'] == idLocal).toList();
    if (fotos.isEmpty) return;

    for (final fotoRow in fotos) {
      final idFoto = fotoRow['id_foto']?.toString() ?? '';
      final ruta = fotoRow['ruta_local_archivo']?.toString();
      final idSeccion = fotoRow['id_seccion']?.toString() ?? '';
      if (ruta == null || ruta.isEmpty || idSeccion.isEmpty) continue;

      final file = File(ruta);
      if (!await file.exists()) {
        if (idFoto.isNotEmpty) await db.marcarFotoErrorV2(idFoto, 'Archivo no encontrado');
        continue;
      }

      try {
        final paths = await ApiService.instance.subirFotosCarrete(
          files: [ruta],
          idSecciones: [idSeccion],
          idLocal: idLocal,
          idEdanLocalidad: localidad.idServer ?? localidad.idEdan,
        );
        final path = paths[idSeccion];
        if (path == null || path.isEmpty) {
          if (idFoto.isNotEmpty) await db.marcarFotoErrorV2(idFoto, 'Server no devolvió path');
          continue;
        }
        if (idFoto.isNotEmpty) await db.marcarFotoSubidaV2(idFoto, path);
        final tabla = await EdanSeccionesRegistry.buscarTablaPorIdSeccion(idSeccion, db);
        if (tabla.isNotEmpty) {
          await db.marcarFotografiaSeccion(tabla, idLocal, idSeccion, path);
        }
        debugPrint('[DocSync] carrete OK: $idSeccion → $path');
      } catch (e) {
        if (idFoto.isNotEmpty) await db.marcarFotoErrorV2(idFoto, e.toString());
        debugPrint('[DocSync] Error carrete $idSeccion: $e');
      }
    }
  }

  int? _intId(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  /// Extrae los errores que el servidor devuelve en el bloque `_errores` de la
  /// respuesta del PUT/POST del documento. Devuelve una lista legible; vacía si
  /// no hubo errores.
  static List<String> _erroresServidor(Map<String, dynamic> resp) {
    final raw = resp['_errores'];
    if (raw is! List || raw.isEmpty) return const [];
    final out = <String>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final seccion = e['seccion']?.toString() ?? '';
      final detail = e['detail']?.toString() ?? '';
      out.add(seccion.isNotEmpty ? '$seccion: $detail' : detail);
    }
    return out;
  }
}