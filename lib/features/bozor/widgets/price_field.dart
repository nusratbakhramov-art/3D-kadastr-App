/// Narx maydoni — bitta quti, ichida ikkita teginish zonasi.
///
/// Chapda raqam kiritiladi, o'ngda birlik (`UZS/oy`) bosilib almashtiriladi.
/// Dizaynda bu ALOHIDA ikkita widget emas: bitta chegara, bitta fon, ular
/// orasida faqat ingichka tik chiziqcha (chegaraning o'zi bilan bir xil
/// rangda, shuning uchun ajratuvchi emas, chok bo'lib ko'rinadi).
///
/// Valyuta va davr AJRALMAYDI — `UZS/oy` bitta matn, bitta shevron, bitta
/// tanlov. Dizaynda ular alohida bosiladigan qilib chizilmagan.
library;

import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../theme/app_colors.dart';
import 'amount_input_formatter.dart';

class PriceField extends StatelessWidget {
  const PriceField({
    super.key,
    required this.label,
    required this.controller,
    required this.unit,
    required this.onPickUnit,
    this.required = false,
  });

  final String label;
  final TextEditingController controller;

  /// Yopiq holatda ko'rinadigan birlik tokeni.
  final String unit;
  final VoidCallback onPickUnit;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark ? Colors.white : AppColors.textBlack;
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : const Color(0xFFB4B9BF);
    final unitColor = isDark ? Colors.white : AppColors.textBlack;
    final chevronColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF6E7480);

    final radius = BorderRadius.circular(14);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  height: 1.25,
                  color: labelColor,
                ),
              ),
            ),
            if (required)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text(
                  '*',
                  style: TextStyle(color: Color(0xFFE0492A), fontSize: 14),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: radius,
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  keyboardType: const TextInputType.numberWithOptions(),
                  // Guruhlash KIRITISH paytida: `5002323` → `5 002 323`.
                  // Kursor o'z joyida qoladi, ya'ni raqamni o'rtasidan ham
                  // tuzatish mumkin — [AmountInputFormatter] ga qarang.
                  inputFormatters: const [AmountInputFormatter()],
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 14.5,
                    color: textColor,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    hintText: '0',
                    hintStyle: TextStyle(
                      fontFamily: 'MTSText',
                      fontSize: 14.5,
                      color: hintColor,
                    ),
                    // Chegara tashqi [Container] da — maydonning o'zi
                    // chegarasiz, aks holda ikkita ramka chiqardi.
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              // Chok + birlik + shevron — BITTA teginish zonasi.
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: hapticSelect(onPickUnit),
                  borderRadius: BorderRadius.only(
                    topRight: radius.topRight,
                    bottomRight: radius.bottomRight,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 1, height: 26, color: border),
                        const SizedBox(width: 10),
                        Text(
                          unit,
                          style: TextStyle(
                            fontFamily: 'MTSText',
                            fontWeight: FontWeight.w500,
                            fontSize: 14.5,
                            color: unitColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.expand_more_rounded,
                          size: 20,
                          color: chevronColor,
                        ),
                      ],
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
