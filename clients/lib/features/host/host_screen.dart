import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/models.dart';
import '../../data/socket.dart';
import '../avatar/avatar_editor.dart';
import '../game/session.dart';
import '../screen/screen_view.dart';
import 'host_game_tab.dart';
import 'host_settings_tab.dart';

/// Host: runs the game (the admin chooses the pack and manages the library).
class HostScreen extends StatefulWidget {
  const HostScreen({super.key});

  @override
  State<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<HostScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final view = context.select<GameSocket, GameView?>((s) => s.view);
    final title = _tab == 0 ? (view?.pack?.title ?? (view == null ? 'Ведущий' : gameTitle(view.game))) : 'Настройки';
    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          const ConnectionBadge(),
          PopupMenuButton<String>(
            onSelected: (v) => _menu(context, v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'avatar', child: Text('Мой аватар')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'finish', child: Text('Завершить игру')),
              PopupMenuItem(value: 'reset', child: Text('Сбросить игру…')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'logout', child: Text('Выйти')),
            ],
          ),
        ],
      ),
      body: StageBackground(
        child: SafeArea(
          top: false,
          child: IndexedStack(index: _tab, children: const [HostGameTab(), HostSettingsTab()]),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        height: 64,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view), label: 'Игра'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Настройки'),
        ],
      ),
    );
  }

  Future<void> _menu(BuildContext context, String v) async {
    switch (v) {
      case 'avatar':
        final view = context.read<GameSocket>().view;
        await editMyAvatar(context, context.read<Session>().api, hasAvatar: view?.game.hostAvatarUrl != null);
      case 'finish':
        await finishGame(context);
      case 'reset':
        await resetGame(context);
      case 'logout':
        await leaveSession(context);
    }
  }
}

Future<void> finishGame(BuildContext context) async {
  if (await confirm(context, 'Завершить игру?', ok: 'Завершить', danger: true) && context.mounted) {
    context.read<GameSocket>().command('finish_game');
  }
}

/// `reset_game` with the keepPlayers choice (host and admin).
Future<void> resetGame(BuildContext context) async {
  var keep = true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Сбросить игру?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Очки обнулятся, все вопросы снова станут доступны, игра вернётся в лобби.'),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: keep,
            onChanged: (v) => setLocal(() => keep = v ?? true),
            title: const Text('Оставить игроков'),
            subtitle: Text(keep ? 'Игроки останутся в игре' : 'Все игроки будут отключены', style: AppText.muted(12)),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: AppColors.text),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    ),
  );
  if (ok == true && context.mounted) context.read<GameSocket>().command('reset_game', {'keepPlayers': keep});
}
