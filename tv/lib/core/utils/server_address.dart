import '../config.dart';

/// Server base URL helpers. A base is `scheme://host:port` with no path.
abstract final class ServerAddress {
  /// Parses what a person typed (`192.168.1.10`, `host:3050`,
  /// `http://host:3050/`) into a base URL. Returns null when it is not an
  /// address. A missing port becomes [AppConfig.defaultServerPort].
  static Uri? parse(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'http://$text';
    final Uri uri;
    try {
      uri = Uri.parse(text);
    } on FormatException {
      return null;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty || uri.host.contains(' ')) return null;
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : AppConfig.defaultServerPort,
    );
  }

  /// WebSocket URL for a token (`/api/ws?token=…`; the token decides game + role).
  static Uri socket(Uri base, String token) => base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: '/api/ws',
        queryParameters: {'token': token},
      );

  /// Resolves a server-relative media URL (`/api/packs/...`) against [base];
  /// absolute `http(s)` URLs pass through.
  static Uri resolve(Uri base, String url) {
    final parsed = Uri.parse(url);
    if (parsed.hasScheme) return parsed;
    return base.resolveUri(parsed);
  }

  /// Short human label: `host:port`.
  static String label(Uri base) => '${base.host}:${base.port}';
}
