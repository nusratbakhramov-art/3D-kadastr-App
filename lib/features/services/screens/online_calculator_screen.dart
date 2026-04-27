import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../models/calculator_draft.dart';
import '../widgets/segmented_tabs.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/style_chip.dart';
import 'online_calculator_result_screen.dart';

class OnlineCalculatorScreen extends StatefulWidget {
  const OnlineCalculatorScreen({super.key});

  @override
  State<OnlineCalculatorScreen> createState() => _OnlineCalculatorScreenState();
}

class _OnlineCalculatorScreenState extends State<OnlineCalculatorScreen> {
  CalculatorTab _tab = CalculatorTab.arxitektura;
  CalculatorStyle _style = CalculatorStyle.minimalizm;

  final TextEditingController _land = TextEditingController();
  final TextEditingController _building = TextEditingController();
  final TextEditingController _floors = TextEditingController();
  final TextEditingController _residents = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final c in [_land, _building, _floors, _residents]) {
      c.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_land, _building, _floors, _residents]) {
      c
        ..removeListener(_refresh)
        ..dispose();
    }
    super.dispose();
  }

  bool get _ready {
    final land = double.tryParse(_land.text.replaceAll(',', '.'));
    final building = double.tryParse(_building.text.replaceAll(',', '.'));
    final floors = int.tryParse(_floors.text);
    final residents = int.tryParse(_residents.text);
    return land != null &&
        land > 0 &&
        building != null &&
        building > 0 &&
        floors != null &&
        floors > 0 &&
        residents != null &&
        residents > 0;
  }

  void _calculate() {
    if (!_ready) return;
    HapticFeedback.lightImpact();
    final draft = CalculatorDraft(
      tab: _tab,
      landSotix: double.parse(_land.text.replaceAll(',', '.')),
      buildingM2: double.parse(_building.text.replaceAll(',', '.')),
      floors: int.parse(_floors.text),
      residents: int.parse(_residents.text),
      style: _style,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OnlineCalculatorResultScreen(draft: draft),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final labelColor = isDark ? Colors.white : AppColors.textBlack;

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
                      child: const ServiceAppBar(title: 'Onlayn kalkulyator'),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SegmentedTabs<CalculatorTab>(
                        values: CalculatorTab.values,
                        labelOf: (t) => t.label,
                        selected: _tab,
                        onChanged: (t) => setState(() => _tab = t),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          _Field(
                            label: 'Yer maydoni (sotix)',
                            placeholder: 'Yer maydonini kiriting',
                            controller: _land,
                            keyboard: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            allow: RegExp(r'[0-9.,]'),
                            labelColor: labelColor,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 14),
                          _Field(
                            label: 'Bino (m²)',
                            placeholder: 'Bino kvadratini kiriting',
                            controller: _building,
                            keyboard: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            allow: RegExp(r'[0-9.,]'),
                            labelColor: labelColor,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 14),
                          _Field(
                            label: 'Qavatlar soni',
                            placeholder: 'Qavatlar sonini kiriting',
                            controller: _floors,
                            keyboard: TextInputType.number,
                            allow: RegExp(r'[0-9]'),
                            labelColor: labelColor,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 14),
                          _Field(
                            label: 'Yashovchilar soni',
                            placeholder: 'Yashovchilar sonini kiriting',
                            controller: _residents,
                            keyboard: TextInputType.number,
                            allow: RegExp(r'[0-9]'),
                            labelColor: labelColor,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 22),
                          Text(
                            'Uslubni tanlang',
                            style: TextStyle(
                              fontFamily: 'MTSCompact',
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              height: 1.25,
                              color: labelColor,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final s in CalculatorStyle.values)
                                StyleChip(
                                  label: s.label,
                                  selected: _style == s,
                                  onTap: () => setState(() => _style = s),
                                ),
                            ],
                          ),
                          const SizedBox(height: 24),
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

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.placeholder,
    required this.controller,
    required this.keyboard,
    required this.allow,
    required this.labelColor,
    required this.isDark,
  });

  final String label;
  final String placeholder;
  final TextEditingController controller;
  final TextInputType keyboard;
  final RegExp allow;
  final Color labelColor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : const Color(0xFFB4B9BF);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 16,
            height: 1.25,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          onTapOutside: (_) => FocusScope.of(context).unfocus(),
          keyboardType: keyboard,
          inputFormatters: [FilteringTextInputFormatter.allow(allow)],
          style: TextStyle(
            fontFamily: 'MTSText',
            fontSize: 15,
            color: textColor,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
            hintText: placeholder,
            hintStyle: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 15,
              color: hintColor,
            ),
            filled: true,
            fillColor: fill,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.splashGreen, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}
