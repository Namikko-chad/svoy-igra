import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';

/// A stored token: one role in one game on one server.
class GameSeat {
  const GameSeat({
    required this.token,
    required this.role,
    this.pin,
    this.gameId,
    this.title = '',
    this.playerId,
    this.name,
  });

  final String token;
  final Role role;

  /// Game PIN; null for a screen watching from the public list.
  final String? pin;

  /// Public game id (always known for seats saved by this version).
  final String? gameId;
  final String title;
  final String? playerId;
  final String? name;

  factory GameSeat.fromJoin(JoinResult r) => GameSeat(
        token: r.token,
        role: r.role,
        pin: r.game.pin,
        gameId: r.game.id.isEmpty ? null : r.game.id,
        title: r.game.title,
        playerId: r.playerId,
        name: r.name,
      );

  Map<String, dynamic> toJson() => {
        'token': token,
        'role': role.name,
        'pin': ?pin,
        'gameId': ?gameId,
        'title': title,
        'playerId': ?playerId,
        'name': ?name,
      };

  static GameSeat? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final token = raw['token'];
    final pin = raw['pin'] is String ? raw['pin'] as String : null;
    final gameId = raw['gameId'] is String ? raw['gameId'] as String : null;
    if (token is! String || (pin == null && gameId == null)) return null;
    return GameSeat(
      token: token,
      role: Role.parse(raw['role']),
      pin: pin,
      gameId: gameId,
      title: raw['title'] is String ? raw['title'] as String : '',
      playerId: raw['playerId'] as String?,
      name: raw['name'] as String?,
    );
  }

  /// Identity of the game in storage: the PIN, or `id:<gameId>` for watch seats.
  String get key => pin ?? 'id:$gameId';

  /// «Продолжить как …» label.
  String get label => role == Role.player && name != null ? '${role.label} «$name»' : role.label;
}

/// Small persistent settings: last server, recent servers and tokens per server.
class Prefs {
  Prefs._(this._p);

  final SharedPreferences _p;

  static late Prefs instance;

  static Future<void> init() async {
    instance = Prefs._(await SharedPreferences.getInstance());
  }

  static const _lastServer = 'lastServer';
  static const _recent = 'recentServers';

  String? get lastServer => _p.getString(_lastServer);

  List<String> get recentServers => _p.getStringList(_recent) ?? const [];

  Future<void> rememberServer(String baseUrl) async {
    await _p.setString(_lastServer, baseUrl);
    final list = [baseUrl, ...recentServers.where((s) => s != baseUrl)].take(5).toList();
    await _p.setStringList(_recent, list);
  }

  Future<void> forgetServer(String baseUrl) async {
    await _p.setStringList(_recent, recentServers.where((s) => s != baseUrl).toList());
    if (lastServer == baseUrl) await _p.remove(_lastServer);
  }

  /// Seats on [baseUrl], newest first.
  List<GameSeat> seats(String baseUrl) {
    final raw = _p.getString('seats:$baseUrl');
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list.map(GameSeat.tryParse).whereType<GameSeat>().toList();
    } catch (_) {
      return const [];
    }
  }

  List<GameSeat> seatsForGame(String baseUrl, String pin) => seats(baseUrl).where((s) => s.pin == pin).toList();

  Future<void> saveSeat(String baseUrl, GameSeat seat) async {
    final list = [
      seat,
      ...seats(baseUrl).where((s) => !(s.key == seat.key && s.role == seat.role)),
    ].take(20).map((s) => s.toJson()).toList();
    await _p.setString('seats:$baseUrl', jsonEncode(list));
  }

  /// [key] is [GameSeat.key].
  Future<void> removeSeat(String baseUrl, String key, Role role) async {
    final list = seats(baseUrl).where((s) => !(s.key == key && s.role == role)).map((s) => s.toJson()).toList();
    await _p.setString('seats:$baseUrl', jsonEncode(list));
  }
}
