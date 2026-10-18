import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rea/screens/role_screens/resp/edan/edan_boton_sacar_foto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('EdanFotoMiniatura muestra el overlay de retomar solo si se pasa onRetomar',
      (tester) async {
    var retomadas = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: EdanFotoMiniatura(
              width: 72,
              height: 72,
              onRetomar: () => retomadas++,
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.refresh), findsOneWidget);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    expect(retomadas, 1);
  });

  testWidgets('EdanFotoMiniatura sin onRetomar no dibuja el overlay',
      (tester) async {
    var tocadas = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: EdanFotoMiniatura(
              width: 72,
              height: 72,
              onTap: () => tocadas++,
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.refresh), findsNothing);

    await tester.tap(find.byType(EdanFotoMiniatura));
    await tester.pump();
    expect(tocadas, 1);
  });

  testWidgets('tocar el overlay no abre el visor (no propaga onTap)',
      (tester) async {
    var tocadas = 0;
    var retomadas = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: EdanFotoMiniatura(
              width: 72,
              height: 72,
              onTap: () => tocadas++,
              onRetomar: () => retomadas++,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    expect(retomadas, 1);
    expect(tocadas, 0);

    await tester.tap(find.byType(EdanFotoMiniatura));
    await tester.pump();
    expect(tocadas, 1);
    expect(retomadas, 1);
  });
}
