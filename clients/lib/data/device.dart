import 'dart:io';
import 'dart:ui';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/platform.dart';

/// Device info sent in the WebSocket `hello` (protocol §4.1). Collected once.
class DeviceHello {
  DeviceHello._();

  static Map<String, dynamic> data = {'platform': clientPlatform.name};
  static String appVersion = '';

  static Future<void> collect() async {
    final platform = clientPlatform;
    var (model, os) = ('', '');
    try {
      (model, os) = await _modelAndOs(platform);
    } catch (_) {}
    try {
      appVersion = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
    var screen = '';
    final views = PlatformDispatcher.instance.views;
    if (views.isNotEmpty) {
      final view = views.first;
      // A desktop window is not the screen: report the display it is on.
      var size = view.physicalSize;
      if (isDesktop) {
        try {
          size = view.display.size;
        } catch (_) {}
      }
      final w = size.shortestSide.round(), h = size.longestSide.round();
      if (w > 0) screen = isDesktop ? '${h}x$w' : '${w}x$h';
    }
    data = {
      'platform': platform.name,
      'model': model,
      'os': os,
      'appVersion': appVersion,
      'userAgent': 'svoy-igra-client/$appVersion ($os; $model)',
      'screen': screen,
    };
  }

  static Future<(String, String)> _modelAndOs(ClientPlatform platform) async {
    final info = DeviceInfoPlugin();
    String join(Iterable<String?> parts) => parts.whereType<String>().where((s) => s.isNotEmpty).join(' ');
    switch (platform) {
      case ClientPlatform.android:
        final a = await info.androidInfo;
        return (join([a.manufacturer, a.model]), 'Android ${a.version.release}');
      case ClientPlatform.windows:
        final w = await info.windowsInfo;
        // The registry still says «Windows 10» on Windows 11; build 22000+ is 11.
        var product = w.productName;
        if (w.buildNumber >= 22000) product = product.replaceFirst('Windows 10', 'Windows 11');
        return (w.computerName, join([product, w.displayVersion]));
      case ClientPlatform.linux:
        final l = await info.linuxInfo;
        return (_linuxModel(), l.prettyName.isNotEmpty ? l.prettyName : join([l.name, l.version]));
      case ClientPlatform.macos:
        final m = await info.macOsInfo;
        return (
          m.modelName.isNotEmpty ? m.modelName : m.model,
          'macOS ${m.majorVersion}.${m.minorVersion}.${m.patchVersion}',
        );
    }
  }

  /// Vendor + product from DMI (readable without root), e.g. «LENOVO 21CB».
  static String _linuxModel() {
    String read(String name) {
      try {
        return File('/sys/class/dmi/id/$name').readAsStringSync().trim();
      } catch (_) {
        return '';
      }
    }

    return [read('sys_vendor'), read('product_name')].where((s) => s.isNotEmpty).join(' ');
  }
}
