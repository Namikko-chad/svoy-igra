import 'package:flutter/foundation.dart';

import '../../data/api/games_api.dart';
import '../../data/models/game_info.dart';

enum PinStatus { entering, looking, found, joining }

/// Game PIN entry: 6 digits → `GET /api/games/{pin}` → confirm →
/// `POST /api/games/{pin}/join {role:"screen"}`. UI-free, so it is unit-tested.
class PinController extends ChangeNotifier {
  PinController(this._api, {this.message});

  static const length = 6;

  final GamesApi _api;

  String _digits = '';
  PinStatus _status = PinStatus.entering;
  GameInfo? _game;

  /// Error or notice under the PIN («Игра не найдена», «Игра закрыта» …).
  String? message;

  String get digits => _digits;
  PinStatus get status => _status;
  GameInfo? get game => _game;
  bool get busy => _status == PinStatus.looking || _status == PinStatus.joining;

  /// Types one digit; the 6th starts the lookup.
  void addDigit(int d) {
    if (busy || d < 0 || d > 9 || _digits.length >= length) return;
    _digits += '$d';
    _resetResult();
    notifyListeners();
    if (_digits.length == length) lookup();
  }

  void backspace() {
    if (busy || _digits.isEmpty) return;
    _digits = _digits.substring(0, _digits.length - 1);
    _resetResult();
    notifyListeners();
  }

  void clear() {
    if (busy) return;
    _digits = '';
    _resetResult();
    notifyListeners();
  }

  void _resetResult() {
    _status = PinStatus.entering;
    _game = null;
    message = null;
  }

  Future<void> lookup() async {
    if (_digits.length != length || busy) return;
    final pin = _digits;
    _status = PinStatus.looking;
    message = null;
    notifyListeners();
    try {
      final game = await _api.getGame(pin);
      if (pin != _digits) return;
      _game = game;
      _status = PinStatus.found;
    } on ApiError catch (e) {
      _status = PinStatus.entering;
      message = _describe(e);
    }
    notifyListeners();
  }

  /// Joins the found game as `screen`; null (with [message]) on failure.
  Future<JoinResult?> join() async {
    if (_status != PinStatus.found) return null;
    _status = PinStatus.joining;
    message = null;
    notifyListeners();
    try {
      final result = await _api.joinAsScreen(_digits);
      _status = PinStatus.found;
      notifyListeners();
      return result;
    } on ApiError catch (e) {
      _status = e.code == 'game_not_found' ? PinStatus.entering : PinStatus.found;
      if (e.code == 'game_not_found') _game = null;
      message = _describe(e);
      notifyListeners();
      return null;
    }
  }

  static String _describe(ApiError e) => switch (e.code) {
        'game_not_found' => 'Игра не найдена',
        'network' => 'Сервер не отвечает',
        _ => e.message,
      };
}
