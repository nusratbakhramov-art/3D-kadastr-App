import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/pressable_scale.dart';

class PrimaryCta extends StatelessWidget {
  const PrimaryCta({
    super.key,
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isActive = enabled && !loading;
    final bg = isActive
        ? AppColors.splashGreen
        : (isDark
              ? Colors.white.withValues(alpha: 0.12)
              : const Color(0xFFE4E7EB));
    final fg = isActive
        ? Colors.black
        : (isDark
              ? Colors.white.withValues(alpha: 0.55)
              : const Color(0xFF8A9097));
    return PressableScale(
      enabled: isActive,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: hapticTap(isActive ? onPressed : null),
        child: SizedBox(
          height: 56,
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.black,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: fg,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'MTSCompact',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.arrow_forward, color: fg, size: 18),
                    ],
                  ),
          ),
        ),
      ),
      ),
    );
  }
}
