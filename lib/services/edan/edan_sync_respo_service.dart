import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/edan.dart';
import '../api_service.dart';
import '../database_helper.dart';
import 'edan_localidades_envio_v2_service.dart';

/// Servicio de sincronización unificado para localidades EDAN (rol 7 RESP).
///
/// Flujo legacy de 3 fases:
///   FASE 1: Subir fotos pendientes (upload)
///   FASE 2: Push datos (DELETE → UPDATE → CREATE)
///   FASE 3: Pull del server (LWW comparison)
///
/// Se reemplazará por EdanSyncEngineV2 en la refactorización actual.
///
/// Puntos clave:
///   - `getLocalidades()` filtra `pendiente_eliminacion=0` → nunca sube lo que se va a borrar
///   - DELETE se ejecuta ANTES del push → no hay carrera
///   - Fotos se suben ANTES del push → paths disponibles en el JSON
///   - `kSyncDebugMode` controla el panel de debug visual
class EdanSyncRespoService {
  EdanSyncRespoService._();
  static final EdanSyncRespoService instance = EdanSyncRespoService._();

  final ValueNotifier<int> pendientes = ValueNotifier(0);
  final ValueNotifier<bool> sincronizando = ValueNotifier(false);
  final ValueNotifier<bool> sincronizandoMunicipio = ValueNotifier(false);

  // =====================================================================
  //  DOWNLOAD FOTOS DEL SERVER
  // =====================================================================

  Future<void> _descargarFotosPendientes() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fotosDir = Directory('${appDir.path}/edan_fotos');
      await fotosDir.create(recursive: true);

      final pendientes = await DatabaseHelper.instance
          .leerFotosPendientesDownloadV2();
      if (pendientes.isEmpty) {
        debugPrint('[FotosEDAN] No hay fotos pendientes de descarga');
        return;
      }
      debugPrint(
        '[FotosEDAN] ${pendientes.length} fotos pendientes de descarga',
      );

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
          await DatabaseHelper.instance.marcarFotoDescargadaV2(
            idFoto,
            savePath,
          );
          continue;
        }

        final result = await ApiService.instance.downloadImage(
          serverPath,
          savePath,
        );
        if (result != null) {
          await DatabaseHelper.instance.marcarFotoDescargadaV2(
            idFoto,
            savePath,
          );
          descargadas++;
        } else {
          await DatabaseHelper.instance.marcarFotoErrorV2(
            idFoto,
            'Error descargando $serverPath',
          );
          fallidas++;
        }
      }

      debugPrint(
        '[FotosEDAN] Fin: $descargadas descargadas, $fallidas fallidas',
      );
    } catch (e) {
      debugPrint('[FotosEDAN] Error: $e');
    }
  }

  // =====================================================================
  //  RECARGAR LOCALIDADES (LOGIN)
  // =====================================================================

  Future<void> recargarLocalidades({required int idUsuario}) async {
    if (sincronizandoMunicipio.value) return;
    sincronizandoMunicipio.value = true;
    try {
      debugPrint(
        '[SyncC] recargarLocalidades: Descargando localidades del usuario $idUsuario...',
      );
      final db = DatabaseHelper.instance;

      // PASO 1: Descargar catálogo de tipos de localidad y guardarlo en SQLite
      final Map<int, String> mapaTipos = {};
      try {
        final tipos = await ApiService.instance.getTipoLocalidad();
        await db.saveTiposLocalidad(
          tipos
              .map(
                (t) => {
                  'id_tipo_localidad': t.idTipoLocalidad,
                  'nombre': t.nombre,
                  'descripcion': t.descripcion,
                  'orden': t.orden,
                },
              )
              .toList(),
        );
        for (final t in tipos) {
          mapaTipos[t.idTipoLocalidad] = t.nombre;
        }
      } catch (e) {
        debugPrint('[SyncC] Error descargando catálogo tipo-localidad: $e');
        // Fallback: intentar cargar desde SQLite local
        try {
          final local = await db.getTiposLocalidadLocal();
          for (final row in local) {
            final id = row['id_tipo_localidad'] as int?;
            final nombre = row['nombre'] as String?;
            if (id != null && nombre != null) mapaTipos[id] = nombre;
          }
        } catch (_) {}
      }

      // PASO 2: Obtener mis reportes del servidor
      final lista = await ApiService.instance.getLocalidadesMisReportes(
        idUsuario: idUsuario,
        soloHuerfanas: true,
        limit: 500,
      );
      debugPrint('[SyncC] Recibidas ${lista.length} localidades del servidor');

      final sincV2 = EdanLocalidadesEnvioV2Service(db: db);

      for (final item in lista) {
        try {
          final localidad = EdanLocalidad.fromJson(item);
          final idLocal = localidad.idLocal;
          if (idLocal == null) continue;

          // Resolver tipoLocalidad desde catálogo usando idTipoLocalidad
          if (localidad.idTipoLocalidad != null &&
              mapaTipos.containsKey(localidad.idTipoLocalidad)) {
            localidad.tipoLocalidad = mapaTipos[localidad.idTipoLocalidad]!;
          } else if (localidad.tipoLocalidad.isEmpty &&
              localidad.idTipoLocalidad != null) {
            // Si tipoLocalidad vino vacío pero tenemos el id, resolver del mapa
            final nombre = mapaTipos[localidad.idTipoLocalidad];
            if (nombre != null) localidad.tipoLocalidad = nombre;
          }

          final existente = await db.getLocalidadByIdLocal(idLocal);
          if (existente != null) {
            // No pisar trabajo local pendiente: los cambios sin subir van por
            // el push (Fase 2b) y los marcados para eliminar se conservan.
            final modificadasLocales =
                await db.getSeccionesModificadas(idLocal);
            if (existente.editado ||
                !existente.sincronizado ||
                existente.pendienteEliminacion ||
                modificadasLocales.isNotEmpty) {
              debugPrint(
                '[SyncC] recargarLocalidades: salta $idLocal (dirty)',
              );
              continue;
            }
            _mergeSecciones(existente, localidad);
            localidad.idLocal = idLocal;
            localidad.deduplicarSecciones();
            await db.updateLocalidad(
              localidad,
              preserveFechaModificacion: existente.fechaModificacion,
            );
            if (localidad.idServer != null) {
              // Conservar la fecha del server (autoridad LWW): no sobrescribir
              // con DateTime.now() para no enmascarar futuras ediciones remotas.
              await db.markLocalidadAsSyncedConFecha(
                idLocal,
                localidad.idServer!,
                existente.fechaModificacion ??
                    DateTime.now().toIso8601String(),
              );
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
      debugPrint(
        '[SyncC] recargarLocalidades finalizado. Pendientes: ${pendientes.value}',
      );
    } catch (e) {
      debugPrint('[SyncC] Error general en recargarLocalidades: $e');
    } finally {
      sincronizandoMunicipio.value = false;
    }
  }

  // =====================================================================
  //  HELPERS
  // =====================================================================

  void _mergeSecciones(EdanLocalidad local, EdanLocalidad server) {
    server.establecimientosSalud = _fusionarSeccion(
      local.establecimientosSalud,
      server.establecimientosSalud,
    );
    server.danosViales = _fusionarSeccion(
      local.danosViales,
      server.danosViales,
    );
    server.danosInfraPublica = _fusionarSeccion(
      local.danosInfraPublica,
      server.danosInfraPublica,
    );
    server.unidadesEducativas = _fusionarSeccion(
      local.unidadesEducativas,
      server.unidadesEducativas,
    );
    server.danosVivienda = _fusionarSeccion(
      local.danosVivienda,
      server.danosVivienda,
    );
    server.danosAgricultura = _fusionarSeccion(
      local.danosAgricultura,
      server.danosAgricultura,
    );
    server.danosPecuarios = _fusionarSeccion(
      local.danosPecuarios,
      server.danosPecuarios,
    );
    server.infraProductiva = _fusionarSeccion(
      local.infraProductiva,
      server.infraProductiva,
    );
    server.serviciosBasicos = _fusionarSeccion(
      local.serviciosBasicos,
      server.serviciosBasicos,
    );
    server.proteccion = _fusionarSeccion(local.proteccion, server.proteccion);
    server.impactoPoblacion = _fusionarSeccion(
      local.impactoPoblacion,
      server.impactoPoblacion,
    );
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
    if (local is EdanEstablecimientoSalud &&
        server is EdanEstablecimientoSalud) {
      _aplicarServer(
        local,
        server.fotografia,
        server.coordenadaLat,
        server.coordenadaLon,
      );
    } else if (local is EdanDanoVial && server is EdanDanoVial) {
      _aplicarServer(
        local,
        server.fotografia,
        server.coordenadaLat,
        server.coordenadaLon,
      );
    } else if (local is EdanDanoInfraPublica &&
        server is EdanDanoInfraPublica) {
      _aplicarServer(
        local,
        server.fotografia,
        server.coordenadaLat,
        server.coordenadaLon,
      );
    } else if (local is EdanDanoUnidadEducativa &&
        server is EdanDanoUnidadEducativa) {
      _aplicarServer(
        local,
        server.fotografia,
        server.coordenadaLat,
        server.coordenadaLon,
      );
    } else if (local is EdanDanoVivienda && server is EdanDanoVivienda) {
      _aplicarServer(
        local,
        server.fotografia,
        server.coordenadaLat,
        server.coordenadaLon,
      );
    } else if (local is EdanDanoAgricultura && server is EdanDanoAgricultura) {
      _aplicarServer(
        local,
        server.fotografia,
        server.coordenadaLat,
        server.coordenadaLon,
      );
    } else if (local is EdanDanoPecuario && server is EdanDanoPecuario) {
      _aplicarServer(
        local,
        server.fotografia,
        server.coordenadaLat,
        server.coordenadaLon,
      );
    } else if (local is EdanInfraProductiva && server is EdanInfraProductiva) {
      _aplicarServer(
        local,
        server.fotografia,
        server.coordenadaLat,
        server.coordenadaLon,
      );
    } else if (local is EdanServicioBasicoDetalle &&
        server is EdanServicioBasicoDetalle) {
      _aplicarServer(
        local,
        server.fotografia,
        server.coordenadaLat,
        server.coordenadaLon,
      );
    }
  }

  void _aplicarServer(
    dynamic local,
    String? fotografia,
    double lat,
    double lon,
  ) {
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
      pendientes.value = await DatabaseHelper.instance
          .countLocalidadesPendientesSync();
    } catch (e) {
      debugPrint('Error recargando pendientes: $e');
    }
  }
}

