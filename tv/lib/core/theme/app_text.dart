import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Type roles of the design manifest: Display (Unbounded), Body (Inter),
/// Mono (JetBrains Mono). Fonts are bundled — the TV may have no internet.
abstract final class AppText {
  static const display = 'Unbounded';
  static const body = 'Inter';
  static const mono = 'JetBrainsMono';

  static const _tabular = [FontFeature.tabularFigures()];

  /// Display text; [tabular] for numbers that change (scores, timers).
  static TextStyle displayStyle(
    double size, {
    FontWeight weight = FontWeight.w800,
    Color color = AppColors.text,
    bool tabular = false,
  }) =>
      TextStyle(
        fontFamily: display,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: 1.15,
        fontFeatures: tabular ? _tabular : null,
      );

  static TextStyle bodyStyle(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.text,
  }) =>
      TextStyle(
        fontFamily: body,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: 1.3,
      );

  static TextStyle monoStyle(double size, {Color color = AppColors.textMuted}) =>
      TextStyle(
        fontFamily: mono,
        fontSize: size,
        fontWeight: FontWeight.w500,
        color: color,
        fontFeatures: _tabular,
      );
}
