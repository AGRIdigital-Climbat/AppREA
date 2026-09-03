import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/edan.dart';
import '../database_helper.dart';
import '../edan_secciones_registry.dart';

/// Servicio de serialización del documento EDAN "todo-en-uno" (grupo v2).
///
/// El backend contrato (`DOCUMENTO_V2_SYNC`) define un JSON simétrico:
///   - GET /localidades/{id}/documento devuelve lo que POST/PUT aceptan.
///   - SIEMPRE COMPACTO: solo viajan las secciones con `imp_*`=true o con datos.
///   - Forma fija: 11 secciones SIEMPRE array, 3 SIEMPRE objeto.
///   - LWW por `fecha_modificacion` (top-level + por fila).
///   - Fotos: se suben primero (`/foto/subir`) y el JSON referencia el `path`.
///
/// Este servicio construye el documento desde el modelo en memoria
/// (`EdanLocalidad`, la fuente que edita el wizard y que nace de SQLite) y
/// deserializa el pull del servidor de vuelta al modelo.
class EdanDocumentoService {
  EdanDocumentoService._();
  static final EdanDocumentoService instance = EdanDocumentoService._();

  /// Lista de secciones array (1:N) presentes en el documento.
  static const List<String> seccionesArray = [
    'impacto_poblacion',
    'establecimientos_salud',
    'danos_viales',
    'danos_infra_publica',
    'servicios_basicos',
    'unidades_educativas',
    'danos_vivienda',
    'danos_agricultura',
    'danos_pecuarios',
    'infra_productiva',
    'proteccion',
  ];

  /// Lista de secciones objeto (1:1) presentes en el documento.
  static const List<String> seccionesObjeto = [
    'necesidad_primera_respuesta',
    'necesidad_salud',
    'necesidad_humanitaria',
  ];

  /// Mapeo sección → campo `imp_*` correspondiente. La fuente de verdad es
  /// `localidad_secciones_activas` en SQLite; aquí se traduce a los flags del
  /// modelo para decidir qué nodos incluir en el JSON.
  static const Map<String, String> seccionAFlag = {
    'impacto_poblacion':          'imp_impacto_poblacion',
    'establecimientos_salud':     'imp_salud_establecimientos',
    'danos_viales':               'imp_danos_viales',
    'danos_infra_publica':        'imp_danos_infra_publica',
    'servicios_basicos':          'imp_servicios_basicos',
    'unidades_educativas':        'imp_unidades_educativas',
    'danos_vivienda':             'imp_danos_vivienda',
    'danos_agricultura':          'imp_danos_agricultura',
    'danos_pecuarios':            'imp_danos_pecuarios',
    'infra_productiva':           'imp_infra_productiva',
    'proteccion':                 'imp_proteccion',
    'necesidad_primera_respuesta':'imp_primera_respuesta',
    'necesidad_salud':            'imp_necesidad_salud',
    'necesidad_humanitaria':      'imp_necesidad_humanitaria',
  };

  /// Construye el documento completo a enviar por POST/PUT `/documento`.
  ///
  /// SIEMPRE COMPACTO: lee secciones activas desde SQLite, recalcula los
  /// 22 flags `imp_*` y omite las secciones vacías.
  Future<Map<String, dynamic>> construirDocumento(EdanLocalidad localidad) async {
    // Lee las secciones activas desde SQLite (corazón del wizard).
    // Si la DB no está disponible (tests/migración), fallback a recalcular.
    List<String> activas = [];
    if (localidad.idLocal != null) {
      try {
        activas = await DatabaseHelper.instance.leerSeccionesActivas(localidad.idLocal!);
      } catch (_) {
        activas = [];
      }
    }

    // Si no hay registro en la tabla (migración/primera vez), fallback:
    // recalcula desde los flags del modelo para no romper nada.
    if (activas.isEmpty) {
      localidad.recalcularFlagsImpacto();
    } else {
      // Sobreescribe flags del modelo según secciones activas.
      final flags = EdanSeccionesRegistry.construirFlagsDesdeActivas(activas);
      localidad
        ..impImpactoPoblacion = flags['imp_impacto_poblacion'] ?? false
        ..impPrimeraRespuesta = flags['imp_primera_respuesta'] ?? false
        ..impSaludEstablecimientos = flags['imp_salud_establecimientos'] ?? false
        ..impNecesidadSalud = flags['imp_necesidad_salud'] ?? false
        ..impDanosViales = flags['imp_danos_viales'] ?? false
        ..impDanosInfraPublica = flags['imp_danos_infra_publica'] ?? false
        ..impServiciosBasicos = flags['imp_servicios_basicos'] ?? false
        ..impUnidadesEducativas = flags['imp_unidades_educativas'] ?? false
        ..impDanosVivienda = flags['imp_danos_vivienda'] ?? false
        ..impDanosAgricultura = flags['imp_danos_agricultura'] ?? false
        ..impDanosPecuarios = flags['imp_danos_pecuarios'] ?? false
        ..impInfraProductiva = flags['imp_infra_productiva'] ?? false
        ..impProteccion = flags['imp_proteccion'] ?? false
        ..impNecesidadHumanitaria = flags['imp_necesidad_humanitaria'] ?? false
        // Flags compuestos (legado):
        ..impPoblacion = flags['imp_poblacion'] ?? false
        ..impSalud = flags['imp_salud'] ?? false
        ..impInfraestructura = flags['imp_infraestructura'] ?? false
        ..impServicios = flags['imp_servicios'] ?? false
        ..impEducacion = flags['imp_educacion'] ?? false
        ..impVivienda = flags['imp_vivienda'] ?? false
        ..impAgropecuario = flags['imp_agropecuario'] ?? false
        ..impNecesidades = flags['imp_necesidades'] ?? false;
    }

    final doc = localidad.toApiJson();

    // Deduplicar arrays 1:N por id_seccion (safety net contra duplicados).
    // Además, un ítem SIN id_seccion que duplique el contenido de un ítem que
    // YA tiene id se descarta (copia que llegó en el pull; el id-having es la
    // fuente de verdad y el id solo se genera al guardar).
    for (final key in seccionesArray) {
      final v = doc[key];
      if (v is! List) continue;
      final idsVistos = <String>{};
      final contenidosVistos = <String>{};
      final dedup = <dynamic>[];
      for (final item in v) {
        if (item is! Map) {
          dedup.add(item);
          continue;
        }
        final id = item['id_seccion']?.toString() ?? '';
        final contenido = _huellaMapaConIdEmpty(key, item as Map<String, dynamic>);
        if (id.isNotEmpty) {
          if (idsVistos.add(id)) {
            dedup.add(item);
            if (contenido != null) contenidosVistos.add(contenido);
          }
        } else {
          if (contenido == null) {
            dedup.add(item);
          } else if (!contenidosVistos.contains(contenido) && idsVistos.add('c:$contenido')) {
            dedup.add(item);
          }
        }
      }
      doc[key] = dedup;
    }

    // ── Duplicados de catálogo + topes por sección (validación de envío) ──
    // Las listas 1:N pueden haber registrado la misma clave de catálogo en
    // filas distintas (id_seccion único pero mismo grupo). Antes de enviar se
    // deduplican por su id de catálogo y se acotan al máximo del catálogo.
    doc['impacto_poblacion'] = _deduplicarPorClave(
      doc['impacto_poblacion'],
      claves: const ['id_grupo_etario', 'id_grupo_etario_catalogo'],
      maxItems: 4,
      seccion: 'impacto_poblacion',
    );
    doc['proteccion'] = _deduplicarPorClave(
      doc['proteccion'],
      claves: const ['id_grupo_vulnerable_catalogo', 'id_grupo_vulnerable'],
      maxItems: 8,
      seccion: 'proteccion',
    );

    // Claves de sync que el servidor autoritativo; no se reenvían.
    doc.remove('pendiente_actualizacion');
    doc.remove('pendiente_eliminacion');
    doc.remove('sincronizado');

    // ── Filtrado por flags imp_* ──────────────────────────────────────
    // Solo incluimos secciones cuyo flag es true (marcadas en
    // localidad_secciones_activas → reconstruidas en los flags del modelo).
    for (final entry in seccionAFlag.entries) {
      final flagValue = doc[entry.value] ?? false;
      if (flagValue != true) {
        doc.remove(entry.key);
      }
    }

    // ── Secciones 1:1: serialización compacta ────────────────────────
    // Reemplaza el mapa completo (con todos los campos) por uno que solo
    // incluye campos con datos reales. Si el flag es true pero no tiene
    // datos, conservamos un objeto mínimo con id_seccion + fecha_modificacion
    // por seguridad (el backend espera la key presente cuando imp_*=true).
    for (final key in seccionesObjeto) {
      final flagKey = seccionAFlag[key];
      final flagValue = flagKey != null ? (doc[flagKey] ?? false) : false;
      final v = doc[key];
      if (v is! Map) {
        if (flagValue == true) {
          // Flag true pero el modelo no trajo nada: objeto mínimo.
          doc[key] = <String, dynamic>{};
        } else {
          doc.remove(key);
        }
        continue;
      }
      // Selecciona el toJsonCompacto correcto según la sección.
      switch (key) {
        case 'necesidad_primera_respuesta':
          final nr = localidad.necesidadPrimeraRespuesta;
          if (nr != null && nr.tieneDatos) {
            doc[key] = nr.toJson();
          } else if (flagValue == true && nr != null) {
            doc[key] = nr.toJson();
          } else {
            doc.remove(key);
          }
          break;
        case 'necesidad_salud':
          final ns = localidad.necesidadSalud;
          if (ns != null && ns.tieneDatos) {
            doc[key] = ns.toApiJson();
          } else if (flagValue == true && ns != null) {
            doc[key] = ns.toApiJson();
          } else {
            doc.remove(key);
          }
          break;
        case 'necesidad_humanitaria':
          final nh = localidad.necesidadHumanitaria;
          if (nh != null && nh.tieneDatos) {
            doc[key] = nh.toJsonCompacto();
          } else if (flagValue == true && nh != null) {
            doc[key] = nh.toJsonCompacto();
          } else {
            doc.remove(key);
          }
          break;
      }
    }

    // ── Secciones 1:N: arrays vacíos se conservan si el flag es true ──
    // Si el flag es true pero no hay datos, dejamos [] por seguridad
    // (el backend espera la key presente cuando imp_*=true).
    for (final key in seccionesArray) {
      final flagKey = seccionAFlag[key];
      final flagValue = flagKey != null ? (doc[flagKey] ?? false) : false;
      if (flagValue == true) {
        // Si la key no existe aún, la inicializamos como []
        if (!doc.containsKey(key)) {
          doc[key] = <dynamic>[];
        }
        // Si existe pero es un mapa (secciones 1:1 que quizás vinieron del
        // modelo), lo convertimos a lista vacía.
        else if (doc[key] is! List) {
          doc[key] = <dynamic>[];
        }
      } else {
        // Flag false: eliminamos la sección completamente.
        doc.remove(key);
      }
    }

    return doc;
  }

  /// Huella de contenido para un ítem de array 1:N en el documento, ignorando
  /// `id_seccion` y campos volátiles (fecha_modificacion, fotos locales).
  static String? _huellaMapaConIdEmpty(String key, Map<String, dynamic> item) {
    try {
      final copia = Map<String, dynamic>.from(item);
      copia.remove('id_seccion');
      copia.remove('fecha_modificacion');
      copia.remove('fecha_modificacion_local');
      return jsonEncode(copia);
    } catch (_) {
      return null;
    }
  }

  /// Deduplica y acota una lista 1:N del documento por su id de catálogo.
  ///
  /// Evita enviar el mismo grupo dos veces cuando el usuario registró filas
  /// con `id_seccion` distinto pero el mismo id de catálogo (ej. dos filas con
  /// `id_grupo_etario: 1`). También acota la lista al máximo del catálogo
  /// ([maxItems]) como limitación de control: los arrays no deben superar el
  /// número de grupos del catálogo (4 para impacto, 8 para protección).
  ///
  /// Retorna la lista pasada por referencia si no aplica (no es una lista o
  /// no hay claves de catálogo), o la lista deduplicada/acotada.
  List<dynamic> _deduplicarPorClave(
    dynamic raw, {
    required List<String> claves,
    required int maxItems,
    required String seccion,
  }) {
    if (raw is! List) return raw is List ? raw : <dynamic>[];
    final vistos = <String>{}; // ids de catálogo ya emitidos (primeras filas)
    final idsFila = <String>{}; // ids de fila ya emitidos (safety)
    final resultado = <dynamic>[];

    for (final item in raw) {
      if (item is! Map) {
        resultado.add(item);
        continue;
      }
      final idFila = item['id_seccion']?.toString() ?? '';
      if (idFila.isNotEmpty && !idsFila.add(idFila)) continue; // duplicado fila

      // Id de catálogo: prioriza el "catalogo", luego la FK local.
      String? idCatalogo;
      for (final k in claves) {
        final v = item[k];
        if (v != null) {
          idCatalogo = v.toString();
          break;
        }
      }
      // Solo deduplicar/acotar sobre filas que tienen id de catálogo; las filas
      // sin id (datos sueltos) se conservan siempre que no excedan el tope.
      if (idCatalogo != null && idCatalogo.isNotEmpty) {
        if (!vistos.add(idCatalogo)) continue; // mismo grupo repetido → se omite
      }
      if (resultado.length >= maxItems) continue; // tope del catálogo
      resultado.add(item);
    }

    if (resultado.length != raw.length) {
      debugPrint('[Documento] $seccion: ${resultado.length} de '
          '${raw.length} filas tras deduplicar/acotar por catálogo '
          '(máx $maxItems)');
    }
    return resultado;
  }

  /// Indica si una sección array del documento porta datos reales (para el
  /// pull): true si es una lista no vacía.
  static bool seccionConDatos(dynamic raw) => raw is List && raw.isNotEmpty;

  /// Deserializa el pull del servidor (`GET /documento`) de vuelta al modelo.
  /// El shape del documento coincide con `EdanLocalidad.fromJson` (la salida
  /// del backend ya usa estas claves; las secciones vacías vienen ausentes/None).
  static EdanLocalidad parsearDocumento(Map<String, dynamic> doc) {
    return EdanLocalidad.fromJson(doc);
  }

  /// Compara dos fechas ISO (LWW). Devuelve true si [a] es estrictamente
  /// más nueva que [b]. Si [a] no es parseable, devuelve false.
  static bool esMasNueva(String? a, String? b) {
    if (a == null || a.isEmpty) return false;
    if (b == null || b.isEmpty) return true;
    final da = DateTime.tryParse(a);
    final db = DateTime.tryParse(b);
    if (da == null) return false;
    if (db == null) return true;
    return da.isAfter(db);
  }

  /// Aplica el pull sobre el modelo local aplicando LWW a nivel de localidad
  /// (comparando `fecha_modificacion` top-level).
  ///
  /// El pull NO debe destruir lo que la app escribió localmente y aún no se ha
  /// subido. Por eso, además de la LWW top-level, se conservan los flags de
  /// edición y el `id_local` (clave de persistencia) del modelo local. La LWW
  /// **por fila** de las secciones vive en SQLite (`fecha_modificacion_local`)
  /// y el merge de filas por `id_seccion` lo resuelve [DatabaseHelper] al
  /// persistir; aquí solo se garantiza no pisar una localidad más nueva.
  static EdanLocalidad aplicarPull(EdanLocalidad local, EdanLocalidad server) {
    // Si la localidad local es MÁS NUEVA que la del servidor, se respeta la
    // local (no se pisa): el push posterior subirá sus cambios.
    if (esMasNueva(local.fechaModificacion, server.fechaModificacion)) {
      return local;
    }
    // El servidor es más nuevo o igual → se adopta su contenido, conservando
    // la clave de persistencia y el flag de edición local pendiente.
    server.idLocal = local.idLocal ?? server.idLocal;
    server.sincronizado = local.sincronizado;
    server.pendienteActualizacion = local.pendienteActualizacion;
    server.pendienteEliminacion = local.pendienteEliminacion;
    server.idEdanLocalidadEstado = local.idEdanLocalidadEstado ?? server.idEdanLocalidadEstado;
    server.estadoLocalidad = local.estadoLocalidad ?? server.estadoLocalidad;
    server.editado = local.editado;
    server.fechaModificacion = server.fechaModificacion ?? local.fechaModificacion;

    server.deduplicarSecciones();
    server.recalcularFlagsImpacto();
    return server;
  }

  /// Conveniencia: fecha ISO actual para la LWW si el modelo no la trae.
  static String _isoNow() => DateTime.now().toIso8601String();

  static String? fechaTop(EdanLocalidad localidad) =>
      localidad.fechaModificacion?.isNotEmpty == true
          ? localidad.fechaModificacion
          : _isoNow();

  /// Devuelve el JSON legible (para debug/registro) de un documento.
  static String jsonLegible(Map<String, dynamic> doc) => jsonEncode(doc);
}