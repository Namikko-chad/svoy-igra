import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/question_timer.dart';
import '../../../core/utils/server_clock.dart';
import '../../../data/models/game_view.dart';

/// Thin bar across the top of the question: `accent` draining, `warning` in
/// the last 3 s, plus a numeric countdown (manifest: Timer).
class TimerBar extends StatefulWidget {
  const TimerBar({super.key, required this.view, required this.clock});

  final GameView view;
  final ServerClock clock;

  @override
  State<TimerBar> createState() => _TimerBarState();
}

class _TimerBarState extends State<TimerBar> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => setState(() {}))..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.clock.now();
    final v = widget.view;
    final countdown = questionCountdown(
      readingStartsAt: v.readingStartsAt,
      readingEndsAt: v.readingEndsAt,
      buzzStartsAt: v.buzzStartsAt,
      buzzEndsAt: v.buzzEndsAt,
      now: now,
    );
    if (countdown == null) return const SizedBox(height: 72);

    final warning = countdown.isWarning(now);
    final color = warning ? AppColors.warning : AppColors.accent;
    final label = switch (countdown.stage) {
      TimerStage.reading => 'Слушаем вопрос',
      TimerStage.buzzing => countdown.remainingMs(now) > 0 ? 'Жмите кнопку!' : 'Время вышло',
    };
    return SizedBox(
      height: 72,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Row(
            children: [
              Text(
                label,
                style: AppText.bodyStyle(28, weight: FontWeight.w600, color: color),
              ),
              const Spacer(),
              Text('${countdown.secondsLeft(now)}', style: AppText.displayStyle(40, color: color, tabular: true)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 10,
              child: Stack(
                children: [
                  const Positioned.fill(child: ColoredBox(color: AppColors.surface2)),
                  FractionallySizedBox(
                    widthFactor: countdown.fraction(now),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 12)],
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
