import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/utils/backoff.dart';
import '../../core/utils/server_address.dart';
import '../../core/utils/server_clock.dart';
import '../models/game_event.dart';
import '../models/game_view.dart';
import '../models/json.dart';

enum SocketStatus {
  connecting,
  connected,
  offline,

  /// The server ended this session for good (close code 4001/4003/4004):
  /// no more reconnects; see [GameSocket.closeCode].
  ended,
}

/// Close codes after which reconnecting with the same token is pointless.
const terminalCloseCodes = {4001, 4003, 4004};

typedef ChannelConnector = WebSocketChannel Function(Uri url);
typedef HelloLoader = Future<Map<String, String>> Function();

WebSocketChannel _defaultConnector(Uri url) =>
    IOWebSocketChannel.connect(url, connectTimeout: const Duration(seconds: 5));

/// The screen's WebSocket session (`/api/ws?token=…`, protocol §4).
///
/// Holds the latest [view], keeps the [clock] in sync, answers `ping` at once,
/// re-sends `hello` after every `welcome`, and reconnects forever with
/// 1, 2, 4 … 10 s backoff until the server closes with a terminal code
/// ([terminalCloseCodes]). The last view stays on screen while offline.
class GameSocket extends ChangeNotifier {
  GameSocket({
    required this.base,
    required this.token,
    required HelloLoader hello,
    ChannelConnector connector = _defaultConnector,
    ServerClock? clock,
  })  : _hello = hello,
        _connector = connector,
        clock = clock ?? ServerClock();

  final Uri base;

  /// The screen token from `POST /api/games/{pin}/join`.
  final String token;
  final ServerClock clock;
  final HelloLoader _hello;
  final ChannelConnector _connector;

  final _events = StreamController<GameEvent>.broadcast();

  SocketStatus _status = SocketStatus.connecting;
  GameView? _view;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retryTimer;
  DateTime? _retryAt;
  int _attempt = 0;
  bool _disposed = false;
  int? _closeCode;

  SocketStatus get status => _status;
  GameView? get view => _view;


  /// The terminal close code once [status] is [SocketStatus.ended].
  int? get closeCode => _closeCode;

  /// When the next reconnect attempt fires (null unless offline).
  DateTime? get retryAt => _retryAt;

  /// Sound/animation cues.
  Stream<GameEvent> get events => _events.stream;

  void start() => _connect();

  void _connect() {
    if (_disposed) return;
    _retryTimer?.cancel();
    _retryAt = null;
    _setStatus(SocketStatus.connecting);
    final WebSocketChannel channel;
    try {
      channel = _connector(ServerAddress.socket(base, token));
    } catch (e) {
      _scheduleReconnect();
      return;
    }
    _channel = channel;
    _sub = channel.stream.listen(
      (frame) {
        if (frame is String) handleFrame(frame);
      },
      onError: (Object e) {
        debugPrint('ws error: $e');
        if (identical(_channel, channel)) _scheduleReconnect();
      },
      onDone: () {
        if (!identical(_channel, channel)) return;
        final code = channel.closeCode;
        if (code != null && terminalCloseCodes.contains(code)) {
          _end(code);
        } else {
          _scheduleReconnect();
        }
      },
      cancelOnError: true,
    );
    // A failed handshake surfaces on `ready`; the stream then just closes.
    channel.ready.catchError((Object e) {
      debugPrint('ws connect failed: $e');
      if (identical(_channel, channel)) _scheduleReconnect();
    });
  }

  void _end(int code) {
    _closeChannel();
    _retryTimer?.cancel();
    _retryAt = null;
    _closeCode = code;
    _setStatus(SocketStatus.ended);
  }

  /// Gives the screen seat up (`leave`, protocol §4.3) and stops for good.
  void leave() {
    send('leave', const {});
    _retryTimer?.cancel();
    _retryAt = null;
    _closeChannel();
  }

  void _scheduleReconnect() {
    if (_disposed || _status == SocketStatus.ended || _retryTimer?.isActive == true) return;
    _closeChannel();
    final delay = reconnectDelay(_attempt++);
    _retryAt = DateTime.now().add(delay);
    _retryTimer = Timer(delay, _connect);
    _setStatus(SocketStatus.offline);
  }

  /// Applies one server frame. Public for tests.
  @visibleForTesting
  void handleFrame(String frame) {
    final Json msg;
    try {
      msg = asJson(jsonDecode(frame));
    } catch (_) {
      return;
    }
    final data = asJson(msg['data']);
    switch (asString(msg['type'])) {
      case 'welcome':
        _attempt = 0;
        final now = asIntOrNull(data['serverNow']);
        if (now != null) clock.sync(now);
        _setStatus(SocketStatus.connected);
        _sendHello();
      case 'state':
        final view = GameView.fromJson(data);
        if (view.serverNow > 0) clock.sync(view.serverNow);
        _view = view;
        if (_status != SocketStatus.connected) _status = SocketStatus.connected;
        notifyListeners();
      case 'ping':
        send('pong', {'t': data['t']});
      case 'event':
        _events.add(GameEvent.fromJson(data));
      case 'error':
        debugPrint('server error: ${data['code']} ${data['message']}');
    }
  }

  Future<void> _sendHello() async {
    try {
      send('hello', await _hello());
    } catch (e) {
      debugPrint('hello failed: $e');
    }
  }

  void send(String type, Map<String, Object?> data) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode({'type': type, 'data': data}));
    } catch (e) {
      debugPrint('ws send failed: $e');
    }
  }

  void _setStatus(SocketStatus s) {
    if (_status == s || _disposed) return;
    _status = s;
    notifyListeners();
  }

  void _closeChannel() {
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _closeChannel();
    _events.close();
    super.dispose();
  }
}
