import '../../models/edan.dart';
import '../edan_secciones_registry.dart';
import 'edan_seccion_envio_base.dart';

/// Envío por sección de `impacto-poblacion` (1:N, sin foto, Modelo A v2).
/// Solo se envían los grupos etarios marcados por el usuario; cada fila arrastra
/// su `id_grupo_etario` (catálogo) como clave.
class EdanImpactoPoblacionService
    extends EdanSeccionEnvioBase<EdanGrupoEtario> {
  EdanImpactoPoblacionService();

  @override
  EdanSeccionDescriptor get descriptor =>
      EdanSeccionesRegistry.porRuta('impacto-poblacion')!;

  @override
  List<EdanGrupoEtario> itemsDe(EdanLocalidad l) =>
      l.impactoPoblacion.expand((p) => p.gruposEtarios).toList();

  @override
  bool debeGuardar(EdanGrupoEtario item) => item.marcado;

  @override
  Map<String, dynamic> filaApi(EdanGrupoEtario item) => item.toApiJson();

  @override
  String? idSeccionDe(EdanGrupoEtario item) => item.idSeccion;

  /// La tabla guarda solo los grupos marcados; igual filtramos por seguridad.
  @override
  Map<String, dynamic> filaDesdeRow(Map<String, dynamic> row) {
    final json = super.filaDesdeRow(row);
    // En el payload el servidor no espera `rango` (resuelve por id_grupo_etario),
    // pero se conserva si no hay id_grupo_etario.
    if (json['id_grupo_etario'] is int) json.remove('rango');
    return json;
  }
}
