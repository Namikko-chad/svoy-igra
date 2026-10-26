import 'dart:io';

import 'package:win32_registry/win32_registry.dart';

import '../core/platform.dart';

/// Desktop: registers this executable as the handler of `svoyigra://` share
/// links (protocol §8), so a click in a browser or chat opens the app.
/// Android declares it in the manifest and macOS in `Info.plist`; Windows and
/// Linux have no installer, so the app registers itself for the current user
/// on every start (the latest started copy wins). Never throws.
Future<void> registerUrlScheme() async {
  try {
    switch (clientPlatform) {
      case ClientPlatform.windows:
        _registerWindows(Platform.resolvedExecutable);
      case ClientPlatform.linux:
        await _registerLinux(Platform.resolvedExecutable);
      case ClientPlatform.android:
      case ClientPlatform.macos:
        break;
    }
  } catch (_) {}
}

const scheme = 'svoyigra';

/// Must match `APPLICATION_ID` in `linux/CMakeLists.txt`, so the desktop
/// associates the window with this entry (name + icon).
const linuxAppId = 'dev.svoyigra.client';

void _registerWindows(String exe) {
  final root = CURRENT_USER.create('Software\\Classes\\$scheme');
  try {
    root.setValue('', const RegistryValue.string('URL:Своя игра'));
    root.setValue('URL Protocol', const RegistryValue.string(''));
    final icon = root.create('DefaultIcon');
    icon.setValue('', RegistryValue.string('"$exe",0'));
    icon.close();
    final command = root.create('shell\\open\\command');
    command.setValue('', RegistryValue.string('"$exe" "%1"'));
    command.close();
  } finally {
    root.close();
  }
}

/// The `.desktop` entry for this executable: menu item + `x-scheme-handler`.
String linuxDesktopEntry(String exe) {
  final dir = File(exe).parent.path;
  String quote(String s) => '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  return [
    '[Desktop Entry]',
    'Type=Application',
    'Name=Своя игра',
    'Comment=Викторина для компании: игрок, ведущий, экран, админ',
    'Exec=${quote(exe)} %u',
    'Icon=$dir/data/flutter_assets/assets/icon.png',
    'Terminal=false',
    'Categories=Game;',
    'MimeType=x-scheme-handler/$scheme;',
    'StartupWMClass=$linuxAppId',
    '',
  ].join('\n');
}

Future<void> _registerLinux(String exe) async {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) return;
  final dataHome = Platform.environment['XDG_DATA_HOME'] ?? '$home/.local/share';
  final apps = Directory('$dataHome/applications');
  final file = File('${apps.path}/$linuxAppId.desktop');
  final entry = linuxDesktopEntry(exe);
  if (file.existsSync() && file.readAsStringSync() == entry) return;
  await apps.create(recursive: true);
  await file.writeAsString(entry);
  // Both tools are optional: without them the entry still shows in the menu.
  for (final cmd in [
    ['xdg-mime', 'default', '$linuxAppId.desktop', 'x-scheme-handler/$scheme'],
    ['update-desktop-database', apps.path],
  ]) {
    try {
      await Process.run(cmd.first, cmd.sublist(1));
    } catch (_) {}
  }
}
