/// Compile-time and protocol constants of the TV client.
abstract final class AppConfig {
  /// Port assumed when a manually entered address has none (backend default).
  static const int defaultServerPort = 3050;

  /// UDP port servers listen on for LAN discovery (protocol §7).
  static const int discoveryPort = 3051;

  /// ASCII datagram that asks servers to identify themselves (protocol §7).
  static const String discoveryProbe = 'SVOY_IGRA_DISCOVER';

  /// How long one discovery scan collects replies.
  static const Duration discoveryWindow = Duration(milliseconds: 2500);

  /// Reconnect backoff cap (protocol §4.1: 1 s, 2 s, 4 s … max 10 s).
  static const Duration maxReconnectDelay = Duration(seconds: 10);

  /// Timeout of the `/api/info` probe used to validate a manual address.
  static const Duration infoTimeout = Duration(seconds: 4);

  /// The UI is laid out on this fixed canvas and scaled to the real screen.
  static const double stageWidth = 1920;
  static const double stageHeight = 1080;

  /// `hello.platform` of this client.
  static const String platform = 'android_tv';
}
