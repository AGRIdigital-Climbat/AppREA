import '../../models/edan.dart';
import '../../models/id_seccion_helper.dart';
import '../api_service.dart';
import '../database_helper.dart';
import '../edan_secciones_registry.dart';

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
    // Bolivia: UTC-4 fijo. El dispositivo ya viene ajustado.
    final fechaLocal = json.remove('fecha_modificacion_local');
    if (fechaLocal != null && fechaLocal.toString().isNotEmpty) {
      json['fecha_modificacion'] = EdanLocalidad.toBoliviaIso(
        fechaLocal.toString(),
      );
    }
    // Mantener id_seccion (clave UPSERT)
    return json;
  }

  // ========== Accesores opcionales (para secciones con foto / 1:N) ==========

  List<EdanFoto> fotosDe(T item) => const [];
  String? fotografiaDe(T item) => null;
  void marcarSubida(T item, String path) {}
  String? idSeccionDe(T item) => null;

  /// Asigna `id_seccion` a los ítems 1:N que están por persistir (los que
  /// [debeGuardar] devuelve true) y que todavía no tienen id.
  ///
  /// Regla: `id_seccion` SOLO se genera aquí (al guardar) y únicamente si el
  /// ítem carece de id. Los ítems con id existente (servidor o guardado previo)
  /// se conservan tal cual; nunca se regeneran ni se reemplazan.
  void asignarIdSeccionSiFalta(EdanLocalidad localidad, String prefijo) {
    for (final item in itemsDe(localidad)) {
      if (!debeGuardar(item)) continue;
      final actual = idSeccionDe(item);
      if (actual == null || actual.isEmpty) {
        _setIdSeccion(item, generarIdSeccion(prefijo));
      }
    }
  }

  static void _setIdSeccion(dynamic item, String id) {
    if (item is EdanDanoInfraPublica) { item.idSeccion = id; return; }
    if (item is EdanEstablecimientoSalud) { item.idSeccion = id; return; }
    if (item is EdanDanoVial) { item.idSeccion = id; return; }
    if (item is EdanDanoUnidadEducativa) { item.idSeccion = id; return; }
    if (item is EdanDanoVivienda) { item.idSeccion = id; return; }
    if (item is EdanDanoAgricultura) { item.idSeccion = id; return; }
    if (item is EdanDanoPecuario) { item.idSeccion = id; return; }
    if (item is EdanInfraProductiva) { item.idSeccion = id; return; }
    if (item is EdanServicioBasicoDetalle) { item.idSeccion = id; return; }
    if (item is EdanGrupoVulnerable) { item.idSeccion = id; return; }
    if (item is EdanImpactoPoblacion) { item.idSeccion = id; return; }
    if (item is EdanGrupoEtario) { item.idSeccion = id; return; }
  }
}
