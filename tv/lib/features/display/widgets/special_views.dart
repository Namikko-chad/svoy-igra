import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/avatar.dart';
import '../../../data/models/game_view.dart';
import 'modifier_reveal.dart';

/// Category + value line shared by the special stages.
class SpecialHeader extends StatelessWidget {
  const SpecialHeader({super.key, required this.question});

  final QuestionView question;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
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
      const SizedBox(width: 24),
      Text('${question.value}', style: AppText.displayStyle(48, color: AppColors.gold, tabular: true)),
    ],
  );
}

/// Small gold pill naming the modifier (question header, special stages).
class ModifierChip extends StatelessWidget {
  const ModifierChip({super.key, required this.modifier});

  final Modifier modifier;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: AppColors.gold, width: 2),
      boxShadow: AppColors.goldGlow,
    ),
    child: Text(
      modifier.label,
      style: AppText.bodyStyle(26, weight: FontWeight.w600, color: AppColors.gold),
    ),
  );
}

/// Phase `cat_transfer`: the chooser picks who gets the cat.
class CatTransferView extends StatelessWidget {
  const CatTransferView({super.key, required this.view, required this.question});

  final GameView view;
  final QuestionView question;

  @override
  Widget build(BuildContext context) {
    final chooser = view.chooser;
    final others = view.players.where((p) => p.id != view.chooserId && p.connected).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(96, 8, 96, 16),
      child: Column(
        children: [
          SpecialHeader(question: question),
          const Spacer(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (chooser != null) ...[
                Avatar(name: chooser.name, url: chooser.avatarUrl, size: 160, ring: AppColors.gold),
                const SizedBox(width: 40),
              ],
              const ModifierArt(modifier: Modifier.cat, size: 260),
            ],
          ),
          const SizedBox(height: 40),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: chooser?.name ?? 'Игрок',
                  style: AppText.displayStyle(56, color: AppColors.gold),
                ),
                TextSpan(
                  text: ' выбирает, кому отдать кота',
                  style: AppText.bodyStyle(52, weight: FontWeight.w600),
                ),
              ],
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 32),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              for (final p in others)
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 8, 24, 8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Avatar(name: p.name, url: p.avatarUrl, size: 48),
                      const SizedBox(width: 12),
                      Text(p.name, style: AppText.bodyStyle(30, weight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

/// Phase `auction`: high bid, leader, whose turn, who passed.
class AuctionStageView extends StatelessWidget {
  const AuctionStageView({super.key, required this.view, required this.question});

  final GameView view;
  final QuestionView question;

  @override
  Widget build(BuildContext context) {
    final a = view.auction;
    if (a == null) return Center(child: SpecialHeader(question: question));
    final leader = view.playerById(a.highBidderId);
    final turn = view.playerById(a.turnPlayerId);
    final bidColor = a.allIn ? AppColors.danger : AppColors.gold;
    return Padding(
      padding: const EdgeInsets.fromLTRB(96, 8, 96, 16),
      child: Column(
        children: [
          SpecialHeader(question: question),
          const SizedBox(height: 24),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'СТАВКА',
                        style: AppText.bodyStyle(
                          30,
                          weight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ).copyWith(letterSpacing: 4),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${a.highBid}',
                          style: AppText.displayStyle(
                            180,
                            color: bidColor,
                            tabular: true,
                          ).copyWith(shadows: [Shadow(color: bidColor.withValues(alpha: 0.6), blurRadius: 40)]),
                        ),
                      ),
                      if (a.allIn)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: const [BoxShadow(color: Color(0x80FF4D5E), blurRadius: 32)],
                          ),
                          child: Text('ВА-БАНК', style: AppText.displayStyle(40)),
                        ),
                      const SizedBox(height: 24),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Лидер: ',
                              style: AppText.bodyStyle(40, color: AppColors.textMuted),
                            ),
                            TextSpan(text: leader?.name ?? '—', style: AppText.displayStyle(40)),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      Text.rich(
                        TextSpan(
                          children: [
                            if (turn != null) ...[
                              TextSpan(
                                text: 'Ходит: ',
                                style: AppText.bodyStyle(36, color: AppColors.textMuted),
                              ),
                              TextSpan(
                                text: turn.name,
                                style: AppText.displayStyle(36, color: AppColors.accent),
                              ),
                            ] else
                              TextSpan(
                                text: 'Торги окончены',
                                style: AppText.bodyStyle(36, weight: FontWeight.w600),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 48),
                Expanded(
                  flex: 4,
                  child: _Bidders(view: view, auction: a),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bidders extends StatelessWidget {
  const _Bidders({required this.view, required this.auction});

  final GameView view;
  final AuctionView auction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final players = view.players;
        final rowH = players.isEmpty ? 80.0 : ((c.maxHeight - 12 * players.length) / players.length).clamp(44.0, 88.0);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [for (final p in players) _bidderRow(p, rowH)],
        );
      },
    );
  }

  Widget _bidderRow(PlayerView p, double height) {
    final leader = p.id == auction.highBidderId;
    final turn = p.id == auction.turnPlayerId;
    final passed = auction.passedPlayerIds.contains(p.id) && !leader;
    final (border, label, labelColor) = leader
        ? (AppColors.gold, 'лидер', AppColors.gold)
        : turn
        ? (AppColors.accent, 'ходит', AppColors.accent)
        : passed
        ? (AppColors.border, 'пас', AppColors.textMuted)
        : (AppColors.border, '', AppColors.textMuted);
    return Opacity(
      opacity: passed ? 0.45 : 1,
      child: Container(
        height: height,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: leader || turn ? 3 : 1),
          boxShadow: turn ? AppColors.accentGlow : (leader ? AppColors.goldGlow : null),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: 640,
            child: Row(
              children: [
                Avatar(
                  name: p.name,
                  url: p.avatarUrl,
                  size: 48,
                  ring: leader ? AppColors.gold : (turn ? AppColors.accent : null),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodyStyle(
                      32,
                      weight: FontWeight.w600,
                    ).copyWith(decoration: passed ? TextDecoration.lineThrough : null),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  label,
                  style: AppText.bodyStyle(26, weight: FontWeight.w600, color: labelColor),
                ),
                const SizedBox(width: 24),
                Text(
                  '${p.score}',
                  style: AppText.displayStyle(
                    32,
                    color: p.score < 0 ? AppColors.danger : AppColors.gold,
                    tabular: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
