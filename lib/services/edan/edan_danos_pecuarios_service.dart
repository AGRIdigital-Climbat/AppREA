import '../../models/edan.dart';
import '../edan_secciones_registry.dart';
import 'edan_seccion_envio_base.dart';

/// Envío por sección de `danos-pecuarios` (1:N, con foto, Modelo A v2).
class EdanDanosPecuariosService
    extends EdanSeccionEnvioBase<EdanDanoPecuario> {
  EdanDanosPecuariosService();

  @override
  EdanSeccionDescriptor get descriptor =>
      EdanSeccionesRegistry.porRuta('danos-pecuarios')!;

  @override
  List<EdanDanoPecuario> itemsDe(EdanLocalidad l) => l.danosPecuarios;

  @override
  Map<String, dynamic> filaApi(EdanDanoPecuario item) => item.toApiJson();

  @override
  List<EdanFoto> fotosDe(EdanDanoPecuario item) => item.fotos;

  @override
  String? fotografiaDe(EdanDanoPecuario item) => item.fotografia;

  @override
  void marcarSubida(EdanDanoPecuario item, String path) =>
      item.fotografia = path;

  @override
  String? idSeccionDe(EdanDanoPecuario item) => item.idSeccion;
}
