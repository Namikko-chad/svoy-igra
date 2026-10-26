import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A server that answered the LAN discovery broadcast (protocol §7).
class DiscoveredServer {
  const DiscoveredServer({required this.name, required this.version, required this.baseUrl});

  final String name;
  final String version;
  final String baseUrl;
}

const discoveryPort = 3051;
const discoveryProbe = 'SVOY_IGRA_DISCOVER';

/// Broadcasts the probe a few times and collects replies for [timeout].
Future<List<DiscoveredServer>> discoverServers({Duration timeout = const Duration(milliseconds: 2500)}) async {
  final found = <String, DiscoveredServer>{};
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  socket.broadcastEnabled = true;
  final probe = ascii.encode(discoveryProbe);
  final sub = socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final dg = socket.receive();
    if (dg == null) return;
    try {
      final j = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
      final port = (j['port'] as num?)?.toInt() ?? 3050;
      final base = 'http://${dg.address.address}:$port';
      found[base] = DiscoveredServer(
        name: (j['name'] as String?) ?? 'Своя игра',
        version: (j['version'] as String?) ?? '',
        baseUrl: base,
      );
    } catch (_) {
      // Not ours.
    }
  });
  void send() {
    try {
      socket.send(probe, InternetAddress('255.255.255.255'), discoveryPort);
    } catch (_) {
      // No network: the result stays empty.
    }
  }

  send();
  final resend = Timer.periodic(const Duration(milliseconds: 700), (_) => send());
  await Future<void>.delayed(timeout);
  resend.cancel();
  await sub.cancel();
  socket.close();
  return found.values.toList()..sort((a, b) => a.baseUrl.compareTo(b.baseUrl));
}

/// Normalises user input (`192.168.1.10:3050`, `http://host`) to a base URL
/// without a trailing slash. Default port 3050 when none is given.
String? normalizeBaseUrl(String input) {
  var s = input.trim();
  if (s.isEmpty) return null;
  if (!s.contains('://')) s = 'http://$s';
  final uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty || !(uri.scheme == 'http' || uri.scheme == 'https')) return null;
  final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 3050);
  final defaultPort = (uri.scheme == 'https' && port == 443) || (uri.scheme == 'http' && port == 80);
  return '${uri.scheme}://${uri.host}${defaultPort ? '' : ':$port'}';
}
