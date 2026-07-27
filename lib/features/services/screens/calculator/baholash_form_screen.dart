import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/app_translations.dart';
import '../../../../theme/app_colors.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../data/calculator_pricing_store.dart';
import '../../models/calculator_draft.dart';
import '../../widgets/choice_tile.dart';
import '../../widgets/service_app_bar.dart';
import '../kadastr_3d_screen.dart';
import '../online_calculator_result_screen.dart';
import '_calculator_field.dart';

class BaholashFormScreen extends StatefulWidget {
  const BaholashFormScreen({super.key});

  @override
  State<BaholashFormScreen> createState() => _BaholashFormScreenState();
}

class _BaholashFormScreenState extends State<BaholashFormScreen> {
  BaholashObject? _selected;
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
    final result = computeBaholash(
      objectType: _selected!,
      areaM2: parseAmount(_area.text)!,
      pricing: calculatorPricingNotifier.value,
      locale: locale,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => OnlineCalculatorResultScreen(
          result: result,
          placeOrderLabel: tr(locale, 'services.calc.submit_order'),
          // "Ariza topshirish" → eski 3D kadastr oqimiga o'tamiz
          // (davreestr lookup → mijoz → lokatsiya → skan).
          onPlaceOrder: () => Navigator.of(ctx).push(
            MaterialPageRoute<void>(
              builder: (_) => const Kadastr3dScreen(),
            ),
          ),
        ),
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
                        title: CalculatorCategory.baholash.title(locale),
                        subtitle: CalculatorCategory.baholash.subtitle(locale),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        children: [
                          CalculatorSectionLabel(
                            text: tr(locale, 'services.calc.choose_object'),
                          ),
                          const SizedBox(height: 12),
                          for (final t in BaholashObject.values) ...[
                            ChoiceTile(
                              label: t.label(locale),
                              selected: _selected == t,
                              onTap: () => setState(() => _selected = t),
                            ),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 14),
                          CalculatorField(
                            label: tr(locale, 'services.calc.area_property'),
                            placeholder: tr(locale, 'services.calc.enter_area'),
                            controller: _area,
                            suffix: 'm²',
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: ListingCtaButton(
                        label: tr(locale, 'services.calc.calculate'),
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
