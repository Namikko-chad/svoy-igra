import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/models.dart';
import '../avatar/avatar.dart';

/// Player chips: name, gold score, connection dot, gold ring on the chooser,
/// accent ring on the player who is answering.
class Scoreboard extends StatelessWidget {
  const Scoreboard({super.key, required this.view, this.meId, this.onTap});

  final GameView view;
  final String? meId;
  final void Function(PlayerView player)? onTap;

  @override
  Widget build(BuildContext context) {
    if (view.players.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text('Игроков пока нет', style: AppText.muted(14)),
      );
    }
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: view.players.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final p = view.players[i];
          return PlayerChip(
            player: p,
            chooser: p.id == view.chooserId,
            answering: p.id == view.answeringPlayerId,
            isMe: p.id == meId,
            attempted: view.attemptedPlayerIds.contains(p.id),
            onTap: onTap == null ? null : () => onTap!(p),
          );
        },
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
    this.isMe = false,
    this.attempted = false,
    this.onTap,
  });

  final PlayerView player;
  final bool chooser;
  final bool answering;
  final bool isMe;
  final bool attempted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ring = answering ? AppColors.accent : (chooser ? AppColors.gold : AppColors.border);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: isMe ? AppColors.surface2 : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ring, width: answering || chooser ? 2 : 1),
        boxShadow: answering ? AppColors.accentGlow : (chooser ? AppColors.goldGlow : null),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Avatar(
                name: player.name,
                url: player.avatarUrl,
                size: 40,
                ring: answering ? AppColors.accent : (chooser ? AppColors.gold : null),
              ),
              const SizedBox(width: 8),
              Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  StatusDot(ok: player.connected),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      player.name,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(13,
                          weight: isMe ? FontWeight.w600 : FontWeight.w500,
                          color: attempted ? AppColors.textMuted : AppColors.text),
                    ),
                  ),
                ]),
                const SizedBox(height: 2),
                Text(
                  formatScore(player.score),
                  style: AppText.display(16, color: player.score < 0 ? AppColors.danger : AppColors.gold),
                ),
              ],
            ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Final / round standings, best first.
class Standings extends StatelessWidget {
  const Standings({super.key, required this.players, this.meId});

  final List<PlayerView> players;
  final String? meId;

  @override
  Widget build(BuildContext context) {
    final sorted = [...players]..sort((a, b) => b.score.compareTo(a.score));
    return Column(
      children: [
        for (var i = 0; i < sorted.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: sorted[i].id == meId ? AppColors.surface2 : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: i == 0 ? AppColors.gold : AppColors.border, width: i == 0 ? 2 : 1),
              boxShadow: i == 0 ? AppColors.goldGlow : null,
            ),
            child: Row(children: [
              SizedBox(width: 32, child: Text('${i + 1}', style: AppText.display(16, color: AppColors.textMuted))),
              Avatar(name: sorted[i].name, url: sorted[i].avatarUrl, size: 64, ring: i == 0 ? AppColors.gold : null),
              const SizedBox(width: 12),
              Expanded(child: Text(sorted[i].name, style: AppText.body(16, weight: FontWeight.w600))),
              Text(
                formatScore(sorted[i].score),
                style: AppText.display(20, color: sorted[i].score < 0 ? AppColors.danger : AppColors.gold),
              ),
            ]),
          ),
      ],
    );
  }
}
