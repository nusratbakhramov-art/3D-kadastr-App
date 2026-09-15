/// Telefon raqami qatori — `+998` prefiksi maydon ichida qat'iy turadi.
///
/// Ko'rinishi [WizardField] bilan bir xil (14 radius, o'sha to'ldirish va
/// chegara), lekin ichida ikkita qism bor: o'zgarmas `+998` va niqoblangan
/// milliy qism. Niqob [UzPhoneMaskFormatter] dan — u kursorni qayta
/// formatlash orqali olib o'tadi, shuning uchun o'rtadan o'chirish kursorni
/// oxiriga uloqtirmaydi.
///
/// Ikkinchi va undan keyingi raqamlarda yorliq yonida o'chirish tugmasi
/// chiqadi: dizaynda qator qo'shish bor, olib tashlash yo'q — qo'shib
/// yuborilgan ortiqcha qatordan chiqib bo'lmay qolardi.
library;

import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/uz_phone_mask_formatter.dart';

class BozorPhoneField extends StatelessWidget {
  const BozorPhoneField({
    super.key,
    required this.label,
    required this.controller,
    this.required = false,
    this.onRemove,
    this.removeLabel,
  });

  final String label;
  final TextEditingController controller;
  final bool required;

  /// `null` — o'chirish tugmasi chizilmaydi (birinchi qator).
  final VoidCallback? onRemove;
  final String? removeLabel;

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
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    final radius = BorderRadius.circular(14);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                height: 1.25,
                color: labelColor,
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
            const Spacer(),
            if (onRemove != null)
              GestureDetector(
                onTap: hapticSelect(onRemove),
                child: Text(
                  removeLabel ?? '',
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: subColor,
                  ),
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
              Padding(
                padding: const EdgeInsets.only(left: 14, right: 8),
                child: Text(
                  '+998',
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontWeight: FontWeight.w500,
                    fontSize: 14.5,
                    color: textColor,
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  keyboardType: TextInputType.phone,
                  inputFormatters: const [UzPhoneMaskFormatter()],
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 14.5,
                    color: textColor,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.fromLTRB(0, 14, 14, 14),
                    hintText: '90 123-45-67',
                    hintStyle: TextStyle(
                      fontFamily: 'MTSText',
                      fontSize: 14.5,
                      color: hintColor,
                    ),
                    // Chegara tashqi [Container] da.
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
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
