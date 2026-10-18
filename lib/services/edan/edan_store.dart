import '../../models/edan.dart';
import '../../models/edan_registro_v2.dart';

/// Abstracción de la capa de datos EDAN. Permite inyectar la implementación
/// legacy (UGR/IA) o la nueva V2 (RESP) en los componentes compartidos.
abstract class EdanStore {
  // Formularios
  Future<EdanLocalidad?> cargarFormulario(String uuidEdanLocalidad);
  Future<List<EdanLocalidad>> listarFormularios({int? usuarioId});
  Future<void> guardarFormulario(
    EdanLocalidad loc, {
    required int usuarioId,
    List<String>? seccionesActivas,
  });
  Future<void> marcarEnviado(String uuidEdanLocalidad);
  Future<void> marcarBorradoFormulario(String uuidEdanLocalidad);

  /// Elimina UNA localidad completa (cabecera + filas + viviendas + fotos +
  /// auxiliares + colas de sus uuids).
  ///
  /// - Si NUNCA se sincronizó (`id_server` nulo): borrado solo-local, SIN
  ///   ninguna llamada de red (no hay nada que informar al servidor).
  /// - Si SÍ se sincronizó: además encola `D {tabla:'formulario'}` para que
  ///   el motor propague `DELETE /formularios/{uuid}` (404 se purga solo).
  Future<void> eliminarLocalidad(String uuidEdanLocalidad);

  /// Registra la intención de envío SIN red (`pending_submit=1` +
  /// `estado_destino`): el próximo push confirmado transiciona al estado
  /// destino. Sin esto, un "Enviar" offline se sincronizaba como borrador.
  Future<void> marcarEnvioPendiente(
      String uuidEdanLocalidad, int idEstadoDestino);

  // Secciones / filas
  Future<void> guardarFilas(
    String uuidEdanLocalidad,
    List<String> tipos,
    EdanLocalidad loc,
  );

  /// Guarda cabecera + filas en **una sola transacción** (todo o nada).
  /// La implementación base lo hace secuencial (sin atomicidad); V2 la
  /// sobrescribe con un `db.transaction` real. El wizard RESP usa esta vía.
  ///
  /// Con [purgarInactivas] se purgan además las filas de las rutas que ya no
  /// están activas (grupo destildado): como el grupo manda y sus filas ya no
  /// van al servidor, no deben quedar huérfanas en SQLite.
  Future<void> guardarTodo(
    EdanLocalidad loc, {
    required int usuarioId,
    List<String>? seccionesActivas,
    required List<String> tipos,
    bool purgarInactivas = false,
  }) async {
    await guardarFormulario(loc,
        usuarioId: usuarioId, seccionesActivas: seccionesActivas);
    final uuid = loc.uuidEdanLocalidad;
    if (uuid != null && uuid.isNotEmpty) {
      await guardarFilas(uuid, tipos, loc);
    }
  }
  Future<void> cargarSecciones(EdanLocalidad loc, {List<String>? tipos});
  Future<void> eliminarFila(String tipo, String uuidRegistro);

  /// Purga TODAS las filas de [rutas] (rutas v2): las borra de
  /// `filas_seccion` (+ hijas `viviendas` + fotos con su archivo), encola `D`
  /// para las que estaban confirmadas y limpia pendientes. Es lo que exige
  /// destildar un grupo en page01: como el grupo manda y sus filas ya no van
  /// al servidor, no deben quedar huérfanas en SQLite. Idempotente.
  Future<void> purgarSecciones(
      String uuidEdanLocalidad, List<String> rutas);

  /// Marca secciones como activas (origen 'usuario' por defecto).
  Future<void> activarSecciones(
    String uuidEdanLocalidad,
    List<String> tipos, {
    String origen,
  });

  /// Apaga la activación de ORIGEN 'usuario'. Una sección que quedó activa
  /// por tener datos no se oculta desde los checkboxes.
  Future<void> desactivarSecciones(String uuidEdanLocalidad, List<String> tipos);

  /// Secciones activas: lo que el usuario tildó ∪ lo que tiene datos reales.
  Future<List<String>> leerSeccionesActivas(String uuidEdanLocalidad);

  /// Rutas v2 con al menos una fila persistida ("verdad en los datos").
  Future<List<String>> rutasConDatos(String uuidEdanLocalidad);

  // Grupos (tabla auxiliar v32: `grupos_local`)
  //
  // Dos verdades distintas: `seleccion_usuario` (lo que tildó en page01 y
  // gobierna qué secciones mostrar) y `grup_servidor` (caché del nodo
  // `grupos` que calcula el servidor; solo lectura).

  /// Persiste la selección de grupos del usuario (los 9, marcados o no).
  Future<void> guardarSeleccionGrupos(
    String uuidEdanLocalidad,
    Set<String> grupos,
  );

  /// Grupos que el usuario tildó en page01.
  Future<Set<String>> leerSeleccionGrupos(String uuidEdanLocalidad);

  /// Guarda la caché del nodo `grupos` devuelto por el servidor.
  Future<void> guardarGruposServidor(
    String uuidEdanLocalidad,
    Map<String, bool> grupos,
  );

  /// Caché del nodo `grupos` del servidor (vacía si todavía no se leyó).
  Future<Map<String, bool>> leerGruposServidor(String uuidEdanLocalidad);

  // Viviendas (1:N bajo danos-vivienda)
  Future<List<EdanVivienda>> cargarViviendas(String uuidDanoVivienda);
  Future<void> guardarVivienda(EdanVivienda vivienda);
  Future<void> eliminarVivienda(String uuidVivienda);

  // Fotos
  Future<void> registrarFoto(
    EdanFoto foto,
    String tipoEntidad,
    String uuidRegistro,
  );
  Future<void> borrarFoto(String uuidFotografia);
  Future<void> encolarFoto(EdanFoto foto);

  /// Lista las fotos **no borradas** de una entidad dueña (`tipo_entidad` +
  /// `uuid_registro`), con su `uuid_fotografia` y ruta local. Permite mostrar
  /// la miniatura y, al reemplazar/eliminar la dueña, purgar el registro previo
  /// sin dejar huérfanos.
  Future<List<EdanFoto>> cargarFotosDeEntidad(
    String tipoEntidad,
    String uuidRegistro,
  );

  // Envío / sync
  Future<EdanEnvioResultado> enviarFormulario(String uuidEdanLocalidad);
  Future<void> procesarColaDeletes();

  // Observables para la UI
  Stream<int> get pendientesStream;

  /// Libera recursos (streams, suscripciones).
  void dispose();
}
