import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';

class ListingCtaButton extends StatelessWidget {
  const ListingCtaButton({
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
    final bg = enabled
        ? AppColors.splashGreen
        : (isDark
              ? Colors.white.withValues(alpha: 0.12)
              : const Color(0xFFE4E7EB));
    final fg = enabled
        ? AppColors.buttonTextBlack
        : (isDark
              ? Colors.white.withValues(alpha: 0.55)
              : const Color(0xFF8A9097));

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled
            ? () {
                HapticFeedback.lightImpact();
                onTap();
              }
            : null,
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  height: 1.2,
                  color: fg,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, size: 20, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}
