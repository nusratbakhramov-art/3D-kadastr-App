import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

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
    final isActive = enabled && !loading;
    final bg = isActive
        ? AppColors.splashGreen
        : Colors.white.withValues(alpha: 0.12);
    final fg = isActive ? Colors.black : Colors.white.withValues(alpha: 0.55);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isActive ? onPressed : null,
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
    );
  }
}
