import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/haptics.dart';
import '../../../theme/app_colors.dart';

class MarketHeader extends StatelessWidget {
  const MarketHeader({
    super.key,
    required this.title,
    required this.onFilterTap,
    this.filterActiveCount = 0,
  });

  final String title;
  final VoidCallback onFilterTap;
  final int filterActiveCount;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    final buttonBg = isDark ? const Color(0xFF121617) : Colors.white;
    final buttonFg = isDark ? Colors.white : AppColors.textBlack;
    final border = isDark ? null : Border.all(color: const Color(0xFFE1E1E1));

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 24,
              height: 1.3,
              color: titleColor,
            ),
          ),
        ),
        SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Material(
                color: buttonBg,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: Ink(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: border,
                  ),
                  child: InkWell(
                    onTap: hapticTap(onFilterTap),
                    customBorder: const CircleBorder(),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: SvgPicture.asset(
                          'assets/icons/filter.svg',
                          width: 20,
                          height: 20,
                          colorFilter: ColorFilter.mode(
                            buttonFg,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: IgnorePointer(
                  child: AnimatedScale(
                    scale: filterActiveCount > 0 ? 1 : 0,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutBack,
                    child: AnimatedOpacity(
                      opacity: filterActiveCount > 0 ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: _CountBadge(
                        count: filterActiveCount > 0 ? filterActiveCount : 1,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: AppColors.splashGreen,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        count.toString(),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'MTSCompact',
          fontWeight: FontWeight.w700,
          fontSize: 10,
          height: 1,
          color: AppColors.buttonTextBlack,
        ),
      ),
    );
  }
}
