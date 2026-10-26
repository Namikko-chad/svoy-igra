/// A link that opens the role step of a game (protocol §8).
class GameLink {
  const GameLink({required this.server, required this.pin});

  /// Server base URL without a trailing slash.
  final String server;
  final String pin;

  @override
  bool operator ==(Object other) => other is GameLink && other.server == server && other.pin == pin;

  @override
  int get hashCode => Object.hash(server, pin);

  @override
  String toString() => 'GameLink($server, $pin)';
}

final _pinRe = RegExp(r'^\d{6}$');

/// Parses `svoyigra://join?server=<base>&pin=<PIN>` and
/// `http(s)://<host>/g/<PIN>` (the server base is the link's origin).
GameLink? parseGameLink(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'svoyigra') {
    if (uri.host != 'join') return null;
    final pin = uri.queryParameters['pin']?.trim() ?? '';
    final server = _origin(Uri.tryParse(uri.queryParameters['server']?.trim() ?? ''));
    if (server == null || !_pinRe.hasMatch(pin)) return null;
    return GameLink(server: server, pin: pin);
  }
  if (scheme == 'http' || scheme == 'https') {
    final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (seg.length != 2 || seg[0] != 'g' || !_pinRe.hasMatch(seg[1])) return null;
    final server = _origin(uri);
    return server == null ? null : GameLink(server: server, pin: seg[1]);
  }
  return null;
}

/// `scheme://host[:port]` of an http(s) URL.
String? _origin(Uri? u) {
  if (u == null || u.host.isEmpty) return null;
  final scheme = u.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  final host = u.host.contains(':') ? '[${u.host}]' : u.host;
  return u.hasPort ? '$scheme://$host:${u.port}' : '$scheme://$host';
}
