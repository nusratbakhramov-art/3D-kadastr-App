/// Manzilni xaritadan tanlash uchun bosiladigan maydon.
///
/// Tanlangan manzil matnini ko'rsatadi; bosilganda `LocationPickerScreen`
/// ochiladi va natija `onChanged` orqali qaytariladi.
library;

import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../theme/app_colors.dart';
import '../models/ai_baholash_bundle.dart';
import '../screens/location_picker_screen.dart';

class LocationPickerField extends StatelessWidget {
  const LocationPickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.required = false,
  });

  final String label;
  final AiLocationInfo? value;
  final ValueChanged<AiLocationInfo> onChanged;
  final bool required;

  Future<void> _open(BuildContext context) async {
    final result = await Navigator.of(context).push<AiLocationInfo>(
      MaterialPageRoute<AiLocationInfo>(
        builder: (_) => LocationPickerScreen(initial: value),
      ),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
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

    final v = value;
    final hasValue = v != null;
    final title = hasValue
        ? (v.addressText ?? _LocationFieldStrings.selectedPoint(l))
        : _LocationFieldStrings.pickOnMap(l);

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
                child: Text('*',
                    style: TextStyle(color: Color(0xFFE0492A), fontSize: 14)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Material(
          color: fill,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: hapticTap(() => _open(context)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  Icon(
                    hasValue ? Icons.place : Icons.add_location_alt_outlined,
                    color: AppColors.splashGreen,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'MTSText',
                            fontSize: 14.5,
                            color: hasValue ? textColor : hintColor,
                          ),
                        ),
                        if (hasValue) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${v.lat.toStringAsFixed(5)}, ${v.lng.toStringAsFixed(5)}',
                            style: TextStyle(
                              fontFamily: 'MTSText',
                              fontSize: 11,
                              color: subColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: subColor, size: 22),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LocationFieldStrings {
  const _LocationFieldStrings._();

  static String selectedPoint(Locale l) => switch (l.languageCode) {
        'ru' => 'Выбранная точка',
        'en' => 'Selected point',
        _ => 'Tanlangan nuqta',
      };

  static String pickOnMap(Locale l) => switch (l.languageCode) {
        'ru' => 'Выберите адрес на карте',
        'en' => 'Pick an address on the map',
        _ => 'Manzilni xaritadan tanlang',
      };
}
