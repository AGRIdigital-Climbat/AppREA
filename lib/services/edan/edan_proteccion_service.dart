import '../../models/edan.dart';
import '../edan_secciones_registry.dart';
import 'edan_seccion_envio_base.dart';

/// Envío por sección de `proteccion` (1:N, sin foto, Modelo A v2).
/// Cada grupo vulnerable con datos se envía como fila del array.
class EdanProteccionService extends EdanSeccionEnvioBase<EdanGrupoVulnerable> {
  EdanProteccionService();

  @override
  EdanSeccionDescriptor get descriptor =>
      EdanSeccionesRegistry.porRuta('proteccion')!;

  @override
  List<EdanGrupoVulnerable> itemsDe(EdanLocalidad l) => l.proteccion;

  @override
  bool debeGuardar(EdanGrupoVulnerable item) => item.tieneDatos;

  @override
  Map<String, dynamic> filaApi(EdanGrupoVulnerable item) =>
      item.toApiJson(null);

  @override
  String? idSeccionDe(EdanGrupoVulnerable item) => item.idSeccion;
}
