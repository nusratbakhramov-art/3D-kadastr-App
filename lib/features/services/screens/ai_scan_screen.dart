import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../data/room_plan_scanner.dart';
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
  RoomScanResult? _scanResult;

  Future<void> _startScan() async {
    if (_state == ScanCardState.scanning) return;
    HapticFeedback.lightImpact();

    final supported = await RoomPlanScanner.isSupported();
    if (!supported) {
      if (!mounted) return;
      AppToast.error(
        context,
        'Bu qurilmada RoomPlan yo\'q. iPhone Pro yoki iPad Pro kerak '
        '(iOS 16+ va LiDAR sensori).',
      );
      return;
    }

    setState(() => _state = ScanCardState.scanning);
    try {
      final result = await RoomPlanScanner.startTexturedScan();
      if (!mounted) return;
      if (result == null) {
        setState(() => _state = ScanCardState.idle);
        return;
      }
      setState(() {
        _scanResult = result;
        _state = ScanCardState.done;
      });
    } on RoomPlanScannerException catch (e) {
      if (!mounted) return;
      setState(() => _state = ScanCardState.idle);
      AppToast.error(context, e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = ScanCardState.idle);
      AppToast.error(context, 'Skan xatosi: $e');
    }
  }

  void _continue() {
    if (_state != ScanCardState.done) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AiMetadataScreen(
          draft: AiValuationDraft(
            scanCompleted: true,
            areaM2: _scanResult?.floorAreaSqm,
          ),
        ),
      ),
    );
  }

  Future<void> _preview() async {
    final path = _scanResult?.filePath;
    if (path == null) return;
    HapticFeedback.lightImpact();
    try {
      await RoomPlanScanner.preview(path);
    } on RoomPlanScannerException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Ko\'rsatish xatosi: $e');
    }
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
                          if (_state == ScanCardState.done &&
                              _scanResult != null) ...[
                            const SizedBox(height: 12),
                            _PreviewButton(onTap: _preview),
                          ],
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

class _PreviewButton extends StatelessWidget {
  const _PreviewButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = AppColors.splashGreen.withValues(alpha: 0.6);
    final textColor = isDark ? Colors.white : AppColors.textBlack;

    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: 1.4),
          ),
          child: Row(
            children: [
              Icon(Icons.view_in_ar_rounded,
                  color: AppColors.splashGreen, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '3D modelni ko\'rish',
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: textColor,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: textColor.withValues(alpha: 0.4), size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
