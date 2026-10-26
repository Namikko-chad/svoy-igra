import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svoy_igra_tv/app_controller.dart';
import 'package:svoy_igra_tv/core/theme/app_theme.dart';
import 'package:svoy_igra_tv/core/widgets/stage_scaler.dart';
import 'package:svoy_igra_tv/data/storage/server_store.dart';
import 'package:svoy_igra_tv/features/games/games_screen.dart';

import 'support/fake_api.dart';

Future<AppController> _app(FakeApi api) async {
  SharedPreferences.setMockInitialValues({'server.base': 'http://10.0.0.2:3050'});
  return AppController(await ServerStore.open(), apiFactory: (_) => api);
}

Future<void> _pump(WidgetTester tester, AppController app) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.build(),
    builder: (context, child) => StageScaler(child: child!),
    home: GamesScreen(app: app),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('lists live games as cards', (tester) async {
    final api = FakeApi()..games['654321'] = game('654321');
    await _pump(tester, await _app(api));
    expect(tester.takeException(), isNull);
    expect(find.text('Пятница'), findsNWidgets(2));
    // The public list never carries PINs, so none is shown.
    expect(find.text('123456'), findsNothing);
    expect(find.text('654321'), findsNothing);
    expect(find.text('Ввести PIN'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('empty state', (tester) async {
    final api = FakeApi()..games.clear();
    await _pump(tester, await _app(api));
    expect(find.text('Игр пока нет — создайте игру на телефоне или сайте'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
