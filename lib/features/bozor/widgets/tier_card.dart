/// Tarif kartasi — "Standart e'lon" / "«Top» ga yuborish".
///
/// Dizaynda ikkala karta AYNAN bir xil chiziladi: tanlanganini faqat radio
/// belgisi bildiradi — ramka ham, fon ham o'zgarmaydi. Bu 20pt li bitta
/// belgiga tayanish demak, shuning uchun bu yerda tanlangan kartaning ramkasi
/// ham yashil qilindi (ilovaning [ChoiceTile] idagi bilan bir xil qoida) va
/// [Semantics] qo'shildi.
///
/// ⓘ tugmasi kartani tanlashdan ALOHIDA nishon: u tarif nima ekanini
/// tushuntiradi, tanlamaydi.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/haptics.dart';
import '../../../theme/app_colors.dart';

class TierCard extends StatelessWidget {
  const TierCard({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.onInfo,
    this.showRocket = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onInfo;

  /// "Top" tarifida yorliq yonida raketa chiqadi.
  final bool showRocket;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1F2426) : Colors.white;
    final idleBorder =
        isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final idleRadio =
        isDark ? const Color(0xFF3A4042) : const Color(0xFFD1D5D9);
    final infoColor =
        isDark ? const Color(0xFF5A6167) : const Color(0xFFBECAD7);
    final radius = BorderRadius.circular(16);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: hapticSelect(onTap),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: selected ? AppColors.splashGreen : idleBorder,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                _Radio(selected: selected, idleColor: idleRadio),
                const SizedBox(width: 12),
                // Yorliq + raketa bitta [Expanded] ichida: ilgari ular
                // yonida `Spacer` turardi va u qolgan joyni teng bo'lib
                // olib, uzun yorliqni ("«Top»ga yuborish") kesib qo'yardi.
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'MTSCompact',
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            height: 1.25,
                            color: textColor,
                          ),
                        ),
                      ),
                      if (showRocket) ...[
                        const SizedBox(width: 8),
                        SvgPicture.asset(
                          'assets/icons/tier-rocket.svg',
                          width: 20,
                          height: 20,
                        ),
                      ],
                    ],
                  ),
                ),
                // Alohida nishon — kartani tanlamaydi. 44pt teginish maydoni.
                GestureDetector(
                  onTap: hapticTap(onInfo),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: Icon(
                        Icons.info_rounded,
                        size: 20,
                        color: infoColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [ChoiceTile] dagi bilan bir xil radio — ilovada tanlov belgisi bitta
/// ko'rinishda bo'lsin.
class _Radio extends StatelessWidget {
  const _Radio({required this.selected, required this.idleColor});

  final bool selected;
  final Color idleColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.splashGreen : Colors.transparent,
        border: Border.all(
          color: selected ? AppColors.splashGreen : idleColor,
          width: 2,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            )
          : null,
    );
  }
}
