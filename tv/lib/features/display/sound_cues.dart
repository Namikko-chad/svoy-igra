import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../../data/models/game_event.dart';

/// Plays a short generated tone (assets/sounds) for each `event` cue.
/// Cue players request no audio focus so they never pause question media.
class SoundCues {
  SoundCues(Stream<GameEvent> events) {
    _sub = events.listen(_onEvent);
  }

  static final _noFocus = AudioContext(
    android: const AudioContextAndroid(
      audioFocus: AndroidAudioFocus.none,
      usageType: AndroidUsageType.game,
      contentType: AndroidContentType.sonification,
    ),
  );

  late final StreamSubscription<GameEvent> _sub;
  final _players = <String, AudioPlayer>{};

  void _onEvent(GameEvent e) {
    final name = switch (e.kind) {
      GameEventKind.questionOpened => 'question_opened',
      GameEventKind.buzz => 'buzz',
      GameEventKind.judged => e.correct == true ? 'correct' : 'wrong',
      GameEventKind.timeout => 'timeout',
      GameEventKind.roundStarted => 'round_started',
      GameEventKind.gameFinished => 'game_finished',
      GameEventKind.modifier => 'modifier',
      GameEventKind.catGiven => 'cat',
      GameEventKind.auctionBid => 'bid',
      GameEventKind.auctionPass => 'pass',
      GameEventKind.auctionWon => 'gavel',
      GameEventKind.finalThemeRemoved => 'remove',
      GameEventKind.finalJudged => e.correct == true ? 'correct' : 'wrong',
      GameEventKind.scoreAdjusted || GameEventKind.unknown => null,
    };
    if (name != null) _play(name);
  }

  Future<void> _play(String name) async {
    try {
      var player = _players[name];
      if (player == null) {
        player = AudioPlayer(playerId: 'cue_$name');
        _players[name] = player;
        await player.setAudioContext(_noFocus);
        await player.setReleaseMode(ReleaseMode.stop);
      }
      await player.stop();
      await player.play(AssetSource('sounds/$name.wav'), volume: 0.8);
    } catch (e) {
      debugPrint('cue $name failed: $e');
    }
  }

  void dispose() {
    _sub.cancel();
    for (final p in _players.values) {
      p.dispose();
    }
    _players.clear();
  }
}
