/// Puerto de `EDAN-Tutor/tests/relaciones.test.js`.
///
/// Relaciones 1:n — varias filas del mismo tipo deben poder existir a la vez.
/// El formulario distingue:
///   1:n  agricultura, pecuario, infraVial, infraPublica, saludDanios,
///        educacion, comunidades, danosVivienda
///   1:1  impactoPoblacion (4 grupos), proteccion (7 grupos),
///        necesidadesHumanitarias (10 ítems)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rea/models/edan_borrador_ia.dart';
import 'package:rea/services/edan_ia/edan_extractor.dart';
import 'package:rea/services/edan_ia/edan_fusion.dart';
import 'package:rea/services/edan_ia/edan_parche.dart';

/// Parche con solo los bloques que interesa a cada prueba.
EdanParche _p({
  List<BchAgricultura> agricultura = const [],
  Map<String, int?> proteccion = const {},
  Map<String, bool?> necesidades = const {},
  Map<String, bool?> primeraRespuesta = const {},
  Map<String, Map<String, Object?>> impacto = const {},
  List<BchDanoVial> infraVial = const [],
}) =>
    EdanParche()
      ..agricultura = List.of(agricultura)
      ..infraVial = List.of(infraVial)
      ..proteccion.addAll({
        for (final e in proteccion.entries)
          e.key: BchProteccionFila(e.key, total: e.value),
      })
      ..necesidadesHumanitarias.addAll(necesidades)
      ..primeraRespuesta.addAll(primeraRespuesta)
      ..impactoPoblacion.addAll(impacto);

void main() {
  group('agricultura: varios cultivos en un solo mensaje (1:n)', () {
    test('tres cultivos con sus hectáreas', () {
      final p = extraer('Se afectaron 120 ha de maíz, 40 ha de papa y 15 ha de soya.');
      expect(p.agricultura, hasLength(3));
      expect(p.agricultura.map((a) => a.cultivo), ['Maíz', 'Papa', 'Soya']);
      expect(p.agricultura.map((a) => a.hasAfectadas), [120, 40, 15]);
    });

    test('el mismo cultivo dos veces se conserva como una sola fila', () {
      final p = extraer('Se afectaron 120 ha de maíz y 30 ha de maíz.');
      expect(p.agricultura, hasLength(2));
      final d = EdanBorradorIa();
      fusionar(d, p);
      expect(d.agricultura, hasLength(1),
          reason: 'la clave natural evita el duplicado');
      expect(d.agricultura.first.hasAfectadas, 30, reason: 'gana el último dato');
    });
  });

  group('pecuario: varias especies en un solo mensaje (1:n)', () {
    test('vacas, ovejas y cabras', () {
      final p =
          extraer('Murieron 15 vacas y 30 ovejas, y quedaron afectadas 12 cabras.');
      final especies = p.pecuario.map((x) => x.especie).toList();
      expect(especies.length, greaterThanOrEqualTo(2));
      expect(especies, contains('Vacas'));
      expect(especies, contains('Ovejas'));
    });

    test('muertos y afectados en la misma especie', () {
      final p = extraer('Murieron 15 vacas y 40 vacas quedaron afectadas.');
      expect(p.pecuario, hasLength(1));
      expect(p.pecuario.first.animalesMuertos, 15);
      expect(p.pecuario.first.animalesAfectados, isNull);
    });
  });

  group('infraestructura vial: varios puentes (1:n)', () {
    test('dos vías distintas', () {
      final p = extraer(
          'El puente viejo quedó cortado 2 km y el puente nuevo 1 km de daño total.');
      expect(p.infraVial.length, greaterThanOrEqualTo(2));
    });

    test('una vía sin nombre NO se fusiona: son dos filas distintas', () {
      // Sin nombre propio no hay clave natural, y una fila sin clave nunca se
      // fusiona (regla deliberada: si no, una fila escrita a mano podría ser
      // pisada por una detección que no la identifica). La vista debe pedir el
      // nombre de la vía en la revisión.
      final p =
          extraer('El puente quedó cortado 2 km. El puente quedó cortado 3 km.');
      final d = EdanBorradorIa();
      fusionar(d, p);
      expect(d.infraVial, hasLength(2));
      expect(d.infraVial.every((f) => f.via.isEmpty), isTrue);
      expect(d.infraVial.map((f) => f.danoTotal), ['2', '3']);
    });

    test('una vía con nombre propio sí se fusiona en una fila', () {
      final d = EdanBorradorIa()
        ..infraVial = [BchDanoVial(via: 'Puente Viejo', tramo: 'km 4')];
      fusionar(d, _p(infraVial: [BchDanoVial(via: 'Puente Viejo', danoTotal: '3')]));
      expect(d.infraVial, hasLength(1));
      expect(d.infraVial.first.danoTotal, '3');
      expect(d.infraVial.first.tramo, 'km 4',
          reason: 'el campo ausente del parche se conserva');
    });
  });

  group('la persona puede agregar filas a mano sin límite fijo', () {
    test('cinco cultivos manuales', () {
      final d = EdanBorradorIa();
      for (var i = 0; i < 5; i++) {
        agregarFila(d, EdanLista.agricultura);
        d.agricultura.last.cultivo = 'cultivo$i';
      }
      expect(d.agricultura, hasLength(5));
    });
  });

  group('las filas a mano sobreviven a una actualización posterior de la IA', () {
    test('trigo y avena se conservan y el maíz se añade al final', () {
      final d = EdanBorradorIa()
        ..agricultura = [
          BchAgricultura(cultivo: 'Trigo', hasAfectadas: 30),
          BchAgricultura(cultivo: 'Avena', hasAfectadas: 10),
        ];
      fusionar(d, _p(agricultura: [
        BchAgricultura(cultivo: 'Maíz', hasAfectadas: 120),
      ]));
      expect(d.agricultura, hasLength(3));
      expect(d.agricultura.map((a) => a.cultivo), ['Trigo', 'Avena', 'Maíz']);
      expect(d.agricultura.last.hasAfectadas, 120);
    });
  });

  group('una fila con la misma clave se ACTUALIZA en vez de duplicarse', () {
    test('actualiza y conserva el resto de campos', () {
      final d = EdanBorradorIa()
        ..agricultura = [
          BchAgricultura(
              cultivo: 'Maíz', hasAfectadas: 120, hasPerdidas: 20),
        ];
      fusionar(d, _p(agricultura: [
        BchAgricultura(cultivo: 'Maíz', hasAfectadas: 150),
      ]));
      expect(d.agricultura, hasLength(1));
      expect(d.agricultura.first.hasAfectadas, 150);
      expect(d.agricultura.first.hasPerdidas, 20,
          reason: 'un campo ausente del parche no se pierde');
    });
  });

  group('los bloques 1:1 conservan exactamente todas sus filas', () {
    test('tras cuatro fusiones parciales', () {
      final d = EdanBorradorIa();
      fusionar(d, _p(impacto: {
        'Niño(a) 0-5 años': {'fallecidos': 2},
      }));
      fusionar(d, _p(proteccion: {'Niñas y Niños': 40}));
      fusionar(d, _p(necesidades: {'Alimentos': true}));
      fusionar(d, _p(primeraRespuesta: {'busqueda': true}));

      expect(d.impactoPoblacion, hasLength(4));
      expect(d.proteccion, hasLength(7));
      expect(d.necesidadesHumanitarias, hasLength(10));
      expect(d.primeraRespuesta.tieneDatos, isTrue);
    });
  });

  group('el contenido de un bloque 1:1 se fusiona por etiqueta', () {
    test('embarazadas sin importar la posición', () {
      final d = EdanBorradorIa();
      fusionar(d, _p(proteccion: {'Mujeres Embarazadas': 10}));
      expect(d.proteccionDe('Mujeres Embarazadas')!.total, 10);
      expect(d.proteccion, hasLength(7));
    });
  });

  group('las secciones del esquema son únicas y están completas', () {
    test('todas las claves son distintas', () {
      final claves = kEdanSeccionesBorrador.map((s) => s.key).toList();
      expect(claves.toSet().length, claves.length,
          reason: 'no puede haber claves repetidas');
    });

    test('ninguna clave queda sin cobertura en el progreso', () {
      // Una clave no contemplada por `seccionProgreso` cae en `default` y
      // devolvería 0 siempre, así que el test tiene que llenar la sección y
      // exigir que suba: si no, la clave no estaría vigilada de verdad.
      void llenar(String key, EdanBorradorIa b) {
        switch (key) {
          case 'cabecera':
            b.municipio = 'Yapacaní';
          case 'impacto-poblacion':
            b.impactoDe(kEdanGruposEdad.first)!.marcado = true;
          case 'primera-respuesta':
            b.primeraRespuesta.busqueda = true;
          case 'salud-establecimientos':
            b.saludDanios.add(BchEstablecimientoSalud(establecimiento: 'Hospital'));
          case 'necesidad-salud':
            b.necesidadSalud.inundacion = 'dengue';
          case 'danos-viales':
            b.infraVial.add(BchDanoVial(via: 'Puente Viejo', danoTotal: 'Total'));
          case 'danos-infra-publica':
            b.infraPublica
                .add(BchInfraPublica(tipoEstructura: 'Escuela', danoTotal: 'Total'));
          case 'servicios-basicos':
            b.servicioDe(kEdanServiciosBasicos.keys.first)!.danoTotal = 'Total';
          case 'unidades-educativas':
            b.educacion.add(BchUnidadEducativa(establecimiento: 'Escuela 1'));
          case 'danos-vivienda':
            b.viviendasAfectadas = 60;
          case 'danos-agricultura':
            b.agricultura.add(BchAgricultura(cultivo: 'Maíz', hasAfectadas: 120));
          case 'danos-pecuarios':
            b.pecuario.add(BchPecuario(especie: 'Vacas', animalesAfectados: 40));
          case 'infra-productiva':
            b.infraProductiva.add(BchInfraProductiva(tipo: 'Silos'));
          case 'proteccion':
            b.proteccionDe(kEdanGruposProteccion.first)!.total = 40;
          case 'necesidad-humanitaria':
            b.necesidadDe(kEdanNecesidadesHumanitarias.first)!.si = true;
          default:
            fail('la sección "$key" no está contemplada en seccionProgreso');
        }
      }

      for (final s in kEdanSeccionesBorrador) {
        final b = EdanBorradorIa();
        expect(seccionProgreso(s.key, b), 0,
            reason: '${s.key} debería estar vacía al inicio');
        llenar(s.key, b);
        expect(seccionProgreso(s.key, b), greaterThan(0),
            reason: 'llenar ${s.key} debe subir su progreso');
      }
    });

    test('el progreso global cubre todas las secciones', () {
      final d = EdanBorradorIa()
        ..municipio = 'Yapacaní'
        ..totalAfectada = 350;
      final progreso = progresoGlobal(d);
      expect(progreso, hasLength(kEdanSeccionesBorrador.length));
      expect(progreso.firstWhere((s) => s.key == 'cabecera').valor,
          greaterThan(0));
    });

    test('las secciones incompletas vienen ordenadas de más a menos vacías', () {
      final d = EdanBorradorIa();
      final incompletas =
          seccionesIncompletas(progresoGlobal(d), umbral: 1.0, maximo: 5);
      expect(incompletas.length, 5);
      for (var i = 1; i < incompletas.length; i++) {
        expect(incompletas[i - 1].valor, lessThanOrEqualTo(incompletas[i].valor));
      }
    });
  });

  group('protección: el desglose por sexo llega hasta el borrador', () {
    test('el extractor separa mujeres y hombres cuando la frase los da', () {
      final p = extraer('Hay 40 mujeres embarazadas.');
      expect(p.proteccion['Mujeres Embarazadas']!.mujeres, 40);
      expect(p.proteccion['Mujeres Embarazadas']!.hombres, isNull);
    });

    test('una frase sin sexo deja el total sin desglose', () {
      final p = extraer('Hay 12 discapacitados afectados.');
      expect(p.proteccion['Personas con Discapacidad']!.total, 12);
      expect(p.proteccion['Personas con Discapacidad']!.tieneDesglose, isFalse);
    });

    test('la fusión respeta un desglose parcial', () {
      final d = EdanBorradorIa()
        ..proteccionDe('Mujeres Embarazadas')!.total = 10;
      fusionar(d, EdanParche()
        ..proteccion['Mujeres Embarazadas'] =
            BchProteccionFila('Mujeres Embarazadas', mujeres: 7));
      expect(d.proteccionDe('Mujeres Embarazadas')!.mujeres, 7);
      expect(d.proteccionDe('Mujeres Embarazadas')!.total, 10,
          reason: 'el total previo no se pisa con un desglose parcial');
    });

    test('el resumen informa el desglose, no solo el total', () {
      final antes = EdanBorradorIa();
      fusionar(antes, EdanParche()
        ..proteccion['Adolescentes'] =
            BchProteccionFila('Adolescentes', mujeres: 5));
      final despues = antes.copy();
      fusionar(despues, EdanParche()
        ..proteccion['Adolescentes'] =
            BchProteccionFila('Adolescentes', hombres: 3));
      expect(
        resumenCambios(antes, despues).join(' | '),
        contains('3 hombres'),
      );
    });
  });

  group('relaciones 1:n de todas las listas', () {
    test('cada lista puede tener varias filas a la vez', () {
      final d = EdanBorradorIa();
      d.comunidades.addAll([
        BchComunidad(nombre: 'San Pedro'),
        BchComunidad(nombre: 'Santa Cruz del Sur'),
      ]);
      d.saludDanios.addAll([
        BchEstablecimientoSalud(establecimiento: 'Hospital A'),
        BchEstablecimientoSalud(establecimiento: 'Hospital B'),
      ]);
      d.infraPublica.addAll([
        BchInfraPublica(tipoEstructura: 'Puente', comunidad: 'San Pedro'),
        BchInfraPublica(tipoEstructura: 'Escuela', comunidad: 'San Pedro'),
      ]);
      d.danosVivienda.addAll([
        BchDanoVivienda(comunidad: 'San Pedro', danoTotal: 12),
        BchDanoVivienda(comunidad: 'Santa Cruz del Sur', danoTotal: 3),
      ]);
      expect(d.comunidades, hasLength(2));
      expect(d.saludDanios, hasLength(2));
      expect(d.infraPublica, hasLength(2));
      expect(d.danosVivienda, hasLength(2));
    });
  });
}
