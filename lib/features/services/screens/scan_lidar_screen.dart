import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../data/room_plan_scanner.dart';
import '../models/scan_draft.dart';
import '../widgets/scan_camera_card.dart';
import '../widgets/scan_tips_card.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';
import 'scan_diagnostics_screen.dart';
import 'scan_metadata_screen.dart';

class ScanLidarScreen extends StatefulWidget {
  const ScanLidarScreen({super.key, required this.draft});

  final ScanDraft draft;

  @override
  State<ScanLidarScreen> createState() => _ScanLidarScreenState();
}

class _ScanLidarScreenState extends State<ScanLidarScreen> {
  ScanCardState _state = ScanCardState.idle;
  RoomScanResult? _scanResult;

  Future<void> _startScan() async {
    if (_state == ScanCardState.scanning) return;
    HapticFeedback.lightImpact();

    // Avval qurilma RoomPlan'ni qo'llaydimi tekshirish.
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
      final result = await RoomPlanScanner.startScan();
      if (!mounted) return;
      if (result == null) {
        // Foydalanuvchi bekor qildi.
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
    final draft = widget.draft.copyWith(scanCompleted: true);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ScanMetadataScreen(draft: draft)),
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
                        title: '3D kadastr',
                        subtitle: 'RoomPlan LiDAR orqali skan qiling',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: const StepProgressBar(count: 4, activeIndex: 2),
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
                          ScanCameraCard(
                            state: _state,
                            onTap: _startScan,
                            onLongPress: () {
                              HapticFeedback.mediumImpact();
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const ScanDiagnosticsScreen(),
                                ),
                              );
                            },
                          ),
                          if (_state == ScanCardState.done && _scanResult != null) ...[
                            const SizedBox(height: 12),
                            _ScanResultCard(result: _scanResult!),
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

class _ScanResultCard extends StatelessWidget {
  const _ScanResultCard({required this.result});
  final RoomScanResult result;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final divider = isDark ? const Color(0xFF2C3133) : const Color(0xFFEEF0F2);
    final keyColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final valColor = isDark ? Colors.white : AppColors.textBlack;

    String fmtSize(int bytes) {
      if (bytes >= 1024 * 1024) {
        return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
      }
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    final rows = <(String, String)>[
      ('Devorlar', '${result.walls}'),
      ('Eshiklar', '${result.doors}'),
      ('Oynalar', '${result.windows}'),
      if (result.openings > 0) ('Boshqa ochiqliklar', '${result.openings}'),
      if (result.objects > 0) ('Mebel/obyektlar', '${result.objects}'),
      if (result.floorAreaSqm != null)
        ('Maydon (taxminiy)', '${result.floorAreaSqm!.toStringAsFixed(1)} m²'),
      ('Fayl hajmi', fmtSize(result.fileSize)),
    ];

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.splashGreen.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      rows[i].$1,
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 13,
                        color: keyColor,
                      ),
                    ),
                  ),
                  Text(
                    rows[i].$2,
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: valColor,
                    ),
                  ),
                ],
              ),
            ),
            if (i != rows.length - 1) Container(height: 1, color: divider),
          ],
        ],
      ),
    );
  }
}
