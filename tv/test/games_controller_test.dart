import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:svoy_igra_tv/data/api/games_api.dart';
import 'package:svoy_igra_tv/data/models/game_info.dart';
import 'package:svoy_igra_tv/data/models/game_view.dart';
import 'package:svoy_igra_tv/features/games/games_controller.dart';

import 'support/fake_api.dart';

void main() {
  test('parses GET /api/games: no PINs/links, newest first kept, id-less entries dropped', () {
    final list = GameInfo.listFromJson(jsonDecode('''[
      {"id":"g2","pin":null,"title":"Вечер","link":null,"phase":"question",
       "pack":{"id":"p1","title":"Кино"},"players":4,"hostTaken":true,"createdAt":20},
      {"id":"g1","pin":null,"title":"","link":null,"phase":"lobby",
       "pack":null,"players":0,"hostTaken":false,"createdAt":10},
      {"title":"broken"}
    ]'''));
    expect(list.map((g) => g.id), ['g2', 'g1']);
    expect(list.every((g) => g.pin == null && g.link == null), isTrue);
    expect(list.first.pack!.title, 'Кино');
    expect(list.first.phase, Phase.question);
    expect(list.first.phaseLabel, 'идёт игра');
    expect(list.first.createdAt, 20);
    expect(list.last.pack, isNull);
    expect(list.last.phaseLabel, 'ожидание игроков');
    expect(GameInfo.listFromJson({'not': 'a list'}), isEmpty);
  });

  test('loads on start and refreshes on the interval', () async {
    final api = FakeApi();
    final c = GamesController(api, interval: const Duration(milliseconds: 50))..start();
    await Future<void>.delayed(Duration.zero);
    expect(c.loaded, isTrue);
    expect(c.games.single.id, 'g_123456');
    expect(c.games.single.pin, isNull);

    api.games['654321'] = game('654321');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(api.listCalls, greaterThanOrEqualTo(2));
    expect(c.games.map((g) => g.id), ['g_654321', 'g_123456']);
    c.dispose();
  });

  test('a failed refresh keeps the last list and shows the error', () async {
    final api = FakeApi();
    final c = GamesController(api, interval: const Duration(hours: 1))..start();
    await Future<void>.delayed(Duration.zero);
    api.listError = const ApiError('network', 'x');
    await c.refresh();
    expect(c.games, hasLength(1));
    expect(c.error, 'Сервер не отвечает');
    c.dispose();
  });

  test('selecting a game watches it by public id (never joins by PIN)', () async {
    final api = FakeApi();
    final c = GamesController(api, interval: const Duration(hours: 1), notice: 'Игра закрыта')..start();
    await Future<void>.delayed(Duration.zero);
    final result = await c.watch(c.games.single);
    expect(api.watches, ['g_123456']);
    expect(api.joins, isEmpty);
    expect(result!.token, 'scr_watch_g_123456');
    expect(result.game.pin, isNull);
    expect(c.notice, isNull);
    c.dispose();
  });

  test('a game that vanished → notice and the list is refreshed', () async {
    final api = FakeApi();
    final c = GamesController(api, interval: const Duration(hours: 1))..start();
    await Future<void>.delayed(Duration.zero);
    final listed = c.games.single;
    api.games.clear();
    expect(await c.watch(listed), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(c.notice, 'Игра не найдена — список обновлён');
    expect(c.games, isEmpty);
    c.dispose();
  });
}
