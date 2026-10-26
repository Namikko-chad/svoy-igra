import 'package:svoy_igra_tv/data/api/games_api.dart';
import 'package:svoy_igra_tv/data/models/game_info.dart';

/// A game as `GET /api/games/{pin}` / join return it (PIN and link known).
GameInfo game(String pin) => GameInfo.fromJson({
      'id': 'g_$pin',
      'pin': pin,
      'title': 'Пятница',
      'link': 'http://quiz.lan/g/$pin',
      'phase': 'lobby',
      'pack': {'id': 'p', 'title': 'Пакет'},
      'players': 3,
      'hostTaken': false,
    });

/// The same game as the public list and `watch` show it: no PIN, no link.
GameInfo hidden(GameInfo g) => GameInfo(
      id: g.id,
      pin: null,
      title: g.title,
      link: null,
      phase: g.phase,
      pack: g.pack,
      players: g.players,
      hostTaken: g.hostTaken,
    );

class FakeApi implements GamesApi {
  final games = <String, GameInfo>{'123456': game('123456')};
  final lookups = <String>[];
  int listCalls = 0;
  ApiError? listError;

  @override
  Future<List<GameInfo>> listGames() async {
    listCalls++;
    if (listError != null) throw listError!;
    return games.values.map(hidden).toList().reversed.toList();
  }

  final joins = <String>[];
  final watches = <String>[];

  @override
  Future<JoinResult> watch(String gameId) async {
    watches.add(gameId);
    final g = games.values.where((g) => g.id == gameId).firstOrNull;
    if (g == null) throw const ApiError('game_not_found', 'game not found', status: 404);
    return JoinResult(token: 'scr_watch_$gameId', role: 'screen', game: hidden(g));
  }

  @override
  Future<GameInfo> getGame(String pin) async {
    lookups.add(pin);
    final g = games[pin];
    if (g == null) throw const ApiError('game_not_found', 'game not found', status: 404);
    return g;
  }

  @override
  Future<JoinResult> joinAsScreen(String pin) async {
    joins.add(pin);
    final g = games[pin];
    if (g == null) throw const ApiError('game_not_found', 'game not found', status: 404);
    return JoinResult(token: 'scr_$pin', role: 'screen', game: g);
  }
}

