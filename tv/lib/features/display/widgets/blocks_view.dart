import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/server_address.dart';
import '../../../data/models/block.dart';
import 'media/media_block.dart';

/// Renders question/answer blocks centred on the stage. Text blocks are
/// CommonMark without raw HTML (tags show as literal text); media fit the
/// space left over, which never exceeds 70 % of the stage height.
class BlocksView extends StatelessWidget {
  const BlocksView({
    super.key,
    required this.blocks,
    required this.server,
    required this.keyPrefix,
    required this.stage,
    this.textSize,
  });

  final List<Block> blocks;
  final Uri server;

  /// Keeps media widgets (and their playback) alive across rebuilds.
  final String keyPrefix;

  /// Display stage owning these blocks' media (see `stageKeyOf`).
  final String stage;

  /// Overrides the length-based text size.
  final double? textSize;

  /// Manifest: question text 24–48 px; shorter text reads bigger.
  static double sizeFor(List<Block> blocks, {required bool hasMedia}) {
    final chars = blocks.where((b) => !b.isMedia).fold(0, (n, b) => n + b.markdown.length);
    if (hasMedia) return chars < 120 ? 40 : 32;
    if (chars < 80) return 48;
    if (chars < 220) return 42;
    if (chars < 450) return 34;
    return 28;
  }

  @override
  Widget build(BuildContext context) {
    final hasMedia = blocks.any((b) => b.isMedia);
    final size = textSize ?? sizeFor(blocks, hasMedia: hasMedia);
    return LayoutBuilder(
      builder: (context, c) {
        final maxMedia = c.maxHeight.isFinite ? c.maxHeight : 756.0;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final (i, b) in blocks.indexed)
              if (b.isMedia)
                Flexible(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxMedia.clamp(0, 756)),
                      child: _media(b, ValueKey('$keyPrefix-$i')),
                    ),
                  ),
                )
              else
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: c.maxWidth),
                        child: MarkdownText(markdown: b.markdown, size: size, server: server),
                      ),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }

  Widget _media(Block b, Key key) {
    final url = ServerAddress.resolve(server, b.url);
    return switch (b.type) {
      BlockType.video || BlockType.audio => MediaBlock(key: key, type: b.type, url: url, alt: b.alt, stage: stage),
      _ => NetworkMedia(key: key, url: url),
    };
  }
}

/// An image block, fitted and rounded.
class NetworkMedia extends StatelessWidget {
  const NetworkMedia({super.key, required this.url});

  final Uri url;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          url.toString(),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const SizedBox(
                  width: 64,
                  height: 64,
                  child: CircularProgressIndicator(strokeWidth: 5, color: AppColors.accent),
                ),
          errorBuilder: (context, error, stack) => mediaPlaceholder(Icons.broken_image, 'Изображение недоступно'),
        ),
      ),
    );
  }
}

/// CommonMark text, centred, in the stage type scale.
class MarkdownText extends StatelessWidget {
  const MarkdownText({
    super.key,
    required this.markdown,
    required this.size,
    required this.server,
    this.color = AppColors.text,
    this.align = WrapAlignment.center,
  });

  final String markdown;
  final double size;
  final Uri server;
  final Color color;
  final WrapAlignment align;

  @override
  Widget build(BuildContext context) {
    final base = AppText.bodyStyle(size, weight: FontWeight.w500, color: color);
    return MarkdownBody(
      data: markdown,
      // CommonMark only; HTML is not interpreted (shown as literal text).
      extensionSet: md.ExtensionSet.commonMark,
      softLineBreak: true,
      styleSheet: MarkdownStyleSheet(
        p: base,
        textAlign: align,
        h1: base.copyWith(fontSize: size * 1.4, fontWeight: FontWeight.w600),
        h2: base.copyWith(fontSize: size * 1.25, fontWeight: FontWeight.w600),
        h3: base.copyWith(fontSize: size * 1.1, fontWeight: FontWeight.w600),
        h4: base,
        h5: base,
        h6: base,
        h1Align: align,
        h2Align: align,
        h3Align: align,
        strong: const TextStyle(fontWeight: FontWeight.w700),
        em: const TextStyle(fontStyle: FontStyle.italic),
        a: base.copyWith(color: AppColors.accent),
        code: AppText.monoStyle(size * 0.9, color: AppColors.gold).copyWith(backgroundColor: AppColors.surface2),
        listBullet: base,
        blockquote: base.copyWith(color: AppColors.textMuted),
        blockquoteDecoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: const Border(left: BorderSide(color: AppColors.accent, width: 4)),
        ),
        codeblockDecoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(8)),
        horizontalRuleDecoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border, width: 2)),
        ),
        tableBody: base,
        tableHead: base.copyWith(fontWeight: FontWeight.w600),
      ),
      // Text blocks never contain media (the server strips them); any stray
      // image reference renders through the same resolver.
      imageBuilder: (uri, title, alt) => Image.network(
        ServerAddress.resolve(server, uri.toString()).toString(),
        height: size * 6,
        errorBuilder: (context, error, stack) => const SizedBox.shrink(),
      ),
    );
  }
}
