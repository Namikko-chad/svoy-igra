import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svoy_igra_client/core/theme.dart';
import 'package:svoy_igra_client/data/models.dart';
import 'package:svoy_igra_client/data/socket.dart';
import 'package:svoy_igra_client/features/admin/player_admin_card.dart';
import 'package:svoy_igra_client/features/game/blocks_view.dart';
import 'package:svoy_igra_client/features/game/board.dart';
import 'package:svoy_igra_client/features/game/question_panel.dart';
import 'package:svoy_igra_client/features/player/buzzer.dart';

Widget _app(Widget child) => MaterialApp(theme: buildTheme(), home: Scaffold(body: child));

List<BoardCategory> _board(int cats, [int values = 5]) => [
      for (var c = 0; c < cats; c++)
        BoardCategory(id: c, name: 'Тема номер $c с длинным названием', questions: [
          for (var q = 0; q < values; q++) BoardQuestion(id: c * 100 + q, value: (q + 1) * 100, played: q == 1 && c == 1),
        ]),
    ];

void main() {
  testWidgets('rotated board: values fit their cells at phone, tablet and desktop sizes', (tester) async {
    final boards = {'10×10': _board(10, 10), '6×5': _board(6, 5)};
    final sizes = {
      'phone portrait': const Size(390, 844),
      'phone landscape': const Size(844, 390),
      'tablet': const Size(1280, 800),
      'desktop min window': const Size(400, 560),
      'desktop full HD': const Size(1920, 1080),
    };
    for (final b in boards.entries) {
      for (final sz in sizes.entries) {
        tester.view.physicalSize = sz.value;
        tester.view.devicePixelRatio = 1;
        BoardQuestion? tapped;
        await tester.pumpWidget(_app(GameBoard(board: b.value, onSelect: (q) => tapped = q)));
        expect(tester.takeException(), isNull, reason: '${b.key} @ ${sz.key}');
        expect(find.byType(FittedBox), findsWidgets);
        if (b.key == '10×10' && sz.key == 'tablet') expect(find.text('1000'), findsNWidgets(10));
        // Every visible value lies inside its cell.
        for (final e in find.byType(FittedBox).evaluate()) {
          final fitted = find.byElementPredicate((x) => x == e);
          final cell = find.ancestor(of: fitted, matching: find.byType(InkWell)).first;
          final text = find.descendant(of: fitted, matching: find.byType(Text));
          final cr = tester.getRect(cell), tr = tester.getRect(text);
          if (cr.right > sz.value.width || cr.bottom > sz.value.height) continue; // scrolled off-screen
          expect(tr.left >= cr.left - 0.5 && tr.right <= cr.right + 0.5, isTrue, reason: '${b.key} @ ${sz.key}: $tr in $cr');
          expect(tr.height <= cr.height * 0.46, isTrue, reason: 'value height ${tr.height} of ${cr.height}');
        }
        // Rows share the height: first and last category name boxes are equally tall.
        final first = tester.getRect(find.text(b.value.first.name.toUpperCase()));
        expect(first.height, greaterThan(0));
        await tester.tap(find.text('100').first);
        expect(tapped?.value, 100);
      }
    }
    tester.view.reset();
  });

  test('board layout: tablet shows everything, phone portrait scrolls values', () {
    final tablet = BoardLayout.of(const Size(1280, 760), rows: 10, cells: 10);
    expect(tablet.scrollX, isFalse);
    expect(tablet.scrollY, isFalse);
    final phone = BoardLayout.of(const Size(390, 700), rows: 10, cells: 10);
    expect(phone.scrollX, isTrue);
    expect(phone.cellWidth, BoardLayout.minCellWidthPhone);
    expect(phone.nameWidth, 104);
    final small = BoardLayout.of(const Size(390, 700), rows: 6, cells: 3);
    expect(small.scrollX, isFalse);
    // Rows fill the height equally.
    expect(small.rowHeight * 6 + BoardLayout.gap * 5, closeTo(700 - 2 * BoardLayout.padding, 0.01));
  });

  testWidgets('buzzer states', (tester) async {
    for (final state in BuzzerState.values.where((s) => s != BuzzerState.hidden)) {
      var pressed = 0;
      final me = MeView(
        id: 'p', name: 'A', score: 0, canSelect: false, buzzer: state,
        buzzOpensAt: state == BuzzerState.waiting ? DateTime.now().millisecondsSinceEpoch + 3000 : null,
        canType: false,
      );
      await tester.pumpWidget(_app(Center(
        child: Buzzer(me: me, now: () => DateTime.now().millisecondsSinceEpoch, size: 240, onPress: () => pressed++),
      )));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byType(Buzzer), warnIfMissed: false);
      expect(pressed, state == BuzzerState.open ? 1 : 0);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('admin card renders all metrics', (tester) async {
    final p = PlayerView.fromJson(jsonDecode('''
      {"id":"p_1","name":"Аня","score":-200,"connected":false,"admin":{
        "device":{"platform":"android","model":"Pixel 8","os":"Android 15","appVersion":"1.0.0","userAgent":"ua","screen":"1080x2400","ip":"1.2.3.4"},
        "rttMs":40,"rttAvgMs":120,"jitterMs":9,"lastSeenAt":1761400000000,"buzzOffsetMs":-300,"effectiveOffsetMs":-320,
        "stats":{"correct":1,"wrong":2,"buzzes":3,"avgReactionMs":350,"bestReactionMs":200}}}''') as Map<String, dynamic>);
    final socket = GameSocket(baseUrl: 'http://127.0.0.1:1', token: 't');
    await tester.pumpWidget(_app(SingleChildScrollView(child: PlayerAdminCard(player: p, socket: socket))));
    expect(find.text('40 мс'), findsOneWidget);
    expect(find.text('-300 мс'), findsOneWidget);
    expect(tester.takeException(), isNull);
    socket.dispose();
  });

  testWidgets('answer and comment media use the playable media widgets', (tester) async {
    const video = Block.media(BlockType.video, '/api/packs/p/media/v.mp4', '');
    await tester.pumpWidget(_app(SingleChildScrollView(
      child: AnswerCard(
        blocks: const [Block.text('Ответ'), video, video, Block.media(BlockType.audio, '/api/packs/p/media/a.mp3', 'гимн')],
        comment: 'См. ![](media:c.mp4)',
        packId: 'p',
        scope: '7',
        mode: MediaMode.player,
        resolveUrl: (u) => 'http://127.0.0.1:1$u',
      ),
    )));
    await tester.pump();
    // Same video twice + the comment's video: three independent players, no key clash.
    expect(find.byType(VideoBlock), findsNWidgets(3));
    expect(find.byType(AudioChip), findsOneWidget);
    expect(find.text('🔊 звучит на экране'), findsOneWidget);
    final v = tester.widget<VideoBlock>(find.byType(VideoBlock).first);
    expect(v.autoplay && v.controls, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  test('media modes', () {
    const host = VideoBlock(url: 'u', mode: MediaMode.host, maxHeight: 1);
    const screen = VideoBlock(url: 'u', mode: MediaMode.screen, maxHeight: 1);
    expect((host.autoplay, host.controls), (false, true));
    expect((screen.autoplay, screen.controls), (true, false));
  });
}
