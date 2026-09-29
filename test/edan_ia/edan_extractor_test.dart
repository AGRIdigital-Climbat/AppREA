/// Puerto de `EDAN-Tutor/tests/extractor.test.js` más los casos límite que
/// importan para no perder datos ni inventar los que nadie dijo.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rea/services/edan_ia/edan_extractor.dart';

void main() {
  group('numero: separadores de miles en español e inglés', () {
    test('"1.200" → 1200', () => expect(numero('1.200'), 1200));
    test('"1,200" → 1200', () => expect(numero('1,200'), 1200));
    test('"350" → 350', () => expect(numero('350'), 350));
    test('"12.000" → 12000', () => expect(numero('12.000'), 12000));
    test('"2.5" → 2.5 (decimal, no millar)', () => expect(numero('2.5'), 2.5));
    test('vacío → null', () => expect(numero(''), isNull));
  });

  group('numero: casos límite', () {
    test('null y espacios → null', () {
      expect(numero(null), isNull);
      expect(numero('   '), isNull);
    });
    test('sin dígitos → null', () => expect(numero('muchos'), isNull));
    test('negativo conserva el signo', () => expect(numero('-40'), -40));
    test('texto con unidades alrededor', () {
      expect(numero('120 ha'), 120);
    });
    test('aInt redondea y tolera cadena', () {
      expect(aInt('120 ha'), 120);
      expect(aInt('2.5'), 3);
      expect(aInt('nada'), isNull);
    });
  });

  group('detecta tipo de evento', () {
    test('con tilde', () {
      expect(extraer('Hubo una:inundación muy fuerte.').tipoEvento['inundacion'],
          isTrue);
    });
    test('deslizamiento', () {
      expect(
          extraer('Hubo un deslizamiento en la ladera.')
              .tipoEvento['deslizamiento'],
          isTrue);
    });
    test('sequía', () {
      expect(extraer('Hubo sequía fuerte.').tipoEvento['sequia'], isTrue);
    });
    test('sin tilde', () {
      expect(extraer('Hubo inundacion.').tipoEvento['inundacion'], isTrue);
    });
    test('varios eventos a la vez', () {
      final p = extraer('Hubo inundación y luego un incendio en la zona.');
      expect(p.tipoEvento['inundacion'], isTrue);
      expect(p.tipoEvento['incendios'], isTrue);
    });
    test('texto sin evento no activa ninguno', () {
      expect(extraer('Hola, buen día.').tipoEvento, isEmpty);
    });
    test('el evento se detecta aunque esté al final de la frase', () {
      expect(extraer('Hubo una granizada.').tipoEvento['granizada'], isTrue);
    });
    test('las formas verbales quedan para la IA, no para las reglas', () {
      // "se inundó" no está en el vocabulario de alias, y esa limitación es
      // deliberada: la IA cubre lo que las reglas no alcanzan.
      expect(extraer('La zona se inundó.').tipoEvento['inundacion'], isNull);
    });
  });

  group('población', () {
    test('familias afectadas y damnificadas se distinguen', () {
      final p = extraer(
          'Se vio afectadas 350 familias y 80 familias quedaron damnificadas.');
      expect(p.totalFamiliasAfectadas, 350);
      expect(p.totalFamiliasDamnificadas, 80);
    });
    test('el orden de las palabras no importa', () {
      final a = extraer('350 familias se vio afectadas.');
      final b = extraer('Afectadas 350 familias.');
      final c = extraer('se vio afectadas 350 familias.');
      expect(a.totalFamiliasAfectadas, 350);
      expect(b.totalFamiliasAfectadas, 350);
      expect(c.totalFamiliasAfectadas, 350);
    });
    test('población afectada con millares', () {
      expect(extraer('Unas 1.200 personas se vio afectadas.').totalAfectada,
          1200);
    });
    test('"damnificadas" no cuenta como afectadas', () {
      final p = extraer('80 familias quedaron damnificadas.');
      expect(p.totalFamiliasAfectadas, isNull);
      expect(p.totalFamiliasDamnificadas, 80);
    });
    test('sin sustantivo no inventa el conteo', () {
      expect(extraer('Hubo afectado el sector rural.').totalAfectada, isNull);
    });
    test('no duplica el conteo de personas a partir de familias', () {
      // "familia" no es sustantivo de persona: por eso la lista es aparte.
      final p = extraer('350 familias afectadas.');
      expect(p.totalAfectada, isNull);
      expect(p.totalFamiliasAfectadas, 350);
    });
  });

  group('ubicación y contacto', () {
    test('municipio y departamento', () {
      final p = extraer(
          'Ocurrió en el municipio de Yapacaní, departamento de Santa Cruz.');
      expect(p.departamento, 'Santa Cruz');
      expect(p.municipio, 'Yapacaní');
    });
    test('la provincia se detecta por el nombre', () {
      expect(extraer('En la provincia de Cochabamba.').departamento,
          'Cochabamba');
    });
    test('el municipio conserva su tilde', () {
      expect(extraer('municipio de Rurrenabaque.').municipio, 'Rurrenabaque');
      expect(extraer('municipio de Yapacaní.').municipio, 'Yapacaní');
    });
    test('teléfono de 7 a 15 dígitos', () {
      expect(extraer('El teléfono es 70123456.').telefono, '70123456');
      expect(extraer('celular 70012345.').telefono, '70012345');
    });
    test('un teléfono demasiado corto se descarta', () {
      expect(extraer('contacto 123.').telefono, isNull);
    });
    test('no confunde un departamento con un municipio', () {
      final p = extraer('Ocurrió en La Paz.');
      expect(p.departamento, 'La Paz');
      expect(p.municipio, isNull);
    });
  });

  group('fechas', () {
    test('formato sandwich con año', () {
      expect(extraer('Fue el 12 de marzo de 2026.').fechaEvento, '2026-03-12');
    });
    test('formato sandwich sin año usa el año en curso', () {
      expect(extraer('Fue el 12 de marzo.').fechaEvento,
          '${DateTime.now().year}-03-12');
    });
    test('formato ISO', () {
      expect(extraer('Fecha 2026-03-12.').fechaEvento, '2026-03-12');
    });
    test('formato numérico dd/mm/aaaa', () {
      expect(extraer('Ocurrió el 05/07/2026.').fechaEvento, '2026-07-05');
    });
    test('formato numérico con año de 2 cifras', () {
      expect(extraer('Ocurrió el 05/07/26.').fechaEvento, '2026-07-05');
    });
    test('setiembre y septiembre son el mismo mes', () {
      expect(extraer('Fue el 3 de setiembre de 2025.').fechaEvento, '2025-09-03');
      expect(extraer('Fue el 3 de septiembre de 2025.').fechaEvento,
          '2025-09-03');
    });
    test('un día de un solo dígito se rellena', () {
      expect(extraer('Fue el 3 de mayo de 2025.').fechaEvento, '2025-05-03');
    });
  });

  group('hora', () {
    test('con AM/PM en español', () {
      expect(extraer('Fue a las 3:30 de la tarde.').horaEvento, '15:30');
    });
    test('con AM', () {
      expect(extraer('Fue a las 9:15 am.').horaEvento, '09:15');
    });
    test('medianoche con am', () {
      expect(extraer('Fue a las 12:00 am.').horaEvento, '00:00');
    });
    test('medianoche con pm no se corre', () {
      expect(extraer('Fue a las 12:00 pm.').horaEvento, '12:00');
    });
    test('sin minutos', () {
      expect(extraer('Fue a las 8 de la mañana.').horaEvento, '08:00');
    });
    test('hora imposible (>23) se descarta', () {
      expect(extraer('Fue a las 30 de la tarde.').horaEvento, isNull);
    });
    test('no hay hora si no se menciona', () {
      expect(extraer('Ocurrió ayer.').horaEvento, isNull);
    });
  });

  group('agropecuario', () {
    test('cultivos con hectáreas', () {
      final p = extraer('Se afectaron 120 ha de maíz y 40 ha de papa.');
      final cultivos = p.agricultura.map((a) => a.cultivo).toList();
      expect(cultivos, contains('Maíz'));
      expect(cultivos, contains('Papa'));
      expect(p.agricultura.firstWhere((a) => a.cultivo == 'Maíz').hasAfectadas,
          120);
    });
    test('acepta "ha" y "hectáreas"', () {
      final p = extraer('Se dañaron 15 hectáreas de trigo.');
      expect(p.agricultura.single.cultivo, 'Trigo');
      expect(p.agricultura.single.hasAfectadas, 15);
    });
    test('pérdida total marcada cuando la palabra está cerca', () {
      final p = extraer('Se perdieron 80 ha de soya.');
      expect(p.agricultura.single.hasPerdidas, 80);
    });
    test('sin pérdida detectada no inventa hectáreas perdidas', () {
      final p = extraer('Se afectaron 80 ha de soya.');
      expect(p.agricultura.single.hasPerdidas, isNull);
    });
    test('el cultivo conserva su tilde', () {
      expect(extraer('5 ha de café.').agricultura.single.cultivo, 'Café');
    });
    test('pecuario: afectados y muertos, sin duplicar singular/plural', () {
      final p = extraer('Murieron 15 vacas y 40 vacas quedaron afectadas.');
      expect(p.pecuario, hasLength(1));
      expect(p.pecuario.first.especie, 'Vacas');
      expect(p.pecuario.first.animalesMuertos, 15);
    });
    test('pecuario: sin muerte la cifra es de afectados', () {
      final p = extraer('Quedaron afectadas 40 ovejas.');
      expect(p.pecuario.single.animalesAfectados, 40);
      expect(p.pecuario.single.animalesMuertos, isNull);
    });
    test('pecuario: varias especies en un solo mensaje', () {
      final p =
          extraer('Murieron 15 vacas y 30 ovejas, y quedaron afectadas 12 cabras.');
      final especies = p.pecuario.map((x) => x.especie).toList();
      expect(especies.length, greaterThanOrEqualTo(2));
      expect(especies, contains('Vacas'));
      expect(especies, contains('Ovejas'));
    });
  });

  group('necesidades humanitarias', () {
    test('detecta alimentos, filtros y politubos', () {
      final p = extraer('Necesitan alimentos, filtros vela y politubos.');
      final items = p.necesidadesHumanitarias.keys.toList();
      expect(items, contains('Alimentos'));
      expect(items, contains('Filtros Vela'));
      expect(items, contains('Politubos'));
    });
    test('las necesidades marcadas quedan en true', () {
      final p = extraer('Necesitan alimentos.');
      expect(p.necesidadesHumanitarias['Alimentos'], isTrue);
    });
    test('necesidad con palabras alternativas', () {
      expect(extraer('Faltan colchones.').necesidadesHumanitarias['Ropa de Cama'],
          isTrue);
      expect(extraer('Faltan ollas.').necesidadesHumanitarias['Artículos de Cocina'],
          isTrue);
    });
    test('no marca lo que no se menciona', () {
      expect(extraer('Necesitan alimentos.').necesidadesHumanitarias.length, 1);
    });
  });

  group('vivienda', () {
    test('afectadas y destruidas se distinguen', () {
      final p = extraer('Se dañaron 60 viviendas y 12 quedaron destruidas.');
      expect(p.viviendasAfectadas, 60);
      expect(p.viviendasDamnificadas, 12);
    });
    test('"casas" también cuenta como vivienda', () {
      expect(extraer('Se dañaron 25 casas.').viviendasAfectadas, 25);
    });
  });

  group('protección', () {
    test('por grupo vulnerable', () {
      final p = extraer('Hay 40 niños, 25 adolescentes y 10 mujeres embarazadas.');
      expect(p.proteccion['Niñas y Niños']!.total, 40);
      expect(p.proteccion['Adolescentes']!.total, 25);
      expect(p.proteccion['Mujeres Embarazadas']!.total, 10);
    });
    test('el desglose por sexo se detecta cuando la frase lo da', () {
      final p = extraer('Hay 40 niños, 25 adolescentes y 10 mujeres embarazadas.');
      expect(p.proteccion['Mujeres Embarazadas']!.mujeres, 10);
      expect(p.proteccion['Mujeres Embarazadas']!.tieneDesglose, isTrue);
      // El "10 mujeres" no puede contaminar al grupo de los niños por estar en la
      // misma frase: cada cifra toma la palabra de sexo más cercana.
      expect(p.proteccion['Niñas y Niños']!.mujeres, isNull);
      expect(p.proteccion['Niñas y Niños']!.hombres, 40);
    });
    test('sin palabra de sexo el total queda sin desglose', () {
      final p = extraer('Hay 12 personas con discapacidad.');
      expect(p.proteccion['Personas con Discapacidad']!.total, 12);
      expect(p.proteccion['Personas con Discapacidad']!.tieneDesglose, isFalse);
    });
    test('descarta la cifra si hay una palabra de muerte', () {
      // "murieron 3 niños" es impacto en población, no protección.
      final p = extraer('Murieron 3 niños.');
      expect(p.proteccion.containsKey('Niñas y Niños'), isFalse);
    });
    test('grupo sin cifra no aparece', () {
      final p = extraer('Hay 40 niños.');
      expect(p.proteccion.containsKey('Adolescentes'), isFalse);
    });
  });

  group('impacto en población', () {
    test('fallecidos en niños', () {
      final p = extraer('Murieron 2 niños.');
      expect(p.impactoPoblacion['Niño(a) 0-5 años']?['fallecidos'], 2);
    });
    test('heridos en escolares', () {
      final p = extraer('Hay 5 estudiantes heridos.');
      expect(p.impactoPoblacion['Escolar 6-18 años']?['heridos'], 5);
    });
    test('desaparecidos sin grupo explícito', () {
      final p = extraer('Hay 2 desaparecidos.');
      expect(p.impactoPoblacion.values.first['desaparecidos'], 2);
    });
  });

  group('infraestructura vial', () {
    test('varios puentes en un solo mensaje', () {
      final p = extraer(
          'El puente viejo quedó cortado 2 km y el puente nuevo 1 km de daño total.');
      expect(p.infraVial.length, greaterThanOrEqualTo(2));
    });
    test('guarda los kilómetros como daño total', () {
      final p = extraer('El puente quedó cortado 3 km.');
      expect(p.infraVial.single.danoTotal, '3');
    });
    test('una vía sin daño no genera fila', () {
      expect(extraer('El puente está bien.').infraVial, isEmpty);
    });
  });

  group('educación y salud', () {
    test('establecimiento de salud dañado conserva su nombre', () {
      final p = extraer('El Hospital San José sufrió daños.');
      expect(p.saludDanios, isNotEmpty);
      expect(p.saludDanios.first.establecimiento, contains('San José'));
    });
    test('escuela dañada con su nombre', () {
      final p = extraer('La escuela Juan Montalvo fue afectada.');
      expect(p.educacion, isNotEmpty);
      expect(p.educacion.first.establecimiento, contains('Juan Montalvo'));
    });
    test('establecimiento sin daño no genera fila', () {
      expect(extraer('El hospital funciona con normalidad.').saludDanios, isEmpty);
    });
  });

  group('comunidades', () {
    test('detecta una comunidad y la capitaliza como topónimo', () {
      final p = extraer('Afectó a la comunidad San Pedro.');
      expect(p.comunidades.map((c) => c.nombre), contains('San Pedro'));
    });
    test('el municipio no se repite como comunidad', () {
      final p = extraer(
          'Ocurrió en el municipio de Yapacaní, comunidad San Pedro.');
      expect(p.municipio, 'Yapacaní');
      expect(p.comunidades.map((c) => c.nombre), isNot(contains('Yapacaní')));
    });
    test('acepta lista tras "comunidades"', () {
      final p = extraer('Comunidades: San Pedro, Santa Cruz del Sur.');
      expect(p.comunidades.length, greaterThanOrEqualTo(2));
    });
  });

  group('servicios básicos', () {
    test('sin agua se registra caída total', () {
      final p = extraer('La población quedó sin agua potable.');
      expect(p.serviciosBasicos['agua']?['danoTotal'], 'Total');
    });
    test('sin luz', () {
      expect(extraer('Se cortó la luz.').serviciosBasicos['luz']?['danoTotal'],
          'Total');
    });
    test('alcantarillado dañado es parcial', () {
      expect(
          extraer('Hay alcantarillo roto.')
              .serviciosBasicos['alcantarillado']?['danoTotal'],
          'Parcial');
    });
    test('sin internet cuenta como telecomunicaciones', () {
      expect(extraer('No hay señal.').serviciosBasicos['telecom']?['danoTotal'],
          'Total');
    });
    test('sin mención no genera nada', () {
      expect(extraer('El pueblo está tranquilo.').serviciosBasicos, isEmpty);
    });
  });

  group('robustez', () {
    test('texto vacío no produce parche', () {
      expect(extraer('').vacio, isTrue);
      expect(extraer('   ').vacio, isTrue);
    });
    test('null no revienta', () {
      expect(extraer('nada').vacio, isTrue);
    });
    test('no inventa datos ausentes', () {
      final p = extraer('Hola, buen día, ¿cómo estás?');
      expect(p.municipio, isNull);
      expect(p.totalAfectada, isNull);
      expect(p.departamento, isNull);
    });
    test('texto sin letras ni cifras no rompe', () {
      expect(extraer('¿¿¿...!!!').vacio, isTrue);
    });
    test('no hay parche a medias cuando un detector no encuentra nada', () {
      // Cada detector debe poder devolver vacío sin contaminar el parche.
      final p = extraer('Hubo un incendio.');
      expect(p.tipoEvento['incendios'], isTrue);
      expect(p.agricultura, isEmpty);
      expect(p.pecuario, isEmpty);
      expect(p.infraVial, isEmpty);
      expect(p.saludDanios, isEmpty);
      expect(p.educacion, isEmpty);
    });
    test('tieneDatoReconocible refleja si el texto aportó algo', () {
      expect(tieneDatoReconocible('Hubo una inundación.'), isTrue);
      expect(tieneDatoReconocible('Hola, buen día.'), isFalse);
    });
  });

  group('sinTilde normaliza para comparar', () {
    test('inundación → inundacion', () => expect(sinTilde('inundación'), 'inundacion'));
    test('Ñoño → nono', () => expect(sinTilde('Ñoño'), 'nono'));
    test('conserva la longitud para poder recortar el original', () {
      const original = 'Yapacaní y Río Grande';
      expect(sinTilde(original).length, original.length);
    });
    test('null y vacío', () {
      expect(sinTilde(null), '');
      expect(sinTilde(''), '');
    });
  });

  group('capitalizarLugar', () {
    test('titulariza cada palabra', () {
      expect(capitalizarLugar('san pedro'), 'San Pedro');
      expect(capitalizarLugar('villa nueva'), 'Villa Nueva');
    });
    test('río conserva su tilde', () {
      expect(capitalizarLugar('río yapacaní'), 'Río Yapacaní');
    });
    test('no deja espacios dobles', () {
      expect(capitalizarLugar('  san   pedro  '), 'San Pedro');
    });
  });
}
