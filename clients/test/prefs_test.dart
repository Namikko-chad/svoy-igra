import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svoy_igra_client/core/prefs.dart';
import 'package:svoy_igra_client/data/models.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
  });

  const base = 'http://192.168.1.10:3050';

  test('seats are keyed by server + PIN (or game id) + role', () async {
    const player = GameSeat(token: 'p', role: Role.player, pin: '123456', gameId: 'g1', name: 'Аня');
    const host = GameSeat(token: 'h', role: Role.host, pin: '123456', gameId: 'g1');
    const watch = GameSeat(token: 's', role: Role.screen, gameId: 'g2', title: 'Пятница');
    await Prefs.instance.saveSeat(base, player);
    await Prefs.instance.saveSeat(base, host);
    await Prefs.instance.saveSeat(base, watch);
    expect(watch.key, 'id:g2');
    expect(player.key, '123456');
    expect(Prefs.instance.seats(base).map((s) => s.token), ['s', 'h', 'p']);
    expect(Prefs.instance.seatsForGame(base, '123456').length, 2);
    expect(Prefs.instance.seats('http://other:3050'), isEmpty);

    // Same game + role replaces the old token.
    await Prefs.instance.saveSeat(base, const GameSeat(token: 'p2', role: Role.player, pin: '123456', name: 'Боря'));
    expect(Prefs.instance.seatsForGame(base, '123456').firstWhere((s) => s.role == Role.player).token, 'p2');

    await Prefs.instance.removeSeat(base, watch.key, Role.screen);
    expect(Prefs.instance.seats(base).any((s) => s.role == Role.screen), isFalse);
    final restored = Prefs.instance.seats(base).firstWhere((s) => s.role == Role.player);
    expect(restored.name, 'Боря');
    expect(restored.label, 'Игрок «Боря»');
  });

  test('a watch seat round-trips without a PIN', () async {
    final seat = GameSeat.fromJoin(JoinResult.fromJson({
      'token': 's', 'role': 'screen',
      'game': {'id': 'g9', 'pin': null, 'link': null, 'title': 'T', 'phase': 'lobby', 'players': 0, 'hostTaken': false, 'createdAt': 1},
    }));
    await Prefs.instance.saveSeat(base, seat);
    final back = Prefs.instance.seats(base).single;
    expect(back.pin, isNull);
    expect(back.gameId, 'g9');
    expect(back.key, 'id:g9');
  });
}
