import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/edan.dart';
import 'api_service.dart';
import 'database_helper.dart';
import 'edan_secciones_registry.dart';

/// Servicio de sincronización de localidades EDAN con la API v2 por secciones.
///
/// La API v2 (`/api/v2/edan/localidades`) sincroniza de forma incremental:
///   1. Cabecera primero (UPSERT por `id_local`) -> devuelve `id_edan_localidad`.
///   2. Cada sección en su propio POST (objeto único o array, cada fila con su
///      `id_seccion`).
///
/// Reglas de oro (Vía B, grupos mixtos foto / sin foto):
///   - Las fotos SIEMPRE se suben ANTES con `POST /upload` y solo el path
///     resultante (`/uploads/...`) viaja en el JSON de la sección.
///   - Cada fila lleva SIEMPRE su `fotografia` (path o null explícito). Si un
///     grupo tiene N ítems y solo algunos tienen foto, cada ítem individual
///     lleva su propia `fotografia` + `coordenada_lat/lon`.
///   - Foto => coordenadas GPS obligatorias por fila (422 si faltan).
class EdanLocalidadesSyncV2Service {
  EdanLocalidadesSyncV2Service({
    ApiService? api,
    DatabaseHelper? db,
  })  : _api = api ?? ApiService.instance,
        _db = db ?? DatabaseHelper.instance;

  final ApiService _api;
  final DatabaseHelper _db;

  /// Punto de entrada: sube fotos, envía cabecera y cada sección.
  /// Devuelve true si todo se sincronizó correctamente.
  ///
  /// Si [soloRutas] no es null, se suben SOLO esas secciones (rutas v2) más la
  /// cabecera, y al terminar se marcan como sincronizadas en el tracking por
  /// sección. Si es null se sube todo y se limpia el tracking completo.
  Future<bool> sincronizarLocalidad(
    EdanLocalidad localidad, {
    Set<String>? soloRutas,
  }) async {
    try {
      final idLocal = localidad.idLocal;
      if (idLocal == null || idLocal.isEmpty) {
        debugPrint('[SyncV2] Localidad sin id_local: ${localidad.nombre}');
        return false;
      }

      final rutas = soloRutas ?? EdanSeccionesRegistry.rutasV2Todas().toSet();

      // 1. Fotos primero (Vía B): subir pendientes de las rutas incluidas.
      await _subirFotosPendientes(localidad, rutas: rutas);

      // 1.5. Eliminar ítems marcados como eliminados localmente.
      await _eliminarSecciones(localidad);

      // 2. Cabecera primero -> id_edan_localidad.
      //    enviarLocalidadCabeceraV2 ya extrae body['data'], así que el
      //    mapa retornado contiene directamente id_edan_localidad.
      final cabecera = await _enviarCabecera(localidad);
      final idEdan = _intId(cabecera['id_edan_localidad']);
      if (idEdan == null) {
        debugPrint('[SyncV2] Cabecera no devolvió id_edan_localidad: $cabecera');
        return false;
      }

      final ok = await _enviarSecciones(localidad, idEdan, solo: rutas);

      // Persistir resultado (id_edan_localidad como referencia de servidor).
      localidad.idServer = idEdan;
      await _db.updateLocalidad(localidad);

      if (ok) {
        await _marcarRutasSincronizadas(idLocal, rutas);
      }

      return ok;
    } catch (e, st) {
      debugPrint('[SyncV2] Error sincronizando localidad ${localidad.nombre}: $e');
      debugPrint('[SyncV2] Stack: $st');
      return false;
    }
  }

  /// Marca en `localidad_seccion_sync` las rutas recién subidas como
  /// sincronizadas (modificada=0), más la cabecera.
  Future<void> _marcarRutasSincronizadas(
    String idLocal,
    Set<String> rutas,
  ) async {
    if (soloTodas(rutas)) {
      await _db.marcarTodasSeccionesSincronizadas(idLocal);
    } else {
      for (final ruta in rutas) {
        await _db.marcarSeccionSincronizada(idLocal, ruta);
      }
    }
    await _db.marcarSeccionSincronizada(idLocal, EdanSeccionesRegistry.cabecera);
  }

  bool soloTodas(Set<String> rutas) =>
      setEquals(rutas, EdanSeccionesRegistry.rutasV2Todas().toSet());

  // ========== Fotos (Vía B) ==========

  /// Sube las fotos locales pendientes de las secciones 1:N (solo las de
  /// [rutas] si se especifica) y guarda el path server (`/uploads/...`) en
  /// `item.fotografia`.
  Future<void> _subirFotosPendientes(
    EdanLocalidad localidad, {
    Set<String>? rutas,
  }) async {
    bool inlcuye(String ruta) => rutas == null || rutas.contains(ruta);
    if (inlcuye('salud-establecimientos')) {
      await _subirFotosSeccion(
        localidad.establecimientosSalud,
        (item) => item.fotos,
        (item) => item.fotografia,
        (item, path) => item.fotografia = path,
      );
    }
    if (inlcuye('danos-viales')) {
      await _subirFotosSeccion(
        localidad.danosViales,
        (item) => item.fotos,
        (item) => item.fotografia,
        (item, path) => item.fotografia = path,
      );
    }
    if (inlcuye('danos-infra-publica')) {
      await _subirFotosSeccion(
        localidad.danosInfraPublica,
        (item) => item.fotos,
        (item) => item.fotografia,
        (item, path) => item.fotografia = path,
      );
    }
    if (inlcuye('unidades-educativas')) {
      await _subirFotosSeccion(
        localidad.unidadesEducativas,
        (item) => item.fotos,
        (item) => item.fotografia,
        (item, path) => item.fotografia = path,
      );
    }
    if (inlcuye('danos-vivienda')) {
      await _subirFotosSeccion(
        localidad.danosVivienda,
        (item) => item.fotos,
        (item) => item.fotografia,
        (item, path) => item.fotografia = path,
      );
    }
    if (inlcuye('danos-agricultura')) {
      await _subirFotosSeccion(
        localidad.danosAgricultura,
        (item) => item.fotos,
        (item) => item.fotografia,
        (item, path) => item.fotografia = path,
      );
    }
    if (inlcuye('danos-pecuarios')) {
      await _subirFotosSeccion(
        localidad.danosPecuarios,
        (item) => item.fotos,
        (item) => item.fotografia,
        (item, path) => item.fotografia = path,
      );
    }
    if (inlcuye('infra-productiva')) {
      await _subirFotosSeccion(
        localidad.infraProductiva,
        (item) => item.fotos,
        (item) => item.fotografia,
        (item, path) => item.fotografia = path,
      );
    }
    if (inlcuye('servicios-basicos')) {
      await _subirFotosSeccion(
        localidad.serviciosBasicos,
        (item) => item.fotos,
        (item) => item.fotografia,
        (item, path) => item.fotografia = path,
      );
    }

    await _db.updateLocalidad(localidad);
  }

  /// Elimina en el servidor los ítems de secciones 1:N que el usuario borró
  /// localmente. Si no hay idEdan (no sincronizado aún), solo limpia la lista.
  Future<void> _eliminarSecciones(EdanLocalidad localidad) async {
    if (localidad.seccionesEliminadas.isEmpty) return;
    final idEdan = localidad.idServer;
    if (idEdan == null) {
      localidad.seccionesEliminadas.clear();
      return;
    }
    final pendientes = List<Map<String, String>>.from(
        localidad.seccionesEliminadas);
    for (final item in pendientes) {
      final ruta = item['ruta']!;
      final idSeccion = item['id_seccion']!;
      try {
        await _api.eliminarLocalidadSeccionV2(
          idLocalidad: idEdan,
          seccion: ruta,
          idSeccion: idSeccion,
        );
        localidad.seccionesEliminadas.removeWhere(
            (e) => e['id_seccion'] == idSeccion && e['ruta'] == ruta);
        debugPrint('[SyncV2] DELETE $idEdan/$ruta/$idSeccion OK');
      } catch (e) {
        debugPrint('[SyncV2] Error DELETE $idEdan/$ruta/$idSeccion: $e');
      }
    }
    if (localidad.seccionesEliminadas.isEmpty) {
      await _db.updateLocalidad(localidad);
    }
  }

  Future<void> _subirFotosSeccion<T>(
    List<T> items,
    List<EdanFoto> Function(T) fotosDe,
    String? Function(T) fotografiaDe,
    void Function(T, String) marcarSubida,
  ) async {
    for (final item in items) {
      final fotos = fotosDe(item);
      final fotografia = fotografiaDe(item);
      if (fotos.isEmpty) continue;
      if (fotografia != null && esPathServer(fotografia)) continue;

      final foto = fotos.first;
      final file = File(foto.ruta);
      if (!await file.exists()) {
        debugPrint('[SyncV2] Foto no existe: ${foto.ruta}');
        continue;
      }
      try {
        final resp = await _api.uploadFile(filePath: foto.ruta);
        final path = _extractUploadPath(resp);
        if (path != null && path.isNotEmpty) {
          marcarSubida(item, path);
          debugPrint('[SyncV2] Foto subida: $path');
        } else {
          debugPrint('[SyncV2] Upload sin path: $resp');
        }
      } catch (e) {
        debugPrint('[SyncV2] Error subiendo foto ${foto.ruta}: $e');
      }
    }
  }

  /// Detecta si un path ya es del servidor (no hay que volver a subirlo).
  static bool esPathServer(String path) => path.trimLeft().startsWith('/uploads/');

  String? _extractUploadPath(Map<String, dynamic> resp) {
    final data = resp['data'];
    if (data is Map) return data['path']?.toString();
    final p = resp['path'];
    if (p is String && p.isNotEmpty) return p;
    return null;
  }

  // ========== Cabecera ==========

  Future<Map<String, dynamic>> _enviarCabecera(EdanLocalidad localidad) async {
    final json = localidad.toApiJson();
    // La cabecera v2 NO lleva las secciones anidadas.
    json.remove('impacto_poblacion');
    json.remove('necesidad_primera_respuesta');
    json.remove('establecimientos_salud');
    json.remove('necesidad_salud');
    json.remove('danos_viales');
    json.remove('danos_infra_publica');
    json.remove('servicios_basicos');
    json.remove('unidades_educativas');
    json.remove('danos_vivienda');
    json.remove('danos_agricultura');
    json.remove('danos_pecuarios');
    json.remove('infra_productiva');
    json.remove('proteccion');
    json.remove('necesidad_humanitaria');
    // El servidor es autoridad de tiempo y de los flags de sync; no enviarlos
    // evita conflictos LWW con fechas locales viejas.
    json.remove('fecha_modificacion');
    json.remove('pendiente_actualizacion');
    json.remove('pendiente_eliminacion');
    json.remove('sincronizado');
    return _api.enviarLocalidadCabeceraV2(json);
  }

  // ========== Secciones ==========

  Future<bool> _enviarSecciones(
    EdanLocalidad localidad,
    int idEdan, {
    Set<String>? solo,
  }) async {
    var ok = true;
    bool incluye(String ruta) => solo == null || solo.contains(ruta);

    // 1:N con foto (Vía B, grupos mixtos).
    if (incluye('salud-establecimientos')) {
      ok = await _enviarSeccion1N(
            idEdan,
            'salud-establecimientos',
            localidad.establecimientosSalud.map((e) => _filaConFoto(e, () => e.toApiJson())).toList(),
          ) &&
          ok;
    }

    if (incluye('danos-viales')) {
      ok = await _enviarSeccion1N(
            idEdan,
            'danos-viales',
            localidad.danosViales.map((e) => _filaConFoto(e, () => e.toApiJson())).toList(),
          ) &&
          ok;
    }

    if (incluye('danos-infra-publica')) {
      ok = await _enviarSeccion1N(
            idEdan,
            'danos-infra-publica',
            localidad.danosInfraPublica.map((e) => _filaConFoto(e, () => e.toApiJson())).toList(),
          ) &&
          ok;
    }

    if (incluye('servicios-basicos')) {
      ok = await _enviarSeccion1N(
            idEdan,
            'servicios-basicos',
            localidad.serviciosBasicos.map((e) => _filaConFoto(e, () => e.toApiJson())).toList(),
          ) &&
          ok;
    }

    if (incluye('unidades-educativas')) {
      ok = await _enviarSeccion1N(
            idEdan,
            'unidades-educativas',
            localidad.unidadesEducativas.map((e) => _filaConFoto(e, () => e.toApiJson())).toList(),
          ) &&
          ok;
    }

    if (incluye('danos-vivienda')) {
      ok = await _enviarSeccion1N(
            idEdan,
            'danos-vivienda',
            localidad.danosVivienda.map((e) => _filaConFoto(e, () => e.toApiJson())).toList(),
          ) &&
          ok;
    }

    if (incluye('danos-agricultura')) {
      ok = await _enviarSeccion1N(
            idEdan,
            'danos-agricultura',
            localidad.danosAgricultura.map((e) => _filaConFoto(e, () => e.toApiJson())).toList(),
          ) &&
          ok;
    }

    if (incluye('danos-pecuarios')) {
      ok = await _enviarSeccion1N(
            idEdan,
            'danos-pecuarios',
            localidad.danosPecuarios.map((e) => _filaConFoto(e, () => e.toApiJson())).toList(),
          ) &&
          ok;
    }

    if (incluye('infra-productiva')) {
      ok = await _enviarSeccion1N(
            idEdan,
            'infra-productiva',
            localidad.infraProductiva.map((e) => _filaConFoto(e, () => e.toApiJson())).toList(),
          ) &&
          ok;
    }

    // impacto-poblacion (1:N, sin foto) -> cada grupo etario marcado.
    // v2: `id_grupo_etario` es la fuente de verdad; `rango` (string) es solo
    // compat v1 y resuelve por catálogo, así que se omite en escritura.
    // Solo se envía lo que el usuario marcó explícitamente (`marcado`), aunque
    // los campos numéricos estén vacíos.
    if (incluye('impacto-poblacion')) {
      final poblacion = localidad.impactoPoblacion
          .expand((p) => p.gruposEtarios.where((g) => g.marcado))
          .map((g) {
        final json = g.toApiJson();
        if (json['id_grupo_etario'] is int) json.remove('rango');
        return json;
      }).toList();
      debugPrint('[SyncV2] impacto-poblacion: ${poblacion.length} grupos marcados '
          '(impactoPoblacion=${localidad.impactoPoblacion.length})');
      ok = await _enviarSeccion1N(idEdan, 'impacto-poblacion', poblacion) && ok;
    }

    // 1:1 -> objeto único.
    if (incluye('primera-respuesta')) {
      final npr = localidad.necesidadPrimeraRespuesta;
      debugPrint('[SyncV2] primera-respuesta: ${npr != null ? 'presente' : 'null'}');
      ok = await _enviarSeccionUno(
            idEdan,
            'primera-respuesta',
            npr?.toJson(),
          ) &&
          ok;
    }
    if (incluye('necesidad-salud')) {
      final ns = localidad.necesidadSalud;
      debugPrint('[SyncV2] necesidad-salud: ${ns != null ? 'presente' : 'null'}');
      ok = await _enviarSeccionUno(
            idEdan,
            'necesidad-salud',
            ns?.toApiJson(),
          ) &&
          ok;
    }
    if (incluye('necesidad-humanitaria')) {
      final nh = localidad.necesidadHumanitaria;
      debugPrint('[SyncV2] necesidad-humanitaria: ${nh != null ? 'presente' : 'null'}');
      ok = await _enviarSeccionUno(
            idEdan,
            'necesidad-humanitaria',
            nh?.toJson(),
          ) &&
          ok;
    }

    // Protección (1:N, sin foto). Cada grupo con datos.
    if (incluye('proteccion')) {
      final proteccion = localidad.proteccionParaEndpointDedicado();
      ok = await _enviarSeccion1N(idEdan, 'proteccion', proteccion) && ok;
    }

    return ok;
  }

  /// Agrega `fotografia` y las coordenadas GPS por fila (Vía B). Siempre
  /// incluye `fotografia` (path server o null explícito) para no borrar la
  /// foto del servidor. `coordenada_lat/lon` viajan si el ítem las tiene
  /// (≠0); con foto son obligatorias por el 422 del backend.
  Map<String, dynamic> _filaConFoto(
    EdanFotoHolder item,
    Map<String, dynamic> Function() build,
  ) {
    final json = build();
    final foto = item.fotografia;
    final tienePathServer = foto is String && esPathServer(foto);
    json['fotografia'] = tienePathServer ? foto : null;
    final lat = item.coordenadaLat;
    final lon = item.coordenadaLon;
    if (lat != 0 || lon != 0) {
      json['coordenada_lat'] = lat;
      json['coordenada_lon'] = lon;
    } else {
      json['coordenada_lat'] = null;
      json['coordenada_lon'] = null;
    }
    return json;
  }

  Future<bool> _enviarSeccion1N(
    int idEdan,
    String seccion,
    List<Map<String, dynamic>> filas,
  ) async {
    if (filas.isEmpty) {
      debugPrint('[SyncV2] $seccion: sin filas, se omite envío');
      return false;
    }
    try {
      final payload = jsonEncode(filas);
      debugPrint('[SyncV2] POST /$seccion (${filas.length} filas, '
          '${payload.length} chars)');
      final resp = await _api.enviarLocalidadSeccionV2(
        idLocalidad: idEdan,
        seccion: seccion,
        payload: filas,
      );
      final huboErrores = _logErroresPorFila(seccion, resp);
      if (huboErrores) {
        debugPrint('[SyncV2] $seccion: servidor reportó errores, '
            'sección NO sincronizada');
        return false;
      }
      debugPrint('[SyncV2] $seccion: OK (${filas.length} filas enviadas)');
      return true;
    } catch (e) {
      debugPrint('[SyncV2] Error sección $seccion: $e');
      return false;
    }
  }

  Future<bool> _enviarSeccionUno(
    int idEdan,
    String seccion,
    Map<String, dynamic>? fila,
  ) async {
    if (fila == null || fila.isEmpty) return true;
    try {
      debugPrint('[SyncV2] POST 1:1 /$seccion');
      final resp = await _api.enviarLocalidadSeccionV2(
        idLocalidad: idEdan,
        seccion: seccion,
        payload: fila,
      );
      final huboErrores = _logErroresPorFila(seccion, resp);
      if (huboErrores) {
        debugPrint('[SyncV2] $seccion: servidor reportó errores');
        return false;
      }
      debugPrint('[SyncV2] $seccion: OK');
      return true;
    } catch (e) {
      debugPrint('[SyncV2] Error sección 1:1 $seccion: $e');
      return false;
    }
  }

  /// Retorna true si hubo errores por fila en la respuesta del servidor.
  bool _logErroresPorFila(String seccion, Map<String, dynamic> resp) {
    final data = resp['data'];
    final errores = data is Map && data['errors'] is List
        ? data['errors']
        : resp['errors'];
    if (errores is List && errores.isNotEmpty) {
      debugPrint('[SyncV2] $seccion TIENE ${errores.length} ERRORES POR FILA:');
      for (final err in errores) {
        debugPrint('  - ERROR $seccion: $err');
      }
      return true;
    }
    return false;
  }

  int? _intId(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }
}
