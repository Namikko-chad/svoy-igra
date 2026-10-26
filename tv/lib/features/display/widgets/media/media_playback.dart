import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../../../../data/models/block.dart';

enum MediaState { loading, playing, completed, stopped, failed }

/// One playable media block (video or audio). The screen's playback rule
/// (protocol §3): start once, with sound, when its stage appears; stop when
/// the stage is left. Behind an interface so tests can count play/stop.
abstract class MediaPlayback {
  ValueListenable<MediaState> get state;

  /// Video frame aspect ratio once known; null for audio / before init.
  double? get aspectRatio;

  /// Loads and plays once (no loop) with sound.
  Future<void> start();

  /// Stops for good (sound off at once); a stopped playback never restarts.
  Future<void> stop();

  /// The video surface; audio has none.
  Widget view();

  void dispose();
}

typedef MediaPlaybackFactory = MediaPlayback Function(BlockType type, Uri url);

MediaPlayback realPlayback(BlockType type, Uri url) =>
    type == BlockType.video ? _VideoPlayback(url) : _AudioPlayback(url);

/// Provides the [MediaPlaybackFactory] (tests swap in a fake).
class MediaPlaybackScope extends InheritedWidget {
  const MediaPlaybackScope({super.key, required this.factory, required super.child});

  final MediaPlaybackFactory factory;

  static MediaPlaybackFactory of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MediaPlaybackScope>()?.factory ?? realPlayback;

  @override
  bool updateShouldNotify(MediaPlaybackScope old) => old.factory != factory;
}

/// The display's current stage key (`q-<id>` for question/answering,
/// `reveal-<id>` …). Media owned by another stage — e.g. the question's
/// video fading out after `reveal` started — stops at once.
class MediaStage extends InheritedNotifier<ValueNotifier<String>> {
  const MediaStage({super.key, required ValueNotifier<String> stage, required super.child}) : super(notifier: stage);

  static ValueNotifier<String>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MediaStage>()?.notifier;
}

class _VideoPlayback implements MediaPlayback {
  _VideoPlayback(Uri url)
    : _controller = VideoPlayerController.networkUrl(url, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));

  final VideoPlayerController _controller;
  final _state = ValueNotifier(MediaState.loading);
  bool _stopped = false;

  @override
  ValueListenable<MediaState> get state => _state;

  @override
  double? get aspectRatio => _controller.value.isInitialized ? _controller.value.aspectRatio : null;

  @override
  Future<void> start() async {
    try {
      await _controller.initialize();
      if (_stopped) return;
      await _controller.setLooping(false);
      await _controller.setVolume(1);
      _controller.addListener(_onTick);
      await _controller.play();
      if (!_stopped) _state.value = MediaState.playing;
    } catch (e) {
      debugPrint('video failed: $e');
      if (!_stopped) _state.value = MediaState.failed;
    }
  }

  void _onTick() {
    final v = _controller.value;
    if (_stopped || !v.isInitialized) return;
    if (v.isCompleted) _state.value = MediaState.completed;
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _state.value = MediaState.stopped;
    try {
      await _controller.setVolume(0);
      await _controller.pause();
    } catch (_) {
      // Not initialised yet: nothing is playing.
    }
  }

  @override
  Widget view() => VideoPlayer(_controller);

  @override
  void dispose() {
    _stopped = true;
    _controller.removeListener(_onTick);
    _controller.dispose();
    _state.dispose();
  }
}

class _AudioPlayback implements MediaPlayback {
  _AudioPlayback(this._url);

  final Uri _url;
  final _player = ap.AudioPlayer();
  final _state = ValueNotifier(MediaState.loading);
  StreamSubscription<ap.PlayerState>? _sub;
  bool _stopped = false;

  @override
  ValueListenable<MediaState> get state => _state;

  @override
  double? get aspectRatio => null;

  @override
  Future<void> start() async {
    _sub = _player.onPlayerStateChanged.listen((s) {
      if (_stopped) return;
      _state.value = switch (s) {
        ap.PlayerState.playing => MediaState.playing,
        ap.PlayerState.completed => MediaState.completed,
        _ => _state.value,
      };
    });
    try {
      await _player.setReleaseMode(ap.ReleaseMode.stop);
      if (_stopped) return;
      await _player.play(ap.UrlSource(_url.toString()), volume: 1);
    } catch (e) {
      debugPrint('audio failed: $e');
      if (!_stopped) _state.value = MediaState.failed;
    }
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _state.value = MediaState.stopped;
    try {
      await _player.stop();
    } catch (_) {}
  }

  @override
  Widget view() => const SizedBox.shrink();

  @override
  void dispose() {
    _stopped = true;
    _sub?.cancel();
    _player.dispose();
    _state.dispose();
  }
}
