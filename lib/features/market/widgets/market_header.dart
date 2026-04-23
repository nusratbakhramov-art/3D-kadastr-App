import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

class MarketHeader extends StatelessWidget {
  const MarketHeader({
    super.key,
    required this.title,
    required this.onFilterTap,
  });

  final String title;
  final VoidCallback onFilterTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    final buttonBg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.92);

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 48,
              height: 1,
              color: titleColor,
            ),
          ),
        ),
        Material(
          color: buttonBg,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onFilterTap,
            child: SizedBox(
              width: 52,
              height: 52,
              child: Icon(
                Icons.tune_rounded,
                size: 28,
                color: isDark ? Colors.white : AppColors.textBlack,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
