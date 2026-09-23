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

/// Eskiz tomoni. 72 → 96 (2026-09-23): muqova nishoni 72pt da 9pt shriftga
/// siqilib, o'qilmasdi va mijoz «Asosiy qilish» ni topa olmasdi.
const double _thumbSize = 96;

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
    this.fileOf,
    this.statusOf,
    this.coverLabel,
    this.coverHint,
    this.makeCoverLabel,
    this.coverIndex,
    this.onSetCover,
  });

  /// Muqova sahnasidagi nishon matni («Asosiy rasm»). `null` — muqova
  /// tushunchasi bu qatorda umuman yo'q (planirovka, 360°), ya'ni sahna ham
  /// chizilmaydi va eskizlar oddiy ko'rish tugmasi bo'lib qoladi.
  final String? coverLabel;

  /// Sahna ostidagi bir qatorlik izoh («E'lon ro'yxatida shu rasm chiqadi»).
  final String? coverHint;

  /// Qolgan eskizlardagi tugma matni («Asosiy qilish»).
  final String? makeCoverLabel;

  /// Hozirgi muqovaning o'rni. `null` — belgilanmagan.
  final int? coverIndex;

  /// Muqovani almashtirish. `null` bo'lsa nishon FAQAT ko'rsatiladi,
  /// bosilmaydi.
  final ValueChanged<int>? onSetCover;

  final String label;
  final String iconAsset;

  /// Tanlangan yozuvlar. Odatda LOKAL YO'L, 360° qatorida esa S3 KALITI
  /// ([urlOf] ga qarang).
  final List<String> paths;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  /// Yozuvning holati — 360° panorama uchun.
  ///
  /// Local captures awaiting processing/upload and legacy server-job drafts
  /// expose their pending/error state here. Without a status callback all
  /// entries are treated as ready (as with ordinary photos and floor plans).
  final MediaItemStatus Function(String path)? statusOf;

  /// Yozuv uchun TARMOQ manzili; `null` bo'lsa yozuv lokal fayl deb o'qiladi.
  ///
  /// 360° panorama endi SERVERDA tikiladi va sehrgarga tayyor holda kaliti
  /// bilan qaytadi — lokal nusxasi YO'Q (kadrlar darhol o'chiriladi).
  /// Busiz eskiz `Image.file` ga tushib «hujjat» ikonkasiga aylanardi va
  /// foydalanuvchi panoramasi yuklanmagan deb o'ylardi.
  final String? Function(String path)? urlOf;

  /// Havola uchun QURILMADAGI eskiz fayli (masalan tikilgan `preview.jpg`).
  /// `local` holatda ishlatiladi; `null` — eskiz hali yo'q.
  final String? Function(String path)? fileOf;

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
          // MUQOVA SAHNASI — faqat muqova tushunchasi bor qatorda (foto).
          //
          // Tanlangan rasm KATTA ko'rsatiladi, e'lon kartasidagi kabi 4:3
          // qirqim bilan. Sabab: sotuvchi «qaysi rasm asosiy» degan mavhum
          // savolga emas, «xaridor nimani ko'radi» degan savolga javob
          // izlaydi — buni yozuv bilan tushuntirgandan ko'ra KO'RSATGAN
          // yaxshi. Shu sababli eskizlarda endi hech qanday yozuv yo'q.
          if (coverLabel != null) ...[
            const SizedBox(height: 10),
            _CoverStage(
              path: paths[_coverAt],
              label: coverLabel!,
              hint: coverHint,
              url: urlOf?.call(paths[_coverAt]),
              onOpen: () => _openGallery(context, _coverAt),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            height: _thumbSize,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: paths.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _Thumb(
                path: paths[i],
                // Sahna bor joyda eskiz — TANLASH tugmasi: bosilsa muqova
                // bo'ladi va yuqorida darhol ko'rinadi. Kattalashtirib
                // ko'rish sahnaning o'zidan (u yerda hamma rasmni surib
                // chiqish mumkin), shuning uchun eskiz ikki vazifani
                // birdan bajarmaydi.
                selectable: coverLabel != null,
                isCover: coverLabel != null && i == _coverAt,
                onSetCover: (onSetCover == null || coverLabel == null)
                    ? null
                    : () => onSetCover!(i),
                url: urlOf?.call(paths[i]),
                file: fileOf?.call(paths[i]),
                status: statusOf?.call(paths[i]) ?? MediaItemStatus.ready,
                onRemove: () => onRemove(i),
                onOpen: () => _openGallery(context, i),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Muqovaning o'rni — belgilanmagan bo'lsa birinchisi.
  int get _coverAt {
    final i = coverIndex ?? 0;
    return (i >= 0 && i < paths.length) ? i : 0;
  }

  void _openGallery(BuildContext context, int index) {
    final ValueChanged<int>? open = onOpen;
    if (open != null) {
      open(index);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FilePreviewGallery(
          paths: paths,
          initialIndex: index,
          // KATTA rasmda ham muqova ko'rinadi va shu yerdan almashtiriladi.
          // Sahna faqat muqovani ko'rsatadi, qolgan rasmlarni esa aynan shu
          // yerda surib chiqish mumkin — ya'ni hech bir rasm «yo'qolmaydi».
          coverIndex: _coverAt,
          coverLabel: coverLabel,
          makeCoverLabel: paths.length > 1 ? makeCoverLabel : null,
          onSetCover: paths.length < 2 ? null : onSetCover,
        ),
      ),
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

  /// Telefonda saqlangan, hali yuklanmagan (360° kadrlar/tikilgan fayl) —
  /// bosilsa davom etadi. [MediaUploadRow.fileOf] eskiz bersa u chiziladi,
  /// bermasa «davom etish» belgisi.
  local,
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.path,
    required this.onRemove,
    required this.onOpen,
    required this.status,
    this.url,
    this.file,
    this.selectable = false,
    this.isCover = false,
    this.onSetCover,
  });

  /// Eskiz MUQOVA TANLASH tugmasimi. `false` — bosilsa galereya ochiladi
  /// (planirovka, 360° qatorlari shunday qoladi).
  final bool selectable;
  final bool isCover;
  final VoidCallback? onSetCover;

  final MediaItemStatus status;

  final String path;

  /// Bo'sh bo'lmasa — eskiz shu manzildan yuklanadi, [path] esa faqat
  /// kalit sifatida qoladi.
  final String? url;
  final String? file;
  final VoidCallback onRemove;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final idle = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    // Tanlangani YASHIL HALQA bilan ajralib turadi. Yozuv yo'q: qaysi rasm
    // muqova ekanini yuqoridagi sahna ko'rsatib turibdi, halqa esa tasmada
    // qaysi biri ekanini bildiradi.
    final showRing = selectable && isCover;
    final border = showRing ? AppColors.splashGreen : idle;
    final radius = BorderRadius.circular(12);

    return SizedBox(
      width: _thumbSize,
      height: _thumbSize,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              // Tanlanadigan qatorda bosish = MUQOVA QILISH. Allaqachon
              // muqova bo'lsa yoki tanlash o'chirilgan bo'lsa — galereya.
              onTap: (selectable && !isCover && onSetCover != null)
                  ? hapticSelect(onSetCover!)
                  : hapticTap(onOpen),
              child: ClipRRect(
                borderRadius: radius,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      color: border,
                      width: showRing ? 2 : 1,
                    ),
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
                    MediaItemStatus.local =>
                      (file != null && File(file!).existsSync())
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(File(file!), fit: BoxFit.cover),
                                const Align(
                                  alignment: Alignment.bottomRight,
                                  child: Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.cloud_upload_outlined,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : _Placeholder(
                              isDark: isDark,
                              color: AppColors.splashGreen,
                              child: const Icon(
                                Icons.play_circle_outline_rounded,
                                color: AppColors.splashGreen,
                                size: 26,
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
          // Muqova yo'lagi eskizning PASTIDA: yuqori o'ng burchakni
          // «o'chirish» tugmasi egallagan, ikkisi bir joyda bo'lsa bosishga
          // xalaqit berardi.
          //
          // Tanlanganida — kichik yashil belgi. Matn YO'Q: 96pt eskizdagi
          // 10pt yozuvni hech kim o'qimasdi, aynan shu sababli bu dizayn
          // almashtirildi.
          if (showRing)
            Positioned(
              right: 3,
              bottom: 3,
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: AppColors.splashGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 14,
                  color: Color(0xFF011606),
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

/// MUQOVA SAHNASI — tanlangan rasm, e'lon kartasidagi qirqim bilan.
///
/// Nima uchun katta: sotuvchi «qaysi biri asosiy» degan mavhum savolga emas,
/// «xaridor nimani ko'radi» degan savolga javob izlaydi. Kartaning o'zi 4:3
/// qirqim ishlatadi (`listing_card.dart`), shuning uchun bu yerda ham aynan
/// shu nisbat — ya'ni sahna va'da qilgan narsa haqiqatan chiqadi.
///
/// Bosilsa galereya ochiladi: barcha rasmlarni surib chiqish mumkin, ya'ni
/// eskiz bosish «tanlash» ga aylangani bilan hech bir rasm yo'qolmaydi.
class _CoverStage extends StatelessWidget {
  const _CoverStage({
    required this.path,
    required this.label,
    required this.onOpen,
    this.hint,
    this.url,
  });

  final String path;
  final String label;
  final String? hint;
  final String? url;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(16);
    final net = url != null && url!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: hapticTap(onOpen),
          child: ClipRRect(
            borderRadius: radius,
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (net)
                    Image.network(
                      url!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _fallbackIcon(isDark),
                    )
                  else
                    Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _fallbackIcon(isDark),
                    ),
                  Positioned(
                    left: 10,
                    top: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.splashGreen,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 13,
                            color: Color(0xFF011606),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            label,
                            style: const TextStyle(
                              fontFamily: 'MTSCompact',
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              height: 1.2,
                              color: Color(0xFF011606),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(
            hint!,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w500,
              fontSize: 12.5,
              height: 1.25,
              color: isDark ? const Color(0xFFB0B5BB) : const Color(0xFF6E7480),
            ),
          ),
        ],
      ],
    );
  }
}
