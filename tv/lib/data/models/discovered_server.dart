import 'json.dart';

/// A server that answered the LAN discovery probe (protocol §7).
class DiscoveredServer {
  const DiscoveredServer({required this.name, required this.version, required this.base});

  final String name;
  final String version;

  /// `http://<reply source IP>:<reply port>`.
  final Uri base;

  /// Parses a reply datagram; null when it is not a valid reply.
  static DiscoveredServer? fromReply(Json json, String sourceIp) {
    final port = asIntOrNull(json['port']);
    if (port == null || port <= 0 || port > 65535) return null;
    return DiscoveredServer(
      name: asString(json['name'], 'Своя игра'),
      version: asString(json['version']),
      base: Uri(scheme: 'http', host: sourceIp, port: port),
    );
  }
}
