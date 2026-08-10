import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Bottom-drawer'lardagi bitta to'liq enlikdagi pill tugma.
///
/// Ilovadagi barcha pastki oynalar shu tugmadan foydalanadi — balandlik,
/// radius va shrift bir joyda turgani uchun oynalar bir xil ko'rinadi
/// (ilgari har oyna o'z tugmasini yasab, dizayn bir-biridan uzoqlashib
/// ketgandi).
class SheetButton extends StatelessWidget {
  const SheetButton({
    super.key,
    required this.label,
    required this.isDark,
    required this.onTap,
    this.filled = false,
    this.destructive = false,
    this.icon,
  });

  final String label;
  final bool isDark;
  final VoidCallback onTap;

  /// Brend yashili bilan to'ldirilgan asosiy tugma.
  final bool filled;

  /// O'chirish kabi qaytarib bo'lmaydigan amal — qizil tonal ko'rinish.
  final bool destructive;

  final IconData? icon;

  static const Color _red = Color(0xFFD64545);

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    if (destructive) {
      bg = _red.withValues(alpha: isDark ? 0.16 : 0.10);
      fg = _red;
    } else if (filled) {
      bg = AppColors.splashGreen;
      fg = AppColors.buttonTextBlack;
    } else {
      bg = isDark
          ? Colors.white.withValues(alpha: 0.07)
          : const Color(0xFFF1F2F4);
      fg = isDark
          ? Colors.white.withValues(alpha: 0.85)
          : const Color(0xFF6C7278);
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 54,
          width: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 19, color: fg),
                const SizedBox(width: 9),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: filled ? FontWeight.w700 : FontWeight.w600,
                  fontSize: 16,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
