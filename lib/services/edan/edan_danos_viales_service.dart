import '../../models/edan.dart';
import '../edan_secciones_registry.dart';
import 'edan_seccion_envio_base.dart';

/// Envío por sección de `danos-viales` (1:N, con foto, Modelo A v2).
class EdanDanosVialesService extends EdanSeccionEnvioBase<EdanDanoVial> {
  EdanDanosVialesService();

  @override
  EdanSeccionDescriptor get descriptor =>
      EdanSeccionesRegistry.porRuta('danos-viales')!;

  @override
  List<EdanDanoVial> itemsDe(EdanLocalidad l) => l.danosViales;

  @override
  Map<String, dynamic> filaApi(EdanDanoVial item) => item.toApiJson();

  @override
  List<EdanFoto> fotosDe(EdanDanoVial item) => item.fotos;

  @override
  String? fotografiaDe(EdanDanoVial item) => item.fotografia;

  @override
  void marcarSubida(EdanDanoVial item, String path) => item.fotografia = path;

  @override
  String? idSeccionDe(EdanDanoVial item) => item.idSeccion;
}
