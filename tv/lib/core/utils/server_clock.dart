/// Server clock estimate (protocol §4.1): `offset = serverNow - localNow` on
/// every `state`, and countdowns are `deadline - (localNow + offset)`.
class ServerClock {
  ServerClock({int Function()? localNow})
      : _localNow = localNow ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int Function() _localNow;
  int _offsetMs = 0;

  int get offsetMs => _offsetMs;

  /// Re-anchors the clock on a `serverNow` received just now.
  void sync(int serverNow) => _offsetMs = serverNow - _localNow();

  /// Current server time, Unix ms.
  int now() => _localNow() + _offsetMs;

  /// Milliseconds left until [deadline] (server time); never negative.
  int remaining(int deadline) {
    final left = deadline - now();
    return left < 0 ? 0 : left;
  }
}
