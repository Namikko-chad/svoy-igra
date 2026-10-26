import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/avatar.dart';
import '../../../data/models/game_view.dart';

/// The round board (manifest: Board): one row per category (≤ 10) — the name in
/// a fixed left column, then the value cells left → right ascending. Played
/// cells keep their place, empty. Rows share the height equally and values are
/// sized to fit their cell (≤ 45 % of its height, scaled down when wider).
class BoardView extends StatelessWidget {
  const BoardView({super.key, required this.view});

  final GameView view;

  static const nameWidth = 340.0;
  static const gap = 10.0;

  @override
  Widget build(BuildContext context) {
    final columns = view.boardRows;
    final chooser = view.chooser;
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 0, 48, 8),
      child: Column(
        children: [
          SizedBox(
            height: 64,
            child: Center(
              child: chooser == null
                  ? const SizedBox()
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Avatar(name: chooser.name, url: chooser.avatarUrl, size: 48, ring: AppColors.gold),
                        const SizedBox(width: 16),
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Выбирает: ',
                                  style: AppText.bodyStyle(34, color: AppColors.textMuted),
                                ),
                                TextSpan(
                                  text: chooser.name,
                                  style: AppText.displayStyle(34, color: AppColors.gold),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          Expanded(
            child: view.board.isEmpty
                ? Center(
                    child: Text('Доска пуста', style: AppText.bodyStyle(32, color: AppColors.textMuted)),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, cat) in view.board.indexed) ...[
                        if (i > 0) const SizedBox(height: gap),
                        Expanded(
                          child: _CategoryRow(category: cat, columns: columns),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.columns});

  final BoardCategory category;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final questions = [...category.questions]..sort((a, b) => a.value.compareTo(b.value));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: BoardView.nameWidth,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: BoardView.nameWidth - 40,
              child: Text(
                category.name.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodyStyle(24, weight: FontWeight.w600).copyWith(height: 1.15),
              ),
            ),
          ),
        ),
        for (var c = 0; c < columns; c++) ...[
          const SizedBox(width: BoardView.gap),
          Expanded(child: c < questions.length ? BoardCell(question: questions[c]) : const SizedBox()),
        ],
      ],
    );
  }
}

/// One value cell; the value never exceeds 45 % of the cell height and
/// shrinks to the cell width (4-digit values on a 10×10 board).
class BoardCell extends StatelessWidget {
  const BoardCell({super.key, required this.question});

  final BoardQuestion question;

  @override
  Widget build(BuildContext context) {
    if (question.played) {
      return DecoratedBox(
        decoration: BoxDecoration(color: AppColors.cellPlayed, borderRadius: BorderRadius.circular(12)),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final fontSize = (c.maxHeight * 0.45).clamp(10.0, 72.0);
        return Container(
          decoration: BoxDecoration(
            gradient: AppColors.cellGradient,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cellHover.withValues(alpha: 0.6)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${question.value}',
              maxLines: 1,
              softWrap: false,
              style: AppText.displayStyle(
                fontSize,
                color: AppColors.gold,
                tabular: true,
              ).copyWith(height: 1, shadows: const [Shadow(color: Color(0x99F7C948), blurRadius: 14)]),
            ),
          ),
        );
      },
    );
  }
}
