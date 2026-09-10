/// [ParamField] ro'yxatini widget'larga aylantiradigan yagona renderer.
///
/// 3/7 ekrani ham, "Barcha parametrlar" ekrani ham SHU widget'ni ishlatadi —
/// farqi faqat qaysi maydonlar berilishida. Shu sababli ikkala sirt hech
/// qachon bir-biridan uzoqlashib ketmaydi.
///
/// Tanlov ro'yxatlari backenddan keladi va `initState` da BIR MARTA yuklanadi
/// (repozitoriy keshlagani uchun ikkinchi ekranda so'rov ketmaydi). Shu sabab
/// chizish paytida yorliqlar tayyor turadi: `values` ichida KOD saqlanadi,
/// ekranda esa yorliq ko'rinadi.
library;

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import '../../services/widgets/wizard_field.dart';
import '../data/bozor_api.dart';
import '../data/param_options.dart';
import '../models/param_schema.dart';
import 'multi_select_field.dart';
import 'option_picker_sheet.dart';
import 'select_field.dart';

class ParamForm extends StatefulWidget {
  const ParamForm({
    super.key,
    required this.fields,
    required this.values,
    required this.onChanged,
    required this.optionsRepository,
  });

  /// Chiziladigan maydonlar (shart bo'yicha filtrlanmagan — filtr ichkarida).
  final List<ParamField> fields;

  /// Joriy qiymatlar. Widget ularni JOYIDA o'zgartiradi va [onChanged] ni
  /// chaqiradi — qoralama sehrgar bo'ylab bitta nusxada yuradi.
  final ParamValues values;
  final VoidCallback onChanged;

  /// Ikkala ekran BITTA nusxani bo'lishadi — kesh shu sababli ishlaydi.
  final ParamOptionsRepository optionsRepository;

  @override
  State<ParamForm> createState() => _ParamFormState();
}

class _ParamFormState extends State<ParamForm> {
  /// Matn/raqam maydonlari uchun kontrollerlar — kalit bo'yicha yaratiladi.
  final Map<String, TextEditingController> _controllers = {};

  /// [_syncFromValues] paytida tinglovchi `values` ga qayta yozmasin.
  bool _syncing = false;

  /// Ro'yxat kaliti → variantlar. Chizishdan oldin to'ldiriladi.
  final Map<String, List<ListingOption>> _options = {};
  bool _loadingOptions = true;
  String? _optionsError;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    final keys = {
      for (final f in widget.fields)
        if (f.optionsKey != null) f.optionsKey!,
    };
    if (keys.isEmpty) {
      setState(() => _loadingOptions = false);
      return;
    }
    try {
      for (final k in keys) {
        _options[k] = await widget.optionsRepository.options(k);
      }
      if (mounted) setState(() => _loadingOptions = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingOptions = false;
          _optionsError = e.toString();
        });
      }
    }
  }

  TextEditingController _controllerFor(ParamField f) =>
      _controllers.putIfAbsent(f.key, () {
        final c = TextEditingController(
          text: widget.values[f.key]?.toString() ?? '',
        );
        c.addListener(() {
          if (_syncing) return;
          final text = c.text.trim();
          widget.values[f.key] = text.isEmpty ? null : text;
          widget.onChanged();
        });
        return c;
      });

  /// Kontrollerlarni `values` bo'yicha qayta tenglaydi.
  ///
  /// SHART: 3/7 ekrani va "Barcha parametrlar" ekrani bitta `values` xaritasini
  /// bo'lishadi, lekin har birining O'Z kontrollerlari bor. Kontroller bir
  /// marta yaratilgach `putIfAbsent` uni qayta o'qimaydi — natijada to'liq
  /// ro'yxatda kiritilgan qiymat qadam ekranida eski matn bo'lib qolardi
  /// (ichkarida 99, tashqarida 98).
  void _syncFromValues() {
    _syncing = true;
    for (final entry in _controllers.entries) {
      final v = widget.values[entry.key]?.toString() ?? '';
      if (entry.value.text == v) continue;
      entry.value.value = TextEditingValue(
        text: v,
        selection: TextSelection.collapsed(offset: v.length),
      );
    }
    _syncing = false;
  }

  @override
  void didUpdateWidget(covariant ParamForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Boshqa ekran `values` ni o'zgartirgan bo'lishi mumkin — qaytib
    // kelinganda ota `setState` chaqiradi va biz shu yerda tenglaymiz.
    _syncFromValues();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<ListingOption> _optionsOf(ParamField f) =>
      _options[f.optionsKey ?? ''] ?? const [];

  /// Saqlangan KODga mos yorliq. Ro'yxat hali kelmagan yoki kod eskirgan
  /// bo'lsa kodning o'zi ko'rsatiladi — bo'sh qator qolgandan yaxshi.
  String? _labelOf(ParamField f, Object? code) {
    if (code == null) return null;
    final match = _optionsOf(f).where((o) => o.code == code).firstOrNull;
    return match?.label ?? code.toString();
  }

  List<String> _labelsOf(ParamField f, List<String> codes) {
    final opts = _optionsOf(f);
    return [
      for (final c in codes)
        opts.where((o) => o.code == c).firstOrNull?.label ?? c,
    ];
  }

  Future<void> _pickSingle(ParamField f, String label) async {
    final opts = _optionsOf(f);
    if (opts.isEmpty) return;
    final picked = await showOptionPickerSheet<ListingOption>(
      context,
      title: label,
      options: opts,
      labelOf: (o) => o.label,
      selected: opts
          .where((o) => o.code == widget.values[f.key])
          .firstOrNull,
    );
    if (picked == null || !mounted) return;
    // Bazaga KOD ketadi.
    widget.values[f.key] = picked.code;
    widget.onChanged();
    setState(() {});
  }

  Future<void> _pickMulti(ParamField f, String label) async {
    final l = Localizations.localeOf(context);
    final opts = _optionsOf(f);
    if (opts.isEmpty) return;
    final current = (widget.values[f.key] as List?)?.cast<String>() ?? const [];
    final picked = await showMultiOptionPickerSheet(
      context,
      title: label,
      options: [for (final o in opts) o.label],
      selected: _labelsOf(f, current),
      confirmLabel: tr(l, 'bozor.common.done'),
    );
    if (picked == null || !mounted) return;
    // Yorliqlar qaytadi — kodga o'giramiz, ro'yxat tartibini saqlab.
    final codes = [
      for (final o in opts)
        if (picked.contains(o.label)) o.code,
    ];
    widget.values[f.key] = codes.isEmpty ? null : codes;
    widget.onChanged();
    setState(() {});
  }

  Widget _build(ParamField f, Locale l) {
    final label = tr(l, f.labelKey);
    // Dizayn ixtiyoriylikni "(по желанию)" bilan belgilaydi; loyihamiz esa
    // MAJBURIYni qizil yulduzcha bilan — shuning uchun teskarisi.
    final isRequired = !f.optional;

    switch (f.control) {
      case ParamControl.toggle:
        return WizardSwitchTile(
          label: label,
          value: widget.values[f.key] == true,
          onChanged: (v) {
            widget.values[f.key] = v;
            widget.onChanged();
            // Bu toggle boshqa qatorni ochishi mumkin (pristroyka, uchastka).
            setState(() {});
          },
        );

      case ParamControl.select:
        return SelectField(
          label: label,
          value: _labelOf(f, widget.values[f.key]),
          placeholder: tr(l, 'bozor.common.choose'),
          required: isRequired,
          enabled: _optionsOf(f).isNotEmpty,
          onTap: () => _pickSingle(f, label),
        );

      case ParamControl.multiSelect:
        final codes =
            (widget.values[f.key] as List?)?.cast<String>() ?? const <String>[];
        return MultiSelectField(
          label: label,
          values: _labelsOf(f, codes),
          placeholder: tr(l, 'bozor.common.choose'),
          moreLabel: tr(l, 'bozor.common.and_more'),
          required: isRequired,
          enabled: _optionsOf(f).isNotEmpty,
          onTap: () => _pickMulti(f, label),
        );

      case ParamControl.text:
        return WizardField(
          label: label,
          controller: _controllerFor(f),
          placeholder: tr(l, 'bozor.common.enter'),
          required: isRequired,
        );

      case ParamControl.number:
      case ParamControl.integer:
        return WizardField(
          label: label,
          controller: _controllerFor(f),
          placeholder: '0',
          suffix: f.unit == null ? null : tr(l, 'bozor.unit.${f.unit}'),
          // Birlik bo'sh maydonda ham ko'rinsin — dizaynda shunday.
          alwaysShowSuffix: true,
          numericOnly: true,
          // Maydon o'lchamlari kasrli bo'ladi (72.5 m²), qavat/yil esa butun.
          allowDecimal: f.control == ParamControl.number,
          maxLength: f.control == ParamControl.integer ? 4 : 9,
          required: isRequired,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final shown = visibleParams(widget.fields, widget.values);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_optionsError != null) ...[
          _OptionsErrorRow(
            message: tr(l, 'bozor.options_failed'),
            onRetry: () {
              setState(() {
                _optionsError = null;
                _loadingOptions = true;
              });
              _loadOptions();
            },
          ),
          const SizedBox(height: 12),
        ],
        for (final f in shown) ...[
          _build(f, l),
          const SizedBox(height: 12),
        ],
        // Ro'yxatlar kelmaguncha select'lar o'chiq turadi — buni bildiramiz.
        if (_loadingOptions)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          ),
      ],
    );
  }
}

class _OptionsErrorRow extends StatelessWidget {
  const _OptionsErrorRow({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(
          Icons.error_outline_rounded,
          size: 18,
          color: isDark ? Colors.white70 : const Color(0xFF8A9097),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 13,
              color: isDark ? Colors.white70 : const Color(0xFF8A9097),
            ),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('↻')),
      ],
    );
  }
}
