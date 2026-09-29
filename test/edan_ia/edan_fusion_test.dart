/// Puerto de `EDAN-Tutor/tests/merge.test.js` más las reglas de no-destrucción
/// que hacen seguro acumular mensajes durante una entrevista.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rea/models/edan_borrador_ia.dart';
import 'package:rea/services/edan_ia/edan_fusion.dart';
import 'package:rea/services/edan_ia/edan_parche.dart';

/// Parche mínimo con un solo campo, para las pruebas de regla única.
EdanParche parcheCon(
        {String? municipio,
        int? totalAfectada,
        int? totalFamiliasAfectadas,
        Map<String, int?> proteccion = const {},
        Map<String, bool?> necesidades = const {},
        Map<String, bool?> primeraRespuesta = const {},
        List<BchAgricultura> agricultura = const [],
        List<BchPecuario> pecuario = const [],
        List<BchComunidad> comunidades = const [],
        Map<String, Map<String, Object?>> impacto = const {},
        Map<String, bool> eventos = const {},
        Map<String, Map<String, String?>> servicios = const {},
        List<BchUnidadEducativa> educacion = const []}) =>
    EdanParche()
      ..municipio = municipio
      ..totalAfectada = totalAfectada
      ..totalFamiliasAfectadas = totalFamiliasAfectadas
      ..proteccion.addAll({
        for (final e in proteccion.entries)
          e.key: BchProteccionFila(e.key, total: e.value),
      })
      ..necesidadesHumanitarias.addAll(necesidades)
      ..primeraRespuesta.addAll(primeraRespuesta)
      ..agricultura = List.of(agricultura)
      ..pecuario = List.of(pecuario)
      ..comunidades = List.of(comunidades)
      ..impactoPoblacion.addAll(impacto)
      ..tipoEvento.addAll(eventos)
      ..serviciosBasicos.addAll(servicios)
      ..educacion = List.of(educacion);

void main() {
  group('fusiona escalares sin tocar lo demás', () {
    test('un campo no pisa a sus hermanos', () {
      final d = EdanBorradorIa();
      fusionar(d, parcheCon(municipio: 'Yapacaní'));
      expect(d.municipio, 'Yapacaní');
      expect(d.departamento, '');
      expect(d.alcalde, '');
    });
  });

  group('null y vacío NUNCA pisan un valor existente', () {
    test('null en cabecera', () {
      final d = EdanBorradorIa()..municipio = 'Rurrenabaque';
      fusionar(d, EdanParche()..municipio = null);
      expect(d.municipio, 'Rurrenabaque');
    });
    test('null en conteo', () {
      final d = EdanBorradorIa()..totalAfectada = 500;
      fusionar(d, EdanParche()..totalAfectada = null);
      expect(d.totalAfectada, 500);
    });
    test('texto vacío en una fila 1:n', () {
      final d = EdanBorradorIa()
        ..agricultura = [BchAgricultura(cultivo: 'Maíz', hasAfectadas: 120)];
      fusionar(d, parcheCon(agricultura: [BchAgricultura(cultivo: 'Maíz')]));
      expect(d.agricultura.single.hasAfectadas, 120,
          reason: 'un parche parcial no debe borrar lo ya anotado');
    });
    test('false no desactiva un evento ya marcado', () {
      final d = EdanBorradorIa()..tipoEvento['inundacion'] = true;
      fusionar(d, parcheCon(eventos: {'inundacion': false}));
      expect(d.tipoEvento['inundacion'], isTrue);
    });
  });

  group('los bloques de tamaño fijo nunca se colapsan', () {
    test('protección conserva sus 7 grupos', () {
      final d = EdanBorradorIa();
      expect(d.proteccion, hasLength(7));
      fusionar(d, parcheCon(proteccion: {'Niñas y Niños': 40}));
      expect(d.proteccion, hasLength(7));
      expect(d.proteccion.first.total, 40);
      expect(d.proteccion[1].grupo, 'Adolescentes');
    });
    test('impacto conserva sus 4 grupos', () {
      final d = EdanBorradorIa();
      fusionar(d, parcheCon(impacto: {
        'Niño(a) 0-5 años': {'fallecidos': 2},
      }));
      expect(d.impactoPoblacion, hasLength(4));
      expect(d.impactoDe('Niño(a) 0-5 años')!.fallecidos, 2);
      expect(d.impactoDe('Escolar 6-18 años')!.marcado, isFalse);
    });
    test('necesidades conservan sus 10 ítems', () {
      final d = EdanBorradorIa();
      fusionar(d, parcheCon(necesidades: {'Alimentos': true}));
      expect(d.necesidadesHumanitarias, hasLength(10));
      expect(d.necesidadDe('Alimentos')!.si, isTrue);
      expect(d.necesidadDe('Politubos')!.si, isFalse);
    });
    test('primera respuesta conserva sus 3 equipos', () {
      final d = EdanBorradorIa();
      fusionar(d, parcheCon(primeraRespuesta: {'busqueda': true}));
      expect(d.primeraRespuesta.busqueda, isTrue);
      expect(d.primeraRespuesta.evacuacion, isFalse);
    });
  });

  group('los bloques 1:1 se fusionan por etiqueta, no por posición', () {
    test('el orden del parche es irrelevante', () {
      final d = EdanBorradorIa();
      fusionar(d, parcheCon(proteccion: {'Mujeres Embarazadas': 10}));
      expect(d.proteccionDe('Mujeres Embarazadas')!.total, 10);
      expect(d.proteccion, hasLength(7));
    });
    test('una etiqueta desconocida se ignora sin romper', () {
      final d = EdanBorradorIa();
      fusionar(d, parcheCon(proteccion: {'Grupo Inventado': 5}));
      expect(d.proteccion, hasLength(7));
      expect(d.proteccionDe('Grupo Inventado'), isNull);
    });
  });

  group('las listas 1:n se fusionan por clave natural', () {
    test('una actualización parcial NO borra filas a mano', () {
      final d = EdanBorradorIa()
        ..agricultura = [
          BchAgricultura(cultivo: 'Maíz', hasAfectadas: 120),
          BchAgricultura(cultivo: 'Papa', hasAfectadas: 40),
        ];
      fusionar(d, parcheCon(agricultura: [
        BchAgricultura(cultivo: 'Maíz', hasAfectadas: 150),
      ]));
      expect(d.agricultura, hasLength(2), reason: 'la fila de Papa debe sobrevivir');
      expect(d.agricultura.first.hasAfectadas, 150);
      expect(d.agricultura.last.cultivo, 'Papa');
    });

    test('las filas a mano sobreviven y la nueva va al final', () {
      final d = EdanBorradorIa()
        ..agricultura = [
          BchAgricultura(cultivo: 'Trigo', hasAfectadas: 30),
          BchAgricultura(cultivo: 'Avena', hasAfectadas: 10),
        ];
      fusionar(d, parcheCon(agricultura: [
        BchAgricultura(cultivo: 'Maíz', hasAfectadas: 120),
      ]));
      expect(d.agricultura, hasLength(3));
      expect(d.agricultura.map((a) => a.cultivo), ['Trigo', 'Avena', 'Maíz']);
      expect(d.agricultura.last.hasAfectadas, 120);
    });

    test('la misma clave ACTUALIZA en vez de duplicar', () {
      final d = EdanBorradorIa()
        ..agricultura = [
          BchAgricultura(
            cultivo: 'Maíz',
            hasAfectadas: 120,
            necesidades: 'Semillas',
          ),
        ];
      fusionar(d, parcheCon(agricultura: [
        BchAgricultura(cultivo: 'Maíz', hasAfectadas: 150),
      ]));
      expect(d.agricultura, hasLength(1));
      expect(d.agricultura.first.hasAfectadas, 150);
      expect(d.agricultura.first.necesidades, 'Semillas',
          reason: 'no debe perder los otros campos');
    });

    test('la clave compara sin tildes, mayúsculas ni espacios', () {
      final d = EdanBorradorIa()
        ..agricultura = [BchAgricultura(cultivo: 'Maíz', hasAfectadas: 120)];
      fusionar(d, parcheCon(agricultura: [
        BchAgricultura(cultivo: '  maiz ', hasAfectadas: 150),
      ]));
      expect(d.agricultura, hasLength(1));
      expect(d.agricultura.first.cultivo, 'Maíz',
          reason: 'no debe perder el nombre bien escrito');
    });

    test('una fila entrante sin clave se añade sin tocar las demás', () {
      final d = EdanBorradorIa()
        ..comunidades = [BchComunidad(nombre: 'San Pedro')];
      fusionar(d, parcheCon(comunidades: [BchComunidad()]));
      expect(d.comunidades, hasLength(2));
      expect(d.comunidades.first.nombre, 'San Pedro');
      expect(d.comunidades.last.nombre, '');
    });

    test('el borrador no guarda referencias al parche', () {
      final fila = BchAgricultura(cultivo: 'Maíz', hasAfectadas: 120);
      final d = EdanBorradorIa();
      fusionar(d, parcheCon(agricultura: [fila]));
      fila.hasAfectadas = 999;
      expect(d.agricultura.single.hasAfectadas, 120,
          reason: 'mutar el parche después no debe alterar el borrador');
    });
  });

  group('agregar y quitar filas', () {
    test('agregar y quitar en una lista variable', () {
      final d = EdanBorradorIa();
      agregarFila(d, EdanLista.comunidades);
      expect(largoLista(d, EdanLista.comunidades), 1);
      quitarFila(d, EdanLista.comunidades, 0);
      expect(largoLista(d, EdanLista.comunidades), 0);
    });

    test('quitar con índice inválido no rompe nada', () {
      final d = EdanBorradorIa()..comunidades = [BchComunidad(nombre: 'A')];
      quitarFila(d, EdanLista.comunidades, 9);
      quitarFila(d, EdanLista.comunidades, -1);
      expect(d.comunidades, hasLength(1));
    });

    test('la persona puede agregar filas a mano sin límite fijo', () {
      final d = EdanBorradorIa();
      for (var i = 0; i < 5; i++) {
        agregarFila(d, EdanLista.agricultura);
        d.agricultura.last.cultivo = 'cultivo$i';
      }
      expect(d.agricultura, hasLength(5));
      expect(d.agricultura.map((a) => a.cultivo),
          ['cultivo0', 'cultivo1', 'cultivo2', 'cultivo3', 'cultivo4']);
    });

    test('quitar la fila que detectó la IA es posible', () {
      final d = EdanBorradorIa();
      fusionar(d, parcheCon(agricultura: [
        BchAgricultura(cultivo: 'Maíz', hasAfectadas: 120),
        BchAgricultura(cultivo: 'Papa', hasAfectadas: 40),
      ]));
      quitarFila(d, EdanLista.agricultura, 0);
      expect(d.agricultura.single.cultivo, 'Papa');
    });
  });

  group('aplicarParche', () {
    test('no muta el original', () {
      final original = EdanBorradorIa();
      final copia = aplicarParche(original, parcheCon(totalAfectada: 500));
      expect(original.totalAfectada, isNull);
      expect(copia.totalAfectada, 500);
    });

    test('las filas del original tampoco se mutan', () {
      final original = EdanBorradorIa()
        ..agricultura = [BchAgricultura(cultivo: 'Maíz', hasAfectadas: 120)];
      aplicarParche(original, parcheCon(agricultura: [
        BchAgricultura(cultivo: 'Maíz', hasAfectadas: 150),
      ]));
      expect(original.agricultura.single.hasAfectadas, 120);
    });
  });

  group('resumenCambios', () {
    test('detecta lo que se tocó', () {
      final a = EdanBorradorIa();
      final b = a.copy()
        ..totalAfectada = 900
        ..tipoEvento['inundacion'] = true;
      final r = resumenCambios(a, b);
      expect(r, contains('Personas afectadas: 900'));
      expect(r, contains('Evento: Inundación'));
    });

    test('no reporta lo que no cambió', () {
      final a = EdanBorradorIa()..totalAfectada = 900;
      final b = a.copy();
      expect(resumenCambios(a, b), isEmpty);
    });

    test('reporta filas nuevas con su clave', () {
      final a = EdanBorradorIa();
      final b = aplicarParche(a,
          parcheCon(agricultura: [BchAgricultura(cultivo: 'Maíz', hasAfectadas: 120)]));
      expect(resumenCambios(a, b), contains('Maíz: 120 ha afectadas'));
    });

    test('no reporta como nuevas las filas que ya existían', () {
      final a = EdanBorradorIa()
        ..agricultura = [BchAgricultura(cultivo: 'Maíz', hasAfectadas: 120)];
      final b = aplicarParche(a,
          parcheCon(agricultura: [BchAgricultura(cultivo: 'Maíz', hasAfectadas: 150)]));
      expect(resumenCambios(a, b).where((s) => s.startsWith('Maíz')), isEmpty);
    });
  });

  group('servicios básicos', () {
    test('un campo vacío del parche no pisa el detalle existente', () {
      final d = EdanBorradorIa();
      fusionar(d, parcheCon(servicios: {
        'agua': {'danoTotal': 'Total', 'observaciones': 'Sin servicio'},
      }));
      fusionar(d, parcheCon(servicios: {
        'agua': {'necesidades': 'Tanques'},
      }));
      final agua = d.servicioDe('agua')!;
      expect(agua.danoTotal, 'Total');
      expect(agua.necesidades, 'Tanques');
    });

    test('una clave de servicio desconocida se ignora', () {
      final d = EdanBorradorIa();
      fusionar(d, parcheCon(servicios: {
        'internet': {'danoTotal': 'Total'},
      }));
      expect(d.serviciosBasicos.length, 5);
    });
  });

  group('educación', () {
    test('se fusiona por establecimiento', () {
      final d = EdanBorradorIa()
        ..educacion = [BchUnidadEducativa(establecimiento: 'Escuela A')];
      fusionar(d, parcheCon(educacion: [
        BchUnidadEducativa(establecimiento: 'Escuela A', suspensionClases: true),
      ]));
      expect(d.educacion, hasLength(1));
      expect(d.educacion.first.suspensionClases, isTrue);
    });

    test('false en suspensión no la desactiva', () {
      final d = EdanBorradorIa()
        ..educacion = [
          BchUnidadEducativa(establecimiento: 'Escuela A', suspensionClases: true),
        ];
      fusionar(d, parcheCon(educacion: [
        BchUnidadEducativa(establecimiento: 'Escuela A'),
      ]));
      expect(d.educacion.first.suspensionClases, isTrue);
    });
  });

  group('origen del dato', () {
    test('el borrador hereda el origen del parche', () {
      final d = EdanBorradorIa();
      fusionar(d, parcheCon(agricultura: [
        BchAgricultura(cultivo: 'Maíz', hasAfectadas: 120, origen: EdanOrigen.voz),
      ]));
      expect(d.agricultura.single.origen, EdanOrigen.voz);
    });
  });
}
