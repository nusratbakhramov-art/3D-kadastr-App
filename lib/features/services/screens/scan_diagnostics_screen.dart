import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../data/scan_capability_probe.dart';
import '../models/scan_capability.dart';
import '../widgets/service_app_bar.dart';

class ScanDiagnosticsScreen extends StatefulWidget {
  const ScanDiagnosticsScreen({super.key});

  @override
  State<ScanDiagnosticsScreen> createState() => _ScanDiagnosticsScreenState();
}

class _ScanDiagnosticsScreenState extends State<ScanDiagnosticsScreen> {
  Future<ScanCapability>? _future;

  @override
  void initState() {
    super.initState();
    _future = ScanCapabilityProbe.probe();
  }

  void _reprobe() {
    setState(() => _future = ScanCapabilityProbe.probe());
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
                        title: 'Scan diagnostika',
                        subtitle: 'LiDAR / depth sensor probe',
                      ),
                    ),
                    Expanded(
                      child: FutureBuilder<ScanCapability>(
                        future: _future,
                        builder: (context, snap) {
                          if (snap.connectionState != ConnectionState.done) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (snap.hasError) {
                            return _ErrorBody(
                              error: snap.error.toString(),
                              onRetry: _reprobe,
                              isDark: isDark,
                            );
                          }
                          return _ResultBody(
                            capability: snap.requireData,
                            onReprobe: _reprobe,
                            isDark: isDark,
                          );
                        },
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

class _ResultBody extends StatelessWidget {
  const _ResultBody({
    required this.capability,
    required this.onReprobe,
    required this.isDark,
  });

  final ScanCapability capability;
  final VoidCallback onReprobe;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final tier = capability.tier;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        _TierBanner(tier: tier, isDark: isDark),
        const SizedBox(height: 16),
        _SectionLabel('Probe', isDark: isDark),
        const SizedBox(height: 8),
        _InfoCard(
          isDark: isDark,
          rows: [
            ('platform', capability.platform),
            ('deviceModel', capability.deviceModel),
            ('osVersion', capability.osVersion),
          ],
        ),
        const SizedBox(height: 16),
        _SectionLabel('Capabilities', isDark: isDark),
        const SizedBox(height: 8),
        _InfoCard(
          isDark: isDark,
          rows: [
            ('hasLidar', _yn(capability.hasLidar)),
            ('hasRoomPlan', _yn(capability.hasRoomPlan)),
            ('arWorldTracking', _yn(capability.arWorldTrackingSupported)),
            ('hasArCore', _yn(capability.hasArCore)),
            ('hasDepthApi', _yn(capability.hasDepthApi)),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.splashGreen,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: onReprobe,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text(
            'Re-probe',
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  String _yn(bool v) => v ? 'true' : 'false';
}

class _TierBanner extends StatelessWidget {
  const _TierBanner({required this.tier, required this.isDark});

  final ScanTier tier;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final (label, color, hint) = switch (tier) {
      ScanTier.roomPlan => (
        'RoomPlan + LiDAR',
        const Color(0xFF00E135),
        'Bu qurilmada to\'liq RoomPlan skani mavjud.',
      ),
      ScanTier.lidar => (
        'LiDAR',
        const Color(0xFF00E135),
        'LiDAR mesh rekonstruksiyasi mavjud, RoomPlan yo\'q (iOS < 16).',
      ),
      ScanTier.depthApi => (
        'ARCore Depth API',
        const Color(0xFF22D3EE),
        'Hardware LiDAR yo\'q, lekin depth sensing mavjud.',
      ),
      ScanTier.photogrammetry => (
        'Fotogrammetriya',
        const Color(0xFFF59E0B),
        'Real-time depth yo\'q. Foto-asosli skanga fallback bo\'ladi.',
      ),
      ScanTier.unsupported => (
        'Qo\'llab-quvvatlanmaydi',
        const Color(0xFFEF4444),
        '3D skan ishlamaydi.',
      ),
    };

    final bg = isDark
        ? color.withValues(alpha: 0.18)
        : color.withValues(alpha: 0.12);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Tanlangan tier',
                style: TextStyle(
                  fontFamily: 'MTSText',
                  fontSize: 12,
                  color: isDark ? Colors.white70 : const Color(0xFF8A9097),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w900,
              fontSize: 22,
              color: isDark ? Colors.white : AppColors.textBlack,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 13,
              height: 1.3,
              color: isDark ? Colors.white70 : const Color(0xFF8A9097),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.isDark});

  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'MTSCompact',
        fontWeight: FontWeight.w700,
        fontSize: 14,
        color: isDark ? Colors.white : AppColors.textBlack,
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.isDark, required this.rows});

  final bool isDark;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final divider = isDark ? const Color(0xFF2C3133) : const Color(0xFFEEF0F2);
    final keyColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final valColor = isDark ? Colors.white : AppColors.textBlack;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      rows[i].$1,
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 13,
                        height: 1.25,
                        color: keyColor,
                      ),
                    ),
                  ),
                  Text(
                    rows[i].$2,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      height: 1.25,
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

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({
    required this.error,
    required this.onRetry,
    required this.isDark,
  });

  final String error;
  final VoidCallback onRetry;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? Colors.white : AppColors.textBlack;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: fg),
          const SizedBox(height: 12),
          Text(
            'Probe xatoligi',
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: fg,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 13,
              color: fg.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
