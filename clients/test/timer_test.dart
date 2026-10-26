import 'package:flutter_test/flutter_test.dart';
import 'package:svoy_igra_client/data/models.dart';
import 'package:svoy_igra_client/features/game/timer_bar.dart';

GameView _view(Map<String, dynamic> extra) => GameView.fromJson({
      'serverNow': 0, 'role': 'player', 'phase': 'question', 'players': <dynamic>[], 'attemptedPlayerIds': <dynamic>[],
      ...extra,
    });

void main() {
  test('timerFraction', () {
    expect(timerFraction(1000, 11000, 1000), 1.0);
    expect(timerFraction(1000, 11000, 6000), 0.5);
    expect(timerFraction(1000, 11000, 12000), 0.0);
    expect(timerFraction(1000, 11000, 0), 1.0);
    expect(timerFraction(5000, 5000, 5000), 0.0);
  });

  test('reading span, then buzz window', () {
    final v = _view({'readingStartsAt': 1000, 'readingEndsAt': 11000, 'buzzStartsAt': 11000, 'buzzEndsAt': 26000});
    final r = TimerSpan.at(v, 3500)!;
    expect(r.kind, TimerKind.reading);
    expect((r.start, r.end), (1000, 11000));
    expect(timerFraction(r.start, r.end, 3500), 0.75);
    final b = TimerSpan.at(v, 14000)!;
    expect(b.kind, TimerKind.buzz);
    expect((b.start, b.end), (11000, 26000));
    expect(timerFraction(b.start, b.end, 14000), 0.8);
  });

  test('reopened window after a wrong answer starts at buzzStartsAt', () {
    final v = _view({'readingStartsAt': 1000, 'readingEndsAt': 11000, 'buzzStartsAt': 40000, 'buzzEndsAt': 55000});
    final s = TimerSpan.at(v, 47500)!;
    expect(s.kind, TimerKind.buzz);
    expect(timerFraction(s.start, s.end, 47500), 0.5);
  });

  test('no timer outside phase question', () {
    final v = _view({'phase': 'answering', 'readingStartsAt': 1, 'readingEndsAt': 2, 'buzzStartsAt': 2, 'buzzEndsAt': 3});
    expect(v.readingStartsAt, 1);
    expect(v.buzzStartsAt, 2);
    expect(TimerSpan.at(v, 1), isNull);
  });

  test('server info webUrl', () {
    expect(ServerInfo.fromJson({'name': 'x', 'version': '1', 'serverNow': 1, 'webUrl': 'http://a'}).webUrl, 'http://a');
    expect(ServerInfo.fromJson({'name': 'x', 'version': '1', 'serverNow': 1, 'webUrl': null}).webUrl, isNull);
  });

  test('final answer bar spans answerStartsAt → answerEndsAt', () {
    // 60 s window, 15 s in → 75 % left.
    expect(timerFraction(100000, 160000, 115000), 0.75);
  });
}
