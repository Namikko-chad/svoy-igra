import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_info.dart';
import '../models/json.dart';

/// Remembers the last server and, per server, the game the screen joined
/// (PIN + screen token) so an app restart rejoins silently (protocol §1).
class ServerStore {
  ServerStore(this._prefs);

  static const _serverKey = 'server.base';
  static String _sessionKey(Uri base) => 'session.$base';

  final SharedPreferences _prefs;

  static Future<ServerStore> open() async => ServerStore(await SharedPreferences.getInstance());

  Uri? loadServer() {
    final raw = _prefs.getString(_serverKey);
    if (raw == null || raw.isEmpty) return null;
    return Uri.tryParse(raw);
  }

  Future<void> saveServer(Uri base) => _prefs.setString(_serverKey, base.toString());

  GameSession? loadSession(Uri base) {
    final raw = _prefs.getString(_sessionKey(base));
    if (raw == null) return null;
    try {
      return GameSession.fromJson(asJson(jsonDecode(raw)));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSession(Uri base, GameSession session) =>
      _prefs.setString(_sessionKey(base), jsonEncode(session.toJson()));

  Future<void> clearSession(Uri base) => _prefs.remove(_sessionKey(base));
}
