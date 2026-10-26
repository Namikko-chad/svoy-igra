import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../data/models/block.dart';
import 'equalizer.dart';
import 'media_playback.dart';

/// A video or audio block of a question, answer or comment.
///
/// Playback rule (protocol §3, screen): starts once, with sound, as soon as
/// its [stage] is the display's current stage ([MediaStage]) — immediately,
/// or after an overlay such as the modifier reveal goes away; once started it
/// stops for good when the display moves to another stage (e.g. the
/// question's media when `reveal` starts) and is disposed with the widget.
/// The parent keys it by stage + block index so unrelated `state` rebuilds
/// keep the same playback.
class MediaBlock extends StatefulWidget {
  const MediaBlock({super.key, required this.type, required this.url, required this.alt, required this.stage});

  final BlockType type;
  final Uri url;
  final String alt;

  /// Stage that owns this media (`q-<id>`, `reveal-<id>`).
  final String stage;

  @override
  State<MediaBlock> createState() => _MediaBlockState();
}

class _MediaBlockState extends State<MediaBlock> {
  MediaPlayback? _playback;
  ValueNotifier<String>? _current;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = MediaStage.of(context);
    if (!identical(current, _current)) {
      _current?.removeListener(_onStage);
      _current = current?..addListener(_onStage);
    }
    if (_playback == null) {
      _playback = MediaPlaybackScope.of(context)(widget.type, widget.url);
      _onStage();
    }
  }

  bool get _isCurrent => _current == null || _current!.value == widget.stage;

  void _onStage() {
    final playback = _playback;
    if (playback == null) return;
    if (_isCurrent && !_started) {
      _started = true;
      playback.start();
    } else if (!_isCurrent && _started) {
      playback.stop();
    }
  }

  @override
  void dispose() {
    _current?.removeListener(_onStage);
    _playback?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playback = _playback!;
    return ValueListenableBuilder<MediaState>(
      valueListenable: playback.state,
      builder: (context, state, _) => widget.type == BlockType.video ? _video(playback, state) : _audio(state),
    );
  }

  Widget _video(MediaPlayback playback, MediaState state) {
    if (state == MediaState.failed) return mediaPlaceholder(Icons.videocam_off, 'Видео недоступно');
    final ratio = playback.aspectRatio;
    if (ratio == null || ratio <= 0) {
      return const Center(
        child: SizedBox(
          width: 64,
          height: 64,
          child: CircularProgressIndicator(strokeWidth: 5, color: AppColors.accent),
        ),
      );
    }
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(aspectRatio: ratio, child: playback.view()),
      ),
    );
  }

  Widget _audio(MediaState state) {
    final playing = state == MediaState.playing;
    final failed = state == MediaState.failed;
    final caption = switch (state) {
      MediaState.failed => 'Аудио недоступно',
      MediaState.playing => 'Звучит фрагмент',
      MediaState.completed || MediaState.stopped => 'Фрагмент прозвучал',
      MediaState.loading => 'Загрузка аудио…',
    };
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: playing ? AppColors.accent : AppColors.border, width: playing ? 3 : 1),
          boxShadow: playing ? AppColors.accentGlow : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(failed ? Icons.volume_off : Icons.volume_up, size: 72, color: AppColors.accent),
            const SizedBox(width: 32),
            Equalizer(active: playing, height: 120),
            const SizedBox(width: 32),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(caption, style: AppText.bodyStyle(34, weight: FontWeight.w600)),
                if (widget.alt.isNotEmpty) Text(widget.alt, style: AppText.bodyStyle(26, color: AppColors.textMuted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared "media failed" look (images too).
Widget mediaPlaceholder(IconData icon, String text) => Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 72, color: AppColors.textMuted),
      const SizedBox(height: 12),
      Text(text, style: AppText.bodyStyle(28, color: AppColors.textMuted)),
    ],
  ),
);
