import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:video_player/video_player.dart';

import '../../core/theme.dart';
import '../../data/models.dart';

/// Who is looking at the blocks — drives the playback rules (protocol §3).
enum MediaMode {
  /// Images + muted autoplay video (with controls / unmute); audio is a chip with manual play.
  player,

  /// Everything with controls, no autoplay.
  host,

  /// Read-only display: video and audio autoplay with sound.
  screen,
}

/// Markdown (CommonMark, raw HTML shown as text — never rendered).
class MarkdownText extends StatelessWidget {
  const MarkdownText(this.data, {super.key, this.fontSize = 18, this.center = false, this.color = AppColors.text});

  final String data;
  final double fontSize;
  final bool center;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final base = AppText.body(fontSize, weight: FontWeight.w500, color: color).copyWith(height: 1.35);
    return MarkdownBody(
      data: data,
      extensionSet: md.ExtensionSet.commonMark,
      softLineBreak: true,
      styleSheet: MarkdownStyleSheet(
        p: base,
        strong: const TextStyle(fontWeight: FontWeight.w700),
        em: const TextStyle(fontStyle: FontStyle.italic),
        a: const TextStyle(color: AppColors.accent),
        h1: AppText.display(fontSize * 1.4, weight: FontWeight.w600, color: color),
        h2: AppText.display(fontSize * 1.25, weight: FontWeight.w600, color: color),
        h3: AppText.display(fontSize * 1.1, weight: FontWeight.w600, color: color),
        listBullet: base,
        code: AppText.mono(fontSize * 0.85).copyWith(backgroundColor: AppColors.surface2),
        codeblockDecoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(8)),
        blockquoteDecoration: const BoxDecoration(
          border: Border(left: BorderSide(color: AppColors.border, width: 3)),
        ),
        textAlign: center ? WrapAlignment.center : WrapAlignment.start,
        h1Align: center ? WrapAlignment.center : WrapAlignment.start,
        h2Align: center ? WrapAlignment.center : WrapAlignment.start,
        h3Align: center ? WrapAlignment.center : WrapAlignment.start,
      ),
    );
  }
}

/// Renders question/answer blocks in document order.
class BlocksView extends StatelessWidget {
  const BlocksView({
    super.key,
    required this.blocks,
    required this.mode,
    required this.resolveUrl,
    this.fontSize = 22,
    this.center = true,
    this.scope = '',
  });

  final List<Block> blocks;
  final MediaMode mode;
  final String Function(String url) resolveUrl;
  final double fontSize;
  final bool center;

  /// Distinguishes media players of different block lists (question / answer /
  /// comment of a question): a new scope disposes the old players.
  final String scope;

  @override
  Widget build(BuildContext context) {
    final maxMediaH = MediaQuery.sizeOf(context).height * 0.5;
    return Column(
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
      children: [
        for (final (i, b) in blocks.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: switch (b.type) {
              BlockType.text => MarkdownText(b.markdown, fontSize: fontSize, center: center),
              BlockType.image => ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxMediaH),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      resolveUrl(b.url),
                      fit: BoxFit.contain,
                      semanticLabel: b.alt,
                      errorBuilder: (_, _, _) => _MediaError(alt: b.alt),
                      loadingBuilder: (_, child, p) => p == null
                          ? child
                          : const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
                    ),
                  ),
                ),
              BlockType.video => VideoBlock(
                  key: ValueKey('$scope:v:$i:${b.url}'),
                  url: resolveUrl(b.url),
                  mode: mode,
                  maxHeight: maxMediaH,
                ),
              BlockType.audio => AudioChip(
                  key: ValueKey('$scope:a:$i:${b.url}'),
                  url: resolveUrl(b.url),
                  autoplay: mode == MediaMode.screen,
                  label: mode == MediaMode.player ? '🔊 звучит на экране' : (b.alt.isEmpty ? 'Аудио' : b.alt),
                ),
            },
          ),
      ],
    );
  }
}

class _MediaError extends StatelessWidget {
  const _MediaError({required this.alt});

  final String alt;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Flexible(child: Text(alt.isEmpty ? 'Не удалось загрузить медиа' : alt, style: AppText.muted(14))),
        ]),
      );
}

/// Video: player — muted autoplay with controls (unmute); screen — autoplay
/// with sound, no controls; host / editor preview — controls, no autoplay.
class VideoBlock extends StatefulWidget {
  const VideoBlock({super.key, required this.url, required this.mode, required this.maxHeight});

  final String url;
  final MediaMode mode;
  final double maxHeight;

  bool get autoplay => mode != MediaMode.host;
  bool get controls => mode != MediaMode.screen;

  @override
  State<VideoBlock> createState() => _VideoBlockState();
}

class _VideoBlockState extends State<VideoBlock> {
  late final VideoPlayerController _c;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _c.initialize().then((_) async {
      if (!mounted) return;
      await _c.setLooping(false);
      if (widget.autoplay) {
        await _c.setVolume(widget.mode == MediaMode.player ? 0 : 1);
        await _c.play();
      }
      if (mounted) setState(() {});
    }).catchError((Object _) {
      if (mounted) setState(() => _failed = true);
    });
    _c.addListener(_onTick);
  }

  void _onTick() {
    if (mounted && widget.controls) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onTick);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const _MediaError(alt: 'Не удалось загрузить видео');
    if (!_c.value.isInitialized) {
      return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
    }
    final video = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: AspectRatio(
        aspectRatio: _c.value.aspectRatio,
        child: ClipRRect(borderRadius: BorderRadius.circular(12), child: VideoPlayer(_c)),
      ),
    );
    if (!widget.controls) return video;
    final playing = _c.value.isPlaying;
    return Column(children: [
      video,
      Row(children: [
        IconButton(
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          onPressed: () => playing ? _c.pause() : _c.play(),
        ),
        Expanded(
          child: VideoProgressIndicator(
            _c,
            allowScrubbing: true,
            colors: const VideoProgressColors(
              playedColor: AppColors.accent,
              bufferedColor: AppColors.border,
              backgroundColor: AppColors.surface2,
            ),
          ),
        ),
        IconButton(
          icon: Icon(_c.value.volume == 0 ? Icons.volume_off : Icons.volume_up),
          onPressed: () => _c.setVolume(_c.value.volume == 0 ? 1 : 0),
        ),
      ]),
    ]);
  }
}

/// Audio as a chip with a manual play/stop button.
class AudioChip extends StatefulWidget {
  const AudioChip({super.key, required this.url, required this.label, this.autoplay = false});

  final String url;
  final String label;
  final bool autoplay;

  @override
  State<AudioChip> createState() => _AudioChipState();
}

class _AudioChipState extends State<AudioChip> {
  final _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  final _subs = <StreamSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    _subs.add(_player.onPlayerStateChanged.listen((s) => mounted ? setState(() => _state = s) : null));
    _subs.add(_player.onPositionChanged.listen((p) => mounted ? setState(() => _pos = p) : null));
    _subs.add(_player.onDurationChanged.listen((d) => mounted ? setState(() => _dur = d) : null));
    if (widget.autoplay) _toggle();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_state == PlayerState.playing) {
        await _player.pause();
      } else if (_state == PlayerState.paused) {
        await _player.resume();
      } else {
        await _player.play(UrlSource(widget.url));
      }
    } catch (_) {}
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final playing = _state == PlayerState.playing;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: playing ? 'Пауза' : 'Слушать',
          icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill, color: AppColors.accent, size: 32),
          onPressed: _toggle,
        ),
        if (_state != PlayerState.stopped && _state != PlayerState.completed)
          IconButton(icon: const Icon(Icons.stop), onPressed: () => _player.stop()),
        Flexible(child: Text(widget.label, style: AppText.body(14, weight: FontWeight.w500))),
        if (_dur > Duration.zero) ...[
          const SizedBox(width: 8),
          Text('${_fmt(_pos)} / ${_fmt(_dur)}', style: AppText.mono(12, color: AppColors.textMuted)),
        ],
      ]),
    );
  }
}
