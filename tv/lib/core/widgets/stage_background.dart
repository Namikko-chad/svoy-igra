import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The `bg-glow` radial backdrop behind the board and the question.
class StageBackground extends StatelessWidget {
  const StageBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.stageGradient),
        child: child,
      );
}
