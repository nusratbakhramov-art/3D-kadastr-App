import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

class ScanTipsCard extends StatelessWidget {
  const ScanTipsCard({super.key, required this.tips});

  final List<String> tips;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A2530) : const Color(0xFFE2EBF6);
    final divider = isDark ? const Color(0xFF2C3133) : const Color(0xFFCFDDED);
    final textColor = isDark ? Colors.white : AppColors.textBlack;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < tips.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.splashGreen,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tips[i],
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                        height: 1.3,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (i != tips.length - 1) Container(height: 1, color: divider),
          ],
        ],
      ),
    );
  }
}
