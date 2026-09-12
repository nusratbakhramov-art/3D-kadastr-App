/// Fayl qo'shish qatori + tanlangan fayllar tasmasi.
///
/// Dizaynda qator 48pt: chapda 28pt ikonka, yonida yorliq, o'ngda HECH NARSA
/// yo'q — butun qator bitta teginish nishoni. Uchta qator (planirovka, foto,
/// 360) bir xil, faqat ikonka va yorliq almashadi.
///
/// TO'LDIRILGAN HOLAT DIZAYNDA YO'Q. Tanlangan fayl ko'rinmasa foydalanuvchi
/// nima yuklaganini bilmaydi va bir narsani ikki marta tanlaydi — shuning
/// uchun qator ostiga kichik tasma qo'shildi (72pt eskizlar + o'chirish).
/// Bu qo'shimcha, dizaynga zid emas.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/haptics.dart';
import '../../../theme/app_colors.dart';
import '../../services/widgets/file_preview_gallery.dart';

class MediaUploadRow extends StatelessWidget {
  const MediaUploadRow({
    super.key,
    required this.label,
    required this.iconAsset,
    required this.paths,
    required this.onAdd,
    required this.onRemove,
    this.onOpen,
    this.urlOf,
    this.statusOf,
  });

  final String label;
  final String iconAsset;

  /// Tanlangan yozuvlar. Odatda LOKAL YO'L, 360° qatorida esa S3 KALITI
  /// ([urlOf] ga qarang).
  final List<String> paths;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  /// Yozuvning holati — 360° panorama uchun.
  ///
  /// Panorama serverda ~7–9 daqiqa tikiladi va foydalanuvchi buni kutmaydi:
  /// qatorda o'sha vaqt davomida KUTILAYOTGAN yozuv turadi. Berilmasa
  /// hamma yozuv tayyor deb qaraladi (foto va planirovka shunday).
  final MediaItemStatus Function(String path)? statusOf;

  /// Yozuv uchun TARMOQ manzili; `null` bo'lsa yozuv lokal fayl deb o'qiladi.
  ///
  /// 360° panorama endi SERVERDA tikiladi va sehrgarga tayyor holda kaliti
  /// bilan qaytadi — lokal nusxasi YO'Q (kadrlar darhol o'chiriladi).
  /// Busiz eskiz `Image.file` ga tushib «hujjat» ikonkasiga aylanardi va
  /// foydalanuvchi panoramasi yuklanmagan deb o'ylardi.
  final String? Function(String path)? urlOf;

  /// Eskiz bosilganda nima ochilishi.
  ///
  /// Berilmasa — oddiy rasm galereyasi. 360° qatori buni ALMASHTIRADI:
  /// tikilgan panorama tekis JPEG bo'lib ko'rinadi, lekin uni tekis
  /// ko'rsatish tasvirni cho'zilgan lentaga aylantiradi va 360° ekanini
  /// umuman bildirmaydi — u sferada ochilishi kerak.
  final ValueChanged<int>? onOpen;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Dizaynda yuklash kartasining foni matn maydonlarinikidan ATAYLAB
    // farq qiladi (#FCFDFF vs #F5F8FC) — o'sha nozik farqni saqlaymiz.
    final fill = isDark ? const Color(0xFF20262A) : const Color(0xFFFCFDFF);
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final fg = isDark ? const Color(0xFFB0B5BB) : const Color(0xFF6E7480);
    final radius = BorderRadius.circular(14);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: fill,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: hapticTap(onAdd),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  SvgPicture.asset(
                    iconAsset,
                    width: 26,
                    height: 26,
                    colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                        color: fg,
                      ),
                    ),
                  ),
                  if (paths.isNotEmpty)
                    Text(
                      '${paths.length}',
                      style: const TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.splashGreen,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (paths.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: paths.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _Thumb(
                path: paths[i],
                url: urlOf?.call(paths[i]),
                status: statusOf?.call(paths[i]) ?? MediaItemStatus.ready,
                onRemove: () => onRemove(i),
                onOpen: () {
                  final ValueChanged<int>? open = onOpen;
                  if (open != null) {
                    open(i);
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          FilePreviewGallery(paths: paths, initialIndex: i),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Tasmadagi bitta yozuvning holati.
enum MediaItemStatus {
  /// Ko'rsatishga tayyor.
  ready,

  /// Serverda tayyorlanmoqda (360° tikish).
  pending,

  /// Tayyorlash yiqildi — bosilsa qayta urinish taklif qilinadi.
  failed,
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.path,
    required this.onRemove,
    required this.onOpen,
    required this.status,
    this.url,
  });

  final MediaItemStatus status;

  final String path;

  /// Bo'sh bo'lmasa — eskiz shu manzildan yuklanadi, [path] esa faqat
  /// kalit sifatida qoladi.
  final String? url;
  final VoidCallback onRemove;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final radius = BorderRadius.circular(12);

    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: hapticTap(onOpen),
              child: ClipRRect(
                borderRadius: radius,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: border),
                  ),
                  child: switch (status) {
                    MediaItemStatus.pending => _Placeholder(
                      isDark: isDark,
                      color: AppColors.splashGreen,
                      child: const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.splashGreen,
                        ),
                      ),
                    ),
                    MediaItemStatus.failed => _Placeholder(
                      isDark: isDark,
                      color: const Color(0xFFE0492A),
                      child: const Icon(
                        Icons.refresh_rounded,
                        color: Color(0xFFE0492A),
                        size: 24,
                      ),
                    ),
                    MediaItemStatus.ready =>
                      (url != null && url!.isNotEmpty)
                          ? Image.network(
                              url!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => _fallbackIcon(isDark),
                              loadingBuilder: (_, child, progress) =>
                                  progress == null
                                  ? child
                                  : const Center(
                                      child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                            )
                          : Image.file(
                              File(path),
                              fit: BoxFit.cover,
                              // PDF/hujjat tanlansa rasm ochilmaydi — qulflanib
                              // qolmasin, o'rniga fayl ikonkasi chiqadi.
                              errorBuilder: (_, _, _) => _fallbackIcon(isDark),
                            ),
                  },
                ),
              ),
            ),
          ),
          Positioned(
            right: 2,
            top: 2,
            child: GestureDetector(
              onTap: hapticSelect(onRemove),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _fallbackIcon(bool isDark) => Icon(
  Icons.insert_drive_file_rounded,
  color: isDark ? Colors.white38 : Colors.black26,
);

/// Eskiz o'rnidagi belgi — hali rasm yo'q (tayyorlanmoqda yoki yiqilgan).
class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.isDark,
    required this.color,
    required this.child,
  });

  final bool isDark;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: isDark ? 0.16 : 0.10),
    ),
    child: Center(child: child),
  );
}
