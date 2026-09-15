import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../models/market_listing.dart';

class ListingFormatsCard extends StatelessWidget {
  const ListingFormatsCard({
    super.key,
    required this.files,
    required this.onTap,
    this.onOpenLocation,
    this.downloadingFileId,
    this.downloadProgress,
    this.downloadedFileIds = const {},
    this.locked = false,
  });

  /// Files available for this listing (only these formats are shown).
  final List<MarketListingFile> files;

  /// Ilovaga allaqachon yuklab olingan fayllar — qator "ochish" ko'rinishiga
  /// o'tadi va bosilganda qayta yuklamaydi.
  final Set<int> downloadedFileIds;

  /// Called when a row is tapped — receives the file. When [locked] the
  /// parent routes this into the purchase flow instead of downloading.
  final ValueChanged<MarketListingFile> onTap;

  /// Yuklab olingan qatordagi jild tugmasi bosilganda — faylning saqlangan
  /// joyini ochadi (Android: Yuklamalar ekrani; iOS: Files ilovasi).
  final ValueChanged<MarketListingFile>? onOpenLocation;

  /// If non-null, that file's row shows progress.
  final int? downloadingFileId;

  /// Yuklab olish ulushi (0..1). `null` bo'lsa — noaniq (aylanma) indikator.
  final double? downloadProgress;

  /// Paid model the user hasn't bought yet — rows show a lock cue (formats are
  /// previewed so the buyer sees what they get, but tapping prompts purchase).
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF121617) : Colors.white;
    final fg = isDark ? Colors.white : AppColors.textBlack;
    final border = isDark ? null : Border.all(color: const Color(0xFFE3E5E8));
    final divider = isDark ? const Color(0xFF202628) : const Color(0xFFF0F1F3);

    if (files.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: border,
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(locale, 'market.formats.title'),
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              height: 1.3,
              color: fg,
            ),
          ),
          const SizedBox(height: 6),
          for (final f in files)
            _FileRow(
              format: formatLabel(f.format),
              name: _formatName(locale, f.format),
              size: sizeLabel(f.fileSize),
              sizeBytes: f.fileSize,
              loading: downloadingFileId == f.id,
              progress: downloadingFileId == f.id ? downloadProgress : null,
              downloaded: downloadedFileIds.contains(f.id),
              locked: locked,
              fg: fg,
              divider: divider,
              onOpenLocation: onOpenLocation == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      onOpenLocation!(f);
                    },
              onTap: () {
                // Yuklanayotgan qatorning o'zi bosilsa — bekor qilish; boshqa
                // qatorlar shu vaqtda bloklanadi.
                if (downloadingFileId != null && downloadingFileId != f.id) {
                  return;
                }
                HapticFeedback.selectionClick();
                onTap(f);
              },
            ),
        ],
      ),
    );
  }

  static String formatLabel(String raw) {
    final u = raw.toUpperCase();
    return u == 'GLTF' ? 'glTF' : u;
  }

  /// Format uchun odam o'qiydigan nom ("MAX" → "3ds Max sahna").
  ///
  /// Bitta e'londa uchta MAX fayl bo'lishi mumkin va ular faqat hajmi bilan
  /// farq qilardi — nima yuklab olayotganini tushunib bo'lmasdi. Backend faqat
  /// kengaytma va hajmni beradi, shuning uchun nom shu yerda xaritalanadi;
  /// tarjima bo'lmasa qator faqat hajm bilan qoladi.
  static String _formatName(Locale locale, String raw) {
    final key = 'market.format.${raw.toLowerCase()}';
    final value = tr(locale, key);
    return value == key ? '' : value;
  }

  /// Bayt hajmini o'qiladigan matnga aylantiradi (qator va yuklab olish
  /// oynasi bir xil formatdan foydalanadi).
  static String sizeLabel(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    if (bytes < 1024 * 1024 * 1024) {
      final mb = bytes / (1024 * 1024);
      return '${mb < 10 ? mb.toStringAsFixed(1) : mb.round()} MB';
    }
    final gb = bytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(1)} GB';
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.format,
    required this.name,
    required this.size,
    required this.sizeBytes,
    required this.loading,
    required this.progress,
    required this.downloaded,
    required this.locked,
    required this.fg,
    required this.divider,
    required this.onTap,
    this.onOpenLocation,
  });

  final String format;
  final String name;
  final String size;
  final int sizeBytes;
  final bool loading;
  final double? progress;
  final bool downloaded;
  final bool locked;
  final Color fg;
  final Color divider;
  final VoidCallback onTap;
  final VoidCallback? onOpenLocation;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = const Color(0xFF8A9097);
    // splashGreen (#00E135) oq fonda matn sifatida qattiq ko'rinadi —
    // yorug' mavzuda to'q brandGreen ishlatiladi.
    final okGreen = isDark ? AppColors.splashGreen : AppColors.brandGreen;
    // Progress halqasining orqa yo'li — busiz 20% shunchaki yolg'iz yoy bo'lib
    // ko'rinadi va qancha qolganini bilib bo'lmaydi.
    final track = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final tileBg = downloaded
        ? AppColors.splashGreen.withValues(alpha: 0.14)
        : (isDark ? const Color(0xFF1C2224) : const Color(0xFFF1F2F4));
    final tileFg = downloaded
        ? okGreen
        : (isDark ? const Color(0xFFB6BCC2) : const Color(0xFF5B6066));

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: divider, width: 0.6)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tileBg,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                format,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: format.length > 4 ? 9 : 10.5,
                  letterSpacing: 0.2,
                  color: tileFg,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name.isEmpty ? format : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      height: 1.25,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _subtitle(locale),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                      height: 1.3,
                      color: downloaded ? okGreen : muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _trailing(tileFg, okGreen, track),
          ],
        ),
      ),
    );
  }

  /// Hajm, yoki yuklab olinayotgan bo'lsa jarayon, yoki "yuklandi".
  String _subtitle(Locale locale) {
    if (loading) {
      final p = progress;
      if (p == null) return tr(locale, 'market.download.in_progress');
      final done = ListingFormatsCard.sizeLabel((sizeBytes * p).round());
      return '${(p * 100).round()}% · $done / $size';
    }
    if (downloaded) return '$size · ${tr(locale, 'market.download.done')}';
    return size;
  }

  Widget _trailing(Color iconColor, Color okGreen, Color track) {
    if (loading) {
      return SizedBox(
        width: 26,
        height: 26,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                value: progress,
                backgroundColor: track,
                valueColor: AlwaysStoppedAnimation(okGreen),
              ),
            ),
            // Halqa ichidagi kichik × — yuklab olishni to'xtatish mumkinligini
            // ko'rsatadi (avval uzilgan yuklashni bekor qilishning iloji
            // yo'q edi).
            SvgPicture.asset(
              'assets/icons/close.svg',
              width: 11,
              height: 11,
              colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
            ),
          ],
        ),
      );
    }
    if (locked) {
      return Icon(
        Icons.lock_outline_rounded,
        size: 19,
        color: iconColor.withValues(alpha: 0.8),
      );
    }
    if (!downloaded) {
      return SvgPicture.asset(
        'assets/icons/file-download.svg',
        width: 21,
        height: 21,
        colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
      );
    }
    // Yuklab olingan: yashil belgidan tashqari, faylning saqlangan joyini
    // ochadigan jild tugmasi. Jild tugmasi o'z tap'ini yutadi — qatorning
    // asosiy tap'i (amallar oynasi) ishlamaydi.
    final check = SvgPicture.asset(
      'assets/icons/file-check.svg',
      width: 21,
      height: 21,
      colorFilter: ColorFilter.mode(okGreen, BlendMode.srcIn),
    );
    if (onOpenLocation == null) return check;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onOpenLocation,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: SvgPicture.asset(
                'assets/icons/folder-open.svg',
                width: 21,
                height: 21,
                colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
              ),
            ),
          ),
        ),
        const SizedBox(width: 2),
        check,
      ],
    );
  }
}
