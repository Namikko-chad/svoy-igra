import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/avatar_image.dart';

/// Provides the server base URL so [Avatar] can prefix relative avatar URLs.
class MediaBase extends InheritedWidget {
  const MediaBase({super.key, required this.baseUrl, required super.child});

  final String baseUrl;

  static String resolve(BuildContext context, String url) {
    if (!url.startsWith('/')) return url;
    final base = context.dependOnInheritedWidgetOfExactType<MediaBase>()?.baseUrl;
    return base == null ? url : '$base$url';
  }

  @override
  bool updateShouldNotify(MediaBase old) => old.baseUrl != baseUrl;
}

/// A round avatar (DESIGN_MANIFEST «Avatar»): the picture, or initials on
/// `surface-2`. Sizes: 24 lists, 40 scoreboard, 64 answering / standings.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.url, this.size = 40, this.ring});

  final String name;
  final String? url;
  final double size;

  /// Gold for the chooser, accent for the answering player.
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Text(
        initials(name),
        style: AppText.display(size * 0.36, weight: FontWeight.w600, color: AppColors.text),
      ),
    );
    final u = url;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surface2,
        border: Border.all(color: ring ?? AppColors.border, width: ring == null ? 1 : 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: u == null || u.isEmpty
          ? fallback
          : Image.network(
              MediaBase.resolve(context, u),
              key: ValueKey(u),
              fit: BoxFit.cover,
              width: size,
              height: size,
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

/// «Отвечает …» highlight: a 64 px avatar with the accent ring and the text.
class AnsweringLine extends StatelessWidget {
  const AnsweringLine({super.key, required this.text, this.name, this.url, this.color = AppColors.accent});

  final String text;
  final String? name;
  final String? url;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (name != null) ...[
          Avatar(name: name!, url: url, size: 64, ring: color),
          const SizedBox(width: 12),
        ],
        Flexible(child: Text(text, style: AppText.display(18, weight: FontWeight.w600, color: color))),
      ]);
}
