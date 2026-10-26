import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svoy_igra_tv/app_controller.dart';
import 'package:svoy_igra_tv/data/models/game_info.dart';
import 'package:svoy_igra_tv/data/storage/server_store.dart';
import 'package:svoy_igra_tv/data/ws/game_socket.dart';

import 'support/fake_api.dart';
import 'support/fake_channel.dart';

void main() {
  final server = Uri.parse('http://10.0.0.2:3050');
  late List<FakeChannel> channels;
  late List<String> tokens;

  Future<(AppController, ServerStore)> make(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final store = await ServerStore.open();
    final app = AppController(
      store,
      apiFactory: (_) => FakeApi(),
      socketFactory: (base, token) {
        tokens.add(token);
        return GameSocket(
          base: base,
          token: token,
          hello: () async => {},
          connector: (_) {
            final c = FakeChannel();
            channels.add(c);
            return c;
          },
        );
      },
    );
    return (app, store);
  }

  setUp(() {
    channels = [];
    tokens = [];
  });

  test('no server → connect; server without a game → games list; «Ввести PIN» ↔ list', () async {
    var (app, _) = await make({});
    app.boot();
    expect(app.stage, AppStage.connect);

    (app, _) = await make({'server.base': '$server'});
    app.boot();
    expect(app.stage, AppStage.games);
    app.enterPin();
    expect(app.stage, AppStage.pin);
    app.backToGames();
    expect(app.stage, AppStage.games);
  });

  test('restart with a saved token reconnects straight to the display', () async {
    final (app, _) = await make({
      'server.base': '$server',
      'session.$server': '{"pin":"123456","token":"scr_saved","title":"T"}',
    });
    app.boot();
    expect(app.stage, AppStage.display);
    expect(tokens, ['scr_saved']);
  });

  test('watching from the list saves {gameId, token} without a PIN', () async {
    final (app, store) = await make({'server.base': '$server'});
    app.boot();
    await app.joined(JoinResult(token: 'scr_w', role: 'screen', game: hidden(game('123456'))));
    final saved = store.loadSession(server)!;
    expect(saved.token, 'scr_w');
    expect(saved.gameId, 'g_123456');
    expect(saved.pin, isNull);
    expect(tokens, ['scr_w']);
  });

  test('joining by PIN saves {pin, token} for the server', () async {
    final (app, store) = await make({'server.base': '$server'});
    app.boot();
    await app.joined(JoinResult(token: 'scr_new', role: 'screen', game: game('123456')));
    expect(app.stage, AppStage.display);
    expect(store.loadSession(server)!.token, 'scr_new');
    expect(store.loadSession(server)!.pin, '123456');
  });

  for (final (code, message) in [(4004, 'Игра закрыта'), (4001, 'Экран отключён от игры — выберите игру снова')]) {
    test('close $code forgets the token and returns to the games list', () async {
      final (app, store) = await make({
        'server.base': '$server',
        'session.$server': '{"pin":"123456","token":"scr_saved"}',
      });
      app.boot();
      await channels.single.serverClose(code);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(app.stage, AppStage.games);
      expect(app.notice, message);
      expect(store.loadSession(server), isNull);
      expect(channels, hasLength(1));
    });
  }

  test('«Сменить игру» sends leave and forgets the token; «Сменить сервер» opens connect', () async {
    final (app, store) = await make({
      'server.base': '$server',
      'session.$server': '{"pin":"123456","token":"scr_saved"}',
    });
    app.boot();
    final channel = channels.single;
    await app.changeGame();
    expect(channel.sink.sent.last['type'], 'leave');
    expect(app.stage, AppStage.games);
    expect(store.loadSession(server), isNull);

    await app.changeServer();
    expect(app.stage, AppStage.connect);
    expect(app.isChangingServer, isTrue);
    expect(app.returnToServer(), isTrue);
    expect(app.stage, AppStage.games);
  });
}
