import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/api/games_api.dart';
import '../../data/models/game_info.dart';

/// The live-games list (`GET /api/games`, refreshed every [interval]; no PINs)
/// and watching one as `screen` by its public id. UI-free, so it is unit-tested.
class GamesController extends ChangeNotifier {
  GamesController(this._api, {this.interval = const Duration(seconds: 5), this.notice});

  final GamesApi _api;
  final Duration interval;

  List<GameInfo> _games = const [];
  bool _loaded = false;
  String? _error;
  String? _joiningId;
  Timer? _timer;
  bool _disposed = false;

  /// One-off notice (game closed, game vanished …); cleared by a successful join.
  String? notice;

  List<GameInfo> get games => _games;

  /// False until the first answer (success or failure) arrives.
  bool get loaded => _loaded;

  /// Why the last refresh failed; the previous list stays shown.
  String? get error => _error;

  /// The id of the game being joined right now, if any.
  String? get joiningId => _joiningId;

  void start() {
    refresh();
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => refresh());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> refresh() async {
    try {
      final games = await _api.listGames();
      if (_disposed) return;
      _games = games;
      _error = null;
    } on ApiError catch (e) {
      if (_disposed) return;
      _error = e.code == 'network' ? 'Сервер не отвечает' : e.message;
    }
    _loaded = true;
    notifyListeners();
  }

  /// Watches [game] as `screen` (`POST /api/games/{id}/watch`); null (with
  /// [notice]) on failure.
  Future<JoinResult?> watch(GameInfo game) async {
    if (_joiningId != null) return null;
    _joiningId = game.id;
    notifyListeners();
    try {
      final result = await _api.watch(game.id);
      notice = null;
      return result;
    } on ApiError catch (e) {
      notice = switch (e.code) {
        'game_not_found' => 'Игра не найдена — список обновлён',
        'network' => 'Сервер не отвечает',
        _ => e.message,
      };
      if (e.code == 'game_not_found') unawaited(refresh());
      return null;
    } finally {
      _joiningId = null;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
