import '../config.dart';

/// Reconnect delay for the n-th consecutive failed attempt (0-based):
/// 1 s, 2 s, 4 s, 8 s, then 10 s forever (protocol §4.1).
Duration reconnectDelay(int attempt) {
  final capMs = AppConfig.maxReconnectDelay.inMilliseconds;
  if (attempt >= 4) return AppConfig.maxReconnectDelay;
  final ms = 1000 << (attempt < 0 ? 0 : attempt);
  return Duration(milliseconds: ms > capMs ? capMs : ms);
}
