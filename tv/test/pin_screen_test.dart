import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svoy_igra_tv/app_controller.dart';
import 'package:svoy_igra_tv/core/theme/app_theme.dart';
import 'package:svoy_igra_tv/core/widgets/stage_scaler.dart';
import 'package:svoy_igra_tv/data/storage/server_store.dart';
import 'package:svoy_igra_tv/features/pin/pin_screen.dart';

import 'support/fake_api.dart';

void main() {
  testWidgets('remote number keys enter the PIN and show the found game', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'server.base': 'http://10.0.0.2:3050'});
    final store = await ServerStore.open();
    final app = AppController(store, apiFactory: (_) => FakeApi());

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      builder: (context, child) => StageScaler(child: child!),
      home: PinScreen(app: app),
    ));
    await tester.pump();

    for (final key in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.numpad4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
    ]) {
      await tester.sendKeyEvent(key);
    }
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Пятница'), findsOneWidget);
    expect(find.text('Показать игру'), findsOneWidget);
  });
}
