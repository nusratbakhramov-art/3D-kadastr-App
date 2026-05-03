import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Theme-aware semantic color tokens.
///
/// Use these instead of raw `AppColors.lightBackground`, `Colors.white`,
/// etc. so screens automatically respond to light/dark mode.
class ColorTokens {
  const ColorTokens._();

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  // --- Surfaces ---

  /// Page / scaffold background.
  static Color scaffoldBg(BuildContext context) =>
      _isDark(context) ? AppColors.darkBackground : AppColors.lightBackground;

  /// Card, list-tile, and elevated-surface background.
  static Color cardBg(BuildContext context) =>
      _isDark(context) ? AppColors.darkSurface : Colors.white;

  /// Slightly elevated card (modal, popovers).
  static Color elevatedBg(BuildContext context) =>
      _isDark(context) ? AppColors.darkSurfaceHigh : Colors.white;

  /// Bottom-sheet / list secondary background.
  static Color sheetBg(BuildContext context) =>
      _isDark(context) ? AppColors.darkSurface : AppColors.sheetListBg;

  /// Subtle "icon container" background (e.g. the gray boxes around list-tile icons).
  static Color iconBg(BuildContext context) =>
      _isDark(context) ? AppColors.darkIconBg : const Color(0xFFEEF1F0);

  /// Filled input field background.
  static Color inputFill(BuildContext context) =>
      _isDark(context) ? AppColors.darkSurface : Colors.white;

  // --- Text ---

  /// Primary on-surface text (titles, body).
  static Color primaryText(BuildContext context) =>
      _isDark(context) ? Colors.white : AppColors.textBlack;

  /// Secondary text (captions, hints, labels).
  static Color secondaryText(BuildContext context) => _isDark(context)
      ? AppColors.darkTextSecondary
      : const Color(0xFF6E7480);

  /// Tertiary / disabled text.
  static Color tertiaryText(BuildContext context) => _isDark(context)
      ? AppColors.darkTextSecondary.withValues(alpha: 0.7)
      : const Color(0xFF8A9097);

  // --- Borders & dividers ---

  /// Outline / 1-px borders.
  static Color outline(BuildContext context) =>
      _isDark(context) ? AppColors.darkOutline : AppColors.outline;

  /// Subtle hairline divider.
  static Color divider(BuildContext context) =>
      _isDark(context) ? AppColors.darkDivider : AppColors.sheetDivider;

  // --- Misc ---

  /// Soft drop-shadow color (cards, headers).
  static Color shadow(BuildContext context) => _isDark(context)
      ? Colors.black.withValues(alpha: 0.4)
      : Colors.black.withValues(alpha: 0.16);

  /// Brand primary that adapts (light = darker green, dark = brighter green).
  static Color brandPrimary(BuildContext context) =>
      _isDark(context) ? AppColors.brandGreen : AppColors.brandGreenDark;
}
