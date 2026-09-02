import '../../models/edan.dart';
import '../edan_secciones_registry.dart';
import 'edan_seccion_envio_base.dart';

/// Envío por sección de `necesidad-salud` (1:1, objeto único, Modelo A v2).
class EdanNecesidadSaludService extends EdanSeccionEnvioBase {
  EdanNecesidadSaludService();

  @override
  EdanSeccionDescriptor get descriptor =>
      EdanSeccionesRegistry.porRuta('necesidad-salud')!;

  @override
  List<Map<String, dynamic>> filasGuardar(EdanLocalidad l) {
    final ns = l.necesidadSalud;
    if (ns == null || !ns.tieneDatos) return const [];
    return [ns.toApiJson()];
  }
}
