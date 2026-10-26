import 'game_view.dart';
import 'json.dart';

/// `GameInfo` (protocol §2.3) from `GET /api/games`, `GET /api/games/{pin}`
/// and join/watch results.
class GameInfo {
  const GameInfo({
    required this.id,
    required this.pin,
    required this.title,
    required this.link,
    required this.phase,
    required this.pack,
    required this.players,
    required this.hostTaken,
    this.createdAt = 0,
  });

  /// Public id; what `POST /api/games/{id}/watch` takes.
  final String id;

  /// 6-digit PIN — null in the public list and for watch screens.
  final String? pin;
  final String title;

  /// Share link (§8) — null exactly when [pin] is.
  final String? link;
  final Phase phase;
  final PackRef? pack;
  final int players;
  final bool hostTaken;
  final int createdAt;

  /// `GET /api/games`: drops entries without an id; keeps the server's order
  /// (newest first).
  static List<GameInfo> listFromJson(Object? v) =>
      asList(v, (e) => GameInfo.fromJson(asJson(e))).where((g) => g.id.isNotEmpty).toList();

  /// Phase in Russian for the game list / card.
  String get phaseLabel => switch (phase) {
        Phase.lobby => 'ожидание игроков',
        Phase.roundEnd => 'перерыв между раундами',
        Phase.finished => 'игра окончена',
        _ => 'идёт игра',
      };

  factory GameInfo.fromJson(Json j) => GameInfo(
        id: asString(j['id']),
        pin: asNonEmptyOrNull(j['pin']),
        title: asString(j['title']),
        link: asNonEmptyOrNull(j['link']),
        phase: Phase.parse(asString(j['phase'])),
        pack: j['pack'] is Map ? PackRef.fromJson(asJson(j['pack'])) : null,
        players: asInt(j['players']),
        hostTaken: asBool(j['hostTaken']),
        createdAt: asInt(j['createdAt']),
      );
}

/// `POST /api/games/{pin}/join` result (protocol §2.3 `JoinResult`).
class JoinResult {
  const JoinResult({required this.token, required this.role, required this.game});

  final String token;
  final String role;
  final GameInfo game;

  factory JoinResult.fromJson(Json j) => JoinResult(
        token: asString(j['token']),
        role: asString(j['role']),
        game: GameInfo.fromJson(asJson(j['game'])),
      );
}

/// What the TV remembers per server to rejoin silently after a restart: the
/// screen token plus the game's public id and, when joined by PIN, the PIN.
class GameSession {
  const GameSession({required this.token, this.gameId = '', this.pin, this.title = ''});

  final String token;
  final String gameId;

  /// Null for a screen that watches a game picked from the list.
  final String? pin;
  final String title;

  Json toJson() => {'token': token, 'gameId': gameId, 'pin': pin, 'title': title};

  static GameSession? fromJson(Json j) {
    final token = asString(j['token']);
    if (token.isEmpty) return null;
    return GameSession(
      token: token,
      gameId: asString(j['gameId']),
      pin: asNonEmptyOrNull(j['pin']),
      title: asString(j['title']),
    );
  }
}
