import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';

/// Rebuilds [builder] every [interval] — for countdowns.
class Ticker extends StatefulWidget {
  const Ticker({super.key, required this.builder, this.interval = const Duration(milliseconds: 100)});

  final WidgetBuilder builder;
  final Duration interval;

  @override
  State<Ticker> createState() => _TickerState();
}

class _TickerState extends State<Ticker> {
  late final Timer _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(widget.interval, (_) => setState(() {}));
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// Thin bar draining from [start] to [deadline] (server ms): `accent`,
/// `warning` in the last 3 s, plus a numeric countdown.
class TimerBar extends StatelessWidget {
  const TimerBar({super.key, required this.start, required this.deadline, required this.now, this.label});

  final int start;
  final int deadline;
  final int Function() now;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Ticker(builder: (context) {
      final t = now();
      final left = deadline - t;
      final frac = timerFraction(start, deadline, t);
      final color = left <= 3000 ? AppColors.warning : AppColors.accent;
      final secs = left <= 0 ? 0 : (left / 1000).ceil();
      return Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 6,
              color: color,
              backgroundColor: AppColors.surface2,
            ),
          ),
        ),
        const SizedBox(width: 12),
        if (label != null) ...[
          Text(label!, style: AppText.muted(12)),
          const SizedBox(width: 6),
        ],
        SizedBox(
          width: 36,
          child: Text('$secs', textAlign: TextAlign.right, style: AppText.mono(16, color: color)),
        ),
      ]);
    });
  }
}

/// Remaining share of the interval [start]→[deadline] at [now], 0..1.
double timerFraction(int start, int deadline, int now) {
  final total = deadline - start;
  if (total <= 0) return 0;
  return ((deadline - now) / total).clamp(0.0, 1.0);
}

enum TimerKind { reading, buzz }

/// Which countdown runs at server time [now] in phase `question`, with its
/// full interval (protocol §4.4): reading = readingStartsAt→readingEndsAt,
/// then the buzz window = buzzStartsAt→buzzEndsAt.
class TimerSpan {
  const TimerSpan(this.kind, this.start, this.end);

  final TimerKind kind;
  final int start;
  final int end;

  static TimerSpan? at(GameView v, int now) {
    if (v.phase != Phase.question) return null;
    final rs = v.readingStartsAt, re = v.readingEndsAt;
    final bs = v.buzzStartsAt, be = v.buzzEndsAt;
    if (re != null && now < re && (bs == null || bs >= re)) {
      return TimerSpan(TimerKind.reading, rs ?? re, re);
    }
    if (be != null) return TimerSpan(TimerKind.buzz, bs ?? re ?? be, be);
    return null;
  }
}
