import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:svoy_igra_client/core/theme.dart';
import 'package:svoy_igra_client/data/avatar_image.dart';
import 'package:svoy_igra_client/data/models.dart';
import 'package:svoy_igra_client/features/avatar/avatar.dart';

Uint8List _png(int w, int h) => Uint8List.fromList(img.encodePng(img.Image(width: w, height: h)));

void main() {
  test('squareAvatar crops to a centred square and caps at 512', () {
    final wide = img.decodeJpg(squareAvatar(_png(800, 400))!)!;
    expect((wide.width, wide.height), (400, 400));
    final tall = img.decodeJpg(squareAvatar(_png(1000, 1600))!)!;
    expect((tall.width, tall.height), (512, 512));
    final tiny = img.decodeJpg(squareAvatar(_png(64, 64))!)!;
    expect(tiny.width, 64);
    expect(squareAvatar(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('initials', () {
    expect(initials('Анна Петрова'), 'АП');
    expect(initials('боря'), 'Б');
    expect(initials('  '), '?');
  });

  test('avatar fields parse', () {
    final p = PlayerView.fromJson({'id': 'p', 'name': 'A', 'score': 0, 'connected': true, 'avatarUrl': '/api/games/g1/avatars/x.jpg'});
    expect(p.avatarUrl, '/api/games/g1/avatars/x.jpg');
    expect(PlayerView.fromJson({'id': 'p', 'avatarUrl': null}).avatarUrl, isNull);
    final g = GameRef.fromJson({'pin': '1', 'hostAvatarUrl': '/api/games/g1/avatars/h.jpg'});
    expect(g.hostAvatarUrl, endsWith('h.jpg'));
  });

  testWidgets('avatar shows initials without a picture and prefixes relative URLs', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const MediaBase(
        baseUrl: 'http://192.168.1.10:3050',
        child: Row(children: [
          Avatar(name: 'Анна Петрова', size: 40),
          Avatar(name: 'Боря', url: '/api/games/g1/avatars/b.jpg', size: 64),
        ]),
      ),
    ));
    expect(find.text('АП'), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as ResizeImage).imageProvider, isA<NetworkImage>().having((n) => n.url, 'url', 'http://192.168.1.10:3050/api/games/g1/avatars/b.jpg'));
    await tester.pump();
    // The network fails in tests → initials fallback, no exception.
    expect(tester.takeException(), isNull);
  });
}
