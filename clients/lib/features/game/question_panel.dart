import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/blocks.dart';
import '../../data/models.dart';
import 'blocks_view.dart';
import 'special.dart';
import 'timer_bar.dart';

/// Phase `question` countdown: the common reading timer, then the buzz window.
class QuestionTimer extends StatelessWidget {
  const QuestionTimer({super.key, required this.view, required this.now});

  final GameView view;
  final int Function() now;

  @override
  Widget build(BuildContext context) {
    if (view.phase != Phase.question) return const SizedBox.shrink();
    return Ticker(builder: (context) {
      final span = TimerSpan.at(view, now());
      if (span == null) return const SizedBox.shrink();
      final reading = span.kind == TimerKind.reading;
      return TimerBar(
        key: ValueKey('${span.kind}:${span.start}'),
        start: span.start,
        deadline: span.end,
        now: now,
        label: reading ? 'Чтение' : 'Кнопки',
      );
    });
  }
}

/// Category + value line, timer, question blocks and — when the server sent
/// them — answer blocks and comment.
class QuestionPanel extends StatelessWidget {
  const QuestionPanel({
    super.key,
    required this.view,
    required this.mode,
    required this.resolveUrl,
    required this.now,
    this.footer,
  });

  final GameView view;
  final MediaMode mode;
  final String Function(String) resolveUrl;
  final int Function() now;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final q = view.question;
    if (q == null) return const SizedBox.shrink();
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(
              q.categoryName.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(13, weight: FontWeight.w600, color: AppColors.textMuted),
            ),
          ),
          if (q.value > 0) ...[
            const SizedBox(width: 12),
            Text('${q.value}', style: AppText.display(24, color: AppColors.gold)),
          ],
        ]),
        if (q.modifier != null) ...[
          const SizedBox(height: 12),
          ModifierSplash(question: q, compact: true),
        ],
        const SizedBox(height: 12),
        QuestionTimer(view: view, now: now),
        const SizedBox(height: 12),
        BlocksView(blocks: q.blocks, mode: mode, resolveUrl: resolveUrl, fontSize: wide ? 30 : 22, scope: 'q${q.id}'),
        if (q.answerBlocks != null) ...[
          const SizedBox(height: 16),
          AnswerCard(
            blocks: q.answerBlocks!,
            comment: q.comment,
            packId: view.pack?.id ?? '',
            scope: '${q.id}',
            mode: mode,
            resolveUrl: resolveUrl,
            revealed: view.phase == Phase.reveal,
          ),
        ],
        ?footer,
      ]),
    );
  }
}

/// The correct answer (+ comment) in a highlighted card.
class AnswerCard extends StatelessWidget {
  const AnswerCard({
    super.key,
    required this.blocks,
    required this.comment,
    required this.packId,
    this.scope = '',
    required this.mode,
    required this.resolveUrl,
    this.revealed = true,
  });

  final List<Block> blocks;

  /// Raw markdown; split into blocks here like question text.
  final String? comment;
  final String packId;

  /// Question id: keeps answer/comment players apart from the question's.
  final String scope;
  final MediaMode mode;
  final String Function(String) resolveUrl;
  final bool revealed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withValues(alpha: revealed ? 0.8 : 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('ОТВЕТ', style: AppText.body(12, weight: FontWeight.w600, color: AppColors.success)),
        BlocksView(blocks: blocks, mode: mode, resolveUrl: resolveUrl, fontSize: 20, center: false, scope: 'a$scope'),
        if (comment != null && comment!.trim().isNotEmpty) ...[
          const Divider(height: 24),
          Text('КОММЕНТАРИЙ', style: AppText.body(12, weight: FontWeight.w600, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          BlocksView(
            blocks: splitBlocks(packId, comment!),
            mode: mode,
            resolveUrl: resolveUrl,
            fontSize: 15,
            center: false,
            scope: 'c$scope',
          ),
        ],
      ]),
    );
  }
}
