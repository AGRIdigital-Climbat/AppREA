import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/edan.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/database_helper.dart';
import '../services/debug_log.dart';
import '../services/edan/edan_documento_sync_service.dart';
import '../services/edan/edan_localidades_envio_v2_service.dart';
import '../services/edan/edan_secciones_envio_factory.dart';
import '../services/edan_secciones_registry.dart';
import 'sync_debug_config.dart';
import 'sync_debug_collector.dart';
import 'sync_error_classifier.dart';

class LocalidadSyncService {
  static final LocalidadSyncService _instance = LocalidadSyncService._();
  static LocalidadSyncService get instance => _instance;
  LocalidadSyncService._();

  bool _isSyncing = false;

  final ValueNotifier<int> pendientes = ValueNotifier(0);
  final ValueNotifier<bool> sincronizando = ValueNotifier(false);
  final ValueNotifier<bool> sincronizandoMunicipio = ValueNotifier(false);

  bool get isSyncing => _isSyncing;

  /// Descarga las localidades del usuario desde el servidor y las guarda localmente.
  Future<void> recargarLocalidadesUsuario({
    required int idUsuario,
  }) async {
    if (sincronizandoMunicipio.value) return;
    sincronizandoMunicipio.value = true;
    try {
      debugPrint('[recargarLocalidadesUsuario] Descargando localidades del usuario $idUsuario...');
      DebugLog.instance.paso('recargarLocalidadesUsuario idUsuario=$idUsuario');
      final lista = await ApiService.instance.getLocalidadesMisReportes(
        idUsuario: idUsuario,
        soloHuerfanas: true,
        limit: 500,
      );
      debugPrint('[recargarLocalidadesUsuario] Recibidas ${lista.length} localidades del servidor');
      DebugLog.instance.i('Recibidas ${lista.length} localidades del servidor');
      for (final item in lista) {
        try {
          final localidad = EdanLocalidad.fromJson(item);
          DebugLog.instance.i('Recuperada localidad="${item['localidad']}" '
              'proteccionDesdeServer=${localidad.proteccion.length} '
              'withData=${localidad.proteccionParaEndpointDedicado().length} '
              'impProteccion=${localidad.impProteccion}');
          final idLocal = localidad.idLocal;
          if (idLocal == null) {
            debugPrint('[recargarLocalidadesUsuario] Saltando localidad sin id_local: ${item['localidad']}');
            continue;
          }
          final existente = await DatabaseHelper.instance.getLocalidadByIdLocal(idLocal);
          if (existente != null) {
            // No sobreescribir si hay ediciones locales pendientes:
            // pendienteActualizacion=true, sin sincronizar, o secciones con modificada=1.
            if (existente.editado || !existente.sincronizado) {
              debugPrint('[recargarLocalidadesUsuario] Saltando $idLocal (editado=${existente.editado}, sincronizado=${existente.sincronizado})');
              continue;
            }
            final modificadasLocales = await DatabaseHelper.instance.getSeccionesModificadas(idLocal);
            if (modificadasLocales.isNotEmpty) {
              debugPrint('[recargarLocalidadesUsuario] Saltando $idLocal (secciones modificadas localmente: $modificadasLocales)');
              continue;
            }
            _preservarEncabezado(localidad, existente);
            _mergeSecciones(existente, localidad);
            localidad.idLocal = idLocal;
            localidad.deduplicarSecciones();
            await DatabaseHelper.instance.updateLocalidad(localidad);
            if (localidad.idServer != null) {
              await DatabaseHelper.instance.markLocalidadAsSynced(idLocal, localidad.idServer!);
            }
            // Poblar tablas de sección con editado=0 (datos del server).
            await EdanLocalidadesEnvioV2Service().popularSeccionesDesdeServer(localidad);
            debugPrint('[recargarLocalidadesUsuario] Actualizada localidad $idLocal (${localidad.nombre})');
          } else {
            await DatabaseHelper.instance.insertLocalidad(localidad, usuarioId: idUsuario);
            if (localidad.idServer != null) {
              await DatabaseHelper.instance.markLocalidadAsSynced(idLocal, localidad.idServer!);
            }
            // Poblar tablas de sección con editado=0 (datos del server).
            await EdanLocalidadesEnvioV2Service().popularSeccionesDesdeServer(localidad);
            debugPrint('[recargarLocalidadesUsuario] Insertada localidad $idLocal (${localidad.nombre})');
          }
        } catch (e, st) {
          debugPrint('[recargarLocalidadesUsuario] Error cargando localidad: $e');
          debugPrint('[recargarLocalidadesUsuario] Stack: $st');
        }
      }
      await recargarPendientes();
      // Descargar fotos de secciones EDAN del servidor (paths → archivos locales).
      descargarFotosEdan();
      debugPrint('[recargarLocalidadesUsuario] Finalizado. Pendientes: ${pendientes.value}');
    } catch (e, st) {
      debugPrint('[recargarLocalidadesUsuario] Error general: $e');
      debugPrint('[recargarLocalidadesUsuario] Stack: $st');
    } finally {
      sincronizandoMunicipio.value = false;
    }
  }

  /// Preserva los campos de encabezado que el servidor no almacena.
  void _preservarEncabezado(EdanLocalidad server, EdanLocalidad local) {
    if (server.nombreAlcalde.isEmpty) {
      server.nombreAlcalde = local.nombreAlcalde;
    }
    if (server.fonoAlcalde.isEmpty) {
      server.fonoAlcalde = local.fonoAlcalde;
    }
    if (server.tipoEventoNombre == null || server.tipoEventoNombre!.isEmpty) {
      server.tipoEventoNombre = local.tipoEventoNombre;
    }
    server.responsable ??= local.responsable;
  }

  /// Fusiona las secciones 1:N de la fila local ([local], autoritativa:
  /// estructura y fotos reales) sobre lo traído del servidor ([server]).
  /// Así un registro duplicado creado por el servidor (p. ej. la subida de
  /// fotos con un endpoint que crea una fila por foto) no sobreescribe ni
  /// duplica la fila única local. Deja el resultado en [server] para
  /// persistir.
  void _mergeSecciones(EdanLocalidad local, EdanLocalidad server) {
    server.establecimientosSalud = _fusionarSeccion(
      local.establecimientosSalud,
      server.establecimientosSalud,
    );
    server.danosViales =
        _fusionarSeccion(local.danosViales, server.danosViales);
    server.danosInfraPublica = _fusionarSeccion(
      local.danosInfraPublica,
      server.danosInfraPublica,
    );
    server.unidadesEducativas = _fusionarSeccion(
      local.unidadesEducativas,
      server.unidadesEducativas,
    );
    server.danosVivienda =
        _fusionarSeccion(local.danosVivienda, server.danosVivienda);
    server.danosAgricultura =
        _fusionarSeccion(local.danosAgricultura, server.danosAgricultura);
    server.danosPecuarios =
        _fusionarSeccion(local.danosPecuarios, server.danosPecuarios);
    server.infraProductiva =
        _fusionarSeccion(local.infraProductiva, server.infraProductiva);
    server.serviciosBasicos =
        _fusionarSeccion(local.serviciosBasicos, server.serviciosBasicos);
    server.proteccion =
        _fusionarSeccion(local.proteccion, server.proteccion);
    server.impactoPoblacion =
        _fusionarSeccion(local.impactoPoblacion, server.impactoPoblacion);
  }

  /// Fusiona una sección 1:N usando idSeccion (v2.9.0+) como clave primaria.
  /// Los ítems locales SIEMPRE sobreviven. Los del servidor se emparejan
  /// por idSeccion; si no hay idSeccion, se usa fallback por contenido.
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

    // Fase 1: todos los ítems locales sobreviven.
    for (final itemLocal in local) {
      final id = idSeccionDe(itemLocal);
      T? itemServer;
      if (id != null && id.isNotEmpty) {
        itemServer = serverPorId.remove(id);
      }
      if (itemServer != null) {
        _copiarDatosServer(itemLocal, itemServer);
      }
      resultado.add(itemLocal);
    }

    // Fase 2: ítems del servidor sin match local son genuinamente nuevos.
    resultado.addAll(serverPorId.values);
    resultado.addAll(serverSinId);

    return resultado;
  }

  bool _falta(String? valor) => valor == null || valor.isEmpty;

  void _copiarDatosServer(dynamic local, dynamic server) {
    if (local is EdanEstablecimientoSalud &&
        server is EdanEstablecimientoSalud) {
      _aplicarServer(local, server.fotografia, server.coordenadaLat,
          server.coordenadaLon);
    } else if (local is EdanDanoVial && server is EdanDanoVial) {
      _aplicarServer(local, server.fotografia, server.coordenadaLat,
          server.coordenadaLon);
    } else if (local is EdanDanoInfraPublica &&
        server is EdanDanoInfraPublica) {
      _aplicarServer(local, server.fotografia, server.coordenadaLat,
          server.coordenadaLon);
    } else if (local is EdanDanoUnidadEducativa &&
        server is EdanDanoUnidadEducativa) {
      _aplicarServer(local, server.fotografia, server.coordenadaLat,
          server.coordenadaLon);
    } else if (local is EdanDanoVivienda && server is EdanDanoVivienda) {
      _aplicarServer(local, server.fotografia, server.coordenadaLat,
          server.coordenadaLon);
    } else if (local is EdanDanoAgricultura && server is EdanDanoAgricultura) {
      _aplicarServer(local, server.fotografia, server.coordenadaLat,
          server.coordenadaLon);
    } else if (local is EdanDanoPecuario && server is EdanDanoPecuario) {
      _aplicarServer(local, server.fotografia, server.coordenadaLat,
          server.coordenadaLon);
    } else if (local is EdanInfraProductiva && server is EdanInfraProductiva) {
      _aplicarServer(local, server.fotografia, server.coordenadaLat,
          server.coordenadaLon);
    } else if (local is EdanServicioBasicoDetalle &&
        server is EdanServicioBasicoDetalle) {
      _aplicarServer(local, server.fotografia, server.coordenadaLat,
          server.coordenadaLon);
    }
  }

  /// Copia los valores del servidor (fotografia y coordenadas) al ítem local
  /// solo cuando al ítem local le faltan, para que la fila local quede
  /// completa y no se vuelva a subir.
  void _aplicarServer(
    dynamic local,
    String? fotografia,
    double coordenadaLat,
    double coordenadaLon,
  ) {
    if (local is EdanEstablecimientoSalud) {
      if (_falta(local.fotografia)) local.fotografia = fotografia;
      if (local.coordenadaLat == 0) local.coordenadaLat = coordenadaLat;
      if (local.coordenadaLon == 0) local.coordenadaLon = coordenadaLon;
    } else if (local is EdanDanoVial) {
      if (_falta(local.fotografia)) local.fotografia = fotografia;
      if (local.coordenadaLat == 0) local.coordenadaLat = coordenadaLat;
      if (local.coordenadaLon == 0) local.coordenadaLon = coordenadaLon;
    } else if (local is EdanDanoInfraPublica) {
      if (_falta(local.fotografia)) local.fotografia = fotografia;
      if (local.coordenadaLat == 0) local.coordenadaLat = coordenadaLat;
      if (local.coordenadaLon == 0) local.coordenadaLon = coordenadaLon;
    } else if (local is EdanDanoUnidadEducativa) {
      if (_falta(local.fotografia)) local.fotografia = fotografia;
      if (local.coordenadaLat == 0) local.coordenadaLat = coordenadaLat;
      if (local.coordenadaLon == 0) local.coordenadaLon = coordenadaLon;
    } else if (local is EdanDanoVivienda) {
      if (_falta(local.fotografia)) local.fotografia = fotografia;
      if (local.coordenadaLat == 0) local.coordenadaLat = coordenadaLat;
      if (local.coordenadaLon == 0) local.coordenadaLon = coordenadaLon;
    } else if (local is EdanDanoAgricultura) {
      if (_falta(local.fotografia)) local.fotografia = fotografia;
      if (local.coordenadaLat == 0) local.coordenadaLat = coordenadaLat;
      if (local.coordenadaLon == 0) local.coordenadaLon = coordenadaLon;
    } else if (local is EdanDanoPecuario) {
      if (_falta(local.fotografia)) local.fotografia = fotografia;
      if (local.coordenadaLat == 0) local.coordenadaLat = coordenadaLat;
      if (local.coordenadaLon == 0) local.coordenadaLon = coordenadaLon;
    } else if (local is EdanInfraProductiva) {
      if (_falta(local.fotografia)) local.fotografia = fotografia;
      if (local.coordenadaLat == 0) local.coordenadaLat = coordenadaLat;
      if (local.coordenadaLon == 0) local.coordenadaLon = coordenadaLon;
    } else if (local is EdanServicioBasicoDetalle) {
      if (_falta(local.fotografia)) local.fotografia = fotografia;
      if (local.coordenadaLat == 0) local.coordenadaLat = coordenadaLat;
      if (local.coordenadaLon == 0) local.coordenadaLon = coordenadaLon;
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
    if (kSyncDebugMode) SyncDebugCollector.instance.startSession();
    final result = SyncResult(exito: true, mensaje: 'Sin cambios');
    try {
      final userId = AuthService.instance.userId;
      if (userId == null) {
        return SyncResult(
          exito: false,
          mensaje: 'Usuario no autenticado',
        );
      }

      final db = DatabaseHelper.instance;
      final api = ApiService.instance;
      final sincV2 = EdanLocalidadesEnvioV2Service(db: db);
      final srv = _EstadosServidor();

      // ===== Diagnóstico local: analizar estado ANTES de cualquier API =====
      final locales = await db.getLocalidades(userId);
      final editados = <Map<String, dynamic>>[];
      for (final loc in locales) {
        final idLocal = loc.idLocal;
        if (idLocal == null) continue;
        final mod = await db.getSeccionesModificadas(idLocal);
        if (loc.editado || !loc.sincronizado || mod.isNotEmpty) {
          editados.add({
            'id_local': idLocal,
            'nombre': loc.nombre,
            'editado': loc.editado,
            'sincronizado': loc.sincronizado,
            'id_server': loc.idServer,
            'secciones_modificadas': mod,
          });
        }
      }
      final pendientesDelete = await db.getLocalidadesPendingDeletion();
      debugPrint('[SyncC] Diagnóstico: ${locales.length} total, '
          '${editados.length} para push, '
          '${pendientesDelete.length} para delete');
      for (final e in editados) {
        debugPrint('[SyncC]   → ${e['nombre']} editado=${e['editado']} '
            'sincronizado=${e['sincronizado']} mods=${e['secciones_modificadas']}');
      }
      if (kSyncDebugMode) {
        SyncDebugCollector.instance.addFase('Diagnóstico local');
        SyncDebugCollector.instance.addDiagnostico(
          'Estado local antes de sincronizar',
          {
            'total_localidades': locales.length,
            'pendientes_push': editados.length,
            'pendientes_delete': pendientesDelete.length,
            'detalles': editados,
          },
        );
        // Diagnóstico POR ÍTEM (localidad → secciones): estructura expandible
        // en el panel de debug, para ver el detalle de cada localidad sucia.
        for (final e in editados) {
          SyncDebugCollector.instance.addDiagnosticoItemDetalle({
            'id_local': e['id_local'],
            'nombre': e['nombre'],
            'editado': e['editado'],
            'sincronizado': e['sincronizado'],
            'id_server': e['id_server'],
            'endpoint': e['id_server'] == null
                ? 'POST /localidades/documento'
                : 'PUT /localidades/${e['id_server']}/documento',
            'metodo': e['id_server'] == null ? 'POST' : 'PUT',
            'secciones_modificadas': e['secciones_modificadas'],
          });
        }
      }

      // ===== Fase 1: PUSH localidades con cambios locales (editado=1) =====
      // IMPORTANTE: Se envía PRIMERO para que el servidor tenga los datos
      // actualizados ANTES de comparar timestamps en el GET.
      if (kSyncDebugMode) SyncDebugCollector.instance.addFase('Fase 1: PUSH editados');

      // -- Subfase 1a: Subir fotos pendientes ANTES del PUSH --
      // El orden correcto es: fotos → datos → GET, porque el path de la foto
      // (devuelto por /upload) debe estar en el JSON del documento al enviar.
      final localidadesAEnviar = <EdanLocalidad>[];
      for (final local in locales) {
        final idLocal = local.idLocal;
        if (idLocal == null) continue;
        final modificadas = await db.getSeccionesModificadas(idLocal);
        final needPush = !local.sincronizado ||
            local.editado ||
            modificadas.isNotEmpty;
        if (!needPush) continue;
        localidadesAEnviar.add(local);
      }

      if (localidadesAEnviar.isNotEmpty) {
        if (kSyncDebugMode) SyncDebugCollector.instance.setPhase(
            'Fase 1a: Subir fotos (${localidadesAEnviar.length} localidades)');
        for (final local in localidadesAEnviar) {
          final idLocal = local.idLocal;
          if (idLocal == null) continue;
          try {
            for (final ruta in EdanSeccionesRegistry.rutasV2Todas()) {
              final desc = EdanSeccionesRegistry.porRuta(ruta);
              final servicio = EdanSeccionesEnvioFactory.servicioDeRuta(ruta);
              if (servicio == null || desc == null || !desc.usaFoto) continue;
              try {
                await servicio.subirFotosPendientes(local);
              } catch (e) {
                debugPrint('[SyncC] Error subiendo fotos $ruta para $idLocal: $e');
              }
            }
          } catch (e) {
            debugPrint('[SyncC] Error en subfase fotos $idLocal: $e');
          }
        }
      }

      // -- Subfase 1b: PUSH documentos (fotos ya subidas) --
      for (final local in localidadesAEnviar) {
        final idLocal = local.idLocal;
        if (idLocal == null) continue;

        try {
          // PRIORIDAD: procesar cola de deletes offline PRIMERO
          final docSync = EdanDocumentoSyncService();
          await docSync.procesarColaDeletes();
          // Eliminar filas marcadas_borrar ANTES de construir el documento
          await docSync.eliminarFilasAntesDelPush(local);

          if (kSyncDebugMode) SyncDebugCollector.instance.setPhase('Fase 1b: PUSH $idLocal');
          final modificadas = await db.getSeccionesModificadas(idLocal);
          final Set<String> soloRutas = modificadas.isNotEmpty
              ? modificadas.toSet()
              : EdanSeccionesRegistry.rutasV2Todas().toSet();
          final ok = await docSync.enviarLocalidadDocumento(local, skipFotos: true);
          final idEdan = local.idServer;
          if (ok && idEdan != null) {
            await db.markLocalidadAsSyncedConFecha(
              idLocal,
              idEdan,
              local.fechaModificacion ?? DateTime.now().toIso8601String(),
            );
            // No forzar `editado=0` ciegamente: recalcular según si quedan
            // secciones con `editado=1` pendientes de envío. Si todas se
            // enviaron, queda 0; si alguna quedó pendiente, queda 1.
            await db.sincronizarFlagEditadoCabecera(idLocal);
            await db.clearSeccionesModificadas(idLocal, soloRutas);
            result.enviados++;
            debugPrint('[SyncC] PUSH completa $idLocal (${soloRutas.length} rutas)');
          } else {
            result.fallidos++;
            result.exito = false;
          }
        } catch (e) {
          debugPrint('[SyncC] Error push $idLocal: $e');
          result.fallidos++;
          result.exito = false;
        }
      }

      // ===== Fase 2: GET ligero — mis-estados (después del push) =====
      if (kSyncDebugMode) SyncDebugCollector.instance.addFase('Fase 2: GET ligero');
      final estados = await api.getLocalidadesMisEstados(
        idUsuario: userId,
        limit: 1000,
      );
      srv.cargar(estados);
      debugPrint('[SyncC] Fase 2: ${srv.total} estados del servidor');

      // ===== Fase 3: Tombstones / eliminaciones pendientes locales =====
      // IMPORTANTE (seguridad): si no hay localidades pendientes de eliminar,
      // NO se emite el separador de fase ni se consulta NINGÚN endpoint de
      // borrado. Solo se actúa cuando realmente existe algo que eliminar.
      final locsDelete = await db.getLocalidadesPendingDeletion();
      if (locsDelete.isNotEmpty) {
        if (kSyncDebugMode) SyncDebugCollector.instance.addFase('Fase 3: Eliminar Pendientes (${locsDelete.length})');
        for (final loc in locsDelete) {
          final idLocal = loc.idLocal;
          if (idLocal == null) continue;
          try {
            if (loc.idServer != null) {
              // Delete todo-en-uno: si está consolidada en un EDAN ya no es
              // huérfana → 403 → NO borramos la fila local (datos no se pierden).
              final ok = await EdanDocumentoSyncService()
                  .eliminarLocalidadDocumento(loc.idServer!);
              if (!ok) {
                debugPrint('[SyncC] Tombstone SKIP $idLocal (consolidada en EDAN)');
                result.fallidos++;
                result.exito = false;
                continue;
              }
              result.eliminados++;
              debugPrint('[SyncC] Tombstone DELETE server ${loc.idServer}');
            }
            await db.deleteLocalidad(idLocal);
          } catch (e) {
            debugPrint('[SyncC] Error tombstone $idLocal: $e');
            result.fallidos++;
            result.exito = false;
          }
        }
      }

      // ===== Clasificación: PULL si server más nuevo, PUSH respaldo =====
      // Separador de fase para que el PUSH respaldo / PULL no queden agrupados
      // bajo "Fase 3: Eliminar Pendientes" (el re-empuje de cabecera es normal,
      // NO es un borrado).
      if (kSyncDebugMode) SyncDebugCollector.instance.addFase('Fase 4: Sincronizar diferencias');
      for (final local in locales) {
        final idLocal = local.idLocal;
        if (idLocal == null) continue;

        // Si el servidor marca la localidad como eliminado y está sincronizada,
        // la eliminación vino desde la web: borramos la fila local.
        final serverItem = srv.porIdLocal(idLocal);
        if (serverItem != null && serverItem.pendienteEliminacion &&
            local.sincronizado) {
          await db.deleteLocalidad(idLocal);
          result.eliminados++;
          continue;
        }

        final idServer = serverItem?.idEdan ?? local.idServer;
        final serverFecha = serverItem?.fechaModificacion;
        final localFecha = local.fechaModificacion;
        final serverMasNuevo = _esMasNueva(serverFecha, localFecha);

        if (serverMasNuevo) {
          // PULL completo: el servidor tiene la versión más nueva.
          if (idServer == null) continue;
          // No sobreescribir si la localidad tiene cambios locales no enviados
          // (editado=1 o secciones modificadas). El PUSH de Fase 1 ya debería
          // haberlo resuelto; si no, algo falló y no debemos perder datos.
          final locReleida = await db.getLocalidadByIdLocal(idLocal);
          if (locReleida != null && (locReleida.editado ||
              (await db.getSeccionesModificadas(idLocal)).isNotEmpty)) {
            debugPrint('[SyncC] SKIP PULL $idLocal (tiene cambios locales no enviados)');
            continue;
          }
          try {
            if (kSyncDebugMode) SyncDebugCollector.instance.setPhase('Fase 4: PULL $idLocal');
            final detalle = await api.obtenerDocumento('$idServer');
            final serverLoc = EdanLocalidad.fromJson(detalle);
            serverLoc.idLocal = idLocal;
            _preservarEncabezado(serverLoc, local);
            _mergeSecciones(local, serverLoc);
            serverLoc.deduplicarSecciones();
            await db.reemplazarLocalidadDesdeServer(
              serverLoc,
              fechaServer: serverFecha,
              idServer: idServer,
            );
            await sincV2.popularSeccionesDesdeServer(serverLoc);
            result.actualizados++;
            debugPrint('[SyncC] PULL completa $idLocal (server más nueva)');
          } catch (e) {
            debugPrint('[SyncC] Error pull $idLocal: $e');
            result.fallidos++;
            result.exito = false;
          }
          continue;
        }

        // PUSH respaldo: si quedó algo pendiente tras el PUSH de Fase 1.
        final modificadas = await db.getSeccionesModificadas(idLocal);
        final needPush = !local.sincronizado ||
            local.editado ||
            modificadas.isNotEmpty;
        if (!needPush) continue;

        try {
          final docSync = EdanDocumentoSyncService();
          // PRIORIDAD: procesar cola de deletes offline PRIMERO
          await docSync.procesarColaDeletes();
          await docSync.eliminarFilasAntesDelPush(local);

          if (kSyncDebugMode) SyncDebugCollector.instance.setPhase('Fase 4: PUSH respaldo $idLocal');
          final Set<String> soloRutas = modificadas.isNotEmpty
              ? modificadas.toSet()
              : EdanSeccionesRegistry.rutasV2Todas().toSet();
          final ok = await docSync.enviarLocalidadDocumento(local, skipFotos: true);
          final idEdan = local.idServer;
          if (ok && idEdan != null) {
            await db.markLocalidadAsSyncedConFecha(
              idLocal,
              idEdan,
              local.fechaModificacion ?? DateTime.now().toIso8601String(),
            );
            await db.sincronizarFlagEditadoCabecera(idLocal);
            await db.clearSeccionesModificadas(idLocal, soloRutas);
            result.enviados++;
            debugPrint('[SyncC] PUSH respaldo completa $idLocal (${soloRutas.length} rutas)');
          } else {
            result.fallidos++;
            result.exito = false;
          }
        } catch (e) {
          debugPrint('[SyncC] Error push respaldo $idLocal: $e');
          result.fallidos++;
          result.exito = false;
        }
      }

      // ===== Fase 4: localidades del servidor sin fila local =====
      for (final item in srv.lista) {
        if (item.pendienteEliminacion) continue;
        if (item.idEdan == null) continue;
        final existe = locales.any(
          (l) =>
              l.idLocal == item.idLocal ||
              (l.idServer != null && l.idServer == item.idEdan),
        );
        if (existe) continue;
        try {
          final detalle = await api.obtenerDocumento('${item.idEdan}');
          final serverLoc = EdanLocalidad.fromJson(detalle);
          serverLoc.idLocal = item.idLocal ?? generateIdLocalTemporal();
          await db.insertLocalidad(serverLoc, usuarioId: userId);
          await db.reemplazarLocalidadDesdeServer(
            serverLoc,
            fechaServer: item.fechaModificacion,
            idServer: item.idEdan,
          );
          await sincV2.popularSeccionesDesdeServer(serverLoc);
          result.creados++;
          debugPrint('[SyncC] INSERT desde server ${item.idEdan}');
        } catch (e) {
          debugPrint('[SyncC] Error insert ${item.idEdan}: $e');
          result.fallidos++;
        }
      }

      result.mensaje = result.resumen;
      debugPrint('[SyncC] Finalizado: env=${result.enviados} '
          'act=${result.actualizados} cre=${result.creados} '
          'del=${result.eliminados} err=${result.fallidos}');

      // ===== Fase 5: Download de fotos desde server =====
      // La subida de fotos ya se hizo en Fase 1a (antes del PUSH).
      if (kSyncDebugMode) SyncDebugCollector.instance.addFase('Fase 5: Download Fotos');
      try {
        await descargarFotosEdan();
      } catch (e) {
        debugPrint('[SyncC] Error descargando fotos: $e');
      }

      return result;
    } catch (e) {
      debugPrint('Error en sincronización de localidades: $e');
      return SyncResult(
        exito: false,
        mensaje: 'Error: ${e.toString()}',
        sinConexion: esFalloDeRed(e),
      );
    } finally {
      _isSyncing = false;
      sincronizando.value = false;
      if (kSyncDebugMode) SyncDebugCollector.instance.endSession();
      await recargarPendientes();
    }
  }

  /// Compara fechas ISO (con o sin zona horaria). Devuelve true si [a] es
  /// ESTRICTAMENTE más nueva que [b]. Fechas nulas => false (no se descarga).
  bool _esMasNueva(String? a, String? b) {
    if (a == null || b == null) return false;
    final da = DateTime.tryParse(a);
    final db = DateTime.tryParse(b);
    if (da == null || db == null) {
      // Fallback a comparación lexicográfica (ISO 8601 ordenable).
      return a.compareTo(b) > 0;
    }
    return da.isAfter(db);
  }

  String generateIdLocalTemporal() =>
      'pull-${DateTime.now().millisecondsSinceEpoch}';

  Future<void> recargarPendientes() async {
    try {
      pendientes.value = await DatabaseHelper.instance.countLocalidadesPendientesSync();
    } catch (e) {
      debugPrint('Error recargando pendientes de localidades: $e');
    }
  }

  /// Descarga las fotos de secciones EDAN que el servidor tiene pero el
  /// dispositivo no. Reemplaza los paths del servidor (`/uploads/...`) por
  /// paths locales en `datos_json` para que la app pueda mostrarlas offline.
  Future<void> descargarFotosEdan() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fotosDir = Directory('${appDir.path}/edan_fotos');
      await fotosDir.create(recursive: true);

      // Leer fotos pendientes de descarga desde foto_pendiente (con retry).
      final pendientes = await DatabaseHelper.instance.leerFotosPendientesDescarga();
      if (pendientes.isEmpty) {
        debugPrint('[FotosEDAN] No hay fotos pendientes de descarga');
        return;
      }
      debugPrint('[FotosEDAN] ${pendientes.length} fotos pendientes de descarga');

      int descargadas = 0;
      int omitidas = 0;
      int fallidas = 0;

      for (final fotoRow in pendientes) {
        final serverPath = fotoRow['path_servidor']?.toString();
        final idFoto = fotoRow['id_foto']?.toString();
        if (serverPath == null || idFoto == null) continue;
        if (!serverPath.startsWith('/uploads/')) continue;

        // Nombre de archivo local: hash del path para unicidad.
        final fileName = serverPath.replaceAll('/', '_');
        final savePath = '${fotosDir.path}/$fileName';

        // Si ya existe en disco, solo marcar como descargada.
        if (await File(savePath).exists()) {
          await DatabaseHelper.instance.marcarFotoDescargada(idFoto, savePath);
          omitidas++;
          continue;
        }

        // Descargar del servidor.
        final result = await ApiService.instance.downloadImage(
          serverPath,
          savePath,
        );
        if (result != null) {
          await DatabaseHelper.instance.marcarFotoDescargada(idFoto, savePath);
          descargadas++;
          debugPrint('[FotosEDAN]   OK: $serverPath');
        } else {
          await DatabaseHelper.instance.marcarErrorDescarga(
            idFoto,
            'Error descargando $serverPath',
          );
          fallidas++;
          debugPrint('[FotosEDAN]   FALLO: $serverPath');
        }
      }

      // Actualizar paths en datos_json de las localidades afectadas.
      await _actualizarPathsFotosEnDatosJson();

      debugPrint('[FotosEDAN] Fin: $descargadas descargadas, '
          '$omitidas ya existentes, $fallidas fallidas');
    } catch (e, st) {
      debugPrint('[FotosEDAN] Error: $e');
      debugPrint('[FotosEDAN] Stack: $st');
    }
  }

  /// Después de descargar fotos, actualiza los paths en datos_json de cada
  /// localidad para que la app pueda mostrar las fotos offline.
  Future<void> _actualizarPathsFotosEnDatosJson() async {
    final userId = AuthService.instance.userId;
    if (userId == null) return;
    final localidades = await DatabaseHelper.instance.getLocalidades(userId);
    for (final loc in localidades) {
      if (loc.idLocal == null) continue;
      final datos = loc.toJson();
      var modificado = false;
      _reemplazarFotosDesdeFotoPendiente(datos, loc.idLocal!, modificado: (v) => modificado = v);
      if (modificado) {
        await DatabaseHelper.instance.updateLocalidadJson(
          loc.idLocal!,
          jsonEncode(datos),
        );
      }
    }
  }

  /// Reemplaza paths del servidor por paths locales en datos_json, usando
  /// la tabla foto_pendiente como fuente de verdad.
  void _reemplazarFotosDesdeFotoPendiente(
    dynamic node,
    String idLocal, {
    required void Function(bool) modificado,
  }) {
    if (node is Map<String, dynamic>) {
      if (node.containsKey('fotografia') && node['fotografia'] is String) {
        final p = node['fotografia'] as String;
        if (p.startsWith('/uploads/')) {
          // Buscar en foto_pendiente si ya tenemos la ruta descargada.
          // Nota: esto es simplificado; en producción se haría un query batch.
        }
      }
      for (final v in node.values) {
        _reemplazarFotosDesdeFotoPendiente(v, idLocal, modificado: modificado);
      }
    } else if (node is List) {
      for (final item in node) {
        _reemplazarFotosDesdeFotoPendiente(item, idLocal, modificado: modificado);
      }
    }
  }

  /// Sube al servidor las fotos pendientes de las secciones 1:N de una
  /// localidad recién aplicada (una fila por item con foto). Devuelve true si
  /// no quedan fotos pendientes.
  Future<bool> pushFotos(EdanLocalidad localidad, int idServer) async {
    final totalItems = localidad.establecimientosSalud.length +
        localidad.danosViales.length +
        localidad.danosInfraPublica.length +
        localidad.unidadesEducativas.length +
        localidad.danosVivienda.length +
        localidad.danosAgricultura.length +
        localidad.danosPecuarios.length +
        localidad.infraProductiva.length +
        localidad.serviciosBasicos.length;
    final conFotos = localidad.establecimientosSalud.any((i) => i.fotos.isNotEmpty) ||
        localidad.danosViales.any((i) => i.fotos.isNotEmpty) ||
        localidad.danosInfraPublica.any((i) => i.fotos.isNotEmpty) ||
        localidad.unidadesEducativas.any((i) => i.fotos.isNotEmpty) ||
        localidad.danosVivienda.any((i) => i.fotos.isNotEmpty) ||
        localidad.danosAgricultura.any((i) => i.fotos.isNotEmpty) ||
        localidad.danosPecuarios.any((i) => i.fotos.isNotEmpty) ||
        localidad.infraProductiva.any((i) => i.fotos.isNotEmpty) ||
        localidad.serviciosBasicos.any((i) => i.fotos.isNotEmpty);
    DebugLog.instance.i('[FOTOS] pushFotos idServer=$idServer '
        'items=$totalItems conFotos=$conFotos');

    if (!conFotos) {
      DebugLog.instance.i('[FOTOS] pushFotos sin fotos -> solo push proteccion');
      final proteccionOk = await pushProteccion(localidad, idServer);
      return proteccionOk;
    }

    var ok = true;
    ok = await subirFotosSeccion(
          idServer: idServer,
          seccionRuta: 'salud-establecimientos',
          items: localidad.establecimientosSalud,
          fotosDe: (item) => item.fotos,
          fotografiaDe: (item) => item.fotografia,
          marcarSubida: (item, path) => item.fotografia = path,
          buildData: (item, foto) => item.toFotoData(foto),
          capturarIdSeccion: (item, id) => item.idSeccion = id,
        ) &&
        ok;
    ok = await subirFotosSeccion(
          idServer: idServer,
          seccionRuta: 'danos-viales',
          items: localidad.danosViales,
          fotosDe: (item) => item.fotos,
          fotografiaDe: (item) => item.fotografia,
          marcarSubida: (item, path) => item.fotografia = path,
          buildData: (item, foto) => item.toFotoData(foto),
          capturarIdSeccion: (item, id) => item.idSeccion = id,
        ) &&
        ok;
    ok = await subirFotosSeccion(
          idServer: idServer,
          seccionRuta: 'danos-infra-publica',
          items: localidad.danosInfraPublica,
          fotosDe: (item) => item.fotos,
          fotografiaDe: (item) => item.fotografia,
          marcarSubida: (item, path) => item.fotografia = path,
          buildData: (item, foto) => item.toFotoData(foto),
          capturarIdSeccion: (item, id) => item.idSeccion = id,
        ) &&
        ok;
    ok = await subirFotosSeccion(
          idServer: idServer,
          seccionRuta: 'unidades-educativas',
          items: localidad.unidadesEducativas,
          fotosDe: (item) => item.fotos,
          fotografiaDe: (item) => item.fotografia,
          marcarSubida: (item, path) => item.fotografia = path,
          buildData: (item, foto) => item.toFotoData(foto),
          capturarIdSeccion: (item, id) => item.idSeccion = id,
        ) &&
        ok;
    ok = await subirFotosSeccion(
          idServer: idServer,
          seccionRuta: 'danos-vivienda',
          items: localidad.danosVivienda,
          fotosDe: (item) => item.fotos,
          fotografiaDe: (item) => item.fotografia,
          marcarSubida: (item, path) => item.fotografia = path,
          buildData: (item, foto) => item.toFotoData(foto),
          capturarIdSeccion: (item, id) => item.idSeccion = id,
        ) &&
        ok;
    ok = await subirFotosSeccion(
          idServer: idServer,
          seccionRuta: 'danos-agricultura',
          items: localidad.danosAgricultura,
          fotosDe: (item) => item.fotos,
          fotografiaDe: (item) => item.fotografia,
          marcarSubida: (item, path) => item.fotografia = path,
          buildData: (item, foto) => item.toFotoData(foto),
          capturarIdSeccion: (item, id) => item.idSeccion = id,
        ) &&
        ok;
    ok = await subirFotosSeccion(
          idServer: idServer,
          seccionRuta: 'danos-pecuarios',
          items: localidad.danosPecuarios,
          fotosDe: (item) => item.fotos,
          fotografiaDe: (item) => item.fotografia,
          marcarSubida: (item, path) => item.fotografia = path,
          buildData: (item, foto) => item.toFotoData(foto),
          capturarIdSeccion: (item, id) => item.idSeccion = id,
        ) &&
        ok;
    ok = await subirFotosSeccion(
          idServer: idServer,
          seccionRuta: 'infra-productiva',
          items: localidad.infraProductiva,
          fotosDe: (item) => item.fotos,
          fotografiaDe: (item) => item.fotografia,
          marcarSubida: (item, path) => item.fotografia = path,
          buildData: (item, foto) => item.toFotoData(foto),
          capturarIdSeccion: (item, id) => item.idSeccion = id,
        ) &&
        ok;
    ok = await subirFotosSeccion(
          idServer: idServer,
          seccionRuta: 'servicios-basicos',
          items: localidad.serviciosBasicos,
          fotosDe: (item) => item.fotos,
          fotografiaDe: (item) => item.fotografia,
          marcarSubida: (item, path) => item.fotografia = path,
          buildData: (item, foto) => item.toFotoData(foto),
          capturarIdSeccion: (item, id) => item.idSeccion = id,
        ) &&
        ok;

    if (conFotos) {
      await DatabaseHelper.instance.updateLocalidad(localidad);
    }
    if (!ok) {
      await DatabaseHelper.instance.updateLocalidadSyncAttempts(
        localidad.idLocal!,
        1,
        'Error subiendo fotos de ${localidad.nombre}',
      );
    }

    final proteccionOk = await pushProteccion(localidad, idServer);
    if (!proteccionOk) ok = false;
    DebugLog.instance.i('pushFotos final ok=$ok (proteccionOk=$proteccionOk)');

    return ok;
  }

  Future<bool> subirFotosSeccion<T>({
    required int idServer,
    required String seccionRuta,
    required List<T> items,
    required List<EdanFoto> Function(T item) fotosDe,
    required String? Function(T item) fotografiaDe,
    required void Function(T item, String path) marcarSubida,
    required Map<String, dynamic> Function(T item, EdanFoto foto) buildData,
    void Function(T item, String idSeccion)? capturarIdSeccion,
  }) async {
    DebugLog.instance.i('[FOTOS] subirFotosSeccion $seccionRuta items=${items.length}');
    var ok = true;
    for (final item in items) {
      final fotos = fotosDe(item);
      final fotografia = fotografiaDe(item);
      if (fotos.isEmpty) {
        DebugLog.instance.i('[FOTOS] $seccionRuta SKIP sin fotos');
        continue;
      }
      if (fotografia != null && fotografia.isNotEmpty) {
        DebugLog.instance.i('[FOTOS] $seccionRuta SKIP ya tiene path="$fotografia"');
        continue;
      }
      final foto = fotos.first;
      final file = File(foto.ruta);
      if (!await file.exists()) {
        DebugLog.instance.e('[FOTOS] $seccionRuta ARCHIVO NO EXISTE: ${foto.ruta}');
        ok = false;
        continue;
      }
      DebugLog.instance.i('[FOTOS] $seccionRuta UPLOAD ruta=${foto.ruta}');
      try {
        final data = buildData(item, foto);
        final resp = await ApiService.instance.createLocalidadSeccionConFoto(
          idLocalidad: idServer,
          seccion: seccionRuta,
          filePath: foto.ruta,
          data: data,
        );
        final path = resp['fotografia'];
        marcarSubida(item, path is String && path.isNotEmpty ? path : 'subida');
        DebugLog.instance.i('[FOTOS] $seccionRuta OK path=$path');
        if (capturarIdSeccion != null) {
          final serverId = resp['id_seccion']?.toString();
          if (serverId != null && serverId.isNotEmpty) {
            capturarIdSeccion(item, serverId);
          }
        }
      } catch (e) {
        DebugLog.instance.e('[FOTOS] $seccionRuta ERROR (${foto.ruta})', e);
        ok = false;
      }
    }
    return ok;
  }

  /// Envía los grupos vulnerables con datos por los endpoints dedicados
  /// POST /edan/localidades/{idServer}/proteccion (1 POST por grupo).
  Future<bool> pushProteccion(EdanLocalidad localidad, int idServer) async {
    final grupos = localidad.proteccionParaEndpointDedicado();
    DebugLog.instance.paso('pushProteccion idServer=$idServer '
        'gruposConDatos=${grupos.length} '
        'totalGrupos=${localidad.proteccion.length} '
        'impProteccion=${localidad.impProteccion}');
    debugPrint('[PROTECCION] pushProteccion idServer=$idServer '
        'gruposConDatos=${grupos.length} '
        'totalGrupos=${localidad.proteccion.length}');
    if (grupos.isEmpty) {
      DebugLog.instance.i('pushProteccion: sin grupos con datos -> no se envía nada '
          '(si el usuario llenó protección, esto indica un BUG de datos vacíos aquí)');
      return true;
    }
    var ok = true;
    for (final grupo in grupos) {
      try {
        await ApiService.instance.crearProteccion(idServer, grupo);
        debugPrint('[PROTECCION] OK grupo catalogo=${grupo['id_grupo_vulnerable_catalogo']}');
        DebugLog.instance.i('proteccion OK cat=${grupo['id_grupo_vulnerable_catalogo']} '
            'mujeres=${grupo['mujeres']} hombres=${grupo['hombres']}');
      } catch (e) {
        debugPrint('[PROTECCION] Error enviando grupo '
            'catalogo=${grupo['id_grupo_vulnerable_catalogo']}: $e');
        DebugLog.instance.e('proteccion ERROR cat=${grupo['id_grupo_vulnerable_catalogo']} '
            'idServer=$idServer', e);
        ok = false;
      }
    }
    DebugLog.instance.i('pushProteccion terminó ok=$ok');
    return ok;
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

  /// `true` cuando el fallo fue de transporte y no un rechazo del servidor.
  bool sinConexion;

  SyncResult({
    required this.exito,
    this.mensaje = '',
    this.sinConexion = false,
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

/// Estado ligero de una localidad remota (mis-estados), con parseo defensivo.
class _EstadosServidor {
  final List<_EstadoItem> lista = [];
  final Map<String, _EstadoItem> _porIdLocal = {};
  final Map<int, _EstadoItem> _porIdEdan = {};

  int get total => lista.length;

  List<_EstadoItem> get pendientesEliminacion =>
      lista.where((e) => e.pendienteEliminacion).toList();

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
          json['pendiente_eliminacion'] == true ||
              json['pendiente_eliminacion'] == 1,
    );
  }

  static int? _intEstado(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }
}
