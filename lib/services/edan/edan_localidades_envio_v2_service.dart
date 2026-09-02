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

  /// Persiste a sus tablas (Modelo A) las secciones indicadas por [rutas].
  ///
  /// - [marcarEditado=true] (default): marca `editado=1` (candidatas a envío).
  ///   Se usa al guardar en el wizard cuando el usuario hizo cambios.
  /// - [marcarEditado=false]: marca `editado=0` y `insertada_en_server=1`.
  ///   Se usa tras pull del servidor (datos nuevos, sin cambios locales).
  Future<void> guardarSecciones(
    EdanLocalidad localidad,
    List<String> rutas, {
    bool marcarEditado = true,
  }) async {
    final idLocal = localidad.idLocal;
    if (idLocal == null || idLocal.isEmpty) return;
    for (final ruta in rutas) {
      final desc = EdanSeccionesRegistry.porRuta(ruta);
      final servicio = EdanSeccionesEnvioFactory.servicioDeRuta(ruta);
      if (desc == null || servicio == null) continue;
      try {
        final filas = servicio.filasGuardar(localidad);
        if (filas.isEmpty && desc.tipo == EdanSeccionTipo.unoAUno) {
          // "Vaciado" de 1:1: si existía fila sincronizada, coordinarla para
          // DELETE (el servidor es la ley; una 1:1 vacía no persiste fila).
          await _marcarVaciado11(desc.tablaSqlite, idLocal);
          debugPrint('[EnvioV2] guardarSecciones $ruta: vaciada (DELETE)');
          continue;
        }
        await _db.guardarFilasSeccion(
          desc.tablaSqlite,
          idLocal,
          filas,
          marcarEditado: marcarEditado,
        );
        debugPrint('[EnvioV2] guardarSecciones $ruta: ${filas.length} filas');
      } catch (e) {
        debugPrint('[EnvioV2] Error guardarSecciones $ruta: $e');
      }
    }
    if (marcarEditado) {
      await _db.marcarCabeceraEditada(idLocal);
    }
  }

  /// Coordina el "vaciado" de una sección 1:1: las filas existentes en SQLite
  /// de esa sección que ya estén insertadas en el servidor se marcan para
  /// DELETE (`marcado_borrar=1`); las que nunca se insertaron se eliminan
  /// localmente. Así el servidor deja de tener la fila y su flag cae a false.
  ///
  /// NOTA: solo se llama cuando `filas.isEmpty` (el usuario vació la sección).
  /// Con `?modo=comprimido`, si la sección vino del servidor con datos,
  /// `filas` no estará vacía y este método NO se ejecuta.
  Future<void> _marcarVaciado11(String tabla, String idLocal) async {
    final filasExistentes = await _db.leerFilasSeccion(tabla, idLocal);
    for (final fila in filasExistentes) {
      final idSeccion = fila['id_seccion']?.toString();
      if (idSeccion == null || idSeccion.isEmpty) continue;
      final insertada = fila['insertada_en_server'] == 1;
      if (insertada) {
        await _db.marcarFilaSeccionBorrada(tabla, idSeccion);
      } else {
        await _db.eliminarFilaSeccion(tabla, idSeccion);
      }
    }
  }

  /// Puebla las tablas de sección (Modelo A) desde el `datos_json` de una
  /// localidad recién descargada del servidor, con `editado=0` e
  /// `insertada_en_server=1` (datos nuevos del server, sin cambios locales).
  ///
  /// **Primero borra** todas las filas viejas de las 14 tablas de sección
  /// de esa localidad, para que solo queden las que el servidor devolvió
  /// con `?modo=comprimido` (las que tienen datos reales).
  ///
  /// Se llama tras un PULL exitoso (sincronizarCentral o
  /// recargarLocalidadesUsuario).
  Future<void> popularSeccionesDesdeServer(EdanLocalidad localidad) async {
    final idLocal = localidad.idLocal;
    if (idLocal == null || idLocal.isEmpty) return;

    // 1. Borrar todo lo viejo de las 14 tablas de sección.
    await _db.limpiarSeccionesLocalidad(idLocal);

    // 2. Escribir solo las secciones que vienen del server (las que tienen datos).
    for (final ruta in EdanSeccionesRegistry.rutasV2Todas()) {
      final desc = EdanSeccionesRegistry.porRuta(ruta);
      final servicio = EdanSeccionesEnvioFactory.servicioDeRuta(ruta);
      if (desc == null || servicio == null) continue;
      try {
        final filas = servicio.filasGuardar(localidad);
        if (filas.isEmpty) continue;
        await _db.guardarFilasSeccion(
          desc.tablaSqlite,
          idLocal,
          filas,
          marcarEditado: false,
        );
        // 3. Registrar fotos del server en foto_pendiente (para descarga offline).
        if (desc.usaFoto) {
          await _registrarFotosServer(localidad, filas);
        }
        debugPrint('[EnvioV2] popularSeccionesDesdeServer $ruta: ${filas.length} filas (editado=0)');
      } catch (e) {
        debugPrint('[EnvioV2] Error popularSeccionesDesdeServer $ruta: $e');
      }
    }
    await _db.sincronizarFlagEditadoCabecera(idLocal);
  }

  /// Registra en foto_pendiente las fotos que vienen del server (path /uploads/)
  /// para que sean descargadas por descargarFotosEdan().
  Future<void> _registrarFotosServer(
    EdanLocalidad localidad,
    List<Map<String, dynamic>> filas,
  ) async {
    final idLocal = localidad.idLocal;
    if (idLocal == null) return;
    for (final fila in filas) {
      final fotografia = fila['fotografia']?.toString();
      final idSeccion = fila['id_seccion']?.toString();
      if (fotografia == null || fotografia.isEmpty) continue;
      if (!fotografia.startsWith('/uploads/')) continue;
      if (idSeccion == null || idSeccion.isEmpty) continue;
      // Verificar si ya existe en foto_pendiente con el mismo path.
      final existente = await _db.buscarFotoPorSeccion(idSeccion);
      if (existente != null &&
          existente['path_servidor'].toString() == fotografia) {
        continue;
      }
      await _db.insertarFotoPendiente(
        idLocal: idLocal,
        idEdanLocalidad: localidad.idServer ?? localidad.idEdan,
        idSeccion: idSeccion,
        rutaLocalArchivo: '',
        lat: 0,
        lon: 0,
        pathServidor: fotografia,
      );
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
