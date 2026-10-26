import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svoy_igra_tv/core/theme/app_theme.dart';
import 'package:svoy_igra_tv/core/widgets/avatar.dart';
import 'package:svoy_igra_tv/core/widgets/stage_scaler.dart';
import 'package:svoy_igra_tv/data/ws/game_socket.dart';
import 'package:svoy_igra_tv/features/display/display_screen.dart';
import 'package:svoy_igra_tv/features/display/widgets/board_view.dart';

import 'support/fake_channel.dart';

Map<String, dynamic> _view({required int categories, required int values, String phase = 'board'}) => {
      'serverNow': 1761400000000,
      'role': 'screen',
      'game': {
        'pin': null,
        'title': 'T',
        'link': null,
        'hostTaken': true,
        'hostConnected': true,
        'hostAvatarUrl': '/api/games/g_x/avatars/host.webp',
      },
      'phase': phase,
      'pack': {'id': 'pk', 'title': 'P'},
      'round': {'index': 0, 'name': 'R', 'total': 1, 'kind': 'normal'},
      'board': [
        for (var c = 0; c < categories; c++)
          {
            'id': c,
            'name': 'Очень длинное название категории номер $c',
            'questions': [
              for (var q = 0; q < values; q++) {'id': c * 100 + q, 'value': (q + 1) * 1000, 'played': (c + q) % 4 == 0},
            ],
          },
      ],
      'players': [
        {'id': 'p1', 'name': 'Анна Петрова', 'score': 1200, 'connected': true, 'avatarUrl': '/api/games/g_x/avatars/a.webp'},
        {'id': 'p2', 'name': 'Боря', 'score': -100, 'connected': true, 'avatarUrl': null},
      ],
      'chooserId': 'p1',
      'question': null,
      'attemptedPlayerIds': [],
    };

Future<GameSocket> _pump(WidgetTester tester, Map<String, dynamic> state) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final socket = GameSocket(
    base: Uri.parse('http://10.0.0.2:3050'),
    token: 't',
    hello: () async => {},
    connector: (_) => FakeChannel(),
  )..start();
  socket.handleFrame(jsonEncode({'type': 'state', 'data': state}));
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.build(),
    builder: (context, child) => StageScaler(child: child!),
    home: DisplayScreen(socket: socket, onChangeGame: () {}, onChangeServer: () {}),
  ));
  await tester.pump(const Duration(milliseconds: 500));
  return socket;
}

void main() {
  for (final (cats, vals) in [(10, 10), (6, 5), (3, 3)]) {
    testWidgets('board $cats×$vals: one row per category, values fit their cells', (tester) async {
      final socket = await _pump(tester, _view(categories: cats, values: vals));
      expect(tester.takeException(), isNull);
      expect(find.byType(BoardCell), findsNWidgets(cats * vals));

      // Rows: every category name sits in the same left column, rows stacked.
      final first = tester.getTopLeft(find.text('ОЧЕНЬ ДЛИННОЕ НАЗВАНИЕ КАТЕГОРИИ НОМЕР 0'));
      final last = tester.getTopLeft(find.text('ОЧЕНЬ ДЛИННОЕ НАЗВАНИЕ КАТЕГОРИИ НОМЕР ${cats - 1}'));
      expect(last.dx, closeTo(first.dx, 0.5));
      expect(last.dy, greaterThan(first.dy));

      // Every visible value is inside its cell.
      for (final cell in find.byType(BoardCell).evaluate()) {
        final cellBox = tester.getRect(find.byWidget(cell.widget));
        final texts = find.descendant(of: find.byWidget(cell.widget), matching: find.byType(Text));
        for (final t in texts.evaluate()) {
          final r = tester.getRect(find.byWidget(t.widget));
          expect(cellBox.inflate(0.5).contains(r.topLeft) && cellBox.inflate(0.5).contains(r.bottomRight), isTrue,
              reason: 'value overflows its cell');
        }
      }
      await tester.pumpWidget(const SizedBox());
      socket.dispose();
    });
  }

  testWidgets('avatars: network image with the server base, initials fallback, host badge', (tester) async {
    final socket = await _pump(tester, _view(categories: 3, values: 3));
    final urls = tester
        .widgetList<Image>(find.byType(Image))
        .map((i) => i.image)
        .whereType<ResizeImage>()
        .map((r) => (r.imageProvider as NetworkImage).url)
        .toSet();
    expect(urls, contains('http://10.0.0.2:3050/api/games/g_x/avatars/a.webp'));
    expect(urls, contains('http://10.0.0.2:3050/api/games/g_x/avatars/host.webp'));
    expect(find.text('Б'), findsWidgets); // Боря has no avatar → initials
    expect(find.text('Ведущий'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    socket.dispose();
  });

  test('initials', () {
    expect(Avatar.initials('Анна Петрова'), 'АП');
    expect(Avatar.initials('  боря '), 'Б');
    expect(Avatar.initials(''), '?');
  });
}
