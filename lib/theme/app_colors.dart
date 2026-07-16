import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  static const Color brandGreenDark = Color(0xFF034112);
  static const Color brandGreenDeep = Color(0xFF011606);
  static const Color brandGreen = Color(0xFF0A6B23);
  static const Color splashGreen = Color(0xFF00E135);
  static const Color greenBlack = Color(0xFF000702);

  /// Decline-red, paired with [callGreen] on the home call/chat buttons so
  /// they read as a native incoming-call accept/decline pair.
  static const Color declineRed = Color(0xFFFF3B30);

  // ── Home call/chat buttons ────────────────────────────────────────────
  // Gradient-glass pair: a lighter top edge falling to a deeper base, so the
  // buttons read as lit objects rather than flat swatches. Each triple is
  // (highlight → base → shade) of a single hue; the base is the brand colour
  // and the other two are derived from it, so a hue change stays coherent.

  /// Call button base — deliberately softer than [splashGreen], which is a
  /// signal colour and reads harsh at 56dp of solid fill.
  static const Color callGreen = Color(0xFF29C840);
  static const Color callGreenLight = Color(0xFF5FE072);
  static const Color callGreenDeep = Color(0xFF16A02C);

  /// Chat button — same treatment on the decline hue.
  static const Color chatRedLight = Color(0xFFFF7C73);
  static const Color chatRedDeep = Color(0xFFD62B21);

  static const Color textBlack = Color(0xFF18181B);
  static const Color buttonTextBlack = Color(0xFF151515);

  static const Color lightBackground = Color(0xFFF4F4F4);
  static const Color surface = lightBackground;
  static const Color onSurface = Color(0xFF0E1A12);
  static const Color outline = Color(0xFFCBD5CE);

  static const Color sheetTitle = Color(0xFF111E2B);
  static const Color sheetListBg = Color(0xFFF4F4F4);
  static const Color sheetDivider = Color(0xFFEBEBEB);
  static const Color radioBorder = Color(0xFFCCCFCD);
  static const Color accentGreen = Color(0xFF00E135);

  // ---------------------------------------------------------------------------
  // Dark-theme palette. Mirrors the patterns already used in
  // `features/services/*` so styling stays consistent across the app.
  // ---------------------------------------------------------------------------
  static const Color darkBackground = greenBlack; // scaffold bg (#000702)
  static const Color darkSurface = Color(0xFF1F2426); // card / sheet bg
  static const Color darkSurfaceHigh = Color(0xFF252D2B); // elevated card
  static const Color darkOutline = Color(0xFF2C3133); // borders & dividers
  static const Color darkDivider = Color(0xFF1A2022);
  static const Color darkTextSecondary = Color(0xFFB0B5BB);
  static const Color darkIconBg = Color(0xFF2A2F32);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [brandGreenDark, brandGreenDeep],
  );
}
