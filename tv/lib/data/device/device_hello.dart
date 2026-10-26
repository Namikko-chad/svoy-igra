import 'dart:io';
import 'dart:ui';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/config.dart';

/// Builds the `hello` payload (protocol §4.1) once per app run.
abstract final class DeviceHello {
  static Map<String, String>? _cached;

  static Future<Map<String, String>> load() async {
    final cached = _cached;
    if (cached != null) return cached;

    var model = 'unknown';
    var os = Platform.operatingSystem;
    var appVersion = '0.0.0';
    try {
      final pkg = await PackageInfo.fromPlatform();
      appVersion = pkg.version;
    } catch (e) {
      debugPrint('package info unavailable: $e');
    }
    try {
      if (Platform.isAndroid) {
        final a = await DeviceInfoPlugin().androidInfo;
        model = '${a.manufacturer} ${a.model}'.trim();
        os = 'Android ${a.version.release} (SDK ${a.version.sdkInt})';
      }
    } catch (e) {
      debugPrint('device info unavailable: $e');
    }

    final views = PlatformDispatcher.instance.views;
    final size = views.isEmpty ? Size.zero : views.first.physicalSize;
    final screen = '${size.width.round()}x${size.height.round()}';

    return _cached = {
      'platform': AppConfig.platform,
      'model': model,
      'os': os,
      'appVersion': appVersion,
      'userAgent': 'svoy_igra_tv/$appVersion ($os; $model)',
      'screen': screen,
    };
  }
}
