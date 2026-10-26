import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:svoy_igra_client/data/models.dart';

const _hostState = '''
{
  "serverNow": 1761400000000,
  "role": "host",
  "game": {"pin": "123456", "title": "Пятница", "link": "http://h:3050/g/123456", "hostTaken": true, "hostConnected": true},
  "phase": "answering",
  "pack": {"id": "pk1", "title": "Пакет"},
  "round": {"index": 0, "name": "Раунд 1", "total": 3},
  "board": [
    {"id": 1, "name": "История", "questions": [
      {"id": 11, "value": 100, "played": true},
      {"id": 12, "value": 200, "played": false}
    ]}
  ],
  "players": [
    {"id": "p_1", "name": "Аня", "score": 300, "connected": true},
    {"id": "p_2", "name": "Боря", "score": -100, "connected": false}
  ],
  "chooserId": "p_1",
  "question": {
    "id": 12, "categoryName": "История", "value": 200,
    "blocks": [{"type": "text", "markdown": "Кто?"}, {"type": "image", "url": "/api/packs/pk1/media/a.jpg", "alt": ""}],
    "answerBlocks": [{"type": "text", "markdown": "Пётр I"}],
    "comment": "Первый император"
  },
  "answeringPlayerId": "p_2",
  "attemptedPlayerIds": ["p_1"],
  "readingEndsAt": null,
  "buzzEndsAt": null,
  "typedAnswer": "петр",
  "lastResult": {"playerId": "p_1", "correct": false, "delta": 0},
  "settings": {"readingSeconds": 10, "buzzSeconds": 15, "wrongPenalty": false, "autoLatencyCompensation": true},
  "me": null
}
''';

const _playerState = '''
{
  "serverNow": 1761400000500, "role": "player", "phase": "question",
  "pack": {"id": "pk1", "title": "Пакет"}, "round": {"index": 1, "name": "Р2", "total": 2},
  "board": [], "players": [{"id": "p_1", "name": "Аня", "score": 0, "connected": true}],
  "chooserId": null,
  "question": {"id": 5, "categoryName": "Кино", "value": 300, "blocks": [], "answerBlocks": null, "comment": null},
  "answeringPlayerId": null, "attemptedPlayerIds": [],
  "readingEndsAt": 1761400010000, "buzzEndsAt": 1761400025000,
  "typedAnswer": null, "lastResult": null, "settings": null,
  "me": {"id": "p_1", "name": "Аня", "score": 0, "canSelect": false, "buzzer": "waiting",
         "buzzOpensAt": 1761400010200, "canType": false}
}
''';

const _adminState = '''
{
  "serverNow": 1, "role": "admin", "phase": "round_end", "pack": {"id": "pk1", "title": "Пакет"},
  "round": {"index": 0, "name": "Р1", "total": 2}, "board": null, "admins": 2,
  "game": {"pin": "654321", "title": "", "link": "", "hostTaken": false, "hostConnected": false},
  "players": [{"id": "p_1", "name": "Аня", "score": 500, "connected": true, "admin": {
    "device": {"platform": "android", "model": "Pixel 8", "os": "Android 15", "appVersion": "1.0.0",
               "userAgent": "ua", "screen": "1080x2400", "ip": "192.168.1.20"},
    "rttMs": 42, "rttAvgMs": 55, "jitterMs": 7, "lastSeenAt": 1761400000000,
    "buzzOffsetMs": 250, "effectiveOffsetMs": 222,
    "stats": {"correct": 3, "wrong": 1, "buzzes": 5, "avgReactionMs": 410, "bestReactionMs": null}
  }}],
  "chooserId": null, "question": null, "answeringPlayerId": null, "attemptedPlayerIds": [],
  "readingEndsAt": null, "buzzEndsAt": null, "typedAnswer": null, "lastResult": null,
  "settings": {"readingSeconds": 12, "buzzSeconds": 20, "wrongPenalty": true, "autoLatencyCompensation": false},
  "me": null
}
''';

Map<String, dynamic> _j(String s) => jsonDecode(s) as Map<String, dynamic>;

void main() {
  test('host GameView', () {
    final v = GameView.fromJson(_j(_hostState));
    expect(v.phase, Phase.answering);
    expect(v.pack!.title, 'Пакет');
    expect(v.round!.total, 3);
    expect(v.board!.single.questions.first.played, isTrue);
    expect(v.players[1].score, -100);
    expect(v.players[1].connected, isFalse);
    expect(v.player('p_2')!.name, 'Боря');
    expect(v.question!.blocks[1].type, BlockType.image);
    expect(v.question!.answerBlocks!.single.markdown, 'Пётр I');
    expect(v.question!.comment, 'Первый император');
    expect(v.attemptedPlayerIds, ['p_1']);
    expect(v.typedAnswer, 'петр');
    expect(v.lastResult!.correct, isFalse);
    expect(v.settings!.autoLatencyCompensation, isTrue);
    expect(v.me, isNull);
    expect(v.game.pin, '123456');
    expect(v.game.hostConnected, isTrue);
    expect(v.admins, isNull);
  });

  test('player GameView', () {
    final v = GameView.fromJson(_j(_playerState));
    expect(v.phase, Phase.question);
    expect(v.question!.answerBlocks, isNull);
    expect(v.settings, isNull);
    expect(v.me!.buzzer, BuzzerState.waiting);
    expect(v.me!.buzzOpensAt, 1761400010200);
    expect(v.readingEndsAt, 1761400010000);
  });

  test('admin GameView', () {
    final v = GameView.fromJson(_j(_adminState));
    expect(v.phase, Phase.roundEnd);
    expect(v.board, isNull);
    expect(v.pack!.id, 'pk1');
    expect(v.round!.total, 2);
    expect(v.admins, 2);
    expect(v.game.hostTaken, isFalse);
    final a = v.players.single.admin!;
    expect(a.device.model, 'Pixel 8');
    expect(a.device.ip, '192.168.1.20');
    expect(a.rttAvgMs, 55);
    expect(a.effectiveOffsetMs, 222);
    expect(a.stats.avgReactionMs, 410);
    expect(a.stats.bestReactionMs, isNull);
    expect(v.settings!.wrongPenalty, isTrue);
  });

  test('pack tree and summary', () {
    final p = Pack.fromJson(_j('''
      {"id":"pk","title":"T","author":"A","description":"","sizeBytes":10,"createdAt":1,"updatedAt":2,
       "rounds":[{"id":1,"position":0,"name":"R","categories":[{"id":2,"roundId":1,"position":0,"name":"C",
         "questions":[{"id":3,"categoryId":2,"position":0,"value":100,"question":"q","answer":"a","comment":"",
           "readingSeconds":null}]}]}],
       "media":[{"name":"a.jpg","mime":"image/jpeg","size":5,"url":"/api/packs/pk/media/a.jpg"}]}'''));
    expect(p.rounds.single.categories.single.questions.single.readingSeconds, isNull);
    expect(p.media.single.mime, 'image/jpeg');
    final s = PackSummary.fromJson(_j('{"id":"pk","title":"T","rounds":2,"questions":20}'));
    expect(s.rounds, 2);
    expect(s.mediaCount, 0);
  });

  test('GameInfo, JoinResult, /auth/me, locked packs', () {
    final r = JoinResult.fromJson(_j('''
      {"token":"t1","role":"player","playerId":"p_1","name":"Аня",
       "game":{"pin":"123456","title":"Т","link":"http://h/g/123456","phase":"board",
               "pack":{"id":"pk","title":"P"},"players":3,"hostTaken":true,"createdAt":5}}'''));
    expect(r.role, Role.player);
    expect(r.playerId, 'p_1');
    expect(r.game.phase, Phase.board);
    expect(r.game.pack!.title, 'P');
    expect(r.game.players, 3);
    expect(r.game.hostTaken, isTrue);
    final me = JoinResult.fromJson(_j('{"role":"admin","game":{"pin":"1","title":"","link":"","phase":"lobby","pack":null,"players":0,"hostTaken":false,"createdAt":1}}'));
    expect(me.token, '');
    expect(me.role, Role.admin);
    expect(me.game.pack, isNull);
    expect(Role.parse('screen'), Role.screen);
    expect(PackSummary.fromJson(_j('{"id":"a","locked":true}')).locked, isTrue);
    expect(Pack.fromJson(_j('{"id":"a"}')).locked, isFalse);
  });

  test('public game list and watch screens carry no PIN or link', () {
    final games = [
      for (final g in jsonDecode('[{"id":"g_abc","pin":null,"link":null,"title":"Пятница","phase":"board",'
          '"pack":null,"players":4,"hostTaken":true,"createdAt":1}]') as List)
        GameInfo.fromJson(g as Map<String, dynamic>),
    ];
    expect(games.single.id, 'g_abc');
    expect(games.single.pin, isNull);
    expect(games.single.link, isNull);
    final watch = JoinResult.fromJson(_j('{"token":"s1","role":"screen","game":{"id":"g_abc","pin":null,"link":null,'
        '"title":"","phase":"lobby","pack":null,"players":0,"hostTaken":false,"createdAt":1}}'));
    expect(watch.role, Role.screen);
    expect(watch.game.pin, isNull);
    final view = GameView.fromJson(_j('{"role":"screen","phase":"lobby","players":[],"attemptedPlayerIds":[],'
        '"game":{"pin":null,"title":"","link":null,"hostTaken":false,"hostConnected":false}}'));
    expect(view.game.pin, isNull);
    expect(view.game.link, isNull);
  });

  test('unknown phase and buzzer fall back safely', () {
    expect(Phase.parse('weird'), Phase.lobby);
    expect(BuzzerState.parse(null), BuzzerState.hidden);
  });
}
