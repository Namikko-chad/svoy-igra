import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:svoy_igra_tv/data/discovery/server_probe.dart';
import 'package:svoy_igra_tv/data/models/block.dart';
import 'package:svoy_igra_tv/data/models/game_event.dart';
import 'package:svoy_igra_tv/data/models/game_info.dart';
import 'package:svoy_igra_tv/data/models/game_view.dart';

/// A `state` frame as the screen receives it (protocol §4.2).
const sampleState = '''
{"type":"state","data":{
  "serverNow":1761400000000,"role":"screen",
  "game":{"pin":"123456","title":"Пятница","link":"http://quiz.lan/g/123456","hostTaken":true,"hostConnected":false},
  "phase":"reveal",
  "pack":{"id":"pk_1","title":"Пятничный квиз"},
  "round":{"index":0,"name":"Разминка","total":2},
  "board":[
    {"id":1,"name":"Кино","questions":[
      {"id":11,"value":100,"played":true},{"id":12,"value":200,"played":false}]},
    {"id":2,"name":"Музыка","questions":[{"id":21,"value":100,"played":false}]}
  ],
  "players":[
    {"id":"p_a","name":"Аня","score":300,"connected":true},
    {"id":"p_b","name":"Боря","score":-100,"connected":false},
    {"id":"p_c","name":"Вика","score":300,"connected":true}
  ],
  "chooserId":"p_a",
  "question":{"id":11,"categoryName":"Кино","value":100,
    "blocks":[
      {"type":"text","markdown":"Кто изображён на **фото**?"},
      {"type":"image","url":"/api/packs/pk_1/media/portrait.jpg","alt":""},
      {"type":"audio","url":"/api/packs/pk_1/media/anthem.mp3","alt":"гимн"}],
    "answerBlocks":[{"type":"text","markdown":"Чарли Чаплин"}],
    "comment":"Снимок 1915 года"},
  "answeringPlayerId":null,
  "attemptedPlayerIds":["p_b"],
  "readingStartsAt":null,"readingEndsAt":null,"buzzStartsAt":null,"buzzEndsAt":null,
  "typedAnswer":null,
  "lastResult":{"playerId":"p_a","correct":true,"delta":100},
  "settings":null,"me":null
}}
''';

void main() {
  test('parses a screen GameView', () {
    final frame = jsonDecode(sampleState) as Map<String, dynamic>;
    final v = GameView.fromJson(frame['data'] as Map<String, dynamic>);

    expect(v.phase, Phase.reveal);
    expect(v.game.pin, '123456');
    expect(v.game.link, 'http://quiz.lan/g/123456');
    expect(v.game.hostTaken, isTrue);
    expect(v.game.hostConnected, isFalse);
    expect(v.serverNow, 1761400000000);
    expect(v.pack!.title, 'Пятничный квиз');
    expect(v.round!.total, 2);
    expect(v.board, hasLength(2));
    expect(v.board.first.questions.first.played, isTrue);
    expect(v.boardRows, 2);
    expect(v.chooser!.name, 'Аня');
    expect(v.players[1].connected, isFalse);
    expect(v.attemptedPlayerIds, ['p_b']);
    expect(v.lastResult!.correct, isTrue);

    final q = v.question!;
    expect(q.blocks.map((b) => b.type), [BlockType.text, BlockType.image, BlockType.audio]);
    expect(q.blocks.first.markdown, 'Кто изображён на **фото**?');
    expect(q.blocks[2].alt, 'гимн');
    expect(q.answerBlocks!.single.markdown, 'Чарли Чаплин');
    expect(q.comment, 'Снимок 1915 года');
  });

  test('standings sort by score, ties keep join order', () {
    final frame = jsonDecode(sampleState) as Map<String, dynamic>;
    final v = GameView.fromJson(frame['data'] as Map<String, dynamic>);
    expect(v.standings.map((p) => p.name), ['Аня', 'Вика', 'Боря']);
  });

  test('tolerates a minimal lobby view', () {
    final v = GameView.fromJson({'phase': 'lobby', 'players': []});
    expect(v.phase, Phase.lobby);
    expect(v.pack, isNull);
    expect(v.game.pin, isNull);
    expect(v.game.link, isNull);
    expect(v.board, isEmpty);
    expect(v.question, isNull);
  });

  test('parses timer windows', () {
    final v = GameView.fromJson({
      'phase': 'question',
      'readingStartsAt': 1000,
      'readingEndsAt': 11000,
      'buzzStartsAt': 11000,
      'buzzEndsAt': 26000,
    });
    expect([v.readingStartsAt, v.readingEndsAt, v.buzzStartsAt, v.buzzEndsAt], [1000, 11000, 11000, 26000]);
  });

  test('a watch screen gets no PIN/link in state.game', () {
    final v = GameView.fromJson({
      'phase': 'lobby',
      'game': {'pin': null, 'title': 'T', 'link': null, 'hostTaken': false, 'hostConnected': false},
    });
    expect(v.game.title, 'T');
    expect(v.game.pin, isNull);
    expect(v.game.link, isNull);
  });

  test('sessions store token + game id, PIN optional', () {
    const watch = GameSession(token: 't1', gameId: 'g1', title: 'T');
    final back = GameSession.fromJson(watch.toJson())!;
    expect(back.gameId, 'g1');
    expect(back.pin, isNull);
    expect(GameSession.fromJson({'pin': '123456', 'token': 't2'})!.pin, '123456');
    expect(GameSession.fromJson({'gameId': 'g1'}), isNull);
  });

  test('parses /api/info webUrl', () {
    expect(ServerInfo.fromJson({'name': 'S', 'webUrl': 'http://quiz.lan/'}).webUrl, 'http://quiz.lan/');
    expect(ServerInfo.fromJson({'name': 'S', 'webUrl': null}).webUrl, isNull);
    expect(ServerInfo.fromJson({'name': 'S', 'webUrl': ' '}).webUrl, isNull);
  });

  test('parses special questions, auction and final', () {
    final v = GameView.fromJson({
      'phase': 'auction',
      'round': {'index': 0, 'name': 'R', 'total': 2, 'kind': 'normal'},
      'question': {'id': 3, 'categoryName': 'C', 'value': 300, 'modifier': 'auction', 'stake': 300, 'blocks': []},
      'soloPlayerId': null,
      'auction': {
        'turnPlayerId': 'p2',
        'highBid': 900,
        'highBidderId': 'p1',
        'allIn': true,
        'passedPlayerIds': ['p3'],
      },
    });
    expect(v.phase, Phase.auction);
    expect(v.round!.isFinal, isFalse);
    expect(v.question!.modifier, Modifier.auction);
    expect(v.question!.stake, 300);
    expect(v.auction!.allIn, isTrue);
    expect(v.auction!.passedPlayerIds, ['p3']);
    expect(Modifier.parse('no_risk')!.label, 'Вопрос без риска');
    expect(Modifier.parse('x'), isNull);

    final f = GameView.fromJson({
      'phase': 'final_question',
      'round': {'index': 1, 'name': 'Ф', 'total': 2, 'kind': 'final'},
      'soloPlayerId': null,
      'final': {
        'themes': [
          {'id': 1, 'name': 'A', 'removed': true},
          {'id': 2, 'name': 'B', 'removed': false},
        ],
        'removerId': null,
        'answerStartsAt': 1000,
        'answerEndsAt': 61000,
        'participants': [
          {'playerId': 'p1', 'hasBet': true, 'bet': null, 'hasAnswer': true, 'answer': null, 'correct': null},
          {'playerId': 'p2', 'hasBet': true, 'bet': 500, 'hasAnswer': true, 'answer': 'X', 'correct': false},
        ],
      },
    });
    expect(f.phase.isFinal, isTrue);
    expect(f.round!.isFinal, isTrue);
    expect(f.finalView!.remainingTheme!.name, 'B');
    expect(f.finalView!.answerStartsAt, 1000);
    expect(f.finalView!.participants.first.judged, isFalse);
    expect(f.finalView!.participants.last.bet, 500);
    expect(f.finalView!.participants.last.correct, isFalse);

    for (final (raw, phase) in [
      ('cat_transfer', Phase.catTransfer),
      ('final_themes', Phase.finalThemes),
      ('final_bets', Phase.finalBets),
      ('final_judging', Phase.finalJudging),
      ('final_reveal', Phase.finalReveal),
    ]) {
      expect(Phase.parse(raw), phase);
    }
    final e = GameEvent.fromJson({'kind': 'auction_bid', 'playerId': 'p1', 'amount': 700, 'allIn': true});
    expect(e.kind, GameEventKind.auctionBid);
    expect(e.amount, 700);
    expect(e.allIn, isTrue);
    expect(GameEvent.fromJson({'kind': 'modifier', 'questionId': 3, 'modifier': 'cat'}).modifier, Modifier.cat);
    expect(GameEvent.fromJson({'kind': 'cat_given', 'fromId': 'a', 'toId': 'b'}).toId, 'b');
    expect(GameEvent.fromJson({'kind': 'final_theme_removed', 'playerId': null, 'themeId': 4}).themeId, 4);
  });

  test('parses phases and events', () {
    expect(Phase.parse('round_end'), Phase.roundEnd);
    expect(Phase.parse('nonsense'), Phase.lobby);
    final e = GameEvent.fromJson({'kind': 'judged', 'playerId': 'p_a', 'correct': false, 'delta': -200});
    expect(e.kind, GameEventKind.judged);
    expect(e.correct, isFalse);
    expect(e.delta, -200);
    expect(GameEvent.fromJson({'kind': 'x'}).kind, GameEventKind.unknown);
  });

  test('a question without answerBlocks keeps them null', () {
    final q = QuestionView.fromJson({
      'id': 5,
      'categoryName': 'A',
      'value': 300,
      'blocks': [
        {'type': 'video', 'url': '/v.mp4', 'alt': ''},
      ],
      'answerBlocks': null,
      'comment': null,
    });
    expect(q.answerBlocks, isNull);
    expect(q.blocks.single.type, BlockType.video);
  });
}
