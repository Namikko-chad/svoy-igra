import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar.dart';
import '../../../data/models/game_view.dart';

/// Player chips along the bottom: name, score, connection dot; gold ring on
/// the chooser, accent ring on the player answering (manifest: Scoreboard).
class ScoreboardStrip extends StatelessWidget {
  const ScoreboardStrip({super.key, required this.view});

  final GameView view;

  @override
  Widget build(BuildContext context) {
    final players = view.players;
    if (players.isEmpty) {
      return SizedBox(
        height: 140,
        child: Center(
          child: Text('Нет игроков', style: AppText.bodyStyle(26, color: AppColors.textMuted)),
        ),
      );
    }
    final questionPhase = view.phase == Phase.question || view.phase == Phase.answering;
    return SizedBox(
      height: 140,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(48, 12, 48, 24),
        child: LayoutBuilder(
          builder: (context, c) {
            const gap = 16.0;
            final width = ((c.maxWidth - gap * (players.length - 1)) / players.length).clamp(80.0, 340.0);
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final (i, p) in players.indexed) ...[
                  if (i > 0) const SizedBox(width: gap),
                  SizedBox(
                    width: width,
                    child: PlayerChip(
                      player: p,
                      chooser: p.id == view.chooserId && view.phase != Phase.lobby,
                      answering: p.id == view.answeringPlayerId && view.phase == Phase.answering,
                      dimmed: questionPhase && view.attemptedPlayerIds.contains(p.id),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class PlayerChip extends StatelessWidget {
  const PlayerChip({
    super.key,
    required this.player,
    this.chooser = false,
    this.answering = false,
    this.dimmed = false,
  });

  final PlayerView player;
  final bool chooser;
  final bool answering;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final ring = answering
        ? AppColors.accent
        : chooser
        ? AppColors.gold
        : AppColors.border;
    return AnimatedOpacity(
      duration: AppTheme.fast(context),
      opacity: dimmed ? 0.45 : 1,
      child: AnimatedContainer(
        duration: AppTheme.phase(context),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: answering ? AppColors.surface2 : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ring, width: answering || chooser ? 4 : 1),
          boxShadow: answering
              ? AppColors.accentGlow
              : chooser
              ? AppColors.goldGlow
              : null,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Avatar(
                name: player.name,
                url: player.avatarUrl,
                size: 56,
                ring: answering ? AppColors.accent : (chooser ? AppColors.gold : null),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: player.connected ? AppColors.success : AppColors.danger,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: Text(
                          player.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodyStyle(24, weight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${player.score}',
                    style: AppText.displayStyle(
                      36,
                      tabular: true,
                      color: player.score < 0 ? AppColors.danger : AppColors.gold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
