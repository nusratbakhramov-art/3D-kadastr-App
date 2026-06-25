/// Kadastr combined calculator — step 1: property area.
///
/// Entry point of the "Kadastr" flow (the renamed home/services tile). Collects
/// the real-estate area, then moves on to the multi-select services step.
library;

import 'package:flutter/material.dart';

import '../../../../theme/app_colors.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../widgets/service_app_bar.dart';
import '../calculator/_calculator_field.dart';
import 'kadastr_services_screen.dart';

class KadastrAreaScreen extends StatefulWidget {
  const KadastrAreaScreen({super.key});

  @override
  State<KadastrAreaScreen> createState() => _KadastrAreaScreenState();
}

class _KadastrAreaScreenState extends State<KadastrAreaScreen> {
  final _areaCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _areaCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _areaCtrl.dispose();
    super.dispose();
  }

  double? get _area {
    final v = parseAmount(_areaCtrl.text);
    return (v != null && v > 0) ? v : null;
  }

  void _next() {
    final area = _area;
    if (area == null) return;
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => KadastrServicesScreen(areaM2: area),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: ServiceAppBar(title: _S.appBar(l)),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                    children: [
                      Text(
                        _S.subheading(l),
                        style: TextStyle(
                          fontFamily: 'MTSText',
                          fontSize: 13.5,
                          height: 1.4,
                          color: subColor,
                        ),
                      ),
                      const SizedBox(height: 20),
                      CalculatorField(
                        label: _S.areaLabel(l),
                        placeholder: _S.areaHint(l),
                        controller: _areaCtrl,
                        suffix: 'm²',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ListingCtaButton(
                    label: _S.next(l),
                    enabled: _area != null,
                    onTap: _next,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _S {
  const _S._();

  static String _pick(Locale l, String uz, String ru, String en) =>
      switch (l.languageCode) { 'ru' => ru, 'en' => en, _ => uz };

  static String appBar(Locale l) => _pick(
        l,
        'Onlayn kalkulyator',
        'Онлайн калькулятор',
        'Online calculator',
      );

  static String subheading(Locale l) => _pick(
        l,
        "Ko'chmas mulk maydonini kiriting — keyin kerakli xizmatlarni tanlaysiz.",
        'Введите площадь недвижимости — затем выберите нужные услуги.',
        'Enter the property area — then choose the services you need.',
      );

  static String areaLabel(Locale l) => _pick(
        l,
        "Ko'chmas mulk maydoni",
        'Площадь недвижимости',
        'Property area',
      );

  static String areaHint(Locale l) =>
      _pick(l, 'Maydonni kiriting', 'Введите площадь', 'Enter the area');

  static String next(Locale l) =>
      _pick(l, 'Davom etish', 'Продолжить', 'Continue');
}
