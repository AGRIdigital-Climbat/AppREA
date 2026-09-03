import '../../models/edan.dart';
import '../edan_secciones_registry.dart';
import 'edan_seccion_envio_base.dart';

/// Envío por sección de `salud-establecimientos` (1:N, con foto, Modelo A v2).
class EdanSaludEstablecimientosService
    extends EdanSeccionEnvioBase<EdanEstablecimientoSalud> {
  EdanSaludEstablecimientosService();

  @override
  EdanSeccionDescriptor get descriptor =>
      EdanSeccionesRegistry.porRuta('salud-establecimientos')!;

  @override
  List<EdanEstablecimientoSalud> itemsDe(EdanLocalidad l) =>
      l.establecimientosSalud;

  @override
  Map<String, dynamic> filaApi(EdanEstablecimientoSalud item) =>
      item.toApiJson();

  @override
  List<EdanFoto> fotosDe(EdanEstablecimientoSalud item) => item.fotos;

  @override
  String? fotografiaDe(EdanEstablecimientoSalud item) => item.fotografia;

  @override
  void marcarSubida(EdanEstablecimientoSalud item, String path) =>
      item.fotografia = path;

  @override
  String? idSeccionDe(EdanEstablecimientoSalud item) => item.idSeccion;
}
