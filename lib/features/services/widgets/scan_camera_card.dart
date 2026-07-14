import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../theme/app_colors.dart';

enum ScanCardState { idle, scanning, done }

class ScanCameraCard extends StatelessWidget {
  const ScanCameraCard({
    super.key,
    required this.state,
    required this.onTap,
    this.onLongPress,
    required this.idleLabel,
    required this.scanningLabel,
    required this.doneLabel,
  });

  final ScanCardState state;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String idleLabel;
  final String scanningLabel;
  final String doneLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final labelColor = isDark ? Colors.white : AppColors.textBlack;
    const badgeBg = Color(0xFFE0EEFF);
    const badgeFg = Color(0xFF2B7FFF);

    final label = switch (state) {
      ScanCardState.idle => idleLabel,
      ScanCardState.scanning => scanningLabel,
      ScanCardState.done => doneLabel,
    };
    final icon = switch (state) {
      ScanCardState.idle => Icons.photo_camera_rounded,
      ScanCardState.scanning => Icons.sync_rounded,
      ScanCardState.done => Icons.check_rounded,
    };

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hapticTap(state == ScanCardState.scanning ? null : onTap),
        onLongPress: state == ScanCardState.scanning ? null : onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
          alignment: Alignment.center,
          child: Column(
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: badgeBg,
                ),
                alignment: Alignment.center,
                child: state == ScanCardState.scanning
                    ? const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: badgeFg,
                        ),
                      )
                    : Icon(icon, size: 36, color: badgeFg),
              ),
              const SizedBox(height: 18),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  height: 1.3,
                  color: labelColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
