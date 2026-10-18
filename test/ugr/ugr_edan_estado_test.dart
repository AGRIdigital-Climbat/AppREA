/// Parseo del estado del EDAN padre: los GET nuevos de la familia cabecera
/// (§20.16/§20.17) traen `estado_edan: {id_estado, nombre}` anidado, no el
/// `estado` plano viejo. `Edan.fromJson` debe leer ambas formas.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rea/models/edan.dart';

void main() {
  group('Edan.fromJson estado_edan (nueva familia cabecera)', () {
    test('estado_edan anidado => nombre e id correctos', () {
      final e = Edan.fromJson({
        'id_edan': 17000,
        'uuid_edan': '11111111-2222-4333-8444-555555555555',
        'estado_edan': {'id_estado': 3, 'nombre': 'Aprobado'},
      });
      expect(e.estado, 'Aprobado');
      expect(e.idEstado, 3);
    });

    test('forma vieja `estado` string sigue funcionando', () {
      final e = Edan.fromJson({
        'id_edan': 1,
        'estado': 'enviado',
      });
      expect(e.estado, 'enviado');
    });

    test('forma vieja `estado` map (nombre/id_estado) sigue funcionando', () {
      final e = Edan.fromJson({
        'id_edan': 2,
        'estado': {'id_estado': 5, 'nombre': 'Rechazado'},
      });
      expect(e.estado, 'Rechazado');
      expect(e.idEstado, 5);
    });

    test('`id_estado` plano tiene prioridad sobre el nodo', () {
      final e = Edan.fromJson({
        'id_edan': 3,
        'id_estado': 2,
        'estado_edan': {'id_estado': 9, 'nombre': 'Otro'},
      });
      expect(e.idEstado, 2);
      expect(e.estado, 'Otro', reason: 'nombre solo viene del nodo');
    });

    test('sin estado => default borrador/1 (nunca vacío)', () {
      final e = Edan.fromJson({'id_edan': 4});
      expect(e.estado, 'borrador');
      expect(e.idEstado, 1);
    });
  });
}
