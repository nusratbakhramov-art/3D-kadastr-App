import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../models/user_profile.dart';

class GenderToggle extends StatelessWidget {
  const GenderToggle({super.key, required this.value, required this.onChanged});

  final Gender? value;
  final ValueChanged<Gender> onChanged;

  void _select(Gender g) {
    if (value == g) return;
    HapticFeedback.selectionClick();
    onChanged(g);
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return Row(
      children: [
        Expanded(
          child: _Pill(
            selected: value == Gender.male,
            label: tr(locale, 'auth.gender.male'),
            accentColor: const Color(0xFF4DA3FF),
            onTap: () => _select(Gender.male),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _Pill(
            selected: value == Gender.female,
            label: tr(locale, 'auth.gender.female'),
            accentColor: const Color(0xFFE57BB9),
            onTap: () => _select(Gender.female),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.selected,
    required this.label,
    required this.accentColor,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.white.withValues(alpha: 0.88);
    final borderColor = selected
        ? AppColors.splashGreen
        : (isDark
              ? Colors.white.withValues(alpha: 0.12)
              : const Color(0xFFD9DDE2));
    final textColor = isDark ? Colors.white : AppColors.textBlack;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.person, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              _Radio(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveBorder = isDark
        ? Colors.white.withValues(alpha: 0.4)
        : AppColors.textBlack.withValues(alpha: 0.4);

    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.splashGreen : Colors.transparent,
        border: Border.all(
          color: selected ? AppColors.splashGreen : inactiveBorder,
          width: 1.5,
        ),
      ),
      child: selected
          ? const Icon(Icons.circle, color: Colors.white, size: 8)
          : null,
    );
  }
}
