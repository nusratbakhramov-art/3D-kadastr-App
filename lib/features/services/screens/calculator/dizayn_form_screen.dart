import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../theme/app_colors.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../models/calculator_draft.dart';
import '../../widgets/choice_tile.dart';
import '../../widgets/service_app_bar.dart';
import '../../widgets/style_chip.dart';
import '../online_calculator_result_screen.dart';
import '_calculator_field.dart';

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
    final result = computeDizayn(
      objectType: _objectType!,
      style: _style!,
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
                        title: 'Dizayn loyihasi',
                        subtitle: 'Interyer va eksteryer',
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
                          for (final t in DizaynObjectType.values) ...[
                            ChoiceTile(
                              label: t.label,
                              selected: _objectType == t,
                              onTap: () => setState(() => _objectType = t),
                            ),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 18),
                          const CalculatorSectionLabel(
                            text: 'Dizayn uslubini tanlang',
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final s in DizaynStyle.values)
                                StyleChip(
                                  label: s.label,
                                  selected: _style == s,
                                  onTap: () => setState(() => _style = s),
                                ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          CalculatorField(
                            label: 'Dizayn maydoni',
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
