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
        ListingMetaPill(iconAsset: 'assets/icons/map.svg', text: district),
        ListingMetaPill(
          iconAsset: 'assets/icons/ruler-triangle.svg',
          text: '$areaM2 m²',
        ),
      ],
    );
  }
}

/// Bitta yumaloq "nishon" — tuman, maydon, xona soni va shunga o'xshash qisqa
/// fakt uchun.
///
/// [ListingMetaPills] ning ichidan chiqarilgan: "Bozor AI" e'lonida nishonlar
/// to'plami boshqa (viloyat+tuman, xona soni, mulk turi — ba'zilari YO'Q
/// bo'lishi mumkin), shuning uchun u qatorni o'zi yig'adi, lekin nishonning
/// ko'rinishi bitta joyda qoladi.
class ListingMetaPill extends StatelessWidget {
  const ListingMetaPill({super.key, this.iconAsset, required this.text});

  /// Ikonkasiz nishon ham bo'ladi (masalan mulk turi) — `null` bo'lsa faqat
  /// matn chiziladi.
  final String? iconAsset;
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
          if (iconAsset != null) ...[
            SvgPicture.asset(iconAsset!, width: 16, height: 16),
            const SizedBox(width: 8),
          ],
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
