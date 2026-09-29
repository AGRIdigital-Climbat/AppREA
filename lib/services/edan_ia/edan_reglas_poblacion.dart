/// Las reglas de población del wizard, aplicadas al borrador de la IA.
///
/// El wizard tiene un control interno repetido en cuatro páginas: **la suma de
/// personas de una sección no puede superar el total de población afectada**
/// (páginas 03, 04, 07 y 10). En el wizard eso sale como un banner ámbar y,
/// peor, como sección "pendiente" que bloquea el botón de enviar.
///
/// Acá se replica ese control, con dos diferencias que importan en una
/// conversación: no se muestra un error y ya. El aviso se le devuelve al
/// modelo para que lo mencione con palabras, y a la persona para que lo
/// corrija. Una fila mal contada casi nunca es un error de la persona: es que
/// olvidó un dato, y eso se arregla preguntando.
///
/// ## Topes que NO se replican, y por qué
///
/// El borrador de la IA no tiene los datos que necesitarían, y adivinarlos
/// daría avisos falsos, que es peor que no avisar:
///
/// - **Salud (página 04).** El tope del wizard suma el personal de cada
///   establecimiento (médicos, enfermeras, otros). `BchEstablecimientoSalud` no
///   tiene esos campos: nunca se portaron. Replicar el tope con otra cosa
///   inventaría un número.
/// - **Educación (página 07).** El tope del wizard suma `totalAfectados` por
///   unidad. El borrador solo tiene `estudiantes`, que es el tamaño de la
///   escuela, no los afectados: una escuela de 500 alumnos en un pueblo de 300
///   afectados dispararía un aviso falso en cada ficha.
///
/// Los dos se pueden agregar el día que se porten esos campos; el sitio está
/// listo en [validarPoblacion].
library;

import '../../models/edan_borrador_ia.dart';

/// Un desajuste entre lo contado y el total, con el mensaje del wizard.
class EdanAvisoPoblacion {
  /// Clave de sección, para poder señalarla en la lista de pendientes.
  final String seccion;

  /// De dónde salió la suma: 'gruposEtarios', 'proteccion' o 'familias'.
  final String origen;

  final int suma;
  final int total;

  /// `true` si impide guardar, como el hard-block de `calcularSeccionesCompletas`.
  final bool bloqueaEnvio;

  const EdanAvisoPoblacion({
    required this.seccion,
    required this.origen,
    required this.suma,
    required this.total,
    this.bloqueaEnvio = true,
  });

  /// El texto del banner del wizard, textual.
  String get mensaje => switch (origen) {
        'gruposEtarios' =>
          'La suma de grupos etarios ($suma) supera el total de población '
              'afectada ($total). Verifica los datos antes de continuar.',
        'proteccion' =>
          'La suma de personas vulnerables ($suma) supera el total de población '
              'afectada ($total). Verifica los datos antes de continuar.',
        _ =>
          'Familias damnificadas ($suma) supera a familias afectadas ($total). '
              'Verifica los datos antes de continuar.',
      };

  @override
  String toString() => 'EdanAvisoPoblacion($seccion/$origen: $mensaje)';
}

/// Suma de fallecidos + heridos + desaparecidos de todos los grupos etarios.
///
/// Ojo con una diferencia respecto al wizard: `sumaGruposEtarios` en
/// `models/edan.dart` solo mira `impactoPoblacion[0]`, porque ahí hay un único
/// registro con `grupoEtario == 'Total'`. Acá se suman todos los grupos, que es
/// lo que la persona quiso decir. Sumar solo el primero dejaría pasar justo el
/// caso que el control existe para cazar.
int sumaGruposEtarios(EdanBorradorIa b) => b.impactoPoblacion.fold<int>(
      0,
      (acc, g) =>
          acc + (g.fallecidos ?? 0) + (g.heridos ?? 0) + (g.desaparecidos ?? 0),
    );

/// La protección suma `mujeres + hombres`, como en el wizard, donde el total es
/// un getter derivado. Si el modelo mandó un total suelto sin desglose se usa
/// ese: es el dato que la persona dio.
int sumaProteccion(EdanBorradorIa b) => b.proteccion.fold<int>(
      0,
      (acc, g) => acc + (g.total ?? ((g.mujeres ?? 0) + (g.hombres ?? 0))),
    );

/// Los topes del wizard que el borrador puede expresar, más la coherencia entre
/// los dos totales de familias.
///
/// El tope solo se evalúa si hay total: con `totalAfectada` en 0 no se dice
/// nada, que es lo que hace el banner del wizard.
List<EdanAvisoPoblacion> validarPoblacion(EdanBorradorIa b) {
  final avisos = <EdanAvisoPoblacion>[];
  final total = b.totalAfectada ?? 0;

  if (total > 0) {
    void cap(String seccion, String origen, int suma) {
      if (suma > total) {
        avisos.add(EdanAvisoPoblacion(
          seccion: seccion,
          origen: origen,
          suma: suma,
          total: total,
        ));
      }
    }

    cap('impacto-poblacion', 'gruposEtarios', sumaGruposEtarios(b));
    cap('proteccion', 'proteccion', sumaProteccion(b));
  }

  // No está en el wizard, pero es la incoherencia que más se cuela al hablar:
  // "100 familias damnificadas de 5 afectadas" no puede ser cierto. Va con
  // `bloqueaEnvio: false` porque el wizard no lo bloquea, y bloquear de más en
  // una evaluación de daños es peor que avisar.
  final afectadas = b.totalFamiliasAfectadas ?? 0;
  final damnificadas = b.totalFamiliasDamnificadas ?? 0;
  if (afectadas > 0 && damnificadas > afectadas) {
    avisos.add(EdanAvisoPoblacion(
      seccion: 'cabecera',
      origen: 'familias',
      suma: damnificadas,
      total: afectadas,
      bloqueaEnvio: false,
    ));
  }

  return avisos;
}

/// `true` si algún aviso impide guardar, igual que el botón de enviar del
/// wizard.
bool bloqueaEnvioPorPoblacion(EdanBorradorIa b) =>
    validarPoblacion(b).any((a) => a.bloqueaEnvio);
