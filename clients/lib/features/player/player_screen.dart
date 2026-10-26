import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/models.dart';
import '../../data/socket.dart';
import '../avatar/avatar.dart';
import '../avatar/avatar_editor.dart';
import '../game/blocks_view.dart';
import '../game/board.dart';
import '../game/final_panel.dart';
import '../game/question_panel.dart';
import '../game/scoreboard.dart';
import '../game/session.dart';
import '../game/special.dart';
import 'buzzer.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final socket = context.watch<GameSocket>();
    final session = context.read<Session>();
    final view = socket.view;
    final me = view?.me;
    return Scaffold(
      appBar: AppBar(
        title: Text(view?.round?.name ?? view?.pack?.title ?? 'Своя игра', overflow: TextOverflow.ellipsis),
        actions: [
          if (me != null)
            IconButton(
              tooltip: 'Мой аватар',
              icon: Avatar(name: me.name, url: view?.player(me.id)?.avatarUrl, size: 30),
              onPressed: () => editMyAvatar(context, session.api, hasAvatar: view?.player(me.id)?.avatarUrl != null),
            ),
          ...sessionActions(context),
        ],
      ),
      body: StageBackground(
        child: SafeArea(
          top: false,
          child: view == null || me == null
              ? const WaitingForState()
              : _PlayerBody(view: view, me: me, socket: socket, session: session),
        ),
      ),
    );
  }
}

class _PlayerBody extends StatelessWidget {
  const _PlayerBody({required this.view, required this.me, required this.socket, required this.session});

  final GameView view;
  final MeView me;
  final GameSocket socket;
  final Session session;

  @override
  Widget build(BuildContext context) {
    // Solo questions (cat / auction / no risk) have no buttons; the solo
    // player may still type an answer.
    final solo = view.soloPlayerId != null;
    final showBuzzer = (me.buzzer != BuzzerState.hidden && !solo) || me.canType;
    return LayoutBuilder(builder: (context, c) {
      final landscape = c.maxWidth > c.maxHeight && c.maxWidth >= 560;
      final main = Column(children: [
        Scoreboard(view: view, meId: me.id),
        const Divider(),
        Expanded(child: _content(context)),
      ]);
      if (!showBuzzer) return main;
      if (landscape) {
        final panelW = c.maxWidth * 0.38;
        return Row(children: [
          Expanded(child: main),
          const VerticalDivider(width: 1),
          SizedBox(
            width: panelW,
            child: _BuzzerPanel(
              me: me,
              socket: socket,
              size: math.max(140.0, math.min(panelW * 0.75, c.maxHeight * 0.62)),
              buzzer: !solo,
            ),
          ),
        ]);
      }
      final size = math.max(140.0, math.min(c.maxWidth * 0.6, c.maxHeight * 0.38));
      return Column(children: [
        Expanded(child: main),
        _BuzzerPanel(me: me, socket: socket, size: size, buzzer: !solo),
      ]);
    });
  }

  Widget _content(BuildContext context) {
    switch (view.phase) {
      case Phase.lobby:
        return EmptyState(
          icon: Icons.hourglass_top,
          title: 'Ожидаем начала игры',
          subtitle: 'Вы в игре как «${me.name}»${view.pack == null ? '' : '\nПакет: ${view.pack!.title}'}',
        );
      case Phase.board:
        final chooser = view.player(view.chooserId);
        return Column(children: [
          _Banner(
            text: me.canSelect ? 'Ваш ход — выберите вопрос' : 'Выбирает: ${chooser?.name ?? '—'}',
            gold: me.canSelect,
          ),
          Expanded(
            child: GameBoard(
              board: view.board ?? const [],
              onSelect: me.canSelect ? (q) => socket.command('select_question', {'questionId': q.id}) : null,
            ),
          ),
        ]);
      case Phase.catTransfer:
        return CatTransferPanel(
          view: view,
          canGive: me.canGiveCat,
          meId: me.id,
          onGive: (id) => socket.command('give_cat', {'playerId': id}),
        );
      case Phase.auction:
        return AuctionPanel(view: view, socket: socket, me: me);
      case Phase.finalThemes:
      case Phase.finalBets:
      case Phase.finalQuestion:
      case Phase.finalJudging:
      case Phase.finalReveal:
        return FinalPanel(view: view, socket: socket, mode: MediaMode.player, resolveUrl: session.api.absolute, me: me);
      case Phase.question:
      case Phase.answering:
      case Phase.reveal:
        return QuestionPanel(
          view: view,
          mode: MediaMode.player,
          resolveUrl: session.api.absolute,
          now: () => socket.serverNow,
          footer: _questionStatus(),
        );
      case Phase.roundEnd:
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('Раунд завершён', textAlign: TextAlign.center, style: AppText.display(24)),
          if (view.round != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 16),
              child: Text(view.round!.name, textAlign: TextAlign.center, style: AppText.muted(14)),
            ),
          Standings(players: view.players, meId: me.id),
        ]);
      case Phase.finished:
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('Игра окончена', textAlign: TextAlign.center, style: AppText.display(28, color: AppColors.gold)),
          const SizedBox(height: 16),
          Standings(players: view.players, meId: me.id),
        ]);
    }
  }

  Widget? _questionStatus() {
    final answering = view.player(view.answeringPlayerId);
    final r = view.lastResult;
    String? text;
    Color color = AppColors.textMuted;
    PlayerView? who;
    final solo = soloLine(view, me.id);
    if (view.phase == Phase.question && solo != null) {
      text = solo;
      color = AppColors.accent;
      who = view.player(view.soloPlayerId);
    } else if (view.phase == Phase.answering && answering != null) {
      text = answering.id == me.id ? 'Вы отвечаете' : 'Отвечает: ${answering.name}';
      color = AppColors.accent;
      who = answering;
    } else if (view.phase == Phase.reveal && r != null) {
      final who = view.player(r.playerId)?.name ?? '';
      text = r.correct ? '$who — верно, +${formatScore(r.delta)}' : '$who — неверно${r.delta != 0 ? ', ${formatScore(r.delta)}' : ''}';
      color = r.correct ? AppColors.success : AppColors.danger;
    } else if (view.phase == Phase.reveal) {
      text = 'Никто не ответил';
    }
    if (text == null) return null;
    if (who != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: AnsweringLine(text: text, name: who.name, url: who.avatarUrl, color: color),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text(text, textAlign: TextAlign.center, style: AppText.body(16, weight: FontWeight.w600, color: color)),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, this.gold = false});

  final String text;
  final bool gold;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: gold ? AppText.display(16, weight: FontWeight.w600, color: AppColors.gold) : AppText.muted(14),
        ),
      );
}

class _BuzzerPanel extends StatelessWidget {
  const _BuzzerPanel({required this.me, required this.socket, required this.size, this.buzzer = true});

  final MeView me;
  final GameSocket socket;
  final double size;
  final bool buzzer;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (buzzer) Buzzer(me: me, now: () => socket.serverNow, size: size, onPress: () => socket.command('buzz')),
        if (me.canType) ...[
          const SizedBox(height: 16),
          _TypedAnswer(socket: socket),
        ],
      ]),
    );
  }
}

/// Optional typed answer; sent debounced while typing and on submit (last wins).
class _TypedAnswer extends StatefulWidget {
  const _TypedAnswer({required this.socket});

  final GameSocket socket;

  @override
  State<_TypedAnswer> createState() => _TypedAnswerState();
}

class _TypedAnswerState extends State<_TypedAnswer> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  String _sent = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _send() {
    _debounce?.cancel();
    final text = _ctrl.text.trim();
    if (text == _sent) return;
    if (widget.socket.command('submit_answer', {'text': text})) setState(() => _sent = text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _ctrl,
        maxLength: 200,
        autofocus: false,
        textInputAction: TextInputAction.send,
        decoration: InputDecoration(
          labelText: 'Ответ (необязательно)',
          suffixIcon: IconButton(icon: const Icon(Icons.send), onPressed: _send),
        ),
        onChanged: (_) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 600), _send);
        },
        onSubmitted: (_) => _send(),
      ),
      if (_sent.isNotEmpty) Text('Ведущий видит: «$_sent»', style: AppText.muted(12)),
    ]);
  }
}
