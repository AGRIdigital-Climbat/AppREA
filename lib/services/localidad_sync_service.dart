import 'dart:io';

import 'package:flutter/foundation.dart';
import '../models/edan.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/database_helper.dart';

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
      final lista = await ApiService.instance.getLocalidadesMisReportes(
        idUsuario: idUsuario,
        soloHuerfanas: true,
        limit: 500,
      );
      debugPrint('[recargarLocalidadesUsuario] Recibidas ${lista.length} localidades del servidor');
      for (final item in lista) {
        try {
          final localidad = EdanLocalidad.fromJson(item);
          final idLocal = localidad.idLocal;
          if (idLocal == null) {
            debugPrint('[recargarLocalidadesUsuario] Saltando localidad sin id_local: ${item['localidad']}');
            continue;
          }
          final existente = await DatabaseHelper.instance.getLocalidadByIdLocal(idLocal);
          if (existente != null) {
            if (existente.pendienteActualizacion || !existente.sincronizado) {
              debugPrint('[recargarLocalidadesUsuario] Saltando $idLocal (pendiente actualización=${existente.pendienteActualizacion}, sincronizado=${existente.sincronizado})');
              continue;
            }
            _preservarEncabezado(localidad, existente);
            _mergeSecciones(existente, localidad);
            localidad.idLocal = idLocal;
            await DatabaseHelper.instance.updateLocalidad(localidad);
            if (localidad.idServer != null) {
              await DatabaseHelper.instance.markLocalidadAsSynced(idLocal, localidad.idServer!);
            }
            debugPrint('[recargarLocalidadesUsuario] Actualizada localidad $idLocal (${localidad.nombre})');
          } else {
            await DatabaseHelper.instance.insertLocalidad(localidad, usuarioId: idUsuario);
            if (localidad.idServer != null) {
              await DatabaseHelper.instance.markLocalidadAsSynced(idLocal, localidad.idServer!);
            }
            debugPrint('[recargarLocalidadesUsuario] Insertada localidad $idLocal (${localidad.nombre})');
          }
        } catch (e, st) {
          debugPrint('[recargarLocalidadesUsuario] Error cargando localidad: $e');
          debugPrint('[recargarLocalidadesUsuario] Stack: $st');
        }
      }
      await recargarPendientes();
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
  }

  /// Fusiona una sección 1:N: conserva los ítems locales (con sus fotos) y
  /// copia de vuelta datos del servidor (fotografia server, coordenadas) que
  /// a la fila local le falten. Descarta los ítems del servidor que sean eco
  /// de un registro local con foto (duplicado por subida de fotos) y deja
  /// pasar los que no tienen contraparte local (adición real en servidor).
  List<T> _fusionarSeccion<T>(List<T> local, List<T> server) {
    if (server.isEmpty) return List<T>.of(local);
    if (local.isEmpty) return List<T>.of(server);

    final porClave = <String, List<int>>{};
    for (var i = 0; i < server.length; i++) {
      final clave = _claveItem(server[i]);
      if (clave.isEmpty) continue;
      porClave.putIfAbsent(clave, () => <int>[]).add(i);
    }

    final usados = <int>{};
    final resultado = <T>[];
    for (final itemLocal in local) {
      final clave = _claveItem(itemLocal);
      var emparejado = -1;
      if (clave.isNotEmpty) {
        for (final i in porClave[clave] ?? const <int>[]) {
          if (usados.add(i)) {
            emparejado = i;
            break;
          }
        }
      }
      if (emparejado >= 0) {
        _copiarDatosServer(itemLocal, server[emparejado]);
      }
      resultado.add(itemLocal);
    }

    for (final entry in porClave.entries) {
      for (final i in entry.value) {
        if (usados.contains(i)) continue;
        final extra = server[i];
        final localesMismaClave =
            local.where((l) => _claveItem(l) == entry.key).toList();
        if (localesMismaClave.isNotEmpty &&
            localesMismaClave.any((l) => _obtenerFotos(l).isNotEmpty)) {
          // Eco de un registro local con foto: no se importa, pero se
          // aprovecha su fotografia/coordenadas para que la fila local quede
          // sincronizada y no se vuelva a subir.
          _copiarDatosServer(localesMismaClave.first, extra);
        } else {
          resultado.add(extra);
        }
      }
    }
    return resultado;
  }

  bool _falta(String? valor) => valor == null || valor.isEmpty;

  List<EdanFoto> _obtenerFotos(dynamic item) {
    if (item is EdanEstablecimientoSalud) return item.fotos;
    if (item is EdanDanoVial) return item.fotos;
    if (item is EdanDanoInfraPublica) return item.fotos;
    if (item is EdanDanoUnidadEducativa) return item.fotos;
    if (item is EdanDanoVivienda) return item.fotos;
    if (item is EdanDanoAgricultura) return item.fotos;
    if (item is EdanDanoPecuario) return item.fotos;
    if (item is EdanInfraProductiva) return item.fotos;
    return <EdanFoto>[];
  }

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
    }
  }

  /// Clave de emparejamiento por campos base para detectar ecos duplicados
  /// que el servidor crea al subir fotos. Devuelve '' si no es reconocible.
  String _claveItem(dynamic item) {
    if (item is EdanEstablecimientoSalud) {
      return 'salud|${item.nombreEstablecimiento}|${item.comunidad}';
    }
    if (item is EdanDanoVial) {
      return 'vial|${item.viaPuente}|${item.tramo}';
    }
    if (item is EdanDanoInfraPublica) {
      return 'infra|${item.tipoEstructura}|${item.comunidad}';
    }
    if (item is EdanDanoUnidadEducativa) {
      return 'educacion|${item.nombreEstablecimiento}|${item.comunidad}';
    }
    if (item is EdanDanoVivienda) {
      return 'vivienda|${item.comunidad}';
    }
    if (item is EdanDanoAgricultura) {
      return 'agricultura|${item.tipoCultivo}';
    }
    if (item is EdanDanoPecuario) {
      return 'pecuario|${item.especie}|${item.raza}';
    }
    if (item is EdanInfraProductiva) {
      return 'productiva|${item.tipo}';
    }
    return '';
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

      await _pullLocalidades(userId, result);
      await _pushDeletions(result);
      await _pushLocalidades(userId, result);

      return result;
    } catch (e) {
      debugPrint('Error en sincronización de localidades: $e');
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
      pendientes.value = await DatabaseHelper.instance.countLocalidadesPendientesSync();
    } catch (e) {
      debugPrint('Error recargando pendientes de localidades: $e');
    }
  }

  Future<void> _pullLocalidades(int userId, SyncResult result) async {
    try {
      final prefs = await DatabaseHelper.instance.getLastSyncDate();
      final fechaDesde = prefs != null ? DateTime.fromMillisecondsSinceEpoch(prefs) : null;

      final localidadesRemotas = await ApiService.instance.getLocalidadesSyncPull(
        idUsuario: userId,
        fechaDesde: fechaDesde,
        skip: 0,
        limit: 100,
      );

      for (final locJson in localidadesRemotas) {
        final localidad = EdanLocalidad.fromJson(locJson);
        final idLocal = localidad.idLocal;
        if (idLocal == null) continue;

        final existente = await DatabaseHelper.instance.getLocalidadByIdLocal(idLocal);
        if (existente != null) {
          if (!existente.pendienteActualizacion && existente.sincronizado) {
            _preservarEncabezado(localidad, existente);
            _mergeSecciones(existente, localidad);
            await DatabaseHelper.instance.updateLocalidad(localidad);
            if (localidad.idServer != null) {
              await DatabaseHelper.instance.markLocalidadAsSynced(idLocal, localidad.idServer!);
            }
          }
          result.actualizados++;
        } else {
          await DatabaseHelper.instance.insertLocalidad(localidad, usuarioId: userId);
          if (localidad.idServer != null) {
            await DatabaseHelper.instance.markLocalidadAsSynced(idLocal, localidad.idServer!);
          }
          result.creados++;
        }
      }

      if (localidadesRemotas.isNotEmpty) {
        await DatabaseHelper.instance.saveLastSyncDate(DateTime.now().millisecondsSinceEpoch);
      }
    } catch (e) {
      debugPrint('Error en pull de localidades: $e');
      result.mensaje = 'Error al recibir localidades: ${e.toString()}';
      result.exito = false;
    }
  }

  Future<void> _pushDeletions(SyncResult result) async {
    try {
      final pendientes = await DatabaseHelper.instance.getLocalidadesPendingDeletion();

      for (final localidad in pendientes) {
        try {
          if (localidad.idServer != null) {
            await ApiService.instance.deleteLocalidad(localidad.idServer!);
          }
          await DatabaseHelper.instance.deleteLocalidad(localidad.idLocal!);
          result.eliminados++;
        } catch (e) {
          debugPrint('Error eliminando localidad ${localidad.idLocal}: $e');
          result.fallidos++;
        }
      }
    } catch (e) {
      debugPrint('Error en push de eliminaciones de localidades: $e');
      result.mensaje = 'Error al eliminar localidades: ${e.toString()}';
      result.exito = false;
    }
  }

  Future<void> _pushLocalidades(int userId, SyncResult result) async {
    try {
      final localidadesPendientes = await DatabaseHelper.instance.getUnsyncedLocalidades();
      
      if (localidadesPendientes.isEmpty) {
        return;
      }

      final localidadesJson = localidadesPendientes.map((loc) {
        final json = loc.toApiJson();
        json['id_usuario'] = userId;
        return json;
      }).toList();
      final porIdLocal = <String, EdanLocalidad>{
        for (final loc in localidadesPendientes)
          if (loc.idLocal != null) loc.idLocal!: loc,
      };

      final respuesta = await ApiService.instance.syncLocalidades(localidadesJson);

      final datos = respuesta['data'];
      final items = datos is List ? datos : <dynamic>[];

      for (final item in items) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final idLocal = m['id_local']?.toString();
        final aplicado = m['aplicado'] == true;
        final conflicto = m['conflicto'] == true;
        final tombstone = m['tombstone'] == true;

        // Tombstone: server deleted the localidad → delete from SQLite
        if (tombstone && idLocal != null) {
          await DatabaseHelper.instance.deleteLocalidad(idLocal);
          result.enviados++;
          continue;
        }

        // Conflicto LWW: server version is newer → adopt server version
        if (conflicto && idLocal != null) {
          final serverData = m['data'];
          if (serverData is Map) {
            await _adoptServerVersion(idLocal, Map<String, dynamic>.from(serverData), userId);
          }
          result.enviados++;
          continue;
        }

        if (aplicado && idLocal != null) {
          final idServer = _parseId(m['id_edan_localidad']);
          final localidad = porIdLocal[idLocal];

          // Adopt server's convergent localidad if provided
          final serverData = m['data'];
          if (serverData is Map && idServer != null) {
            await _adoptServerVersion(idLocal, Map<String, dynamic>.from(serverData), userId);
          }

          if (idServer != null) {
            final fotosOk = localidad == null ||
                await _pushFotos(localidad, idServer);
            if (fotosOk) {
              await DatabaseHelper.instance.markLocalidadAsSynced(idLocal, idServer);
              result.enviados++;
            } else {
              result.fallidos++;
            }
          } else {
            result.fallidos++;
          }
          continue;
        }

        if (idLocal != null) {
          final error = _extractError(m);
          final errorTexto = error.toLowerCase();
          final esColisionCodigo = errorTexto.contains('codigo') &&
              (errorTexto.contains('unique') ||
                  errorTexto.contains('duplic') ||
                  errorTexto.contains('ya existe'));
          final localidad = porIdLocal[idLocal];
          if (esColisionCodigo && localidad != null) {
            final reintentado = await _regenerarIdLocalYReintentar(localidad, userId);
            if (reintentado) {
              result.enviados++;
            } else {
              result.fallidos++;
            }
          } else {
            final intentos = _parseId(m['intentos']) ?? 0;
            await DatabaseHelper.instance.updateLocalidadSyncAttempts(
              idLocal,
              intentos + 1,
              error,
            );
            result.fallidos++;
          }
        } else {
          result.fallidos++;
        }
      }
    } catch (e) {
      debugPrint('Error en push de localidades: $e');
      result.mensaje = 'Error al enviar localidades: ${e.toString()}';
      result.exito = false;
    }
  }

  /// Adopta la versión convergente del servidor para una localidad.
  /// Reemplaza los datos locales con los del servidor y marca como sincronizado.
  Future<void> _adoptServerVersion(
    String idLocal,
    Map<String, dynamic> serverData,
    int userId,
  ) async {
    try {
      final serverLoc = EdanLocalidad.fromJson(Map<String, dynamic>.from(serverData));
      serverLoc.idLocal = idLocal;
      final existente = await DatabaseHelper.instance.getLocalidadByIdLocal(idLocal);
      if (existente != null) {
        _preservarEncabezado(serverLoc, existente);
        _mergeSecciones(existente, serverLoc);
      }
      await DatabaseHelper.instance.updateLocalidad(serverLoc);
      final idServer = serverLoc.idServer;
      if (idServer != null) {
        await DatabaseHelper.instance.markLocalidadAsSynced(idLocal, idServer);
      }
    } catch (e) {
      debugPrint('Error adoptando versión del servidor para $idLocal: $e');
    }
  }

  Future<bool> _regenerarIdLocalYReintentar(EdanLocalidad localidad, int userId) async {
    try {
      final nuevoIdLocal = '${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
      localidad.idLocal = nuevoIdLocal;
      await DatabaseHelper.instance.updateLocalidad(localidad);

      final json = localidad.toApiJson();
      json['id_usuario'] = userId;
      final respuesta = await ApiService.instance.syncLocalidades([json]);
      final datos = respuesta['data'];
      final items = datos is List ? datos : <dynamic>[];
      var aplicado = false;
      for (final item in items) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        if (m['aplicado'] == true) {
          aplicado = true;
          final idLocal = m['id_local']?.toString();
          final idServer = _parseId(m['id_edan_localidad']);
          if (idLocal != null && idServer != null) {
            final fotosOk = await _pushFotos(localidad, idServer);
            if (fotosOk) {
              await DatabaseHelper.instance.markLocalidadAsSynced(idLocal, idServer);
            } else {
              aplicado = false;
            }
          }
        }
      }
      return aplicado;
    } catch (e) {
      debugPrint('Error reintentando localidad tras colisión: $e');
      return false;
    }
  }

  /// Sube al servidor las fotos pendientes de las secciones 1:N de una
  /// localidad recién aplicada (una fila por item con foto). Devuelve true si
  /// no quedan fotos pendientes.
  Future<bool> _pushFotos(EdanLocalidad localidad, int idServer) async {
    var ok = true;
    ok = await _subirFotosSeccion(
          idServer: idServer,
          seccionRuta: 'salud-establecimientos',
          items: localidad.establecimientosSalud,
          fotosDe: (item) => item.fotos,
          fotografiaDe: (item) => item.fotografia,
          marcarSubida: (item, path) => item.fotografia = path,
          buildData: (item, foto) => item.toFotoData(foto),
        ) &&
        ok;
    ok = await _subirFotosSeccion(
          idServer: idServer,
          seccionRuta: 'danos-viales',
          items: localidad.danosViales,
          fotosDe: (item) => item.fotos,
          fotografiaDe: (item) => item.fotografia,
          marcarSubida: (item, path) => item.fotografia = path,
          buildData: (item, foto) => item.toFotoData(foto),
        ) &&
        ok;
    ok = await _subirFotosSeccion(
          idServer: idServer,
          seccionRuta: 'danos-infra-publica',
          items: localidad.danosInfraPublica,
          fotosDe: (item) => item.fotos,
          fotografiaDe: (item) => item.fotografia,
          marcarSubida: (item, path) => item.fotografia = path,
          buildData: (item, foto) => item.toFotoData(foto),
        ) &&
        ok;
    ok = await _subirFotosSeccion(
          idServer: idServer,
          seccionRuta: 'unidades-educativas',
          items: localidad.unidadesEducativas,
          fotosDe: (item) => item.fotos,
          fotografiaDe: (item) => item.fotografia,
          marcarSubida: (item, path) => item.fotografia = path,
          buildData: (item, foto) => item.toFotoData(foto),
        ) &&
        ok;
    ok = await _subirFotosSeccion(
          idServer: idServer,
          seccionRuta: 'danos-vivienda',
          items: localidad.danosVivienda,
          fotosDe: (item) => item.fotos,
          fotografiaDe: (item) => item.fotografia,
          marcarSubida: (item, path) => item.fotografia = path,
          buildData: (item, foto) => item.toFotoData(foto),
        ) &&
        ok;
    ok = await _subirFotosSeccion(
          idServer: idServer,
          seccionRuta: 'danos-agricultura',
          items: localidad.danosAgricultura,
          fotosDe: (item) => item.fotos,
          fotografiaDe: (item) => item.fotografia,
          marcarSubida: (item, path) => item.fotografia = path,
          buildData: (item, foto) => item.toFotoData(foto),
        ) &&
        ok;
    ok = await _subirFotosSeccion(
          idServer: idServer,
          seccionRuta: 'danos-pecuarios',
          items: localidad.danosPecuarios,
          fotosDe: (item) => item.fotos,
          fotografiaDe: (item) => item.fotografia,
          marcarSubida: (item, path) => item.fotografia = path,
          buildData: (item, foto) => item.toFotoData(foto),
        ) &&
        ok;
    ok = await _subirFotosSeccion(
          idServer: idServer,
          seccionRuta: 'infra-productiva',
          items: localidad.infraProductiva,
          fotosDe: (item) => item.fotos,
          fotografiaDe: (item) => item.fotografia,
          marcarSubida: (item, path) => item.fotografia = path,
          buildData: (item, foto) => item.toFotoData(foto),
        ) &&
        ok;

    final huboFotos = localidad.establecimientosSalud.any((i) => i.fotos.isNotEmpty) ||
        localidad.danosViales.any((i) => i.fotos.isNotEmpty) ||
        localidad.danosInfraPublica.any((i) => i.fotos.isNotEmpty) ||
        localidad.unidadesEducativas.any((i) => i.fotos.isNotEmpty) ||
        localidad.danosVivienda.any((i) => i.fotos.isNotEmpty) ||
        localidad.danosAgricultura.any((i) => i.fotos.isNotEmpty) ||
        localidad.danosPecuarios.any((i) => i.fotos.isNotEmpty) ||
        localidad.infraProductiva.any((i) => i.fotos.isNotEmpty);
    if (huboFotos) {
      await DatabaseHelper.instance.updateLocalidad(localidad);
    }
    if (!ok) {
      await DatabaseHelper.instance.updateLocalidadSyncAttempts(
        localidad.idLocal!,
        1,
        'Error subiendo fotos de ${localidad.nombre}',
      );
    }
    return ok;
  }

  Future<bool> _subirFotosSeccion<T>({
    required int idServer,
    required String seccionRuta,
    required List<T> items,
    required List<EdanFoto> Function(T item) fotosDe,
    required String? Function(T item) fotografiaDe,
    required void Function(T item, String path) marcarSubida,
    required Map<String, dynamic> Function(T item, EdanFoto foto) buildData,
  }) async {
    var ok = true;
    for (final item in items) {
      final fotos = fotosDe(item);
      if (fotos.isEmpty || fotografiaDe(item) != null) continue;
      final foto = fotos.first;
      final file = File(foto.ruta);
      if (!await file.exists()) {
        debugPrint('Foto no encontrada en $seccionRuta: ${foto.ruta}');
        ok = false;
        continue;
      }
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
      } catch (e) {
        debugPrint('Error subiendo foto en $seccionRuta (${foto.ruta}): $e');
        ok = false;
      }
    }
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

int? _parseId(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}

String _extractError(Map<String, dynamic> m) {
  final directo = m['error'];
  if (directo is String && directo.isNotEmpty) return directo;
  final data = m['data'];
  if (data is Map) {
    final ultimo = data['ultimo_error'];
    if (ultimo is String && ultimo.isNotEmpty) return ultimo;
  }
  return 'Error de sincronización';
}
