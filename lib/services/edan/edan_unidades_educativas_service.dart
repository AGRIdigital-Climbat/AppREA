import '../../models/edan.dart';
import '../edan_secciones_registry.dart';
import 'edan_seccion_envio_base.dart';

/// Envío por sección de `unidades-educativas` (1:N, con foto, Modelo A v2).
class EdanUnidadesEducativasService
    extends EdanSeccionEnvioBase<EdanDanoUnidadEducativa> {
  EdanUnidadesEducativasService();

  @override
  EdanSeccionDescriptor get descriptor =>
      EdanSeccionesRegistry.porRuta('unidades-educativas')!;

  @override
  List<EdanDanoUnidadEducativa> itemsDe(EdanLocalidad l) => l.unidadesEducativas;

  @override
  Map<String, dynamic> filaApi(EdanDanoUnidadEducativa item) =>
      item.toApiJson();

  @override
  List<EdanFoto> fotosDe(EdanDanoUnidadEducativa item) => item.fotos;

  @override
  String? fotografiaDe(EdanDanoUnidadEducativa item) => item.fotografia;

  @override
  void marcarSubida(EdanDanoUnidadEducativa item, String path) =>
      item.fotografia = path;

  @override
  String? idSeccionDe(EdanDanoUnidadEducativa item) => item.idSeccion;
}
