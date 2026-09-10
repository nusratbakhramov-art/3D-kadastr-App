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
  });

  final String label;
  final String iconAsset;

  /// Tanlangan fayllarning LOKAL yo'llari.
  final List<String> paths;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

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
                onRemove: () => onRemove(i),
                onOpen: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        FilePreviewGallery(paths: paths, initialIndex: i),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.path,
    required this.onRemove,
    required this.onOpen,
  });

  final String path;
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
                  child: Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    // PDF/hujjat tanlansa rasm ochilmaydi — qulflanib
                    // qolmasin, o'rniga fayl ikonkasi chiqadi.
                    errorBuilder: (_, _, _) => Icon(
                      Icons.insert_drive_file_rounded,
                      color: isDark ? Colors.white38 : Colors.black26,
                    ),
                  ),
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
