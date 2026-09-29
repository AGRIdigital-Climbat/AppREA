import 'package:flutter/foundation.dart';

import '../../models/edan.dart';
import '../../models/id_seccion_helper.dart';
import '../database_helper.dart';
import '../edan_secciones_registry.dart';
import 'edan_secciones_envio_factory.dart';

/// Utilidades de persistencia a SQLite (Modelo A, tablas normalizadas por
/// sección) para el flujo "documento todo-en-uno".
///
/// Mantiene dos operaciones clave cuando el wizard y los pull del servidor
/// necesitan leer/escribir las tablas de sección como base de datos local
/// (el JSON del documento "nace de SQLite"):
///   - [guardarSecciones]: persiste las secciones editadas (editado=1).
///   - [popularSeccionesDesdeServer]: puebla las tablas desde un pull (editado=0).
class EdanLocalidadesEnvioV2Service {
  EdanLocalidadesEnvioV2Service({
    DatabaseHelper? db,
  }) : _db = db ?? DatabaseHelper.instance;

  final DatabaseHelper _db;

  /// Fuente de verdad única para los flags `imp_*` de un modelo: la tabla
  /// `localidad_secciones_activas` en SQLite. Sobreescribe los flags del
  /// [localidad] con el estado actual de las secciones activas (misma lógica
  /// que [EdanDocumentoService.construirDocumento], el wizard y la vista previa
  /// RESP). Si no hay idLocal o no hay secciones activas, recalcula los flags
  /// desde los datos ya cargados en el modelo.
  ///
  /// Con [unionConGuardados]=true (items de Inicio/Reportes y del listado UGR)
  /// los flags GRUESOS del modelo (los que guarda page01 en `datos_json`) se
  /// conservan en unión con los derivados de secciones activas: así el badge
  /// refleja lo marcado en page01 aunque la tabla de secciones activas no lo
  /// tenga (p. ej. por un pull de una versión vieja). La unión también se
  /// conserva en el fallback (sin idLocal o sin secciones activas): se
  /// recalculan los flags desde los datos del modelo y se mantienen en OR los
  /// gruesos previos (server/doc). La vista previa y el JSON usan el default
  /// (false) para seguir siendo 1:1.
  Future<void> aplicarFlagsDesdeSeccionesActivas(
    EdanLocalidad localidad, {
    bool unionConGuardados = false,
  }) async {
    final base = unionConGuardados
        ? {
            'imp_poblacion': localidad.impPoblacion,
            'imp_salud': localidad.impSalud,
            'imp_infraestructura': localidad.impInfraestructura,
            'imp_servicios': localidad.impServicios,
            'imp_educacion': localidad.impEducacion,
            'imp_vivienda': localidad.impVivienda,
            'imp_agropecuario': localidad.impAgropecuario,
            'imp_proteccion': localidad.impProteccion,
            'imp_necesidades': localidad.impNecesidades,
          }
        : const <String, bool>{};

    final idLocal = localidad.idLocal;
    if (idLocal == null || idLocal.isEmpty) {
      _aplicarUnionDesdeDatos(localidad, base);
      return;
    }
    final activas = await _db.leerSeccionesActivas(idLocal);
    if (activas.isEmpty) {
      _aplicarUnionDesdeDatos(localidad, base);
      return;
    }
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
      ..impPoblacion =
          (flags['imp_poblacion'] ?? false) || (base['imp_poblacion'] ?? false)
      ..impSalud =
          (flags['imp_salud'] ?? false) || (base['imp_salud'] ?? false)
      ..impInfraestructura = (flags['imp_infraestructura'] ?? false) ||
          (base['imp_infraestructura'] ?? false)
      ..impServicios = (flags['imp_servicios'] ?? false) ||
          (base['imp_servicios'] ?? false)
      ..impEducacion = (flags['imp_educacion'] ?? false) ||
          (base['imp_educacion'] ?? false)
      ..impVivienda = (flags['imp_vivienda'] ?? false) ||
          (base['imp_vivienda'] ?? false)
      ..impAgropecuario = (flags['imp_agropecuario'] ?? false) ||
          (base['imp_agropecuario'] ?? false)
      ..impProteccion = (flags['imp_proteccion'] ?? false) ||
          (base['imp_proteccion'] ?? false)
      ..impNecesidades = (flags['imp_necesidades'] ?? false) ||
          (base['imp_necesidades'] ?? false);
  }

  /// Fallback de [aplicarFlagsDesdeSeccionesActivas] cuando no hay idLocal o
  /// no hay secciones activas: recalcula los flags desde los datos ya cargados
  /// en el modelo y, si se pidió unión, conserva los gruesos previos (los que
  /// trae el server/doc, equivalentes a page01) en OR con los derivados.
  void _aplicarUnionDesdeDatos(
    EdanLocalidad localidad,
    Map<String, bool> base,
  ) {
    localidad.recalcularFlagsImpacto();
    if (base.isEmpty) return;
    localidad
      ..impPoblacion =
          localidad.impPoblacion || (base['imp_poblacion'] ?? false)
      ..impSalud = localidad.impSalud || (base['imp_salud'] ?? false)
      ..impInfraestructura = localidad.impInfraestructura ||
          (base['imp_infraestructura'] ?? false)
      ..impServicios =
          localidad.impServicios || (base['imp_servicios'] ?? false)
      ..impEducacion =
          localidad.impEducacion || (base['imp_educacion'] ?? false)
      ..impVivienda =
          localidad.impVivienda || (base['imp_vivienda'] ?? false)
      ..impAgropecuario =
          localidad.impAgropecuario || (base['imp_agropecuario'] ?? false)
      ..impProteccion =
          localidad.impProteccion || (base['imp_proteccion'] ?? false)
      ..impNecesidades =
          localidad.impNecesidades || (base['imp_necesidades'] ?? false);
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
        // Regla: id_seccion se genera SOLO aquí (al guardar) para ítems que
        // tengan datos y carezcan de id. Los ids del servidor/guardado previo
        // se conservan (nunca se regeneran).
        //
        // Para las secciones 1:N con "caso especial" (protección, impacto) el
        // catálogo muestra todos los grupos con id_seccion vacío. Al editar,
        // reutilizamos el id_seccion que YA existe en SQLite para ese grupo
        // (localidad + id de catálogo) en lugar de generar uno nuevo: así se
        // conserva el vínculo de sync (insertada_en_server=1) y no se rompe el
        // UPDATE del grupo original al modificar sus datos.
        await _reutilizarIdsCatalogo(ruta, desc, localidad, idLocal);
        servicio.asignarIdSeccionSiFalta(localidad, _prefijoDeRuta(ruta));
        _asignarId11SiFalta(localidad, ruta);
        final filas = servicio.filasGuardar(localidad);
        if (filas.isEmpty && desc.tipo == EdanSeccionTipo.unoAUno) {
          // "Vaciado" de 1:1: si existía fila sincronizada, coordinarla para
          // DELETE (el servidor es la ley; una 1:1 vacía no persiste fila).
          await _marcarVaciado11(desc.tablaSqlite, idLocal);
          debugPrint('[EnvioV2] guardarSecciones $ruta: vaciada (DELETE)');
          continue;
        }
        // Recoger los id_seccion que vamos a persistir para limpiar los sobrantes.
        final idsAConserver = filas
            .map((f) => f['id_seccion']?.toString())
            .where((id) => id != null && id.isNotEmpty)
            .cast<String>()
            .toSet();
        await _db.guardarFilasSeccion(
          desc.tablaSqlite,
          idLocal,
          filas,
          marcarEditado: marcarEditado,
        );
        // FIX Duplicacion: eliminar filas en SQLite que ya no estan en el
        // modelo (usuario las quito del array 1:N). Si ya estaban en el
        // servidor se marca marcado_borrar=1; si nunca se subieron se
        // eliminan directamente.
        if (desc.tipo == EdanSeccionTipo.unoAN) {
          await _db.limpiarFilasFaltantesEnSeccion(
            desc.tablaSqlite,
            idLocal,
            idsAConserver,
          );
        }
        debugPrint('[EnvioV2] guardarSecciones $ruta: ${filas.length} filas (${idsAConserver.length} IDs, cleanup 1:N)');
      } catch (e) {
        debugPrint('[EnvioV2] Error guardarSecciones $ruta: $e');
      }
    }
    if (marcarEditado) {
      await _db.marcarCabeceraEditada(idLocal);
    }
  }

  /// Reutiliza el `id_seccion` ya persistido en SQLite para las secciones de
  /// catálogo "caso especial" (protección e impacto en población).
  ///
  /// Estas secciones se muestran SIEMPRE completas (todos los grupos del
  /// catálogo) con `id_seccion` vacío en el modelo. Cuando el usuario edita un
  /// grupo que ya tenía fila guardada, el modelo no arrastra ese id, así que
  /// buscamos la fila existente por `(id_local, id de catálogo)` y volvemos a
  /// ponerle su id_seccion. Así se conserva el vínculo con el servidor
  /// (UPDATE en vez de INSERT duplicado) y no se pierde la edición.
  ///
  /// Solo actúa sobre ítems con datos (debeGuardar) y sin id; los ids del
  /// servidor/guardado previo ya presentes en el modelo NO se tocan.
  Future<void> _reutilizarIdsCatalogo(
    String ruta,
    EdanSeccionDescriptor desc,
    EdanLocalidad localidad,
    String idLocal,
  ) async {
    // Solo las dos secciones "1:N con rasgo especial": el resto genera id
    // nuevo al guardar (comportamiento normal) o ya conserva el suyo propio.
    if (ruta != 'proteccion' && ruta != 'impacto-poblacion') return;

    if (ruta == 'proteccion') {
      await _reutilizarIdsProteccion(desc.tablaSqlite, localidad, idLocal);
    } else {
      await _reutilizarIdsImpacto(desc.tablaSqlite, localidad, idLocal);
    }
  }

  Future<void> _reutilizarIdsProteccion(
    String tabla,
    EdanLocalidad localidad,
    String idLocal,
  ) async {
    final filas = await _db.leerFilasSeccion(tabla, idLocal);
    if (filas.isEmpty) return;
    // Mapa catálogo -> id_seccion de las filas ya guardadas.
    final idPorCatalogo = <int, String>{};
    for (final fila in filas) {
      final idCat = fila['id_grupo_vulnerable_catalogo'];
      final idSeccion = fila['id_seccion']?.toString();
      if (idCat is int && idSeccion != null && idSeccion.isNotEmpty) {
        idPorCatalogo[idCat] = idSeccion;
      }
    }
    if (idPorCatalogo.isEmpty) return;

    for (final g in localidad.proteccion) {
      final idCat = g.idGrupoVulnerableCatalogo;
      if (idCat == null) continue;
      if (g.idSeccion != null && g.idSeccion!.isNotEmpty) continue; // conservar
      final existente = idPorCatalogo[idCat];
      if (existente != null && existente.isNotEmpty) {
        g.idSeccion = existente;
      }
    }
  }

  Future<void> _reutilizarIdsImpacto(
    String tabla,
    EdanLocalidad localidad,
    String idLocal,
  ) async {
    final filas = await _db.leerFilasSeccion(tabla, idLocal);
    if (filas.isEmpty) return;
    final idPorEtario = <int?, String>{};
    for (final fila in filas) {
      final idGe = fila['id_grupo_etario'];
      final idSeccion = fila['id_seccion']?.toString();
      if (idGe is int && idSeccion != null && idSeccion.isNotEmpty) {
        idPorEtario[idGe] = idSeccion;
      }
    }
    if (idPorEtario.isEmpty) return;

    for (final p in localidad.impactoPoblacion) {
      for (final g in p.gruposEtarios) {
        final idGe = g.idGrupoEtario;
        if (idGe == null) continue;
        if (g.idSeccion != null && g.idSeccion!.isNotEmpty) continue;
        final existente = idPorEtario[idGe];
        if (existente != null && existente.isNotEmpty) {
          g.idSeccion = existente;
        }
      }
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

  /// Carga las secciones desde las tablas normalizadas SQLite y puebla
  /// los arrays del modelo. Se llama ANTES de `construirDocumento` para
  /// que `recalcularFlagsImpacto()` tenga los datos reales y los flags
  /// `imp_*` se calculen correctamente.
  ///
  /// Los flags `imp_*` vienen de `datos_json` (cabecera); este método
  /// rellena los arrays (ej. `danosViales`, `impactoPoblacion`) desde
  /// las tablas `seccion_*`.
  Future<void> cargarSeccionesDesdeSQLite(EdanLocalidad localidad, {List<String>? soloLasActivas}) async {
    final idLocal = localidad.idLocal;
    if (idLocal == null || idLocal.isEmpty) return;

    for (final desc in EdanSeccionesRegistry.secciones) {
      if (soloLasActivas != null && !soloLasActivas.contains(desc.rutaV2)) continue;
      try {
        var filas = await _db.leerFilasSeccion(desc.tablaSqlite, idLocal);
        if (filas.isEmpty) continue;
        // Deduplicar por id_seccion (safety net contra duplicados en SQLite).
        if (desc.tipo == EdanSeccionTipo.unoAN) {
          final idsVistos = <String>{};
          filas = filas.where((f) {
            final id = f['id_seccion']?.toString() ?? '';
            if (id.isEmpty || idsVistos.add(id)) return true;
            return false;
          }).toList();
        }
        final servicio = EdanSeccionesEnvioFactory.servicioDeRuta(desc.rutaV2);
        if (servicio == null) continue;
        _poblarSeccion(localidad, desc.llaveJson, filas);
      } catch (e) {
        debugPrint('[EnvioV2] Error cargarSeccionesDesdeSQLite ${desc.rutaV2}: $e');
      }
    }
  }

  /// Puebla un array del modelo [localidad] con la clave [llaveJson]
  /// a partir de filas leídas de la tabla SQLite.
  void _poblarSeccion(
    EdanLocalidad localidad,
    String llaveJson,
    List<Map<String, dynamic>> filas,
  ) {
    switch (llaveJson) {
      case 'impacto_poblacion':
        // Las filas SQLite son EdanGrupoEtario planas (una por grupo etario).
        // Se reconstruyen en EdanImpactoPoblacion agrupados por idSeccion.
        final grupos = filas
            .map((f) => EdanGrupoEtario.fromJson(f))
            .toList();
        final Map<String, List<EdanGrupoEtario>> porSeccion = {};
        for (final g in grupos) {
          final key = g.idSeccion ?? '';
          porSeccion.putIfAbsent(key, () => []).add(g);
        }
        localidad.impactoPoblacion = porSeccion.entries.map((e) {
          final items = e.value;
          return EdanImpactoPoblacion(
            idSeccion: e.key.isNotEmpty ? e.key : null,
            grupoEtario: items.isNotEmpty ? items.first.rango : '',
            fallecidos: items.fold(0, (s, g) => s + g.fallecidos),
            heridos: items.fold(0, (s, g) => s + g.heridos),
            desaparecidos: items.fold(0, (s, g) => s + g.desaparecidos),
            gruposEtarios: items,
          );
        }).toList();
        break;
      case 'establecimientos_salud':
        localidad.establecimientosSalud =
            filas.map((f) => EdanEstablecimientoSalud.fromJson(f)).toList();
        break;
      case 'danos_viales':
        localidad.danosViales =
            filas.map((f) => EdanDanoVial.fromJson(f)).toList();
        break;
      case 'danos_infra_publica':
        localidad.danosInfraPublica =
            filas.map((f) => EdanDanoInfraPublica.fromJson(f)).toList();
        break;
      case 'servicios_basicos':
        localidad.serviciosBasicos =
            filas.map((f) => EdanServicioBasicoDetalle.fromJson(f)).toList();
        break;
      case 'unidades_educativas':
        localidad.unidadesEducativas =
            filas.map((f) => EdanDanoUnidadEducativa.fromJson(f)).toList();
        break;
      case 'danos_vivienda':
        localidad.danosVivienda =
            filas.map((f) => EdanDanoVivienda.fromJson(f)).toList();
        break;
      case 'danos_agricultura':
        localidad.danosAgricultura =
            filas.map((f) => EdanDanoAgricultura.fromJson(f)).toList();
        break;
      case 'danos_pecuarios':
        localidad.danosPecuarios =
            filas.map((f) => EdanDanoPecuario.fromJson(f)).toList();
        break;
      case 'infra_productiva':
        localidad.infraProductiva =
            filas.map((f) => EdanInfraProductiva.fromJson(f)).toList();
        break;
      case 'proteccion':
        localidad.proteccion =
            filas.map((f) => EdanGrupoVulnerable.fromJson(f)).toList();
        break;
      case 'necesidad_primera_respuesta':
        if (filas.isNotEmpty) {
          final nuevo = EdanNecesidadPrimeraRespuesta.fromJson(filas.first);
          // Si el modelo ya traía la 1:1 con id_seccion (del server/EDAN), ese
          // id es la fuente de verdad; se conserva por encima de una fila SQLite
          // vieja que pudiera tener un id distinto (evita duplicados).
          final existe = localidad.necesidadPrimeraRespuesta;
          if (existe != null && existe.idSeccion != null
              && existe.idSeccion!.isNotEmpty) {
            nuevo.idSeccion = existe.idSeccion;
          }
          localidad.necesidadPrimeraRespuesta = nuevo;
        }
        break;
      case 'necesidad_salud':
        if (filas.isNotEmpty) {
          final nuevo = EdanNecesidadSalud.fromJson(filas.first);
          final existe = localidad.necesidadSalud;
          if (existe != null && existe.idSeccion != null
              && existe.idSeccion!.isNotEmpty) {
            nuevo.idSeccion = existe.idSeccion;
          }
          localidad.necesidadSalud = nuevo;
        }
        break;
      case 'necesidad_humanitaria':
        if (filas.isNotEmpty) {
          final nuevo = EdanNecesidadHumanitaria.fromJson(filas.first);
          final existe = localidad.necesidadHumanitaria;
          if (existe != null && existe.idSeccion != null
              && existe.idSeccion!.isNotEmpty) {
            nuevo.idSeccion = existe.idSeccion;
          }
          localidad.necesidadHumanitaria = nuevo;
        }
        break;
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

    // 0. Antes de limpiar, capturar los id_seccion que YA existen en SQLite
    //    para las secciones 1:1. Regla: id_seccion solo se genera al guardar,
    //    NUNCA al pull ni en la capa visual. Si el server trae una 1:1 sin
    //    id_seccion (dato legacy), conservamos el id previo local en lugar de
    //    generar uno nuevo; eso evita duplicar la fila en el server (el push
    //    vuelve a usar el mismo id y se hace UPDATE, no INSERT).
    final idsPrevios11 = await _capturarIds11Existentes(idLocal);

    // 1. Borrar todo lo viejo de las 14 tablas de sección.
    await _db.limpiarSeccionesLocalidad(idLocal);

    // 2. Escribir solo las secciones que vienen del server (las que tienen datos).
    for (final ruta in EdanSeccionesRegistry.rutasV2Todas()) {
      final desc = EdanSeccionesRegistry.porRuta(ruta);
      final servicio = EdanSeccionesEnvioFactory.servicioDeRuta(ruta);
      if (desc == null || servicio == null) continue;
      try {
        // Para 1:1 NO se generan ids al pull: se respeta el id que trae el
        // modelo (del server) o, si viene vacío, se reutiliza el id previo
        // local (si existe). Para 1:N el server siempre trae id_seccion y se
        // respeta; en ningún caso se genera un id nuevo aquí.
        if (desc.tipo == EdanSeccionTipo.unoAUno) {
          _aplicarId11DesdeServer(localidad, ruta, idsPrevios11);
        }
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

    // 4. Marcar en localidad_secciones_activas qué secciones trajo el server.
    final activas = <String>[];
    for (final ruta in EdanSeccionesRegistry.rutasV2Todas()) {
      final desc = EdanSeccionesRegistry.porRuta(ruta);
      if (desc == null) continue;
      final filas = await _db.leerFilasSeccion(
        desc.tablaSqlite,
        idLocal,
      );
      if (filas.isNotEmpty) activas.add(ruta);
    }
    await _db.reemplazarSeccionesActivas(idLocal, activas);

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
      final existente = await _db.buscarFotoV2PorSeccion(idSeccion);
      if (existente != null &&
          existente['path_servidor'].toString() == fotografia) {
        continue;
      }
      await _db.insertarFotoPendienteV2(
        idLocal: idLocal,
        idSeccion: idSeccion,
        rutaLocalArchivo: '',
        lat: 0,
        lon: 0,
        pathServidor: fotografia,
      );
    }
  }

  /// Prefijo de `id_seccion` por ruta v2 (para generar ids nuevos al guardar).
  static String _prefijoDeRuta(String ruta) {
    return switch (ruta) {
      'impacto-poblacion' || 'impacto_poblacion' => 'im',
      'salud-establecimientos' || 'establecimientos_salud' => 'es',
      'danos-viales' || 'danos_viales' => 'sv',
      'danos-infra-publica' || 'danos_infra_publica' => 'di',
      'servicios-basicos' || 'servicios_basicos' => 'sb',
      'unidades-educativas' || 'unidades_educativas' => 'ue',
      'danos-vivienda' || 'danos_vivienda' => 'dv',
      'danos-agricultura' || 'danos_agricultura' => 'ag',
      'danos-pecuarios' || 'danos_pecuarios' => 'pc',
      'infra-productiva' || 'infra_productiva' => 'ip',
      'proteccion' => 'po',
      'primera-respuesta' => 'nr',
      'necesidad-salud' => 'ns',
      'necesidad-humanitaria' => 'nh',
      _ => 'sx',
    };
  }

  /// Captura los `id_seccion` que ya existen en SQLite para las 3 secciones
  /// 1:1 de la localidad (ruta → id). Devuelve un mapa ruta->id; las rutas
  /// sin fila no se incluyen. NO genera ids.
  Future<Map<String, String>> _capturarIds11Existentes(String idLocal) async {
    final mapa = <String, String>{};
    const rutas11 = [
      'primera-respuesta',
      'necesidad-salud',
      'necesidad-humanitaria',
    ];
    for (final ruta in rutas11) {
      final desc = EdanSeccionesRegistry.porRuta(ruta);
      if (desc == null) continue;
      try {
        final filas = await _db.leerFilasSeccion(desc.tablaSqlite, idLocal);
        if (filas.isEmpty) continue;
        final id = filas.first['id_seccion']?.toString();
        if (id != null && id.isNotEmpty) mapa[ruta] = id;
      } catch (e) {
        debugPrint('[EnvioV2] capturarIds11 $ruta: $e');
      }
    }
    return mapa;
  }

  /// Reutiliza para las 1:1 el `id_seccion` previo local cuando el server la
  /// devuelve SIN id_seccion (dato legacy). Nunca genera un id nuevo.
  static void _aplicarId11DesdeServer(
    EdanLocalidad l,
    String ruta,
    Map<String, String> idsPrevios,
  ) {
    if (ruta == 'primera-respuesta') {
      final nr = l.necesidadPrimeraRespuesta;
      if (nr != null && (nr.idSeccion == null || nr.idSeccion!.isEmpty)) {
        nr.idSeccion = idsPrevios[ruta];
      }
    } else if (ruta == 'necesidad-salud') {
      final ns = l.necesidadSalud;
      if (ns != null && (ns.idSeccion == null || ns.idSeccion!.isEmpty)) {
        ns.idSeccion = idsPrevios[ruta];
      }
    } else if (ruta == 'necesidad-humanitaria') {
      final nh = l.necesidadHumanitaria;
      if (nh != null && (nh.idSeccion == null || nh.idSeccion!.isEmpty)) {
        nh.idSeccion = idsPrevios[ruta];
      }
    }
  }

  /// Asigna `id_seccion` a las secciones 1:1 (nr/ns/nh) al guardar, si tienen
  /// datos y carecen de id. Conserva cualquier id existente.
  static void _asignarId11SiFalta(EdanLocalidad l, String ruta) {
    switch (ruta) {
      case 'primera-respuesta':
        final nr = l.necesidadPrimeraRespuesta;
        if (nr != null && nr.tieneDatos &&
            (nr.idSeccion == null || nr.idSeccion!.isEmpty)) {
          nr.idSeccion = generarIdSeccion('nr');
        }
        break;
      case 'necesidad-salud':
        final ns = l.necesidadSalud;
        if (ns != null && ns.tieneDatos &&
            (ns.idSeccion == null || ns.idSeccion!.isEmpty)) {
          ns.idSeccion = generarIdSeccion('ns');
        }
        break;
      case 'necesidad-humanitaria':
        final nh = l.necesidadHumanitaria;
        if (nh != null && nh.tieneDatos &&
            (nh.idSeccion == null || nh.idSeccion!.isEmpty)) {
          nh.idSeccion = generarIdSeccion('nh');
        }
        break;
    }
  }
}