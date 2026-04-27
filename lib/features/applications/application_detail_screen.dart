import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_header_back.dart';
import '../services/widgets/segmented_tabs.dart';
import 'application_model.dart';

class ApplicationDetailScreen extends StatefulWidget {
  const ApplicationDetailScreen({super.key, required this.item});

  final ApplicationItem item;

  @override
  State<ApplicationDetailScreen> createState() =>
      _ApplicationDetailScreenState();
}

class _ApplicationDetailScreenState extends State<ApplicationDetailScreen> {
  _DetailTab _tab = _DetailTab.status;

  @override
  Widget build(BuildContext context) {
    final steps = widget.item.timeline
        .where((s) => s.completed)
        .toList(growable: false);
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppHeaderBack(
                title: 'Arizalar',
                onBack: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(height: 2),
              Text(
                widget.item.serviceLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  height: 1.3,
                  color: AppColors.textBlack.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 14),
              SegmentedTabs<_DetailTab>(
                values: _DetailTab.values,
                labelOf: (t) => switch (t) {
                  _DetailTab.status => 'Ariza holati',
                  _DetailTab.about => 'Ariza haqida',
                },
                selected: _tab,
                onChanged: (next) => setState(() => _tab = next),
              ),
              const SizedBox(height: 14),
              if (_tab == _DetailTab.status)
                _StatusTab(steps: steps)
              else
                const _AboutTab(),
            ],
          ),
        ),
      ),
    );
  }
}

enum _DetailTab { status, about }

class _StatusTab extends StatelessWidget {
  const _StatusTab({required this.steps});

  final List<ApplicationTimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TimelineCard(steps: steps),
        const SizedBox(height: 14),
        const _PrimaryBlackAction(label: "Mutaxasis bilan bog'lanish"),
      ],
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.steps});

  final List<ApplicationTimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    final visible = steps.isEmpty ? const <ApplicationTimelineStep>[] : steps;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE3E3E3), width: 0.6),
      ),
      child: Column(
        children: [
          for (var i = 0; i < visible.length; i++)
            _TimelineRow(step: visible[i], showTail: i != visible.length - 1),
          if (visible.isEmpty)
            Text(
              'Jarayon maʼlumotlari hali yoʻq',
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: AppColors.textBlack.withValues(alpha: 0.55),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.step, required this.showTail});

  final ApplicationTimelineStep step;
  final bool showTail;

  @override
  Widget build(BuildContext context) {
    final style = _TimelineStyle.fromStatus(step.status);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: style.bg,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(style.icon, color: Colors.white, size: 22),
              ),
              if (showTail)
                Container(width: 1, height: 34, color: const Color(0xFFD0D0D0)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  style.label,
                  style: const TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    height: 1.3,
                    color: AppColors.textBlack,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatAt(step.at),
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    height: 1.3,
                    color: AppColors.textBlack.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TimelineStyle {
  const _TimelineStyle({
    required this.label,
    required this.icon,
    required this.bg,
  });

  final String label;
  final IconData icon;
  final Color bg;

  static _TimelineStyle fromStatus(ApplicationTimelineStatus status) =>
      switch (status) {
        ApplicationTimelineStatus.accepted => const _TimelineStyle(
          label: 'Ariza qabul qilindi',
          icon: Icons.description_outlined,
          bg: Color(0xFF18B4E8),
        ),
        ApplicationTimelineStatus.sentToSystem => const _TimelineStyle(
          label: 'Tizimga yuborildi',
          icon: Icons.send_rounded,
          bg: Color(0xFF6A16F6),
        ),
        ApplicationTimelineStatus.assignedSpecialist => const _TimelineStyle(
          label: 'Mutaxassisga tayinlandi',
          icon: Icons.badge_outlined,
          bg: Color(0xFFFF9800),
        ),
        ApplicationTimelineStatus.scanned => const _TimelineStyle(
          label: 'Skan qilindi',
          icon: Icons.crop_free_rounded,
          bg: Color(0xFF03C050),
        ),
        ApplicationTimelineStatus.reportReady => const _TimelineStyle(
          label: 'Hisobot tayyorlandi',
          icon: Icons.description_outlined,
          bg: Color(0xFF1A9BF4),
        ),
      };
}

class _AboutTab extends StatelessWidget {
  const _AboutTab();

  @override
  Widget build(BuildContext context) {
    const rows = <(String, String)>[
      ('Obyekt', "Ko'p qavatli xonadon, 3 xona"),
      ('Manzil', 'Toshkent sh., Chilonzor t., 7-mavze'),
      ('Maydon', '120.5 m²'),
      ('Qavat', '5/9'),
      ('Kadastr qiymati', '385 mln'),
      ('Kadastr raqami', '10:06:0310101:012:0001'),
      ('Skan sanasi', '02.04.2026'),
      ('Hisobot sanasi', '02.04.2026'),
      ('Skan aniqligi', '±2 sm'),
      ('Mutaxassis', 'Abdullayev J.'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Hisobot',
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: AppColors.textBlack,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE3E3E3), width: 0.6),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                _InfoRow(label: rows[i].$1, value: rows[i].$2),
                if (i != rows.length - 1)
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFE8E8E8),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        const _FileCard(),
        const SizedBox(height: 14),
        const _ModelCard(),
        const SizedBox(height: 18),
        const _PrimaryGreenAction(label: "AR orqali ko'rish"),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$label:',
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w400,
                fontSize: 14,
                height: 1.3,
                color: AppColors.textBlack.withValues(alpha: 0.5),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  height: 1.3,
                  color: AppColors.textBlack,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE3E3E3), width: 0.6),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F2),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: SvgPicture.asset(
              'assets/icons/application-ready.svg',
              width: 20,
              height: 20,
              colorFilter: ColorFilter.mode(
                AppColors.textBlack.withValues(alpha: 0.5),
                BlendMode.srcIn,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '3D_Kadastr_Xulosa.pdf',
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    height: 1.3,
                    color: AppColors.textBlack,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '3.1 MB',
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    height: 1.3,
                    color: Color(0xFF8A8A8A),
                  ),
                ),
              ],
            ),
          ),
          _MiniPillButton(
            label: 'Yuklash',
            fg: const Color(0xFF03B54F),
            bg: const Color(0xFFD7F3E3),
            iconAsset: 'assets/icons/download.svg',
          ),
        ],
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE3E3E3), width: 0.6),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F2),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: SvgPicture.asset(
              'assets/icons/chart-scatter-3d.svg',
              width: 20,
              height: 20,
              colorFilter: ColorFilter.mode(
                AppColors.textBlack.withValues(alpha: 0.5),
                BlendMode.srcIn,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '3D Model',
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    height: 1.3,
                    color: AppColors.textBlack,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'RoomPlan viewer ochiladi',
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    height: 1.3,
                    color: Color(0xFF8A8A8A),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _MiniPillButton(
            label: "Ko'rish",
            fg: AppColors.textBlack,
            bg: const Color(0xFFF2F2F2),
            iconAsset: 'assets/icons/chevron-right.svg',
          ),
        ],
      ),
    );
  }
}

class _MiniPillButton extends StatelessWidget {
  const _MiniPillButton({
    required this.label,
    required this.fg,
    required this.bg,
    required this.iconAsset,
  });

  final String label;
  final Color fg;
  final Color bg;
  final String iconAsset;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.fromLTRB(8, 3, 6, 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10000),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: fg,
            ),
          ),
          const SizedBox(width: 6),
          SvgPicture.asset(
            iconAsset,
            width: 18,
            height: 18,
            colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
          ),
        ],
      ),
    );
  }
}

class _PrimaryBlackAction extends StatelessWidget {
  const _PrimaryBlackAction({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {},
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.call_outlined, size: 24, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryGreenAction extends StatelessWidget {
  const _PrimaryGreenAction({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF00E135),
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {},
        child: SizedBox(
          height: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 10),
              SvgPicture.asset(
                'assets/icons/camera.svg',
                width: 30,
                height: 30,
                colorFilter: const ColorFilter.mode(
                  Colors.black,
                  BlendMode.srcIn,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatAt(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final hh = d.hour.toString().padLeft(2, '0');
  final mi = d.minute.toString().padLeft(2, '0');
  return '$dd.$mm.${d.year},$hh:$mi';
}
