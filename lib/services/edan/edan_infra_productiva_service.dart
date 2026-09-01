import '../../models/edan.dart';
import '../edan_secciones_registry.dart';
import 'edan_seccion_envio_base.dart';

/// Envío por sección de `infra-productiva` (1:N, con foto, Modelo A v2).
class EdanInfraProductivaService
    extends EdanSeccionEnvioBase<EdanInfraProductiva> {
  EdanInfraProductivaService();

  @override
  EdanSeccionDescriptor get descriptor =>
      EdanSeccionesRegistry.porRuta('infra-productiva')!;

  @override
  List<EdanInfraProductiva> itemsDe(EdanLocalidad l) => l.infraProductiva;

  @override
  Map<String, dynamic> filaApi(EdanInfraProductiva item) => item.toApiJson();

  @override
  List<EdanFoto> fotosDe(EdanInfraProductiva item) => item.fotos;

  @override
  String? fotografiaDe(EdanInfraProductiva item) => item.fotografia;

  @override
  void marcarSubida(EdanInfraProductiva item, String path) =>
      item.fotografia = path;

  @override
  String? idSeccionDe(EdanInfraProductiva item) => item.idSeccion;
}
