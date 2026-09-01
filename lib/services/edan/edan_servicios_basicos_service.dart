import '../../models/edan.dart';
import '../edan_secciones_registry.dart';
import 'edan_seccion_envio_base.dart';

/// Envío por sección de `servicios-basicos` (1:N, con foto, Modelo A v2).
class EdanServiciosBasicosService
    extends EdanSeccionEnvioBase<EdanServicioBasicoDetalle> {
  EdanServiciosBasicosService();

  @override
  EdanSeccionDescriptor get descriptor =>
      EdanSeccionesRegistry.porRuta('servicios-basicos')!;

  @override
  List<EdanServicioBasicoDetalle> itemsDe(EdanLocalidad l) =>
      l.serviciosBasicos;

  @override
  bool debeGuardar(EdanServicioBasicoDetalle item) => item.tieneDatos;

  @override
  Map<String, dynamic> filaApi(EdanServicioBasicoDetalle item) =>
      item.toApiJson();

  @override
  List<EdanFoto> fotosDe(EdanServicioBasicoDetalle item) => item.fotos;

  @override
  String? fotografiaDe(EdanServicioBasicoDetalle item) => item.fotografia;

  @override
  void marcarSubida(EdanServicioBasicoDetalle item, String path) =>
      item.fotografia = path;

  @override
  String? idSeccionDe(EdanServicioBasicoDetalle item) => item.idSeccion;
}
