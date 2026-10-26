import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svoy_igra_client/core/platform.dart';
import 'package:svoy_igra_client/data/api.dart';
import 'package:svoy_igra_client/data/url_scheme.dart';
import 'package:svoy_igra_client/features/avatar/avatar_editor.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('client platform follows the target platform', () {
    const expected = {
      TargetPlatform.android: ClientPlatform.android,
      TargetPlatform.windows: ClientPlatform.windows,
      TargetPlatform.linux: ClientPlatform.linux,
      TargetPlatform.macOS: ClientPlatform.macos,
    };
    for (final e in expected.entries) {
      debugDefaultTargetPlatformOverride = e.key;
      expect(clientPlatform, e.value);
      expect(isDesktop, e.key != TargetPlatform.android);
    }
    // hello.platform values (protocol §4.1).
    expect(ClientPlatform.values.map((p) => p.name), ['android', 'windows', 'linux', 'macos']);
  });

  test('linux .desktop entry handles svoyigra:// with the bundled icon', () {
    final entry = linuxDesktopEntry('/opt/svoy igra/svoy_igra');
    expect(entry, contains('Exec="/opt/svoy igra/svoy_igra" %u\n'));
    expect(entry, contains('Icon=/opt/svoy igra/data/flutter_assets/assets/icon.png\n'));
    expect(entry, contains('MimeType=x-scheme-handler/svoyigra;\n'));
    expect(entry, contains('StartupWMClass=$linuxAppId\n'));
  });

  for (final desktop in [false, true]) {
    testWidgets('avatar sheet: camera only on the phone (desktop: $desktop)', (tester) async {
      debugDefaultTargetPlatformOverride = desktop ? TargetPlatform.linux : TargetPlatform.android;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => editMyAvatar(context, Api('http://127.0.0.1:1')),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Сделать фото'), desktop ? findsNothing : findsOneWidget);
      expect(find.text(desktop ? 'Выбрать файл' : 'Выбрать из галереи'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
