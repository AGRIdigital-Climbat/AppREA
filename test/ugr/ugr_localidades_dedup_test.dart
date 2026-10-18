/// Dedup del merge híbrido de Localidades UGR (server municipio + SQLite
/// propio). Cubre la garantía de paridad con RESP: un EDAN que el UGR creó y
/// aún no sincroniza se LISTA como pendiente, y en cuanto existe en el server
/// (por `id_edan_localidad` o por uuid) NO se duplica.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rea/models/edan.dart';
import 'package:rea/screens/role_screens/ugr/ugr_localidades_tab.dart';

EdanLocalidad loc({
  required String nombre,
  int? idServer,
  String? idLocal,
  String? uuid,
}) {
  final l = EdanLocalidad(nombre: nombre, idTipoEvento: 1)
    ..idLocal = idLocal
    ..uuidEdanLocalidad = uuid;
  if (idServer != null) l.idServer = idServer;
  return l;
}

void main() {
  group('sinDuplicadas (merge server+SQLite UGR)', () {
    test('local ya sincronizado por id_edan_localidad se descarta', () {
      final servidor = [loc(nombre: 'A', idServer: 1, uuid: 'uuid-a')];
      final locales = [loc(nombre: 'A', idServer: 1, uuid: 'uuid-a')];
      expect(UgrLocalidadesTab.sinDuplicadas(servidor, locales), isEmpty);
    });

    test('local pendiente (sin idServer, uuid nuevo) se conserva', () {
      final servidor = [loc(nombre: 'A', idServer: 1, uuid: 'uuid-a')];
      final locales = [loc(nombre: 'B', uuid: 'uuid-b')]; // idServer null
      final res = UgrLocalidadesTab.sinDuplicadas(servidor, locales);
      expect(res.map((l) => l.nombre), ['B']);
    });

    test('dedup por uuid cuando el server solo trae id_local (sin uuid)', () {
      // Server: fila cuya identidad uuid vive en id_local (v2 legacy espejo),
      // sin uuid_edan_localidad y sin idServer local en el mirror.
      final servidor = [loc(nombre: 'C', idServer: 5, idLocal: 'uuid-c')];
      // Local: sincronizada, con uuid pero idServer aún sin retro-traer (null).
      final locales = [loc(nombre: 'C', uuid: 'uuid-c')];
      expect(UgrLocalidadesTab.sinDuplicadas(servidor, locales), isEmpty,
          reason: 'mismo uuid => no duplicar aunque falte el idServer local');
    });

    test('dedup por idServer aunque el uuid difiera', () {
      final servidor = [loc(nombre: 'D', idServer: 9, uuid: 'uuid-d-server')];
      final locales = [loc(nombre: 'D', idServer: 9, uuid: 'uuid-d-local')];
      expect(UgrLocalidadesTab.sinDuplicadas(servidor, locales), isEmpty);
    });

    test('local sin ninguna identidad no se descarta (no se puede dedupear)',
        () {
      final servidor = [loc(nombre: 'A', idServer: 1, uuid: 'uuid-a')];
      final locales = [loc(nombre: 'E')]; // idServer null, uuid null, idLocal null
      expect(UgrLocalidadesTab.sinDuplicadas(servidor, locales).length, 1);
    });

    test('mezcla: queda solo lo verdaderamente nuevo', () {
      final servidor = [
        loc(nombre: 'A', idServer: 1, uuid: 'uuid-a'),
        loc(nombre: 'B', idServer: 2, uuid: 'uuid-b'),
      ];
      final locales = [
        loc(nombre: 'A', idServer: 1, uuid: 'uuid-a'), // dup
        loc(nombre: 'B', uuid: 'uuid-b'), // dup por uuid
        loc(nombre: 'C', uuid: 'uuid-c'), // nuevo pendiente
      ];
      final res = UgrLocalidadesTab.sinDuplicadas(servidor, locales);
      expect(res.map((l) => l.nombre), ['C']);
    });
  });
}
