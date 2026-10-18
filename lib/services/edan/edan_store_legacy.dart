import 'dart:async';

import '../../models/edan.dart';
import '../../models/edan_registro_v2.dart';
import 'edan_store.dart';

/// Implementación legacy de [EdanStore]. Es un stub que conserva la firma de
/// la interfaz sin delegar aún en `DatabaseHelper`; su objetivo es no romper
/// los componentes compartidos mientras RESP migra a [EdanStoreV2].
///
/// Cuando UGR/IA necesiten pasar por esta interfaz, se completará con las
/// llamadas legacy reales (`getLocalidadByIdLocal`, `updateLocalidad`, etc.).
class EdanStoreLegacy implements EdanStore {
  EdanStoreLegacy();

  final _pendientesController = StreamController<int>.broadcast();

  @override
  Future<EdanLocalidad?> cargarFormulario(String uuidEdanLocalidad) async {
    throw UnimplementedError('EdanStoreLegacy.cargarFormulario');
  }

  @override
  Future<List<EdanLocalidad>> listarFormularios({int? usuarioId}) async {
    throw UnimplementedError('EdanStoreLegacy.listarFormularios');
  }

  @override
  Future<void> guardarFormulario(EdanLocalidad loc,
      {required int usuarioId, List<String>? seccionesActivas}) async {
    throw UnimplementedError('EdanStoreLegacy.guardarFormulario');
  }

  @override
  Future<void> marcarEnviado(String uuidEdanLocalidad) async {}

  @override
  Future<void> marcarEnvioPendiente(
      String uuidEdanLocalidad, int idEstadoDestino) async {}

  @override
  Future<void> purgarSecciones(
      String uuidEdanLocalidad, List<String> rutas) async {}

  @override
  Future<void> marcarBorradoFormulario(String uuidEdanLocalidad) async {
    throw UnimplementedError('EdanStoreLegacy.marcarBorradoFormulario');
  }

  @override
  Future<void> eliminarLocalidad(String uuidEdanLocalidad) async {
    throw UnimplementedError('EdanStoreLegacy.eliminarLocalidad');
  }

  @override
  Future<void> guardarFilas(
    String uuidEdanLocalidad,
    List<String> tipos,
    EdanLocalidad loc,
  ) async {
    throw UnimplementedError('EdanStoreLegacy.guardarFilas');
  }

  @override
  Future<void> guardarTodo(
    EdanLocalidad loc, {
    required int usuarioId,
    List<String>? seccionesActivas,
    required List<String> tipos,
    bool purgarInactivas = false,
  }) async {
    throw UnimplementedError('EdanStoreLegacy.guardarTodo');
  }

  @override
  Future<void> cargarSecciones(EdanLocalidad loc, {List<String>? tipos}) async {
    throw UnimplementedError('EdanStoreLegacy.cargarSecciones');
  }

  @override
  Future<void> eliminarFila(String tipo, String uuidRegistro) async {
    throw UnimplementedError('EdanStoreLegacy.eliminarFila');
  }

  @override
  Future<void> activarSecciones(
    String uuidEdanLocalidad,
    List<String> tipos, {
    String origen = 'usuario',
  }) async {
    throw UnimplementedError('EdanStoreLegacy.activarSecciones');
  }

  @override
  Future<void> desactivarSecciones(
    String uuidEdanLocalidad,
    List<String> tipos,
  ) async {
    throw UnimplementedError('EdanStoreLegacy.desactivarSecciones');
  }

  @override
  Future<List<String>> leerSeccionesActivas(String uuidEdanLocalidad) async {
    throw UnimplementedError('EdanStoreLegacy.leerSeccionesActivas');
  }

  @override
  Future<List<String>> rutasConDatos(String uuidEdanLocalidad) async {
    throw UnimplementedError('EdanStoreLegacy.rutasConDatos');
  }

  @override
  Future<void> guardarSeleccionGrupos(
    String uuidEdanLocalidad,
    Set<String> grupos,
  ) async {
    throw UnimplementedError('EdanStoreLegacy.guardarSeleccionGrupos');
  }

  @override
  Future<Set<String>> leerSeleccionGrupos(String uuidEdanLocalidad) async {
    throw UnimplementedError('EdanStoreLegacy.leerSeleccionGrupos');
  }

  @override
  Future<void> guardarGruposServidor(
    String uuidEdanLocalidad,
    Map<String, bool> grupos,
  ) async {
    throw UnimplementedError('EdanStoreLegacy.guardarGruposServidor');
  }

  @override
  Future<Map<String, bool>> leerGruposServidor(String uuidEdanLocalidad) async {
    throw UnimplementedError('EdanStoreLegacy.leerGruposServidor');
  }

  @override
  Future<List<EdanVivienda>> cargarViviendas(String uuidDanoVivienda) async {
    return [];
  }

  @override
  Future<void> guardarVivienda(EdanVivienda vivienda) async {
    throw UnimplementedError('EdanStoreLegacy no soporta viviendas V2');
  }

  @override
  Future<void> eliminarVivienda(String uuidVivienda) async {
    throw UnimplementedError('EdanStoreLegacy no soporta viviendas V2');
  }

  @override
  Future<void> registrarFoto(
      EdanFoto foto, String tipoEntidad, String uuidRegistro) async {
    throw UnimplementedError('EdanStoreLegacy.registrarFoto');
  }

  @override
  Future<void> borrarFoto(String uuidFotografia) async {}

  @override
  Future<void> encolarFoto(EdanFoto foto) async {}

  @override
  Future<List<EdanFoto>> cargarFotosDeEntidad(
      String tipoEntidad, String uuidRegistro) async {
    return [];
  }

  @override
  Future<EdanEnvioResultado> enviarFormulario(
      String uuidEdanLocalidad) async {
    return EdanEnvioResultado.error(
      'EdanStoreLegacy no implementa envío directo',
    );
  }

  @override
  Future<void> procesarColaDeletes() async {}

  @override
  Stream<int> get pendientesStream => _pendientesController.stream;

  @override
  void dispose() {
    _pendientesController.close();
  }
}
