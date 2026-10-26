import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/models.dart';
import '../../data/socket.dart';
import '../game/session.dart';
import '../library/pack_library.dart';
import '../screen/screen_view.dart';
import 'admin_game_tab.dart';
import 'player_admin_card.dart';

/// Admin: the game (PIN, link, pack, settings, file), players, pack library.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final view = context.select<GameSocket, GameView?>((s) => s.view);
    final title = switch (_tab) {
      0 => view == null ? 'Администратор' : gameTitle(view.game),
      1 => 'Игроки',
      _ => 'Пакеты',
    };
    return Scaffold(
      appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis), actions: sessionActions(context)),
      body: StageBackground(
        child: SafeArea(
          top: false,
          child: IndexedStack(index: _tab, children: const [AdminGameTab(), _PlayersTab(), PackLibrary()]),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        height: 64,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.sports_esports_outlined), label: 'Игра'),
          NavigationDestination(icon: Icon(Icons.people_outline), label: 'Игроки'),
          NavigationDestination(icon: Icon(Icons.library_books_outlined), label: 'Пакеты'),
        ],
      ),
    );
  }
}

class _PlayersTab extends StatelessWidget {
  const _PlayersTab();

  @override
  Widget build(BuildContext context) {
    final socket = context.watch<GameSocket>();
    final view = socket.view;
    if (view == null) return const WaitingForState();
    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth >= 900 ? 2 : 1;
      final online = view.players.where((p) => p.connected).length;
      return ListView(padding: const EdgeInsets.all(16), children: [
        SectionTitle('Игроки: в сети $online из ${view.players.length}'),
        if (view.players.isEmpty) const EmptyState(icon: Icons.people_outline, title: 'Игроков пока нет'),
        if (columns == 1)
          for (final p in view.players)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PlayerAdminCard(key: ValueKey(p.id), player: p, socket: socket),
            )
        else
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final p in view.players)
              SizedBox(
                width: (c.maxWidth - 32 - 12) / 2,
                child: PlayerAdminCard(key: ValueKey(p.id), player: p, socket: socket),
              ),
          ]),
      ]);
    });
  }
}
