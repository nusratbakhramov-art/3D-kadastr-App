import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../../../widgets/pressable_scale.dart';

/// Secondary "skip" pill shown under the primary scan CTA.
///
/// A ghost/outlined counterpart to [ListingCtaButton]: same pill shape and
/// press feel, but a transparent body with a muted border so it reads clearly
/// as the secondary action. Lets the user continue the flow without a 3D scan.
class ScanSkipButton extends StatelessWidget {
  const ScanSkipButton({
    super.key,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = enabled
        ? (isDark
              ? Colors.white.withValues(alpha: 0.18)
              : const Color(0xFFD6DBE0))
        : (isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFEAEDF0));
    final fg = enabled
        ? (isDark ? Colors.white.withValues(alpha: 0.85) : AppColors.textBlack)
        : (isDark
              ? Colors.white.withValues(alpha: 0.4)
              : const Color(0xFFB0B6BD));

    return PressableScale(
      enabled: enabled,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled
              ? () {
                  HapticFeedback.lightImpact();
                  onTap();
                }
              : null,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border, width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    height: 1.2,
                    color: fg,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.redo_rounded, size: 18, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
