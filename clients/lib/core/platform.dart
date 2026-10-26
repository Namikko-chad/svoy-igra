import 'package:flutter/foundation.dart';

/// The platform the client runs on. Uses [defaultTargetPlatform], so tests can
/// override it with `debugDefaultTargetPlatformOverride`.
enum ClientPlatform { android, windows, linux, macos }

ClientPlatform get clientPlatform => switch (defaultTargetPlatform) {
      TargetPlatform.windows => ClientPlatform.windows,
      TargetPlatform.linux => ClientPlatform.linux,
      TargetPlatform.macOS => ClientPlatform.macos,
      _ => ClientPlatform.android,
    };

/// Windows, Linux or macOS: mouse + keyboard, resizable window, no camera picker.
bool get isDesktop => clientPlatform != ClientPlatform.android;
