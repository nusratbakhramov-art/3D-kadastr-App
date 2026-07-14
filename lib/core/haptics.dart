import 'package:flutter/services.dart';

/// Tap-haptic helpers. Wrap an interactive widget's callback so every
/// actionable button/card emits tactile feedback before running its handler.
///
/// Both helpers are null-safe: wrapping a `null` callback returns `null`, so a
/// disabled control stays disabled (and never buzzes). Use [hapticTap] for
/// buttons, cards and navigation; [hapticSelect] for toggles, tabs, chips and
/// other selection controls.

/// Light-impact haptic for taps on buttons, cards and navigation targets.
VoidCallback? hapticTap(VoidCallback? onTap) {
  if (onTap == null) return null;
  return () {
    HapticFeedback.lightImpact();
    onTap();
  };
}

/// Selection-click haptic for toggles, tabs, chips and segmented controls.
VoidCallback? hapticSelect(VoidCallback? onTap) {
  if (onTap == null) return null;
  return () {
    HapticFeedback.selectionClick();
    onTap();
  };
}
