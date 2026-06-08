/// Ranglarni nom o'rniga namuna (swatch) sifatida tanlash uchun maydon.
///
/// Bir nechta rang tanlanadi + qo'shimcha (erkin matn) izoh kiritiladi.
/// Natija bitta satr sifatida `onChanged` orqali qaytariladi — mavjud
/// `colors` (String) maydoniga mos.
library;

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../data/calculator_pricing_store.dart';
import '../models/calculator_pricing.dart';

const String _kDetailSep = ' — ';

class ColorPaletteField extends StatefulWidget {
  const ColorPaletteField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.detailPlaceholder,
  });

  final String label;

  /// Oldingi qiymat (nomlar ", " bilan, izoh " — " dan keyin).
  final String? value;
  final ValueChanged<String> onChanged;
  final String? detailPlaceholder;

  @override
  State<ColorPaletteField> createState() => _ColorPaletteFieldState();
}

class _ColorPaletteFieldState extends State<ColorPaletteField> {
  // Tanlangan mashina qiymatlari ('oq', 'bej' …) — tildan mustaqil.
  final Set<String> _selected = {};
  late final TextEditingController _detail;
  Locale _locale = const Locale('uz');

  // Ranglar katalogi (backend → kesh → default fallback).
  List<CalcOption> get _opts =>
      calculatorPricingNotifier.value.optionsFor('colors');

  @override
  void initState() {
    super.initState();
    final initial = widget.value ?? '';
    String namesPart = initial;
    String detailPart = '';
    final sepIdx = initial.indexOf(_kDetailSep);
    if (sepIdx != -1) {
      namesPart = initial.substring(0, sepIdx);
      detailPart = initial.substring(sepIdx + _kDetailSep.length);
    }
    final opts = _opts;
    final leftover = <String>[];
    for (final raw in namesPart.split(',')) {
      final n = raw.trim();
      if (n.isEmpty) continue;
      // Qiymat yoki har qanday tildagi label bo'yicha moslashtiramiz.
      final match = opts.where((o) =>
          o.value == n ||
          o.label.values.any((lbl) => lbl.toLowerCase() == n.toLowerCase()));
      if (match.isNotEmpty) {
        _selected.add(match.first.value);
      } else {
        leftover.add(n);
      }
    }
    if (leftover.isNotEmpty) {
      detailPart = detailPart.isEmpty
          ? leftover.join(', ')
          : '${leftover.join(', ')}, $detailPart';
    }
    _detail = TextEditingController(text: detailPart);
    _detail.addListener(_emit);
  }

  @override
  void dispose() {
    _detail.removeListener(_emit);
    _detail.dispose();
    super.dispose();
  }

  void _emit() {
    // Katalog tartibida tanlangan ranglar — joriy tildagi nomlar.
    final names = [
      for (final o in _opts)
        if (_selected.contains(o.value)) o.localized(_locale),
    ].join(', ');
    final detail = _detail.text.trim();
    final combined = detail.isEmpty
        ? names
        : (names.isEmpty ? detail : '$names$_kDetailSep$detail');
    widget.onChanged(combined);
  }

  void _toggle(String value) {
    setState(() {
      if (!_selected.add(value)) _selected.remove(value);
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    _locale = l;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark ? Colors.white : AppColors.textBlack;
    final swatchBorder =
        isDark ? const Color(0xFF3A4042) : const Color(0xFFD1D5D9);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            height: 1.25,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final o in _opts)
              _Swatch(
                name: o.localized(l),
                color: o.color ?? const Color(0xFF9AA0A6),
                selected: _selected.contains(o.value),
                idleBorder: swatchBorder,
                onTap: () => _toggle(o.value),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _DetailField(
          controller: _detail,
          placeholder:
              widget.detailPlaceholder ?? _ColorPaletteStrings.detailHint(l),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.name,
    required this.color,
    required this.selected,
    required this.idleBorder,
    required this.onTap,
  });

  final String name;
  final Color color;
  final bool selected;
  final Color idleBorder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    // Oq/och ranglar uchun check belgisi qora bo'lsin.
    final luminance = color.computeLuminance();
    final checkColor = luminance > 0.6 ? Colors.black87 : Colors.white;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.splashGreen : idleBorder,
                width: selected ? 2.5 : 1,
              ),
            ),
            child: selected
                ? Icon(Icons.check_rounded, size: 22, color: checkColor)
                : null,
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: 52,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'MTSText',
                fontSize: 11,
                color: textColor.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({required this.controller, required this.placeholder});

  final TextEditingController controller;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : const Color(0xFFB4B9BF);

    return TextField(
      controller: controller,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      style: TextStyle(fontFamily: 'MTSText', fontSize: 14.5, color: textColor),
      decoration: InputDecoration(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintText: placeholder,
        hintStyle:
            TextStyle(fontFamily: 'MTSText', fontSize: 14.5, color: hintColor),
        filled: true,
        fillColor: fill,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.splashGreen, width: 1.4),
        ),
      ),
    );
  }
}

class _ColorPaletteStrings {
  const _ColorPaletteStrings._();

  static String detailHint(Locale l) => switch (l.languageCode) {
        'ru' => 'Дополнительная деталь или предпочтение',
        'en' => 'Additional detail or preference',
        _ => 'Qo\'shimcha tafsilot yoki afzallik',
      };
}
