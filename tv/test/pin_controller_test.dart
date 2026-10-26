import 'package:flutter_test/flutter_test.dart';
import 'package:svoy_igra_tv/features/pin/pin_controller.dart';

import 'support/fake_api.dart';

void main() {
  late FakeApi api;
  late PinController pin;

  setUp(() {
    api = FakeApi();
    pin = PinController(api);
  });

  Future<void> type(String digits) async {
    for (final c in digits.split('')) {
      pin.addDigit(int.parse(c));
    }
    await Future<void>.delayed(Duration.zero);
  }

  test('the 6th digit looks the game up; join returns the screen token', () async {
    await type('12345');
    expect(api.lookups, isEmpty);
    await type('6');
    expect(api.lookups, ['123456']);
    expect(pin.status, PinStatus.found);
    expect(pin.game!.title, 'Пятница');

    final result = await pin.join();
    expect(api.joins, ['123456']);
    expect(result!.token, 'scr_123456');
  });

  test('unknown PIN → «Игра не найдена», no join possible', () async {
    await type('000000');
    expect(pin.status, PinStatus.entering);
    expect(pin.message, 'Игра не найдена');
    expect(await pin.join(), isNull);
    expect(api.joins, isEmpty);
  });

  test('editing resets the result; extra digits are ignored', () async {
    await type('1234567');
    expect(pin.digits, '123456');
    pin.backspace();
    expect(pin.digits, '12345');
    expect(pin.game, isNull);
    expect(pin.status, PinStatus.entering);
    pin.clear();
    expect(pin.digits, isEmpty);
  });

  test('the game disappearing between lookup and join is reported', () async {
    await type('123456');
    api.games.clear();
    expect(await pin.join(), isNull);
    expect(pin.message, 'Игра не найдена');
    expect(pin.game, isNull);
  });

  test('an initial message (e.g. «Игра закрыта») is shown until typing', () async {
    pin = PinController(api, message: 'Игра закрыта');
    expect(pin.message, 'Игра закрыта');
    await type('1');
    expect(pin.message, isNull);
  });
}
