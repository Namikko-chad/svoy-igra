import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../utils/server_address.dart';

/// The server base for resolving relative avatar URLs below this widget.
class ServerBase extends InheritedWidget {
  const ServerBase({super.key, required this.base, required super.child});

  final Uri base;

  static Uri? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ServerBase>()?.base;

  @override
  bool updateShouldNotify(ServerBase old) => old.base != base;
}

/// Manifest "Avatar": a circle with the picture, or initials on `surface-2`.
/// [url] is the server-relative `avatarUrl` (null → initials). Sizes: 24
/// lists, 40 scoreboard, 64 answering/standings, 96 lobby/podium.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, required this.url, this.size = 40, this.ring});

  final String name;
  final String? url;
  final double size;

  /// Gold for the chooser, accent for the player answering.
  final Color? ring;

  /// Up to two initials: first letters of the first two words.
  static String initials(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    final first = String.fromCharCodes(words.first.runes.take(1));
    final second = words.length > 1 ? String.fromCharCodes(words[1].runes.take(1)) : '';
    return (first + second).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final base = ServerBase.of(context);
    final raw = url;
    final fallback = Center(
      child: Padding(
        padding: EdgeInsets.all(size * 0.12),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(initials(name), style: AppText.displayStyle(size * 0.38, color: AppColors.text)),
        ),
      ),
    );
    Widget child = fallback;
    if (raw != null && raw.isNotEmpty && base != null) {
      child = Image.network(
        ServerAddress.resolve(base, raw).toString(),
        fit: BoxFit.cover,
        width: size,
        height: size,
        // Avatar URLs are immutable; decode at display size.
        cacheWidth: (size * 2).round(),
        errorBuilder: (context, error, stack) => fallback,
      );
    }
    final ringWidth = ring == null ? 0.0 : (size / 16).clamp(2.0, 5.0);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surface2,
        border: ring == null ? null : Border.all(color: ring!, width: ringWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
