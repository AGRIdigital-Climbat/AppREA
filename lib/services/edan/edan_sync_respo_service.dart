import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/edan.dart';
import '../api_service.dart';
import '../auth_service.dart';
import '../database_helper.dart';
import 'edan_documento_sync_service.dart';
import 'edan_localidades_envio_v2_service.dart';
import '../edan_secciones_registry.dart';
import '../sync_debug_config.dart';
import '../sync_debug_collector.dart';

/// Servicio de sincronización unificado para localidades EDAN (rol 7 RESP).
///
/// Reemplaza `LocalidadSyncService` con un flujo de 3 fases más robusto:
///   FASE 1: Subir fotos pendientes (upload)
///   FASE 2: Push datos (DELETE → UPDATE → CREATE)
///   FASE 3: Pull del server (LWW comparison)
///
/// Puntos clave:
///   - `getLocalidades()` filtra `pendiente_eliminacion=0` → nunca sube lo que se va a borrar
///   - DELETE se ejecuta ANTES del push → no hay carrera
///   - Fotos se suben ANTES del push → paths disponibles en el JSON
///   - `kSyncDebugMode` controla el panel de debug visual
class EdanSyncRespoService {
  EdanSyncRespoService._();
  static final EdanSyncRespoService instance = EdanSyncRespoService._();

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  final ValueNotifier<int> pendientes = ValueNotifier(0);
  final ValueNotifier<bool> sincronizando = ValueNotifier(false);
  final ValueNotifier<bool> sincronizandoMunicipio = ValueNotifier(false);

  // =====================================================================
  //  SINCRONIZACIÓN PRINCIPAL — 3 fases
  // =====================================================================

  Future<SyncResult> sincronizar() async {
    if (_isSyncing) {
      return SyncResult(exito: false, mensaje: 'Ya hay una sincronización en curso');
    }

    _isSyncing = true;
    sincronizando.value = true;
    if (kSyncDebugMode) SyncDebugCollector.instance.startSession();

    final result = SyncResult(exito: true, mensaje: 'Sin cambios');
    try {
      final userId = AuthService.instance.userId;
      if (userId == null) {
        return SyncResult(exito: false, mensaje: 'Usuario no autenticado');
      }

      final db = DatabaseHelper.instance;

      // ===== Diagnóstico local =====
      final locales = await db.getLocalidades(userId);
      final pendientesDelete = await db.getLocalidadesPendingDeletion();
      debugPrint('[SyncC] Diagnóstico: ${locales.length} total, '
          '${pendientesDelete.length} para delete');
      if (kSyncDebugMode) {
        SyncDebugCollector.instance.addFase('Diagnóstico local');
        final fotosLocal = await _fotosLocalesPendientes(db, locales);
        SyncDebugCollector.instance.addDiagnostico(
          'Estado local antes de sincronizar',
          {
            'total_localidades': locales.length,
            'pendientes_delete': pendientesDelete.length,
            'fotos_pendientes': fotosLocal,
          },
        );
      }

      // ===== FASE 1: FOTOS (upload) =====
      // Subir fotos pendientes ANTES del push para que el path del server
      // esté disponible en el JSON del documento.
      if (kSyncDebugMode) SyncDebugCollector.instance.addFase('Fase 1: Fotos');
      await _subirFotosPendientes(locales, result);

      // ===== FASE 2: DATOS (push) =====
      // DELETE primero → luego UPDATE/CREATE.
      if (kSyncDebugMode) SyncDebugCollector.instance.addFase('Fase 2: Datos');
      await _eliminarPendientes(result);
      await _subirSucios(locales, result);

      // ===== FASE 3: PULL (GET) =====
      // Comparar timestamps y traer lo que el server tiene más nuevo.
      if (kSyncDebugMode) SyncDebugCollector.instance.addFase('Fase 3: Pull');
      await _pullDatos(result);

      // ===== Download fotos del server =====
      if (kSyncDebugMode) SyncDebugCollector.instance.addFase('Fase 3b: Download Fotos');
      await _descargarFotosPendientes();

      // ===== Resumen global (contadores visibles en el debug) =====
      if (kSyncDebugMode) {
        SyncDebugCollector.instance.addFase('Resumen sincronización');
        SyncDebugCollector.instance.addDiagnostico(
          'Contadores finales',
          {
            'creados': result.creados,
            'actualizados': result.actualizados,
            'enviados': result.enviados,
            'eliminados': result.eliminados,
            'fallidos': result.fallidos,
            'fotos_pendientes': result.fotosPendientes,
            'fotos_subidas': result.fotosSubidas,
            'fotos_fallidas': result.fotosFallidas,
          },
        );
      }

      return result;
    } catch (e, st) {
      debugPrint('[SyncC] Error general: $e');
      debugPrint('[SyncC] Stack: $st');
      return SyncResult(exito: false, mensaje: 'Error: $e');
    } finally {
      _isSyncing = false;
      sincronizando.value = false;
      if (kSyncDebugMode) SyncDebugCollector.instance.endSession();
      await recargarPendientes();
    }
  }

  /// Devuelve un resumen de las fotos locales pendientes de subir, para el
  /// "Diagnóstico local" del debug visual. Cuenta tanto las filas de la cola
  /// [`foto_pendiente_v2`] (subida=0) como las fotos de las tablas de sección
  /// cuyo path sigue siendo local (`/data/`), agrupadas por localidad.
  Future<Map<String, dynamic>> _fotosLocalesPendientes(
    DatabaseHelper db,
    List<EdanLocalidad> locales,
  ) async {
    final porLocalidad = <String, int>{};
    var total = 0;

    try {
      final pendientesV2 = await db.leerFotosPendientesUploadV2();
      for (final f in pendientesV2) {
        final idLocal = f['id_local']?.toString();
        if (idLocal == null || idLocal.isEmpty) continue;
        porLocalidad[idLocal] = (porLocalidad[idLocal] ?? 0) + 1;
        total++;
      }
    } catch (e) {
      debugPrint('[SyncC] Diagnóstico fotos v2 error: $e');
    }

    for (final local in locales) {
      final idLocal = local.idLocal;
      if (idLocal == null) continue;
      for (final desc in EdanSeccionesRegistry.secciones.where((s) => s.usaFoto)) {
        try {
          final filas = await db.leerFilasSeccion(desc.tablaSqlite, idLocal);
          for (final fila in filas) {
            final fotografia = fila['fotografia']?.toString();
            if (fotografia == null || fotografia.isEmpty) continue;
            if (!fotografia.startsWith('/data/')) continue;
            porLocalidad[idLocal] = (porLocalidad[idLocal] ?? 0) + 1;
            total++;
          }
        } catch (_) {
          // tabla o fila no disponible: se omite
        }
      }
    }

    return {
      'total': total,
      'por_localidad': porLocalidad,
    };
  }

  // =====================================================================
  //  FASE 1: SUBIR FOTOS PENDIENTES
  // =====================================================================

  Future<void> _subirFotosPendientes(List<EdanLocalidad> locales, SyncResult result) async {
    final db = DatabaseHelper.instance;
    int subidas = 0;
    int fallidas = 0;
    int pendientes = 0;

    for (final local in locales) {
      final idLocal = local.idLocal;
      if (idLocal == null) continue;

      // 1) Buscar en foto_pendiente_v2
      final pendientesV2 = await db.leerFotosPendientesUploadV2();
      final fotosLocal = pendientesV2.where((f) => f['id_local'] == idLocal).toList();

      // 2) Fallback: buscar en tablas de secciones donde fotografia empiece con /data/
      if (fotosLocal.isEmpty) {
        for (final desc in EdanSeccionesRegistry.secciones.where((s) => s.usaFoto)) {
          try {
            final filas = await db.leerFilasSeccion(desc.tablaSqlite, idLocal);
            for (final fila in filas) {
              final fotografia = fila['fotografia']?.toString();
              final idSeccion = fila['id_seccion']?.toString();
              if (fotografia == null || fotografia.isEmpty) continue;
              if (idSeccion == null || idSeccion.isEmpty) continue;
              if (!fotografia.startsWith('/data/')) continue;
              // Esta fila tiene un path local sin subir — registrar en foto_pendiente_v2.
              // El id_foto devuelto se usa para marcar la subida (subida=1) y así
              // evitar que el mismo archivo se vuelva a subir en el próximo ciclo.
              final idFotoNuevo = await db.insertarFotoPendienteV2(
                idLocal: idLocal,
                idSeccion: idSeccion,
                rutaLocalArchivo: fotografia,
              );
              fotosLocal.add({
                'id_foto': idFotoNuevo,
                'id_local': idLocal,
                'id_seccion': idSeccion,
                'ruta_local_archivo': fotografia,
              });
            }
          } catch (e) {
            debugPrint('[SyncC] Fallback fotos error ${desc.rutaV2}: $e');
          }
        }
      }

      pendientes += fotosLocal.length;
      if (fotosLocal.isEmpty) continue;
      debugPrint('[SyncC] Fase 1: ${fotosLocal.length} fotos para $idLocal');

      for (final fotoRow in fotosLocal) {
        final idFoto = fotoRow['id_foto']?.toString() ?? '';
        final ruta = fotoRow['ruta_local_archivo']?.toString();
        final idSeccion = fotoRow['id_seccion']?.toString() ?? '';

        if (ruta == null || ruta.isEmpty) {
          if (idFoto.isNotEmpty) await db.marcarFotoErrorV2(idFoto, 'Ruta vacía');
          fallidas++;
          continue;
        }

        final file = File(ruta);
        if (!await file.exists()) {
          if (idFoto.isNotEmpty) await db.marcarFotoErrorV2(idFoto, 'Archivo no encontrado');
          fallidas++;
          continue;
        }

        try {
          final paths = await ApiService.instance.subirFotosCarrete(
            files: [ruta],
            idSecciones: [idSeccion],
            idLocal: idLocal,
            idEdanLocalidad: local.idServer ?? local.idEdan,
          );

          final path = paths[idSeccion];
          if (path != null && path.isNotEmpty) {
            if (idFoto.isNotEmpty) await db.marcarFotoSubidaV2(idFoto, path);
            // Actualizar la sección en SQLite con el path del server
            final tabla = await _tablaPorSeccion(idSeccion);
            if (tabla.isNotEmpty) {
              await db.marcarFotografiaSeccion(
                tabla,
                idLocal,
                idSeccion,
                path,
              );
            }
            // Actualizar el modelo en memoria para que el documento que se arme
            // en Fase 2b use el path del server (no el /data/ local), incluso si
            // la búsqueda de tabla falló o la fila cambió.
            _actualizarFotoModelo(local, idSeccion, path);
            subidas++;
            debugPrint('[SyncC]   Foto OK: $idSeccion → $path');
          } else {
            if (idFoto.isNotEmpty) await db.marcarFotoErrorV2(idFoto, 'Server no devolvió path');
            fallidas++;
          }
        } catch (e) {
          if (idFoto.isNotEmpty) await db.marcarFotoErrorV2(idFoto, e.toString());
          fallidas++;
          debugPrint('[SyncC]   Foto FALLO: $idSeccion → $e');
        }
      }
    }

    result.fotosPendientes = pendientes;
    result.fotosSubidas = subidas;
    result.fotosFallidas = fallidas;
    debugPrint('[SyncC] Fase 1 completada: $subidas subidas, $fallidas fallidas, $pendientes pendientes');
    if (kSyncDebugMode) {
      SyncDebugCollector.instance.addDiagnostico(
        'Resultado Fase 1: Fotos',
        {'pendientes': pendientes, 'subidas': subidas, 'fallidas': fallidas},
      );
    }
  }

  Future<String> _tablaPorSeccion(String idSeccion) {
    return EdanSeccionesRegistry.buscarTablaPorIdSeccion(
      idSeccion,
      DatabaseHelper.instance,
    );
  }

  /// Actualiza el campo `fotografia` del ítem del modelo (en memoria) cuyo
  /// `id_seccion` coincide, reemplazando el path local `/data/` por el path del
  /// servidor. Así el documento que se construye en Fase 2b serializa la ruta
  /// servida, no la local.
  void _actualizarFotoModelo(EdanLocalidad local, String idSeccion, String path) {
    for (final item in _itemsConFoto(local)) {
      if (idSeccionDe(item) == idSeccion) {
        _setFotografiaItem(item, path);
        return;
      }
    }
  }

  List<Object> _itemsConFoto(EdanLocalidad local) => [
        ...local.establecimientosSalud,
        ...local.danosViales,
        ...local.danosInfraPublica,
        ...local.serviciosBasicos,
        ...local.unidadesEducativas,
        ...local.danosVivienda,
        ...local.danosAgricultura,
        ...local.danosPecuarios,
        ...local.infraProductiva,
      ];

  void _setFotografiaItem(Object item, String path) {
    if (item is EdanEstablecimientoSalud) { item.fotografia = path; return; }
    if (item is EdanDanoVial) { item.fotografia = path; return; }
    if (item is EdanDanoInfraPublica) { item.fotografia = path; return; }
    if (item is EdanServicioBasicoDetalle) { item.fotografia = path; return; }
    if (item is EdanDanoUnidadEducativa) { item.fotografia = path; return; }
    if (item is EdanDanoVivienda) { item.fotografia = path; return; }
    if (item is EdanDanoAgricultura) { item.fotografia = path; return; }
    if (item is EdanDanoPecuario) { item.fotografia = path; return; }
    if (item is EdanInfraProductiva) { item.fotografia = path; return; }
  }

  // =====================================================================
  //  FASE 2a: ELIMINAR LOCALIDADES PENDIENTES
  // =====================================================================

  Future<void> _eliminarPendientes(SyncResult result) async {
    final db = DatabaseHelper.instance;
    if (kSyncDebugMode) {
      SyncDebugCollector.instance.addFase('Fase 2a: Eliminar localidades');
    }
    final pendientes = await db.getLocalidadesPendingDeletion();
    if (pendientes.isEmpty) {
      debugPrint('[SyncC] Fase 2a: No hay localidades para eliminar');
      if (kSyncDebugMode) {
        SyncDebugCollector.instance.addDiagnostico(
          'Fase 2a: Sin localidades pendientes',
          {'total': 0},
        );
      }
      return;
    }

    debugPrint('[SyncC] Fase 2a: Eliminando ${pendientes.length} localidades');
    int eliminadas = 0;
    int conservadas = 0;
    int errores = 0;

    for (final loc in pendientes) {
      final idLocal = loc.idLocal;
      final idServer = loc.idServer;
      if (idLocal == null) continue;

      try {
        if (idServer != null) {
          // Tiene idServer → DELETE al backend
          final ok = await EdanDocumentoSyncService().eliminarLocalidadDocumento(idServer);
          if (!ok) {
            // 403: consolidada en EDAN → no borrar local
            conservadas++;
            debugPrint('[SyncC]   DELETE $idLocal → consolidada (403), se conserva');
            if (kSyncDebugMode) {
              SyncDebugCollector.instance.add(SyncApiEntry(
                fase: SyncDebugCollector.instance.currentPhase,
                metodo: 'DELETE',
                endpoint: '$idServer/documento (403 consolidada)',
                localidadId: idLocal,
                error: 'Localidad consolidada en EDAN, no se borra local',
              ));
            }
            continue;
          }
        }
        // Borrar local
        await db.deleteLocalidad(idLocal);
        eliminadas++;
        result.eliminados++;
        debugPrint('[SyncC]   DELETE $idLocal → OK');
      } catch (e) {
        errores++;
        debugPrint('[SyncC]   DELETE $idLocal → ERROR: $e');
        result.fallidos++;
        if (kSyncDebugMode) {
          SyncDebugCollector.instance.add(SyncApiEntry(
            fase: SyncDebugCollector.instance.currentPhase,
            metodo: 'DELETE',
            endpoint: 'error-localidad-pendiente',
            localidadId: idLocal,
            error: e.toString(),
          ));
        }
      }
    }
    if (kSyncDebugMode) {
      SyncDebugCollector.instance.addDiagnostico(
        'Fase 2a: Resultado',
        {
          'total_pendientes': pendientes.length,
          'eliminadas': eliminadas,
          'conservadas_403': conservadas,
          'errores': errores,
        },
      );
    }
  }

  // =====================================================================
  //  FASE 2b: SUBIR LOCALIDADES SUCIAS
  // =====================================================================

  Future<void> _subirSucios(List<EdanLocalidad> locales, SyncResult result) async {
    final db = DatabaseHelper.instance;
    final sincV2 = EdanLocalidadesEnvioV2Service(db: db);
    final docSync = EdanDocumentoSyncService();

    int enviados = 0;
    int fallidos = 0;

    for (final local in locales) {
      final idLocal = local.idLocal;
      if (idLocal == null) continue;

      // Verificar si necesita push
      final modificadas = await db.getSeccionesModificadas(idLocal);
      final needPush = !local.sincronizado || local.editado || modificadas.isNotEmpty;
      if (!needPush) continue;

      debugPrint('[SyncC] Fase 2b: Push $idLocal (${local.nombre})');
      if (kSyncDebugMode) {
        SyncDebugCollector.instance.setPhase('Fase 2b: PUSH $idLocal');
      }

      try {
        // Cargar secciones desde SQLite al modelo
        await sincV2.cargarSeccionesDesdeSQLite(local);
        // PRIORIDAD: procesar cola de deletes offline PRIMERO
        await docSync.procesarColaDeletes();
        // Eliminar filas marcadas con marcado_borrar=1
        await docSync.eliminarFilasAntesDelPush(local);

        // Enviar documento completo
        final ok = await docSync.enviarLocalidadDocumento(local, skipFotos: true);

        if (ok) {
          final idEdan = local.idServer;
          if (idEdan != null) {
            await db.markLocalidadAsSyncedConFecha(
              idLocal,
              idEdan,
              local.fechaModificacion ?? DateTime.now().toIso8601String(),
            );
          } else {
            await db.markLocalidadAsSynced(idLocal, 0);
          }
          await db.sincronizarFlagEditadoCabecera(idLocal);
          final mods = await db.getSeccionesModificadas(idLocal);
          await db.clearSeccionesModificadas(idLocal, mods.toSet());
          enviados++;
          debugPrint('[SyncC]   PUSH $idLocal → OK (idServer=$idEdan)');
        } else {
          fallidos++;
          debugPrint('[SyncC]   PUSH $idLocal → FALLÓ');
          if (kSyncDebugMode) {
            SyncDebugCollector.instance.add(SyncApiEntry(
              fase: SyncDebugCollector.instance.currentPhase,
              metodo: 'PUSH',
              endpoint: '${local.nombre} — enviarLocalidadDocumento=false',
              localidadId: idLocal,
              error: 'enviar documento devolvió false (id_local vacío?)',
            ));
          }
        }
      } catch (e) {
        fallidos++;
        debugPrint('[SyncC]   PUSH $idLocal → ERROR: $e');
        if (kSyncDebugMode) {
          SyncDebugCollector.instance.add(SyncApiEntry(
            fase: SyncDebugCollector.instance.currentPhase,
            metodo: 'PUSH',
            endpoint: '${local.nombre} — error no-API',
            localidadId: idLocal,
            error: e.toString(),
          ));
        }
      }
    }

    result.enviados = enviados;
    result.fallidos += fallidos;
    debugPrint('[SyncC] Fase 2b completada: $enviados enviados, $fallidos fallidos');
    if (kSyncDebugMode) {
      SyncDebugCollector.instance.addDiagnostico(
        'Resultado Fase 2: Datos',
        {'enviados': enviados, 'fallidos': fallidos},
      );
    }
  }

  // =====================================================================
  //  FASE 3: PULL (LWW comparison)
  // =====================================================================

  Future<void> _pullDatos(SyncResult result) async {
    final db = DatabaseHelper.instance;
    final api = ApiService.instance;
    final sincV2 = EdanLocalidadesEnvioV2Service(db: db);
    final srv = _EstadosServidor();

    // GET lightweight states
    final userId = AuthService.instance.userId;
    if (userId == null) return;

    try {
      final estados = await api.getLocalidadesMisEstados(
        idUsuario: userId,
        limit: 1000,
      );
      srv.cargar(estados);
    } catch (e) {
      debugPrint('[SyncC] Fase 3: Error getting states: $e');
      return;
    }

    // Para cada localidad local: comparar con server
    final locales = await db.getLocalidades(userId);
    int creados = 0;
    int actualizados = 0;

    for (final local in locales) {
      final idLocal = local.idLocal;
      if (idLocal == null) continue;

      final serverItem = srv.porIdLocal(idLocal);
      if (serverItem == null) continue;

      // Server marca eliminación → borrar local
      if (serverItem.pendienteEliminacion && local.sincronizado) {
        await db.deleteLocalidad(idLocal);
        result.eliminados++;
        debugPrint('[SyncC]   PULL delete $idLocal (server marked)');
        continue;
      }

      // LWW: server más nuevo?
      final serverFecha = serverItem.fechaModificacion;
      final localFecha = local.fechaModificacion;
      if (!_esMasNueva(serverFecha, localFecha)) continue;

      // No tirar si local tiene cambios sin push
      final modificadas = await db.getSeccionesModificadas(idLocal);
      if (local.editado || !local.sincronizado || modificadas.isNotEmpty) {
        debugPrint('[SyncC]   SKIP PULL $idLocal (local dirty)');
        continue;
      }

      // PULL: traer documento completo
      final idEdan = serverItem.idEdan;
      if (idEdan == null) continue;

      try {
        final doc = await api.obtenerDocumento('$idEdan');

        final serverLoc = EdanLocalidad.fromJson(doc);
        _preservarEncabezado(serverLoc, local);
        _mergeSecciones(local, serverLoc);
        serverLoc.idLocal = idLocal;
        // Persistencia limpia: deduplicar por id_seccion ANTES de escribir
        // datos_json, para que el blob en disco nunca acumule duplicados
        // que `_localidadFromRow` luego vuelva a propagar.
        serverLoc.deduplicarSecciones();

        await db.reemplazarLocalidadDesdeServer(serverLoc);
        await sincV2.popularSeccionesDesdeServer(serverLoc);
        actualizados++;
        debugPrint('[SyncC]   PULL $idLocal → OK (server más nuevo)');
      } catch (e) {
        debugPrint('[SyncC]   PULL $idLocal → ERROR: $e');
      }
    }

    // Server items sin match local → INSERT
    for (final item in srv.lista) {
      if (item.pendienteEliminacion) continue;
      if (item.idEdan == null) continue;

      final existe = locales.any((l) =>
          l.idLocal == item.idLocal ||
          (l.idServer != null && l.idServer == item.idEdan));
      if (existe) continue;

      try {
        final doc = await api.obtenerDocumento('${item.idEdan!}');

        final nueva = EdanLocalidad.fromJson(doc);
        final idLocal = nueva.idLocal ?? 'pull-${DateTime.now().millisecondsSinceEpoch}';
        nueva.idLocal = idLocal;
        nueva.idUsuario = userId;
        nueva.deduplicarSecciones();

        await db.insertLocalidad(nueva, usuarioId: userId);
        await db.markLocalidadAsSynced(idLocal, item.idEdan!);
        await sincV2.popularSeccionesDesdeServer(nueva);
        creados++;
        debugPrint('[SyncC]   INSERT $idLocal (new from server)');
      } catch (e) {
        debugPrint('[SyncC]   INSERT error: $e');
      }
    }

    result.creados = creados;
    result.actualizados = actualizados;
    debugPrint('[SyncC] Fase 3 completada: $creados creados, $actualizados actualizados');
    if (kSyncDebugMode) {
      SyncDebugCollector.instance.addDiagnostico(
        'Resultado Fase 3: Pull',
        {'creados': creados, 'actualizados': actualizados},
      );
    }
  }

  // =====================================================================
  //  DOWNLOAD FOTOS DEL SERVER
  // =====================================================================

  Future<void> _descargarFotosPendientes() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fotosDir = Directory('${appDir.path}/edan_fotos');
      await fotosDir.create(recursive: true);

      final pendientes = await DatabaseHelper.instance.leerFotosPendientesDownloadV2();
      if (pendientes.isEmpty) {
        debugPrint('[FotosEDAN] No hay fotos pendientes de descarga');
        return;
      }
      debugPrint('[FotosEDAN] ${pendientes.length} fotos pendientes de descarga');

      int descargadas = 0;
      int fallidas = 0;

      for (final fotoRow in pendientes) {
        final serverPath = fotoRow['path_servidor']?.toString();
        final idFoto = fotoRow['id_foto']?.toString();
        if (serverPath == null || idFoto == null) continue;
        if (!serverPath.startsWith('/uploads/')) continue;

        final fileName = serverPath.replaceAll('/', '_');
        final savePath = '${fotosDir.path}/$fileName';

        if (await File(savePath).exists()) {
          await DatabaseHelper.instance.marcarFotoDescargadaV2(idFoto, savePath);
          continue;
        }

        final result = await ApiService.instance.downloadImage(serverPath, savePath);
        if (result != null) {
          await DatabaseHelper.instance.marcarFotoDescargadaV2(idFoto, savePath);
          descargadas++;
        } else {
          await DatabaseHelper.instance.marcarFotoErrorV2(idFoto, 'Error descargando $serverPath');
          fallidas++;
        }
      }

      debugPrint('[FotosEDAN] Fin: $descargadas descargadas, $fallidas fallidas');
    } catch (e) {
      debugPrint('[FotosEDAN] Error: $e');
    }
  }

  // =====================================================================
  //  ELIMINAR LOCALIDAD
  // =====================================================================

  Future<void> eliminarLocalidad(String idLocal) async {
    final db = DatabaseHelper.instance;
    final local = await db.getLocalidadByIdLocal(idLocal);

    if (local == null) {
      debugPrint('[SyncC] eliminarLocalidad: $idLocal no encontrada');
      return;
    }

    if (local.idServer == null) {
      // Sin idServer → borrado directo local
      await db.deleteLocalidad(idLocal);
      debugPrint('[SyncC] eliminarLocalidad: $idLocal borrada localmente (sin server)');
    } else {
      // Con idServer → marcar para delete en próximo sync
      await db.markLocalidadAsPendingDeletion(idLocal);
      debugPrint('[SyncC] eliminarLocalidad: $idLocal marcada para delete (server)');
    }
    await recargarPendientes();
  }

  // =====================================================================
  //  RECARGAR LOCALIDADES (LOGIN)
  // =====================================================================

  Future<void> recargarLocalidades({required int idUsuario}) async {
    if (sincronizandoMunicipio.value) return;
    sincronizandoMunicipio.value = true;
    try {
      debugPrint('[SyncC] recargarLocalidades: Descargando localidades del usuario $idUsuario...');
      final lista = await ApiService.instance.getLocalidadesMisReportes(
        idUsuario: idUsuario,
        soloHuerfanas: true,
        limit: 500,
      );
      debugPrint('[SyncC] Recibidas ${lista.length} localidades del servidor');

      final db = DatabaseHelper.instance;
      final sincV2 = EdanLocalidadesEnvioV2Service(db: db);

      for (final item in lista) {
        try {
          final localidad = EdanLocalidad.fromJson(item);
          final idLocal = localidad.idLocal;
          if (idLocal == null) continue;

          final existente = await db.getLocalidadByIdLocal(idLocal);
          if (existente != null) {
            if (existente.editado || !existente.sincronizado) continue;

            final modificadasLocales = await db.getSeccionesModificadas(idLocal);
            if (modificadasLocales.isNotEmpty) continue;

            _preservarEncabezado(localidad, existente);
            _mergeSecciones(existente, localidad);
            localidad.idLocal = idLocal;
            localidad.deduplicarSecciones();
            await db.updateLocalidad(localidad);
            if (localidad.idServer != null) {
              await db.markLocalidadAsSynced(idLocal, localidad.idServer!);
            }
            await sincV2.popularSeccionesDesdeServer(localidad);
          } else {
            await db.insertLocalidad(localidad, usuarioId: idUsuario);
            if (localidad.idServer != null) {
              await db.markLocalidadAsSynced(idLocal, localidad.idServer!);
            }
            await sincV2.popularSeccionesDesdeServer(localidad);
          }
        } catch (e) {
          debugPrint('[SyncC] Error cargando localidad: $e');
        }
      }

      await recargarPendientes();
      _descargarFotosPendientes();
      debugPrint('[SyncC] recargarLocalidades finalizado. Pendientes: ${pendientes.value}');
    } catch (e) {
      debugPrint('[SyncC] Error general en recargarLocalidades: $e');
    } finally {
      sincronizandoMunicipio.value = false;
    }
  }

  // =====================================================================
  //  HELPERS
  // =====================================================================

  bool _esMasNueva(String? a, String? b) {
    if (a == null || b == null) return false;
    final da = DateTime.tryParse(a);
    final db2 = DateTime.tryParse(b);
    if (da == null || db2 == null) return a.compareTo(b) > 0;
    return da.isAfter(db2);
  }

  void _preservarEncabezado(EdanLocalidad server, EdanLocalidad local) {
    if (server.nombreAlcalde.isEmpty) server.nombreAlcalde = local.nombreAlcalde;
    if (server.fonoAlcalde.isEmpty) server.fonoAlcalde = local.fonoAlcalde;
    if (server.tipoEventoNombre == null || server.tipoEventoNombre!.isEmpty) {
      server.tipoEventoNombre = local.tipoEventoNombre;
    }
    server.responsable ??= local.responsable;
  }

  void _mergeSecciones(EdanLocalidad local, EdanLocalidad server) {
    server.establecimientosSalud = _fusionarSeccion(local.establecimientosSalud, server.establecimientosSalud);
    server.danosViales = _fusionarSeccion(local.danosViales, server.danosViales);
    server.danosInfraPublica = _fusionarSeccion(local.danosInfraPublica, server.danosInfraPublica);
    server.unidadesEducativas = _fusionarSeccion(local.unidadesEducativas, server.unidadesEducativas);
    server.danosVivienda = _fusionarSeccion(local.danosVivienda, server.danosVivienda);
    server.danosAgricultura = _fusionarSeccion(local.danosAgricultura, server.danosAgricultura);
    server.danosPecuarios = _fusionarSeccion(local.danosPecuarios, server.danosPecuarios);
    server.infraProductiva = _fusionarSeccion(local.infraProductiva, server.infraProductiva);
    server.serviciosBasicos = _fusionarSeccion(local.serviciosBasicos, server.serviciosBasicos);
    server.proteccion = _fusionarSeccion(local.proteccion, server.proteccion);
    server.impactoPoblacion = _fusionarSeccion(local.impactoPoblacion, server.impactoPoblacion);
  }

  List<T> _fusionarSeccion<T>(List<T> local, List<T> server) {
    if (server.isEmpty) return List<T>.of(local);
    if (local.isEmpty) return List<T>.of(server);

    final serverPorId = <String, T>{};
    final serverSinId = <T>[];
    for (final item in server) {
      final id = idSeccionDe(item);
      if (id != null && id.isNotEmpty) {
        serverPorId[id] = item;
      } else {
        serverSinId.add(item);
      }
    }

    final resultado = <T>[];
    final idsVistos = <String>{};
    for (final itemLocal in local) {
      final id = idSeccionDe(itemLocal);
      T? itemServer;
      if (id != null && id.isNotEmpty) {
        if (idsVistos.contains(id)) continue;
        idsVistos.add(id);
        itemServer = serverPorId.remove(id);
      } else {
        // ítem local sin id: si el servidor tiene un ítem con id cuyo contenido
        // coincide, la copia local es un duplicado llegado en el pull y se
        // descarta (el id-having es la fuente de verdad).
        if (_tieneMatchConId(itemLocal, serverPorId.values.toList())) continue;
      }
      if (itemServer != null) {
        _copiarDatosServer(itemLocal, itemServer);
      }
      resultado.add(itemLocal);
    }

    for (final item in serverPorId.values) {
      final id = idSeccionDe(item);
      if (id != null && id.isNotEmpty && idsVistos.contains(id)) continue;
      if (id != null && id.isNotEmpty) idsVistos.add(id);
      resultado.add(item);
    }
    for (final item in serverSinId) {
      resultado.add(item);
    }
    return resultado;
  }

  /// True si existe en [serverConId] un ítem con `id_seccion` no vacío cuyo
  /// contenido (excluyendo id y campos volátiles) coincide con [local].
  /// Se usa para descartar copias locales SIN id que duplican un ítem del server.
  bool _tieneMatchConId<T>(T local, List<T> serverConId) {
    final huellaLocal = _huellaContenidoSinVolatiles(local as Object);
    if (huellaLocal == null) return false;
    for (final s in serverConId) {
      if (idSeccionDe(s) == null) continue;
      if (huellaLocal == _huellaContenidoSinVolatiles(s as Object)) return true;
    }
    return false;
  }

  /// Huella de contenido de un ítem 1:N, sin `id_seccion` ni campos volátiles
  /// (`fecha_modificacion`, rutas de foto local) para comparar copias.
  String? _huellaContenidoSinVolatiles(Object item) {
    try {
      final String json;
      if (item is EdanEstablecimientoSalud) {
        json = _huellaMap(item.toJson());
      } else if (item is EdanDanoVial) {
        json = _huellaMap(item.toJson());
      } else if (item is EdanDanoInfraPublica) {
        json = _huellaMap(item.toJson());
      } else if (item is EdanDanoUnidadEducativa) {
        json = _huellaMap(item.toJson());
      } else if (item is EdanDanoVivienda) {
        json = _huellaMap(item.toJson());
      } else if (item is EdanDanoAgricultura) {
        json = _huellaMap(item.toJson());
      } else if (item is EdanDanoPecuario) {
        json = _huellaMap(item.toJson());
      } else if (item is EdanInfraProductiva) {
        json = _huellaMap(item.toJson());
      } else if (item is EdanServicioBasicoDetalle) {
        json = _huellaMap(item.toJson());
      } else if (item is EdanGrupoVulnerable) {
        json = _huellaMap(item.toJson());
      } else if (item is EdanImpactoPoblacion) {
        json = _huellaMap(item.toJson());
      } else {
        return null;
      }
      return json;
    } catch (_) {
      return null;
    }
  }

  String _huellaMap(Map<String, dynamic> m) {
    final copia = Map<String, dynamic>.from(m)
      ..remove('id_seccion')
      ..remove('fecha_modificacion')
      ..remove('fecha_modificacion_local')
      // La ruta de foto local y la referencia subida en el servidor difieren
      // para la misma fila física, por lo que no deben participar en la huella.
      ..remove('fotografia')
      ..remove('fotos');
    return jsonEncode(copia);
  }

  bool _falta(String? valor) => valor == null || valor.isEmpty;

  void _copiarDatosServer(dynamic local, dynamic server) {
    if (local is EdanEstablecimientoSalud && server is EdanEstablecimientoSalud) {
      _aplicarServer(local, server.fotografia, server.coordenadaLat, server.coordenadaLon);
    } else if (local is EdanDanoVial && server is EdanDanoVial) {
      _aplicarServer(local, server.fotografia, server.coordenadaLat, server.coordenadaLon);
    } else if (local is EdanDanoInfraPublica && server is EdanDanoInfraPublica) {
      _aplicarServer(local, server.fotografia, server.coordenadaLat, server.coordenadaLon);
    } else if (local is EdanDanoUnidadEducativa && server is EdanDanoUnidadEducativa) {
      _aplicarServer(local, server.fotografia, server.coordenadaLat, server.coordenadaLon);
    } else if (local is EdanDanoVivienda && server is EdanDanoVivienda) {
      _aplicarServer(local, server.fotografia, server.coordenadaLat, server.coordenadaLon);
    } else if (local is EdanDanoAgricultura && server is EdanDanoAgricultura) {
      _aplicarServer(local, server.fotografia, server.coordenadaLat, server.coordenadaLon);
    } else if (local is EdanDanoPecuario && server is EdanDanoPecuario) {
      _aplicarServer(local, server.fotografia, server.coordenadaLat, server.coordenadaLon);
    } else if (local is EdanInfraProductiva && server is EdanInfraProductiva) {
      _aplicarServer(local, server.fotografia, server.coordenadaLat, server.coordenadaLon);
    } else if (local is EdanServicioBasicoDetalle && server is EdanServicioBasicoDetalle) {
      _aplicarServer(local, server.fotografia, server.coordenadaLat, server.coordenadaLon);
    }
  }

  void _aplicarServer(dynamic local, String? fotografia, double lat, double lon) {
    if (local is EdanEstablecimientoSalud) {
      if (_falta(local.fotografia)) local.fotografia = fotografia;
      if (local.coordenadaLat == 0) local.coordenadaLat = lat;
      if (local.coordenadaLon == 0) local.coordenadaLon = lon;
    } else if (local is EdanDanoVial) {
      if (_falta(local.fotografia)) local.fotografia = fotografia;
      if (local.coordenadaLat == 0) local.coordenadaLat = lat;
      if (local.coordenadaLon == 0) local.coordenadaLon = lon;
    } else if (local is EdanDanoInfraPublica) {
      if (_falta(local.fotografia)) local.fotografia = fotografia;
      if (local.coordenadaLat == 0) local.coordenadaLat = lat;
      if (local.coordenadaLon == 0) local.coordenadaLon = lon;
    } else if (local is EdanDanoUnidadEducativa) {
      if (_falta(local.fotografia)) local.fotografia = fotografia;
      if (local.coordenadaLat == 0) local.coordenadaLat = lat;
      if (local.coordenadaLon == 0) local.coordenadaLon = lon;
    } else if (local is EdanDanoVivienda) {
      if (_falta(local.fotografia)) local.fotografia = fotografia;
      if (local.coordenadaLat == 0) local.coordenadaLat = lat;
      if (local.coordenadaLon == 0) local.coordenadaLon = lon;
    } else if (local is EdanDanoAgricultura) {
      if (_falta(local.fotografia)) local.fotografia = fotografia;
      if (local.coordenadaLat == 0) local.coordenadaLat = lat;
      if (local.coordenadaLon == 0) local.coordenadaLon = lon;
    } else if (local is EdanDanoPecuario) {
      if (_falta(local.fotografia)) local.fotografia = fotografia;
      if (local.coordenadaLat == 0) local.coordenadaLat = lat;
      if (local.coordenadaLon == 0) local.coordenadaLon = lon;
    } else if (local is EdanInfraProductiva) {
      if (_falta(local.fotografia)) local.fotografia = fotografia;
      if (local.coordenadaLat == 0) local.coordenadaLat = lat;
      if (local.coordenadaLon == 0) local.coordenadaLon = lon;
    } else if (local is EdanServicioBasicoDetalle) {
      if (_falta(local.fotografia)) local.fotografia = fotografia;
      if (local.coordenadaLat == 0) local.coordenadaLat = lat;
      if (local.coordenadaLon == 0) local.coordenadaLon = lon;
    }
  }

  String? idSeccionDe(dynamic item) {
    if (item is EdanEstablecimientoSalud) return item.idSeccion;
    if (item is EdanDanoVial) return item.idSeccion;
    if (item is EdanDanoInfraPublica) return item.idSeccion;
    if (item is EdanDanoUnidadEducativa) return item.idSeccion;
    if (item is EdanDanoVivienda) return item.idSeccion;
    if (item is EdanDanoAgricultura) return item.idSeccion;
    if (item is EdanDanoPecuario) return item.idSeccion;
    if (item is EdanInfraProductiva) return item.idSeccion;
    if (item is EdanServicioBasicoDetalle) return item.idSeccion;
    if (item is EdanGrupoVulnerable) return item.idSeccion;
    if (item is EdanImpactoPoblacion) return item.idSeccion;
    return null;
  }

  Future<void> recargarPendientes() async {
    try {
      pendientes.value = await DatabaseHelper.instance.countLocalidadesPendientesSync();
    } catch (e) {
      debugPrint('Error recargando pendientes: $e');
    }
  }
}

// =====================================================================
//  MODELOS AUXILIARES
// =====================================================================

class SyncResult {
  bool exito;
  String mensaje;
  int creados = 0;
  int actualizados = 0;
  int enviados = 0;
  int fallidos = 0;
  int eliminados = 0;
  int fotosPendientes = 0;
  int fotosSubidas = 0;
  int fotosFallidas = 0;

  SyncResult({required this.exito, this.mensaje = ''});

  String get resumen {
    if (!exito) return mensaje;
    final partes = <String>[];
    if (creados > 0) partes.add('$creados creados');
    if (actualizados > 0) partes.add('$actualizados actualizados');
    if (enviados > 0) partes.add('$enviados enviados');
    if (eliminados > 0) partes.add('$eliminados eliminados');
    if (fotosPendientes > 0) {
      partes.add('fotos: $fotosSubidas/$fotosPendientes subidas');
    }
    if (fotosFallidas > 0) partes.add('$fotosFallidas fotos fallidas');
    if (fallidos > 0) partes.add('$fallidos fallidos');
    if (partes.isEmpty) return 'Sin cambios';
    return 'Sync: ${partes.join(', ')}';
  }
}

class _EstadosServidor {
  final List<_EstadoItem> lista = [];
  final Map<String, _EstadoItem> _porIdLocal = {};
  final Map<int, _EstadoItem> _porIdEdan = {};

  void cargar(List<Map<String, dynamic>> estados) {
    lista.clear();
    _porIdLocal.clear();
    _porIdEdan.clear();
    for (final e in estados) {
      final item = _EstadoItem.fromJson(e);
      lista.add(item);
      if (item.idLocal != null) _porIdLocal[item.idLocal!] = item;
      if (item.idEdan != null) _porIdEdan[item.idEdan!] = item;
    }
  }

  _EstadoItem? porIdLocal(String? idLocal) =>
      idLocal == null ? null : _porIdLocal[idLocal];

  _EstadoItem? porIdEdan(int? idEdan) =>
      idEdan == null ? null : _porIdEdan[idEdan];
}

class _EstadoItem {
  final String? idLocal;
  final int? idEdan;
  final String? fechaModificacion;
  final bool pendienteEliminacion;

  _EstadoItem({
    this.idLocal,
    this.idEdan,
    this.fechaModificacion,
    this.pendienteEliminacion = false,
  });

  factory _EstadoItem.fromJson(Map<String, dynamic> json) {
    return _EstadoItem(
      idLocal: json['id_local']?.toString(),
      idEdan: _intEstado(json['id_edan_localidad'] ?? json['id_server']),
      fechaModificacion: json['fecha_modificacion']?.toString(),
      pendienteEliminacion:
          json['pendiente_eliminacion'] == true || json['pendiente_eliminacion'] == 1,
    );
  }

  static int? _intEstado(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }
}
