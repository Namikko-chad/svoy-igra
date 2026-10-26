import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../data/models/game_view.dart';

/// Full-screen "special question!" moment shown when a modifier cell opens
/// (protocol §4.5): big art, the Russian name and what is at stake.
class ModifierReveal extends StatelessWidget {
  const ModifierReveal({super.key, required this.view, required this.question});

  final GameView view;
  final QuestionView question;

  String _subtitle(Modifier m) {
    final chooser = view.chooser?.name;
    return switch (m) {
      Modifier.cat => 'Вопрос достанется другому игроку · цена ${question.value}',
      Modifier.auction => 'Торги за право ответить · старт ${question.value}',
      Modifier.noRisk => '${chooser ?? 'Игрок'} отвечает без риска · +${question.stake}',
      Modifier.double => 'Цена вопроса удвоена · ${question.stake}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final m = question.modifier!;
    final reduced = MediaQuery.of(context).disableAnimations;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduced ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.scale(scale: 0.4 + 0.6 * t, child: child),
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(radius: 1.0, colors: [Color(0xFF2A3A9A), AppColors.bg]),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                question.categoryName.toUpperCase(),
                style: AppText.bodyStyle(
                  32,
                  weight: FontWeight.w600,
                  color: AppColors.textMuted,
                ).copyWith(letterSpacing: 3),
              ),
              const SizedBox(height: 32),
              ModifierArt(modifier: m, size: 340),
              const SizedBox(height: 40),
              Text(
                m.label.toUpperCase(),
                textAlign: TextAlign.center,
                style: AppText.displayStyle(
                  96,
                  color: AppColors.gold,
                ).copyWith(shadows: const [Shadow(color: Color(0x99F7C948), blurRadius: 32)]),
              ),
              const SizedBox(height: 20),
              Text(
                _subtitle(m),
                textAlign: TextAlign.center,
                style: AppText.bodyStyle(40, weight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The modifier's picture inside a glowing gold ring.
class ModifierArt extends StatelessWidget {
  const ModifierArt({super.key, required this.modifier, this.size = 200});

  final Modifier modifier;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Widget art = switch (modifier) {
      Modifier.cat => CustomPaint(size: Size.square(size * 0.7), painter: CatPainter()),
      Modifier.double => Text('×2', style: AppText.displayStyle(size * 0.38, color: AppColors.gold)),
      _ => Text(modifier.emoji, style: TextStyle(fontSize: size * 0.42)),
    };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surface,
        border: Border.all(color: AppColors.gold, width: size / 40),
        boxShadow: const [BoxShadow(color: Color(0x80F7C948), blurRadius: 60, spreadRadius: 6)],
      ),
      child: art,
    );
  }
}

/// A cat face from plain shapes (no image assets).
class CatPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fur = Paint()..color = AppColors.gold;
    final dark = Paint()..color = AppColors.bg;
    final pink = Paint()..color = const Color(0xFFFF9EB0);

    // Ears.
    for (final dir in [-1.0, 1.0]) {
      final cx = w / 2 + dir * w * 0.27;
      final ear = Path()
        ..moveTo(cx - w * 0.17, h * 0.42)
        ..lineTo(cx + dir * w * 0.06, h * 0.04)
        ..lineTo(cx + w * 0.17, h * 0.42)
        ..close();
      canvas.drawPath(ear, fur);
      final inner = Path()
        ..moveTo(cx - w * 0.09, h * 0.38)
        ..lineTo(cx + dir * w * 0.045, h * 0.14)
        ..lineTo(cx + w * 0.09, h * 0.38)
        ..close();
      canvas.drawPath(inner, pink);
    }
    // Head.
    canvas.drawOval(Rect.fromCenter(center: Offset(w / 2, h * 0.6), width: w * 0.86, height: h * 0.72), fur);
    // Eyes.
    for (final dir in [-1.0, 1.0]) {
      final c = Offset(w / 2 + dir * w * 0.17, h * 0.55);
      canvas.drawOval(Rect.fromCenter(center: c, width: w * 0.13, height: h * 0.17), dark);
      canvas.drawCircle(c.translate(w * 0.02, -h * 0.03), w * 0.022, Paint()..color = Colors.white);
    }
    // Nose and mouth.
    final nose = Path()
      ..moveTo(w / 2 - w * 0.04, h * 0.68)
      ..lineTo(w / 2 + w * 0.04, h * 0.68)
      ..lineTo(w / 2, h * 0.73)
      ..close();
    canvas.drawPath(nose, pink);
    final line = Paint()
      ..color = AppColors.bg
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.015
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(w / 2 - w * 0.05, h * 0.74), radius: w * 0.05),
      0,
      math.pi,
      false,
      line,
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset(w / 2 + w * 0.05, h * 0.74), radius: w * 0.05),
      0,
      math.pi,
      false,
      line,
    );
    // Whiskers.
    for (final dir in [-1.0, 1.0]) {
      for (final dy in [-0.03, 0.02, 0.07]) {
        canvas.drawLine(
          Offset(w / 2 + dir * w * 0.12, h * (0.70 + dy / 2)),
          Offset(w / 2 + dir * w * 0.46, h * (0.66 + dy)),
          line,
        );
      }
    }
  }

  @override
  bool shouldRepaint(CatPainter oldDelegate) => false;
}
