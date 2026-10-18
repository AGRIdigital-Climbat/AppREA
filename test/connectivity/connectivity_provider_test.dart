/// Regresión del bug que dejaba el botón Sincronizar deshabilitado.
///
/// El botón se habilita con `online && chequeoCompletado` (`resp_screen` /
/// `ugr_screen`). Antes, con red estable, el primer chequeo no se comunicaba
/// (el servicio solo emitía al cambiar de estado y el valor optimista inicial
/// ya era `true`), así que `chequeoCompletado` quedaba en `false` de por vida.
/// Estos tests fijan que, tras `initialize()`, el provider siempre conoce el
/// resultado real del primer chequeo.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rea/providers/connectivity_provider.dart';
import 'package:rea/services/connectivity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConnectivityService service;

  setUp(() {
    service = ConnectivityService();
    service.debugReset();
    ConnectivityService.debugOmitirPlugin = true;
  });

  tearDown(() {
    service.debugReset();
  });

  test('online estable: el provider queda chequeoCompletado = true', () async {
    ConnectivityService.debugChequeoDeRed = () async => true;

    final provider = ConnectivityProvider();
    await provider.initialize();

    expect(provider.chequeoCompletado, isTrue);
    expect(provider.isConnected, isTrue);

    provider.dispose();
  });

  test('sin red: comunica chequeoCompletado = true e isConnected = false',
      () async {
    ConnectivityService.debugChequeoDeRed = () async => false;

    final provider = ConnectivityProvider();
    await provider.initialize();

    expect(provider.chequeoCompletado, isTrue);
    expect(provider.isConnected, isFalse);

    provider.dispose();
  });

  test('initialize es idempotente y esperable: dos await comparten el chequeo',
      () async {
    var llamadas = 0;
    final completer = Completer<bool>();
    ConnectivityService.debugChequeoDeRed = () {
      llamadas++;
      return completer.future;
    };

    final p1 = ConnectivityProvider();
    final f1 = p1.initialize();
    final p2 = ConnectivityProvider();
    final f2 = p2.initialize();

    completer.complete(true);
    await Future.wait([f1, f2]);

    expect(llamadas, 1, reason: 'un solo chequeo real de red');
    expect(p1.chequeoCompletado, isTrue);
    expect(p2.chequeoCompletado, isTrue);

    p1.dispose();
    p2.dispose();
  });
}
