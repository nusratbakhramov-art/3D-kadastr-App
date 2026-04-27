import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../widgets/circle_chevron_right.dart';

class HomeCard extends StatelessWidget {
  const HomeCard({
    super.key,
    required this.title,
    required this.iconAsset,
    this.onTap,
  });

  final String title;
  final String iconAsset;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF121617) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF101113);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: isDark
          ? BorderSide.none
          : const BorderSide(color: Color(0xFFE1E1E1), width: 1),
    );

    return Material(
      color: cardColor,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SvgPicture.asset(iconAsset, width: 32, height: 32),
                  const Spacer(),
                  const CircleChevronRight(),
                ],
              ),
              const Spacer(),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                  height: 1.3,
                ).copyWith(color: textColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
