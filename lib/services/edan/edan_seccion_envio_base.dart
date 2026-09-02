import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/edan.dart';
import '../api_service.dart';
import '../database_helper.dart';
import '../edan_secciones_registry.dart';
import '../sync_debug_config.dart';
import '../sync_debug_collector.dart';

/// Mínimo que cualquier sección EDAN (Modelo A, v20) debe exponer a su servicio
/// de envío por sección: el descriptor de registro, la lista de filas del modelo
/// y, si usa foto, los accesores de binario/coordenadas.
abstract class EdanSeccionEnvioBase<T> {
  EdanSeccionEnvioBase({
    ApiService? api,
    DatabaseHelper? db,
  })  : _api = api ?? ApiService.instance,
        _db = db ?? DatabaseHelper.instance;

  final ApiService _api;
  final DatabaseHelper _db;

  ApiService get api => _api;
  DatabaseHelper get db => _db;

  /// Descriptor de la sección (ruta v2, tabla, tipo, usaFoto).
  EdanSeccionDescriptor get descriptor;

  /// Lista de ítems 1:N del modelo (lista vacía si la sección es 1:1).
  List<T> itemsDe(EdanLocalidad localidad) => const [];

  /// Construye el payload de la API para una fila del modelo (SIN fotografia:
  /// las fotos del carrete se reinyectan después en [_filaConFoto]).
  Map<String, dynamic> filaApi(T item) => {};

  /// Filtro opcional de 1:N: por defecto se guarda todo ítem. Las secciones
  /// con filtrado (impacto marcado, protección con datos) lo sobreescriben.
  bool debeGuardar(T item) => true;

  /// Produce las FILAS SQLITE (columnas = nombres de campo de la API) de la
  /// sección para persistirlas con `editado=1` al guardar. Para 1:N recorre
  /// [itemsDe]; para 1:1 se sobreescribe devolviendo una lista de una fila.
  List<Map<String, dynamic>> filasGuardar(EdanLocalidad localidad) {
    final filas = <Map<String, dynamic>>[];
    for (final item in itemsDe(localidad)) {
      if (!debeGuardar(item)) continue;
      final row = filaApi(item);
      if (descriptor.usaFoto) {
        final foto = fotografiaDe(item);
        if (foto != null) row['fotografia'] = foto;
        // coordenadas ya vienen en filaApi de las secciones con foto.
      }
      filas.add(row);
    }
    return filas;
  }

  // ========== Helper de carrete ==========

  /// Sube las fotos pendientes usando `foto/subir` (carrete).
  /// Lee de `foto_pendiente WHERE subida=0` (solo las que faltan, con retry).
  /// Después de subir, actualiza `fotografia` en la tabla de sección y en el
  /// modelo en memoria.
  Future<void> subirFotosPendientes(EdanLocalidad localidad) async {
    final pendientes = await _db.leerFotosPendientesSubida();
    if (pendientes.isEmpty) return;

    // Filtrar solo las fotos de esta sección y esta localidad.
    final fotosSeccion = pendientes.where((f) {
      return f['id_local'] == localidad.idLocal &&
          f['id_seccion'] != null &&
          (f['id_seccion'] as String).isNotEmpty;
    }).toList();
    if (fotosSeccion.isEmpty) return;

    final rutas = <String>[];
    final idsFotos = <String>[];
    final idSecciones = <String>[];

    for (final fotoRow in fotosSeccion) {
      final ruta = fotoRow['ruta_local_archivo']?.toString();
      final idSeccion = fotoRow['id_seccion']?.toString();
      final idFoto = fotoRow['id_foto']?.toString();
      if (ruta == null || idSeccion == null || idFoto == null) continue;

      final file = File(ruta);
      if (!await file.exists()) {
        await _db.marcarErrorSubida(idFoto, 'Archivo local no encontrado');
        continue;
      }

      rutas.add(ruta);
      idsFotos.add(idFoto);
      idSecciones.add(idSeccion);
    }

    if (rutas.isEmpty) return;

    final idEdan = localidad.idServer ?? localidad.idEdan;
    try {
      if (kSyncDebugMode) {
        SyncDebugCollector.instance.add(SyncApiEntry(
          fase: SyncDebugCollector.instance.currentPhase,
          metodo: 'PRE',
          endpoint: 'Preparar fotos ${descriptor.rutaV2}',
          requestBody: {'fotos': rutas.length, 'id_secciones': idSecciones},
          fotos: rutas.map((r) => r.split('/').last).toList(),
          localidadId: localidad.idLocal,
          seccion: descriptor.rutaV2,
        ));
      }
      final paths = await _api.subirFotosCarrete(
        files: rutas,
        idSecciones: idSecciones,
        idLocal: localidad.idLocal,
        idEdanLocalidad: idEdan,
      );

      for (var i = 0; i < idsFotos.length; i++) {
        final idFoto = idsFotos[i];
        final idSeccion = idSecciones[i];
        final path = paths[idSeccion];
        if (path != null && path.isNotEmpty) {
          // Marcar en foto_pendiente.
          await _db.marcarFotoSubida(idFoto, path);
          // Actualizar en la tabla de sección.
          await _db.marcarFotografiaSeccion(
            descriptor.tablaSqlite,
            localidad.idLocal!,
            idSeccion,
            path,
          );
        } else {
          await _db.marcarErrorSubida(idFoto, 'Server no devolvió path');
        }
      }
    } catch (e) {
      // Marcar error en todas las fotos de este batch.
      for (final idFoto in idsFotos) {
        await _db.marcarErrorSubida(idFoto, e.toString());
      }
      debugPrint('[${descriptor.rutaV2}] Error subirFotos: $e');
    }
  }

  // ========== Helper de envío ==========

  /// Envía las filas `editado=1` de esta sección a su endpoint v2.
  /// - 1:N → array directo (aunque haya un solo ítem). NUNCA `{"items":[]}`.
  /// - 1:1 → objeto único.
  /// Tras éxito marca cada fila `editado=0` (+ `insertada_en_server=1`).
  Future<bool> enviar(EdanLocalidad localidad) async {
    final idLocal = localidad.idLocal;
    final idEdan = localidad.idServer ?? localidad.idEdan;
    if (idLocal == null || idEdan == null) {
      debugPrint('[${descriptor.rutaV2}] sin idLocal/idEdan: omite envío');
      return false;
    }

    final filasEditadas = await _db.leerFilasEditadas(
      descriptor.tablaSqlite,
      idLocal,
    );
    if (filasEditadas.isEmpty) {
      debugPrint('[${descriptor.rutaV2}] sin filas editadas');
      return true;
    }

    // Asociar el path del carrete (foto_pendiente) a la fila enviar.
    await _asociarPathsCarrete(idLocal, filasEditadas);

    final payload = filasEditadas
        .map((row) => _filaConFoto(row, () => filaDesdeRow(row)))
        .toList();

    final body = descriptor.tipo == EdanSeccionTipo.unoAUno
        ? (payload.isNotEmpty ? payload.first : null)
        : payload;

    if (body == null) {
      debugPrint('[${descriptor.rutaV2}] sin payload');
      return true;
    }

    try {
      debugPrint('[${descriptor.rutaV2}] POST '
          '${descriptor.tipo == EdanSeccionTipo.unoAUno ? '1:1' : '1:N'} '
          '(${payload.length} filas)');
      if (kSyncDebugMode) {
        SyncDebugCollector.instance.add(SyncApiEntry(
          fase: SyncDebugCollector.instance.currentPhase,
          metodo: 'PRE',
          endpoint: 'Preparar sección ${descriptor.rutaV2}',
          requestBody: {'filas': payload.length, 'tipo': descriptor.tipo == EdanSeccionTipo.unoAUno ? '1:1' : '1:N'},
          localidadId: idLocal,
          seccion: descriptor.rutaV2,
        ));
      }
      await _api.enviarLocalidadSeccionV2(
        idLocalidad: idEdan,
        seccion: descriptor.rutaV2,
        payload: body,
      );
      for (final row in filasEditadas) {
        final idSeccion = row['id_seccion']?.toString();
        if (idSeccion != null && idSeccion.isNotEmpty) {
          await _db.marcarFilaSeccionSincronizada(
            descriptor.tablaSqlite,
            idSeccion,
          );
        }
      }
      debugPrint('[${descriptor.rutaV2}] OK');
      return true;
    } catch (e) {
      debugPrint('[${descriptor.rutaV2}] Error: $e');
      return false;
    }
  }

  /// Devuelve el payload de la API a partir de una fila SQLite. La
  /// implementación por defecto reutiliza [filaApi] sobre un ítem construido
  /// desde la fila, pero para la mayoría de secciones basta con [filaDesdeRow].
  /// Las subclases pueden sobreescribir si necesitan lógica específica.
  Map<String, dynamic> filaDesdeRow(Map<String, dynamic> row) {
    final json = Map<String, dynamic>.from(row);
    // Quitar banderas locales que no van a la API.
    json.remove('id_local');
    json.remove('id_edan_localidad');
    json.remove('editado');
    json.remove('marcado_borrar');
    json.remove('insertada_en_server');
    // Exponer la fecha local de edición como `fecha_modificacion` (LWW).
    // El servidor aplica GREATEST(fecha_modificacion, :enviada); si no se envía
    // usa NOW(). Se envía en ISO 8601 UTC (YYYY-MM-DDTHH:MM:SSZ / .sssZ).
    final fechaLocal = json.remove('fecha_modificacion_local');
    if (fechaLocal != null && fechaLocal.toString().isNotEmpty) {
      var iso = fechaLocal.toString();
      if (!iso.endsWith('Z') && !iso.contains('+') && iso.length > 10) {
        iso = '${iso}Z';
      }
      json['fecha_modificacion'] = iso;
    }
    // Mantener id_seccion (clave UPSERT)
    return json;
  }

  /// Reinyecta `fotografia` (path servidor o null explícito) y coordenadas GPS
  /// en una fila (Vía B, grupos mixtos). Siempre incluye `fotografia` para no
  /// borrar la foto del servidor; con foto, las coordenadas son obligatorias.
  Map<String, dynamic> _filaConFoto(
    Map<String, dynamic> row,
    Map<String, dynamic> Function() build,
  ) {
    final json = build();
    if (!descriptor.usaFoto) return json;
    final path = row['fotografia']?.toString();
    final tienePathServer = path != null && path.isNotEmpty && _esPathServer(path);
    json['fotografia'] = tienePathServer ? path : row['fotografia'];
    final lat = (row['coordenada_lat'] is num)
        ? (row['coordenada_lat'] as num).toDouble()
        : 0.0;
    final lon = (row['coordenada_lon'] is num)
        ? (row['coordenada_lon'] as num).toDouble()
        : 0.0;
    json['coordenada_lat'] = (lat != 0 || lon != 0) ? lat : null;
    json['coordenada_lon'] = (lat != 0 || lon != 0) ? lon : null;
    return json;
  }

  /// Asocia los paths del carrete (`foto_pendiente.path_servidor`) a las filas
  /// que van a enviarse, según `id_seccion`. Actualiza `fotografia` en BD y en
  /// las filas (manteniéndolas `editado=1`) sin borrar el binario pendiente.
  Future<void> _asociarPathsCarrete(
    String idLocal,
    List<Map<String, dynamic>> filasEditadas,
  ) async {
    final fotos = await _db.leerFotosPendientesSubida();
    final porIdSeccion = <String, Map<String, dynamic>>{};
    for (final foto in fotos) {
      final idSeccion = foto['id_seccion']?.toString();
      final path = foto['path_servidor']?.toString() ?? '';
      if (idSeccion == null || idSeccion.isEmpty || path.isEmpty) continue;
      porIdSeccion[idSeccion] = foto;
    }

    final aActualizar = <Map<String, dynamic>>[];
    for (final fila in filasEditadas) {
      final idSeccion = fila['id_seccion']?.toString();
      final foto = porIdSeccion[idSeccion];
      if (idSeccion == null || foto == null) continue;
      final path = foto['path_servidor'].toString();
      fila['fotografia'] = path;
      aActualizar.add(fila);
      await _db.marcarFotoSubida(foto['id_foto'].toString(), path);
    }
    if (aActualizar.isNotEmpty) {
      await _db.guardarFilasSeccion(
        descriptor.tablaSqlite,
        idLocal,
        aActualizar,
      );
    }
  }

  // ========== Accesores opcionales (para secciones con foto / 1:N) ==========

  List<EdanFoto> fotosDe(T item) => const [];
  String? fotografiaDe(T item) => null;
  void marcarSubida(T item, String path) {}
  String? idSeccionDe(T item) => null;

  static bool _esPathServer(String path) =>
      path.trimLeft().startsWith('/uploads/');
}
