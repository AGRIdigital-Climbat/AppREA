/// Los topes de población del wizard, aplicados al borrador de la IA.
///
/// Se prueban los tres casos que importan: que el tope se respete, que no
/// salte cuando el total es cero, y que la regla nueva de familias no bloquee
/// el guardado como sí hacen las del wizard.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rea/models/edan_borrador_ia.dart';
import 'package:rea/services/edan_ia/edan_reglas_poblacion.dart';

void main() {
  group('grupos etarios', () {
    test('avisa si la suma de la tabla supera el total de población', () {
      final b = EdanBorradorIa()
        ..totalAfectada = 100
        ..impactoPoblacion = [
          BchImpactoFila('Niños')
            ..heridos = 60,
          BchImpactoFila('Adultos mayores')..heridos = 50,
        ];

      final avisos = validarPoblacion(b);

      expect(avisos, hasLength(1));
      expect(avisos.first.seccion, 'impacto-poblacion');
      expect(avisos.first.suma, 110);
      expect(avisos.first.total, 100);
      expect(avisos.first.mensaje, contains('110'));
      expect(avisos.first.mensaje, contains('100'));
      expect(bloqueaEnvioPorPoblacion(b), isTrue);
    });

    test('suma todos los grupos, no solo el primero', () {
      // La diferencia con `EdanLocalidad.sumaGruposEtarios`, que mira un único
      // registro: si solo mirara el primero, estos 10 no saltarían.
      final b = EdanBorradorIa()
        ..totalAfectada = 20
        ..impactoPoblacion = [
          BchImpactoFila('Niños')..heridos = 10,
          BchImpactoFila('Adultos mayores')..heridos = 15,
        ];

      expect(sumaGruposEtarios(b), 25);
      expect(validarPoblacion(b), isNotEmpty);
    });

    test('no dice nada mientras no haya total de población', () {
      // Con el total en 0 el total de familias se infiere de la tabla, así que
      // un tope en contra sería inventar una regla.
      final b = EdanBorradorIa()
        ..impactoPoblacion = [
          BchImpactoFila('Niños')..heridos = 400,
        ];

      expect(validarPoblacion(b), isEmpty);
      expect(bloqueaEnvioPorPoblacion(b), isFalse);
    });

    test('no avisa si la suma queda justo en el total', () {
      final b = EdanBorradorIa()
        ..totalAfectada = 100
        ..impactoPoblacion = [
          BchImpactoFila('Niños')
            ..fallecidos = 10
            ..heridos = 60
            ..desaparecidos = 30,
        ];

      expect(validarPoblacion(b), isEmpty);
    });
  });

  group('protección', () {
    test('usa el desglose por sexo cuando hay', () {
      final b = EdanBorradorIa()
        ..totalAfectada = 50
        ..proteccion = [
          BchProteccionFila('Mujeres')
            ..mujeres = 30
            ..hombres = 25,
        ];

      expect(sumaProteccion(b), 55);
      expect(validarPoblacion(b).first.seccion, 'proteccion');
    });

    test('usa el total suelto cuando no hay desglose', () {
      final b = EdanBorradorIa()
        ..totalAfectada = 200
        ..proteccion = [BchProteccionFila('Niños')..total = 210];

      expect(sumaProteccion(b), 210);
      expect(validarPoblacion(b).first.suma, 210);
    });
  });

  group('no se inventan topes donde no hay el dato', () {
    test('una escuela grande en un pueblo chico no dispara aviso', () {
      // El tope del wizard suma `totalAfectados` por unidad educativa. El
      // borrador solo tiene `estudiantes`, que es el tamaño de la escuela: usar
      // ese número daría un aviso falso en cada ficha con escuela.
      final b = EdanBorradorIa()
        ..totalAfectada = 300
        ..educacion = [
          BchUnidadEducativa(establecimiento: 'Colegio Central')
            ..estudiantes = 900,
        ];

      expect(validarPoblacion(b), isEmpty);
    });

    test('el borrador no tiene personal de salud por establecimiento', () {
      // El tope de salud del wizard no se puede replicar: el dato no existe
      // acá. Esta prueba falla el día que se porte el campo, que es justo
      // cuando hay que revisar la regla.
      final b = EdanBorradorIa()
        ..totalAfectada = 100
        ..saludDanios = [
          BchEstablecimientoSalud(establecimiento: 'Hospital San Juan'),
        ];

      expect(validarPoblacion(b), isEmpty);
    });
  });

  group('coherencia de familias', () {
    test('avisa si hay más damnificadas que afectadas, sin bloquear', () {
      final b = EdanBorradorIa()
        ..totalFamiliasAfectadas = 50
        ..totalFamiliasDamnificadas = 120;

      final avisos = validarPoblacion(b);

      expect(avisos, hasLength(1));
      expect(avisos.first.seccion, 'cabecera');
      expect(avisos.first.mensaje, contains('120'));
      expect(avisos.first.mensaje, contains('50'));
      // El wizard no lo bloquea, y bloquear de más en una evaluación de daños
      // deja gente sin reportar.
      expect(avisos.first.bloqueaEnvio, isFalse);
      expect(bloqueaEnvioPorPoblacion(b), isFalse);
    });

    test('acepta damnificadas iguales a afectadas', () {
      final b = EdanBorradorIa()
        ..totalFamiliasAfectadas = 50
        ..totalFamiliasDamnificadas = 50;

      expect(validarPoblacion(b), isEmpty);
    });

    test('no juzga si no se declaró cuántas familias están afectadas', () {
      // Sin afectadas no hay contra qué comparar: 300 damnificadas puede ser
      // perfectamente válido si hay 400 afectadas en total.
      final b = EdanBorradorIa()..totalFamiliasDamnificadas = 300;

      expect(validarPoblacion(b), isEmpty);
    });
  });

  group('el aviso', () {
    test('no dice el nombre de ninguna pantalla', () {
      const a = EdanAvisoPoblacion(
        seccion: 'impacto-poblacion',
        origen: 'gruposEtarios',
        suma: 10,
        total: 5,
      );
      final t = a.mensaje.toLowerCase();
      expect(t, isNot(contains('wizard')));
      expect(t, isNot(contains('página')));
      expect(t, isNot(contains('banner')));
    });
  });
}
