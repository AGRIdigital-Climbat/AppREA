import 'dart:io';

import 'package:flutter/foundation.dart';
import '../models/edan.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/database_helper.dart';
import '../services/debug_log.dart';

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
    try {
      final userId = AuthService.instance.userId;
      if (userId == null) {
        return SyncResult(
          exito: false,
          mensaje: 'Usuario no autenticado',
        );
      }

      final result = SyncResult(exito: true, mensaje: 'Sincronización deshabilitada por ahora');
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
