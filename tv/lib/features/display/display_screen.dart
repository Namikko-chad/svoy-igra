import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/server_address.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/stage_background.dart';
import '../../core/widgets/tv_button.dart';
import '../../data/models/game_event.dart';
import '../../data/models/game_view.dart';
import '../../data/ws/game_socket.dart';
import 'sound_cues.dart';
import 'stage_key.dart';
import 'widgets/board_view.dart';
import 'widgets/final_views.dart';
import 'widgets/lobby_view.dart';
import 'widgets/media/media_playback.dart';
import 'widgets/modifier_reveal.dart';
import 'widgets/question_stage.dart';
import 'widgets/scoreboard_strip.dart';
import 'widgets/special_views.dart';
import 'widgets/standings_view.dart';
import 'widgets/top_bar.dart';

/// The read-only game display. Back / Menu / OK opens the "change server"
/// dialog; nothing else on this screen takes input.
class DisplayScreen extends StatefulWidget {
  const DisplayScreen({super.key, required this.socket, required this.onChangeGame, required this.onChangeServer});

  final GameSocket socket;
  final VoidCallback onChangeGame;
  final VoidCallback onChangeServer;

  @override
  State<DisplayScreen> createState() => _DisplayScreenState();
}

class _DisplayScreenState extends State<DisplayScreen> {
  late final SoundCues _cues;
  late final StreamSubscription<GameEvent> _toastSub;
  final _focus = FocusNode(debugLabel: 'display');
  String? _toast;
  Timer? _toastTimer;
  bool _dialogOpen = false;

  /// Current stage for [MediaStage]; updated before the UI rebuilds.
  final _mediaStage = ValueNotifier<String>('');

  GameSocket get _socket => widget.socket;

  @override
  void initState() {
    super.initState();
    _cues = SoundCues(_socket.events);
    _socket.addListener(_syncStage);
    _syncStage();
    _ready = true;
    _toastSub = _socket.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _socket.removeListener(_syncStage);
    _modifierTimer?.cancel();
    _mediaStage.dispose();
    _cues.dispose();
    _toastSub.cancel();
    _toastTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  /// Question ids whose modifier reveal was already shown.
  final _shownModifiers = <int>{};
  QuestionView? _modifierShown;
  bool _ready = false; // setState is not allowed during initState
  Timer? _modifierTimer;

  void _syncStage() {
    final v = _socket.view;
    if (v == null) return;
    _maybeRevealModifier(v);
    final overlay = _modifierShown;
    // While the reveal covers the screen, the question's media waits.
    _mediaStage.value = overlay != null ? 'modifier-${overlay.id}' : stageKeyOf(v);
  }

  /// A special cell just opened: full-screen reveal for a few seconds, once
  /// per question (the `modifier` event only adds the sound).
  void _maybeRevealModifier(GameView v) {
    final q = v.question;
    const phases = {Phase.catTransfer, Phase.auction, Phase.question, Phase.answering};
    if (q == null || q.modifier == null || !phases.contains(v.phase) || _shownModifiers.contains(q.id)) {
      if (_modifierShown != null && (q == null || q.id != _modifierShown!.id || !phases.contains(v.phase))) {
        _endModifierReveal();
      }
      return;
    }
    _shownModifiers.add(q.id);
    _modifierTimer?.cancel();
    _modifierShown = q;
    _modifierTimer = Timer(const Duration(milliseconds: 3200), _endModifierReveal);
    if (mounted && _ready) setState(() {});
  }

  void _endModifierReveal() {
    _modifierTimer?.cancel();
    if (_modifierShown == null) return;
    _modifierShown = null;
    final v = _socket.view;
    if (v != null) _mediaStage.value = stageKeyOf(v);
    if (mounted && _ready) setState(() {});
  }

  void _onEvent(GameEvent e) {
    if (e.kind != GameEventKind.scoreAdjusted) return;
    final p = _socket.view?.playerById(e.playerId);
    final d = e.delta ?? 0;
    _showToast('Счёт изменён: ${p?.name ?? 'игрок'} ${d >= 0 ? '+' : ''}$d');
  }

  void _showToast(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Future<void> _openMenu() async {
    if (_dialogOpen) return;
    _dialogOpen = true;
    final choice = await showDialog<_MenuChoice>(
      context: context,
      barrierColor: const Color(0xCC070B1F),
      builder: (context) => _MenuDialog(server: _socket.base, game: _socket.view?.game),
    );
    _dialogOpen = false;
    if (choice == _MenuChoice.changeGame) {
      widget.onChangeGame();
    } else if (choice == _MenuChoice.changeServer) {
      widget.onChangeServer();
    } else if (mounted) {
      _focus.requestFocus();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keys = {
      LogicalKeyboardKey.contextMenu,
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.gameButtonStart,
      LogicalKeyboardKey.gameButtonA,
    };
    if (keys.contains(event.logicalKey)) {
      _openMenu();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _openMenu();
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: StageBackground(
            child: ServerBase(
              base: _socket.base,
              child: MediaStage(
                stage: _mediaStage,
                child: ListenableBuilder(listenable: _socket, builder: (context, _) => _body(context)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final view = _socket.view;
    if (view == null) return _Waiting(socket: _socket);

    final showStrip = switch (view.phase) {
      Phase.lobby || Phase.roundEnd || Phase.finished => false,
      _ => true,
    };
    final opening = view.phase == Phase.question || view.phase == Phase.answering;
    return Stack(
      children: [
        Column(
          children: [
            TopBar(view: view, status: _socket.status, server: _socket.base),
            Expanded(
              child: AnimatedSwitcher(
                duration: opening ? AppTheme.open(context) : AppTheme.phase(context),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(
                    // A cell "opens" into the question: grow from small.
                    scale: Tween(begin: opening ? 0.6 : 0.96, end: 1.0).animate(anim),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(key: ValueKey(stageKeyOf(view)), child: _stage(view)),
              ),
            ),
            if (showStrip) ScoreboardStrip(view: view),
          ],
        ),
        if (_modifierShown != null)
          Positioned.fill(
            child: ModifierReveal(key: ValueKey('mod-${_modifierShown!.id}'), view: view, question: _modifierShown!),
          ),
        if (_socket.status != SocketStatus.connected)
          Positioned(
            top: 96,
            left: 0,
            right: 0,
            child: Center(child: _OfflineBanner(socket: _socket)),
          ),
        if (_toast != null)
          Positioned(
            bottom: 160,
            left: 0,
            right: 0,
            child: Center(child: _Toast(text: _toast!)),
          ),
      ],
    );
  }

  Widget _stage(GameView v) {
    final q = v.question;
    switch (v.phase) {
      case Phase.lobby:
        return LobbyView(view: v);
      case Phase.board:
        return BoardView(view: v);
      case Phase.catTransfer:
        if (q == null) return BoardView(view: v);
        return CatTransferView(view: v, question: q);
      case Phase.auction:
        if (q == null) return BoardView(view: v);
        return AuctionStageView(view: v, question: q);
      case Phase.question || Phase.answering || Phase.reveal:
        if (q == null) return BoardView(view: v);
        return QuestionStage(view: v, question: q, server: _socket.base, clock: _socket.clock);
      case Phase.roundEnd:
        return RoundEndView(view: v);
      case Phase.finalThemes:
        return FinalThemesView(view: v);
      case Phase.finalBets:
        return FinalBetsView(view: v);
      case Phase.finalQuestion:
        if (q == null) return FinalBetsView(view: v);
        return FinalQuestionView(view: v, question: q, server: _socket.base, clock: _socket.clock);
      case Phase.finalJudging:
        return FinalJudgingView(view: v);
      case Phase.finalReveal:
        if (q == null) return FinalJudgingView(view: v);
        return FinalRevealView(view: v, question: q, server: _socket.base);
      case Phase.finished:
        return FinishedView(view: v);
    }
  }
}

/// Before the first `state`: connecting / retrying to the saved server.
class _Waiting extends StatelessWidget {
  const _Waiting({required this.socket});

  final GameSocket socket;

  @override
  Widget build(BuildContext context) {
    final offline = socket.status == SocketStatus.offline;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('СВОЯ ИГРА', style: AppText.displayStyle(72, color: AppColors.gold)),
          const SizedBox(height: 48),
          if (!offline)
            const SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(strokeWidth: 5, color: AppColors.accent),
            ),
          const SizedBox(height: 32),
          Text(
            offline ? 'Сервер недоступен' : 'Подключение…',
            style: AppText.bodyStyle(40, weight: FontWeight.w600, color: offline ? AppColors.danger : AppColors.text),
          ),
          const SizedBox(height: 12),
          Text(ServerAddress.label(socket.base), style: AppText.monoStyle(32)),
          if (offline) ...[
            const SizedBox(height: 12),
            _RetryCountdown(
              socket: socket,
              style: AppText.bodyStyle(28, color: AppColors.textMuted),
            ),
          ],
          const SizedBox(height: 48),
          Text('Назад или ОК — сменить игру или сервер', style: AppText.bodyStyle(26, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.socket});

  final GameSocket socket;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: AppColors.danger, width: 2),
    ),
    child: socket.status == SocketStatus.connecting
        ? Text('Переподключение…', style: AppText.bodyStyle(28, weight: FontWeight.w600))
        : _RetryCountdown(
            socket: socket,
            style: AppText.bodyStyle(28, weight: FontWeight.w600),
          ),
  );
}

/// "Нет связи — повтор через N с", ticking once a second.
class _RetryCountdown extends StatefulWidget {
  const _RetryCountdown({required this.socket, required this.style});

  final GameSocket socket;
  final TextStyle style;

  @override
  State<_RetryCountdown> createState() => _RetryCountdownState();
}

class _RetryCountdownState extends State<_RetryCountdown> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final at = widget.socket.retryAt;
    final secs = at == null ? 0 : (at.difference(DateTime.now()).inMilliseconds / 1000).ceil().clamp(0, 99);
    return Text('Нет связи — повтор через $secs с', style: widget.style);
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
    decoration: BoxDecoration(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.accent),
      boxShadow: AppColors.accentGlow,
    ),
    child: Text(text, style: AppText.bodyStyle(30, weight: FontWeight.w600)),
  );
}

enum _MenuChoice { resume, changeGame, changeServer }

class _MenuDialog extends StatelessWidget {
  const _MenuDialog({required this.server, required this.game});

  final Uri server;
  final GameRef? game;

  @override
  Widget build(BuildContext context) {
    final g = game;
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              g == null || g.title.isEmpty ? 'Игра' : g.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.displayStyle(40),
            ),
            const SizedBox(height: 12),
            Text(
              '${g?.pin == null ? '' : 'PIN ${g!.pin}  ·  '}${ServerAddress.label(server)}',
              style: AppText.monoStyle(30, color: AppColors.accent),
            ),
            const SizedBox(height: 40),
            FocusTraversalGroup(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TvButton(
                    autofocus: true,
                    icon: Icons.play_arrow,
                    label: 'Продолжить показ',
                    onPressed: () => Navigator.of(context).pop(_MenuChoice.resume),
                  ),
                  const SizedBox(width: 24),
                  TvButton(
                    icon: Icons.dialpad,
                    label: 'Сменить игру',
                    onPressed: () => Navigator.of(context).pop(_MenuChoice.changeGame),
                  ),
                  const SizedBox(width: 24),
                  TvButton(
                    kind: TvButtonKind.danger,
                    icon: Icons.swap_horiz,
                    label: 'Сменить сервер',
                    onPressed: () => Navigator.of(context).pop(_MenuChoice.changeServer),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
