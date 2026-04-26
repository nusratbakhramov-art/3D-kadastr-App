import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

class StepProgressBar extends StatelessWidget {
  const StepProgressBar({
    super.key,
    required this.count,
    required this.activeIndex,
  });

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final active = isDark ? Colors.white : AppColors.textBlack;
    final idle = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);

    return Row(
      children: List<Widget>.generate(count, (i) {
        final isActive = i <= activeIndex;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == count - 1 ? 0 : 8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              height: 4,
              decoration: BoxDecoration(
                color: isActive ? active : idle,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        );
      }),
    );
  }
}
