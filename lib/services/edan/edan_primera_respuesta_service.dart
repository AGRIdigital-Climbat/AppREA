import '../../models/edan.dart';
import '../edan_secciones_registry.dart';
import 'edan_seccion_envio_base.dart';

/// Envío por sección de `primera-respuesta` (1:1, objeto único, Modelo A v2).
class EdanPrimeraRespuestaService extends EdanSeccionEnvioBase {
  EdanPrimeraRespuestaService();

  @override
  EdanSeccionDescriptor get descriptor =>
      EdanSeccionesRegistry.porRuta('primera-respuesta')!;

  @override
  List<Map<String, dynamic>> filasGuardar(EdanLocalidad l) {
    final pr = l.necesidadPrimeraRespuesta;
    if (pr == null || !pr.tieneDatos) return const [];
    return [pr.toJson()];
  }
}
