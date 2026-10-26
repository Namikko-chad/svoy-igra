import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/socket.dart';
import '../avatar/avatar.dart';
import 'blocks_view.dart';
import 'question_panel.dart';
import 'timer_bar.dart';

/// Final round (protocol §4.6) for every role: themes → bets → question →
/// judging → reveal. [me] is set for players; [host] enables the host's
/// commands (remove on behalf, close bets/answers, judge).
class FinalPanel extends StatelessWidget {
  const FinalPanel({
    super.key,
    required this.view,
    required this.socket,
    required this.mode,
    required this.resolveUrl,
    this.me,
    this.host = false,
  });

  final GameView view;
  final GameSocket socket;
  final MediaMode mode;
  final String Function(String) resolveUrl;
  final MeView? me;
  final bool host;

  @override
  Widget build(BuildContext context) {
    final f = view.finalView;
    if (f == null) return const SizedBox.shrink();
    switch (view.phase) {
      case Phase.finalThemes:
        return FinalThemesPanel(view: view, me: me, host: host, socket: socket);
      case Phase.finalBets:
        return ListView(padding: const EdgeInsets.all(16), children: [
          // The server sends the remaining theme as question.categoryName.
          _ThemeTitle(
            name: (view.question?.categoryName.isNotEmpty ?? false)
                ? view.question!.categoryName
                : (f.remainingTheme?.name ?? ''),
          ),
          const SizedBox(height: 16),
          if (me != null) FinalBetBox(me: me!, participant: f.participant(me!.id), socket: socket),
          const SizedBox(height: 16),
          FinalResults(view: view, socket: socket, host: host),
        ]);
      case Phase.finalQuestion:
      case Phase.finalJudging:
      case Phase.finalReveal:
        return QuestionPanel(
          view: view,
          mode: mode,
          resolveUrl: resolveUrl,
          now: () => socket.serverNow,
          footer: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (view.phase == Phase.finalQuestion && f.answerEndsAt != null) ...[
              const SizedBox(height: 12),
              FinalCountdown(
                deadline: f.answerEndsAt!,
                start: f.answerStartsAt,
                now: () => socket.serverNow,
              ),
            ],
            if (me != null && me!.finalist && view.phase == Phase.finalQuestion) ...[
              const SizedBox(height: 16),
              FinalAnswerBox(me: me!, participant: f.participant(me!.id), socket: socket),
            ],
            const SizedBox(height: 16),
            FinalResults(view: view, socket: socket, host: host),
          ]),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _ThemeTitle extends StatelessWidget {
  const _ThemeTitle({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text('ФИНАЛ', style: AppText.display(14, color: AppColors.textMuted)),
        const SizedBox(height: 4),
        Text(name, textAlign: TextAlign.center, style: AppText.display(26, color: AppColors.gold)),
      ]);
}

/// `final_themes`: finalists remove themes in turn; the remover (or the host on
/// their behalf) taps a theme.
class FinalThemesPanel extends StatelessWidget {
  const FinalThemesPanel({super.key, required this.view, required this.socket, this.me, this.host = false});

  final GameView view;
  final GameSocket socket;
  final MeView? me;
  final bool host;

  @override
  Widget build(BuildContext context) {
    final f = view.finalView!;
    final remover = view.player(f.removerId);
    final canRemove = host || (me?.canRemoveTheme ?? false);
    final line = me?.canRemoveTheme == true
        ? 'Ваш ход: уберите тему'
        : (host ? 'Убирает ${remover?.name ?? '—'} (можно убрать за него)' : 'Убирает тему: ${remover?.name ?? '—'}');
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('ФИНАЛ', textAlign: TextAlign.center, style: AppText.display(22, color: AppColors.gold)),
      const SizedBox(height: 8),
      Text(line,
          textAlign: TextAlign.center,
          style: AppText.body(15, weight: FontWeight.w600, color: me?.canRemoveTheme == true ? AppColors.accent : AppColors.text)),
      const SizedBox(height: 16),
      for (final t in f.themes)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: t.removed ? AppColors.cellPlayed : AppColors.cellBottom,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              key: ValueKey('theme:${t.id}'),
              borderRadius: BorderRadius.circular(12),
              onTap: canRemove && !t.removed
                  ? () {
                      HapticFeedback.selectionClick();
                      socket.command('final_remove_theme', {'themeId': t.id});
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      t.name.toUpperCase(),
                      style: AppText.body(15, weight: FontWeight.w600, color: t.removed ? AppColors.textMuted : AppColors.text)
                          .copyWith(decoration: t.removed ? TextDecoration.lineThrough : null),
                    ),
                  ),
                  if (canRemove && !t.removed) const Icon(Icons.close, color: AppColors.danger),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// `final_bets` for a finalist: secret bet 1..score (may re-bet until closed).
class FinalBetBox extends StatefulWidget {
  const FinalBetBox({super.key, required this.me, required this.participant, required this.socket});

  final MeView me;
  final FinalParticipant? participant;
  final GameSocket socket;

  @override
  State<FinalBetBox> createState() => _FinalBetBoxState();
}

class _FinalBetBoxState extends State<FinalBetBox> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _bet() {
    final n = int.tryParse(_ctrl.text.trim());
    final max = widget.me.score;
    if (n == null || n < 1 || n > max) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ставка — от 1 до ${formatScore(max)}')));
      return;
    }
    HapticFeedback.mediumImpact();
    widget.socket.command('final_bet', {'amount': n});
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    if (!me.finalist) {
      return Text('Вы не участвуете в финале (нужны очки больше нуля)',
          textAlign: TextAlign.center, style: AppText.muted(14));
    }
    final p = widget.participant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Ваша ставка (1…${formatScore(me.score)})', style: AppText.body(14, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (me.canBet) ...[
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(hintText: 'Ставка'),
                  onSubmitted: (_) => _bet(),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () => _ctrl.text = '${me.score}', child: const Text('Всё')),
            ]),
            const SizedBox(height: 8),
            FilledButton(onPressed: _bet, child: Text(p?.hasBet == true ? 'Изменить ставку' : 'Сделать ставку')),
          ],
          if (p?.hasBet == true)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Ставка принята${p!.bet != null ? ': ${formatScore(p.bet!)}' : ''}',
                textAlign: TextAlign.center,
                style: AppText.body(14, weight: FontWeight.w600, color: AppColors.success),
              ),
            ),
        ]),
      ),
    );
  }
}

/// `final_question` for a finalist: the written answer (sent debounced; last wins).
class FinalAnswerBox extends StatefulWidget {
  const FinalAnswerBox({super.key, required this.me, required this.participant, required this.socket});

  final MeView me;
  final FinalParticipant? participant;
  final GameSocket socket;

  @override
  State<FinalAnswerBox> createState() => _FinalAnswerBoxState();
}

class _FinalAnswerBoxState extends State<FinalAnswerBox> {
  late final _ctrl = TextEditingController(text: widget.participant?.answer ?? '');
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _send() {
    _debounce?.cancel();
    widget.socket.command('final_answer', {'text': _ctrl.text.trim()});
  }

  @override
  Widget build(BuildContext context) {
    final can = widget.me.canAnswerFinal;
    final p = widget.participant;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _ctrl,
        enabled: can,
        maxLength: 200,
        textInputAction: TextInputAction.send,
        decoration: InputDecoration(
          labelText: can ? 'Ваш ответ' : 'Время вышло',
          suffixIcon: can ? IconButton(icon: const Icon(Icons.send), onPressed: _send) : null,
        ),
        onChanged: (_) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 600), _send);
        },
        onSubmitted: (_) => _send(),
      ),
      if (p?.hasAnswer == true)
        Text('Ответ записан${p!.answer != null ? ': «${p.answer}»' : ''}', style: AppText.body(12, color: AppColors.success)),
    ]);
  }
}

/// Countdown to [deadline]; the bar runs from [start] (`answerStartsAt`).
/// Without it (older server) the time left when first shown is the full bar.
class FinalCountdown extends StatefulWidget {
  const FinalCountdown({super.key, required this.deadline, required this.now, this.start});

  final int deadline;
  final int? start;
  final int Function() now;

  @override
  State<FinalCountdown> createState() => _FinalCountdownState();
}

class _FinalCountdownState extends State<FinalCountdown> {
  late int _fallback = widget.now();

  @override
  void didUpdateWidget(FinalCountdown old) {
    super.didUpdateWidget(old);
    if (old.deadline != widget.deadline) _fallback = widget.now();
  }

  @override
  Widget build(BuildContext context) =>
      TimerBar(start: widget.start ?? _fallback, deadline: widget.deadline, now: widget.now, label: 'Ответ');
}

/// Finalists: bet / answer / result as far as the receiver may see them. The
/// host judges here during `final_judging`.
class FinalResults extends StatelessWidget {
  const FinalResults({super.key, required this.view, required this.socket, this.host = false});

  final GameView view;
  final GameSocket socket;
  final bool host;

  @override
  Widget build(BuildContext context) {
    final f = view.finalView;
    if (f == null || f.participants.isEmpty) return const SizedBox.shrink();
    final judging = view.phase == Phase.finalJudging;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('ФИНАЛИСТЫ', style: AppText.body(12, weight: FontWeight.w600, color: AppColors.textMuted)),
      const SizedBox(height: 8),
      for (final p in f.participants)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            key: ValueKey('finalist:${p.playerId}'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: p.correct == null ? AppColors.border : (p.correct! ? AppColors.success : AppColors.danger),
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Avatar(name: view.player(p.playerId)?.name ?? '?', url: view.player(p.playerId)?.avatarUrl, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(view.player(p.playerId)?.name ?? '?', style: AppText.body(15, weight: FontWeight.w600)),
                ),
                Text(
                  p.bet != null ? 'ставка ${formatScore(p.bet!)}' : (p.hasBet ? 'ставка сделана' : 'нет ставки'),
                  style: AppText.mono(12, color: p.hasBet ? AppColors.gold : AppColors.textMuted),
                ),
              ]),
              if (view.phase != Phase.finalBets) ...[
                const SizedBox(height: 4),
                Text(
                  p.answer != null
                      ? (p.answer!.isEmpty ? '(пустой ответ)' : '«${p.answer}»')
                      : (p.hasAnswer ? 'ответ записан' : 'ответа нет'),
                  style: p.answer != null ? AppText.body(15) : AppText.muted(13),
                ),
              ],
              if (p.correct != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    p.correct!
                        ? 'Верно${p.bet != null ? ' +${formatScore(p.bet!)}' : ''}'
                        : 'Неверно${p.bet != null ? ' −${formatScore(p.bet!)}' : ''}',
                    style: AppText.body(14, weight: FontWeight.w600, color: p.correct! ? AppColors.success : AppColors.danger),
                  ),
                ),
              if (host && judging && p.correct == null) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: AppColors.bg),
                      onPressed: () => socket.command('final_judge', {'playerId': p.playerId, 'correct': true}),
                      child: const Text('Верно'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: AppColors.text),
                      onPressed: () => socket.command('final_judge', {'playerId': p.playerId, 'correct': false}),
                      child: const Text('Неверно'),
                    ),
                  ),
                ]),
              ],
            ]),
          ),
        ),
    ]);
  }
}
