/// Kadastr combined calculator — step 1: property area.
///
/// Entry point of the "Kadastr" flow (the renamed home/services tile). Collects
/// the real-estate area, then moves on to the multi-select services step.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/app_translations.dart';
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
                  child: ServiceAppBar(
                      // Yangi kalit — eskisi prod bundle'ida "3D kadastr"ga
                      // o'zgartirilgan, bu oqim esa kalkulyator oqimi.
                      title: tr(l, 'services.kadastr.flow.appbar.calc')),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                    children: [
                      Text(
                        tr(l, 'services.kadastr.area.subheading'),
                        style: TextStyle(
                          fontFamily: 'MTSText',
                          fontSize: 13.5,
                          height: 1.4,
                          color: subColor,
                        ),
                      ),
                      const SizedBox(height: 20),
                      CalculatorField(
                        label: tr(l, 'services.kadastr.area.label'),
                        placeholder: tr(l, 'services.kadastr.area.hint'),
                        controller: _areaCtrl,
                        suffix: 'm²',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ListingCtaButton(
                    label: tr(l, 'services.kadastr.continue'),
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

