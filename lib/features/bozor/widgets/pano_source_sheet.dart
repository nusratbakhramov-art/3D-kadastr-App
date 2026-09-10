/// 360° foto manbasini tanlash — suratga olish yoki galereyadan.
///
/// NEGA TANLOV. Ikkala yo'l ham haqiqiy: foydalanuvchi joyida bo'lsa
/// panoramani SHU YERDA olishi mumkin, boshqa ilovada yasab qo'ygan
/// bo'lsa esa uni yuklashi kerak. Tugmani to'g'ridan capture'ga bog'lash
/// ikkinchi holatni yo'q qilardi.
///
/// Capture ekrani kameraga muhtoj, ya'ni u BAND bo'lishi mumkin (AI
/// Baholash skani ochiq bo'lsa). U holda ekran o'zi tushunarli xato
/// ko'rsatadi — bu yerda oldindan tekshirilmaydi, chunki holat
/// varaqni ochish bilan tanlash orasida o'zgarishi mumkin.
library;

import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../panorama/screens/pano_capture_screen.dart';

/// Foydalanuvchi nimani tanladi.
enum PanoSource { capture, gallery }

/// Varaqni ochadi. Bekor qilinsa `null`.
Future<PanoSource?> showPanoSourceSheet(BuildContext context) =>
    showModalBottomSheet<PanoSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PanoSourceSheet(),
    );

/// Capture ekranini ochadi va tikilgan panorama yo'lini qaytaradi.
///
/// Bekor qilinsa yoki tikilmasa `null`.
Future<String?> openPanoCapture(BuildContext context) =>
    Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const PanoCaptureScreen()),
    );

class _PanoSourceSheet extends StatelessWidget {
  const _PanoSourceSheet();

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF15191B) : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.textBlack;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: textColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                tr(l, 'bozor.pano.source.title'),
                style: TextStyle(
                  color: textColor,
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 12),
              _Row(
                icon: Icons.camera_alt_outlined,
                label: tr(l, 'bozor.pano.source.capture'),
                hint: tr(l, 'bozor.pano.source.capture_hint'),
                color: textColor,
                onTap: () => Navigator.of(context).pop(PanoSource.capture),
              ),
              _Row(
                icon: Icons.photo_library_outlined,
                label: tr(l, 'bozor.pano.source.gallery'),
                hint: tr(l, 'bozor.pano.source.gallery_hint'),
                color: textColor,
                onTap: () => Navigator.of(context).pop(PanoSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.hint,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: hapticTap(onTap),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 26, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    style: TextStyle(
                      color: color.withValues(alpha: 0.55),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
