import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/models.dart';
import '../../data/socket.dart';
import '../game/session.dart';
import '../game/settings_card.dart';
import 'host_game_tab.dart';
import 'host_screen.dart';

/// Host settings: timings, players (chooser / kick), finish and reset.
class HostSettingsTab extends StatelessWidget {
  const HostSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final socket = context.watch<GameSocket>();
    final view = socket.view;
    if (view == null) return const WaitingForState();
    return ListView(padding: const EdgeInsets.all(16), children: [
      const SectionTitle('Настройки игры'),
      SettingsCard(settings: view.settings, socket: socket, canCompensate: false),
      SectionTitle('Игроки (${view.players.length})'),
      if (view.players.isEmpty) Text('Игроков пока нет', style: AppText.muted(14)),
      for (final p in view.players)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: ListTile(
              leading: StatusDot(ok: p.connected, size: 10),
              title: Text(p.name),
              subtitle: p.id == view.chooserId ? Text('выбирает', style: AppText.body(12, color: AppColors.gold)) : null,
              trailing: Text(formatScore(p.score),
                  style: AppText.display(16, color: p.score < 0 ? AppColors.danger : AppColors.gold)),
              onTap: () => showPlayerActions(context, view, p),
            ),
          ),
        ),
      const SectionTitle('Управление'),
      if (view.started && view.phase != Phase.finished)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton(onPressed: () => finishGame(context), child: const Text('Завершить игру')),
        ),
      OutlinedButton(
        style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
        onPressed: () => resetGame(context),
        child: const Text('Сбросить игру…'),
      ),
      const SizedBox(height: 24),
    ]);
  }
}
