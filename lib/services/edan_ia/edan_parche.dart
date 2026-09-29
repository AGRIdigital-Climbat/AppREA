/// Parche de actualización del borrador.
///
/// Contrato: contiene **solo lo detectado**. Un campo ausente (o `null`) significa
/// "no lo dijo nadie" y la fusión debe respetarlo tal cual, sin pisar lo que la
/// persona ya había escrito o corregido a mano.
///
/// Es el equivalente Dart de los objetos que devuelve `extraer()` en
/// `EDAN-Tutor/src/services/extractor.js` y del JSON que produce la IA. Que los
/// dos compartan tipo simplifica la fusión: no hace falta distinguir "lo dijo
/// una regla" de "lo dijo el modelo".
library;

import '../../models/edan_borrador_ia.dart';

/// Actualización parcial de un [EdanBorradorIa].
class EdanParche {
  // --- Cabecera (`localidades_offline`) ---
  String? departamento;
  String? provincia;
  String? municipio;
  String? alcalde;
  String? telefono;
  String? fechaLlenado;
  String? fechaEvento;
  String? horaEvento;
  String? tipoEventoOtro;
  String? responsableNombre;
  String? responsableCargo;
  String? responsableTelefono;
  String? responsableEmail;

  // --- Conteos (`localidades_offline`) ---
  int? totalAfectada;
  int? totalFamiliasAfectadas;
  int? totalFamiliasDamnificadas;

  // --- Totales de vivienda (se materializan como fila de daños de vivienda) ---
  int? viviendasAfectadas;
  int? viviendasDamnificadas;

  // --- Bloques fijos: clave -> campo -> valor detectado ---
  /// Tipo de evento: `key -> true` (incluye `otros`).
  final Map<String, bool> tipoEvento = {};
  /// Impacto: etiqueta de grupo -> campo -> valor detectado. Los campos
  /// `fallecidos` / `heridos` / `desaparecidos` son cifras y
  /// `observaciones` es texto, de ahí el `Object?`.
  final Map<String, Map<String, Object?>> impactoPoblacion = {};
  /// Protección: etiqueta de grupo -> lo detectado para ese grupo. Se lleva la
  /// fila entera (y no solo un entero) porque SQLite separa `mujeres` y
  /// `hombres` y el extractor solo puede rellenar ese desglose si la frase lo da.
  final Map<String, BchProteccionFila> proteccion = {};
  /// Necesidades: ítem -> marcadas.
  final Map<String, bool?> necesidadesHumanitarias = {};
  /// Primera respuesta: `busqueda` / `salvamento` / `evacuacion`.
  final Map<String, bool?> primeraRespuesta = {};
  /// Necesidad de salud: `incendio` / `inundacion` / `sequia` / `otras` /
  /// `observaciones`.
  final Map<String, String?> necesidadSalud = {};
  /// Servicios básicos: clave (`luz`, `agua`…) -> campos detectados.
  final Map<String, Map<String, String?>> serviciosBasicos = {};

  // --- Relaciones 1:n ---
  List<BchDanoVial> infraVial = [];
  List<BchInfraPublica> infraPublica = [];
  List<BchInfraProductiva> infraProductiva = [];
  List<BchEstablecimientoSalud> saludDanios = [];
  List<BchUnidadEducativa> educacion = [];
  List<BchDanoVivienda> danosVivienda = [];
  List<BchAgricultura> agricultura = [];
  List<BchPecuario> pecuario = [];
  List<BchComunidad> comunidades = [];

  /// ¿El parche no aporta nada? Un parche vacío no debe tocar el borrador ni
  /// generar un mensaje de "anoté esto" en la interfaz.
  bool get vacio {
    if (departamento != null ||
        provincia != null ||
        municipio != null ||
        alcalde != null ||
        telefono != null ||
        fechaLlenado != null ||
        fechaEvento != null ||
        horaEvento != null ||
        tipoEventoOtro != null ||
        responsableNombre != null ||
        responsableCargo != null ||
        responsableTelefono != null ||
        responsableEmail != null ||
        totalAfectada != null ||
        totalFamiliasAfectadas != null ||
        totalFamiliasDamnificadas != null ||
        viviendasAfectadas != null ||
        viviendasDamnificadas != null) {
      return false;
    }
    if (tipoEvento.isNotEmpty ||
        impactoPoblacion.isNotEmpty ||
        proteccion.isNotEmpty ||
        necesidadesHumanitarias.isNotEmpty ||
        primeraRespuesta.isNotEmpty ||
        necesidadSalud.isNotEmpty ||
        serviciosBasicos.isNotEmpty) {
      return false;
    }
    return infraVial.isEmpty &&
        infraPublica.isEmpty &&
        infraProductiva.isEmpty &&
        saludDanios.isEmpty &&
        educacion.isEmpty &&
        danosVivienda.isEmpty &&
        agricultura.isEmpty &&
        pecuario.isEmpty &&
        comunidades.isEmpty;
  }
}
