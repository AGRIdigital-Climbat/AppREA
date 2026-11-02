/// Orden de listados (2026-10-18): fecha de llenado más reciente arriba, en
/// Inicio RESP, Reportes y Localidades UGR; sin `fechaLlenado` manda
/// `fechaModificacion` y esas filas quedan después.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rea/models/edan.dart';

void main() {
  EdanLocalidad _l({String? llenado, String? modif}) => EdanLocalidad(
        nombre: 'L',
        idTipoEvento: 1,
        fechaLlenado: llenado,
        fechaModificacion: modif,
      );

  test('descendente por fechaLlenado ISO', () {
    final vieja = _l(llenado: '2026-10-15');
    final media = _l(llenado: '2026-10-17');
    final nueva = _l(llenado: '2026-10-18');
    final lista = [vieja, nueva, media]..sort(compararRecientePrimero);
    expect(lista.map((l) => l.fechaLlenado), [
      '2026-10-18',
      '2026-10-17',
      '2026-10-15',
    ]);
  });

  test('fechaLlenado ISO con hora sigue el mismo orden', () {
    final a = _l(llenado: '2026-10-17T09:00:00.000');
    final b = _l(llenado: '2026-10-17T21:30:00.000');
    final lista = [a, b]..sort(compararRecientePrimero);
    expect(lista.first, b);
  });

  test('sin fechaLlenado: decide fechaModificacion y quedan debajo', () {
    final conLlenado = _l(llenado: '2026-10-01');
    final viejoSin = _l(modif: '2026-10-19T00:00:00');
    final nuevoSin = _l(modif: '2026-10-20T00:00:00');
    final lista = [viejoSin, conLlenado, nuevoSin]..sort(compararRecientePrimero);
    expect(
      lista.map((l) => l.fechaLlenado ?? l.fechaModificacion).toList(),
      ['2026-10-01', '2026-10-20T00:00:00', '2026-10-19T00:00:00'],
    );
  });

  test('sin ninguna fecha: estables al final', () {
    final x = _l();
    final y = _l(llenado: '2026-01-01');
    final lista = [x, y]..sort(compararRecientePrimero);
    expect(lista.first, y);
    expect(lista.last, x);
  });

  test('empates de llenado conservan orden descendente por modificación', () {
    final a = _l(llenado: '2026-10-17', modif: '2026-10-17T08:00:00');
    final b = _l(llenado: '2026-10-17', modif: '2026-10-17T18:00:00');
    final lista = [a, b]..sort(compararRecientePrimero);
    expect(lista.first, b);
  });
}
