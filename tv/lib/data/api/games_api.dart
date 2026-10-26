import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../models/game_info.dart';
import '../models/json.dart';

/// A failed REST call: `{"error":{"code","message"}}` (protocol §2) or a
/// network failure (`code: network`).
class ApiError implements Exception {
  const ApiError(this.code, this.message, {this.status = 0});

  final String code;
  final String message;
  final int status;

  @override
  String toString() => 'ApiError($status $code: $message)';
}

/// The public game calls the screen needs (protocol §2.1).
abstract class GamesApi {
  /// Every live game, newest first.
  Future<List<GameInfo>> listGames();
  Future<GameInfo> getGame(String pin);
  Future<JoinResult> joinAsScreen(String pin);

  /// Watch a game from the list by its public id (no PIN/link is revealed).
  Future<JoinResult> watch(String gameId);
}

class HttpGamesApi implements GamesApi {
  HttpGamesApi(this.base, {http.Client? client}) : _client = client ?? http.Client();

  final Uri base;
  final http.Client _client;

  Uri _url(String path) => base.replace(path: path);

  @override
  Future<List<GameInfo>> listGames() async {
    final body = await _send(() => _client.get(_url('/api/games')));
    return GameInfo.listFromJson(body);
  }

  @override
  Future<GameInfo> getGame(String pin) async =>
      GameInfo.fromJson(asJson(await _send(() => _client.get(_url('/api/games/$pin')))));

  @override
  Future<JoinResult> joinAsScreen(String pin) async => JoinResult.fromJson(asJson(await _send(
        () => _client.post(
          _url('/api/games/$pin/join'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'role': 'screen'}),
        ),
      )));

  @override
  Future<JoinResult> watch(String gameId) async => JoinResult.fromJson(asJson(await _send(
        () => _client.post(_url('/api/games/${Uri.encodeComponent(gameId)}/watch')),
      )));

  /// Decodes a 2xx body (object or array); throws [ApiError] otherwise.
  Future<Object?> _send(Future<http.Response> Function() call) async {
    final http.Response res;
    try {
      res = await call().timeout(AppConfig.infoTimeout);
    } catch (_) {
      throw const ApiError('network', 'Сервер не отвечает');
    }
    Object? body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      body = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300 && (body is Map || body is List)) return body;
    final err = asJson(asJson(body)['error']);
    throw ApiError(
      asString(err['code'], 'http_${res.statusCode}'),
      asString(err['message'], 'Ответ сервера: ${res.statusCode}'),
      status: res.statusCode,
    );
  }
}
