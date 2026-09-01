import '../../models/edan.dart';
import '../edan_secciones_registry.dart';
import 'edan_seccion_envio_base.dart';

/// Envío por sección de `danos-vivienda` (1:N, con foto, Modelo A v2).
class EdanDanosViviendaService
    extends EdanSeccionEnvioBase<EdanDanoVivienda> {
  EdanDanosViviendaService();

  @override
  EdanSeccionDescriptor get descriptor =>
      EdanSeccionesRegistry.porRuta('danos-vivienda')!;

  @override
  List<EdanDanoVivienda> itemsDe(EdanLocalidad l) => l.danosVivienda;

  @override
  Map<String, dynamic> filaApi(EdanDanoVivienda item) => item.toApiJson();

  @override
  List<EdanFoto> fotosDe(EdanDanoVivienda item) => item.fotos;

  @override
  String? fotografiaDe(EdanDanoVivienda item) => item.fotografia;

  @override
  void marcarSubida(EdanDanoVivienda item, String path) =>
      item.fotografia = path;

  @override
  String? idSeccionDe(EdanDanoVivienda item) => item.idSeccion;
}
