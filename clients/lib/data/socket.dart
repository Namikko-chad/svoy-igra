import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'device.dart';
import 'models.dart';

enum SocketStatus { connecting, online, offline, closed }

/// Close codes (protocol §4).
abstract final class CloseCodes {
  static const invalidToken = 4001;
  static const kicked = 4003;
  static const gameClosed = 4004;
  static const replaced = 4009;
}

/// The game WebSocket (protocol §4): handshake, heartbeat, clock offset,
/// automatic reconnect with backoff 1, 2, 4 … 10 s, latest `state`.
class GameSocket extends ChangeNotifier {
  GameSocket({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  WebSocket? _ws;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  Timer? _watchdog;
  DateTime _lastMessageAt = DateTime.now();
  int _attempt = 0;
  bool _disposed = false;
  int _reqSeq = 0;

  SocketStatus status = SocketStatus.connecting;

  /// Close code that stopped reconnecting (4001 / 4003 / 4004 / 4009), else null.
  int? closeCode;

  GameView? view;
  String? playerId;
  String? pin;

  /// Set after [leave]: no more reconnects.
  bool _left = false;

  /// `serverNow - localNow`, refreshed on every `state` / `welcome`.
  int offsetMs = 0;

  final _events = StreamController<GameEvent>.broadcast();
  final _errors = StreamController<ServerError>.broadcast();

  Stream<GameEvent> get events => _events.stream;
  Stream<ServerError> get errors => _errors.stream;

  /// Current server time in Unix ms.
  int get serverNow => DateTime.now().millisecondsSinceEpoch + offsetMs;

  Uri get _wsUri {
    final u = Uri.parse(baseUrl);
    return u.replace(
      scheme: u.scheme == 'https' ? 'wss' : 'ws',
      path: '/api/ws',
      queryParameters: {'token': token},
    );
  }

  void connect() {
    if (_disposed || _left) return;
    _retry?.cancel();
    closeCode = null;
    _setStatus(SocketStatus.connecting);
    WebSocket.connect(_wsUri.toString()).timeout(const Duration(seconds: 6)).then((ws) {
      if (_disposed) {
        ws.close();
        return;
      }
      _ws = ws;
      _attempt = 0;
      _lastMessageAt = DateTime.now();
      // The server pings every 2 s; silence for 7 s means a dead link.
      _watchdog?.cancel();
      _watchdog = Timer.periodic(const Duration(seconds: 1), (_) {
        if (DateTime.now().difference(_lastMessageAt) > const Duration(seconds: 7)) ws.close();
      });
      void closed([Object? _]) {
        if (identical(_ws, ws)) _onClosed(ws.closeCode);
      }

      _sub?.cancel();
      _sub = ws.listen(_onMessage, onDone: closed, onError: closed, cancelOnError: true);
    }).catchError((Object _) {
      _onClosed(null);
    });
  }

  /// Reconnect right now (after a 4009 or from the UI).
  void reconnectNow() {
    _ws?.close();
    _ws = null;
    _attempt = 0;
    connect();
  }

  void _onClosed(int? code) {
    _ws = null;
    _watchdog?.cancel();
    if (_disposed) return;
    if (_left) {
      _setStatus(SocketStatus.closed);
      return;
    }
    if (code == CloseCodes.invalidToken ||
        code == CloseCodes.kicked ||
        code == CloseCodes.gameClosed ||
        code == CloseCodes.replaced) {
      closeCode = code;
      _setStatus(SocketStatus.closed);
      return;
    }
    _setStatus(SocketStatus.offline);
    final delay = [1, 2, 4, 8, 10][_attempt.clamp(0, 4)];
    _attempt++;
    _retry = Timer(Duration(seconds: delay), connect);
  }

  void _setStatus(SocketStatus s) {
    if (_disposed) return;
    status = s;
    notifyListeners();
  }

  void _onMessage(dynamic raw) {
    if (raw is! String || _disposed) return;
    _lastMessageAt = DateTime.now();
    final Map<String, dynamic> msg;
    try {
      msg = (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    final data = msg['data'] is Map ? (msg['data'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    switch (msg['type']) {
      case 'welcome':
        _syncClock(data['serverNow']);
        playerId = data['playerId'] as String?;
        pin = data['pin'] as String?;
        _send('hello', DeviceHello.data);
        if (status != SocketStatus.online) _setStatus(SocketStatus.online);
      case 'ping':
        _send('pong', {'t': data['t']});
      case 'state':
        _syncClock(data['serverNow']);
        view = GameView.fromJson(data);
        status = SocketStatus.online;
        notifyListeners();
      case 'event':
        _events.add(GameEvent.fromJson(data));
      case 'error':
        _errors.add(ServerError('${data['code'] ?? 'error'}', '${data['message'] ?? ''}', msg['reqId'] as String?));
    }
  }

  void _syncClock(Object? serverNow) {
    if (serverNow is num) offsetMs = serverNow.toInt() - DateTime.now().millisecondsSinceEpoch;
  }

  void _send(String type, Map<String, dynamic> data, [String? reqId]) {
    final ws = _ws;
    if (ws == null || ws.readyState != WebSocket.open) return;
    ws.add(jsonEncode({'type': type, 'data': data, 'reqId': ?reqId}));
  }

  /// Sends a command; returns false when offline (nothing was sent).
  bool command(String type, [Map<String, dynamic> data = const {}]) {
    final ws = _ws;
    if (ws == null || ws.readyState != WebSocket.open) {
      _errors.add(const ServerError('network', ''));
      return false;
    }
    _send(type, data, 'r${++_reqSeq}');
    return true;
  }

  /// Gives the seat up (`leave`) and closes the socket for good.
  Future<void> leave() async {
    _left = true;
    _retry?.cancel();
    final ws = _ws;
    if (ws == null || ws.readyState != WebSocket.open) return;
    _send('leave', const {});
    // The server closes the socket; don't wait for it forever.
    await ws.done.timeout(const Duration(seconds: 2), onTimeout: () => null).catchError((Object _) => null);
    await ws.close();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _retry?.cancel();
    _watchdog?.cancel();
    _ws?.close();
    _events.close();
    _errors.close();
    super.dispose();
  }
}
