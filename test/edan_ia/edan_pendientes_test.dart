/// El listado de variables vacías que se le manda al modelo para que pregunte
/// por un hueco concreto en vez de adivinar dentro de una sección.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rea/models/edan_borrador_ia.dart';
import 'package:rea/services/edan_ia/edan_pendientes.dart';

void main() {
  group('variablesVacias', () {
    test('con la ficha vacía arranca por el lugar y el tipo de evento', () {
      final v = variablesVacias(EdanBorradorIa(), maximo: 5);
      expect(v.map((x) => x.clave), contains('municipio'));
      expect(v.map((x) => x.clave), contains('tipoEvento'));
    });

    test('respeta el máximo pedido', () {
      expect(variablesVacias(EdanBorradorIa(), maximo: 5).length, 5);
      expect(variablesVacias(EdanBorradorIa(), maximo: 3).length, 3);
      expect(variablesVacias(EdanBorradorIa(), maximo: 99).length,
          lessThanOrEqualTo(30));
    });

    test('el orden es estable entre llamadas', () {
      final b = EdanBorradorIa();
      expect(
        variablesVacias(b, maximo: 8).map((v) => v.clave).toList(),
        variablesVacias(b, maximo: 8).map((v) => v.clave).toList(),
      );
    });

    test('una variable llenada desaparece de la lista', () {
      final b = EdanBorradorIa()..municipio = 'Yapacaní';
      final claves = variablesVacias(b, maximo: 99).map((v) => v.clave);
      expect(claves, isNot(contains('municipio')));
      expect(claves, contains('provincia'));
    });

    test('el conteo lleno saca la pregunta de totalAfectada', () {
      final b = EdanBorradorIa()..totalAfectada = 350;
      final claves = variablesVacias(b, maximo: 99).map((v) => v.clave);
      expect(claves, isNot(contains('totalAfectada')));
    });

    test('sin evento marcado se pregunta el tipo de evento', () {
      final claves = variablesVacias(EdanBorradorIa(), maximo: 99)
          .map((v) => v.clave)
          .toList();
      expect(claves, contains('tipoEvento'));
    });

    test('con evento marcado se pregunta el detalle, no el tipo', () {
      final b = EdanBorradorIa()..tipoEvento['inundacion'] = true;
      final claves = variablesVacias(b, maximo: 99).map((v) => v.clave).toList();
      expect(claves, isNot(contains('tipoEvento')));
      expect(claves, contains('fechaEvento'));
    });
  });

  group('necesidades humanitarias, en dos tiempos', () {
    test('sin nada marcado se pregunta qué necesitan', () {
      final b = EdanBorradorIa();
      final v = variablesVacias(b, maximo: 99);
      final necesidad = v.firstWhere(
        (x) => x.bloque == 'necesidad-humanitaria',
      );
      expect(necesidad.clave, 'necesidadesHumanitarias');
    });

    test('con algo marcado se pregunta el detalle de eso, no el general', () {
      final b = EdanBorradorIa()
        ..necesidadesHumanitarias
            .firstWhere((f) => f.item == 'Alimentos')
            .si = true;

      final v = variablesVacias(b, maximo: 99);
      final bloque = v.where((x) => x.bloque == 'necesidad-humanitaria');

      expect(bloque, hasLength(1));
      expect(bloque.single.clave, 'necesidadesHumanitarias.Alimentos');
      expect(bloque.single.pregunta, contains('alimentos'));
    });

    test('con el detalle ya anotado se pasa a la otra necesidad', () {
      final b = EdanBorradorIa();
      final alimentos =
          b.necesidadesHumanitarias.firstWhere((f) => f.item == 'Alimentos')
            ..si = true
            ..observaciones = 'Arroz y aceite';
      b.necesidadesHumanitarias.firstWhere((f) => f.item == 'Ropa de Cama').si = true;

      final claves = variablesVacias(b, maximo: 99).map((v) => v.clave);
      expect(claves, isNot(contains('necesidadesHumanitarias.Alimentos')));
      expect(claves, contains('necesidadesHumanitarias.Ropa de Cama'));
      expect(alimentos.observaciones, 'Arroz y aceite');
    });
  });

  group('la lista se acorta a medida que se llena', () {
    test('cada variable llenada reduce el total pendiente', () {
      final vacio = EdanBorradorIa();
      final totalInicial = variablesVacias(vacio, maximo: 99).length;

      final b = EdanBorradorIa()
        ..municipio = 'Yapacaní'
        ..provincia = 'Ichilo'
        ..departamento = 'Santa Cruz'
        ..tipoEvento['inundacion'] = true
        ..fechaEvento = '2026-09-28'
        ..totalAfectada = 350
        ..totalFamiliasAfectadas = 80;

      final totalFinal = variablesVacias(b, maximo: 99).length;
      expect(totalFinal, lessThan(totalInicial));
    });
  });

  group('variablesVaciasPorBloque', () {
    test('agrupa por bloque', () {
      final m = variablesVaciasPorBloque(EdanBorradorIa(), maximo: 99);
      expect(m.keys, contains('cabecera'));
      expect(m.keys, contains('servicios-basicos'));
      expect(m['servicios-basicos'], hasLength(5));
    });

    test('preguntasDeRespaldo devuelve las frases en orden', () {
      final f = preguntasDeRespaldo(EdanBorradorIa(), maximo: 3);
      expect(f, hasLength(3));
      expect(f.every((x) => x.startsWith('¿')), isTrue);
    });
  });
}
