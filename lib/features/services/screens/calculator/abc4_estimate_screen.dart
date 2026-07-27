import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/app_translations.dart';
import '../../../../theme/app_colors.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../data/abc4_estimate_client.dart';
import '../../models/calculator_draft.dart';
import '../../widgets/choice_tile.dart';
import '../../widgets/service_app_bar.dart';
import '../online_calculator_result_screen.dart';
import '_calculator_field.dart';

/// Kalkulyator — "Ta'mirlash va qurilish" → real ABC-UZ smeta estimate.
///
/// Collects a building profile (work kind, type, wall material, finish level,
/// floors, area), sends it to `POST /abc4/estimate`, and shows the itemized
/// cost. The backend prices it with the ABC software when reachable, otherwise
/// returns a deterministic per-m² approximation — either way we get a number.
class Abc4EstimateScreen extends StatefulWidget {
  const Abc4EstimateScreen({
    super.key,
    this.service,
    this.initialArea,
    this.cadastreNumber,
    this.address,
  });

  final Abc4EstimateService? service;

  /// Optional prefill when arriving from a cadastre lookup.
  final double? initialArea;
  final String? cadastreNumber;
  final String? address;

  @override
  State<Abc4EstimateScreen> createState() => _Abc4EstimateScreenState();
}

class _Abc4EstimateScreenState extends State<Abc4EstimateScreen> {
  late final Abc4EstimateService _service =
      widget.service ?? Abc4EstimateService();

  WorkKind _workKind = WorkKind.construction;
  BuildingType? _buildingType;
  WallMaterial _wallMaterial = WallMaterial.brick;
  FinishLevel _finishLevel = FinishLevel.standard;
  int _floors = 1;
  final TextEditingController _area = TextEditingController();

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialArea != null && widget.initialArea! > 0) {
      _area.text = widget.initialArea!
          .toStringAsFixed(widget.initialArea! % 1 == 0 ? 0 : 1);
    }
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
    return _buildingType != null && v != null && v > 0 && !_submitting;
  }

  Future<void> _calculate() async {
    if (!_ready) return;
    HapticFeedback.lightImpact();
    final locale = Localizations.localeOf(context);
    final profile = ConstructionProfile(
      workKind: _workKind,
      buildingType: _buildingType!,
      wallMaterial: _wallMaterial,
      finishLevel: _finishLevel,
      floors: _floors,
      areaSqm: parseAmount(_area.text)!,
      cadastreNumber: widget.cadastreNumber,
      address: widget.address,
    );

    setState(() => _submitting = true);
    try {
      final result = await _service.estimate(profile);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OnlineCalculatorResultScreen(
            result: _toCalculatorResult(result, locale),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(locale, 'services.calc.abc4.error'))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  CalculatorResult _toCalculatorResult(
    ConstructionEstimateResult r,
    Locale locale,
  ) {
    final lines = <CalculatorLine>[
      CalculatorLine(tr(locale, 'services.calc.abc4.object_line'), r.profileSummary),
      CalculatorLine(
        tr(locale, 'services.calc.abc4.method_line'),
        r.isAbc
            ? tr(locale, 'services.calc.abc4.method_abc')
            : tr(locale, 'services.calc.abc4.method_approx'),
      ),
      for (final l in r.lines)
        CalculatorLine(l.section, fmtUzsPublic(locale, l.costUzs)),
    ];
    return CalculatorResult(
      categoryTitle: tr(locale, 'services.calc.repair_construction'),
      totalUzs: r.totalUzs,
      note: r.isAbc
          ? tr(locale, 'services.calc.abc4.method_abc')
          : tr(locale, 'services.calc.abc4.note_approx'),
      lines: lines,
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
                        title: tr(locale, 'services.calc.repair_construction'),
                        subtitle: tr(locale, 'services.calc.abc4.subtitle'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        children: [
                          CalculatorSectionLabel(text: tr(locale, 'services.calc.abc4.work_kind')),
                          const SizedBox(height: 12),
                          for (final w in WorkKind.values) ...[
                            ChoiceTile(
                              label: w.label(locale),
                              selected: _workKind == w,
                              onTap: () => setState(() => _workKind = w),
                            ),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 18),
                          CalculatorSectionLabel(
                            text: tr(locale, 'services.calc.abc4.building_type'),
                          ),
                          const SizedBox(height: 12),
                          for (final t in BuildingType.values) ...[
                            ChoiceTile(
                              label: t.label(locale),
                              selected: _buildingType == t,
                              onTap: () => setState(() => _buildingType = t),
                            ),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 18),
                          CalculatorSectionLabel(
                            text: tr(locale, 'services.calc.abc4.wall_material'),
                          ),
                          const SizedBox(height: 12),
                          for (final m in WallMaterial.values) ...[
                            ChoiceTile(
                              label: m.label(locale),
                              selected: _wallMaterial == m,
                              onTap: () => setState(() => _wallMaterial = m),
                            ),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 18),
                          CalculatorSectionLabel(
                            text: tr(locale, 'services.calc.abc4.finish_level'),
                          ),
                          const SizedBox(height: 12),
                          for (final f in FinishLevel.values) ...[
                            ChoiceTile(
                              label: f.label(locale),
                              selected: _finishLevel == f,
                              onTap: () => setState(() => _finishLevel = f),
                            ),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 18),
                          CalculatorSectionLabel(text: tr(locale, 'services.calc.abc4.floors')),
                          const SizedBox(height: 12),
                          _FloorStepper(
                            value: _floors,
                            onChanged: (v) => setState(() => _floors = v),
                          ),
                          const SizedBox(height: 18),
                          CalculatorField(
                            label: tr(locale, 'services.calc.abc4.area_label'),
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
                        label: _submitting
                            ? tr(locale, 'services.calc.abc4.calculating')
                            : tr(locale, 'services.calc.calculate'),
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

class _FloorStepper extends StatelessWidget {
  const _FloorStepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _btn(Icons.remove_rounded, value > 1, () => onChanged(value - 1)),
          Text(
            '$value',
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: textColor,
            ),
          ),
          _btn(Icons.add_rounded, value < 50, () => onChanged(value + 1)),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, bool enabled, VoidCallback onTap) {
    return Material(
      color: enabled
          ? AppColors.splashGreen.withValues(alpha: 0.15)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onTap();
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            icon,
            size: 22,
            color: enabled ? AppColors.splashGreen : const Color(0xFFB4B9BF),
          ),
        ),
      ),
    );
  }
}
