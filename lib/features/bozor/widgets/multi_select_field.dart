/// Ko'p tanlovli yopiq qator + uning varag'i.
///
/// Yopiq holatda dizayndagidek qisqartirib ko'rsatadi: birinchi ikkita qiymat,
/// qolgani "va yana N" ("Школа, Детский сад и еще 3"). Chegara ikkita — chunki
/// uchinchisi 375pt li ekranda sig'may ketardi va qator kengligiga qarab
/// o'zgaruvchi kesish ro'yxatni har ekranda boshqacha ko'rsatardi.
library;

import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../theme/app_colors.dart';
import '../../services/widgets/choice_tile.dart';
import '../../market/widgets/listing_cta_button.dart';

/// Ko'rsatiladigan qiymatlar soni — qolgani "va yana N" bo'lib yig'iladi.
const int _visibleValues = 2;

class MultiSelectField extends StatelessWidget {
  const MultiSelectField({
    super.key,
    required this.label,
    required this.values,
    required this.placeholder,
    required this.onTap,
    required this.moreLabel,
    this.enabled = true,
    this.required = false,
  });

  final String label;
  final List<String> values;
  final String placeholder;
  final VoidCallback onTap;

  /// "va yana %d" ko'rinishidagi tarjima — `%d` almashtiriladi.
  final String moreLabel;
  final bool enabled;
  final bool required;

  String get _summary {
    if (values.isEmpty) return placeholder;
    if (values.length <= _visibleValues) return values.join(', ');
    final head = values.take(_visibleValues).join(', ');
    final rest = values.length - _visibleValues;
    return '$head ${moreLabel.replaceAll('%d', '$rest')}';
  }

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
    final filled = values.isNotEmpty;

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
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _summary,
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
                      // Dizaynda ko'p tanlovning ikonkasi bir tanlovnikidan
                      // FARQ QILADI (belgilangan ro'yxat) — o'sha farqni
                      // saqlaymiz, aks holda ikki xil qator bir xil ko'rinadi.
                      child: Icon(
                        Icons.checklist_rounded,
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

/// Ko'p tanlovli varaq. Tanlanganlar ro'yxati qaytadi; bekor qilinsa `null`.
Future<List<String>?> showMultiOptionPickerSheet(
  BuildContext context, {
  required String title,
  required List<String> options,
  required List<String> selected,
  required String confirmLabel,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MultiPickerSheet(
      title: title,
      options: options,
      selected: selected,
      confirmLabel: confirmLabel,
    ),
  );
}

class _MultiPickerSheet extends StatefulWidget {
  const _MultiPickerSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.confirmLabel,
  });

  final String title;
  final List<String> options;
  final List<String> selected;
  final String confirmLabel;

  @override
  State<_MultiPickerSheet> createState() => _MultiPickerSheetState();
}

class _MultiPickerSheetState extends State<_MultiPickerSheet> {
  late final Set<String> _picked = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF15191B) : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.textBlack;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : const Color(0xFFD9DEE1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                widget.title,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final option in widget.options) ...[
                        // Bitta tanlovdan farqi: varaq YOPILMAYDI, belgi
                        // qo'yiladi va keyingisini tanlash mumkin.
                        ChoiceTile(
                          label: option,
                          selected: _picked.contains(option),
                          onTap: () => setState(() {
                            if (!_picked.remove(option)) _picked.add(option);
                          }),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              ListingCtaButton(
                label: widget.confirmLabel,
                onTap: () => Navigator.of(context).pop(
                  // Tanlash tartibi emas, ro'yxat tartibi saqlanadi — yopiq
                  // qatordagi qisqartma har safar bir xil chiqsin.
                  widget.options.where(_picked.contains).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
