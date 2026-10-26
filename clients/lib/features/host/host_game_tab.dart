import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/models.dart';
import '../../data/socket.dart';
import '../avatar/avatar.dart';
import '../connect/server_screen.dart';
import '../game/blocks_view.dart';
import '../game/board.dart';
import '../game/final_panel.dart';
import '../game/question_panel.dart';
import '../game/scoreboard.dart';
import '../game/session.dart';
import '../game/special.dart';
import 'host_screen.dart';

/// Host game control: every host command of the protocol, by phase.
class HostGameTab extends StatelessWidget {
  const HostGameTab({super.key});

  @override
  Widget build(BuildContext context) {
    final socket = context.watch<GameSocket>();
    final view = socket.view;
    if (view == null) return const WaitingForState();
    return Column(children: [
      Scoreboard(view: view, onTap: (p) => showPlayerActions(context, view, p)),
      _PhaseLine(view: view),
      const Divider(),
      Expanded(child: _content(context, view, socket)),
      _ActionBar(view: view, socket: socket),
    ]);
  }

  Widget _content(BuildContext context, GameView view, GameSocket socket) {
    final session = context.read<Session>();
    switch (view.phase) {
      case Phase.lobby:
        return EmptyState(
          icon: view.pack == null ? Icons.hourglass_top : Icons.play_circle_outline,
          title: view.pack == null ? 'Ожидаем, пока администратор выберет пак' : view.pack!.title,
          subtitle: view.pack == null
              ? 'Игроков: ${view.players.length}.${view.game.pin == null ? '' : ' PIN игры: ${formatPin(view.game.pin)}'}'
              : 'Игроков: ${view.players.length}. Нажмите «Начать игру», когда все будут готовы.',
        );
      case Phase.board:
        return GameBoard(
          board: view.board ?? const [],
          onSelect: (q) => socket.command('select_question', {'questionId': q.id}),
        );
      case Phase.catTransfer:
        // The host may give the cat on behalf of the chooser.
        return CatTransferPanel(
          view: view,
          canGive: true,
          onGive: (id) => socket.command('give_cat', {'playerId': id}),
        );
      case Phase.auction:
        return AuctionPanel(view: view, socket: socket, hostControls: true);
      case Phase.finalThemes:
      case Phase.finalBets:
      case Phase.finalQuestion:
      case Phase.finalJudging:
      case Phase.finalReveal:
        return FinalPanel(view: view, socket: socket, mode: MediaMode.host, resolveUrl: session.api.absolute, host: true);
      case Phase.question:
      case Phase.answering:
      case Phase.reveal:
        return QuestionPanel(
          view: view,
          mode: MediaMode.host,
          resolveUrl: session.api.absolute,
          now: () => socket.serverNow,
          footer: _QuestionFooter(view: view),
        );
      case Phase.roundEnd:
      case Phase.finished:
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text(
            view.phase == Phase.finished ? 'Игра окончена' : 'Раунд завершён',
            textAlign: TextAlign.center,
            style: AppText.display(24, color: view.phase == Phase.finished ? AppColors.gold : AppColors.text),
          ),
          const SizedBox(height: 16),
          Standings(players: view.players),
        ]);
    }
  }
}

class _PhaseLine extends StatelessWidget {
  const _PhaseLine({required this.view});

  final GameView view;

  @override
  Widget build(BuildContext context) {
    final chooser = view.player(view.chooserId);
    final round = view.round;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(children: [
        _Pill(text: view.phase.label),
        if (round != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Раунд ${round.index + 1}/${round.total} · ${round.name}',
              overflow: TextOverflow.ellipsis,
              style: AppText.muted(13),
            ),
          ),
        ],
        const Spacer(),
        if (chooser != null && view.started)
          Flexible(
            child: Text(
              'Выбирает: ${chooser.name}',
              overflow: TextOverflow.ellipsis,
              style: AppText.body(13, color: AppColors.gold),
            ),
          ),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(text, style: AppText.body(12, weight: FontWeight.w600)),
      );
}

/// Under the question: who answers, typed answer, last result, attempted players.
class _QuestionFooter extends StatelessWidget {
  const _QuestionFooter({required this.view});

  final GameView view;

  @override
  Widget build(BuildContext context) {
    final answering = view.player(view.answeringPlayerId);
    final attempted = view.attemptedPlayerIds.map((id) => view.player(id)?.name).whereType<String>().toList();
    final r = view.lastResult;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (view.phase == Phase.question && soloLine(view, null) != null)
          AnsweringLine(
            text: soloLine(view, null)!,
            name: view.player(view.soloPlayerId)?.name,
            url: view.player(view.soloPlayerId)?.avatarUrl,
          ),
        if (view.phase == Phase.answering && answering != null)
          AnsweringLine(text: 'Отвечает: ${answering.name}', name: answering.name, url: answering.avatarUrl),
        if (view.phase == Phase.answering) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              (view.typedAnswer ?? '').isEmpty ? 'Игрок ничего не напечатал' : '«${view.typedAnswer}»',
              style: (view.typedAnswer ?? '').isEmpty ? AppText.muted(14) : AppText.body(16, weight: FontWeight.w500),
            ),
          ),
        ],
        if (view.phase == Phase.reveal && r != null)
          Text(
            '${view.player(r.playerId)?.name ?? ''}: ${r.correct ? 'верно' : 'неверно'} (${r.delta >= 0 ? '+' : ''}${formatScore(r.delta)})',
            style: AppText.body(16, weight: FontWeight.w600, color: r.correct ? AppColors.success : AppColors.danger),
          ),
        if (view.phase == Phase.reveal && r == null) Text('Никто не ответил', style: AppText.muted(14)),
        if (attempted.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Уже отвечали: ${attempted.join(', ')}', style: AppText.muted(13)),
        ],
      ]),
    );
  }
}

/// Primary + secondary actions for the current phase.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.view, required this.socket});

  final GameView view;
  final GameSocket socket;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    void cmd(String type, [Map<String, dynamic> data = const {}]) => socket.command(type, data);

    switch (view.phase) {
      case Phase.lobby:
        children.add(FilledButton.icon(
          icon: const Icon(Icons.play_arrow),
          onPressed: view.pack == null ? null : () => cmd('start_game'),
          label: const Text('Начать игру'),
        ));
      case Phase.board:
        children.add(Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => pickRound(context, view), child: const Text('Раунд…'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(onPressed: () => cmd('next_round'), child: const Text('След. раунд'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(onPressed: () => finishGame(context), child: const Text('Завершить'))),
        ]));
      case Phase.catTransfer:
        children.add(Text('Выберите, кому отдать кота в мешке', textAlign: TextAlign.center, style: AppText.muted(13)));
      case Phase.auction:
        children.add(Text('Торги идут; закрыть их можно кнопкой выше', textAlign: TextAlign.center, style: AppText.muted(13)));
      case Phase.finalThemes:
        children.add(Text('Финалисты убирают темы; можно убрать тему за текущего игрока',
            textAlign: TextAlign.center, style: AppText.muted(13)));
      case Phase.finalBets:
        children.add(FilledButton.icon(
          icon: const Icon(Icons.lock_clock),
          onPressed: () => cmd('final_close_bets'),
          label: const Text('Закрыть ставки'),
        ));
      case Phase.finalQuestion:
        children.add(FilledButton.icon(
          icon: const Icon(Icons.timer_off),
          onPressed: () => cmd('final_close_answers'),
          label: const Text('Закрыть ответы'),
        ));
      case Phase.finalJudging:
        children.add(Text('Оцените ответ каждого финалиста', textAlign: TextAlign.center, style: AppText.muted(13)));
      case Phase.finalReveal:
        children.add(FilledButton.icon(
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => cmd('continue'),
          label: const Text('Продолжить'),
        ));
      case Phase.question:
        children.add(OutlinedButton.icon(
          icon: const Icon(Icons.skip_next),
          onPressed: () => cmd('skip_question'),
          label: const Text('Пропустить вопрос'),
        ));
      case Phase.answering:
        final q = view.question;
        final answerText = q?.answerBlocks
                ?.where((b) => b.type == BlockType.text)
                .map((b) => b.markdown)
                .join(' ') ??
            '';
        children.addAll([
          if (answerText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Ответ: $answerText',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(15, weight: FontWeight.w600, color: AppColors.success),
              ),
            ),
          Row(children: [
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: AppColors.bg,
                  minimumSize: const Size(48, 56),
                ),
                onPressed: () => cmd('judge', {'correct': true}),
                child: Text('Верно +${q?.stake ?? 0}'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: AppColors.text,
                  minimumSize: const Size(48, 56),
                ),
                onPressed: () => cmd('judge', {'correct': false}),
                child: const Text('Неверно'),
              ),
            ),
          ]),
          TextButton(onPressed: () => cmd('skip_question'), child: const Text('Пропустить вопрос')),
        ]);
      case Phase.reveal:
        children.add(FilledButton.icon(
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => cmd('continue'),
          label: const Text('Продолжить'),
        ));
      case Phase.roundEnd:
        children.addAll([
          FilledButton.icon(
            icon: const Icon(Icons.skip_next),
            onPressed: () => cmd('next_round'),
            label: const Text('Следующий раунд'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => pickRound(context, view), child: const Text('Раунд…'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: () => finishGame(context), child: const Text('Завершить'))),
          ]),
        ]);
      case Phase.finished:
        children.add(FilledButton.icon(
          icon: const Icon(Icons.restart_alt),
          onPressed: () => resetGame(context),
          label: const Text('Новая игра'),
        ));
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// `set_round`: choose a round index.
Future<void> pickRound(BuildContext context, GameView view) async {
  final total = view.round?.total ?? 0;
  if (total == 0) return;
  final socket = context.read<GameSocket>();
  final index = await showDialog<int>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Перейти к раунду'),
      children: [
        for (var i = 0; i < total; i++)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, i),
            child: Text(
              'Раунд ${i + 1}${i == view.round?.index ? ' (текущий)' : ''}',
              style: AppText.body(16, weight: i == view.round?.index ? FontWeight.w600 : FontWeight.w400),
            ),
          ),
      ],
    ),
  );
  if (index != null) socket.command('set_round', {'index': index});
}

/// Host actions on a player chip: set chooser, kick.
Future<void> showPlayerActions(BuildContext context, GameView view, PlayerView p) async {
  final socket = context.read<GameSocket>();
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          title: Text(p.name, style: AppText.display(16, weight: FontWeight.w600)),
          subtitle: Text('Очки: ${formatScore(p.score)} · ${p.connected ? 'в сети' : 'не в сети'}'),
        ),
        const Divider(),
        if (view.started)
          ListTile(
            leading: const Icon(Icons.touch_app, color: AppColors.gold),
            title: const Text('Сделать выбирающим'),
            enabled: view.chooserId != p.id,
            onTap: () => Navigator.pop(ctx, 'chooser'),
          ),
        ListTile(
          leading: const Icon(Icons.person_remove, color: AppColors.danger),
          title: const Text('Исключить из игры'),
          onTap: () => Navigator.pop(ctx, 'kick'),
        ),
      ]),
    ),
  );
  if (!context.mounted) return;
  if (action == 'chooser') socket.command('set_chooser', {'playerId': p.id});
  if (action == 'kick' &&
      await confirm(context, 'Исключить ${p.name}?', message: 'Игрок будет отключён и потеряет очки.', ok: 'Исключить', danger: true)) {
    socket.command('kick_player', {'playerId': p.id});
  }
}
