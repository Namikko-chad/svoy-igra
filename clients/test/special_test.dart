import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svoy_igra_client/core/theme.dart';
import 'package:svoy_igra_client/data/models.dart';
import 'package:svoy_igra_client/data/socket.dart';
import 'package:svoy_igra_client/features/game/blocks_view.dart';
import 'package:svoy_igra_client/features/game/final_panel.dart';
import 'package:svoy_igra_client/features/game/special.dart';

/// Records commands instead of sending them.
class FakeSocket extends GameSocket {
  FakeSocket() : super(baseUrl: 'http://127.0.0.1:1', token: 't');

  final sent = <(String, Map<String, dynamic>)>[];

  @override
  bool command(String type, [Map<String, dynamic> data = const {}]) {
    sent.add((type, data));
    return true;
  }
}

void expectCmd(FakeSocket s, String type, Map<String, dynamic> data) {
  expect(s.sent.last.$1, type);
  expect(s.sent.last.$2, equals(data));
}

Widget _app(Widget child) => MaterialApp(theme: buildTheme(), home: Scaffold(body: child));

Map<String, dynamic> _base(String phase, [Map<String, dynamic> extra = const {}]) => {
      'serverNow': 1000,
      'role': 'player',
      'phase': phase,
      'game': {'pin': '123456', 'title': 'T', 'link': null, 'hostTaken': true, 'hostConnected': true},
      'players': [
        {'id': 'p1', 'name': 'Аня', 'score': 500, 'connected': true},
        {'id': 'p2', 'name': 'Боря', 'score': 300, 'connected': true},
        {'id': 'p3', 'name': 'Вера', 'score': 0, 'connected': true},
      ],
      'chooserId': 'p1',
      'attemptedPlayerIds': <String>[],
      ...extra,
    };

const _me = {'id': 'p1', 'name': 'Аня', 'score': 500, 'canSelect': false, 'buzzer': 'hidden', 'canType': false};

void main() {
  test('parses special questions and the final', () {
    final v = GameView.fromJson(jsonDecode(jsonEncode(_base('auction', {
      'round': {'index': 1, 'name': 'Р2', 'total': 3, 'kind': 'normal'},
      'question': {'id': 9, 'categoryName': 'Кино', 'value': 200, 'modifier': 'auction', 'stake': 400, 'blocks': [], 'answerBlocks': null, 'comment': null},
      'soloPlayerId': null,
      'auction': {'turnPlayerId': 'p2', 'highBid': 400, 'highBidderId': 'p1', 'allIn': false, 'passedPlayerIds': ['p3']},
      'settings': {'readingSeconds': 10, 'buzzSeconds': 15, 'wrongPenalty': false, 'autoLatencyCompensation': false,
        'modifiers': {'cat': 2, 'auction': 0, 'noRisk': 1, 'double': 5}, 'finalSeconds': 90},
      'me': {..._me, 'canBid': true, 'finalist': true},
    }))) as Map<String, dynamic>);
    expect(v.phase, Phase.auction);
    expect(v.round!.isFinal, isFalse);
    expect(v.question!.modifier, Modifier.auction);
    expect(v.question!.stake, 400);
    expect(v.auction!.highBidderId, 'p1');
    expect(v.auction!.passedPlayerIds, ['p3']);
    expect(v.settings!.modifiers.cat, 2);
    expect(v.settings!.modifiers.of(Modifier.double), 5);
    expect(v.settings!.modifiers.withCount(Modifier.auction, 3), {'cat': 2, 'auction': 3, 'noRisk': 1, 'double': 5});
    expect(v.settings!.finalSeconds, 90);
    expect(v.me!.canBid, isTrue);
    expect(v.me!.canBet, isFalse);

    final f = GameView.fromJson(_base('final_judging', {
      'round': {'index': 2, 'name': 'Финал', 'total': 3, 'kind': 'final'},
      'final': {
        'themes': [
          {'id': 1, 'name': 'А', 'removed': true},
          {'id': 2, 'name': 'Б', 'removed': false},
        ],
        'removerId': null,
        'answerStartsAt': 2000,
        'answerEndsAt': 5000,
        'participants': [
          {'playerId': 'p1', 'hasBet': true, 'bet': 300, 'hasAnswer': true, 'answer': 'x', 'correct': null},
          {'playerId': 'p2', 'hasBet': true, 'bet': null, 'hasAnswer': false, 'answer': null, 'correct': false},
        ],
      },
    }));
    expect(f.phase.isFinal, isTrue);
    expect(f.round!.isFinal, isTrue);
    expect(f.finalView!.remainingTheme!.name, 'Б');
    expect(f.finalView!.answerStartsAt, 2000);
    expect(f.finalView!.answerEndsAt, 5000);
    expect(f.finalView!.participant('p1')!.correct, isNull);
    expect(f.finalView!.participant('p2')!.correct, isFalse);
    expect(Phase.parse('cat_transfer'), Phase.catTransfer);
    expect(Modifier.parse('no_risk')!.label, 'Вопрос без риска');
    // Old servers: stake falls back to the value, no modifier.
    expect(QuestionView.fromJson({'id': 1, 'value': 300}).stake, 300);
    expect(Round.fromJson({'id': 1, 'kind': 'final'}).isFinal, isTrue);
  });

  testWidgets('cat transfer: chooser picks another player', (tester) async {
    final v = GameView.fromJson(_base('cat_transfer', {
      'question': {'id': 9, 'categoryName': 'Кино', 'value': 200, 'modifier': 'cat', 'stake': 200, 'blocks': [], 'answerBlocks': null, 'comment': null},
    }));
    String? given;
    await tester.pumpWidget(_app(CatTransferPanel(view: v, canGive: true, meId: 'p1', onGive: (id) => given = id)));
    await tester.pumpAndSettle();
    expect(find.text('Кот в мешке'), findsOneWidget);
    expect(find.byKey(const ValueKey('give:p1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('give:p2')));
    expect(given, 'p2');
    await tester.pumpWidget(_app(CatTransferPanel(view: v, canGive: false)));
    expect(find.text('Кота в мешке отдаёт: Аня'), findsOneWidget);
  });

  testWidgets('auction: bid +100, all-in, pass on my turn; host closes', (tester) async {
    final socket = FakeSocket();
    final v = GameView.fromJson(_base('auction', {
      'question': {'id': 9, 'categoryName': 'Кино', 'value': 200, 'modifier': 'auction', 'stake': 200, 'blocks': [], 'answerBlocks': null, 'comment': null},
      'auction': {'turnPlayerId': 'p1', 'highBid': 200, 'highBidderId': 'p2', 'allIn': false, 'passedPlayerIds': []},
    }));
    final me = MeView.fromJson({..._me, 'canBid': true});
    await tester.pumpWidget(_app(AuctionPanel(view: v, socket: socket, me: me)));
    await tester.pumpAndSettle();
    expect(find.text('Ваш ход'), findsOneWidget);
    await tester.tap(find.byTooltip('+100'));
    await tester.pump();
    await tester.tap(find.text('Ставка'));
    expectCmd(socket, 'auction_bid', {'amount': 400});
    await tester.tap(find.text('Ва-банк'));
    expect(socket.sent.last.$1, 'auction_all_in');
    await tester.tap(find.text('Пас'));
    expect(socket.sent.last.$1, 'auction_pass');

    await tester.pumpWidget(_app(AuctionPanel(view: v, socket: socket, hostControls: true)));
    expect(find.text('Ставка'), findsNothing);
    await tester.tap(find.text('Закрыть торги'));
    expect(socket.sent.last.$1, 'auction_close');
    socket.dispose();
  });

  testWidgets('final: remove a theme, bet, host judges', (tester) async {
    final socket = FakeSocket();
    final themes = GameView.fromJson(_base('final_themes', {
      'final': {
        'themes': [
          {'id': 1, 'name': 'Кино', 'removed': false},
          {'id': 2, 'name': 'Спорт', 'removed': true},
        ],
        'removerId': 'p1',
        'answerEndsAt': null,
        'participants': [],
      },
    }));
    final me = MeView.fromJson({..._me, 'canRemoveTheme': true, 'finalist': true});
    await tester.pumpWidget(_app(FinalPanel(view: themes, socket: socket, mode: MediaMode.player, resolveUrl: (u) => u, me: me)));
    expect(find.text('Ваш ход: уберите тему'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('theme:2'))); // removed: no-op
    expect(socket.sent, isEmpty);
    await tester.tap(find.byKey(const ValueKey('theme:1')));
    expectCmd(socket, 'final_remove_theme', {'themeId': 1});

    final bets = GameView.fromJson(_base('final_bets', {
      'question': {'id': 5, 'categoryName': 'Кино (с сервера)', 'value': 0, 'stake': 0, 'blocks': [], 'answerBlocks': null, 'comment': null},
      'final': {
        'themes': [
          {'id': 1, 'name': 'Кино', 'removed': false},
        ],
        'removerId': null,
        'answerEndsAt': null,
        'participants': [
          {'playerId': 'p1', 'hasBet': false, 'bet': null, 'hasAnswer': false, 'answer': null, 'correct': null},
        ],
      },
    }));
    final bettor = MeView.fromJson({..._me, 'finalist': true, 'canBet': true});
    await tester.pumpWidget(_app(FinalPanel(view: bets, socket: socket, mode: MediaMode.player, resolveUrl: (u) => u, me: bettor)));
    expect(find.text('Кино (с сервера)'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '250');
    await tester.tap(find.text('Сделать ставку'));
    expectCmd(socket, 'final_bet', {'amount': 250});

    final judging = GameView.fromJson(_base('final_judging', {
      'question': {'id': 5, 'categoryName': 'Кино', 'value': 0, 'stake': 0, 'blocks': [{'type': 'text', 'markdown': 'Вопрос'}],
        'answerBlocks': [{'type': 'text', 'markdown': 'Ответ'}], 'comment': null},
      'final': {
        'themes': [
          {'id': 1, 'name': 'Кино', 'removed': false},
        ],
        'removerId': null,
        'answerEndsAt': null,
        'participants': [
          {'playerId': 'p1', 'hasBet': true, 'bet': 300, 'hasAnswer': true, 'answer': 'Титаник', 'correct': null},
          {'playerId': 'p2', 'hasBet': true, 'bet': 100, 'hasAnswer': true, 'answer': 'x', 'correct': true},
        ],
      },
    }));
    await tester.pumpWidget(_app(FinalPanel(view: judging, socket: socket, mode: MediaMode.host, resolveUrl: (u) => u, host: true)));
    await tester.pump();
    expect(find.text('«Титаник»'), findsOneWidget);
    expect(find.text('Верно +100'), findsOneWidget); // already judged
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Неверно'));
    await tester.tap(find.widgetWithText(FilledButton, 'Неверно'));
    expectCmd(socket, 'final_judge', {'playerId': 'p1', 'correct': false});
    await tester.pumpWidget(const SizedBox());
    socket.dispose();
  });
}
