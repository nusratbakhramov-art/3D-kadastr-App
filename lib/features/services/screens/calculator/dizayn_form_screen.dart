import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../theme/app_colors.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../data/calculator_pricing_store.dart';
import '../../models/calculator_draft.dart';
import '../../models/design_order_draft.dart';
import '../../widgets/choice_tile.dart';
import '../../widgets/service_app_bar.dart';
import '../../widgets/style_chip.dart';
import '../online_calculator_result_screen.dart';
import '_calculator_field.dart';
import 'dizayn_tz_wizard_screen.dart';

class DizaynFormScreen extends StatefulWidget {
  const DizaynFormScreen({super.key});

  @override
  State<DizaynFormScreen> createState() => _DizaynFormScreenState();
}

class _DizaynFormScreenState extends State<DizaynFormScreen> {
  DizaynObjectType? _objectType;
  DizaynStyle? _style;
  final TextEditingController _area = TextEditingController();

  @override
  void initState() {
    super.initState();
    _area.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _area.dispose();
    super.dispose();
  }

  bool get _ready {
    final v = parseAmount(_area.text);
    return _objectType != null && _style != null && v != null && v > 0;
  }

  void _calculate() {
    if (!_ready) return;
    HapticFeedback.lightImpact();
    final locale = Localizations.localeOf(context);
    final objectType = _objectType!;
    final style = _style!;
    final area = parseAmount(_area.text)!;
    final result = computeDizayn(
      objectType: objectType,
      style: style,
      areaM2: area,
      pricing: calculatorPricingNotifier.value,
      locale: locale,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => OnlineCalculatorResultScreen(
          result: result,
          placeOrderLabel: _Strings.placeTzOrder(locale),
          onPlaceOrder: () {
            final draft = _draftFromCalculator(objectType, style, area);
            Navigator.of(ctx).push(
              MaterialPageRoute<void>(
                builder: (_) => DizaynTzWizardScreen(initialDraft: draft),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Calculator natijasidan TZ wizard uchun boshlang'ich draft:
  /// obyekt turi, uslub va maydonni oldindan to'ldirib qo'yamiz.
  static DizaynOrderDraft _draftFromCalculator(
    DizaynObjectType objectType,
    DizaynStyle style,
    double area,
  ) {
    final draft = DizaynOrderDraft();
    // Kalkulatorda faqat turar/noturar bor — wizardda aniqroq tur tanlanadi.
    draft.objectType = objectType == DizaynObjectType.turar
        ? DizObjectType.yakka
        : DizObjectType.ofis;
    draft.interior.style = switch (style) {
      DizaynStyle.highTech => 'high_tech',
      DizaynStyle.klassik => 'klassik',
      DizaynStyle.neoklassik => 'neoklassik',
      DizaynStyle.minimalizm => 'minimalizm',
      DizaynStyle.loft => 'loft',
      DizaynStyle.japandi => 'boshqa',
    };
    draft.designAreaSqm = area;
    draft.interiorAreaSqm = area;
    return draft;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final locale = Localizations.localeOf(context);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxContent = constraints.maxWidth.clamp(0.0, 640.0);
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContent),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: ServiceAppBar(
                        title: CalculatorCategory.dizayn.title(locale),
                        subtitle: _Strings.subtitle(locale),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        children: [
                          CalculatorSectionLabel(
                            text: _Strings.chooseObject(locale),
                          ),
                          const SizedBox(height: 12),
                          for (final t in DizaynObjectType.values) ...[
                            ChoiceTile(
                              label: t.label(locale),
                              selected: _objectType == t,
                              onTap: () => setState(() => _objectType = t),
                            ),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 18),
                          CalculatorSectionLabel(
                            text: _Strings.chooseStyle(locale),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final s in DizaynStyle.values)
                                StyleChip(
                                  label: s.label(locale),
                                  selected: _style == s,
                                  onTap: () => setState(() => _style = s),
                                ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          CalculatorField(
                            label: _Strings.areaLabel(locale),
                            placeholder: _Strings.areaPlaceholder(locale),
                            controller: _area,
                            suffix: 'm²',
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: ListingCtaButton(
                        label: _Strings.calculate(locale),
                        enabled: _ready,
                        onTap: _calculate,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Strings {
  const _Strings._();

  static String _pick(Locale l, String uz, String ru, String en) =>
      switch (l.languageCode) { 'ru' => ru, 'en' => en, _ => uz };

  static String subtitle(Locale l) => _pick(
        l,
        'Interyer va eksteryer',
        'Интерьер и экстерьер',
        'Interior & exterior',
      );

  static String chooseObject(Locale l) => _pick(
        l,
        "Ob'ekt turini tanlang",
        'Выберите тип объекта',
        'Choose object type',
      );

  static String chooseStyle(Locale l) => _pick(
        l,
        'Dizayn uslubini tanlang',
        'Выберите стиль дизайна',
        'Choose design style',
      );

  static String areaLabel(Locale l) =>
      _pick(l, 'Dizayn maydoni', 'Площадь дизайна', 'Design area');

  static String areaPlaceholder(Locale l) => _pick(
        l,
        'Maydonni kiriting',
        'Введите площадь',
        'Enter area',
      );

  static String calculate(Locale l) =>
      _pick(l, 'Hisoblash', 'Рассчитать', 'Calculate');

  static String placeTzOrder(Locale l) => _pick(
        l,
        "So'rovnomani to'ldirish",
        'Заполнить анкету',
        'Fill questionnaire',
      );
}
