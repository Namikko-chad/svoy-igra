import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/avatar.dart';
import '../../../data/models/game_view.dart';

/// `round_end`: the round's standings table.
class RoundEndView extends StatelessWidget {
  const RoundEndView({super.key, required this.view});

  final GameView view;

  @override
  Widget build(BuildContext context) {
    final round = view.round;
    final last = round != null && round.index + 1 >= round.total;
    final standings = view.standings;
    final twoColumns = standings.length > 7;
    final half = (standings.length + 1) ~/ 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(320, 24, 320, 48),
      child: Column(
        children: [
          Text(
            round == null || round.name.isEmpty ? 'Раунд окончен' : 'Раунд «${round.name}» окончен',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.displayStyle(56),
          ),
          const SizedBox(height: 12),
          Text(
            last ? 'Впереди подведение итогов' : 'Скоро следующий раунд',
            style: AppText.bodyStyle(30, color: AppColors.textMuted),
          ),
          const SizedBox(height: 40),
          Expanded(
            child: twoColumns
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _table(standings.sublist(0, half), 0)),
                      const SizedBox(width: 48),
                      Expanded(child: _table(standings.sublist(half), half)),
                    ],
                  )
                : _table(standings, 0),
          ),
        ],
      ),
    );
  }

  Widget _table(List<PlayerView> rows, int offset) => LayoutBuilder(
    builder: (context, c) {
      final rowHeight = rows.isEmpty ? 88.0 : (c.maxHeight / rows.length - 12).clamp(40.0, 88.0);
      return Column(
        children: [
          for (final (i, p) in rows.indexed)
            Container(
              height: rowHeight,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 32),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: offset + i == 0 ? AppColors.gold : AppColors.border,
                  width: offset + i == 0 ? 3 : 1,
                ),
                boxShadow: offset + i == 0 ? AppColors.goldGlow : null,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: c.maxWidth - 64,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 72,
                        child: Text(
                          '${offset + i + 1}',
                          style: AppText.displayStyle(32, color: AppColors.textMuted, tabular: true),
                        ),
                      ),
                      Avatar(name: p.name, url: p.avatarUrl, size: 64),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodyStyle(36, weight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        '${p.score}',
                        style: AppText.displayStyle(
                          40,
                          color: p.score < 0 ? AppColors.danger : AppColors.gold,
                          tabular: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// `finished`: a podium for the top three, everyone else below.
class FinishedView extends StatelessWidget {
  const FinishedView({super.key, required this.view});

  final GameView view;

  @override
  Widget build(BuildContext context) {
    final standings = view.standings;
    final top = standings.take(3).toList();
    final rest = standings.skip(3).toList();
    // Podium order: 2nd, 1st, 3rd.
    final podium = <(int, PlayerView)>[
      if (top.length > 1) (1, top[1]),
      if (top.isNotEmpty) (0, top[0]),
      if (top.length > 2) (2, top[2]),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(96, 16, 96, 40),
      child: Column(
        children: [
          Text('Игра окончена', style: AppText.displayStyle(64, color: AppColors.gold)),
          const SizedBox(height: 8),
          if (view.pack != null) Text(view.pack!.title, style: AppText.bodyStyle(30, color: AppColors.textMuted)),
          const SizedBox(height: 24),
          Expanded(
            child: standings.isEmpty
                ? Center(
                    child: Text('Нет игроков', style: AppText.bodyStyle(32, color: AppColors.textMuted)),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [for (final (place, p) in podium) _PodiumStep(place: place, player: p)],
                  ),
          ),
          if (rest.isNotEmpty) ...[
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                for (final (i, p) in rest.indexed)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Avatar(name: p.name, url: p.avatarUrl, size: 32),
                        const SizedBox(width: 10),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${i + 4}. ',
                                style: AppText.bodyStyle(26, color: AppColors.textMuted),
                              ),
                              TextSpan(
                                text: '${p.name}  ',
                                style: AppText.bodyStyle(26, weight: FontWeight.w600),
                              ),
                              TextSpan(
                                text: '${p.score}',
                                style: AppText.displayStyle(
                                  26,
                                  color: p.score < 0 ? AppColors.danger : AppColors.gold,
                                  tabular: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PodiumStep extends StatelessWidget {
  const _PodiumStep({required this.place, required this.player});

  final int place;
  final PlayerView player;

  static const _heights = [340.0, 250.0, 190.0];
  static const _colors = [AppColors.gold, Color(0xFFC9D1E8), Color(0xFFD08A4E)];

  @override
  Widget build(BuildContext context) {
    final color = _colors[place];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: 400,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Avatar(
              name: player.name,
              url: player.avatarUrl,
              size: place == 0 ? 120 : 96,
              ring: place == 0 ? AppColors.gold : null,
            ),
            const SizedBox(height: 12),
            Text(
              player.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.displayStyle(place == 0 ? 44 : 34),
            ),
            const SizedBox(height: 8),
            Text(
              '${player.score}',
              style: AppText.displayStyle(
                place == 0 ? 56 : 40,
                color: player.score < 0 ? AppColors.danger : AppColors.gold,
                tabular: true,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: Container(
                height: _heights[place],
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [color.withValues(alpha: 0.9), color.withValues(alpha: 0.35)],
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  boxShadow: place == 0 ? AppColors.goldGlow : null,
                ),
                alignment: Alignment.topCenter,
                padding: const EdgeInsets.only(top: 16),
                child: Text('${place + 1}', style: AppText.displayStyle(72, color: AppColors.bg)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
