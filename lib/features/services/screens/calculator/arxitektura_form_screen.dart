import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../theme/app_colors.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../models/architecture_order_draft.dart';
import '../../data/calculator_pricing_store.dart';
import '../../models/calculator_draft.dart';
import '../../widgets/choice_tile.dart';
import '../../widgets/service_app_bar.dart';
import '../online_calculator_result_screen.dart';
import '_calculator_field.dart';
import 'arxitektura_tz_wizard_screen.dart';

class ArxitekturaFormScreen extends StatefulWidget {
  const ArxitekturaFormScreen({super.key});

  @override
  State<ArxitekturaFormScreen> createState() => _ArxitekturaFormScreenState();
}

class _ArxitekturaFormScreenState extends State<ArxitekturaFormScreen> {
  ArxitekturaObject? _selected;
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
    return _selected != null && v != null && v > 0;
  }

  void _calculate() {
    if (!_ready) return;
    HapticFeedback.lightImpact();
    final locale = Localizations.localeOf(context);
    final selected = _selected!;
    final area = parseAmount(_area.text)!;
    final result = computeArxitektura(
      objectType: selected,
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
            final draft = _draftFromCalculator(selected, area);
            // Kalkulyatorda hisoblangan narxni saqlaymiz — adminka "Итого".
            draft.estimatedPriceUzs = result.totalUzs;
            Navigator.of(ctx).push(
              MaterialPageRoute<void>(
                builder: (_) => ArxitekturaTzWizardScreen(initialDraft: draft),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Calculator natijasidan TZ wizard uchun boshlang'ich draft tuzish:
  /// obyekt turi va umumiy maydonni oldindan to'ldirib qo'yamiz.
  static ArchitectureOrderDraft _draftFromCalculator(
    ArxitekturaObject calc,
    double area,
  ) {
    final draft = ArchitectureOrderDraft();
    draft.totalAreaSqm = area;
    switch (calc) {
      case ArxitekturaObject.yakkaSmall:
        draft.objectType = ArchObjectType.yakkaSmall;
        draft.constructionType = ConstructionType.yangi;
      case ArxitekturaObject.yakkaLarge:
        draft.objectType = ArchObjectType.yakkaLarge;
        draft.constructionType = ConstructionType.yangi;
      case ArxitekturaObject.kopQavatli:
        draft.objectType = ArchObjectType.kopQavatli;
        draft.constructionType = ConstructionType.yangi;
      case ArxitekturaObject.jamoat:
        // Jamoat ostida bir nechta tur bor — default `ofis`. Foydalanuvchi
        // wizardda o'zgartira oladi.
        draft.objectType = ArchObjectType.ofis;
        draft.constructionType = ConstructionType.yangi;
      case ArxitekturaObject.sanoat:
        draft.objectType = ArchObjectType.sanoat;
        draft.constructionType = ConstructionType.yangi;
      case ArxitekturaObject.rekonstruksiya:
        // Rekonstruksiya — qurilish turi alohida o'lcham; obyekt turi
        // sifatida default `yakkaSmall` qoldiramiz, foydalanuvchi tanlaydi.
        draft.objectType = ArchObjectType.yakkaSmall;
        draft.constructionType = ConstructionType.rekonstruksiya;
    }
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
                        title: _Strings.title(locale),
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
                          for (final t in ArxitekturaObject.values) ...[
                            _ObjectTile(
                              label: t.label(locale),
                              hint: t.hint(locale),
                              selected: _selected == t,
                              onTap: () => setState(() => _selected = t),
                            ),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 14),
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

  static String title(Locale l) => _pick(
        l,
        'Arxitektura va qurilish',
        'Архитектура и строительство',
        'Architecture & construction',
      );

  static String subtitle(Locale l) => _pick(
        l,
        'Loyiha narxini hisoblang',
        'Рассчитайте стоимость проекта',
        'Calculate project cost',
      );

  static String chooseObject(Locale l) => _pick(
        l,
        "Ob'ekt turini tanlang",
        'Выберите тип объекта',
        'Choose object type',
      );

  static String areaLabel(Locale l) => _pick(
        l,
        'Qurilish hajmi',
        'Объём строительства',
        'Construction volume',
      );

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
        'Ariza topshirish',
        'Подать заявку',
        'Submit application',
      );
}

class _ObjectTile extends StatelessWidget {
  const _ObjectTile({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (hint == null) {
      return ChoiceTile(label: label, selected: selected, onTap: onTap);
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1F2426) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF2C3133)
        : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : const Color(0xFF8A9097);
    final idleRadio = isDark
        ? const Color(0xFF3A4042)
        : const Color(0xFFD1D5D9);

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.splashGreen : borderColor,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        height: 1.25,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hint!,
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 12.5,
                        height: 1.3,
                        color: hintColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _RadioDot(selected: selected, idleColor: idleRadio),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected, required this.idleColor});
  final bool selected;
  final Color idleColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.splashGreen : Colors.transparent,
        border: Border.all(
          color: selected ? AppColors.splashGreen : idleColor,
          width: 2,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            )
          : null,
    );
  }
}
