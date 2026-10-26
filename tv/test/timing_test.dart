import 'package:flutter_test/flutter_test.dart';
import 'package:svoy_igra_tv/core/utils/backoff.dart';
import 'package:svoy_igra_tv/core/utils/question_timer.dart';
import 'package:svoy_igra_tv/core/utils/server_address.dart';
import 'package:svoy_igra_tv/core/utils/server_clock.dart';

void main() {
  group('ServerClock', () {
    test('offset = serverNow - localNow; countdown = deadline - (local + offset)', () {
      var local = 1000;
      final clock = ServerClock(localNow: () => local);
      clock.sync(51000); // server is 50 s ahead
      expect(clock.offsetMs, 50000);
      expect(clock.now(), 51000);
      local = 3000;
      expect(clock.now(), 53000);
      expect(clock.remaining(60000), 7000);
      expect(clock.remaining(50000), 0);
    });
  });

  group('questionCountdown', () {
    const opened = 100000;
    const readingEnds = opened + 10000;
    const buzzEnds = readingEnds + 15000;

    Countdown? at(int now, {int? buzzStartsAt = readingEnds, int? buzzEndsAt = buzzEnds}) => questionCountdown(
          readingStartsAt: opened,
          readingEndsAt: readingEnds,
          buzzStartsAt: buzzStartsAt,
          buzzEndsAt: buzzEndsAt,
          now: now,
        );

    test('reading window = readingStartsAt → readingEndsAt', () {
      final c = at(opened + 5000)!;
      expect(c.stage, TimerStage.reading);
      expect(c.startsAt, opened);
      expect(c.totalMs, 10000);
      expect(c.fraction(opened + 5000), 0.5);
      expect(c.secondsLeft(opened + 5000), 5);
      expect(c.secondsLeft(readingEnds - 1), 1);
      expect(c.isWarning(opened + 5000), isFalse);
      expect(c.isWarning(readingEnds - 2500), isTrue);
    });

    test('buzz window = buzzStartsAt → buzzEndsAt once reading ends', () {
      final c = at(readingEnds + 1000)!;
      expect(c.stage, TimerStage.buzzing);
      expect(c.startsAt, readingEnds);
      expect(c.endsAt, buzzEnds);
      expect(c.secondsLeft(readingEnds + 1000), 14);
      expect(c.fraction(buzzEnds + 500), 0);
    });

    test('window reopened after a wrong answer starts at buzzStartsAt', () {
      const reopenedAt = readingEnds + 8000;
      final c = at(reopenedAt + 30, buzzStartsAt: reopenedAt, buzzEndsAt: reopenedAt + 15000)!;
      expect(c.stage, TimerStage.buzzing);
      expect(c.startsAt, reopenedAt);
      expect(c.totalMs, 15000);
      expect(c.secondsLeft(reopenedAt + 30), 15);
    });

    test('no deadlines → no bar', () {
      expect(
        questionCountdown(readingStartsAt: null, readingEndsAt: null, buzzStartsAt: null, buzzEndsAt: null, now: 5),
        isNull,
      );
      expect(at(readingEnds + 1, buzzStartsAt: null, buzzEndsAt: null), isNull);
    });
  });

  test('reconnect backoff 1, 2, 4, 8, 10, 10 s', () {
    expect([for (var i = 0; i < 6; i++) reconnectDelay(i).inSeconds], [1, 2, 4, 8, 10, 10]);
  });

  group('ServerAddress', () {
    test('parses manual input with default port', () {
      expect(ServerAddress.parse('192.168.1.10').toString(), 'http://192.168.1.10:3050');
      expect(ServerAddress.parse(' host:8080 ').toString(), 'http://host:8080');
      expect(ServerAddress.parse('http://h:1/x').toString(), 'http://h:1');
      expect(ServerAddress.parse(''), isNull);
      expect(ServerAddress.parse('ftp://h'), isNull);
    });

    test('builds socket and media URLs', () {
      final base = ServerAddress.parse('10.0.0.2:3050')!;
      expect(ServerAddress.socket(base, 'tok').toString(), 'ws://10.0.0.2:3050/api/ws?token=tok');
      expect(ServerAddress.resolve(base, '/api/packs/p/media/a.jpg').toString(),
          'http://10.0.0.2:3050/api/packs/p/media/a.jpg');
      expect(ServerAddress.resolve(base, 'https://x/y.png').toString(), 'https://x/y.png');
    });
  });
}
