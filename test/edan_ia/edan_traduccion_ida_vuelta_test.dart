/// Ida y vuelta del contrato de datos: traducir -> `toJson` (la fila que se
/// guarda en SQLite) -> `fromJson` (la fila que se vuelve a leer).
///
/// No abre la base de datos: `DatabaseHelper` es un singleton atado a una ruta
/// real, así que la prueba de SQLite de verdad va aparte. Esto sí detecta los
/// errores que más duelen en la práctica: un campo que la traducción llena pero
/// el `fromJson` no lee (o al revés), que es exactamente lo que pasó con
/// `observaciones` en `EdanDanoPecuario`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rea/models/edan.dart';
import 'package:rea/models/edan_borrador_ia.dart';
import 'package:rea/services/edan_ia/edan_traduccion.dart';

void main() {
/// Un borrador con algo en cada sección, para que la ida y vuelta no pueda
/// pasar por una sección vacía por accidente.
  EdanBorradorIa borradorCompleto() => EdanBorradorIa()
    ..departamento = 'Cochabamba'
    ..provincia = 'Ichu'
    ..municipio = 'Yapacaní'
    ..alcalde = 'Juan Pérez'
    ..telefono = '70012345'
    ..fechaEvento = '2026-03-12'
    ..horaEvento = '14:30'
    ..totalAfectada = 350
    ..totalFamiliasAfectadas = 80
    ..totalFamiliasDamnificadas = 40
    ..tipoEvento['inundacion'] = true
    ..responsableNombre = 'María López'
    ..impactoDe('Niño(a) 0-5 años')!.fallecidos = 2
    ..impactoDe('Escolar 6-18 años')!.heridos = 5
    ..primeraRespuesta.busqueda = true
    ..primeraRespuesta.evacuacion = true
    ..saludDanios = [
      BchEstablecimientoSalud(
          establecimiento: 'Hospital', comunidad: 'San Pedro', dano: 'Total'),
    ]
    ..necesidadSalud.inundacion = 'dengue'
    ..infraVial = [
      BchDanoVial(
          via: 'Puente Viejo',
          tramo: 'km 4',
          danoTotal: 'Total',
          necesidades: 'maquinaria'),
    ]
    ..infraPublica = [
      BchInfraPublica(
          comunidad: 'San Pedro', tipoEstructura: 'Escuela', danoTotal: 'Total'),
    ]
    ..servicioDe('agua')!.danoParcial = 'Parcial'
    ..educacion = [
      BchUnidadEducativa(
          establecimiento: 'Escuela 1',
          comunidad: 'San Pedro',
          danoTotal: 'Total',
          suspensionClases: true,
          estudiantes: 120),
    ]
    ..danosVivienda = [
      BchDanoVivienda(comunidad: 'San Pedro', danoParcial: 10, danoTotal: 2),
    ]
    ..agricultura = [
      BchAgricultura(
          cultivo: 'Maíz', hasAfectadas: 120, hasPerdidas: 30),
    ]
    ..pecuario = [
      BchPecuario(
          especie: 'Vacas',
          animalesAfectados: 40,
          animalesMuertos: 5,
          observaciones: 'vacas_string'),
    ]
    ..infraProductiva = [BchInfraProductiva(tipo: 'Silos', danoTotal: '4')]
    ..proteccionDe('Mujeres Embarazadas')!.mujeres = 10
    ..necesidadDe('Alimentos')!.si = true
    ..necesidadDe('Politubos')!.observaciones = 'unos 200 metros';

  final l = traducirBorrador(borradorCompleto()).localidad;

  group('secciones 1:1', () {
    test('primera respuesta', () {
      final a = EdanNecesidadPrimeraRespuesta.fromJson(
          l.necesidadPrimeraRespuesta!.toJson());
      expect(a.busqueda, isTrue);
      expect(a.evacuacion, isTrue);
      expect(a.salvamento, isFalse);
    });

    test('necesidad de salud', () {
      final a = EdanNecesidadSalud.fromJson(l.necesidadSalud!.toJson());
      expect(a.observaciones, l.necesidadSalud!.observaciones);
      expect(a.otrasNecesidades, contains('dengue'));
    });

    test('necesidad humanitaria con las 10 del tutor reducidas a 9', () {
      final a = EdanNecesidadHumanitaria.fromJson(
          l.necesidadHumanitaria!.toJson());
      expect(a.alimentos, isTrue);
      // Una observación obliga a marcar la casilla: si no, `toJson` la descarta.
      expect(a.herramientas, isTrue,
          reason: 'obs sin marcar se perdería al guardar');
      expect(a.obsHerramientas, 'unos 200 metros');
    });
  });

  group('secciones 1:n', () {
    test('impacto en la población', () {
      final a = EdanImpactoPoblacion.fromJson(l.impactoPoblacion.first.toJson());
      expect(a.grupoEtario, 'Niño (a) 0-5 años');
      expect(a.fallecidos, 2);
      expect(a.gruposEtarios, isNotEmpty);
      final g = EdanGrupoEtario.fromJson(a.gruposEtarios.first.toJson());
      expect(g.rango, 'Niño (a) 0-5 años');
      expect(g.fallecidos, 2);
      expect(g.idGrupoEtario, 1);
    });

    test('establecimiento de salud', () {
      final a =
          EdanEstablecimientoSalud.fromJson(l.establecimientosSalud.first.toJson());
      expect(a.nombreEstablecimiento, 'Hospital');
      expect(a.comunidad, 'San Pedro');
      expect(a.danoTotal, isTrue);
      expect(a.danoParcial, isFalse);
    });

    test('daño vial con su extensión en kilómetros', () {
      final a = EdanDanoVial.fromJson(l.danosViales.first.toJson());
      expect(a.viaPuente, 'Puente Viejo');
      expect(a.tramo, 'km 4');
      expect(a.danoTotal, isTrue);
      expect(a.necesidadesInmediatas, 'maquinaria');
    });

    test('daño vial numérico conserva los kilómetros', () {
      final b = EdanBorradorIa()
        ..infraVial = [BchDanoVial(via: 'Ruta 4', danoTotal: '2')];
      final a = EdanDanoVial.fromJson(
          traducirBorrador(b).localidad.danosViales.first.toJson());
      expect(a.kmDanio, 2);
      expect(a.danoTotal, isTrue);
    });

    test('infraestructura pública', () {
      final a =
          EdanDanoInfraPublica.fromJson(l.danosInfraPublica.first.toJson());
      expect(a.tipoEstructura, 'Escuela');
      expect(a.danoTotal, isTrue);
    });

    test('servicio básico con su tipo de columna', () {
      final a = EdanServicioBasicoDetalle.fromJson(l.serviciosBasicos.first.toJson());
      expect(a.tipo, 'agua_potable');
      expect(a.afectado, isTrue);
      expect(a.danoParcial, isTrue);
    });

    test('unidad educativa', () {
      final a = EdanDanoUnidadEducativa.fromJson(l.unidadesEducativas.first.toJson());
      expect(a.nombreEstablecimiento, 'Escuela 1');
      expect(a.suspensionClases, isTrue);
      expect(a.estudiantes, 120);
    });

    test('daño de vivienda', () {
      final a = EdanDanoVivienda.fromJson(l.danosVivienda.first.toJson());
      expect(a.comunidad, 'San Pedro');
      expect(a.danoParcial, 10);
      expect(a.danoTotal, 2);
    });

    test('agricultura', () {
      final a = EdanDanoAgricultura.fromJson(l.danosAgricultura.first.toJson());
      expect(a.tipoCultivo, 'Maíz');
      expect(a.hectareasAfectadas, 120);
      expect(a.hectareasPerdidas, 30);
    });

    test('pecuario conserva `observaciones` (columna que el modelo tenía perdida)',
        () {
      final a = EdanDanoPecuario.fromJson(l.danosPecuarios.first.toJson());
      expect(a.especie, 'Vacas');
      expect(a.animalesAfectados, 40);
      expect(a.animalesMuertos, 5);
      expect(a.observaciones, 'vacas_string');
    });

    test('infraestructura productiva', () {
      final a = EdanInfraProductiva.fromJson(l.infraProductiva.first.toJson());
      expect(a.tipo, 'Silos');
      expect(a.danoTotal, 4);
    });

    test('grupo vulnerable', () {
      final a = EdanGrupoVulnerable.fromJson(l.proteccion.first.toJson());
      expect(a.nombreGrupo, isNotEmpty);
      expect(a.mujeres, 10);
      expect(a.hombres, 0);
    });
  });

  group('la localidad entera', () {
    test('los datos generales y los totales sobreviven', () {
      final j = l.toJson();
      final a = EdanLocalidad.fromJson(Map<String, dynamic>.from(j));
      expect(a.municipioNombre, 'Yapacaní');
      expect(a.departamentoNombre, 'Cochabamba');
      expect(a.provinciaNombre, 'Ichu');
      expect(a.totalPoblacionAfectada, 350);
      expect(a.totalFamiliasAfectadas, 80);
      expect(a.totalFamiliasDamnificadas, 40);
      expect(a.nombreAlcalde, 'Juan Pérez');
      expect(a.fonoAlcalde, '70012345');
      expect(a.fechaEvento, '2026-03-12');
      expect(a.horaEvento, '14:30');
      expect(a.tipoEventoNombre, 'Inundación');
      expect(a.responsable!.nombre, 'María López');
    });

    test('los flags imp_* sobreviven', () {
      final a = EdanLocalidad.fromJson(Map<String, dynamic>.from(l.toJson()));
      expect(a.impImpactoPoblacion, isTrue);
      expect(a.impPrimeraRespuesta, isTrue);
      expect(a.impDanosViales, isTrue);
      expect(a.impDanosAgricultura, isTrue);
      expect(a.impProteccion, isTrue);
      expect(a.impNecesidadHumanitaria, isTrue);
      expect(a.grupSalud, isTrue);
      expect(a.grupServicios, isTrue);
      expect(a.grupEducacion, isTrue);
      expect(a.grupVivienda, isTrue);
      expect(a.grupInfraestructura, isTrue);
      expect(a.grupAgropecuario, isTrue);
    });

    test('no se inventa un id_seccion al deserializar', () {
      // Regla del contrato de sincronización: `id_seccion` se genera al
      // guardar, nunca al leer.
      final a = EdanLocalidad.fromJson(Map<String, dynamic>.from(l.toJson()));
      for (final g in a.proteccion) {
        expect(g.idSeccion, isNull);
      }
      for (final v in a.danosViales) {
        expect(v.idSeccion, isNull);
      }
    });
  });
}
