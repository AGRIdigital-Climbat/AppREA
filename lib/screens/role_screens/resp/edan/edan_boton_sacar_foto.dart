import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../config/api_config.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import '../../../../services/api_service.dart';
import '../../../../services/app_logger_ui.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/connectivity_service.dart';
import '../../../../services/database_helper.dart';
import '../../../../services/edan/edan_store.dart';
import '../../../../services/edan/edan_uuid_helper.dart';
import '../../../../services/edan_secciones_registry.dart';
import '../../../../services/image_service.dart';
import '../../../../services/location_service.dart';
import '../../../../services/permission_service.dart';
import 'edan_dialog_helper.dart';

/// Utilidades de captura de foto + coordenadas GPS para el wizard EDAN.
///
/// El flujo de respaldo por ítem se dispara desde la propia página (nunca
/// dentro de un diálogo): primero se captura el GPS con precisión < 30m y
/// luego la cámara.
class EdanBotonSacarFoto {
  /// Captura las coordenadas con precisión < 30m. Devuelve la [Position]
  /// o null si no se logró. Pensado para usarse desde la página (no un
  /// diálogo) en el flujo de respaldo por ítem.
  static Future<Position?> capturarCoordenadas(
    BuildContext context, {
    double precisionMinima = 30,
  }) async {
    final hasPermission = await PermissionService.requestLocationPermission();
    if (!hasPermission) {
      if (context.mounted) {
        PermissionService.showPermissionDeniedDialog(context, 'ubicación');
      }
      return null;
    }

    // LocationService ya reintenta (5 con red + 5 sin red). Aquí solo se
    // valida la precisión; si no se alcanza, se devuelve la mejor obtenida.
    final pos = await LocationService().getCurrentLocation();
    if (pos != null) {
      if (pos.accuracy <= precisionMinima) return pos;
      // Un segundo intento por si el primero fue marginal.
      final pos2 = await LocationService().getCurrentLocation();
      if (pos2 != null && pos2.accuracy < pos.accuracy) return pos2;
      return pos;
    }

    // Sin GPS: ofrecer captura manual en lugar de dejar el flujo colgado.
    if (context.mounted) {
      return await LocationService.manualLocationDialog(context);
    }
    return null;
  }

  /// Flujo de respaldo por ítem (Diseño C): captura coordenadas si faltan y
  /// siempre toma una foto nueva, guardando todo en [fotos]/coordenadas.
  /// Devuelve true si se completó el respaldo. Debe llamarse con el contexto
  /// de la página (nunca dentro de un diálogo).
  /// [onCoordenadasCapturadas] recibe las coordenadas finales para que la
  /// página las escriba en el ítem (coordenadaLat/coordenadaLon).
  static Future<bool> capturarRespaldo(
    BuildContext context, {
    required List<EdanFoto> fotos,
    required double latActual,
    required double lonActual,
    required void Function(double lat, double lon) onCoordenadasCapturadas,
    EdanStore? store,
    String? uuidRegistro,
    String? tipoEntidad,
    String? rutaSeccion,
  }) async {
    double lat = latActual;
    double lon = lonActual;
    double prec = 0;

    if (lat == 0 && lon == 0) {
      final pos = await capturarCoordenadas(context);
      if (pos == null) return false;
      lat = pos.latitude;
      lon = pos.longitude;
      prec = pos.accuracy;
    } else if (fotos.isNotEmpty) {
      prec = fotos.first.precision;
    }

    onCoordenadasCapturadas(lat, lon);
    return capturarFoto(
      fotos: fotos,
      latitud: lat,
      longitud: lon,
      precision: prec,
      store: store,
      uuidRegistro: uuidRegistro,
      tipoEntidad: tipoEntidad,
      rutaSeccion: rutaSeccion,
    );
  }

  /// Cambia la foto de un ítem que ya tiene una: **siempre** vuelve a
  /// capturar las coordenadas GPS (precisión < 30m) primero y luego toma la
  /// foto nueva, reemplazando la existente en [fotos].
  /// Devuelve true si se completó el cambio. Debe llamarse con el contexto
  /// de la página (nunca dentro de un diálogo).
  static Future<bool> cambiarFoto(
    BuildContext context, {
    required List<EdanFoto> fotos,
    required void Function(double lat, double lon) onCoordenadasCapturadas,
    EdanStore? store,
    String? uuidRegistro,
    String? tipoEntidad,
    String? rutaSeccion,
  }) async {
    final pos = await capturarCoordenadas(context);
    if (pos == null) return false;
    onCoordenadasCapturadas(pos.latitude, pos.longitude);
    return capturarFoto(
      fotos: fotos,
      latitud: pos.latitude,
      longitud: pos.longitude,
      precision: pos.accuracy,
      store: store,
      uuidRegistro: uuidRegistro,
      tipoEntidad: tipoEntidad,
      rutaSeccion: rutaSeccion,
    );
  }

  /// Abre el bottom sheet de respaldo de foto para un ítem.
  ///
  /// Flujo (seguridad): primero se obtienen y muestran las coordenadas GPS
  /// (precisión < [precisionMinima]); el botón verde "Sacar foto" queda
  /// deshabilitado hasta tener coordenadas válidas. Al tocarlo:
  /// - sin foto: captura una nueva foto y la guarda en [fotos].
  /// - con foto: abre un mini menú (Ver foto / Re-tomar foto / Cancelar).
  ///   "Re-tomar foto" vuelve a capturar coordenadas frescas y la foto nueva,
  ///   reemplazando la existente.
  ///
  /// Devuelve true si se tomó guardó una foto (nueva o reemplazada).
  /// [onCoordenadasCapturadas] recibe las coordenadas finales para que la
  /// página las escriba en el ítem (coordenadaLat/coordenadaLon).
  static Future<bool> mostrarSheetFoto(
    BuildContext context, {
    required List<EdanFoto> fotos,
    double latActual = 0,
    double lonActual = 0,
    double precisionMinima = 30,
    String? seccion,
    String? idLocal,
    String? idSeccion,
    int? idEdanLocalidad,
    required void Function(double lat, double lon) onCoordenadasCapturadas,
    void Function(String savedPath)? onFotoGuardada,
    EdanStore? store,
    String? uuidRegistro,
    String? tipoEntidad,
    String? rutaSeccion,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SheetFoto(
        fotos: fotos,
        latActual: latActual,
        lonActual: lonActual,
        precisionMinima: precisionMinima,
        seccion: seccion,
        idLocal: idLocal,
        idSeccion: idSeccion,
        onCoordenadasCapturadas: onCoordenadasCapturadas,
        onFotoGuardada: onFotoGuardada,
        store: store,
        uuidRegistro: uuidRegistro,
        tipoEntidad: tipoEntidad,
        rutaSeccion: rutaSeccion,
      ),
    );
    return saved ?? false;
  }

  /// Captura una foto con la cámara y la guarda en [fotos] con sus
  /// coordenadas. Utilizable también fuera del widget cuando la captura
  /// se hace con el diálogo ya cerrado.
  ///
  /// Con [store] (flujo V2) la foto recibe su `uuid_fotografia` propio y se
  /// registra en `fotografias`/`cola_fotos` aunque la fila dueña aún no esté
  /// guardada en la DB (corrige el hueco de exigir `idLocal`). Cambiar la foto
  /// persiste el borrado de la anterior. Sin [store] se conserva el flujo
  /// legacy (`foto_pendiente_v2` + subida en segundo plano) para UGR/IA.
  ///
  /// [rutaSeccion] (p. ej. `danos-agricultura`) resuelve el `tipo_entidad`
  /// canónico del CHECK (nombre de TABLA, no `llaveJson`); tiene prioridad
  /// sobre [tipoEntidad] y corrige el marcador local `'filas_seccion'`.
  static Future<bool> capturarFoto({
    required List<EdanFoto> fotos,
    required double latitud,
    required double longitud,
    required double precision,
    String? idLocal,
    String? idSeccion,
    int? idEdanLocalidad,
    EdanStore? store,
    String? uuidRegistro,
    String? tipoEntidad,
    String? rutaSeccion,
  }) async {
    final hasPermission = await PermissionService.requestCameraPermission();
    if (!hasPermission) {
      return false;
    }
    final imagen = await ImageService().takePhoto();
    if (imagen == null) return false;
    // Etapa 4: el uuid nace ANTES de copiar (el archivo se nombra con él).
    final photoUuid = EdanUuidHelper.generarUuidFotografia();
    String savedPath;
    try {
      savedPath = await ImageService().savePhotoLocally(imagen, photoUuid);
    } catch (_) {
      // Disco lleno o ruta inválida: no hay foto que registrar.
      return false;
    }

    // V2: si había una foto previa con uuid, persiste su borrado (cambiar la
    // foto reemplaza el registro, no duplica).
    if (store != null && fotos.isNotEmpty && fotos.first.uuidFotografia != null) {
      try {
        await store.borrarFoto(fotos.first.uuidFotografia!);
      } catch (e) {
        debugPrint('[Foto] Error al borrar foto previa: $e');
      }
    }

    fotos.clear();
    final foto = EdanFoto(
      ruta: savedPath,
      latitud: latitud,
      longitud: longitud,
      precision: precision,
      uuidFotografia: photoUuid,
    );
    fotos.add(foto);

    final target = (uuidRegistro ?? idSeccion) ?? '';
    if (store != null) {
      // V2: registra con uuid propio y encola para subir cuando la dueña
      // esté confirmada. No exige que la fila ya exista en la DB.
      if (target.isNotEmpty) {
        // El `tipo_entidad` válido sale de la ruta de sección; el marcador
        // local `'filas_seccion'` nunca viaja (el server lo rechaza con 400).
        final tipo = (rutaSeccion != null && rutaSeccion.isNotEmpty)
            ? EdanSeccionesRegistry.tipoEntidadDeRuta(rutaSeccion)
            : null;
        final tipoFinal = tipo ??
            (EdanSeccionesRegistry.esTipoEntidadValido(tipoEntidad)
                ? tipoEntidad
                : null);
        if (tipoFinal == null || tipoFinal.isEmpty) {
          debugPrint(
              '[Foto] tipo_entidad irresoluble (ruta=$rutaSeccion, tipo=$tipoEntidad): '
              'foto en memoria, pendiente de re-captura');
          return true;
        }
        try {
          await store.registrarFoto(foto, tipoFinal, target);
          await store.encolarFoto(foto);
        } catch (e) {
          debugPrint('[Foto] Error al registrar/enColar foto: $e');
        }
      }
      return true;
    }

    // Legacy (UGR/IA): registrar en foto_pendiente_v2 y subir en segundo plano.
    String? idFoto;
    if (idLocal != null && idSeccion != null) {
      try {
        idFoto = await DatabaseHelper.instance.insertarFotoPendienteV2(
          idLocal: idLocal,
          idSeccion: idSeccion,
          rutaLocalArchivo: savedPath,
          pathServidor: null,
          lat: latitud,
          lon: longitud,
        );
      } catch (e) {
        debugPrint('[FotoPendiente] Error al registrar foto: $e');
      }
    }

    if (idLocal != null && idSeccion != null &&
        ConnectivityService().isConnected) {
      _subirFotoEnSegundoPlano(
        savedPath,
        idLocal,
        idSeccion,
        idFoto,
        idEdanLocalidad,
      );
    }

    return true;
  }

  /// Garantiza que [item] tenga `id_seccion` (= `uuid_registro` de la fila V2)
  /// antes de asociarle una foto. Devuelve el uuid vigente; si el ítem aún no
  /// se ha guardado se le asigna uno nuevo, que `guardarFilas` reutilizará.
  static String asegurarUuidRegistro(EdanFotoHolder item) {
    final actual = item.idSeccion;
    // Solo un uuid canónico es identidad estable: un `id_seccion` legacy con
    // prefijo (`sb_…`, `po_…`) NO vale, porque `registrarFila` lo descarta y
    // regenera al persistir la fila, y la foto quedaría colgada de un id que
    // ninguna fila tendrá.
    if (actual != null &&
        actual.isNotEmpty &&
        EdanUuidHelper.esUuidValido(actual)) {
      return actual;
    }
    final nuevo = EdanUuidHelper.generarUuidRegistro();
    item.idSeccion = nuevo;
    return nuevo;
  }

  /// Rehidrata [fotos]/[fotografia] de cada ítem desde la tabla `fotografias`
  /// (V2). Útil al abrir una página: las fotos tomadas en otra sesión o
  /// bajadas por el pull vuelven a mostrarse como miniatura. Devuelve true si
  /// cambió algo (para repintar).
  static Future<bool> hidratarFotosDeItems(
    EdanStore? store,
    Iterable<EdanFotoHolder> items,
  ) async {
    if (store == null) return false;
    var cambio = false;
    for (final item in items) {
      final uuid = item.idSeccion;
      if (uuid == null || uuid.isEmpty) continue;
      try {
        final fotos = await store.cargarFotosDeEntidad('filas_seccion', uuid);
        if (fotos.isEmpty) continue;
        item.fotos
          ..clear()
          ..addAll(fotos);
        if ((item.fotografia ?? '').isEmpty) {
          item.fotografia = fotos.first.ruta;
        }
        cambio = true;
      } catch (e) {
        debugPrint('[Foto] Error al hidratar fotos de $uuid: $e');
      }
    }
    return cambio;
  }

  /// Purga las fotos V2 asociadas a una fila de sección al eliminar el ítem
  /// (registros en `fotografias`, cola de subida y archivos locales).
  static Future<void> purgarFotosDeItem(
    EdanStore? store,
    String? idSeccion,
  ) async {
    if (store == null || idSeccion == null || idSeccion.isEmpty) return;
    try {
      final fotos =
          await store.cargarFotosDeEntidad('filas_seccion', idSeccion);
      for (final f in fotos) {
        final uuid = f.uuidFotografia;
        if (uuid != null && uuid.isNotEmpty) {
          await store.borrarFoto(uuid);
        }
      }
    } catch (e) {
      debugPrint('[Foto] Error al purgar fotos de $idSeccion: $e');
    }
  }

  /// Sube una foto de respaldo en segundo plano (fire-and-forget, sin bloquear
  /// la UI). Al completar marca la foto pendiente como subida ([idFoto]) y
  /// actualiza la columna `fotografia` de la tabla de sección con el path del
  /// servidor. Si falla, registra el error y el sync la reintentará.
  static void _subirFotoEnSegundoPlano(
    String savedPath,
    String idLocal,
    String idSeccion,
    String? idFoto,
    int? idEdanLocalidad,
  ) async {
    try {
      final paths = await ApiService.instance.subirFotosCarrete(
        files: [savedPath],
        idSecciones: [idSeccion],
        idLocal: idLocal,
        idEdanLocalidad: idEdanLocalidad,
      );
      final serverPath = paths[idSeccion];
      if (serverPath == null || serverPath.isEmpty) {
        debugPrint('[Foto] Upload background sin path para $idSeccion');
        if (idFoto != null) {
          await DatabaseHelper.instance
              .marcarFotoErrorV2(idFoto, 'Server no devolvió path');
        }
        return;
      }
      debugPrint('[Foto] Upload background OK: $serverPath');
      if (idFoto != null) {
        await DatabaseHelper.instance.marcarFotoSubidaV2(idFoto, serverPath);
      }
      final tabla = await EdanSeccionesRegistry.buscarTablaPorIdSeccion(
        idSeccion,
        DatabaseHelper.instance,
      );
      if (tabla.isNotEmpty) {
        await DatabaseHelper.instance.marcarFotografiaSeccion(
          tabla,
          idLocal,
          idSeccion,
          serverPath,
        );
      }
    } catch (e) {
      debugPrint('[Foto] Upload background falló: $e');
      if (idFoto != null) {
        await DatabaseHelper.instance.marcarFotoErrorV2(idFoto, e.toString());
      }
    }
  }

  /// Visor a pantalla completa de la foto con zoom (InteractiveViewer),
  /// coordenadas y botón de borrado. Reutilizable fuera del widget; al borrar
  /// limpia [fotos] y notifica [onEliminada] para refrescar la UI. Con [store]
  /// el borrado se persiste (borrado lógico + purga de cola + archivo).
  static void verFotoCompleta(
    BuildContext context, {
    required List<EdanFoto> fotos,
    String? fotografia,
    double coordenadaLat = 0,
    double coordenadaLon = 0,
    String? seccion,
    /// Etiqueta del chip superior. En el wizard es `'Respaldo - $seccion'`;
    /// la Galería pasa el contexto completo (localidad · sección).
    String? titulo,
    VoidCallback? onEliminada,
    bool soloLectura = false,
    EdanStore? store,
  }) {
    final EdanFoto? foto = fotos.isNotEmpty ? fotos.first : null;
    final lat = foto != null && foto.latitud != 0 ? foto.latitud : coordenadaLat;
    final lon = foto != null && foto.longitud != 0 ? foto.longitud : coordenadaLon;
    final precision = foto?.precision ?? 0;
    // Ruta LOCAL compartible: la de la foto recién capturada o la de una
    // descarga previa (Galería). Si la imagen solo vive en el servidor no se
    // ofrece compartir (la Galería la baja primero al abrirla).
    final compartible = foto != null && _esArchivoLocal(foto.ruta)
        ? foto.ruta
        : (_esArchivoLocal(fotografia) ? fotografia! : null);
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4,
                  child: Center(
                    child: _imagenCompleta(
                      dialogCtx,
                      foto: foto,
                      fotografia: fotografia,
                    ),
                  ),
                ),
              ),
              if (seccion != null || titulo != null)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Container(
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        titulo ?? 'Respaldo - $seccion',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (compartible != null)
                              IconButton(
                                tooltip: 'Compartir foto',
                                icon: const Icon(
                                  Icons.ios_share,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                onPressed: () async {
                                  try {
                                    await SharePlus.instance.share(
                                      ShareParams(
                                        files: [XFile(compartible)],
                                      ),
                                    );
                                  } catch (e) {
                                    // Desktop/sin selector de compartir:
                                    // aviso, nunca rompe el visor.
                                    if (!dialogCtx.mounted) return;
                                    showAppSnackBar(
                                      dialogCtx,
                                      SnackBar(
                                        content: Text(
                                            'No se pudo compartir: $e'),
                                      ),
                                    );
                                  }
                                },
                              ),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 28,
                              ),
                              onPressed: () =>
                                  Navigator.of(dialogCtx).pop(),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (lat != 0 || lon != 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${lat.toStringAsFixed(4)}, '
                                  '${lon.toStringAsFixed(4)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (precision > 0)
                                Text(
                                  '±${precision.toStringAsFixed(0)}m',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              const SizedBox(width: 10),
                              if (foto != null && !soloLectura)
                                GestureDetector(
                                  onTap: () async {
                                    final ok = await confirmarEliminacion(
                                      dialogCtx,
                                      titulo: '¿Eliminar foto?',
                                      mensaje: 'Se eliminará la foto de respaldo de este ítem.',
                                    );
                                    if (!ok) return;
                                    Navigator.of(dialogCtx).pop();
                                    // V2: persiste el borrado (lógico + purga
                                    // de cola + archivo local).
                                    if (store != null &&
                                        foto.uuidFotografia != null) {
                                      try {
                                        await store
                                            .borrarFoto(foto.uuidFotografia!);
                                      } catch (e) {
                                        debugPrint(
                                            '[Foto] Error al borrar: $e');
                                      }
                                    }
                                    fotos.clear();
                                    onEliminada?.call();
                                  },
                                  child: const Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                    color: Colors.white,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _imagenCompleta(
    BuildContext context, {
    EdanFoto? foto,
    String? fotografia,
    String? servidor,
  }) {
    final server = servidor ?? ApiConfig.baseUrl;
    if (foto != null && foto.ruta.isNotEmpty) {
      final file = File(foto.ruta);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const _FotoRemotaNoDisponible(),
        );
      }
    }
    if (EdanBotonSacarFoto._esArchivoLocal(fotografia)) {
      return Image.file(
        File(fotografia!),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const _FotoRemotaNoDisponible(),
      );
    }
    if (fotografia != null && fotografia.isNotEmpty) {
      return Image.network(
        _fotoUrl(server, fotografia),
        fit: BoxFit.contain,
        headers: _fotoHeaders(),
        errorBuilder: (context, error, stackTrace) =>
            const _FotoRemotaNoDisponible(),
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
      );
    }
    return const _FotoRemotaNoDisponible();
  }

  static String _fotoUrl(String server, String path) =>
      '$server/upload/descargar/${Uri.encodeComponent(path)}';

  /// True si [ruta] apunta a un archivo **local existente**.
  ///
  /// Algunos modelos guardan la foto indistintamente como ruta local
  /// (p. ej. `EdanVivienda.fotografia` = "path local o URL servidor") o como
  /// path/URL del servidor. Se valida la existencia real del archivo —y no sólo
  /// el formato— porque en iOS el contenedor de la app cambia entre versiones
  /// de la app/SO y una ruta absoluta almacenada puede quedar obsoleta; en ese
  /// caso se cae al fallback remoto en vez de mostrar un error de carga.
  static bool _esArchivoLocal(String? ruta) {
    if (ruta == null || ruta.isEmpty) return false;
    if (ruta.contains('://')) return false;
    try {
      return File(ruta).existsSync();
    } catch (_) {
      return false;
    }
  }

  static Map<String, String> _fotoHeaders() {
    final token = AuthService.instance.currentToken?.accessToken;
    return token != null && token.isNotEmpty
        ? {'Authorization': 'Bearer $token'}
        : {};
  }
}

class _FotoRemotaNoDisponible extends StatelessWidget {
  const _FotoRemotaNoDisponible();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF3A3A3A),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              size: 40,
              color: Colors.white54,
            ),
            SizedBox(height: 8),
            Text(
              'Foto no disponible',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Miniatura de la foto de respaldo de un ítem (local primero, remota como
/// fallback). Al tocarla se abre el visor completo vía [EdanBotonSacarFoto.verFotoCompleta].
class EdanFotoMiniatura extends StatelessWidget {
  final EdanFoto? foto;
  final String? fotografia;
  final double? width;
  final double? height;
  final VoidCallback? onTap;

  /// Acción de retomar la foto (reemplaza la actual). Cuando se define se
  /// muestra un botón de refresh superpuesto en la esquina inferior derecha;
  /// tocar la miniatura sigue abriendo el visor.
  final VoidCallback? onRetomar;

  const EdanFotoMiniatura({
    super.key,
    this.foto,
    this.fotografia,
    this.width,
    this.height,
    this.onTap,
    this.onRetomar,
  });

  @override
  Widget build(BuildContext context) {
    Widget contenido;
    final ruta = foto?.ruta ?? '';
    if (ruta.trim().isNotEmpty && File(ruta).existsSync()) {
      contenido = Image.file(
        File(ruta),
        width: width,
        height: height,
        cacheWidth: 480,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    } else if (EdanBotonSacarFoto._esArchivoLocal(fotografia)) {
      // Ruta local guardada directamente en `fotografia` (sin `EdanFoto`).
      contenido = Image.file(
        File(fotografia!),
        width: width,
        height: height,
        cacheWidth: 480,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    } else if (fotografia != null && fotografia!.isNotEmpty) {
      contenido = Image.network(
        EdanBotonSacarFoto._fotoUrl(ApiConfig.baseUrl, fotografia!),
        width: width,
        height: height,
        cacheWidth: 480,
        fit: BoxFit.cover,
        headers: EdanBotonSacarFoto._fotoHeaders(),
        errorBuilder: (_, _, _) => _placeholder(),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _placeholder(),
      );
    } else {
      contenido = _placeholder();
    }

    final miniatura = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            contenido,
            if (onRetomar != null)
              Positioned(
                right: 2,
                bottom: 2,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRetomar,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: const Icon(
                      Icons.refresh,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (onTap == null) return miniatura;
    return GestureDetector(onTap: onTap, child: miniatura);
  }

  Widget _placeholder() {
    return Container(
      width: width,
      height: height,
      color: AppColors.background,
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported_outlined,
        size: 18,
        color: AppColors.textSecondary,
      ),
    );
  }
}

/// Bottom sheet de captura/edición de foto de respaldo de un ítem.
///
/// Flujo:
/// 1. Obtiene y muestra coordenadas GPS (o usa las ya guardadas del ítem).
/// 2. El botón verde "Sacar foto" se habilita solo con coordenadas válidas.
/// 3. Sin foto: captura y guarda una foto nueva.
///    Con foto: abre un mini menú (Ver foto / Re-tomar foto / Cancelar);
///    "Re-tomar foto" vuelve a capturar coordenadas frescas y reemplaza.
class _SheetFoto extends StatefulWidget {
  final List<EdanFoto> fotos;
  final double latActual;
  final double lonActual;
  final double precisionMinima;
  final String? seccion;
  final String? idLocal;
  final String? idSeccion;
  final void Function(double lat, double lon) onCoordenadasCapturadas;
  final void Function(String savedPath)? onFotoGuardada;
  final EdanStore? store;
  final String? uuidRegistro;
  final String? tipoEntidad;
  final String? rutaSeccion;

  const _SheetFoto({
    required this.fotos,
    required this.latActual,
    required this.lonActual,
    required this.precisionMinima,
    this.seccion,
    this.idLocal,
    this.idSeccion,
    required this.onCoordenadasCapturadas,
    this.onFotoGuardada,
    this.store,
    this.uuidRegistro,
    this.tipoEntidad,
    this.rutaSeccion,
  });

  @override
  State<_SheetFoto> createState() => _SheetFotoState();
}

class _SheetFotoState extends State<_SheetFoto> {
  bool _capturando = false;
  bool _reintentar = false;
  double? _lat;
  double? _lon;
  double _prec = 0;
  bool _sacando = false;

  // Windows: controllers para entrada manual de coordenadas
  final _latCtrl = TextEditingController();
  final _lonCtrl = TextEditingController();
  final _coordFormKey = GlobalKey<FormState>();
  static bool get _isWindows => Platform.isWindows;

  @override
  void initState() {
    super.initState();
    if (_isWindows) {
      // Windows: prellenar con coordenadas previas si existen
      if (widget.latActual != 0) {
        _latCtrl.text = widget.latActual.toStringAsFixed(6);
      }
      if (widget.lonActual != 0) {
        _lonCtrl.text = widget.lonActual.toStringAsFixed(6);
      }
    } else {
      // Móvil: siempre se solicitan coordenadas GPS frescas al abrir el
      // bottom sheet, sin reutilizar las ya guardadas en el ítem.
      _capturarCoordenadas();
    }
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lonCtrl.dispose();
    super.dispose();
  }

  bool _validarCoordenadasWindows() {
    if (!_coordFormKey.currentState!.validate()) return false;
    _lat = double.parse(_latCtrl.text.trim());
    _lon = double.parse(_lonCtrl.text.trim());
    _prec = 10.0;
    return true;
  }

  Future<void> _capturarCoordenadas() async {
    if (_capturando) return;
    setState(() {
      _capturando = true;
      _reintentar = false;
    });
    final pos = await EdanBotonSacarFoto.capturarCoordenadas(
      context,
      precisionMinima: widget.precisionMinima,
    );
    if (!mounted) return;
    if (pos != null) {
      setState(() {
        _lat = pos.latitude;
        _lon = pos.longitude;
        _prec = pos.accuracy;
        _capturando = false;
      });
    } else {
      setState(() {
        _reintentar = true;
        _capturando = false;
      });
    }
  }

  /// Devuelve true si se completó una captura (nueva o reemplazada) con
  /// coordenadas frescas [lat]/[lon].
  Future<bool> _tomarFoto() async {
    // Windows: leer coordenadas de los campos de texto + file picker
    if (_isWindows) {
      if (!_validarCoordenadasWindows()) return false;
      setState(() => _sacando = true);
      final ok = await EdanBotonSacarFoto.capturarFoto(
        fotos: widget.fotos,
        latitud: _lat!,
        longitud: _lon!,
        precision: _prec,
        idLocal: widget.idLocal,
        idSeccion: widget.idSeccion,
        store: widget.store,
        uuidRegistro: widget.uuidRegistro,
        tipoEntidad: widget.tipoEntidad,
        rutaSeccion: widget.rutaSeccion,
      );
      if (!mounted) return false;
      setState(() => _sacando = false);
      if (ok) {
        widget.onCoordenadasCapturadas(_lat!, _lon!);
        if (widget.fotos.isNotEmpty) {
          widget.onFotoGuardada?.call(widget.fotos.first.ruta);
        }
        Navigator.of(context).pop(true);
      }
      return ok;
    }

    // Móvil: siempre se recapturan coordenadas GPS frescas justo antes de
    // tomar la foto.
    setState(() => _capturando = true);
    final pos = await EdanBotonSacarFoto.capturarCoordenadas(
      context,
      precisionMinima: widget.precisionMinima,
    );
    if (!mounted) return false;
    if (pos == null) {
      setState(() {
        _capturando = false;
        _reintentar = true;
      });
      return false;
    }
    setState(() {
      _lat = pos.latitude;
      _lon = pos.longitude;
      _prec = pos.accuracy;
      _capturando = false;
    });
    final lat = _lat;
    final lon = _lon;
    if (lat == null || lon == null) return false;

    setState(() => _sacando = true);
    // Etapa 4 (P8): la rama móvil propaga store/uuidRegistro/tipoEntidad
    // igual que Windows; sin esto la foto quedaba solo en memoria y nunca
    // se registraba ni encolaba en Android/iOS.
    final ok = await EdanBotonSacarFoto.capturarFoto(
      fotos: widget.fotos,
      latitud: lat,
      longitud: lon,
      precision: _prec,
      idLocal: widget.idLocal,
      idSeccion: widget.idSeccion,
      store: widget.store,
      uuidRegistro: widget.uuidRegistro,
      tipoEntidad: widget.tipoEntidad,
      rutaSeccion: widget.rutaSeccion,
    );
    if (!mounted) return false;
    setState(() => _sacando = false);
    if (ok) {
      widget.onCoordenadasCapturadas(lat, lon);
      if (widget.fotos.isNotEmpty) {
        widget.onFotoGuardada?.call(widget.fotos.first.ruta);
      }
      Navigator.of(context).pop(true);
    }
    return ok;
  }

  void _abrirMenuFotoExistente() {
    showModalBottomSheet<bool>(
      context: context,
      builder: (menuCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined, color: AppColors.textPrimary),
              title: const Text('Ver foto actual'),
              onTap: () {
                Navigator.of(menuCtx).pop();
                EdanBotonSacarFoto.verFotoCompleta(
                  context,
                  fotos: widget.fotos,
                  fotografia: null,
                  coordenadaLat: _lat ?? 0,
                  coordenadaLon: _lon ?? 0,
                  seccion: widget.seccion,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh, color: AppColors.completed),
              title: const Text('Re-tomar foto'),
              subtitle: const Text('Se recapturarán las coordenadas por seguridad'),
              onTap: () {
                Navigator.of(menuCtx).pop();
                _tomarFoto();
              },
            ),
            ListTile(
              leading: const Icon(Icons.close, color: AppColors.textSecondary),
              title: const Text('Cancelar'),
              onTap: () => Navigator.of(menuCtx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  void _onSacarFoto() {
    if (_sacando) return;
    // Windows: validar coordenadas de los campos de texto
    if (_isWindows) {
      if (!_validarCoordenadasWindows()) return;
    } else {
      if (_lat == null || _lon == null) return;
    }
    if (widget.fotos.isNotEmpty) {
      _abrirMenuFotoExistente();
      return;
    }
    _tomarFoto();
  }

  @override
  Widget build(BuildContext context) {
    const colorPrimario = AppColors.completed;
    // Windows: "listo" cuando los campos de texto tienen valores
    final bool coordsListas = _isWindows
        ? (_latCtrl.text.isNotEmpty && _lonCtrl.text.isNotEmpty)
        : (_lat != null && _lon != null);
    final bool tienefoto = widget.fotos.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Material(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorPrimario.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.camera_alt_outlined,
                          color: AppColors.completed, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.seccion != null
                            ? 'Respaldo · ${widget.seccion}'
                            : 'Respaldo de foto',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _coordenadasCard(colorPrimario, coordsListas),
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorPrimario,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.closed.withValues(alpha: 0.4),
                      disabledForegroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed:
                        (coordsListas && !_sacando) ? _onSacarFoto : null,
                    icon: _sacando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            _isWindows ? Icons.image_outlined : Icons.photo_camera_outlined,
                            size: 20,
                          ),
                    label: Text(
                      _isWindows
                          ? (tienefoto ? 'Cambiar imagen' : 'Seleccionar imagen')
                          : (tienefoto ? 'Editar foto' : 'Sacar foto'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (tienefoto) ...[
                  const SizedBox(height: 8),
                  Text(
                    _isWindows
                        ? 'Ya tienes una imagen seleccionada. El botón abrirá opciones para cambiarla.'
                        : 'Ya tienes una foto. El botón abrirá opciones para '
                            'verla o retomarla.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _coordenadasCard(Color verde, bool coordsListas) {
    // Windows: campos editables de coordenadas
    if (_isWindows) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Form(
          key: _coordFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.edit_location_alt, color: verde, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Coordenadas del punto de muestreo',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Latitud',
                        hintText: 'ej: -16.500000',
                        prefixIcon: const Icon(Icons.north, size: 16),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Req.';
                        final n = double.tryParse(v.trim());
                        if (n == null) return 'Inválido';
                        if (n < -90 || n > 90) return '-90 a 90';
                        return null;
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _lonCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Longitud',
                        hintText: 'ej: -68.000000',
                        prefixIcon: const Icon(Icons.east, size: 16),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Req.';
                        final n = double.tryParse(v.trim());
                        if (n == null) return 'Inválido';
                        if (n < -180 || n > 180) return '-180 a 180';
                        return null;
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Móvil: flujo GPS automático
    final Widget contenido;
    if (_capturando) {
      contenido = const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Capturando ubicación…',
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
        ],
      );
    } else if (coordsListas) {
      contenido = Row(
        children: [
          const Icon(Icons.check_circle_outline, color: AppColors.completed, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${_lat!.toStringAsFixed(6)}, ${_lon!.toStringAsFixed(6)}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_prec > 0)
            Text(
              '±${_prec.toStringAsFixed(0)}m',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
        ],
      );
    } else {
      contenido = Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.rejected, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'No se pudo obtener la ubicación',
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
          if (_reintentar)
            TextButton(
              onPressed: _capturarCoordenadas,
              child: const Text('Reintentar'),
            ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: coordsListas
            ? verde.withValues(alpha: 0.10)
            : AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: coordsListas
              ? verde.withValues(alpha: 0.4)
              : AppColors.divider,
        ),
      ),
      child: contenido,
    );
  }
}
