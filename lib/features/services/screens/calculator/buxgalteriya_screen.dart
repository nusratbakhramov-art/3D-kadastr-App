/// Qurilish buxgalteriyasi — obyekt qiymati bo'yicha progressiv kalkulyator.
///
/// Boshqa xizmatlar 1 m² narxidan hisoblanadi; buxgalteriya haqi esa obyekt
/// QIYMATIDAN pog'onali olinadi (`computeBuxgalteriya`, shkala adminkadan:
/// `buxgalteriya.value_scale`). Natija ekrani har pog'onani alohida satr qilib
/// ko'rsatadi, shuning uchun mijoz summaning qayerdan chiqqanini ko'radi.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/app_translations.dart';
import '../../../../theme/app_colors.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../data/calculator_pricing_store.dart';
import '../../models/calculator_draft.dart';
import '../../widgets/service_app_bar.dart';
import '../online_calculator_result_screen.dart';
import '_calculator_field.dart';

class BuxgalteriyaScreen extends StatefulWidget {
  const BuxgalteriyaScreen({super.key});

  @override
  State<BuxgalteriyaScreen> createState() => _BuxgalteriyaScreenState();
}

class _BuxgalteriyaScreenState extends State<BuxgalteriyaScreen> {
  final TextEditingController _value = TextEditingController();

  @override
  void initState() {
    super.initState();
    _value.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  bool get _ready {
    final v = parseAmount(_value.text);
    return v != null && v > 0;
  }

  void _calculate() {
    if (!_ready) return;
    HapticFeedback.lightImpact();
    final locale = Localizations.localeOf(context);
    final result = computeBuxgalteriya(
      objectValueUzs: parseAmount(_value.text)!,
      pricing: calculatorPricingNotifier.value,
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
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
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
                        title: CalculatorCategory.buxgalteriya.title(locale),
                        subtitle:
                            tr(locale, 'services.calc.buxgalteriya.subtitle'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        children: [
                          Text(
                            tr(locale, 'services.calc.buxgalteriya.heading'),
                            style: TextStyle(
                              fontFamily: 'MTSCompact',
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              height: 1.3,
                              color: titleColor,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            tr(locale, 'services.calc.buxgalteriya.scale_note'),
                            style: TextStyle(
                              fontFamily: 'MTSText',
                              fontSize: 13,
                              height: 1.4,
                              color: subColor,
                            ),
                          ),
                          const SizedBox(height: 18),
                          CalculatorField(
                            label: tr(
                              locale,
                              'services.calc.buxgalteriya.value_label',
                            ),
                            placeholder: tr(
                              locale,
                              'services.calc.buxgalteriya.value_hint',
                            ),
                            controller: _value,
                            suffix: "so'm",
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: ListingCtaButton(
                        label:
                            tr(locale, 'services.calc.buxgalteriya.calculate'),
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
