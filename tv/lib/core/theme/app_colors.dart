import 'package:flutter/material.dart';

/// Colour tokens of the design manifest (§1). Dark only.
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

  /// `bg-glow`: radial stage backdrop behind the board and the question.
  static const stageGradient = RadialGradient(
    center: Alignment(0, -0.3),
    radius: 1.1,
    colors: [bgGlow, bg],
  );

  static const cellGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [cellTop, cellBottom],
  );

  /// Glow elevation for focused/active elements.
  static const accentGlow = [
    BoxShadow(color: Color(0x4038C6FF), blurRadius: 24),
  ];

  /// Glow elevation for gold highlights.
  static const goldGlow = [
    BoxShadow(color: Color(0x59F7C948), blurRadius: 32),
  ];
}
