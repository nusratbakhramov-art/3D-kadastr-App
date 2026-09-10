/// Bitta variantni tanlash varag'i — "Bozor AI" sehrgaridagi HAR BIR
/// `select` maydoni shu varaqni ochadi.
///
/// Chizmasi [showRoomPickerSheet] bilan bir xil (12pt hoshiya, 20 radius,
/// tortish dastagi, [ChoiceTile] ro'yxati) — ilovada varaqlar bitta ko'rinishga
/// ega bo'lsin. Farqi: bu generic va tanlangan zahoti yopiladi, chunki bu
/// yerda "Boshqa" kabi qo'shimcha kiritish yo'q.
library;

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../services/widgets/choice_tile.dart';

/// Varaqni ochadi. Tanlangan qiymat qaytadi, bekor qilinsa `null`.
///
/// [selected] ro'yxatda belgilanadi. [labelOf] — element matni.
Future<T?> showOptionPickerSheet<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required String Function(T) labelOf,
  T? selected,
  String? subtitle,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _OptionPickerSheet<T>(
      title: title,
      subtitle: subtitle,
      options: options,
      labelOf: labelOf,
      selected: selected,
    ),
  );
}

class _OptionPickerSheet<T> extends StatelessWidget {
  const _OptionPickerSheet({
    required this.title,
    required this.options,
    required this.labelOf,
    this.selected,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<T> options;
  final String Function(T) labelOf;
  final T? selected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF15191B) : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

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
                title,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: textColor,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 13,
                    height: 1.35,
                    color: subColor,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final option in options) ...[
                        ChoiceTile(
                          label: labelOf(option),
                          selected: option == selected,
                          onTap: () => Navigator.of(context).pop(option),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
