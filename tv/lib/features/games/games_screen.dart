import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/server_address.dart';
import '../../core/widgets/stage_background.dart';
import '../../core/widgets/tv_button.dart';
import '../../data/models/game_info.dart';
import '../../data/models/game_view.dart';
import 'games_controller.dart';

/// Pick a live game on the server: D-pad focusable cards, refreshed every 5 s.
/// «Ввести PIN» stays as the secondary way in.
class GamesScreen extends StatefulWidget {
  const GamesScreen({super.key, required this.app});

  final AppController app;

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  late final GamesController _games = GamesController(widget.app.api, notice: widget.app.notice)
    ..addListener(_onGames)
    ..start();
  final _pinFocus = FocusNode(debugLabel: 'enter-pin');
  bool _placedFocus = false;

  /// First answer: the first game card autofocuses itself; with no games park
  /// focus on «Ввести PIN».
  void _onGames() {
    if (_placedFocus || !_games.loaded) return;
    _placedFocus = true;
    if (_games.games.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pinFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _games.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _join(GameInfo g) async {
    final result = await _games.watch(g);
    if (result != null && mounted) await widget.app.joined(result);
  }

  @override
  Widget build(BuildContext context) {
    final server = widget.app.server;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.app.changeServer();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: StageBackground(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(120, 80, 120, 64),
            child: ListenableBuilder(
              listenable: _games,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('СВОЯ ИГРА', style: AppText.displayStyle(56, color: AppColors.gold)),
                            const SizedBox(height: 8),
                            Text(
                              'Выберите игру${server == null ? '' : ' · сервер ${ServerAddress.label(server)}'}',
                              style: AppText.bodyStyle(30, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      FocusTraversalGroup(
                        child: Row(children: [
                          TvButton(
                            focusNode: _pinFocus,
                            icon: Icons.dialpad,
                            label: 'Ввести PIN',
                            onPressed: widget.app.enterPin,
                          ),
                          const SizedBox(width: 20),
                          TvButton(
                            icon: Icons.dns_outlined,
                            label: 'Сменить сервер',
                            onPressed: widget.app.changeServer,
                          ),
                        ]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 40,
                    child: Text(
                      _games.notice ?? _games.error ?? '',
                      style: AppText.bodyStyle(28, weight: FontWeight.w600, color: AppColors.danger),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(child: _list()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _list() {
    if (!_games.loaded) {
      return const Center(
        child: SizedBox(
          width: 64,
          height: 64,
          child: CircularProgressIndicator(strokeWidth: 5, color: AppColors.accent),
        ),
      );
    }
    final games = _games.games;
    if (games.isEmpty) {
      return Center(
        child: Text(
          'Игр пока нет — создайте игру на телефоне или сайте',
          textAlign: TextAlign.center,
          style: AppText.bodyStyle(36, weight: FontWeight.w500, color: AppColors.textMuted),
        ),
      );
    }
    return FocusTraversalGroup(
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 24,
          crossAxisSpacing: 24,
          childAspectRatio: 2.0,
        ),
        itemCount: games.length,
        itemBuilder: (context, i) {
          final g = games[i];
          return _GameTile(
            key: ValueKey(g.id),
            autofocus: i == 0,
            game: g,
            joining: _games.joiningId == g.id,
            onSelect: () => _join(g),
          );
        },
      ),
    );
  }
}

class _GameTile extends StatefulWidget {
  const _GameTile({
    super.key,
    required this.game,
    required this.joining,
    required this.onSelect,
    this.autofocus = false,
  });

  final bool autofocus;
  final GameInfo game;
  final bool joining;
  final VoidCallback onSelect;

  @override
  State<_GameTile> createState() => _GameTileState();
}

class _GameTileState extends State<_GameTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final live = g.phase != Phase.lobby && g.phase != Phase.finished;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onFocusChange: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onSelect();
          return null;
        }),
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedScale(
          scale: _focused ? 1.03 : 1,
          duration: AppTheme.fast(context),
          child: AnimatedContainer(
            duration: AppTheme.fast(context),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: _focused ? AppColors.surface2 : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _focused ? AppColors.accent : AppColors.border, width: _focused ? 4 : 1),
              boxShadow: _focused ? AppColors.accentGlow : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  g.title.isEmpty ? 'Игра без названия' : g.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.displayStyle(32),
                ),
                const SizedBox(height: 10),
                Text(
                  g.pack == null ? 'Пакет не выбран' : 'Пакет «${g.pack!.title}»',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyStyle(26, color: AppColors.text),
                ),
                const Spacer(),
                Row(children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: live ? AppColors.success : AppColors.textMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.joining ? 'Подключаем…' : '${g.phaseLabel}  ·  игроков: ${g.players}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyStyle(24, color: AppColors.textMuted),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
