import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../models/ai_valuation_draft.dart';
import '../widgets/scan_camera_card.dart';
import '../widgets/scan_tips_card.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';
import 'ai_metadata_screen.dart';

class AiScanScreen extends StatefulWidget {
  const AiScanScreen({super.key});

  @override
  State<AiScanScreen> createState() => _AiScanScreenState();
}

class _AiScanScreenState extends State<AiScanScreen> {
  ScanCardState _state = ScanCardState.idle;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startScan() {
    if (_state == ScanCardState.scanning) return;
    HapticFeedback.lightImpact();
    setState(() => _state = ScanCardState.scanning);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _state = ScanCardState.done);
    });
  }

  void _continue() {
    if (_state != ScanCardState.done) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AiMetadataScreen(
          draft: AiValuationDraft(scanCompleted: true),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final headingColor = isDark ? Colors.white : AppColors.textBlack;
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
                        title: 'AI Baholash',
                        subtitle: 'Ko\'chmas mulk qiymatini aniqlash',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: const StepProgressBar(count: 4, activeIndex: 0),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          Text(
                            'Obyektni skan qiling',
                            style: TextStyle(
                              fontFamily: 'MTSCompact',
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              height: 1.25,
                              color: headingColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'RoomPlan LiDAR orqali skan qiling',
                            style: TextStyle(
                              fontFamily: 'MTSText',
                              fontSize: 13,
                              height: 1.3,
                              color: subColor,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ScanCameraCard(state: _state, onTap: _startScan),
                          const SizedBox(height: 16),
                          const ScanTipsCard(),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: ListingCtaButton(
                        label: _state == ScanCardState.done
                            ? 'Davom etish'
                            : 'Scan boshlash',
                        enabled: _state != ScanCardState.scanning,
                        onTap: _state == ScanCardState.done
                            ? _continue
                            : _startScan,
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
