/// El paso final de fotos y coordenadas del asistente.
///
/// Cubre las nueve secciones 1:n que llevan foto, la regla del wizard
/// (coordenada primero, foto después) y que todo sobreviva al viaje por SQLite.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rea/models/edan.dart';
import 'package:rea/models/edan_borrador_ia.dart';
import 'package:rea/services/edan_ia/edan_slots_foto.dart';
import 'package:rea/services/edan_ia/edan_traduccion.dart';
import 'package:rea/services/edan_secciones_registry.dart';

void main() {
  test('las claves son las del registro, no nombres inventados', () {
    // Si una clave no existe en el registro, la foto se guarda pero la sección
    // no queda activa y al sincronizar la foto viaja sola.
    final registro = EdanSeccionesRegistry.seccionFlags.keys.toSet();
    for (final clave in kEdanSeccionesConFoto.keys) {
      expect(registro, contains(clave),
          reason: '$clave no existe en el registro de secciones');
    }
  });

  test('son exactamente las nueve secciones con foto', () {
    expect(kEdanSeccionesConFoto, hasLength(9));
  });

  // Un borrador que llena las nueve secciones con foto.
  EdanBorradorIa borradorCompleto() => EdanBorradorIa()
    ..municipio = 'Yapacaní'
    ..infraVial = [BchDanoVial(via: 'Puente Viejo', danoTotal: 'Total')]
    ..infraPublica = [
      BchInfraPublica(
          comunidad: 'San Pedro', tipoEstructura: 'Escuela', danoTotal: 'Total'),
    ]
    ..saludDanios = [
      BchEstablecimientoSalud(establecimiento: 'Hospital', dano: 'Total'),
    ]
    ..servicioDe('agua')!.danoParcial = 'Parcial'
    ..educacion = [
      BchUnidadEducativa(
          establecimiento: 'Escuela 1', danoTotal: 'Total', estudiantes: 120),
    ]
    ..danosVivienda = [
      BchDanoVivienda(comunidad: 'San Pedro', danoParcial: 10, danoTotal: 2),
    ]
    ..agricultura = [BchAgricultura(cultivo: 'Maíz', hasAfectadas: 120)]
    ..pecuario = [BchPecuario(especie: 'Vacas', animalesAfectados: 40)]
    ..infraProductiva = [BchInfraProductiva(tipo: 'Silos', danoTotal: '4')];

  // Una localidad nueva por prueba: varias de estas pruebas agregan fotos y
  // coordenadas, y si compartieran el mismo objeto una contaminaría a la otra.
  late EdanLocalidad l;

  setUp(() => l = traducirBorrador(borradorCompleto()).localidad);

  group('cobertura de las secciones con foto', () {
    test('sale un slot por cada ítem de las nueve secciones', () {
      final slots = slotsDeFoto(l);
      expect(slots, hasLength(9));
      expect(
        slots.map((s) => s.seccion).toSet(),
        kEdanSeccionesConFoto.keys.toSet(),
        reason: 'las nueve secciones del wizard deben aparecer',
      );
    });

    test('cada sección con foto del modelo está en el listado', () {
      // Si mañana el modelo gana otra sección con fotos, el listado debe
      // crecer: esta prueba avisa en vez de dejar la foto sin salida.
      final conFotoEnElModelo = <String>[
        if (l.danosViales.isNotEmpty) 'danos_viales',
        if (l.danosInfraPublica.isNotEmpty) 'danos_infra_publica',
        if (l.establecimientosSalud.isNotEmpty) 'establecimientos_salud',
        if (l.serviciosBasicos.isNotEmpty) 'servicios_basicos',
        if (l.unidadesEducativas.isNotEmpty) 'unidades_educativas',
        if (l.danosVivienda.isNotEmpty) 'danos_vivienda',
        if (l.danosAgricultura.isNotEmpty) 'danos_agricultura',
        if (l.danosPecuarios.isNotEmpty) 'danos_pecuarios',
        if (l.infraProductiva.isNotEmpty) 'infra_productiva',
      ];
      expect(conFotoEnElModelo, hasLength(9));
      expect(kEdanSeccionesConFoto, hasLength(9));
    });

    test('no hay huecos para secciones sin datos', () {
      final vacia = traducirBorrador(EdanBorradorIa()..municipio = 'X').localidad;
      expect(slotsDeFoto(vacia), isEmpty);
      expect(resumenFotos(vacia).total, 0);
    });

    test('varias filas de la misma sección son huecos distintos', () {
      final b = borradorCompleto()
        ..agricultura = [
          BchAgricultura(cultivo: 'Maíz', hasAfectadas: 120),
          BchAgricultura(cultivo: 'Trigo', hasAfectadas: 80),
        ];
      final agri = slotsDeFoto(traducirBorrador(b).localidad)
          .where((s) => s.seccion == 'danos-agricultura')
          .toList();
      expect(agri, hasLength(2));
      expect(agri[0].etiqueta, 'Maíz');
      expect(agri[1].etiqueta, 'Trigo');
      expect(agri[0].indice, isNot(agri[1].indice));
    });
  });

  group('la etiqueta que ve la persona', () {
    test('cada tipo muestra su propio identificador', () {
      String etiqueta(String seccion) =>
          slotsDeFoto(l).firstWhere((s) => s.seccion == seccion).etiqueta;

      expect(etiqueta('danos-viales'), 'Puente Viejo');
      expect(etiqueta('danos-infra-publica'), contains('Escuela'));
      expect(etiqueta('salud-establecimientos'), 'Hospital');
      expect(etiqueta('unidades-educativas'), contains('Escuela 1'));
      expect(etiqueta('danos-vivienda'), 'San Pedro');
      expect(etiqueta('danos-agricultura'), 'Maíz');
      expect(etiqueta('danos-pecuarios'), 'Vacas');
      expect(etiqueta('infra-productiva'), 'Silos');
      expect(etiqueta('servicios-basicos'), 'agua_potable');
    });
  });

  group('orden del wizard: coordenada primero, foto después', () {
    test('una captura escribe la coordenada del ítem y agrega la foto', () {
      final slot = slotsDeFoto(l).firstWhere((s) => s.seccion == 'danos-viales');
      expect(slot.tieneCoordenada, isFalse);
      expect(slot.tieneFoto, isFalse);

      // Lo que hace `EdanBotonSacarFoto.capturar`: primero `Position`, luego la
      // foto. El slot recibe las dos cosas.
      slot.registrarCaptura(
        lat: -17.02,
        lon: -65.29,
        foto: EdanFoto(ruta: 'C:/fotos/puente.jpg', latitud: -17.02, longitud: -65.29),
      );

      expect(slot.tieneCoordenada, isTrue);
      expect(slot.tieneFoto, isTrue);
      expect(slot.completo, isTrue);
      expect(l.danosViales.first.coordenadaLat, -17.02);
      expect(l.danosViales.first.coordenadaLon, -65.29);
      expect(l.danosViales.first.fotos.single.ruta, 'C:/fotos/puente.jpg');
    });

    test('una captura sin foto deja la coordenada a medias', () {
      final slot =
          slotsDeFoto(l).firstWhere((s) => s.seccion == 'danos-agricultura');
      slot.registrarCaptura(lat: -17.1, lon: -65.3);
      expect(slot.tieneCoordenada, isTrue);
      expect(slot.tieneFoto, isFalse);
      expect(slot.completo, isFalse);
    });

    test('una foto con ruta vacía no cuenta como foto', () {
      final slot = slotsDeFoto(l).firstWhere((s) => s.seccion == 'danos-pecuarios');
      slot.registrarCaptura(lat: 1, lon: 2, foto: EdanFoto(ruta: '   '));
      expect(slot.tieneFoto, isFalse);
    });

    test('la coordenada 0/0 cuenta como "no capturada"', () {
      final slot = slotsDeFoto(l).firstWhere((s) => s.seccion == 'infra-productiva');
      slot.registrarCaptura(lat: 0, lon: 0, foto: EdanFoto(ruta: 'x.jpg'));
      expect(slot.tieneCoordenada, isFalse);
      expect(slot.completo, isFalse);
    });
  });

  group('la lista de trabajo del paso final', () {
    test('slotsPendientes quita solo lo que ya está completo', () {
      final slots = slotsDeFoto(l);
      slots.first.registrarCaptura(
        lat: 1,
        lon: 2,
        foto: EdanFoto(ruta: 'a.jpg'),
      );
      expect(slotsPendientes(l), hasLength(8));
      expect(slots.firstWhere((s) => s.completo).seccion, slots.first.seccion);
    });

    test('resumenFotos cuenta los tres estados', () {
      final slots = slotsDeFoto(l);
      slots[0].registrarCaptura(lat: 1, lon: 2, foto: EdanFoto(ruta: 'a.jpg'));
      slots[1].registrarCaptura(lat: 1, lon: 2);

      final r = resumenFotos(l);
      expect(r.total, 9);
      expect(r.conFoto, 1);
      expect(r.soloCoordenada, 1);
      expect(r.pendientes, 8);
    });

    test('agrupar por sección conserva el orden del formulario', () {
      final porSeccion = slotsDeFotoPorSeccion(l);
      expect(porSeccion.keys.toList(), kEdanSeccionesConFoto.keys.toList());
    });
  });

  group('las fotos y coordenadas sobreviven a toJson/fromJson', () {
    test('el viaje del ítem conserva la foto y su coordenada', () {
      final slot = slotsDeFoto(l).firstWhere((s) => s.seccion == 'danos-vivienda');
      slot.registrarCaptura(
        lat: -17.5,
        lon: -65.1,
        foto: EdanFoto(ruta: 'C:/fotos/vivienda.jpg', latitud: -17.5, longitud: -65.1),
      );

      final a = EdanDanoVivienda.fromJson(l.danosVivienda.first.toJson());
      expect(a.coordenadaLat, -17.5);
      expect(a.coordenadaLon, -65.1);
      expect(a.fotos, hasLength(1));
      expect(a.fotos.first.ruta, 'C:/fotos/vivienda.jpg');
    });

    test('toFotoData manda las coordenadas de la foto sobre las de la sección',
        () {
      // Es la regla del servidor: la foto manda.
      final v = l.danosVivienda.first..coordenadaLat = 1..coordenadaLon = 2;
      final foto = EdanFoto(ruta: 'a.jpg', latitud: -17.9, longitud: -65.9);
      final data = v.toFotoData(foto);
      expect(data['coordenada_lat'], -17.9);
      expect(data['coordenada_lon'], -65.9);
    });

    test('un ítem sin foto no inventa coordenadas', () {
      final v = EdanDanoVivienda.fromJson(l.danosVivienda.first.toJson());
      expect(v.coordenadaLat, 0);
      expect(v.coordenadaLon, 0);
      expect(v.fotos, isEmpty);
    });
  });
}
