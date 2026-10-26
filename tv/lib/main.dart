import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app.dart';
import 'app_controller.dart';
import 'data/storage/server_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // TV is driven by the D-pad: always draw focus rings.
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  try {
    await WakelockPlus.enable();
  } catch (e) {
    debugPrint('wakelock unavailable: $e');
  }

  final controller = AppController(await ServerStore.open())..boot();
  runApp(SvoyIgraTvApp(controller: controller));
}
