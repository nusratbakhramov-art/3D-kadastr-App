import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

class DobField extends StatelessWidget {
  const DobField({super.key, required this.value, required this.onChanged});

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;

  String _format(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.'
      '${d.year}';

  Future<void> _pick(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = Localizations.maybeLocaleOf(context);
    final now = DateTime.now();
    final initial = value ?? DateTime(now.year - 20, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      locale: locale,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme:
              (isDark ? const ColorScheme.dark() : const ColorScheme.light())
                  .copyWith(
                    primary: const Color(0xFF00E135),
                    onPrimary: Colors.black,
                    surface: isDark ? const Color(0xFF0E1A12) : Colors.white,
                    onSurface: isDark ? Colors.white : AppColors.textBlack,
                  ),
        ),
        child: child ?? const SizedBox(),
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldBg = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.white.withValues(alpha: 0.88);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFD9DDE2);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final fadedTextColor = isDark
        ? Colors.white.withValues(alpha: 0.35)
        : AppColors.textBlack.withValues(alpha: 0.35);
    final iconColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : AppColors.textBlack.withValues(alpha: 0.6);
    final text = value == null ? 'kk.oo.yyyy' : _format(value!);
    final faded = value == null;
    return Material(
      color: fieldBg,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _pick(context),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: faded ? fadedTextColor : textColor,
                    fontSize: 16,
                  ),
                ),
              ),
              Icon(Icons.calendar_month_outlined, color: iconColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
