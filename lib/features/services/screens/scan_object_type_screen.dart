import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../../settings/settings_state.dart';
import '../models/kadastr_3d_bundle.dart';
import '../models/scan_draft.dart';
import '../widgets/choice_tile.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';
import 'kadastr_3d/k3d_intake_screen.dart';

String _scanObjectTypeLabel(ScanObjectType t, Locale locale) =>
    switch (locale.languageCode) {
      'ru' => switch (t) {
          ScanObjectType.turarJoy => 'Жилое',
          ScanObjectType.noturarJoy => 'Нежилое',
          ScanObjectType.ombor => 'Склад',
          ScanObjectType.sanoat => 'Промышленные объекты',
        },
      'en' => switch (t) {
          ScanObjectType.turarJoy => 'Residential',
          ScanObjectType.noturarJoy => 'Non-residential',
          ScanObjectType.ombor => 'Warehouse',
          ScanObjectType.sanoat => 'Industrial objects',
        },
      _ => t.label,
    };

class ScanObjectTypeScreen extends StatefulWidget {
  const ScanObjectTypeScreen({super.key, required this.bundle});

  final Kadastr3dBundle bundle;

  @override
  State<ScanObjectTypeScreen> createState() => _ScanObjectTypeScreenState();
}

class _ScanObjectTypeScreenState extends State<ScanObjectTypeScreen> {
  ScanObjectType? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.bundle.objectType;
  }

  void _continue() {
    if (_selected == null) return;
    widget.bundle.objectType = _selected;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => K3dIntakeScreen(bundle: widget.bundle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, locale, _) => _build(context, locale),
    );
  }

  Widget _build(BuildContext context, Locale locale) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final labelColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

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
                        title: _ScanObjectTypeStrings.appBarTitle(locale),
                        subtitle:
                            _ScanObjectTypeStrings.appBarSubtitle(locale),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: const StepProgressBar(count: 6, activeIndex: 3),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          Text(
                            _ScanObjectTypeStrings.heading(locale),
                            style: TextStyle(
                              fontFamily: 'MTSCompact',
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              height: 1.25,
                              color: labelColor,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _ScanObjectTypeStrings.subheading(locale),
                            style: TextStyle(
                              fontFamily: 'MTSText',
                              fontSize: 13,
                              height: 1.3,
                              color: subColor,
                            ),
                          ),
                          const SizedBox(height: 14),
                          for (final t in ScanObjectType.values) ...[
                            ChoiceTile(
                              label: _scanObjectTypeLabel(t, locale),
                              selected: _selected == t,
                              onTap: () => setState(() => _selected = t),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: ListingCtaButton(
                        label: _ScanObjectTypeStrings.ctaContinue(locale),
                        enabled: _selected != null,
                        onTap: _continue,
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

class _ScanObjectTypeStrings {
  static String appBarTitle(Locale locale) => switch (locale.languageCode) {
        'ru' => '3D Кадастр',
        'en' => '3D Cadastre',
        _ => '3D kadastr',
      };

  static String appBarSubtitle(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Выберите тип объекта',
        'en' => 'Select object type',
        _ => 'Obyekt turini tanlang',
      };

  static String heading(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Тип объекта',
        'en' => 'Object type',
        _ => 'Obyekt turi',
      };

  static String subheading(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Выберите тип сканируемого объекта',
        'en' => 'Select the type of object being scanned',
        _ => 'Skan qilinayotgan obyekt turini tanlang',
      };

  static String ctaContinue(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Продолжить',
        'en' => 'Continue',
        _ => 'Davom etish',
      };
}
