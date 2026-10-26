import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data/api/games_api.dart';
import 'data/device/device_hello.dart';
import 'data/models/game_info.dart';
import 'data/storage/server_store.dart';
import 'data/ws/game_socket.dart';

/// Which screen the app shows.
enum AppStage { connect, games, pin, display }

typedef SocketFactory = GameSocket Function(Uri base, String token);
typedef ApiFactory = GamesApi Function(Uri base);

GameSocket _defaultSocket(Uri base, String token) =>
    GameSocket(base: base, token: token, hello: DeviceHello.load);

/// Top-level flow: server → live games list (or game PIN) → display
/// (protocol §8 "TV app").
///
/// - A saved server with a saved {PIN, token} rejoins straight to the display.
/// - Close code 4001/4003/4004 forgets the token and returns to the games
///   list with [notice] («Игра закрыта» …).
/// - «Сменить игру» / «Сменить сервер» send `leave` first.
class AppController extends ChangeNotifier {
  AppController(
    this._store, {
    SocketFactory socketFactory = _defaultSocket,
    ApiFactory apiFactory = HttpGamesApi.new,
  })  : _socketFactory = socketFactory,
        _apiFactory = apiFactory,
        _server = _store.loadServer();

  final ServerStore _store;
  final SocketFactory _socketFactory;
  final ApiFactory _apiFactory;

  Uri? _server;
  GameSession? _session;
  GameSocket? _socket;
  bool _changingServer = false;
  bool _enteringPin = false;
  String? _notice;

  AppStage get stage {
    if (_socket != null) return AppStage.display;
    if (_server == null || _changingServer) return AppStage.connect;
    return _enteringPin ? AppStage.pin : AppStage.games;
  }

  /// The live session, or null outside the display.
  GameSocket? get socket => _socket;

  Uri? get server => _server;
  GameSession? get session => _session;

  /// Set when the person chose "change server": the connect screen then
  /// never auto-connects, and Back returns to this server.
  bool get isChangingServer => _changingServer;

  /// Why the game choice is shown again («Игра закрыта» …); null normally.
  String? get notice => _notice;

  /// REST client for the current server (games list, PIN lookup, join).
  GamesApi get api => _apiFactory(_server!);

  /// On start: rejoin the saved game of the saved server, if any.
  void boot() {
    final server = _server;
    if (server == null) return;
    final session = _store.loadSession(server);
    if (session != null) _open(session);
  }

  /// A server was chosen on the connect screen.
  Future<void> chooseServer(Uri base) async {
    _changingServer = false;
    _enteringPin = false;
    _notice = null;
    _server = base;
    await _store.saveServer(base);
    final session = _store.loadSession(base);
    if (session != null) {
      _open(session);
    } else {
      notifyListeners();
    }
  }

  /// Back from the connect screen to the server we came from.
  bool returnToServer() {
    if (_server == null) return false;
    _changingServer = false;
    _enteringPin = false;
    final session = _store.loadSession(_server!);
    if (session != null) {
      _open(session);
    } else {
      notifyListeners();
    }
    return true;
  }

  /// «Ввести PIN» on the games list.
  void enterPin() {
    _enteringPin = true;
    notifyListeners();
  }

  /// Back from PIN entry to the games list.
  void backToGames() {
    _enteringPin = false;
    notifyListeners();
  }

  /// The games list or the PIN screen joined a game.
  Future<void> joined(JoinResult result) async {
    final session = GameSession(
      token: result.token,
      gameId: result.game.id,
      pin: result.game.pin,
      title: result.game.title,
    );
    await _store.saveSession(_server!, session);
    _notice = null;
    _enteringPin = false;
    _open(session);
  }

  /// «Сменить игру»: leave the game, back to the games list.
  Future<void> changeGame() async {
    _leave();
    await _forgetSession();
    _enteringPin = false;
    notifyListeners();
  }

  /// «Сменить сервер» (also Back on the PIN screen): leave, pick another server.
  Future<void> changeServer() async {
    _leave();
    await _forgetSession();
    _changingServer = true;
    _enteringPin = false;
    _notice = null;
    notifyListeners();
  }

  void _open(GameSession session) {
    _closeSocket();
    _session = session;
    final socket = _socketFactory(_server!, session.token)..addListener(_onSocket);
    _socket = socket;
    socket.start();
    notifyListeners();
  }

  void _onSocket() {
    final socket = _socket;
    if (socket == null || socket.status != SocketStatus.ended) return;
    final code = socket.closeCode;
    _notice = code == 4004 ? 'Игра закрыта' : 'Экран отключён от игры — выберите игру снова';
    _enteringPin = false;
    _closeSocket();
    unawaited(_forgetSession().then((_) => notifyListeners()));
  }

  void _leave() {
    _socket?.leave();
    _closeSocket();
  }

  void _closeSocket() {
    final socket = _socket;
    _socket = null;
    if (socket == null) return;
    socket.removeListener(_onSocket);
    // Let the display finish its exit transition before the notifier dies.
    Future<void>.delayed(const Duration(seconds: 1), socket.dispose);
  }

  Future<void> _forgetSession() async {
    _session = null;
    final server = _server;
    if (server != null) await _store.clearSession(server);
  }

  @override
  void dispose() {
    _socket?.dispose();
    super.dispose();
  }
}
