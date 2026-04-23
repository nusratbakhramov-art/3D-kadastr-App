import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme/app_colors.dart';

class ListingMetaPills extends StatelessWidget {
  const ListingMetaPills({
    super.key,
    required this.district,
    required this.areaM2,
  });

  final String district;
  final int areaM2;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Pill(iconAsset: 'assets/icons/map.svg', text: district),
        _Pill(iconAsset: 'assets/icons/ruler-triangle.svg', text: '$areaM2 m²'),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.iconAsset, required this.text});

  final String iconAsset;
  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF121617) : Colors.white;
    final fg = isDark ? Colors.white : AppColors.textBlack;
    final border = isDark
        ? BorderSide.none
        : const BorderSide(color: Color(0xFFE3E5E8));

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: border == BorderSide.none
            ? null
            : Border.fromBorderSide(border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(iconAsset, width: 16, height: 16),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w500,
              fontSize: 13,
              height: 1.2,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
