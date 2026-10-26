import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../game/timer_bar.dart';

/// The player's one big action (DESIGN_MANIFEST.md, Buzzer). The server opens
/// it; the client never opens it on its own clock.
class Buzzer extends StatefulWidget {
  const Buzzer({super.key, required this.me, required this.now, required this.onPress, required this.size});

  final MeView me;
  final int Function() now;
  final VoidCallback onPress;
  final double size;

  @override
  State<Buzzer> createState() => _BuzzerState();
}

class _BuzzerState extends State<Buzzer> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  /// Pressed locally, waiting for the server's verdict.
  bool _pressed = false;

  @override
  void didUpdateWidget(Buzzer old) {
    super.didUpdateWidget(old);
    if (old.me.buzzer != widget.me.buzzer) _pressed = false;
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _press() {
    if (_pressed || widget.me.buzzer != BuzzerState.open) return;
    HapticFeedback.heavyImpact();
    setState(() => _pressed = true);
    widget.onPress();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.me.buzzer;
    final size = widget.size;
    final disabled = state == BuzzerState.used || state == BuzzerState.closed;
    final label = switch (state) {
      BuzzerState.answering => 'Вы отвечаете',
      BuzzerState.used => 'Попытка использована',
      BuzzerState.closed => 'Закрыто',
      _ => 'Дать ответ',
    };
    final Color fill = switch (state) {
      BuzzerState.open => AppColors.danger,
      BuzzerState.answering => AppColors.gold,
      BuzzerState.waiting => Colors.transparent,
      _ => AppColors.surface2,
    };
    final Color fg = switch (state) {
      BuzzerState.answering => AppColors.bg,
      BuzzerState.waiting => AppColors.textMuted,
      _ when disabled => AppColors.textMuted,
      _ => AppColors.text,
    };
    final border = switch (state) {
      BuzzerState.waiting => AppColors.border,
      BuzzerState.open => AppColors.danger,
      BuzzerState.answering => AppColors.gold,
      _ => AppColors.border,
    };

    final Widget content = Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: EdgeInsets.symmetric(horizontal: size * 0.12),
        child: FittedBox(
          child: Text(
            _pressed && state == BuzzerState.open ? '…' : label,
            textAlign: TextAlign.center,
            style: AppText.display(size * 0.1, color: fg),
          ),
        ),
      ),
      if (state == BuzzerState.waiting && widget.me.buzzOpensAt != null)
        Ticker(builder: (_) {
          final left = widget.me.buzzOpensAt! - widget.now();
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(left > 0 ? (left / 1000).toStringAsFixed(1) : '0.0', style: AppText.mono(size * 0.09, color: fg)),
          );
        }),
    ]);

    return Semantics(
      button: true,
      enabled: state == BuzzerState.open,
      label: label,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final glow = state == BuzzerState.open
              ? [BoxShadow(color: AppColors.danger.withValues(alpha: 0.35 + 0.35 * _pulse.value), blurRadius: 24 + 24 * _pulse.value, spreadRadius: 4 * _pulse.value)]
              : state == BuzzerState.answering
                  ? AppColors.goldGlow
                  : null;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fill,
              border: Border.all(color: border, width: 3),
              boxShadow: glow,
            ),
            child: child,
          );
        },
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTapDown: state == BuzzerState.open ? (_) => _press() : null,
            onTap: state == BuzzerState.open ? () {} : null,
            child: Center(child: content),
          ),
        ),
      ),
    );
  }
}
