import '../../models/edan.dart';
import '../edan_secciones_registry.dart';
import 'edan_seccion_envio_base.dart';

/// Envío por sección de `danos-infra-publica` (1:N, con foto, Modelo A v2).
class EdanDanosInfraPublicaService
    extends EdanSeccionEnvioBase<EdanDanoInfraPublica> {
  EdanDanosInfraPublicaService();

  @override
  EdanSeccionDescriptor get descriptor =>
      EdanSeccionesRegistry.porRuta('danos-infra-publica')!;

  @override
  List<EdanDanoInfraPublica> itemsDe(EdanLocalidad l) => l.danosInfraPublica;

  @override
  Map<String, dynamic> filaApi(EdanDanoInfraPublica item) => item.toApiJson();

  @override
  List<EdanFoto> fotosDe(EdanDanoInfraPublica item) => item.fotos;

  @override
  String? fotografiaDe(EdanDanoInfraPublica item) => item.fotografia;

  @override
  void marcarSubida(EdanDanoInfraPublica item, String path) =>
      item.fotografia = path;

  @override
  String? idSeccionDe(EdanDanoInfraPublica item) => item.idSeccion;
}
