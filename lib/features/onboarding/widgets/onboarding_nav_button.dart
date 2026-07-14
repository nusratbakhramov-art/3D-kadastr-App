import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/haptics.dart';
import '../../../theme/app_colors.dart';

enum OnboardingNavVariant { primary, secondary }

class OnboardingNavButton extends StatelessWidget {
  const OnboardingNavButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.variant,
  });

  final String label;
  final VoidCallback onPressed;
  final OnboardingNavVariant variant;

  @override
  Widget build(BuildContext context) {
    final isPrimary = variant == OnboardingNavVariant.primary;
    const radius = 999.0;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isPrimary) ...[
            SvgPicture.asset(
              'assets/icons/arrow.svg',
              width: 18,
              height: 18,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: isPrimary ? AppColors.buttonTextBlack : Colors.white,
            ),
          ),
          if (isPrimary) ...[
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: AppColors.buttonTextBlack,
            ),
          ],
        ],
      ),
    );

    if (isPrimary) {
      return Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: hapticTap(onPressed),
          child: SizedBox(height: 52, child: Center(child: content)),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: const Color(0x0FFFFFFF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: const BorderSide(color: Color(0x1FFFFFFF), width: 1),
          ),
          child: InkWell(
            onTap: hapticTap(onPressed),
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
            ),
            child: SizedBox(height: 52, child: Center(child: content)),
          ),
        ),
      ),
    );
  }
}
