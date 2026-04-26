import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../models/scan_draft.dart';
import '../widgets/choice_tile.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';
import 'scan_lidar_screen.dart';

class ScanObjectTypeScreen extends StatefulWidget {
  const ScanObjectTypeScreen({super.key, required this.draft});

  final ScanDraft draft;

  @override
  State<ScanObjectTypeScreen> createState() => _ScanObjectTypeScreenState();
}

class _ScanObjectTypeScreenState extends State<ScanObjectTypeScreen> {
  ScanObjectType? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.draft.objectType;
  }

  void _continue() {
    if (_selected == null) return;
    final draft = widget.draft.copyWith(objectType: _selected);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ScanLidarScreen(draft: draft)),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                      child: const ServiceAppBar(
                        title: '3D kadastr',
                        subtitle: 'Obyekt turini tanlang',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: const StepProgressBar(count: 4, activeIndex: 1),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          Text(
                            'Obyekt turi',
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
                            'Skan qilinayotgan obyekt turini tanlang',
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
                              label: t.label,
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
                        label: 'Davom etish',
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
