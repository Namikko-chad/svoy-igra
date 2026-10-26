import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_text.dart';

/// Material theme built from the manifest tokens. Dark only.
abstract final class AppTheme {
  static const motionFast = Duration(milliseconds: 150);
  static const motionPhase = Duration(milliseconds: 300);
  static const motionOpen = Duration(milliseconds: 400);

  static ThemeData build() {
    const scheme = ColorScheme.dark(
      surface: AppColors.surface,
      primary: AppColors.accent,
      onPrimary: AppColors.bg,
      secondary: AppColors.gold,
      onSecondary: AppColors.bg,
      error: AppColors.danger,
      onSurface: AppColors.text,
      outline: AppColors.border,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      fontFamily: AppText.body,
      focusColor: AppColors.accent.withValues(alpha: 0.2),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.accent,
        selectionColor: Color(0x5538C6FF),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface2,
        hintStyle: AppText.bodyStyle(28, color: AppColors.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.accent, width: 3),
        ),
      ),
    );
  }

  /// Phase-transition duration, zero when the platform asks for reduced motion.
  static Duration phase(BuildContext context) =>
      MediaQuery.of(context).disableAnimations ? Duration.zero : motionPhase;

  static Duration open(BuildContext context) =>
      MediaQuery.of(context).disableAnimations ? Duration.zero : motionOpen;

  static Duration fast(BuildContext context) =>
      MediaQuery.of(context).disableAnimations ? Duration.zero : motionFast;
}
