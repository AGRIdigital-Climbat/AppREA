import 'package:flutter/foundation.dart';
import '../models/edan.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/database_helper.dart';
import 'edan/edan_documento_service.dart';
import 'edan/edan_documento_sync_service.dart';
import 'edan/edan_localidades_envio_v2_service.dart';

class EdanSyncService {
  static final EdanSyncService _instance = EdanSyncService._();
  static EdanSyncService get instance => _instance;
  EdanSyncService._();

  bool _isSyncing = false;

  final ValueNotifier<int> pendientes = ValueNotifier(0);
  final ValueNotifier<bool> sincronizando = ValueNotifier(false);
  final ValueNotifier<bool> sincronizandoMunicipio = ValueNotifier(false);

  bool get isSyncing => _isSyncing;

  /// Descarga los EDANs del municipio del usuario (todos los usuarios de ese
  /// municipio) y los guarda localmente. Se dispara tras login/registro de
  /// un rol UGR para que el nuevo responsable recupere el histórico.
  Future<void> recargarEdansMunicipio({
    required int idMunicipio,
    required int usuarioId,
  }) async {
    if (sincronizandoMunicipio.value) return;
    sincronizandoMunicipio.value = true;
    try {
      final lista = await ApiService.instance
          .listarEdansPorMunicipio(idMunicipio);
      for (final item in lista) {
        try {
          final edan = Edan.fromJson(item);
          final serverId = edan.idEdan ?? edan.idServer;
          if (serverId == null) continue;
          final existente =
              await DatabaseHelper.instance.getEdanByServerId(serverId);
          if (existente != null) {
            if (existente.pendienteActualizacion || !existente.sincronizado) {
              continue;
            }
            edan.idLocal = existente.idLocal;
            await DatabaseHelper.instance.updateEdan(edan);
            await DatabaseHelper.instance.markEdanAsSynced(
              existente.idLocal!,
              serverId,
            );
          } else {
            final idLocal = await DatabaseHelper.instance
                .insertEdan(edan, usuarioId: usuarioId);
            if (idLocal > 0) {
              await DatabaseHelper.instance
                  .markEdanAsSynced(idLocal, serverId);
            }
          }
        } catch (e) {
          debugPrint('Error cargando EDAN del municipio: $e');
        }
      }
      await recargarPendientes();
    } catch (e) {
      debugPrint('Error cargando EDANs del municipio: $e');
    } finally {
      sincronizandoMunicipio.value = false;
    }
  }

  Future<SyncResult> sincronizar() async {
    if (_isSyncing) {
      return SyncResult(
        exito: false,
        mensaje: 'Ya hay una sincronización en curso',
      );
    }

    _isSyncing = true;
    sincronizando.value = true;
    try {
      final userId = AuthService.instance.userId;
      if (userId == null) {
        return SyncResult(
          exito: false,
          mensaje: 'Usuario no autenticado',
        );
      }

      final result = SyncResult(exito: true);

      await _pullEdans(userId, result);
      await _pushDeletions(result);
      await _pushEdans(userId, result);

      return result;
    } catch (e) {
      debugPrint('Error en sincronización: $e');
      return SyncResult(
        exito: false,
        mensaje: 'Error: ${e.toString()}',
      );
    } finally {
      _isSyncing = false;
      sincronizando.value = false;
      await recargarPendientes();
    }
  }

  Future<void> recargarPendientes() async {
    try {
      pendientes.value =
          await DatabaseHelper.instance.countEdansPendientesSync();
    } catch (e) {
      debugPrint('Error recargando pendientes: $e');
    }
  }

  Future<void> _pullEdans(int userId, SyncResult result) async {
    try {
      final api = ApiService.instance;
      final db = DatabaseHelper.instance;
      final servicioV2 = EdanLocalidadesEnvioV2Service();

      // 1) Cabeceras de EDAN: listado estándar `/edan/` (ruta viva; la antigua
      //    `/edan/sync/pull` ya no existe y devolvía 404 "not found").
      final edansRemotos = await api.pullEdans(
        idUsuario: userId,
        skip: 0,
        limit: 100,
      );

      for (final edanJson in edansRemotos) {
        final edan = Edan.fromJson(edanJson);
        final serverId = edan.idEdan ?? edan.idServer ?? 0;

        final existente = await db.getEdanByServerId(serverId);
        if (existente != null) {
          if (!existente.pendienteActualizacion && existente.sincronizado) {
            edan.idLocal = existente.idLocal;
            await db.updateEdan(edan);
            await db.markEdanAsSynced(
              existente.idLocal!,
              edan.idEdan ?? edan.idServer ?? existente.idServer ?? 0,
            );
          }
          result.actualizados++;
        } else {
          final idLocal = await db.insertEdan(edan, usuarioId: userId);
          if (serverId != 0 && idLocal > 0) {
            await db.markEdanAsSynced(idLocal, serverId);
          }
          if (idLocal > 0) result.creados++;
        }
      }

      // 2) Localidades con todas sus secciones: `GET /edan/localidades/
      //    mis-reportes`. El listado `/edan/` NO trae `localidades` (vienen
      //    vacías), por lo que la descarga real de datos se hace por este
      //    endpoint, cuyo shape es idéntico al documento de `construirDocumento`.
      var skip = 0;
      const page = 100;
      while (true) {
        final items = await api.getLocalidadesMisReportes(
          idUsuario: userId,
          skip: skip,
          limit: page,
          modoComprimido: true,
        );
        if (items.isEmpty) break;
        for (final raw in items) {
          try {
            await _recibirLocalidad(raw, userId, servicioV2, result);
          } catch (e) {
            debugPrint('Error recibiendo localidad del servidor: $e');
            result.fallidos++;
          }
        }
        skip += items.length;
        if (items.length < page) break;
      }
    } catch (e) {
      debugPrint('Error en pull: $e');
      result.mensaje = 'Error al recibir EDANs: ${e.toString()}';
      result.exito = false;
    }
  }

  /// Persiste (insert/update LWW) una localidad traída del servidor y rellena
  /// las tablas de secciones. No pisa cambios locales pendientes de subir.
  Future<void> _recibirLocalidad(
    Map<String, dynamic> raw,
    int userId,
    EdanLocalidadesEnvioV2Service servicioV2,
    SyncResult result,
  ) async {
    final db = DatabaseHelper.instance;
    final server = EdanDocumentoService.parsearDocumento(raw);
    if (server.idLocal == null || server.idLocal!.isEmpty) {
      server.idLocal = 'pull-${DateTime.now().millisecondsSinceEpoch}';
    }
    server.idUsuario = userId;

    final idLocal = server.idLocal!;
    final serverId = server.idServer ?? server.idEdan;

    // Marca borrado en servidor → eliminar local (solo si ya está sincronizada).
    if (server.pendienteEliminacion) {
      final local = await db.getLocalidadByIdLocal(idLocal);
      if (local != null && local.sincronizado) {
        await db.deleteLocalidad(idLocal);
        result.eliminados++;
      }
      return;
    }

    final existente = await db.getLocalidadByIdLocal(idLocal);
    EdanLocalidad persistida;
    if (existente == null) {
      await db.insertLocalidad(server, usuarioId: userId);
      if (serverId != null && serverId > 0) {
        await db.markLocalidadAsSyncedConFecha(
          idLocal,
          serverId,
          server.fechaModificacion ?? DateTime.now().toIso8601String(),
        );
      }
      result.creados++;
      persistida = server;
    } else {
      // No pisar trabajo local pendiente: sus cambios van por el push.
      if (existente.editado ||
          !existente.sincronizado ||
          existente.pendienteActualizacion) {
        return;
      }
      persistida = EdanDocumentoService.aplicarPull(existente, server);
      await db.reemplazarLocalidadDesdeServer(
        persistida,
        idServer: serverId,
        fechaServer: persistida.fechaModificacion,
      );
      result.actualizados++;
    }

    await servicioV2.popularSeccionesDesdeServer(persistida);
  }

  Future<void> _pushDeletions(SyncResult result) async {
    try {
      final pendientes = await DatabaseHelper.instance.getEdansPendingDeletion();

      for (final edan in pendientes) {
        try {
          if (edan.idServer != null) {
            await ApiService.instance.deleteEdan(edan.idServer!);
          }
          await DatabaseHelper.instance.deleteEdan(edan.idLocal!);
          result.eliminados++;
        } catch (e) {
          debugPrint('Error eliminando EDAN ${edan.idLocal}: $e');
          result.fallidos++;
        }
      }
    } catch (e) {
      debugPrint('Error en push de eliminaciones: $e');
      result.mensaje = 'Error al eliminar EDANs: ${e.toString()}';
      result.exito = false;
    }
  }

  Future<void> _pushEdans(int userId, SyncResult result) async {
    try {
      final edansPendientes = await DatabaseHelper.instance.getUnsyncedEdans();

      if (edansPendientes.isEmpty) {
        return;
      }

      final db = DatabaseHelper.instance;
      final docSync = EdanDocumentoSyncService();

      // El backend v2 NO tiene POST `/edan/sync` (404, igual que `sync/pull`).
      // El envío v2 es PER LOCALIDAD vía `POST/PUT /localidades/{...}/documento`
      // (el mismo contrato que usa el RESP en su Fase 2).
      for (final edan in edansPendientes) {
        var todosOk = true;

        for (final loc in edan.localidades) {
          final idLocal = loc.idLocal;
          if (idLocal == null || idLocal.isEmpty) {
            todosOk = false;
            continue;
          }

          try {
            final ok = await docSync.enviarLocalidadDocumento(
              loc,
              skipFotos: true,
            );
            if (ok) {
              final idEdanLocalidad = loc.idServer;
              if (idEdanLocalidad != null) {
                await db.markLocalidadAsSyncedConFecha(
                  idLocal,
                  idEdanLocalidad,
                  loc.fechaModificacion ?? DateTime.now().toIso8601String(),
                );
              } else {
                await db.markLocalidadAsSynced(idLocal, 0);
              }
              result.enviados++;
            } else {
              todosOk = false;
              result.fallidos++;
            }
          } catch (e) {
            todosOk = false;
            result.fallidos++;
            debugPrint('Error enviando localidad ${loc.nombre}: $e');
          }
        }

        // Solo se marca el EDAN sincronizado si todas sus localidades OK.
        if (todosOk && edan.idLocal != null) {
          await db.markEdanAsSynced(
            edan.idLocal!,
            edan.idEdan ?? edan.idServer ?? 0,
          );
        }
      }
    } catch (e) {
      debugPrint('Error en push: $e');
      result.mensaje = 'Error al enviar EDANs: ${e.toString()}';
      result.exito = false;
    }
  }
}

class SyncResult {
  bool exito;
  String mensaje;
  int creados = 0;
  int actualizados = 0;
  int enviados = 0;
  int fallidos = 0;
  int eliminados = 0;

  SyncResult({
    required this.exito,
    this.mensaje = '',
  });

  String get resumen {
    if (!exito) return mensaje;
    
    final partes = <String>[];
    if (creados > 0) partes.add('$creados creados');
    if (actualizados > 0) partes.add('$actualizados actualizados');
    if (enviados > 0) partes.add('$enviados enviados');
    if (eliminados > 0) partes.add('$eliminados eliminados');
    if (fallidos > 0) partes.add('$fallidos fallidos');
    
    if (partes.isEmpty) return 'Sin cambios';
    return 'Sincronización completada: ${partes.join(', ')}';
  }
}
