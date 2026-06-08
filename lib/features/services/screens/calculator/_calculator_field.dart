import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../theme/app_colors.dart';

/// Numeric area / amount input shared across calculator forms.
class CalculatorField extends StatelessWidget {
  const CalculatorField({
    super.key,
    required this.label,
    required this.placeholder,
    required this.controller,
    this.suffix,
    this.allowDecimal = true,
  });

  final String label;
  final String placeholder;
  final TextEditingController controller;
  final String? suffix;
  final bool allowDecimal;

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
    final suffixColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    final allow = allowDecimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 16,
            height: 1.25,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          onTapOutside: (_) => FocusScope.of(context).unfocus(),
          keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
          inputFormatters: [FilteringTextInputFormatter.allow(allow)],
          style: TextStyle(
            fontFamily: 'MTSText',
            fontSize: 15,
            color: textColor,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
            hintText: placeholder,
            hintStyle: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 15,
              color: hintColor,
            ),
            suffixText: suffix,
            suffixStyle: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 14,
              color: suffixColor,
            ),
            filled: true,
            fillColor: fill,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.splashGreen, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}

class CalculatorSectionLabel extends StatelessWidget {
  const CalculatorSectionLabel({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white : AppColors.textBlack;
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'MTSCompact',
        fontWeight: FontWeight.w700,
        fontSize: 16,
        height: 1.25,
        color: color,
      ),
    );
  }
}

/// Foydalanuvchi kiritgan raqamni xavfsiz o'qish.
///
/// Mingliklar ajratuvchisi (vergul yoki bo'sh joy), o'nlik vergul va tasodifiy
/// ortiqcha belgilarni normallashtiradi — shunda "1 200,5" yoki "1,2.3" kabi
/// kiritishlar jimgina `null` ga aylanib qolmaydi.
double? parseAmount(String s) {
  var t = s.trim();
  if (t.isEmpty) return null;
  // Faqat raqam, nuqta va vergulni qoldiramiz.
  t = t.replaceAll(RegExp(r'[^0-9.,]'), '');
  if (t.isEmpty) return null;
  if (t.contains(',') && t.contains('.')) {
    // Ikkalasi ham bo'lsa — vergul mingliklar ajratuvchisi deb olinadi.
    t = t.replaceAll(',', '');
  } else {
    t = t.replaceAll(',', '.');
  }
  // Bir nechta nuqta bo'lsa, birinchisini o'nlik sifatida saqlaymiz.
  final firstDot = t.indexOf('.');
  if (firstDot != -1) {
    final intPart = t.substring(0, firstDot);
    final fracPart = t.substring(firstDot + 1).replaceAll('.', '');
    t = '$intPart.$fracPart';
  }
  return double.tryParse(t);
}
