/// Yopiq "tanlov" qatori — bosilganda [showOptionPickerSheet] ochiladi.
///
/// Ko'rinishi ataylab [WizardField] bilan bir xil (14 radius, o'sha to'ldirish
/// va chegara ranglari, o'sha ichki bo'shliq): bitta formada matn maydoni va
/// tanlov qatori yonma-yon turganda ular bir oilaga o'xshashi kerak.
/// Dizayndagi o'ng tarafdagi "ro'yxat" tugmachasi saqlangan — u qatorning
/// bosilishini va ro'yxat ochilishini bildiradi.
library;

import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../theme/app_colors.dart';

class SelectField extends StatelessWidget {
  const SelectField({
    super.key,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onTap,
    this.enabled = true,
    this.required = false,
  });

  final String label;

  /// Tanlangan qiymat matni. `null` — hali tanlanmagan, [placeholder] chiqadi.
  final String? value;
  final String placeholder;
  final VoidCallback onTap;

  /// O'chiq qator bosilmaydi va xiraroq chiziladi — masalan mulk toifasi
  /// tanlanmaguncha mulk turi tanlanmaydi.
  final bool enabled;
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
    final iconBg = isDark ? const Color(0xFF2A2F32) : const Color(0xFFEEF1F0);
    final iconFg = isDark
        ? Colors.white.withValues(alpha: 0.7)
        : const Color(0xFF6E7480);

    final radius = BorderRadius.circular(14);
    final filled = value != null;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Column(
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
          Material(
            color: fill,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? hapticSelect(onTap) : null,
              child: Container(
                // Balandligi [WizardField] bilan bir xil chiqishi uchun
                // vertikal bo'shliq 10: ichidagi 28pt li tugmacha matndan
                // baland, shuning uchun 14 emas.
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        value ?? placeholder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'MTSText',
                          fontSize: 14.5,
                          color: filled ? textColor : hintColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: iconBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.format_list_bulleted_rounded,
                        size: 16,
                        color: iconFg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
