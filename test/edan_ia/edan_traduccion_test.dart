/// Pruebas de la traducción borrador -> SQLite ([traducirBorrador]).
///
/// Es una función pura, así que aquí se comprueba todo sin base de datos:
/// equivalencias de catálogo, conversión de tipos, `imp_*` derivados y los
/// casos donde la traducción tiene que-callarse y devolver un aviso en vez de
/// inventar un dato.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rea/models/edan.dart';
import 'package:rea/models/edan_borrador_ia.dart';
import 'package:rea/services/edan_ia/edan_traduccion.dart';

/// Catálogo real de grupos vulnerables (8 filas), como lo devuelve la API.
const List<dynamic> kCatalogoProteccion = [
  {'id_grupo_vulnerable': 1, 'nombre': 'Niñas y niños 0-5 años'},
  {'id_grupo_vulnerable': 2, 'nombre': 'Niñas y niños 6-12 años'},
  {'id_grupo_vulnerable': 3, 'nombre': 'Adolescentes'},
  {'id_grupo_vulnerable': 4, 'nombre': 'Mujeres lactantes'},
  {'id_grupo_vulnerable': 5, 'nombre': 'Mujeres embarazadas'},
  {'id_grupo_vulnerable': 6, 'nombre': 'Adultos mayores'},
  {'id_grupo_vulnerable': 7, 'nombre': 'Personas con discapacidad'},
  {'id_grupo_vulnerable': 8, 'nombre': 'Personas con enfermedad crónica'},
];

/// Opciones con el catálogo de verdad (con ids), que es como se llama en
/// producción.
const EdanTraduccionOpciones _opciones =
    EdanTraduccionOpciones(catalogoGrupoVulnerable: kCatalogoProteccion);

EdanTraduccionResultado traducir(
  EdanBorradorIa b, {
  EdanTraduccionOpciones o = const EdanTraduccionOpciones(),
}) =>
    traducirBorrador(b, opciones: o);

void main() {
  group('cabecera', () {
    test('lleva los datos generales y deja los vacíos en null', () {
      final l = traducir(EdanBorradorIa()
        ..municipio = 'Yapacaní'
        ..departamento = 'Cochabamba'
        ..provincia = 'Ichu'
        ..totalAfectada = 350
        ..totalFamiliasAfectadas = 80
        ..totalFamiliasDamnificadas = 40
        ..fechaEvento = '2026-03-12'
        ..horaEvento = '14:30'
        ..alcalde = 'Juan Pérez'
        ..telefono = '70012345'
        ..responsableNombre = 'María López'
        ..responsableCargo = 'Coordinadora'
        ..responsableTelefono = '70123456'
        ..responsableEmail = 'maria@correo.test'
        ..fechaLlenado = '2026-03-13').localidad;

      expect(l.municipioNombre, 'Yapacaní');
      expect(l.departamentoNombre, 'Cochabamba');
      expect(l.provinciaNombre, 'Ichu');
      expect(l.totalPoblacionAfectada, 350);
      expect(l.totalFamiliasAfectadas, 80);
      expect(l.totalFamiliasDamnificadas, 40);
      expect(l.fechaEvento, '2026-03-12');
      expect(l.horaEvento, '14:30');
      expect(l.nombreAlcalde, 'Juan Pérez');
      expect(l.fonoAlcalde, '70012345');
      expect(l.fechaLlenado, '2026-03-13');
      expect(l.responsable!.nombre, 'María López');
      expect(l.responsable!.correo, 'maria@correo.test');
    });

    test('un texto en blanco se guarda como null y no como ""', () {
      final l = traducir(EdanBorradorIa()
        ..municipio = 'Yapacaní'
        ..provincia = '   '
        ..horaEvento = '').localidad;
      expect(l.provinciaNombre, isNull);
      expect(l.horaEvento, isNull);
    });

    test('sin responsable no se inventan datos', () {
      // `EdanLocalidad` siempre trae un objeto responsable (no nullable), así
      // que lo que se comprueba es que sus campos queden vacíos.
      final r = traducir(EdanBorradorIa()).localidad.responsable!;
      expect(r.nombre, '');
      expect(r.cargo, '');
      expect(r.fono, '');
      expect(r.correo, '');
    });

    test('los ids y el tipo los pone quien llama, no la traducción', () {
      final l = traducir(
        EdanBorradorIa()..municipio = 'Yapacaní',
        o: const EdanTraduccionOpciones(
          idUsuario: 7,
          idDepartamento: 3,
          idProvincia: 11,
          idMunicipio: 45,
          idTipoEvento: 2,
        ),
      ).localidad;
      expect(l.idUsuario, 7);
      expect(l.idDepartamento, 3);
      expect(l.idProvincia, 11);
      expect(l.idMunicipio, 45);
      expect(l.idTipoEvento, 2);
    });

    test('el tipo de evento se arma con las etiquetas del borrador', () {
      final b = EdanBorradorIa()..tipoEvento['inundacion'] = true;
      expect(traducir(b).localidad.tipoEventoNombre, 'Inundación');
    });

    test('varios eventos se nombran todos', () {
      final b = EdanBorradorIa()
        ..tipoEvento['inundacion'] = true
        ..tipoEvento['deslizamiento'] = true;
      expect(traducir(b).localidad.tipoEventoNombre,
          'Inundación, Deslizamiento');
    });

    test('el catálogo gana sobre la etiqueta del borrador', () {
      final b = EdanBorradorIa()..tipoEvento['inundacion'] = true;
      final l = traducir(b,
              o: const EdanTraduccionOpciones(tipoEventoNombre: 'CRE'))
          .localidad;
      expect(l.tipoEventoNombre, 'CRE');
    });

    test('una ficha escrita por una persona queda marcada como editada', () {
      expect(traducir(EdanBorradorIa()).localidad.editado, isTrue);
    });
  });

  group('impacto en la población', () {
    test('el texto del grupo se canonicaliza al del formulario', () {
      final b = EdanBorradorIa()
        ..impactoDe('Niño(a) 0-5 años')!.fallecidos = 2
        ..impactoDe('Escolar 6-18 años')!.heridos = 5
        ..impactoDe('Adulto 19-60 años')!.desaparecidos = 1
        ..impactoDe('Adulto mayor 60+')!.fallecidos = 3;
      final filas = traducir(b).localidad.impactoPoblacion;
      expect(filas.map((f) => f.grupoEtario), [
        'Niño (a) 0-5 años',
        'Escolar de 6-18 años',
        'Adulto de 19-60 años',
        'Adulto mayor de 60 años adelante',
      ]);
    });

    test('cada fila resuelve su id de catálogo por el nombre', () {
      final b = EdanBorradorIa()
        ..impactoDe('Niño(a) 0-5 años')!.fallecidos = 2
        ..impactoDe('Adulto mayor 60+')!.fallecidos = 3;
      final filas = traducir(b).localidad.impactoPoblacion;
      expect(filas[0].gruposEtarios.first.idGrupoEtario, 1);
      expect(filas[1].gruposEtarios.first.idGrupoEtario, 4);
    });

    test('un grupo marcado sin cifras cuenta como fila', () {
      final b = EdanBorradorIa()
        ..impactoDe('Escolar 6-18 años')!.marcado = true;
      final filas = traducir(b).localidad.impactoPoblacion;
      expect(filas, hasLength(1));
      expect(filas.first.fallecidos, 0);
      expect(filas.first.heridos, 0);
      expect(filas.first.gruposEtarios.first.marcado, isTrue);
    });

    test('un grupo vacío no genera fila', () {
      expect(traducir(EdanBorradorIa()).localidad.impactoPoblacion, isEmpty);
    });

    test('las observaciones viajan a la fila', () {
      final b = EdanBorradorIa()
        ..impactoDe('Niño(a) 0-5 años')!.observaciones = 'todos ilesos';
      expect(traducir(b).localidad.impactoPoblacion.first.observaciones,
          'todos ilesos');
    });
  });

  group('primera respuesta', () {
    test('los tres equipos se copian tal cual', () {
      final b = EdanBorradorIa()
        ..primeraRespuesta.busqueda = true
        ..primeraRespuesta.evacuacion = true;
      final r = traducir(b).localidad.necesidadPrimeraRespuesta!;
      expect(r.busqueda, isTrue);
      expect(r.salvamento, isFalse);
      expect(r.evacuacion, isTrue);
      expect(r.tieneDatos, isTrue);
    });

    test('sin equipos marcados la sección no cuenta como activa', () {
      expect(traducir(EdanBorradorIa()).seccionesActivas,
          isNot(contains('primera-respuesta')));
    });
  });

  group('daños viales', () {
    test('"Total" es daño total, no parcial', () {
      final b = EdanBorradorIa()
        ..infraVial = [BchDanoVial(via: 'Puente Viejo', danoTotal: 'Total')];
      final v = traducir(b).localidad.danosViales.single;
      expect(v.viaPuente, 'Puente Viejo');
      expect(v.danoTotal, isTrue);
      expect(v.danoParcial, isFalse);
    });

    test('"Parcial" es daño parcial', () {
      final b = EdanBorradorIa()
        ..infraVial = [BchDanoVial(via: 'Camino', danoParcial: 'Parcial')];
      final v = traducir(b).localidad.danosViales.single;
      expect(v.danoParcial, isTrue);
      expect(v.danoTotal, isFalse);
    });

    test('una cifra es-extension en kilómetros y daño total', () {
      final b = EdanBorradorIa()
        ..infraVial = [BchDanoVial(via: 'Ruta 4', danoTotal: '2')];
      final v = traducir(b).localidad.danosViales.single;
      expect(v.kmDanio, 2);
      expect(v.danoTotal, isTrue);
      expect(v.danoParcial, isFalse);
    });

    test('necesidades y observaciones viajan', () {
      final b = EdanBorradorIa()
        ..infraVial = [
          BchDanoVial(
              via: 'Puente', danoTotal: 'Total', necesidades: 'maquinaria'),
        ];
      expect(traducir(b).localidad.danosViales.single.necesidadesInmediatas,
          'maquinaria');
    });

    test('una vía sin nombre se conserva igual (la UI pide el nombre)', () {
      final b = EdanBorradorIa()
        ..infraVial = [BchDanoVial(danoTotal: '2')];
      expect(traducir(b).localidad.danosViales.single.viaPuente, '');
    });
  });

  group('servicios básicos', () {
    test('la clave interna se traduce al tipo de la columna', () {
      final b = EdanBorradorIa()
        ..servicioDe('luz')!.danoTotal = 'Total'
        ..servicioDe('agua')!.danoParcial = 'Parcial';
      final filas = traducir(b).localidad.serviciosBasicos;
      expect(filas.map((f) => f.tipo),
          containsAll(['energia_electrica', 'agua_potable']));
      expect(filas.firstWhere((f) => f.tipo == 'energia_electrica').danoTotal,
          isTrue);
      expect(
        filas.firstWhere((f) => f.tipo == 'agua_potable').danoParcial,
        isTrue,
      );
    });

    test('un servicio con datos queda marcado como afectado', () {
      final b = EdanBorradorIa()..servicioDe('gas')!.danoTotal = 'Total';
      expect(traducir(b).localidad.serviciosBasicos.single.afectado, isTrue);
    });

    test('un servicio sin datos no genera fila', () {
      final b = EdanBorradorIa()..servicioDe('gas')!.observaciones = '   ';
      expect(traducir(b).localidad.serviciosBasicos, isEmpty);
    });
  });

  group('educación', () {
    test('suspensión en true viaja, en false viaja como null', () {
      final b = EdanBorradorIa()
        ..educacion = [
          BchUnidadEducativa(
              establecimiento: 'Escuela 1', danoTotal: 'Total', estudiantes: 120),
          BchUnidadEducativa(
              establecimiento: 'Escuela 2', suspensionClases: true),
        ];
      final filas = traducir(b).localidad.unidadesEducativas;
      expect(filas[0].suspensionClases, isNull,
          reason: 'false significa "no lo dijo", no "dijo que no"');
      expect(filas[0].estudiantes, 120);
      expect(filas[1].suspensionClases, isTrue);
    });
  });

  group('salud', () {
    test('"Total" y "Parcial" se reparten en los dos booleanos', () {
      final b = EdanBorradorIa()
        ..saludDanios = [
          BchEstablecimientoSalud(establecimiento: 'Hospital', dano: 'Total'),
          BchEstablecimientoSalud(establecimiento: 'Puesto', dano: 'Parcial'),
        ];
      final filas = traducir(b).localidad.establecimientosSalud;
      expect(filas[0].danoTotal, isTrue);
      expect(filas[0].danoParcial, isFalse);
      expect(filas[1].danoParcial, isTrue);
      expect(filas[1].danoTotal, isFalse);
    });

    test('el nivel de atención viaja', () {
      final b = EdanBorradorIa()
        ..saludDanios = [
          BchEstablecimientoSalud(
              establecimiento: 'Hospital', nivel: 'Tercer nivel'),
        ];
      expect(
        traducir(b).localidad.establecimientosSalud.single.nivelAtencion,
        'Tercer nivel',
      );
    });
  });

  group('vivienda: los totales se materializan como fila', () {
    test('sin filas sueltas', () {
      final b = EdanBorradorIa()
        ..viviendasAfectadas = 60
        ..viviendasDamnificadas = 12;
      final filas = traducir(b).localidad.danosVivienda;
      expect(filas, hasLength(1));
      expect(filas.single.danoParcial, 60);
      expect(filas.single.danoTotal, 12);
    });

    test('las filas por comunidad se conservan', () {
      final b = EdanBorradorIa()
        ..danosVivienda = [
          BchDanoVivienda(comunidad: 'San Pedro', danoParcial: 10),
        ];
      final filas = traducir(b).localidad.danosVivienda;
      expect(filas.single.comunidad, 'San Pedro');
      expect(filas.single.danoParcial, 10);
    });
  });

  group('agricultura, pecuario e infraestructura productiva', () {
    test('los números del borrador pasan tal cual', () {
      final b = EdanBorradorIa()
        ..agricultura = [
          BchAgricultura(cultivo: 'Maíz', hasAfectadas: 120, hasPerdidas: 30),
        ]
        ..pecuario = [
          BchPecuario(especie: 'Vacas', animalesAfectados: 40, animalesMuertos: 5),
        ];
      final l = traducir(b).localidad;
      expect(l.danosAgricultura.single.tipoCultivo, 'Maíz');
      expect(l.danosAgricultura.single.hectareasAfectadas, 120);
      expect(l.danosAgricultura.single.hectareasPerdidas, 30);
      expect(l.danosPecuarios.single.especie, 'Vacas');
      expect(l.danosPecuarios.single.animalesAfectados, 40);
      expect(l.danosPecuarios.single.animalesMuertos, 5);
    });

    test('la infraestructura productiva convierte el texto a número', () {
      final b = EdanBorradorIa()
        ..infraProductiva = [BchInfraProductiva(tipo: 'Silos', danoTotal: '4')];
      final s = traducir(b).localidad.infraProductiva.single;
      expect(s.tipo, 'Silos');
      expect(s.danoTotal, 4);
    });
  });

  group('necesidades humanitarias: 10 casillas del tutor a 9 columnas', () {
    test('los cuatro ítems de agua caen en almacenamiento de agua', () {
      final b = EdanBorradorIa();
      for (final i in [
        'Tanques de Agua',
        'Pastillas Potabilizadoras',
        'Filtros Vela',
        'Carro Cisterna',
      ]) {
        b.necesidadDe(i)!.si = true;
      }
      final n = traducir(b).localidad.necesidadHumanitaria!;
      expect(n.almacenamientoAgua, isTrue);
    });

    test('politubos es herramienta', () {
      final b = EdanBorradorIa()..necesidadDe('Politubos')!.si = true;
      final n = traducir(b).localidad.necesidadHumanitaria!;
      expect(n.herramientas, isTrue);
      expect(n.almacenamientoAgua, isFalse);
    });

    test('cada ítem tiene su columna', () {
      const unoAUno = {
        'Alimentos': 'alimentos',
        'Refugio y Vivienda': 'refugioVivienda',
        'Ropa de Cama': 'ropaCama',
        'Artículos de Higiene': 'articulosHigiene',
        'Artículos de Cocina': 'articulosCocina',
      };
      for (final e in unoAUno.entries) {
        final b = EdanBorradorIa()..necesidadDe(e.key)!.si = true;
        final n = traducir(b).localidad.necesidadHumanitaria!;
        expect(n.tieneDatos, isTrue, reason: e.key);
      }
    });

    test('las observaciones viajan a su columna', () {
      final b = EdanBorradorIa()
        ..necesidadDe('Alimentos')!.observaciones = 'ración diaria';
      final n = traducir(b).localidad.necesidadHumanitaria!;
      expect(n.obsAlimentos, 'ración diaria');
      // Una observación sin marcar no se serializa (`toJson` solo escribe la obs
      // de una casilla marcada), y el formulario además borra la obs al
      // desmarcar. Traducir una obs suelta produciría una sección que se pierde
      // al guardar, así que la obs implica marcar.
      expect(n.alimentos, isTrue,
          reason: 'la obs debe sobrevivir al guardado, y eso exige marcar');
      expect(EdanNecesidadHumanitaria.fromJson(n.toJson()).obsAlimentos,
          'ración diaria');
    });

    test('sin observación ni marca, la casilla no se toca', () {
      // El borrador trae una fila por cada una de las 10 necesidades, vacías.
      final n = traducir(EdanBorradorIa()).localidad.necesidadHumanitaria!;
      expect(n.alimentos, isFalse);
      expect(n.obsAlimentos, '');
    });

    test('nada marcado deja la sección inactiva', () {
      final r = traducir(EdanBorradorIa());
      expect(r.localidad.necesidadHumanitaria!.tieneDatos, isFalse);
      expect(r.seccionesActivas, isNot(contains('necesidad-humanitaria')));
    });
  });

  group('protección: el punto delicado', () {
    test('un grupo con desglose va a mujeres/hombres tal cual', () {
      final b = EdanBorradorIa()
        ..proteccionDe('Mujeres Embarazadas')!.mujeres = 10
        ..proteccionDe('Mujeres Embarazadas')!.hombres = 2;
      final g = _grupo(traducir(b, o: _opciones).localidad, 'Mujeres embarazadas');
      expect(g.mujeres, 10);
      expect(g.hombres, 2);
      expect(g.idGrupoVulnerableCatalogo, 5);
    });

    test('el nombre del catálogo se resuelve por equivalencia, no por posición',
        () {
      final b = EdanBorradorIa()
        ..proteccionDe('Personas con Discapacidad')!.mujeres = 3;
      final g = _grupo(traducir(b, o: _opciones).localidad,
          'Personas con discapacidad');
      expect(g.idGrupoVulnerableCatalogo, 7);
    });

    test('"Enfermedad Inhabilitante" es enfermedad crónica', () {
      final b = EdanBorradorIa()
        ..proteccionDe('Enfermedad Inhabilitante')!.mujeres = 4;
      final g = _grupo(traducir(b, o: _opciones).localidad,
          'Personas con enfermedad crónica');
      expect(g.idGrupoVulnerableCatalogo, 8);
      expect(g.mujeres, 4);
    });

    test('un total en un grupo con sexo en el nombre se ubica solo', () {
      final b = EdanBorradorIa()
        ..proteccionDe('Mujeres Lactantes')!.total = 12;
      final g = _grupo(traducir(b, o: _opciones).localidad, 'Mujeres lactantes');
      expect(g.mujeres, 12);
      expect(g.hombres, 0);
    });

    test('un total SIN sexo no se reparte: queda la cifra y un aviso', () {
      final b = EdanBorradorIa()
        ..proteccionDe('Adolescentes')!.total = 30;
      final r = traducir(b, o: _opciones);
      final g = _grupo(r.localidad, 'Adolescentes');
      expect(g.mujeres, 0, reason: 'no se puede repartir sin inventar');
      expect(g.hombres, 0);
      expect(g.observaciones, contains('30'));
      expect(r.avisos.map((a) => a.clave), contains('proteccion.sexo'));
    });

    test('"Niñas y Niños" sin rango de edad se devuelve como aviso', () {
      final b = EdanBorradorIa()
        ..proteccionDe('Niñas y Niños')!.total = 15;
      final r = traducir(b, o: _opciones);
      expect(r.avisos.map((a) => a.clave), contains('proteccion.grupo'));
      expect(
        r.localidad.proteccion.any((g) => g.total == 15),
        isFalse,
        reason: 'no se reparte entre 0-5 y 6-12 sin preguntar',
      );
    });

    test('una etiqueta desconocida avisa y no rompe', () {
      final b = EdanBorradorIa()
        ..proteccion.add(BchProteccionFila('Ancianos de la región',
            total: 7));
      final r = traducir(b, o: _opciones);
      expect(r.avisos, isNotEmpty);
    });

    test('solo se devuelven los grupos con datos', () {
      final b = EdanBorradorIa()
        ..proteccionDe('Mujeres Embarazadas')!.mujeres = 10;
      expect(traducir(b, o: _opciones).localidad.proteccion, hasLength(1));
    });

    test('sin catálogo se usan los 8 grupos por defecto', () {
      final b = EdanBorradorIa()
        ..proteccionDe('Mujeres Embarazadas')!.mujeres = 10;
      final g = _grupo(traducir(b).localidad, 'Mujeres embarazadas');
      expect(g.mujeres, 10);
    });

    test('un catálogo con nombres parecidos se resuelve por parecido', () {
      const catalogo = [
        {'id_grupo_vulnerable': 90, 'nombre': 'Personas con discapacidad física'},
      ];
      final b = EdanBorradorIa()
        ..proteccionDe('Personas con Discapacidad')!.mujeres = 8;
      final l = traducir(b, o: const EdanTraduccionOpciones(
              catalogoGrupoVulnerable: catalogo))
          .localidad;
      expect(l.proteccion.single.mujeres, 8);
      expect(l.proteccion.single.idGrupoVulnerableCatalogo, 90);
    });
  });

  group('secciones activas e imp_*', () {
    test('una ficha vacía no activa nada', () {
      final r = traducir(EdanBorradorIa());
      expect(r.seccionesActivas, isEmpty);
      final l = r.localidad;
      expect(l.impPoblacion, isFalse);
      expect(l.impSalud, isFalse);
      expect(l.impAgropecuario, isFalse);
      expect(l.impProteccion, isFalse);
      expect(l.impNecesidades, isFalse);
    });

    test('cada sección activa su flag propio y el suyo de familia', () {
      final r = traducir(EdanBorradorIa()
        ..agricultura = [BchAgricultura(cultivo: 'Maíz', hasAfectadas: 120)]);
      expect(r.seccionesActivas, ['danos-agricultura']);
      expect(r.localidad.impDanosAgricultura, isTrue);
      expect(r.localidad.impAgropecuario, isTrue);
      expect(r.localidad.impDanosPecuarios, isFalse);
      expect(r.localidad.impEducacion, isFalse);
    });

    test('varias secciones de la misma familia encienden el flag de familia', () {
      final l = traducir(EdanBorradorIa()
            ..agricultura = [BchAgricultura(cultivo: 'Maíz', hasAfectadas: 1)]
            ..pecuario = [BchPecuario(especie: 'Vacas', animalesAfectados: 1)])
          .localidad;
      expect(l.impAgropecuario, isTrue);
      expect(l.impDanosAgricultura, isTrue);
      expect(l.impDanosPecuarios, isTrue);
    });

    test('necesidad de salud enciende salud y necesidades', () {
      final b = EdanBorradorIa()..necesidadSalud.inundacion = 'dengue';
      final l = traducir(b).localidad;
      expect(l.impNecesidadSalud, isTrue);
      expect(l.impSalud, isTrue);
      expect(l.impNecesidades, isTrue);
    });

    test('todas las secciones juntas cubren los 22 flags', () {
      final b = EdanBorradorIa()
        ..impactoDe('Niño(a) 0-5 años')!.fallecidos = 1
        ..primeraRespuesta.busqueda = true
        ..saludDanios = [BchEstablecimientoSalud(establecimiento: 'H', dano: 'Total')]
        ..necesidadSalud.inundacion = 'dengue'
        ..infraVial = [BchDanoVial(via: 'P', danoTotal: 'Total')]
        ..infraPublica = [BchInfraPublica(tipoEstructura: 'Escuela', danoTotal: 'Total')]
        ..servicioDe('luz')!.danoTotal = 'Total'
        ..educacion = [BchUnidadEducativa(establecimiento: 'E')]
        ..viviendasAfectadas = 10
        ..agricultura = [BchAgricultura(cultivo: 'Maíz', hasAfectadas: 1)]
        ..pecuario = [BchPecuario(especie: 'Vacas', animalesAfectados: 1)]
        ..infraProductiva = [BchInfraProductiva(tipo: 'Silos', danoTotal: '1')]
        ..proteccionDe('Mujeres Embarazadas')!.mujeres = 6
        ..necesidadDe('Alimentos')!.si = true;
      final r = traducir(b, o: _opciones);
      expect(r.seccionesActivas, hasLength(14));
      expect(r.avisos, isEmpty, reason: 'esta ficha no debe dejar avisos');
      final l = r.localidad;
      for (final f in [
        l.impPoblacion,
        l.impSalud,
        l.impInfraestructura,
        l.impServicios,
        l.impEducacion,
        l.impVivienda,
        l.impAgropecuario,
        l.impNecesidades,
        l.impImpactoPoblacion,
        l.impPrimeraRespuesta,
        l.impSaludEstablecimientos,
        l.impNecesidadSalud,
        l.impDanosViales,
        l.impDanosInfraPublica,
        l.impServiciosBasicos,
        l.impUnidadesEducativas,
        l.impDanosVivienda,
        l.impDanosAgricultura,
        l.impDanosPecuarios,
        l.impInfraProductiva,
        l.impProteccion,
        l.impNecesidadHumanitaria,
      ]) {
        expect(f, isTrue, reason: 'un imp_* quedó apagado');
      }
    });
  });

  group('robustez', () {
    test('traducir dos veces da el mismo resultado', () {
      final b = EdanBorradorIa()
        ..municipio = 'Yapacaní'
        ..totalAfectada = 350
        ..agricultura = [BchAgricultura(cultivo: 'Maíz', hasAfectadas: 120)]
        ..necesidadDe('Alimentos')!.si = true;
      final a = _sinTimestamps(traducir(b, o: _opciones).localidad.toJson());
      final c = _sinTimestamps(traducir(b, o: _opciones).localidad.toJson());
      expect(a, c);
    });

    test('traducir no modifica el borrador', () {
      final b = EdanBorradorIa()
        ..municipio = 'Yapacaní'
        ..proteccionDe('Adolescentes')!.total = 30;
      final antes = b.toString();
      traducir(b, o: _opciones);
      expect(b.toString(), antes);
    });

    test('una ficha sin datos reales no inventa secciones', () {
      final b = EdanBorradorIa()
        ..fechaLlenado = '2026-01-01'
        ..tipoEvento['inundacion'] = false;
      final r = traducir(b);
      expect(r.seccionesActivas, isEmpty);
      expect(r.avisos, isEmpty);
    });
  });
}

EdanGrupoVulnerable _grupo(EdanLocalidad l, String nombre) {
  for (final g in l.proteccion) {
    if (g.nombreGrupo == nombre) return g;
  }
  fail('no se encontró el grupo "$nombre" en '
      '${l.proteccion.map((g) => g.nombreGrupo).toList()}');
}

/// El JSON de una localidad trae `fecha_modificacion` generado con
/// `DateTime.now()`, así que para comparar dos traducciones hay que quitarlo.
Object? _sinTimestamps(Object? v) {
  if (v is Map) {
    return {
      for (final e in v.entries)
        if (e.key != 'fecha_modificacion' && e.key != 'fecha_modificacion_local')
          e.key: _sinTimestamps(e.value),
    };
  }
  if (v is List) return v.map(_sinTimestamps).toList();
  return v;
}
