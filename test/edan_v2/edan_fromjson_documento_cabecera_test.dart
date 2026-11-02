/// `Edan.fromJson` con la forma REAL de los documentos del servidor
/// (`GET /edan/{id}`, `GET /formularios`, `GET /formularios/{uuid}/completo`):
///
/// * cada localidad viene envuelta en `{"cabecera": {...}, secciones...}` →
///   debe desempaquetarse a plano antes de `EdanLocalidad.fromJson` (si no,
///   la pestaña EDAN del rol 6 queda vacía: nombre/flags/estado en `cabecera`);
/// * las secciones 1:1 (`necesidad_primera_respuesta`, `necesidad_salud`,
///   `necesidad_humanitaria`) llegan como **lista de 0..1 filas**;
/// * sin nodo `cabecera` (snapshots locales / card maps) el parser debe
///   comportarse EXACTAMENTE igual que antes (passthrough).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rea/models/edan.dart';

void main() {
  Map<String, dynamic> _cabecera() => {
        'uuid_edan_localidad': 'u-79-a',
        'localidad': 'Santa Cruz de la Sierra',
        'tipo_localidad': 'Ciudad',
        'id_municipio': 70101,
        'id_usuario': 55,
        'fecha_modificacion': '2026-10-19T13:03:11.504187',
        'estado_localidad': {'id': 3, 'nombre': 'Aprobado UGR'},
        'grup_agropecuario': true,
        'grup_necesidades': true,
        'imp_danos_agricultura': true,
        'imp_primera_respuesta': true,
        'imp_necesidad_humanitaria': true,
        'imp_necesidad_salud': false,
      };

  Map<String, dynamic> _edanServidor() => {
        'id_edan': 79,
        'codigo_edan': 'SCZ-79',
        'id_municipio': 70101,
        'num_localidades': 2,
        'localidades': [
          {
            // Documento envuelto: cabecera + secciones al nivel superior.
            'cabecera': _cabecera(),
            'impacto_poblacion': [
              {
                'uuid_registro': 'ip-1',
                'grupo_etario': 'Ninos',
                'fallecidos': 0,
                'heridos': 2,
              },
            ],
            'danos_agricultura': [
              {
                'uuid_registro': 'ag-1',
                'tipo_cultivo': 'Maiz',
                'coordenada_lat': -16.5,
                'coordenada_lon': -68.1,
              },
            ],
            'necesidad_primera_respuesta': [
              {
                'uuid_registro': 'nr-1',
                'id_edan_localidad': 'u-79-a',
                'busqueda': true,
                'salvamento': false,
                'evacuacion': true,
              },
            ],
            'necesidad_salud': <Map<String, dynamic>>[],
            'necesidad_humanitaria': [
              {
                'uuid_registro': 'nh-1',
                'alimentos': true,
                'refugio_vivienda': true,
              },
            ],
            'proteccion': <Map<String, dynamic>>[],
          },
          {
            // Forma plana legacy (snapshots locales / card maps) → passthrough.
            'uuid_edan_localidad': 'u-plana',
            'localidad': 'Localidad Planera',
            'id_municipio': 70101,
            'imp_danos_agricultura': false,
          },
        ],
      };

  group('Edan.fromJson · documentos con cabecera', () {
    test('desempaqueta la cabecera de cada localidad (nombre, uuid, flags '
        'grup_*/imp_*, estado y fecha_modificacion)', () {
      final edan = Edan.fromJson(_edanServidor());

      expect(edan.localidades, hasLength(2));

      final loc = edan.localidades.first;
      expect(loc.uuidEdanLocalidad, 'u-79-a');
      expect(loc.nombre, 'Santa Cruz de la Sierra',
          reason: 'el nombre vive en cabecera; sin unwrap el detalle sale vacío');
      expect(loc.tipoLocalidad, 'Ciudad');
      expect(loc.idMunicipio, 70101);
      expect(loc.fechaModificacion, '2026-10-19T13:03:11.504187');
      expect(loc.idEdanLocalidadEstado, 3);
      expect(loc.estadoLocalidad, UgrLocalidadEstado.aprobadoUgr);
      expect(loc.grupAgropecuario, isTrue);
      expect(loc.grupNecesidades, isTrue);
      expect(loc.impDanosAgricultura, isTrue);
      expect(loc.impPrimeraRespuesta, isTrue);
      expect(loc.impNecesidadHumanitaria, isTrue);
      expect(loc.impNecesidadSalud, isFalse);
      expect(loc.etiquetaLugar, 'Ciudad Santa Cruz de la Sierra');
    });

    test('las secciones 1:1 llegan como lista de 0..1 filas y se hidratan', () {
      final loc = Edan.fromJson(_edanServidor()).localidades.first;

      expect(loc.necesidadPrimeraRespuesta, isNotNull,
          reason: 'lista de 1 fila debe parsear (antes se descartaba)');
      expect(loc.necesidadPrimeraRespuesta!.busqueda, isTrue);
      expect(loc.necesidadPrimeraRespuesta!.evacuacion, isTrue);
      expect(loc.necesidadPrimeraRespuesta!.salvamento, isFalse);

      expect(loc.necesidadHumanitaria, isNotNull);
      expect(loc.necesidadHumanitaria!.alimentos, isTrue);
      expect(loc.necesidadHumanitaria!.refugioVivienda, isTrue);

      expect(loc.necesidadSalud, isNotNull,
          reason: 'lista vacía → el constructor defaultea a objeto vacío '
              '(mismo resultado que la clave ausente de antes)');
      expect(loc.necesidadSalud!.botiquines, isFalse);
      expect(loc.necesidadSalud!.numeroPersonas, 0);
    });

    test('las secciones 1:N del documento quedan hidratadas con coordenadas', () {
      final loc = Edan.fromJson(_edanServidor()).localidades.first;

      expect(loc.impactoPoblacion, hasLength(1));
      expect(loc.impactoPoblacion.first.grupoEtario, 'Ninos');
      expect(loc.impactoPoblacion.first.heridos, 2);

      expect(loc.danosAgricultura, hasLength(1));
      expect(loc.danosAgricultura.first.tipoCultivo, 'Maiz');
      expect(loc.danosAgricultura.first.coordenadaLat, -16.5);
      expect(loc.danosAgricultura.first.coordenadaLon, -68.1);
    });

    test('localidad plana sin cabecera: passthrough idéntico al parser viejo',
        () {
      final edan = Edan.fromJson(_edanServidor());

      final plana = edan.localidades[1];
      expect(plana.uuidEdanLocalidad, 'u-plana');
      expect(plana.nombre, 'Localidad Planera');
      expect(plana.impDanosAgricultura, isFalse);
      expect(plana.necesidadPrimeraRespuesta, isNotNull,
          reason: 'constructor defaultea a objeto vacío (igual que antes '
              'con la clave ausente)');
      expect(plana.necesidadPrimeraRespuesta!.busqueda, isFalse);
      expect(plana.grupAgropecuario, isFalse);
    });

    test('necesidad_* como OBJETO único (round-trip de toJson propio) sigue '
        'funcionando', () {
      final loc = EdanLocalidad.fromJson({
        'localidad': 'Legacy',
        'necesidad_primera_respuesta': {'busqueda': true},
        'necesidad_salud': {'botiquines': true, 'numero_personas': 4},
        'necesidad_humanitaria': {'alimentos': true, 'banos': true},
      });

      expect(loc.necesidadPrimeraRespuesta, isNotNull);
      expect(loc.necesidadPrimeraRespuesta!.busqueda, isTrue);
      expect(loc.necesidadSalud, isNotNull);
      expect(loc.necesidadSalud!.botiquines, isTrue);
      expect(loc.necesidadSalud!.numeroPersonas, 4);
      expect(loc.necesidadHumanitaria, isNotNull);
      expect(loc.necesidadHumanitaria!.alimentos, isTrue);
      expect(loc.necesidadHumanitaria!.banos, isTrue);
    });

    test('desempaquetarCabecera: con nodo `cabecera` aplana; sin nodo devuelve '
        'el mismo mapa', () {
      const conNodo = {
        'cabecera': {'localidad': 'X', 'id_municipio': 70101},
        'danos_agricultura': [],
      };
      final aplanado = EdanLocalidad.desempaquetarCabecera(conNodo);
      expect(aplanado.containsKey('cabecera'), isFalse);
      expect(aplanado['localidad'], 'X');
      expect(aplanado['id_municipio'], 70101);
      expect(aplanado['danos_agricultura'], isEmpty);

      const sinNodo = {'localidad': 'Y'};
      expect(EdanLocalidad.desempaquetarCabecera(sinNodo), same(sinNodo));
    });
  });
}
