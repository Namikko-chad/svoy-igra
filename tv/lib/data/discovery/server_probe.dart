import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../models/json.dart';

/// `GET /api/info` (protocol §2.1).
class ServerInfo {
  const ServerInfo({required this.name, required this.webUrl});

  final String name;

  /// Public address of the web client (server env `WEB_URL`); null when unset.
  final String? webUrl;

  factory ServerInfo.fromJson(Json j) {
    final web = asStringOrNull(j['webUrl'])?.trim();
    return ServerInfo(
      name: asString(j['name'], 'Своя игра'),
      webUrl: web == null || web.isEmpty ? null : web,
    );
  }
}

/// Validates a manually entered address and reads the lobby join link.
abstract final class ServerProbe {
  /// Returns the server info, or throws a human-readable [ProbeError].
  static Future<ServerInfo> info(Uri base) async {
    final http.Response res;
    try {
      res = await http.get(base.replace(path: '/api/info')).timeout(AppConfig.infoTimeout);
    } catch (_) {
      throw const ProbeError('Сервер не отвечает');
    }
    if (res.statusCode != 200) throw ProbeError('Ответ сервера: ${res.statusCode}');
    try {
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      if (json is! Map) throw const FormatException();
      return ServerInfo.fromJson(asJson(json));
    } catch (_) {
      throw const ProbeError('Это не сервер «Своей игры»');
    }
  }
}

class ProbeError implements Exception {
  const ProbeError(this.message);
  final String message;

  @override
  String toString() => message;
}
