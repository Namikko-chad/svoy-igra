import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/server_clock.dart';
import '../../../core/widgets/avatar.dart';
import '../../../data/models/block_splitter.dart';
import '../../../data/models/game_view.dart';
import '../stage_key.dart';
import 'blocks_view.dart';

/// "ФИНАЛ" + a subtitle, on top of every final phase.
class _FinalTitle extends StatelessWidget {
  const _FinalTitle({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('ФИНАЛ', style: AppText.displayStyle(64, color: AppColors.gold).copyWith(letterSpacing: 6)),
      const SizedBox(height: 4),
      Text(
        subtitle,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.bodyStyle(34, weight: FontWeight.w500, color: AppColors.textMuted),
      ),
    ],
  );
}

String _name(GameView v, String id) => v.playerById(id)?.name ?? 'Игрок';

/// `final_themes`: theme grid; removed themes struck out; who removes now.
class FinalThemesView extends StatelessWidget {
  const FinalThemesView({super.key, required this.view});

  final GameView view;

  @override
  Widget build(BuildContext context) {
    final f = view.finalView;
    final themes = f?.themes ?? const <FinalTheme>[];
    final remover = view.playerById(f?.removerId);
    final columns = themes.length <= 4 ? 2 : (themes.length <= 9 ? 3 : 4);
    return Padding(
      padding: const EdgeInsets.fromLTRB(96, 0, 96, 16),
      child: Column(
        children: [
          _FinalTitle(subtitle: remover == null ? 'Темы финала' : 'Финалисты убирают темы'),
          const SizedBox(height: 16),
          if (remover != null)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Убирает: ',
                    style: AppText.bodyStyle(40, color: AppColors.textMuted),
                  ),
                  TextSpan(
                    text: remover.name,
                    style: AppText.displayStyle(40, color: AppColors.accent),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 24),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                const gap = 20.0;
                final rows = (themes.length / columns).ceil().clamp(1, 99);
                final w = (c.maxWidth - gap * (columns - 1)) / columns;
                final h = ((c.maxHeight - gap * (rows - 1)) / rows).clamp(40.0, 150.0);
                return Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final t in themes)
                        SizedBox(
                          width: w,
                          height: h,
                          child: _ThemeCard(theme: t),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.theme});

  final FinalTheme theme;

  @override
  Widget build(BuildContext context) {
    final removed = theme.removed;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: removed ? 0.35 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: removed ? null : AppColors.cellGradient,
          color: removed ? AppColors.cellPlayed : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: removed ? AppColors.border : AppColors.cellHover),
        ),
        child: Text(
          theme.name.toUpperCase(),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppText.bodyStyle(32, weight: FontWeight.w600, color: removed ? AppColors.textMuted : AppColors.text)
              .copyWith(
                decoration: removed ? TextDecoration.lineThrough : null,
                decorationColor: AppColors.danger,
                decorationThickness: 3,
              ),
        ),
      ),
    );
  }
}

/// A finalist tile: name, score and a status line (bet/answer ✓, result).
class _FinalistTile extends StatelessWidget {
  const _FinalistTile({
    required this.name,
    required this.score,
    required this.status,
    this.color,
    this.detail,
    this.player,
  });

  final String name;

  /// For the avatar (initials when it has none).
  final PlayerView? player;
  final int score;
  final String status;
  final Color? color;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final c = color;
    return Container(
      width: 400,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: c == null ? AppColors.surface : Color.alphaBlend(c.withValues(alpha: 0.18), AppColors.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c ?? AppColors.border, width: c == null ? 1 : 3),
        boxShadow: c == null ? null : [BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: 24)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(name: player?.name ?? name, url: player?.avatarUrl, size: 64, ring: color),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyStyle(32, weight: FontWeight.w600),
                ),
              ),
              Text(
                '$score',
                style: AppText.displayStyle(32, color: score < 0 ? AppColors.danger : AppColors.gold, tabular: true),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (detail != null)
            Text(
              detail!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.bodyStyle(30, weight: FontWeight.w500, color: AppColors.text),
            ),
          Text(
            status,
            style: AppText.bodyStyle(26, weight: FontWeight.w600, color: c ?? AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

Widget _finalists(List<Widget> tiles) =>
    Wrap(alignment: WrapAlignment.center, spacing: 20, runSpacing: 20, children: tiles);

/// `final_bets`: the remaining theme; who has bet (amounts stay hidden).
class FinalBetsView extends StatelessWidget {
  const FinalBetsView({super.key, required this.view});

  final GameView view;

  @override
  Widget build(BuildContext context) {
    final f = view.finalView;
    // final_bets carries the remaining theme as question.categoryName.
    final fromQuestion = view.question?.categoryName.trim() ?? '';
    final theme = fromQuestion.isNotEmpty ? fromQuestion : f?.remainingTheme?.name;
    final parts = f?.participants ?? const <FinalParticipant>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(96, 0, 96, 16),
      child: Column(
        children: [
          const _FinalTitle(subtitle: 'Финалисты делают ставки'),
          const Spacer(),
          if (theme != null) ...[
            Text(
              'ТЕМА',
              style: AppText.bodyStyle(28, weight: FontWeight.w600, color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            Text(
              theme,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.displayStyle(72, color: AppColors.text),
            ),
          ],
          const Spacer(),
          _finalists([
            for (final p in parts)
              _FinalistTile(
                name: _name(view, p.playerId),
                player: view.playerById(p.playerId),
                score: view.playerById(p.playerId)?.score ?? 0,
                status: p.hasBet ? '✓ ставка сделана' : 'думает…',
                color: p.hasBet ? AppColors.success : null,
              ),
          ]),
          const Spacer(),
        ],
      ),
    );
  }
}

/// `final_question`: the question, a big countdown to `answerEndsAt`, and ✓ per
/// finalist who has answered.
class FinalQuestionView extends StatelessWidget {
  const FinalQuestionView({
    super.key,
    required this.view,
    required this.question,
    required this.server,
    required this.clock,
  });

  final GameView view;
  final QuestionView question;
  final Uri server;
  final ServerClock clock;

  @override
  Widget build(BuildContext context) {
    final f = view.finalView;
    final parts = f?.participants ?? const <FinalParticipant>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(96, 0, 96, 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'ФИНАЛ · ${question.categoryName.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyStyle(
                    32,
                    weight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ).copyWith(letterSpacing: 1.5),
                ),
              ),
              if (f?.answerEndsAt != null)
                FinalCountdown(startsAt: f!.answerStartsAt, endsAt: f.answerEndsAt!, clock: clock),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: BlocksView(
              key: ValueKey('fq-${question.id}'),
              blocks: question.blocks,
              server: server,
              keyPrefix: 'fq${question.id}',
              stage: stageKeyOf(view),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              for (final p in parts)
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 8, 24, 8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: p.hasAnswer ? AppColors.success : AppColors.border,
                      width: p.hasAnswer ? 3 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Avatar(
                        name: _name(view, p.playerId),
                        url: view.playerById(p.playerId)?.avatarUrl,
                        size: 40,
                        ring: p.hasAnswer ? AppColors.success : null,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${p.hasAnswer ? '✓ ' : ''}${_name(view, p.playerId)}',
                        style: AppText.bodyStyle(
                          28,
                          weight: FontWeight.w600,
                          color: p.hasAnswer ? AppColors.success : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Big seconds countdown + ring for the final answer window
/// `answerStartsAt → answerEndsAt`. Without a start (older server) the ring's
/// length is the time left when first seen, rounded up to whole seconds.
class FinalCountdown extends StatefulWidget {
  const FinalCountdown({super.key, this.startsAt, required this.endsAt, required this.clock});

  final int? startsAt;
  final int endsAt;
  final ServerClock clock;

  @override
  State<FinalCountdown> createState() => _FinalCountdownState();
}

class _FinalCountdownState extends State<FinalCountdown> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late int _totalMs;

  @override
  void initState() {
    super.initState();
    _measure();
    _ticker = createTicker((_) => setState(() {}))..start();
  }

  void _measure() {
    final start = widget.startsAt;
    if (start != null && widget.endsAt > start) {
      _totalMs = widget.endsAt - start;
      return;
    }
    final left = widget.endsAt - widget.clock.now();
    _totalMs = left <= 0 ? 1 : ((left + 899) ~/ 1000) * 1000;
  }

  @override
  void didUpdateWidget(FinalCountdown old) {
    super.didUpdateWidget(old);
    if (old.endsAt != widget.endsAt || old.startsAt != widget.startsAt) _measure();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.clock.remaining(widget.endsAt);
    final secs = (left + 999) ~/ 1000;
    final warning = left > 0 && left <= 10000;
    final color = left == 0 ? AppColors.textMuted : (warning ? AppColors.warning : AppColors.accent);
    return SizedBox(
      width: 150,
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: (left / _totalMs).clamp(0.0, 1.0),
              strokeWidth: 12,
              color: color,
              backgroundColor: AppColors.surface2,
            ),
          ),
          Text('$secs', style: AppText.displayStyle(56, color: color, tabular: true)),
        ],
      ),
    );
  }
}

/// `final_judging`: finalists' answers and bets appear as each is judged.
class FinalJudgingView extends StatelessWidget {
  const FinalJudgingView({super.key, required this.view});

  final GameView view;

  @override
  Widget build(BuildContext context) {
    final parts = view.finalView?.participants ?? const <FinalParticipant>[];
    final theme = view.question?.categoryName ?? view.finalView?.remainingTheme?.name ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(96, 0, 96, 16),
      child: Column(
        children: [
          _FinalTitle(subtitle: theme.isEmpty ? 'Ведущий проверяет ответы' : 'Ответы · $theme'),
          const Spacer(),
          _finalists([for (final p in parts) _judgedTile(p)]),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _judgedTile(FinalParticipant p) {
    final score = view.playerById(p.playerId)?.score ?? 0;
    if (!p.judged) {
      return _FinalistTile(
        name: _name(view, p.playerId),
        player: view.playerById(p.playerId),
        score: score,
        status: p.hasAnswer ? 'ждём решения ведущего' : 'без ответа · ждём решения',
      );
    }
    final ok = p.correct!;
    final bet = p.bet;
    return _FinalistTile(
      name: _name(view, p.playerId),
      player: view.playerById(p.playerId),
      score: score,
      detail: (p.answer ?? '').trim().isEmpty ? '— без ответа —' : '«${p.answer!.trim()}»',
      status: '${ok ? 'Верно' : 'Неверно'}${bet == null ? '' : ' · ставка ${ok ? '+' : '−'}$bet'}',
      color: ok ? AppColors.success : AppColors.danger,
    );
  }
}

/// `final_reveal`: the correct answer + everyone's final result.
class FinalRevealView extends StatelessWidget {
  const FinalRevealView({super.key, required this.view, required this.question, required this.server});

  final GameView view;
  final QuestionView question;
  final Uri server;

  @override
  Widget build(BuildContext context) {
    final parts = [...?view.finalView?.participants]
      ..sort((a, b) => (view.playerById(b.playerId)?.score ?? 0).compareTo(view.playerById(a.playerId)?.score ?? 0));
    final comment = question.comment?.trim() ?? '';
    final stage = stageKeyOf(view);
    return Padding(
      padding: const EdgeInsets.fromLTRB(96, 0, 96, 16),
      child: Column(
        children: [
          Text(
            'ПРАВИЛЬНЫЙ ОТВЕТ',
            style: AppText.bodyStyle(28, weight: FontWeight.w600, color: AppColors.success).copyWith(letterSpacing: 3),
          ),
          Expanded(
            flex: 3,
            child: BlocksView(
              key: ValueKey('fa-${question.id}'),
              blocks: question.answerBlocks ?? const [],
              server: server,
              keyPrefix: 'fa${question.id}',
              stage: stage,
            ),
          ),
          if (comment.isNotEmpty)
            Flexible(
              child: BlocksView(
                key: ValueKey('fc-${question.id}'),
                blocks: splitBlocks(comment, packId: view.pack?.id ?? ''),
                server: server,
                keyPrefix: 'fc${question.id}',
                stage: stage,
                textSize: 26,
              ),
            ),
          const SizedBox(height: 16),
          _finalists([
            for (final (i, p) in parts.indexed)
              _FinalistTile(
                name: '${i + 1}. ${_name(view, p.playerId)}',
                player: view.playerById(p.playerId),
                score: view.playerById(p.playerId)?.score ?? 0,
                detail: (p.answer ?? '').trim().isEmpty ? '— без ответа —' : '«${p.answer!.trim()}»',
                status: p.correct == null
                    ? ''
                    : '${p.correct! ? 'Верно' : 'Неверно'}${p.bet == null ? '' : ' · ${p.correct! ? '+' : '−'}${p.bet}'}',
                color: p.correct == null ? null : (p.correct! ? AppColors.success : AppColors.danger),
              ),
          ]),
        ],
      ),
    );
  }
}
