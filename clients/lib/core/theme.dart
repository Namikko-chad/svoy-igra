import 'package:flutter/material.dart';

/// Colour tokens from DESIGN_MANIFEST.md §1. Dark only.
abstract final class AppColors {
  static const bg = Color(0xFF070B1F);
  static const bgGlow = Color(0xFF1A2A7A);
  static const surface = Color(0xFF10173A);
  static const surface2 = Color(0xFF18214F);
  static const border = Color(0xFF26306A);
  static const cellTop = Color(0xFF1638B5);
  static const cellBottom = Color(0xFF0E2280);
  static const cellHover = Color(0xFF2148D6);
  static const cellPlayed = Color(0xFF0B1236);
  static const gold = Color(0xFFF7C948);
  static const text = Color(0xFFF1F3FF);
  static const textMuted = Color(0xFF98A2CF);
  static const accent = Color(0xFF38C6FF);
  static const success = Color(0xFF2BD47D);
  static const danger = Color(0xFFFF4D5E);
  static const warning = Color(0xFFFFB020);

  /// Admin latency scale: < 60 ms success, 60–150 ms warning, > 150 ms danger.
  static Color latency(int? ms) {
    if (ms == null) return textMuted;
    if (ms < 60) return success;
    if (ms <= 150) return warning;
    return danger;
  }

  static const accentGlow = [
    BoxShadow(color: Color(0x4038C6FF), blurRadius: 24),
  ];
  static const goldGlow = [
    BoxShadow(color: Color(0x59F7C948), blurRadius: 32),
  ];
}

abstract final class AppFonts {
  static const display = 'Unbounded';
  static const body = 'Inter';
  static const mono = 'JetBrainsMono';
}

/// Text style helpers. Changing numbers always use tabular figures.
abstract final class AppText {
  static const _tabular = [FontFeature.tabularFigures()];

  static TextStyle display(double size, {FontWeight weight = FontWeight.w800, Color color = AppColors.text}) =>
      TextStyle(
        fontFamily: AppFonts.display,
        fontSize: size,
        fontWeight: weight,
        color: color,
        fontFeatures: _tabular,
        height: 1.15,
      );

  static TextStyle body(double size, {FontWeight weight = FontWeight.w400, Color color = AppColors.text}) =>
      TextStyle(fontFamily: AppFonts.body, fontSize: size, fontWeight: weight, color: color);

  static TextStyle muted(double size) => body(size, color: AppColors.textMuted);

  static TextStyle mono(double size, {Color color = AppColors.text}) => TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: size,
        fontWeight: FontWeight.w500,
        color: color,
        fontFeatures: _tabular,
      );
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: AppColors.bg,
    secondary: AppColors.gold,
    onSecondary: AppColors.bg,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    surfaceContainerHighest: AppColors.surface2,
    error: AppColors.danger,
    onError: AppColors.text,
    outline: AppColors.border,
  );
  final radius8 = BorderRadius.circular(8);
  final radius12 = BorderRadius.circular(12);
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: AppFonts.body,
    scaffoldBackgroundColor: AppColors.bg,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: AppFonts.display,
        fontWeight: FontWeight.w600,
        fontSize: 16,
        color: AppColors.text,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: radius12,
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface2,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      labelStyle: const TextStyle(color: AppColors.textMuted),
      hintStyle: const TextStyle(color: AppColors.textMuted),
      border: OutlineInputBorder(borderRadius: radius8, borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: radius8, borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: radius8, borderSide: const BorderSide(color: AppColors.accent, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: radius8, borderSide: const BorderSide(color: AppColors.danger)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.bg,
        disabledBackgroundColor: AppColors.surface2,
        disabledForegroundColor: AppColors.textMuted,
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w600, fontSize: 16),
        shape: RoundedRectangleBorder(borderRadius: radius8),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: AppColors.border),
        textStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w500, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: radius8),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.accent),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface2,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: radius8),
      labelStyle: const TextStyle(color: AppColors.text, fontSize: 13),
    ),
    listTileTheme: const ListTileThemeData(iconColor: AppColors.textMuted),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surface2,
      contentTextStyle: const TextStyle(color: AppColors.text, fontFamily: AppFonts.body),
      shape: RoundedRectangleBorder(borderRadius: radius8),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: radius12, side: const BorderSide(color: AppColors.border)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: AppColors.surface),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.surface2,
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, color: AppColors.text)),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.text,
      unselectedLabelColor: AppColors.textMuted,
      indicatorColor: AppColors.accent,
      dividerColor: AppColors.border,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.accent,
      thumbColor: AppColors.accent,
      inactiveTrackColor: AppColors.surface2,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.bg : AppColors.textMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.accent : AppColors.surface2,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.accent),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

/// The stage backdrop: radial `bg-glow` → `bg`.
class StageBackground extends StatelessWidget {
  const StageBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.4),
          radius: 1.1,
          colors: [AppColors.bgGlow, AppColors.bg],
        ),
      ),
      child: child,
    );
  }
}
