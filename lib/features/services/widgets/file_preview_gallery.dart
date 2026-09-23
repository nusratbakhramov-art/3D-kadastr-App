import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../theme/app_colors.dart';

/// Full-screen, swipeable image preview with pinch-to-zoom. Takes a list of
/// LOCAL file paths. Shared by the AI Baholash intake and review steps.
///
/// MUQOVA (ixtiyoriy). E'lon sehrgarining foto qatori muqova tanlovini shu
/// yerga ham beradi: 96pt eskizdagi yo'lak kichkina, foydalanuvchi esa
/// rasmni KATTA ko'rib turib tanlashni kutadi. Callback'siz chaqiruvchilar
/// (AI Baholash) uchun hech narsa o'zgarmaydi.
class FilePreviewGallery extends StatefulWidget {
  const FilePreviewGallery({
    super.key,
    required this.paths,
    required this.initialIndex,
    this.coverIndex,
    this.coverLabel,
    this.makeCoverLabel,
    this.onSetCover,
  });

  final List<String> paths;
  final int initialIndex;

  /// Hozirgi muqovaning [paths] dagi o'rni. `null` — muqova tushunchasi yo'q.
  final int? coverIndex;

  /// Muqovadagi nishon matni («Asosiy rasm»).
  final String? coverLabel;

  /// Qolganlaridagi tugma matni («Asosiy qilish»). `null` — almashtirish yo'q.
  final String? makeCoverLabel;

  /// Muqovani almashtirish. `null` bo'lsa nishon faqat ko'rsatiladi.
  final ValueChanged<int>? onSetCover;

  @override
  State<FilePreviewGallery> createState() => _FilePreviewGalleryState();
}

class _FilePreviewGalleryState extends State<FilePreviewGallery> {
  late final PageController _pc;
  late int _index;

  /// Muqova SHU EKRANDA ham darhol ko'chishi kerak. Chaqiruvchi o'z holatini
  /// yangilaydi, lekin bu marshrut uning ustida turadi va qayta qurilmaydi.
  late int? _cover;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _cover = widget.coverIndex;
    _pc = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pc,
              itemCount: widget.paths.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Image.file(File(widget.paths[i]), fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: hapticTap(() => Navigator.of(context).pop()),
              ),
            ),
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.paths.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_index + 1} / ${widget.paths.length}',
                        style: const TextStyle(
                          fontFamily: 'MTSCompact',
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  if (widget.coverLabel != null) ...[
                    const SizedBox(height: 12),
                    _CoverAction(
                      isCover: _index == _cover,
                      coverLabel: widget.coverLabel!,
                      makeCoverLabel: widget.makeCoverLabel,
                      onSetCover: widget.onSetCover == null
                          ? null
                          : () {
                              widget.onSetCover!(_index);
                              setState(() => _cover = _index);
                            },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Katta rasm ostidagi muqova boshqaruvi.
///
/// Muqovada — bosilmaydigan yashil nishon; qolganlarida — «Asosiy qilish»
/// tugmasi. Ikkalasi bir joyda turadi, ya'ni surib o'tganda holat o'sha
/// joyda o'zgaradi va foydalanuvchi qidirmaydi.
class _CoverAction extends StatelessWidget {
  const _CoverAction({
    required this.isCover,
    required this.coverLabel,
    this.makeCoverLabel,
    this.onSetCover,
  });

  final bool isCover;
  final String coverLabel;
  final String? makeCoverLabel;
  final VoidCallback? onSetCover;

  @override
  Widget build(BuildContext context) {
    if (isCover) {
      return _pill(
        color: AppColors.splashGreen,
        icon: Icons.check_circle_rounded,
        text: coverLabel,
      );
    }
    final label = makeCoverLabel;
    if (label == null || onSetCover == null) return const SizedBox.shrink();
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hapticSelect(onSetCover!),
        child: _pill(
          color: Colors.transparent,
          icon: Icons.add_circle_outline,
          text: label,
        ),
      ),
    );
  }

  Widget _pill({
    required Color color,
    required IconData icon,
    required String text,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Colors.white),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: Colors.white,
          ),
        ),
      ],
    ),
  );
}
