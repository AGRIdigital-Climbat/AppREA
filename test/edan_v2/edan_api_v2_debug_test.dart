/// Instrumentación de `EdanApiV2` hacia [SyncDebugCollector]: cada llamada V2
/// reporta su método, endpoint, request, response y status al panel de
/// depuración, y el `body` reportado es EXACTAMENTE el enviado (sin el
/// envoltorio `payload`/`fotos` que antes inventaba el diálogo).
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rea/services/api/edan_api_v2.dart';
import 'package:rea/services/sync_debug_collector.dart';
import 'package:rea/services/sync_debug_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  EdanApiV2 api(MockClient client) => EdanApiV2(
        httpClient: client,
        baseUrl: 'https://api.test/api/v2/edan',
      );

  // La instrumentación solo actúa con el modo debug encendido.
  const skip = !kSyncDebugMode;

  setUp(() {
    SyncDebugCollector.instance.startSession();
  });

  test('reporta el POST /completo con el body crudo (sin envoltorio payload)',
      skip: skip, () async {
    final payload = <String, dynamic>{
      'uuid_edan_localidad': 'u-dbg',
      'localidad': 'LOC',
      'imp_danos_agricultura': false,
    };
    late Map<String, dynamic> enviado;
    final client = MockClient((req) async {
      enviado = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({'success': true, 'data': {'ok': true}}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await api(client).crearFormularioCompleto(payload);

    // El body viajó plano: sin la clave 'payload'.
    expect(enviado.containsKey('payload'), isFalse);
    expect(enviado['uuid_edan_localidad'], 'u-dbg');

    final entradas = SyncDebugCollector.instance.entries.value
        .where((e) => e.metodo == 'POST')
        .toList();
    expect(entradas, hasLength(1));
    final e = entradas.single;
    expect(e.endpoint, contains('/formularios/completo'));
    expect(e.statusCode, 200);
    expect(e.requestBody, isNotNull);
    expect(e.requestBody!.containsKey('payload'), isFalse,
        reason: 'el panel muestra el body real, no un envoltorio');
    expect(e.requestBody!['uuid_edan_localidad'], 'u-dbg');
  });

  test('un 400 deja entrada con status 400 y el detail del servidor',
      skip: skip, () async {
    final client = MockClient((req) async => http.Response(
          jsonEncode({'success': false, 'detail': 'flag true sin filas'}),
          400,
          headers: {'content-type': 'application/json'},
        ));

    await expectLater(
      api(client).crearFormularioCompleto({'uuid_edan_localidad': 'u-dbg2'}),
      throwsA(isA<EdanApiError>()),
    );

    final e = SyncDebugCollector.instance.entries.value
        .firstWhere((x) => x.metodo == 'POST');
    expect(e.statusCode, 400);
    expect(e.isError, isTrue);
    expect(e.responseBody?['detail'], 'flag true sin filas',
        reason: 'el panel conserva la respuesta del servidor para depurar');
  });
}
