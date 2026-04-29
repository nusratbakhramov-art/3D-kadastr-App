import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../theme/app_colors.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../models/calculator_draft.dart';
import '../../widgets/choice_tile.dart';
import '../../widgets/service_app_bar.dart';
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
    final result = computeBaholash(
      objectType: _selected!,
      areaM2: parseAmount(_area.text)!,
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
                      child: const ServiceAppBar(
                        title: 'Mulk qiymatini baholash',
                        subtitle: 'Bozor qiymatini aniqlash',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        children: [
                          const CalculatorSectionLabel(
                            text: "Ob'ekt turini tanlang",
                          ),
                          const SizedBox(height: 12),
                          for (final t in BaholashObject.values) ...[
                            ChoiceTile(
                              label: t.label,
                              selected: _selected == t,
                              onTap: () => setState(() => _selected = t),
                            ),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 14),
                          CalculatorField(
                            label: "Ko'chmas mulk maydoni",
                            placeholder: 'Maydonni kiriting',
                            controller: _area,
                            suffix: 'm²',
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: ListingCtaButton(
                        label: 'Hisoblash',
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
