/// Lo que el modelo ve del borrador: los valores, no solo el relleno.
///
/// Sin esto el asistente es un formulario con otra voz: sabe qué secciones
/// están llenas, pero no cuánto dijo la persona ni si se contradice. Estas
/// pruebas fijan qué tiene que llegarle al prompt.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rea/models/edan_borrador_ia.dart';
import 'package:rea/services/edan_ia/edan_estado_asistente.dart';

void main() {
  group('el estado que ve el modelo', () {
    test('lleva los totales, para poder compararlos con lo nuevo', () {
      final b = EdanBorradorIa()
        ..municipio = 'Yapacaní'
        ..totalAfectada = 350
        ..totalFamiliasAfectadas = 80
        ..totalFamiliasDamnificadas = 30;

      final t = estadoParaAsistente(b);

      expect(t, contains('Yapacaní'));
      expect(t, contains('350'));
      expect(t, contains('80'));
      expect(t, contains('30'));
    });

    test('lleva los grupos etarios con sus números', () {
      final b = EdanBorradorIa()
        ..impactoPoblacion = [
          BchImpactoFila('Niños')
            ..heridos = 12
            ..observaciones = 'en la escuela',
          BchImpactoFila('Adultos mayores')..fallecidos = 3,
        ];

      final t = estadoParaAsistente(b);

      expect(t, contains('Niños: 12 heridos (en la escuela)'));
      expect(t, contains('Adultos mayores: 3 fallecidos'));
    });

    test('no lista las filas que están en blanco', () {
      final b = EdanBorradorIa()
        ..impactoPoblacion = [
          BchImpactoFila('Niños'),
          BchImpactoFila('Adultos')..heridos = 2,
        ];

      final t = estadoParaAsistente(b);

      expect(t, isNot(contains('Niños:')));
      expect(t, contains('Adultos: 2 heridos'));
    });

    test('lleva las listas con nombre, no con el índice', () {
      final b = EdanBorradorIa()
        ..infraVial = [
          BchDanoVial(via: 'Ruta 1', tramo: 'km 12')..danoTotal = 'Puente caído',
        ]
        ..danosVivienda = [
          BchDanoVivienda(comunidad: 'San Pedro')
            ..danoTotal = 4
            ..danoParcial = 9,
        ];

      final t = estadoParaAsistente(b);

      expect(t, contains('Vía Ruta 1'));
      expect(t, contains('San Pedro'));
      expect(t, contains('9 parciales'));
      expect(t, contains('4 totales'));
    });

    test('lleva los campos de cantidad de la agricultura y la ganadería', () {
      final b = EdanBorradorIa()
        ..agricultura = [BchAgricultura(cultivo: 'Caña')..hasAfectadas = 12]
        ..pecuario = [BchPecuario(especie: 'Vacas')..animalesAfectados = 30];

      final t = estadoParaAsistente(b);

      expect(t, contains('Caña'));
      expect(t, contains('12 ha afectadas'));
      expect(t, contains('30 afectados'));
    });

    test('no manda un bloque vacío al prompt', () {
      expect(estadoParaAsistente(EdanBorradorIa()), isEmpty);
    });

    test('un cero explícito no se confunde con un dato', () {
      final b = EdanBorradorIa()
        ..municipio = 'Yapacaní'
        ..totalAfectada = 0;

      final t = estadoParaAsistente(b);

      expect(t, contains('Yapacaní'));
      // El total en 0 no es un dato: si se mandara, el modelo lo leería como
      // "no hay afectados" y dejaría de preguntar por el dato que falta.
      expect(t, isNot(contains('Población total afectada: 0')));
    });
  });

  group('los avisos que ve el modelo', () {
    test('le llega el desajuste, con la instrucción de preguntar', () {
      final b = EdanBorradorIa()
        ..totalAfectada = 100
        ..impactoPoblacion = [BchImpactoFila('Niños')..heridos = 400];

      final t = avisosParaAsistente(b);

      expect(t, contains('400'));
      expect(t, contains('100'));
      expect(t, contains('Preguntale'));
      expect(t.toLowerCase(), contains('sin reprochar'));
    });

    test('no hay bloque de avisos cuando todo cierra', () {
      final b = EdanBorradorIa()..totalAfectada = 100;

      expect(avisosParaAsistente(b), isEmpty);
    });
  });
}
