import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/config.dart';
import '../models/discovered_server.dart';
import '../models/json.dart';

/// LAN discovery (protocol §7): broadcast `SVOY_IGRA_DISCOVER` to UDP 3051 and
/// collect the JSON replies for [AppConfig.discoveryWindow].
abstract final class LanDiscovery {
  static Future<List<DiscoveredServer>> scan({Duration? window}) async {
    final found = <String, DiscoveredServer>{};
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final targets = await _broadcastTargets();
      final probe = ascii.encode(AppConfig.discoveryProbe);

      final s = socket;
      final sub = s.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = s.receive();
        if (dg == null) return;
        try {
          final json = jsonDecode(utf8.decode(dg.data));
          final server = DiscoveredServer.fromReply(asJson(json), dg.address.address);
          if (server != null) found[server.base.toString()] = server;
        } catch (_) {
          // Not a discovery reply.
        }
      });

      // Three probes spread over the window: UDP may drop one.
      for (var i = 0; i < 3; i++) {
        for (final t in targets) {
          try {
            s.send(probe, t, AppConfig.discoveryPort);
          } catch (e) {
            debugPrint('discovery send to ${t.address} failed: $e');
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      final rest = (window ?? AppConfig.discoveryWindow) - const Duration(milliseconds: 1200);
      if (rest > Duration.zero) await Future<void>.delayed(rest);
      await sub.cancel();
    } catch (e) {
      debugPrint('discovery failed: $e');
    } finally {
      socket?.close();
    }
    final list = found.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// The limited broadcast address plus each IPv4 interface's /24 broadcast,
  /// since some access points drop `255.255.255.255`.
  static Future<List<InternetAddress>> _broadcastTargets() async {
    final targets = <String>{'255.255.255.255'};
    try {
      final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          final parts = addr.address.split('.');
          if (parts.length == 4) targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
        }
      }
    } catch (_) {
      // Interface listing unavailable: the limited broadcast is enough.
    }
    return [for (final t in targets) InternetAddress(t)];
  }
}
