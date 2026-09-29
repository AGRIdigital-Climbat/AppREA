/// La 1:1 y la 1:N a través del camino real: puente → parche → borrador.
///
/// Las pruebas del fusionador usan parches armados a mano. Estas pasan por el
/// mismo camino que usa la conversación, incluida la validación que descarta
/// lo que el modelo inventa, porque un 1:N que funciona en pruebas y falla con
/// el modelo real no sirve de nada.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rea/providers/edan_ia_borrador_provider.dart';
import 'package:rea/services/edan_ia/puente_service.dart';

class _VozFalsa implements EdanIaVoz {
  @override
  Future<void> hablar(String texto) async {}
  @override
  Future<void> detener() async {}
  @override
  Future<void> detenerEscucha() async {}
  @override
  Future<void> escuchar({
    required void Function(String texto) onResultado,
    required void Function() onFin,
  }) async =>
      onFin();
}

/// Provider que responde con un turno distinto en cada llamada, como si la
/// persona fuera hablando turno a turno.
EdanIaBorradorProvider _conTurnos(List<Map<String, Object?>> turnos) {
  var i = 0;
  final cliente = MockClient((_) async {
    if (i >= turnos.length) return http.Response.bytes(const [], 200);
    final parche = turnos[i++];
    // SSE del puente: el parche viaja en el evento `json` y el `done` lo
    // confirma. El parche vacío va explícito para que el provider pruebe la
    // pasada de reparación igual que con el proveedor real.
    final sse = [
      'data: ${jsonEncode({'tipo': 'token', 'texto': 'ok'})}',
      'data: ${jsonEncode({
            'tipo': 'json',
            'json': {'parche': parche},
          })}',
      'data: ${jsonEncode({
            'tipo': 'done',
            'respuesta': 'ok',
            'json': {'parche': parche},
            'formato': 'json',
            'modelo': 'openai/gpt-oss-20b',
            'proveedor': 'Groq-adrian',
            'intentos': 1,
            'tokens': {'entrada': 1, 'salida': 1, 'razonamiento': 0},
            'avisos': <String>[],
          })}',
      'data: [DONE]',
    ].join('\n');
    return http.Response.bytes(utf8.encode(sse), 200);
  });
  return EdanIaBorradorProvider(
    puente: PuenteService(
      baseUrl: 'https://test.puente',
      apiKey: 'llave',
      client: cliente,
    ),
    voz: _VozFalsa(),
  );
}

void main() {
  group('secciones 1:1', () {
    test('el segundo turno corrige sin borrar lo demás', () async {
      final p = _conTurnos([
        {'municipio': 'Yapacaní', 'totalAfectada': 40, 'totalFamiliasAfectadas': 12},
        {'totalAfectada': 55},
      ]);

      await p.enviar('llovió en Yapacaní');
      await p.enviar('son 55 los que se mojaron');

      expect(p.borrador.totalAfectada, 55, reason: 'el dato nuevo entra');
      expect(p.borrador.municipio, 'Yapacaní', reason: 'lo otro no se toca');
      expect(p.borrador.totalFamiliasAfectadas, 12);
    });

    test('un campo que el modelo no menciona se queda como estaba', () async {
      final p = _conTurnos([
        {'alcalde': 'María López'},
        {'telefono': '70012345'},
      ]);

      await p.enviar('la alcaldesa es María López');
      await p.enviar('su teléfono es 70012345');

      expect(p.borrador.alcalde, 'María López');
      expect(p.borrador.telefono, '70012345');
    });

    test('el parche de un turno no pisa con vacíos', () async {
      final p = _conTurnos([
        {'municipio': 'Yapacaní', 'provincia': 'Ichilo'},
        {'municipio': '', 'provincia': ''},
      ]);

      await p.enviar('soy de Yapacaní, provincia Ichilo');
      await p.enviar('no sé, se me olvidó');

      expect(p.borrador.municipio, 'Yapacaní');
      expect(p.borrador.provincia, 'Ichilo');
    });
  });

  group('secciones 1:N, dos turnos', () {
    test('cada elemento con nombre distinto es una fila distinta', () async {
      final p = _conTurnos([
        {
          'infraVial': [
            {'via': 'Puente San Carlos', 'kmDanio': '1', 'danoTotal': 'Total'},
          ],
        },
        {
          'infraVial': [
            {'via': 'Puente Ichilo', 'kmDanio': '2', 'danoTotal': 'Total'},
          ],
        },
      ]);

      await p.enviar('se cayó el puente San Carlos');
      await p.enviar('también el Ichilo');

      expect(p.borrador.infraVial, hasLength(2));
      expect(p.borrador.infraVial.first.via, 'Puente San Carlos');
      expect(p.borrador.infraVial.last.via, 'Puente Ichilo');
    });

    test('un nombre repetido actualiza la fila, no la duplica', () async {
      final p = _conTurnos([
        {
          'infraVial': [
            {'via': 'Puente San Carlos', 'kmDanio': '1', 'danoTotal': 'Total'},
          ],
        },
        {
          'infraVial': [
            {'via': 'Puente San Carlos', 'kmDanio': '3', 'necesidades': 'Maquinaria'},
          ],
        },
      ]);

      await p.enviar('se cayó el puente San Carlos, un kilómetro');
      await p.enviar('son tres kilómetros y hace falta maquinaria');

      expect(p.borrador.infraVial, hasLength(1), reason: 'no debe duplicar');
      expect(p.borrador.infraVial.single.kmDanio, '3');
      expect(p.borrador.infraVial.single.danoTotal, 'Total',
          reason: 'lo del turno anterior se conserva');
      expect(p.borrador.infraVial.single.necesidades, 'Maquinaria');
    });

    test('el nombre se compara sin tildes ni mayúsculas', () async {
      final p = _conTurnos([
        {
          'infraVial': [
            {'via': 'Puente San Carlos', 'kmDanio': '1', 'danoTotal': 'Total'},
          ],
        },
        {
          'infraVial': [
            {'via': '  puente san carlos ', 'kmDanio': '2'},
          ],
        },
      ]);

      await p.enviar('se cayó el puente San Carlos');
      await p.enviar('el puente san carlos son dos kilómetros');

      expect(p.borrador.infraVial, hasLength(1));
      expect(p.borrador.infraVial.single.kmDanio, '2');
    });
  });

  group('secciones 1:N, dos elementos en el mismo turno', () {
    test('el modelo puede mandar dos filas de una vez', () async {
      final p = _conTurnos([
        {
          'infraVial': [
            {'via': 'Puente San Carlos', 'kmDanio': '1', 'danoTotal': 'Total'},
            {'via': 'Puente Ichilo', 'kmDanio': '2', 'danoTotal': 'Total'},
          ],
        },
      ]);

      await p.enviar('se cayeron dos puentes');

      expect(p.borrador.infraVial, hasLength(2));
    });

    test('las nueve secciones 1:n admiten varias filas', () async {
      final p = _conTurnos([
        {
          'infraVial': [
            {'via': 'A', 'danoTotal': 'Total'},
            {'via': 'B', 'danoTotal': 'Total'},
          ],
          'infraPublica': [
            {'comunidad': 'San Pedro', 'tipoEstructura': 'Escuela', 'danoTotal': 'Total'},
            {'comunidad': 'Santa Rosa', 'tipoEstructura': 'Parque', 'danoTotal': 'Total'},
          ],
          'infraProductiva': [
            {'tipo': 'Silos', 'danoTotal': 'Total'},
            {'tipo': 'Cañal', 'danoTotal': 'Total'},
          ],
          'saludDanios': [
            {'establecimiento': 'Hospital', 'dano': 'Total'},
            {'establecimiento': 'Puesto de salud', 'dano': 'Parcial'},
          ],
          'educacion': [
            {'establecimiento': 'Escuela 1', 'danoTotal': 'Total'},
            {'establecimiento': 'Escuela 2', 'danoTotal': 'Total'},
          ],
          'danosVivienda': [
            {'comunidad': 'San Pedro', 'danoParcial': 10},
            {'comunidad': 'Santa Rosa', 'danoParcial': 4},
          ],
          'agricultura': [
            {'cultivo': 'Maíz', 'hasAfectadas': 120},
            {'cultivo': 'Trigo', 'hasAfectadas': 80},
          ],
          'pecuario': [
            {'especie': 'Vacas', 'animalesAfectados': 40},
            {'especie': 'Pollos', 'animalesAfectados': 300},
          ],
        },
      ]);

      await p.enviar('se dañó de todo');

      expect(p.borrador.infraVial, hasLength(2));
      expect(p.borrador.infraPublica, hasLength(2));
      expect(p.borrador.infraProductiva, hasLength(2));
      expect(p.borrador.saludDanios, hasLength(2));
      expect(p.borrador.educacion, hasLength(2));
      expect(p.borrador.danosVivienda, hasLength(2));
      expect(p.borrador.agricultura, hasLength(2));
      expect(p.borrador.pecuario, hasLength(2));

      // Y llegan enteras a las filas de SQLite, con su clave de sección.
      final r = p.prepararGuardado();
      expect(r.localidad.danosViales, hasLength(2));
      expect(r.localidad.establecimientosSalud, hasLength(2));
      expect(r.localidad.unidadesEducativas, hasLength(2));
      expect(r.localidad.danosAgricultura, hasLength(2));
      expect(r.seccionesActivas, contains('danos-viales'));
      expect(r.seccionesActivas, contains('danos-pecuarios'));
    });
  });

  group('lo que el modelo no puede hacer con las filas', () {
    test('una fila totalmente vacía no se agrega', () async {
      final p = _conTurnos([
        {
          'infraVial': [
            {'via': ''},
          ],
        },
      ]);

      await p.enviar('hubo daños');

      expect(p.borrador.infraVial, isEmpty);
    });

    test('una fila sin nombre pero con datos sí se guarda', () async {
      // No se tira información: la persona dijo que hubo daño total aunque no
      // nombrara el lugar. La fila queda esperando su nombre.
      final p = _conTurnos([
        {
          'infraVial': [
            {'danoTotal': 'Total'},
          ],
        },
      ]);

      await p.enviar('hubo daños');

      expect(p.borrador.infraVial, hasLength(1));
      expect(p.borrador.infraVial.single.danoTotal, 'Total');
    });

    test('los campos de sincronización los pone el sistema, no el modelo', () async {
      final p = _conTurnos([
        {
          'idLocal': 'inventado',
          'sincronizado': true,
          'municipio': 'Yapacaní',
        },
      ]);

      await p.enviar('soy de Yapacaní');

      expect(p.borrador.municipio, 'Yapacaní');
      // Y al traducir, el id que inventó el modelo no aparece.
      expect(p.prepararGuardado().localidad.idLocal, isNot('inventado'));
    });
  });

  group('el caso sin nombre: la gente nombra después de describir', () {
    test('el nombre que llega después se pone en la fila sin nombre', () async {
      // Es el orden natural de una conversación: primero el daño, después el
      // nombre. Sin esto se guardaban dos filas y la mitad de lo dicho quedaba
      // en una huérfana.
      final p = _conTurnos([
        {
          'infraVial': [
            {'kmDanio': '1', 'danoTotal': 'Total'},
          ],
        },
        {
          'infraVial': [
            {'via': 'Puente San Carlos', 'kmDanio': '1'},
          ],
        },
      ]);

      await p.enviar('se cayó un puente, un kilómetro');
      await p.enviar('es el puente San Carlos');

      expect(p.borrador.infraVial, hasLength(1));
      expect(p.borrador.infraVial.single.via, 'Puente San Carlos');
      expect(p.borrador.infraVial.single.kmDanio, '1');
      expect(p.borrador.infraVial.single.danoTotal, 'Total');
    });

    test('el detalle que llega sin nombre se suma a la fila sin nombre', () async {
      final p = _conTurnos([
        {
          'infraVial': [
            {'danoTotal': 'Total'},
          ],
        },
        {
          'infraVial': [
            {'kmDanio': '3'},
          ],
        },
      ]);

      await p.enviar('se cayó un puente');
      await p.enviar('son tres kilómetros');

      expect(p.borrador.infraVial, hasLength(1));
      expect(p.borrador.infraVial.single.kmDanio, '3');
      expect(p.borrador.infraVial.single.danoTotal, 'Total');
    });

    test('con dos filas sin nombre no se apuesta cuál es cuál', () async {
      // Ambiguo de verdad: fusionar el nombre con la fila equivocada sería peor
      // que dejar una fila de más, que la persona puede corregir.
      final p = _conTurnos([
        {
          'infraVial': [
            {'danoTotal': 'Total'},
            {'danoParcial': 'Parcial'},
          ],
        },
        {
          'infraVial': [
            {'via': 'Puente San Carlos', 'kmDanio': '1'},
          ],
        },
      ]);

      await p.enviar('se cayó un puente y otro quedó mal');
      await p.enviar('el primero es el San Carlos');

      expect(p.borrador.infraVial, hasLength(3));
      expect(p.borrador.infraVial.last.via, 'Puente San Carlos');
    });

    test('las filas sin nombre de un mismo turno no se fusionan entre sí',
        () async {
      // El snapshot es previo al parche: dos puentes sin nombrar en la misma
      // frase son dos puentes, no uno repetido.
      final p = _conTurnos([
        {
          'infraVial': [
            {'kmDanio': '1', 'danoTotal': 'Total'},
            {'kmDanio': '2', 'danoTotal': 'Total'},
          ],
        },
      ]);

      await p.enviar('se cayeron dos puentes');

      expect(p.borrador.infraVial, hasLength(2));
    });

    test('el nombre no se roba de otra sección', () async {
      // La clave natural es por sección: un hospital no es un puente.
      final p = _conTurnos([
        {
          'infraVial': [
            {'danoTotal': 'Total'},
          ],
          'saludDanios': [
            {'dano': 'Total'},
          ],
        },
        {
          'infraVial': [
            {'via': 'Hospital', 'kmDanio': '1'},
          ],
        },
      ]);

      await p.enviar('se cayó algo y el hospital también');
      await p.enviar('el del puente se llama Hospital');

      expect(p.borrador.infraVial, hasLength(1));
      expect(p.borrador.infraVial.single.via, 'Hospital');
      expect(p.borrador.saludDanios, hasLength(1),
          reason: 'la fila de salud no se toca desde otra sección');
    });
  });
}
