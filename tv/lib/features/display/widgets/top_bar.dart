import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/server_address.dart';
import '../../../core/widgets/avatar.dart';
import '../../../data/models/game_view.dart';
import '../../../data/ws/game_socket.dart';

/// Pack title + round on the left, connection status on the right.
class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.view, required this.status, required this.server});

  final GameView? view;
  final SocketStatus status;
  final Uri server;

  @override
  Widget build(BuildContext context) {
    final round = view?.round;
    final phase = view?.phase;
    final showRound = round != null && phase != Phase.lobby && phase != Phase.finished && round.total > 0;
    return SizedBox(
      height: 88,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Row(
          children: [
            Text('СВОЯ ИГРА', style: AppText.displayStyle(28, color: AppColors.gold)),
            const SizedBox(width: 32),
            Expanded(
              child: Text(
                [
                  if (view != null && view!.game.title.isNotEmpty) view!.game.title,
                  if (view?.pack != null) view!.pack!.title,
                  if (showRound)
                    round.isFinal
                        ? 'Финал${round.name.isEmpty ? '' : ' · ${round.name}'}'
                        : 'Раунд ${round.index + 1} из ${round.total}${round.name.isEmpty ? '' : ' · ${round.name}'}',
                ].join('   ·   '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodyStyle(26, weight: FontWeight.w500, color: AppColors.textMuted),
              ),
            ),
            if (view != null && view!.game.hostTaken) ...[HostBadge(game: view!.game), const SizedBox(width: 24)],
            ConnectionBadge(status: status, server: server),
          ],
        ),
      ),
    );
  }
}

/// The host's avatar next to the «Ведущий» label (manifest: Avatar).
class HostBadge extends StatelessWidget {
  const HostBadge({super.key, required this.game, this.size = 48, this.textSize = 24});

  final GameRef game;
  final double size;
  final double textSize;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: game.hostConnected ? 1 : 0.5,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Avatar(name: 'Ведущий', url: game.hostAvatarUrl, size: size),
        const SizedBox(width: 12),
        Text(
          game.hostConnected ? 'Ведущий' : 'Ведущий не в сети',
          style: AppText.bodyStyle(textSize, weight: FontWeight.w600, color: AppColors.textMuted),
        ),
      ],
    ),
  );
}

class ConnectionBadge extends StatelessWidget {
  const ConnectionBadge({super.key, required this.status, required this.server});

  final SocketStatus status;
  final Uri server;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      SocketStatus.connected => (AppColors.success, ServerAddress.label(server)),
      SocketStatus.connecting => (AppColors.warning, 'Подключение…'),
      SocketStatus.offline => (AppColors.danger, 'Нет связи'),
      SocketStatus.ended => (AppColors.danger, 'Отключено'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Text(label, style: AppText.monoStyle(20, color: AppColors.text)),
        ],
      ),
    );
  }
}
