/// Pruebas del borrador intermedio: semántica de "no detectado", copias
/// independientes, detección de vacío y cálculo de progreso por sección.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rea/models/edan_borrador_ia.dart';
import 'package:rea/services/edan_ia/edan_extractor.dart';
import 'package:rea/services/edan_ia/edan_fusion.dart';

void main() {
  group('semántica null = no detectado', () {
    test('un borrador recién creado no tiene datos', () {
      expect(EdanBorradorIa().vacio, isTrue);
    });

    test('relleno distingue null, vacío, 0 y false', () {
      expect(relleno(null), isFalse);
      expect(relleno(''), isFalse);
      expect(relleno('   '), isFalse);
      expect(relleno(0), isTrue, reason: 'el cero explícito SÍ es un dato');
      expect(relleno(false), isFalse, reason: 'false significa "no aplica"');
      expect(relleno(true), isTrue);
      expect(relleno(<String>[]), isFalse);
      expect(relleno(<int>[0]), isTrue);
    });

    test('un cero explícito hace el borrador no vacío', () {
      final b = EdanBorradorIa()..totalAfectada = 0;
      expect(b.vacio, isFalse);
    });

    test('un texto con espacios no cuenta', () {
      final b = EdanBorradorIa()..municipio = '   ';
      expect(b.vacio, isTrue);
    });

    test('con un solo dato real ya no está vacío', () {
      final b = EdanBorradorIa()
        ..agricultura = [BchAgricultura(cultivo: 'Maíz', hasAfectadas: 120)];
      expect(b.vacio, isFalse);
    });
  });

  group('las listas de tamaño fijo arrancan pobladas', () {
    test('impacto, protección y necesidades', () {
      final b = EdanBorradorIa();
      expect(b.impactoPoblacion.map((f) => f.grupo), kEdanGruposEdad);
      expect(b.proteccion.map((f) => f.grupo), kEdanGruposProteccion);
      expect(b.necesidadesHumanitarias.map((f) => f.item),
          kEdanNecesidadesHumanitarias);
    });

    test('servicios básicos con las 5 claves', () {
      final b = EdanBorradorIa();
      expect(b.serviciosBasicos.keys, kEdanServiciosBasicos.keys);
    });

    test('tipo evento con las 7 claves, todas en false', () {
      final b = EdanBorradorIa();
      expect(b.tipoEvento.keys, kEdanClavesEvento);
      expect(b.tipoEvento.values.every((v) => v == false), isTrue);
      expect(b.etiquetasEvento, isEmpty);
    });

    test('las listas 1:n arrancan vacías', () {
      final b = EdanBorradorIa();
      expect(b.agricultura, isEmpty);
      expect(b.pecuario, isEmpty);
      expect(b.infraVial, isEmpty);
      expect(b.comunidades, isEmpty);
      expect(b.educacion, isEmpty);
      expect(b.saludDanios, isEmpty);
      expect(b.danosVivienda, isEmpty);
    });

    test('fechaLlenado se prellena con el día de hoy', () {
      expect(EdanBorradorIa().fechaLlenado, hoyIso());
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(hoyIso()), isTrue);
    });
  });

  group('buscadores por etiqueta', () {
    test('impactoDe y proteccionDe y necesidadDe', () {
      final b = EdanBorradorIa();
      expect(b.impactoDe('Escolar 6-18 años'), isNotNull);
      expect(b.impactoDe('Grupo Inexistente'), isNull);
      expect(b.proteccionDe('Mujeres Lactantes'), isNotNull);
      expect(b.proteccionDe('Nadie'), isNull);
      expect(b.necesidadDe('Filtros Vela'), isNotNull);
      expect(b.necesidadDe('Bicicletas'), isNull);
    });

    test('servicioDe devuelve null para una clave que no es servicio', () {
      expect(EdanBorradorIa().servicioDe('luz'), isNotNull);
      expect(EdanBorradorIa().servicioDe('banana'), isNull);
    });
  });

  group('copy() es una copia profunda', () {
    test('los escalares son independientes', () {
      final a = EdanBorradorIa()..municipio = 'Yapacaní';
      final b = a.copy()..municipio = 'Rurrenabaque';
      expect(a.municipio, 'Yapacaní');
      expect(b.municipio, 'Rurrenabaque');
    });

    test('las listas 1:n son independientes', () {
      final a = EdanBorradorIa()
        ..agricultura = [BchAgricultura(cultivo: 'Maíz', hasAfectadas: 120)];
      final b = a.copy();
      b.agricultura.first.cultivo = 'Papa';
      b.agricultura.add(BchAgricultura(cultivo: 'Trigo'));
      expect(a.agricultura, hasLength(1));
      expect(a.agricultura.first.cultivo, 'Maíz');
      expect(b.agricultura, hasLength(2));
    });

    test('los bloques fijos son independientes', () {
      final a = EdanBorradorIa();
      final b = a.copy();
      b.proteccionDe('Niñas y Niños')!.total = 40;
      b.necesidadDe('Alimentos')!.si = true;
      b.primeraRespuesta.busqueda = true;
      expect(a.proteccionDe('Niñas y Niños')!.total, isNull);
      expect(a.necesidadDe('Alimentos')!.si, isFalse);
      expect(a.primeraRespuesta.busqueda, isFalse);
    });

    test('servicios básicos y mapas son independientes', () {
      final a = EdanBorradorIa();
      final b = a.copy();
      b.servicioDe('agua')!.danoTotal = 'Total';
      b.tipoEvento['sequia'] = true;
      expect(a.servicioDe('agua')!.danoTotal, '');
      expect(a.tipoEvento['sequia'], isFalse);
    });

    test('ultimaActualizacion se copia', () {
      final a = EdanBorradorIa()..ultimaActualizacion = ['x'];
      final b = a.copy()..ultimaActualizacion = ['y'];
      expect(a.ultimaActualizacion, ['x']);
      expect(b.ultimaActualizacion, ['y']);
    });
  });

  group('tieneDatos por fila', () {
    test('una fila totalmente vacía no tiene datos', () {
      expect(BchAgricultura().tieneDatos, isFalse);
      expect(BchPecuario().tieneDatos, isFalse);
      expect(BchComunidad().tieneDatos, isFalse);
      expect(BchDanoVial().tieneDatos, isFalse);
    });

    test('basta un solo campo para que la fila cuente', () {
      expect(BchAgricultura(cultivo: 'Maíz').tieneDatos, isTrue);
      expect(BchPecuario(animalesMuertos: 0).tieneDatos, isTrue);
      expect(BchComunidad(nombre: 'San Pedro').tieneDatos, isTrue);
    });

    test('protección cuenta una observación sin total', () {
      expect(BchProteccionFila('X', observaciones: 'nota').tieneDatos, isTrue);
    });

    test('necesidad cuenta una observación sin marcar', () {
      expect(BchNecesidadFila('X', observaciones: 'nota').tieneDatos, isTrue);
    });

    test('impacto cuenta un grupo marcado aunque no haya números', () {
      expect(BchImpactoFila('Escolar 6-18 años', marcado: true).tieneDatos,
          isTrue);
      expect(BchImpactoFila('Escolar 6-18 años', observaciones: 'sin datos')
          .tieneDatos, isTrue);
    });
  });

  group('tieneVivienda', () {
    test('detecta vivienda por totales o por filas', () {
      expect(EdanBorradorIa().tieneVivienda, isFalse);
      expect((EdanBorradorIa()..viviendasAfectadas = 60).tieneVivienda, isTrue);
      expect(
        (EdanBorradorIa()
              ..danosVivienda = [BchDanoVivienda(comunidad: 'San Pedro')])
            .tieneVivienda,
        isTrue,
      );
    });
  });

  group('progreso por sección', () {
    test('sección vacía vale 0', () {
      final b = EdanBorradorIa();
      expect(seccionProgreso('cabecera', b), 0);
      expect(seccionProgreso('servicios-basicos', b), 0);
      expect(seccionProgreso('agricultura', b), 0);
    });

    test('una sección 1:n con una fila vale 1', () {
      final b = EdanBorradorIa()
        ..agricultura = [BchAgricultura(cultivo: 'Maíz', hasAfectadas: 120)];
      expect(seccionProgreso('danos-agricultura', b), 1);
    });

    test('una clave desconocida vale 0 y no revienta', () {
      expect(seccionProgreso('seccion-inventada', EdanBorradorIa()), 0);
    });

    test('necesidades cuenta la proporción de casillas marcadas', () {
      final b = EdanBorradorIa();
      b.necesidadDe('Alimentos')!.si = true;
      b.necesidadDe('Politubos')!.si = true;
      expect(seccionProgreso('necesidad-humanitaria', b),
          closeTo(2 / 10, 0.0001));
    });

    test('progreso global mantiene el orden de las secciones', () {
      final p = progresoGlobal(EdanBorradorIa());
      expect(p.map((s) => s.key), kEdanSeccionesBorrador.map((s) => s.key));
    });

    test('completo solo cuando el valor llega a 1', () {
      expect(const EdanProgresoSeccion('a', 'A', 0.99).completo, isFalse);
      expect(const EdanProgresoSeccion('a', 'A', 1.0).completo, isTrue);
    });

    test('el progreso crece al llenar la sección', () {
      final b = EdanBorradorIa();
      final antes = seccionProgreso('danos-pecuarios', b);
      b.pecuario.add(BchPecuario(especie: 'Vacas', animalesAfectados: 40));
      expect(seccionProgreso('danos-pecuarios', b), greaterThan(antes));
    });
  });

  group('seccionesIncompletas', () {
    test('respeta el umbral y el máximo', () {
      final b = EdanBorradorIa();
      final r = seccionesIncompletas(progresoGlobal(b), umbral: 0.5, maximo: 3);
      expect(r, hasLength(3));
      expect(r.every((s) => s.valor < 0.5), isTrue);
    });

    test('ignora las secciones ya completas', () {
      final b = EdanBorradorIa()
        ..agricultura = [BchAgricultura(cultivo: 'Maíz', hasAfectadas: 1)];
      final r = seccionesIncompletas(progresoGlobal(b), umbral: 1.0);
      expect(r.map((s) => s.key), isNot(contains('danos-agricultura')));
    });
  });

  group('integración extracción + fusión', () {
    test('una frase completa llena varias secciones', () {
      final b = EdanBorradorIa();
      fusionar(b, extraer(
          'Hubo una:inundación. Se vio afectadas 350 familias y 80 familias '
          'quedaron damnificadas en el municipio de Yapacaní, el 12 de marzo de '
          '2026. Se afectaron 120 ha de maíz. Murieron 15 vacas. '
          'Necesitan alimentos y politubos.'));

      expect(b.tipoEvento['inundacion'], isTrue);
      expect(b.totalFamiliasAfectadas, 350);
      expect(b.totalFamiliasDamnificadas, 80);
      expect(b.municipio, 'Yapacaní');
      expect(b.fechaEvento, '2026-03-12');
      expect(b.agricultura.single.cultivo, 'Maíz');
      expect(b.pecuario.single.animalesMuertos, 15);
      expect(b.necesidadDe('Alimentos')!.si, isTrue);
      expect(b.necesidadDe('Politubos')!.si, isTrue);
      expect(b.vacio, isFalse);
    });

    test('un segundo mensaje añade sin perder lo anterior', () {
      final b = EdanBorradorIa();
      fusionar(b, extraer('Se afectaron 120 ha de maíz.'));
      fusionar(b, extraer('Se afectaron 40 ha de papa.'));

      expect(b.agricultura.map((a) => a.cultivo), ['Maíz', 'Papa']);
      expect(b.agricultura.first.hasAfectadas, 120);
    });

    test('un mensaje repetido actualiza en vez de duplicar', () {
      final b = EdanBorradorIa();
      fusionar(b, extraer('Se vio afectadas 350 familias.'));
      fusionar(b, extraer('Se vio afectadas 400 familias.'));
      expect(b.totalFamiliasAfectadas, 400);
    });
  });
}
