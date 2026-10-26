import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/server_clock.dart';
import '../../../core/widgets/avatar.dart';
import '../../../data/models/block_splitter.dart';
import '../../../data/models/game_view.dart';
import '../stage_key.dart';
import 'blocks_view.dart';
import 'special_views.dart';
import 'timer_bar.dart';

/// Phases `question`, `answering` and `reveal` of one question.
class QuestionStage extends StatelessWidget {
  const QuestionStage({
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
    final reveal = view.phase == Phase.reveal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(96, 0, 96, 16),
      child: Column(
        children: [
          _header(),
          const SizedBox(height: 8),
          if (view.phase == Phase.question) TimerBar(view: view, clock: clock) else const SizedBox(height: 72),
          const SizedBox(height: 16),
          Expanded(child: reveal ? _answer() : _question()),
          const SizedBox(height: 16),
          _StatusLine(view: view),
        ],
      ),
    );
  }

  Widget _header() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      if (question.modifier != null) ...[ModifierChip(modifier: question.modifier!), const SizedBox(width: 24)],
      Flexible(
        child: Text(
          question.categoryName.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.bodyStyle(
            32,
            weight: FontWeight.w600,
            color: AppColors.textMuted,
          ).copyWith(letterSpacing: 1.5),
        ),
      ),
      const SizedBox(width: 32),
      Text(
        // What a correct answer earns: ×2, the winning bid …
        '${question.stake}',
        style: AppText.displayStyle(
          56,
          color: AppColors.gold,
          tabular: true,
        ).copyWith(shadows: const [Shadow(color: Color(0x99F7C948), blurRadius: 18)]),
      ),
    ],
  );

  Widget _question() => BlocksView(
    key: ValueKey('q-${question.id}'),
    blocks: question.blocks,
    server: server,
    keyPrefix: 'q${question.id}',
    stage: stageKeyOf(view),
  );

  Widget _answer() {
    final answer = question.answerBlocks ?? const [];
    final comment = question.comment?.trim() ?? '';
    return Column(
      children: [
        Text(
          'ПРАВИЛЬНЫЙ ОТВЕТ',
          style: AppText.bodyStyle(26, weight: FontWeight.w600, color: AppColors.success).copyWith(letterSpacing: 3),
        ),
        const SizedBox(height: 8),
        Expanded(
          flex: 3,
          child: answer.isEmpty
              ? Center(
                  child: Text('—', style: AppText.displayStyle(48, color: AppColors.textMuted)),
                )
              : BlocksView(
                  key: ValueKey('a-${question.id}'),
                  blocks: answer,
                  server: server,
                  keyPrefix: 'a${question.id}',
                  stage: stageKeyOf(view),
                ),
        ),
        if (comment.isNotEmpty) ...[
          const SizedBox(height: 16),
          Flexible(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: BlocksView(
                key: ValueKey('c-${question.id}'),
                blocks: splitBlocks(comment, packId: view.pack?.id ?? ''),
                server: server,
                keyPrefix: 'c${question.id}',
                stage: stageKeyOf(view),
                textSize: 28,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Who is answering / what happened, under the question.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.view});

  final GameView view;

  @override
  Widget build(BuildContext context) {
    final result = view.lastResult;
    final resultPlayer = view.playerById(result?.playerId);
    Widget? child;
    switch (view.phase) {
      case Phase.answering:
        final p = view.answering;
        child = _Pill(
          color: AppColors.accent,
          glow: AppColors.accentGlow,
          children: [
            if (p != null) ...[
              Avatar(name: p.name, url: p.avatarUrl, size: 64, ring: AppColors.accent),
              const SizedBox(width: 20),
            ],
            Text('Отвечает: ', style: AppText.bodyStyle(40, color: AppColors.textMuted)),
            Flexible(
              child: Text(
                p?.name ?? '…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.displayStyle(48),
              ),
            ),
          ],
        );
      case Phase.question when view.soloPlayerId != null:
        final solo = view.playerById(view.soloPlayerId);
        child = _Pill(
          color: AppColors.accent,
          glow: AppColors.accentGlow,
          children: [
            if (solo != null) ...[
              Avatar(name: solo.name, url: solo.avatarUrl, size: 64, ring: AppColors.accent),
              const SizedBox(width: 20),
            ],
            Text('Отвечает ', style: AppText.bodyStyle(40, color: AppColors.textMuted)),
            Flexible(
              child: Text(
                solo?.name ?? '…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.displayStyle(48),
              ),
            ),
          ],
        );
      case Phase.question:
        if (result != null && !result.correct && resultPlayer != null) {
          child = _Pill(
            color: AppColors.danger,
            children: [
              Flexible(
                child: Text(
                  '${resultPlayer.name}: неверно${result.delta != 0 ? ' (${result.delta})' : ''} — отвечают остальные',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyStyle(32, weight: FontWeight.w600),
                ),
              ),
            ],
          );
        }
      case Phase.reveal:
        if (result != null && result.correct) {
          child = _Pill(
            color: AppColors.success,
            glow: AppColors.goldGlow,
            children: [
              if (resultPlayer != null) ...[
                Avatar(name: resultPlayer.name, url: resultPlayer.avatarUrl, size: 64, ring: AppColors.success),
                const SizedBox(width: 20),
              ],
              Text('Верно! ', style: AppText.displayStyle(40, color: AppColors.success)),
              Flexible(
                child: Text(
                  resultPlayer?.name ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.displayStyle(40),
                ),
              ),
              Text('  +${result.delta}', style: AppText.displayStyle(40, color: AppColors.gold, tabular: true)),
            ],
          );
        } else if (result != null && !result.correct && resultPlayer != null && _isSolo(view.question?.modifier)) {
          // A wrong solo answer (cat / auction / no-risk) goes straight to reveal.
          child = _Pill(
            color: AppColors.danger,
            children: [
              Text('Неверно · ', style: AppText.displayStyle(40, color: AppColors.danger)),
              Flexible(
                child: Text(
                  resultPlayer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.displayStyle(40),
                ),
              ),
              if (result.delta != 0)
                Text('  ${result.delta}', style: AppText.displayStyle(40, color: AppColors.danger, tabular: true)),
            ],
          );
        } else {
          child = _Pill(
            color: AppColors.border,
            children: [Text('Никто не ответил верно', style: AppText.bodyStyle(34, weight: FontWeight.w600))],
          );
        }
      default:
        child = null;
    }
    return SizedBox(height: 104, child: Center(child: child));
  }
}

bool _isSolo(Modifier? m) => m == Modifier.cat || m == Modifier.auction || m == Modifier.noRisk;

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.children, this.glow});

  final Color color;
  final List<Widget> children;
  final List<BoxShadow>? glow;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color, width: 4),
      boxShadow: glow,
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: children),
  );
}
