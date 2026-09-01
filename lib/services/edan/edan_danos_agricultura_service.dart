import '../../models/edan.dart';
import '../edan_secciones_registry.dart';
import 'edan_seccion_envio_base.dart';

/// Envío por sección de `danos-agricultura` (1:N, con foto, Modelo A v2).
class EdanDanosAgriculturaService
    extends EdanSeccionEnvioBase<EdanDanoAgricultura> {
  EdanDanosAgriculturaService();

  @override
  EdanSeccionDescriptor get descriptor =>
      EdanSeccionesRegistry.porRuta('danos-agricultura')!;

  @override
  List<EdanDanoAgricultura> itemsDe(EdanLocalidad l) => l.danosAgricultura;

  @override
  Map<String, dynamic> filaApi(EdanDanoAgricultura item) => item.toApiJson();

  @override
  List<EdanFoto> fotosDe(EdanDanoAgricultura item) => item.fotos;

  @override
  String? fotografiaDe(EdanDanoAgricultura item) => item.fotografia;

  @override
  void marcarSubida(EdanDanoAgricultura item, String path) =>
      item.fotografia = path;

  @override
  String? idSeccionDe(EdanDanoAgricultura item) => item.idSeccion;
}
