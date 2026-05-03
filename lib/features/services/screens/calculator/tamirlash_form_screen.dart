import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../theme/app_colors.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../models/calculator_draft.dart';
import '../../widgets/choice_tile.dart';
import '../../widgets/service_app_bar.dart';
import '../online_calculator_result_screen.dart';
import '_calculator_field.dart';

class TamirlashFormScreen extends StatefulWidget {
  const TamirlashFormScreen({super.key});

  @override
  State<TamirlashFormScreen> createState() => _TamirlashFormScreenState();
}

class _TamirlashFormScreenState extends State<TamirlashFormScreen> {
  TamirlashServiceType? _serviceType;
  TamirlashObjectType? _objectType;
  TamirlashLocation? _location;
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
    return _serviceType != null &&
        _objectType != null &&
        _location != null &&
        v != null &&
        v > 0;
  }

  void _calculate() {
    if (!_ready) return;
    HapticFeedback.lightImpact();
    final locale = Localizations.localeOf(context);
    final result = computeTamirlash(
      objectType: _objectType!,
      location: _location!,
      serviceType: _serviceType!,
      areaM2: parseAmount(_area.text)!,
      locale: locale,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OnlineCalculatorResultScreen(result: result),
      ),
    );
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
                            text: _Strings.chooseService(locale),
                          ),
                          const SizedBox(height: 12),
                          for (final s in TamirlashServiceType.values) ...[
                            ChoiceTile(
                              label: s.label(locale),
                              selected: _serviceType == s,
                              onTap: () => setState(() => _serviceType = s),
                            ),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 18),
                          CalculatorSectionLabel(
                            text: _Strings.chooseObject(locale),
                          ),
                          const SizedBox(height: 12),
                          for (final t in TamirlashObjectType.values) ...[
                            ChoiceTile(
                              label: t.label(locale),
                              selected: _objectType == t,
                              onTap: () => setState(() => _objectType = t),
                            ),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 18),
                          CalculatorSectionLabel(
                            text: _Strings.chooseLocation(locale),
                          ),
                          const SizedBox(height: 12),
                          for (final l in TamirlashLocation.values) ...[
                            ChoiceTile(
                              label: l.label(locale),
                              selected: _location == l,
                              onTap: () => setState(() => _location = l),
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
        "Ta'mirlash va qurilish",
        'Ремонт и строительство',
        'Repair & construction',
      );

  static String subtitle(Locale l) => _pick(
        l,
        "Ta'mir yoki qurilish narxi",
        'Цена ремонта или строительства',
        'Repair or construction price',
      );

  static String chooseService(Locale l) => _pick(
        l,
        'Xizmat turini tanlang',
        'Выберите тип услуги',
        'Choose service type',
      );

  static String chooseObject(Locale l) => _pick(
        l,
        "Ob'ekt turini tanlang",
        'Выберите тип объекта',
        'Choose object type',
      );

  static String chooseLocation(Locale l) => _pick(
        l,
        'Manzilni tanlang',
        'Выберите местоположение',
        'Choose location',
      );

  static String areaLabel(Locale l) =>
      _pick(l, 'Maydon', 'Площадь', 'Area');

  static String areaPlaceholder(Locale l) => _pick(
        l,
        'Maydonni kiriting',
        'Введите площадь',
        'Enter area',
      );

  static String calculate(Locale l) =>
      _pick(l, 'Hisoblash', 'Рассчитать', 'Calculate');
}
