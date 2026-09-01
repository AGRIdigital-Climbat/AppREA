import 'package:flutter/foundation.dart';

import '../../models/edan.dart';
import '../api_service.dart';
import '../database_helper.dart';
import '../edan_secciones_registry.dart';
import 'edan_secciones_envio_factory.dart';
import 'edan_seccion_envio_base.dart';

/// Orquestador de envío EDAN por secciones (Modelo A, `/api/v2`, sin `/sync`).
///
/// Orden de envío (importante, fiel al Modelo A):
///   1. Cabecera primero → `id_edan_localidad` (UPSERT por `id_local`) y
///      PROPAGAR ese id a todas las secciones por `id_local` (puente offline→online).
///   2. Carrete de fotos (`foto/subir`) en primera instancia → paths servidos.
///   3. Cada sección con filas `editado=1` (función Dart dedicada por sección).
///   4. Borrados locales (`marcado_borrar=1`) → DELETE.
///
/// Al terminar marca `editado=0` en las filas enviadas. Si [soloRutas] es
/// distinto de null, se envían SOLO esas secciones (rutas v2) más la cabecera.
class EdanLocalidadesEnvioV2Service {
  EdanLocalidadesEnvioV2Service({
    ApiService? api,
    DatabaseHelper? db,
  })  : _api = api ?? ApiService.instance,
        _db = db ?? DatabaseHelper.instance;

  final ApiService _api;
  final DatabaseHelper _db;

  /// Punto de entrada: envía cabecera + fotos + secciones candidatas.
  /// Devuelve true si TODO lo solicitado se envió correctamente.
  Future<bool> enviarLocalidad(
    EdanLocalidad localidad, {
    Set<String>? soloRutas,
  }) async {
    final idLocal = localidad.idLocal;
    if (idLocal == null || idLocal.isEmpty) {
      debugPrint('[EnvioV2] Localidad sin id_local: ${localidad.nombre}');
      return false;
    }

    final rutas = soloRutas ?? EdanSeccionesRegistry.rutasV2Todas().toSet();

    // 1. Cabecera (UPSERT por id_local) -> id_edan_localidad y puente.
    final idEdan = await _enviarCabeceraYPropagar(localidad);
    if (idEdan == null) return false;

    // 2. Carrete de fotos en primera instancia (solo secciones del alcance).
    await _subirFotosCarrete(localidad, rutas: rutas);

    // 3. Secciones con editado=1 (función por sección).
    var ok = await _enviarSecciones(localidad, solo: rutas);

    // 4. Borrados locales.
    await _eliminarBorrados(localidad);

    // Persistir referencia de servidor.
    localidad.idServer = idEdan;
    await _db.updateLocalidad(localidad);

    return ok;
  }

  /// Persiste a sus tablas (Modelo A) las secciones indicadas por [rutas],
  /// marcándolas `editado=1` (candidatas a envío). Se usa al guardar en el
  /// wizard: solo se marcan las secciones tocadas por la página actual.
  Future<void> guardarSecciones(
    EdanLocalidad localidad,
    List<String> rutas,
  ) async {
    final idLocal = localidad.idLocal;
    if (idLocal == null || idLocal.isEmpty) return;
    for (final ruta in rutas) {
      final desc = EdanSeccionesRegistry.porRuta(ruta);
      final servicio = EdanSeccionesEnvioFactory.servicioDeRuta(ruta);
      if (desc == null || servicio == null) continue;
      try {
        final filas = servicio.filasGuardar(localidad);
        await _db.guardarFilasSeccion(desc.tablaSqlite, idLocal, filas);
        debugPrint('[EnvioV2] guardarSecciones $ruta: ${filas.length} filas');
      } catch (e) {
        debugPrint('[EnvioV2] Error guardarSecciones $ruta: $e');
      }
    }
  }

  // ========== Cabecera ==========

  Future<int?> _enviarCabeceraYPropagar(EdanLocalidad localidad) async {
    try {
      final json = localidad.toApiJson();
      // La cabecera v2 NO lleva las secciones anidadas.
      for (final s in EdanSeccionesRegistry.secciones) {
        json.remove(s.llaveJson);
      }
      // El servidor es autoridad de tiempo y de flags de sync.
      json.remove('fecha_modificacion');
      json.remove('pendiente_actualizacion');
      json.remove('pendiente_eliminacion');
      json.remove('sincronizado');

      final resp = await _api.enviarLocalidadCabeceraV2(json);
      final idEdan = _intId(resp['id_edan_localidad']);
      if (idEdan == null) {
        debugPrint('[EnvioV2] Cabecera sin id_edan_localidad: $resp');
        return null;
      }

      // Puente offline→online: propagar el id a TODAS las secciones.
      await _db.propagarIdEdanASecciones(localidad.idLocal!, idEdan);
      localidad.idServer = idEdan;
      return idEdan;
    } catch (e, st) {
      debugPrint('[EnvioV2] Error cabecera: $e');
      debugPrint('[EnvioV2] $st');
      return null;
    }
  }

  // ========== Carrete de fotos ==========

  Future<void> _subirFotosCarrete(
    EdanLocalidad localidad, {
    Set<String>? rutas,
  }) async {
    for (final ruta in EdanSeccionesRegistry.rutasV2Todas()) {
      if (rutas != null && !rutas.contains(ruta)) continue;
      final servicio = EdanSeccionesEnvioFactory.servicioDeRuta(ruta);
      final desc = EdanSeccionesRegistry.porRuta(ruta);
      if (servicio == null || desc == null || !desc.usaFoto) continue;
      try {
        await servicio.subirFotosPendientes(localidad);
      } catch (e) {
        debugPrint('[EnvioV2] Error carrete $ruta: $e');
      }
    }
  }

  // ========== Secciones ==========

  Future<bool> _enviarSecciones(
    EdanLocalidad localidad, {
    Set<String>? solo,
  }) async {
    var ok = true;
    for (final ruta in EdanSeccionesRegistry.rutasV2Todas()) {
      if (solo != null && !solo.contains(ruta)) continue;
      final servicio = EdanSeccionesEnvioFactory.servicioDeRuta(ruta);
      if (servicio == null) continue;
      final resultado = await _enviarSeccion(localidad, servicio);
      ok = resultado && ok;
    }
    return ok;
  }

  Future<bool> _enviarSeccion(
    EdanLocalidad localidad,
    EdanSeccionEnvioBase servicio,
  ) async {
    try {
      return await servicio.enviar(localidad);
    } catch (e) {
      debugPrint('[EnvioV2] Error sección ${servicio.descriptor.rutaV2}: $e');
      return false;
    }
  }

  // ========== Borrados ==========

  /// Envía DELETE al servidor por cada fila `marcado_borrar=1` y la elimina
  /// localmente. Después de propagar el puente ya se conoce el id_edan_localidad.
  Future<void> _eliminarBorrados(EdanLocalidad localidad) async {
    final idEdan = localidad.idServer ?? localidad.idEdan;
    final idLocal = localidad.idLocal;
    if (idLocal == null || idEdan == null) return;
    for (final tabla in EdanSeccionesRegistry.tablasSqlite()) {
      final filas = await _db.leerFilasBorradas(tabla, idLocal);
      for (final fila in filas) {
        final idSeccion = fila['id_seccion']?.toString();
        final ruta = _rutaDeTabla(tabla);
        if (idSeccion == null || ruta == null) continue;
        try {
          await _api.eliminarLocalidadSeccionV2(
            idLocalidad: idEdan,
            seccion: ruta,
            idSeccion: idSeccion,
          );
          await _db.eliminarFilaSeccion(tabla, idSeccion);
          debugPrint('[EnvioV2] DELETE $ruta/$idSeccion OK');
        } catch (e) {
          debugPrint('[EnvioV2] Error DELETE $ruta/$idSeccion: $e');
        }
      }
    }
  }

  String? _rutaDeTabla(String tabla) {
    for (final s in EdanSeccionesRegistry.secciones) {
      if (s.tablaSqlite == tabla) return s.rutaV2;
    }
    return null;
  }

  int? _intId(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }
}
