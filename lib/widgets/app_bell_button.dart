import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Circular bell button used in screen headers. Shows a small red dot when
/// [hasUnread] is true.
class AppBellButton extends StatelessWidget {
  const AppBellButton({
    super.key,
    required this.hasUnread,
    this.onTap,
    this.size = 40,
    this.dotKey,
  });

  final bool hasUnread;
  final VoidCallback? onTap;
  final double size;
  final Key? dotKey;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF1A1F21) : Colors.white;
    final iconColor = isDark ? Colors.white : AppColors.textBlack;
    final dotBorderColor = isDark ? const Color(0xFF000702) : Colors.white;
    final iconSize = size * 0.5;

    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: backgroundColor,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0F000000),
                    blurRadius: 8,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.notifications_none_rounded,
                size: iconSize,
                color: iconColor,
              ),
            ),
            if (hasUnread)
              Positioned(
                top: size * 0.1,
                right: size * 0.1,
                child: Container(
                  key: dotKey,
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF3B30),
                    shape: BoxShape.circle,
                    border: Border.all(color: dotBorderColor, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
