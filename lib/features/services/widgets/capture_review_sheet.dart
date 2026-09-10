/// Yozuvdan keyingi varaq — videoni yuklashdan OLDIN foydalanuvchidan
/// tasdiq oladi.
///
/// Nega kerak: ilgari kamera yopilishi bilan video darhol 3DGS serverga
/// ketardi. Yozuv esa foydalanuvchi tugatmasdan ham tugashi mumkin (xotira
/// to'ladi, telefon qizib ketadi, ilova fonga o'tadi) — natijada yarim
/// video jimgina yuklanib, serverda GPU vaqti behuda ketardi. Fayl 1.5 GB
/// gacha bo'lishi mumkin, ya'ni xato yuklash qimmat.
///
/// Shuning uchun bu varaq uch narsani beradi:
///   1. yozuv o'zidan-o'zi tugagan bo'lsa — SABABI ko'rinadi;
///   2. video haqidagi haqiqiy raqamlar (davomiylik, hajm, kadr tezligi);
///   3. uch aniq yo'l: yuklash / qayta olish / o'chirib tashlash.
library;

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../data/video_capture.dart';
import '../models/ai_baholash_bundle.dart';

/// Foydalanuvchi tanlovi.
enum CaptureReviewChoice {
  /// Serverga yuborish.
  upload,

  /// Bu videoni tashlab, qaytadan yozish.
  retake,

  /// Butunlay bekor qilish (video o'chiriladi).
  discard,
}

/// Varaqni ochadi. Tashqariga bosib yopilsa — [CaptureReviewChoice.discard]
/// EMAS, `null` qaytadi: tasodifiy bosishda video o'chib ketmasligi kerak.
Future<CaptureReviewChoice?> showCaptureReviewSheet(
  BuildContext context, {
  required VideoCaptureResult video,
  required RoomChoice room,
}) {
  return showModalBottomSheet<CaptureReviewChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CaptureReviewSheet(video: video, room: room),
  );
}

class _CaptureReviewSheet extends StatelessWidget {
  const _CaptureReviewSheet({required this.video, required this.room});

  final VideoCaptureResult video;
  final RoomChoice room;

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF15191B) : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : const Color(0xFFD9DEE1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                _S.title(l),
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                room.label(l),
                style: TextStyle(
                  fontFamily: 'MTSText',
                  fontSize: 13,
                  height: 1.35,
                  color: subColor,
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Yozuv o'zi to'xtagan bo'lsa — eng tepada, chunki bu
                      // qarorni o'zgartiradi: yarim videoni yuklash ko'pincha
                      // ma'nosiz.
                      if (video.endedEarly)
                        _Warning(
                          text: _S.endedEarly(l, video.endReason),
                          isDark: isDark,
                        ),
                      // Kadr tashlangan bo'lsa sifat pasayadi — buni ham
                      // yashirmaymiz, lekin bu to'xtatuvchi emas.
                      if (!video.endedEarly && video.droppedPercent >= 10)
                        _Warning(
                          text: _S.dropped(l, video.droppedPercent),
                          isDark: isDark,
                          mild: true,
                        ),
                      _FactRow(
                        label: _S.factDuration(l),
                        value: video.durationLabel,
                        isDark: isDark,
                      ),
                      _FactRow(
                        label: _S.factSize(l),
                        value: video.sizeLabel,
                        isDark: isDark,
                      ),
                      if (video.width > 0 && video.height > 0)
                        _FactRow(
                          label: _S.factQuality(l),
                          value: '${video.height}p${video.fpsLabel.isEmpty ? '' : ' '}'
                              '${video.fpsLabel.replaceFirst('@', '')}',
                          isDark: isDark,
                        ),
                      if (video.zoom.isNotEmpty)
                        _FactRow(
                          label: _S.factLens(l),
                          value: video.zoom,
                          isDark: isDark,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _PrimaryButton(
                label: _S.upload(l),
                onTap: () =>
                    Navigator.of(context).pop(CaptureReviewChoice.upload),
              ),
              const SizedBox(height: 8),
              _SecondaryButton(
                label: _S.retake(l),
                color: AppColors.splashGreen,
                onTap: () =>
                    Navigator.of(context).pop(CaptureReviewChoice.retake),
              ),
              _SecondaryButton(
                label: _S.discard(l),
                color: AppColors.chatRedDeep,
                onTap: () =>
                    Navigator.of(context).pop(CaptureReviewChoice.discard),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ogohlantirish paneli. `mild` — sifat haqida (sariq), aks holda yozuv
/// uzilgani haqida (qizil).
class _Warning extends StatelessWidget {
  const _Warning({
    required this.text,
    required this.isDark,
    this.mild = false,
  });

  final String text;
  final bool isDark;
  final bool mild;

  @override
  Widget build(BuildContext context) {
    final accent = mild ? const Color(0xFFE0A12A) : AppColors.chatRedDeep;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            mild ? Icons.info_outline_rounded : Icons.warning_amber_rounded,
            size: 18,
            color: accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'MTSText',
                fontSize: 13,
                height: 1.35,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.label,
    required this.value,
    required this.isDark,
  });

  final String label;
  final String value;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'MTSText',
                fontSize: 13,
                color: subColor,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.splashGreen,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        foregroundColor: color,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'MTSCompact',
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: color,
        ),
      ),
    );
  }
}

class _S {
  const _S._();

  static String title(Locale l) => tr(l, 'services.ai.capture.review_title');
  static String upload(Locale l) => tr(l, 'services.ai.capture.review_upload');
  /// Bundle'da allaqachon bor va ishlatilmagan kalit — takrorlamaymiz.
  static String retake(Locale l) => tr(l, 'services.ai.capture.record_again');
  static String discard(Locale l) =>
      tr(l, 'services.ai.capture.review_discard');
  static String factDuration(Locale l) =>
      tr(l, 'services.ai.capture.fact_duration');
  static String factSize(Locale l) => tr(l, 'services.ai.capture.fact_size');
  static String factQuality(Locale l) =>
      tr(l, 'services.ai.capture.fact_quality');
  static String factLens(Locale l) => tr(l, 'services.ai.capture.fact_lens');

  /// Sabab native tomondan matn sifatida keladi (o'zbekcha) va tarjima
  /// shabloniga qo'yiladi. Sabab bo'sh bo'lsa shablonning o'zi yetarli.
  static String endedEarly(Locale l, String reason) {
    final template = tr(l, 'services.ai.capture.ended_early');
    return reason.isEmpty
        ? template
        : template.replaceFirst('{reason}', reason);
  }

  static String dropped(Locale l, int percent) => tr(
        l,
        'services.ai.capture.dropped_frames',
      ).replaceFirst('{percent}', '$percent');
}
