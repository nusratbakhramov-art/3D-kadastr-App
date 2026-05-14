import 'package:flutter/cupertino.dart';
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

    DateTime tempPicked = initial;

    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final sheetBg = isDark ? const Color(0xFF121214) : Colors.white;
        final textColor = isDark ? Colors.white : AppColors.textBlack;
        final dividerColor = isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.08);

        return SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              color: sheetBg,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Tug‘ilgan sana',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: textColor),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: dividerColor),
                SizedBox(
                  height: 220,
                  child: CupertinoTheme(
                    data: CupertinoThemeData(
                      brightness: isDark ? Brightness.dark : Brightness.light,
                      textTheme: CupertinoTextThemeData(
                        dateTimePickerTextStyle: TextStyle(
                          fontSize: 20,
                          color: textColor,
                        ),
                      ),
                    ),
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.date,
                      initialDateTime: initial,
                      minimumDate: DateTime(1900),
                      maximumDate: now,
                      dateOrder: DatePickerDateOrder.mdy,
                      onDateTimeChanged: (d) => tempPicked = d,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () => Navigator.of(ctx).pop(tempPicked),
                      child: const Text(
                        'Tasdiqlash',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (picked != null) onChanged(picked);
    // ignore unused locale (CupertinoDatePicker uses ambient localization)
    locale?.toString();
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
