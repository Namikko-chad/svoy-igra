import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// A visual equaliser: bars bounce while [active], rest flat otherwise.
/// Purely decorative (no spectrum analysis).
class Equalizer extends StatefulWidget {
  const Equalizer({super.key, required this.active, this.bars = 9, this.height = 96});

  final bool active;
  final int bars;
  final double height;

  @override
  State<Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<Equalizer> with SingleTickerProviderStateMixin {
  late final AnimationController _ticker = AnimationController(vsync: this, duration: const Duration(seconds: 10));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(Equalizer old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final reduced = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (widget.active && !reduced) {
      if (!_ticker.isAnimating) _ticker.repeat();
    } else {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _ticker,
        builder: (context, _) {
          final t = _ticker.value * 10 * 2 * math.pi;
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < widget.bars; i++)
                Container(
                  width: 14,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: widget.height * _level(i, t),
                  decoration: BoxDecoration(
                    color: Color.lerp(AppColors.accent, AppColors.gold, i / widget.bars),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  double _level(int i, double t) {
    if (!widget.active) return 0.12;
    final a = math.sin(t * (1.3 + i * 0.17) + i * 1.7);
    final b = math.sin(t * (2.1 + i * 0.11) + i * 0.6);
    return (0.55 + 0.25 * a + 0.2 * b).clamp(0.12, 1.0);
  }
}
