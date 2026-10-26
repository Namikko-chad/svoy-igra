import 'package:flutter_test/flutter_test.dart';
import 'package:svoy_igra_tv/data/ws/game_socket.dart';

import 'support/fake_channel.dart';

void main() {
  late List<FakeChannel> channels;
  late List<Uri> urls;

  GameSocket socket() => GameSocket(
        base: Uri.parse('http://10.0.0.2:3050'),
        token: 'scr_abc',
        hello: () async => {'platform': 'android_tv'},
        connector: (u) {
          urls.add(u);
          final c = FakeChannel();
          channels.add(c);
          return c;
        },
      )..start();

  setUp(() {
    channels = [];
    urls = [];
  });

  test('connects with the token; welcome → hello, ping → immediate pong, state → view', () async {
    final s = socket();
    expect(urls.single.toString(), 'ws://10.0.0.2:3050/api/ws?token=scr_abc');

    s.handleFrame('{"type":"welcome","data":{"role":"screen","pin":"123456","serverNow":5000}}');
    await Future<void>.delayed(Duration.zero);
    expect(s.status, SocketStatus.connected);
    final sent = channels.single.sink.sent;
    expect(sent.first, {
      'type': 'hello',
      'data': {'platform': 'android_tv'},
    });

    s.handleFrame('{"type":"ping","data":{"t":123}}');
    expect(sent.last, {
      'type': 'pong',
      'data': {'t': 123},
    });

    s.handleFrame('{"type":"state","data":{"serverNow":9000,"phase":"board","players":[],'
        '"game":{"pin":"123456","title":"T","link":"http://quiz.lan/g/123456"}}}');
    expect(s.view!.serverNow, 9000);
    expect(s.view!.game.link, 'http://quiz.lan/g/123456');
    expect((s.clock.now() - 9000).abs() < 1000, isTrue);
    s.dispose();
  });

  test('4004 (game closed) ends the session without reconnecting', () async {
    final s = socket();
    await channels.single.serverClose(4004);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(s.status, SocketStatus.ended);
    expect(s.closeCode, 4004);
    expect(channels, hasLength(1));
    s.dispose();
  });

  test('a plain drop reconnects with the same token after 1 s', () async {
    final s = socket();
    await channels.single.serverClose(1006);
    await Future<void>.delayed(Duration.zero);
    expect(s.status, SocketStatus.offline);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(channels, hasLength(2));
    expect(urls.last.queryParameters['token'], 'scr_abc');
    s.dispose();
  });

  test('leave sends `leave` and stops', () async {
    final s = socket();
    s.leave();
    expect(channels.single.sink.sent.single, {'type': 'leave', 'data': <String, dynamic>{}});
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(channels, hasLength(1));
    s.dispose();
  });
}
