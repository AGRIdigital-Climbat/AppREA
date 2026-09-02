import '../../models/edan.dart';
import '../edan_secciones_registry.dart';
import 'edan_seccion_envio_base.dart';

/// Envío por sección de `necesidad-humanitaria` (1:1, objeto único, Modelo A v2).
///
/// La API es DINÁMICA: solo se envían los ítems `true` + su campo `obs_*`
/// (p. ej. `alimentos:true` + `obs_alimentos`). Nunca se envían los false.
class EdanNecesidadHumanitariaService extends EdanSeccionEnvioBase {
  EdanNecesidadHumanitariaService();

  @override
  EdanSeccionDescriptor get descriptor =>
      EdanSeccionesRegistry.porRuta('necesidad-humanitaria')!;

  @override
  List<Map<String, dynamic>> filasGuardar(EdanLocalidad l) {
    final nh = l.necesidadHumanitaria;
    if (nh == null || !nh.tieneDatos) return const [];
    return [nh.toJson()];
  }

  @override
  Map<String, dynamic> filaDesdeRow(Map<String, dynamic> row) {
    const pares = <(String, String)>[
      ('alimentos', 'obs_alimentos'),
      ('refugio_vivienda', 'obs_refugio_vivienda'),
      ('ropa_cama', 'obs_ropa_cama'),
      ('articulos_higiene', 'obs_articulos_higiene'),
      ('articulos_cocina', 'obs_articulos_cocina'),
      ('prendas_vestir', 'obs_prendas_vestir'),
      ('herramientas', 'obs_herramientas'),
      ('almacenamiento_agua', 'obs_almacenamiento_agua'),
      ('banos', 'obs_banos'),
    ];

    final json = <String, dynamic>{
      if (row['id_seccion']?.toString().isNotEmpty == true)
        'id_seccion': row['id_seccion'].toString(),
    };

    for (final (flag, obs) in pares) {
      final valor = row[flag];
      final esTrue = valor is bool
          ? valor
          : (valor is num ? valor != 0 : valor.toString() == 'true');
      if (!esTrue) continue;
      json[flag] = true;
      final obsVal = row[obs]?.toString() ?? '';
      if (obsVal.isNotEmpty) json[obs] = obsVal;
    }
    return json;
  }
}
