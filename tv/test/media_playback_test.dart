import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svoy_igra_tv/core/theme/app_theme.dart';
import 'package:svoy_igra_tv/core/widgets/stage_scaler.dart';
import 'package:svoy_igra_tv/data/models/block.dart';
import 'package:svoy_igra_tv/data/ws/game_socket.dart';
import 'package:svoy_igra_tv/features/display/display_screen.dart';
import 'package:svoy_igra_tv/features/display/widgets/media/media_block.dart';
import 'package:svoy_igra_tv/features/display/widgets/media/media_playback.dart';

import 'support/fake_channel.dart';

class FakePlayback implements MediaPlayback {
  FakePlayback(this.type, this.url);

  final BlockType type;
  final Uri url;
  int starts = 0;
  int stops = 0;
  bool disposed = false;
  final _state = ValueNotifier(MediaState.loading);

  @override
  ValueListenable<MediaState> get state => _state;
  @override
  double? get aspectRatio => type == BlockType.video ? 16 / 9 : null;
  @override
  Future<void> start() async {
    starts++;
    _state.value = MediaState.playing;
  }

  @override
  Future<void> stop() async {
    stops++;
    _state.value = MediaState.stopped;
  }

  @override
  Widget view() => const ColoredBox(color: Colors.black);
  @override
  void dispose() => disposed = true;

  bool get playing => starts == 1 && stops == 0 && !disposed;
  bool get silenced => stops > 0 || disposed;
}

const _now = 1761400000000;

Map<String, dynamic> _state(String phase, {bool reveal = false, int score = 0}) => {
      'serverNow': _now,
      'role': 'screen',
      'game': {'pin': null, 'title': 'T', 'link': null, 'hostTaken': true, 'hostConnected': true},
      'phase': phase,
      'pack': {'id': 'pk', 'title': 'P'},
      'round': {'index': 0, 'name': 'R', 'total': 1},
      'board': [],
      'players': [
        {'id': 'p1', 'name': 'Аня', 'score': score, 'connected': true},
      ],
      'chooserId': 'p1',
      'question': {
        'id': 7,
        'categoryName': 'Кино',
        'value': 100,
        'blocks': [
          {'type': 'text', 'markdown': 'Что звучит?'},
          {'type': 'video', 'url': '/api/packs/pk/media/q.mp4', 'alt': ''},
          {'type': 'audio', 'url': '/api/packs/pk/media/q.mp3', 'alt': 'гимн'},
        ],
        'answerBlocks': reveal
            ? [
                {'type': 'text', 'markdown': 'Ответ'},
                {'type': 'video', 'url': '/api/packs/pk/media/a.mp4', 'alt': ''},
                {'type': 'audio', 'url': '/api/packs/pk/media/a.mp3', 'alt': ''},
              ]
            : null,
        'comment': reveal ? 'Послушайте ещё: ![](media:c.ogg)' : null,
      },
      'answeringPlayerId': phase == 'answering' ? 'p1' : null,
      'attemptedPlayerIds': [],
      'readingStartsAt': phase == 'reveal' ? null : _now,
      'readingEndsAt': phase == 'reveal' ? null : _now + 10000,
      'buzzStartsAt': phase == 'reveal' ? null : _now + 10000,
      'buzzEndsAt': phase == 'reveal' ? null : _now + 25000,
      'lastResult': reveal ? {'playerId': 'p1', 'correct': true, 'delta': 100} : null,
    };

void main() {
  testWidgets('question media autoplay; reveal stops them and autoplays answer + comment media once',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final players = <FakePlayback>[];
    FakePlayback byPath(String p) => players.singleWhere((f) => f.url.path.endsWith(p));

    final socket = GameSocket(
      base: Uri.parse('http://10.0.0.2:3050'),
      token: 't',
      hello: () async => {},
      connector: (_) => FakeChannel(),
    )..start();
    void push(Map<String, dynamic> s) => socket.handleFrame(jsonEncode({'type': 'state', 'data': s}));

    push(_state('question'));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      builder: (context, child) => StageScaler(child: child!),
      home: MediaPlaybackScope(
        factory: (type, url) {
          final p = FakePlayback(type, url);
          players.add(p);
          return p;
        },
        child: DisplayScreen(socket: socket, onChangeGame: () {}, onChangeServer: () {}),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));

    // Question: video + audio play once, with full URLs.
    expect(players, hasLength(2));
    expect(byPath('q.mp4').url.toString(), 'http://10.0.0.2:3050/api/packs/pk/media/q.mp4');
    expect(byPath('q.mp4').playing, isTrue);
    expect(byPath('q.mp3').playing, isTrue);
    expect(find.byType(MediaBlock), findsNWidgets(2));

    // Someone buzzes: same question stage → nothing restarts.
    push(_state('answering'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(players, hasLength(2));
    expect(byPath('q.mp4').playing, isTrue);

    // Reveal: question media stops at once (even while fading out) …
    push(_state('reveal', reveal: true));
    await tester.pump();
    expect(byPath('q.mp4').silenced, isTrue);
    expect(byPath('q.mp3').silenced, isTrue);
    // … and the answer's video/audio and the comment's audio autoplay.
    expect(byPath('a.mp4').playing, isTrue);
    expect(byPath('a.mp3').playing, isTrue);
    expect(byPath('c.ogg').type, BlockType.audio);
    expect(byPath('c.ogg').playing, isTrue);

    await tester.pump(const Duration(milliseconds: 500));
    expect(byPath('q.mp4').disposed, isTrue);
    expect(find.byType(MediaBlock), findsNWidgets(3));

    // An unrelated rebuild (score change) during reveal restarts nothing.
    push(_state('reveal', reveal: true, score: 300));
    await tester.pump(const Duration(milliseconds: 500));
    expect(players, hasLength(5));
    expect(byPath('a.mp4').starts, 1);
    expect(byPath('a.mp4').playing, isTrue);

    // Leaving reveal for the board stops and disposes the answer media.
    push({..._state('reveal', reveal: true), 'phase': 'board', 'question': null});
    await tester.pump();
    expect(byPath('a.mp4').silenced, isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    expect(byPath('a.mp4').disposed, isTrue);

    await tester.pumpWidget(const SizedBox());
    socket.dispose();
  });

  testWidgets('a special question shows the modifier reveal first; its media waits until it ends', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final players = <FakePlayback>[];
    final socket = GameSocket(
      base: Uri.parse('http://10.0.0.2:3050'),
      token: 't',
      hello: () async => {},
      connector: (_) => FakeChannel(),
    )..start();
    final state = _state('question');
    (state['question'] as Map<String, dynamic>)
      ..['modifier'] = 'double'
      ..['stake'] = 200;
    socket.handleFrame(jsonEncode({'type': 'state', 'data': state}));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      builder: (context, child) => StageScaler(child: child!),
      home: MediaPlaybackScope(
        factory: (type, url) {
          final p = FakePlayback(type, url);
          players.add(p);
          return p;
        },
        child: DisplayScreen(socket: socket, onChangeGame: () {}, onChangeServer: () {}),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('ДВОЙНАЯ СТОИМОСТЬ'), findsOneWidget);
    expect(players, hasLength(2));
    expect(players.every((p) => p.starts == 0), isTrue, reason: 'media waits under the reveal');

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('ДВОЙНАЯ СТОИМОСТЬ'), findsNothing);
    expect(players.every((p) => p.starts == 1 && p.stops == 0), isTrue);

    await tester.pumpWidget(const SizedBox());
    socket.dispose();
  });
}
