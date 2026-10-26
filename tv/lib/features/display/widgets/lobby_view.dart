import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/avatar.dart';
import '../../../data/models/game_view.dart';
import 'top_bar.dart';

/// Before the game: pack title, who has joined, and how to join. The join
/// panel shows the game's link + QR + PIN only when this screen knows them
/// (joined by PIN); a screen watching from the public list never gets them.
class LobbyView extends StatelessWidget {
  const LobbyView({super.key, required this.view});

  final GameView view;

  @override
  Widget build(BuildContext context) {
    final link = view.game.link;
    final pin = view.game.pin;
    return Padding(
      padding: const EdgeInsets.fromLTRB(96, 24, 96, 48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  view.game.title.isNotEmpty ? view.game.title : (view.pack?.title ?? 'Своя игра'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.displayStyle(64),
                ),
                const SizedBox(height: 16),
                Text(
                  view.pack == null ? 'Пакет ещё не выбран' : 'Пакет «${view.pack!.title}»',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyStyle(32, weight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                if (view.game.hostTaken) ...[
                  HostBadge(game: view.game, size: 64, textSize: 28),
                  const SizedBox(height: 12),
                ],
                Text('Ждём начала игры…', style: AppText.bodyStyle(32, color: AppColors.textMuted)),
                const SizedBox(height: 48),
                Text(
                  'ИГРОКИ · ${view.players.length}',
                  style: AppText.bodyStyle(
                    24,
                    weight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ).copyWith(letterSpacing: 2),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: view.players.isEmpty
                      ? Text(
                          'Пока никого — отсканируйте QR-код справа',
                          style: AppText.bodyStyle(30, color: AppColors.textMuted),
                        )
                      : SingleChildScrollView(
                          child: Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [for (final p in view.players) _PlayerTag(player: p)],
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 80),
          if (link == null)
            const _NoLinkPanel()
          else
            Container(
              width: 560,
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
                boxShadow: AppColors.accentGlow,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Подключайтесь с телефона',
                    textAlign: TextAlign.center,
                    style: AppText.bodyStyle(32, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: QrImageView(
                      data: link,
                      size: 320,
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.bg),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: AppColors.bg,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(link, style: AppText.monoStyle(36, color: AppColors.accent)),
                  ),
                  if (pin != null) ...[
                    const SizedBox(height: 20),
                    Text(
                      'PIN ИГРЫ',
                      style: AppText.bodyStyle(
                        22,
                        weight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ).copyWith(letterSpacing: 3),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _spacedPin(pin),
                        style: AppText.displayStyle(80, color: AppColors.gold, tabular: true),
                      ),
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

/// Watch screens get no PIN or link: say who hands out the way in.
class _NoLinkPanel extends StatelessWidget {
  const _NoLinkPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 560,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, size: 72, color: AppColors.accent),
          const SizedBox(height: 24),
          Text(
            'Ссылку для входа раздаёт администратор',
            textAlign: TextAlign.center,
            style: AppText.bodyStyle(34, weight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Text(
            'Спросите у ведущего ссылку или PIN игры, чтобы подключиться с телефона.',
            textAlign: TextAlign.center,
            style: AppText.bodyStyle(26, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// `123456` → `123 456` for reading from the sofa.
String _spacedPin(String pin) => pin.length == 6 ? '${pin.substring(0, 3)} ${pin.substring(3)}' : pin;

class _PlayerTag extends StatelessWidget {
  const _PlayerTag({required this.player});

  final PlayerView player;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 28, 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Avatar(name: player.name, url: player.avatarUrl, size: 96),
          const SizedBox(width: 16),
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: player.connected ? AppColors.success : AppColors.danger,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Text(player.name, style: AppText.bodyStyle(32, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}
