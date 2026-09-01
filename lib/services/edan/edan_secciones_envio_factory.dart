import 'edan_seccion_envio_base.dart';
import 'edan_salud_establecimientos_service.dart';
import 'edan_danos_viales_service.dart';
import 'edan_danos_infra_publica_service.dart';
import 'edan_servicios_basicos_service.dart';
import 'edan_unidades_educativas_service.dart';
import 'edan_danos_vivienda_service.dart';
import 'edan_danos_agricultura_service.dart';
import 'edan_danos_pecuarios_service.dart';
import 'edan_infra_productiva_service.dart';
import 'edan_proteccion_service.dart';
import 'edan_impacto_poblacion_service.dart';
import 'edan_primera_respuesta_service.dart';
import 'edan_necesidad_salud_service.dart';
import 'edan_necesidad_humanitaria_service.dart';

/// Registro de los servicios de envío por sección (Modelo A v2).
/// Cada sección tiene SU función de envío dedicada (no por página), de modo que
/// el envío incremental aísla fallos: una sección que falle no bloquea al resto.
class EdanSeccionesEnvioFactory {
  const EdanSeccionesEnvioFactory._();

  static EdanSeccionEnvioBase? servicioDeRuta(String rutaV2) {
    switch (rutaV2) {
      case 'impacto-poblacion':
        return EdanImpactoPoblacionService();
      case 'salud-establecimientos':
        return EdanSaludEstablecimientosService();
      case 'danos-viales':
        return EdanDanosVialesService();
      case 'danos-infra-publica':
        return EdanDanosInfraPublicaService();
      case 'servicios-basicos':
        return EdanServiciosBasicosService();
      case 'unidades-educativas':
        return EdanUnidadesEducativasService();
      case 'danos-vivienda':
        return EdanDanosViviendaService();
      case 'danos-agricultura':
        return EdanDanosAgriculturaService();
      case 'danos-pecuarios':
        return EdanDanosPecuariosService();
      case 'infra-productiva':
        return EdanInfraProductivaService();
      case 'proteccion':
        return EdanProteccionService();
      case 'primera-respuesta':
        return EdanPrimeraRespuestaService();
      case 'necesidad-salud':
        return EdanNecesidadSaludService();
      case 'necesidad-humanitaria':
        return EdanNecesidadHumanitariaService();
      default:
        return null;
    }
  }
}
