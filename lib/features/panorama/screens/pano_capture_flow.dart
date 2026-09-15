/// 360° panorama: suratga olish → TELEFONDA tikish → tayyor faylni yuklash.
///
/// Uch bosqich, hammasi shu ekranda, foydalanuvchi natijani KUTADI:
///
///   1. nativ capture (ARKit, `PanoCapture.swift`) — 30 nishon, kadrlar +
///      `meta.json` `tmp/pano/<uuid>/` ga;
///   2. nativ tikish (`PanoStitch.swift` → C++ `PanoCore/`) — o'sha
///      katalogga `pano.jpg`; progress + o'tgan vaqt ko'rsatiladi. iPhone 14
///      Pro'da MVS "tez" preset ~1.5–2 daqiqa, rotatsiya-only 30–90 s;
///   3. nativ natija ko'rish (`PanoTour.swift` `preview`) — sferada
///      «Davom etish» / «Qayta tushirish» (Uy360 `LocalResultView`);
///   4. `POST /listings/media role=panorama` — bitta JPEG (~2–4 MB) →
///      S3 kaliti + URL. Kalit sehrgar qoralamasiga to'g'ridan yoziladi.
///
/// ⚠️ ILGARI kadrlar serverga yuborilib u yerda tikilardi (`PanoApi`,
/// `celery-panorama`) va bu prodda **7–9 daqiqa** olardi — shuning uchun
/// oqim fonga (`PanoJobWatcher`, `PendingPano`) ko'chirilgan edi. Endi
/// tikish telefonda va bir-ikki daqiqa, ya'ni kutish ekranga qaytdi va
/// natija DARHOL kalit bo'ladi: `pendingPanoramas` YANGI panorama uchun
/// yozilmaydi (eski qoralamalardagi `job:<id>` havolalar uchun watcher
/// saqlanib qolgan).
///
/// Qayta urinish KADRLARNI QAYTA OLMAYDI: tikish yiqilsa kadrlar diskda,
/// yuklash yiqilsa `pano.jpg` ham diskda — faqat yiqilgan bosqich
/// takrorlanadi. Katalog FAQAT muvaffaqiyatli yuklashdan keyin o'chiriladi.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../bozor/data/bozor_api.dart';
import '../data/pano_capture_channel.dart';

/// Oqim natijasi.
///
/// [PanoUploaded] — hammasi tugadi, kalit tayyor. [PanoSaved] — kadrlar (va
/// balki tikilgan `pano.jpg`) TELEFONDA saqlangan, lekin yuklanmagan:
/// foydalanuvchi xato ekranidan chiqdi. Qoralama uni `LocalPano` qilib
/// saqlaydi va keyin [openPanoCapture] `resumeDir` bilan davom ettiradi.
/// `null` — capture'ning o'zi bekor qilingan (hech narsa yo'q).
sealed class PanoOutcome {
  const PanoOutcome();
}

/// Tayyor va YUKLANGAN panorama.
///
/// `storageKey` — `listings/media/{user_id}/….jpg`, e'longa SHU qo'shiladi;
/// `url` — ko'rsatish uchun (eskiz, sfera).
@immutable
class PanoUploaded extends PanoOutcome {
  const PanoUploaded({required this.storageKey, required this.url});

  final String storageKey;
  final String url;
}

/// Telefonda saqlangan, yuklanmagan tushirish.
@immutable
class PanoSaved extends PanoOutcome {
  const PanoSaved({required this.dir, required this.stitched, this.error});

  final String dir;

  /// `pano.jpg` tayyormi (yuklash yiqilgan) yoki faqat kadrlar (tikish
  /// yiqilgan / bekor).
  final bool stitched;
  final String? error;
}

/// Ekranni ochadi. [resumeDir] — avval saqlangan tushirish: capture
/// o'tkazib yuboriladi, yiqilgan bosqichdan (tikish yoki yuklash) davom
/// etadi. [onCaptured] — capture TUGASHI bilan (tikishdan OLDIN) katalog;
/// chaqiruvchi shu zahoti qoralamaga yozadi — ilova tikish paytida o'lsa ham
/// kadrlar egasiz qolmasin.
Future<PanoOutcome?> openPanoCapture(
  BuildContext context, {
  String? resumeDir,
  void Function(String dir)? onCaptured,
}) => Navigator.of(context).push<PanoOutcome>(
  MaterialPageRoute<PanoOutcome>(
    builder: (_) =>
        PanoCaptureFlow(resumeDir: resumeDir, onCaptured: onCaptured),
  ),
);

/// Oqimning qaysi bosqichida turibmiz.
enum _Stage { capturing, stitching, previewing, uploading, failed }

/// Nativ capture — test uchun almashtiriladi.
typedef PanoCaptureFn = Future<PanoCaptureResult?> Function(BuildContext);

/// Nativ natija ko'rish — test uchun almashtiriladi.
typedef PanoPreviewFn =
    Future<PanoPreviewAction> Function(BuildContext, String path);

/// Nativ tikish — test uchun almashtiriladi.
typedef PanoStitchFn =
    Future<PanoStitchResult> Function({
      required String dir,
      void Function(double p, String msg)? onProgress,
    });

class PanoCaptureFlow extends StatefulWidget {
  const PanoCaptureFlow({
    super.key,
    this.resumeDir,
    this.onCaptured,
    this.api,
    this.capture,
    this.stitch,
    this.preview,
  });

  /// Saqlangan tushirish katalogi — capture o'tkazib yuboriladi.
  final String? resumeDir;

  /// Capture tugashi bilan chaqiriladi (katalog). [openPanoCapture] izohi.
  final void Function(String dir)? onCaptured;

  /// Faqat testlar uchun — sukut bo'yicha haqiqiy kanal va `BozorApi`.
  final BozorApi? api;
  final PanoCaptureFn? capture;
  final PanoStitchFn? stitch;
  final PanoPreviewFn? preview;

  @override
  State<PanoCaptureFlow> createState() => PanoCaptureFlowState();
}

/// ⚠️ OCHIQ (xususiy emas) FAQAT test uchun.
class PanoCaptureFlowState extends State<PanoCaptureFlow> {
  late final BozorApi _api = widget.api ?? BozorApi();
  late final PanoCaptureFn _capture =
      widget.capture ?? PanoCaptureChannel.start;
  late final PanoStitchFn _stitch = widget.stitch ?? _defaultStitch;
  late final PanoPreviewFn _preview = widget.preview ?? _defaultPreview;

  static Future<PanoPreviewAction> _defaultPreview(
    BuildContext context,
    String path,
  ) => PanoCaptureChannel.preview(context, path: path);

  /// Nadir (oyoq osti) suratga OLINMAYDI — o'rniga shu disk-logo bosiladi
  /// (`PanoCapture.swift` nishon to'ri, yadro `nadirLogoPath`).
  static const String kNadirLogoAsset = 'assets/branding/nadir_logo.png';

  static Future<PanoStitchResult> _defaultStitch({
    required String dir,
    void Function(double p, String msg)? onProgress,
  }) => PanoCaptureChannel.stitch(
    dir: dir,
    logoAsset: kNadirLogoAsset,
    onProgress: onProgress,
  );

  _Stage _stage = _Stage.capturing;
  double _progress = 0;
  String _note = '';
  String? _error;

  PanoCaptureResult? _shot;
  bool _started = false;

  // Tikish vaqti — foydalanuvchi «qotib qoldimi» deb o'ylamasin.
  Timer? _ticker;
  DateTime? _stitchStarted;
  int _elapsedS = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Ekran chizilgandan KEYIN boshlanadi — nativ ekran shu Navigator ustiga
    // modal bo'lib chiqadi.
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    try {
      final resume = widget.resumeDir;
      if (resume != null && _shot == null && Directory(resume).existsSync()) {
        // Saqlangan tushirish — capture yo'q, yiqilgan bosqichdan.
        final frames = Directory(resume)
            .listSync()
            .where(
              (f) => f.path.endsWith('.jpg') && !f.path.endsWith('pano.jpg'),
            )
            .length;
        final shot = PanoCaptureResult(dir: resume, frames: frames);
        _shot = shot;
        final pano = _panoFile(shot);
        if (pano.existsSync()) {
          await _previewThenUpload(shot, pano);
        } else {
          await _stitchThenUpload(shot);
        }
        return;
      }
      final shot = await _capture(context);
      if (!mounted) return;
      if (shot == null) {
        Navigator.of(context).pop(); // bekor qilindi
        return;
      }
      _shot = shot;
      widget.onCaptured?.call(shot.dir);
      await _stitchThenUpload(shot);
    } on Object catch (e) {
      _fail(e);
    }
  }

  /// Xato ekranidan chiqish: kadrlar bo'lsa ULAR SAQLANADI — qoralama
  /// `LocalPano` qilib yozadi, keyin davom ettiriladi.
  void _leave() {
    final shot = _shot;
    if (shot != null && shot.directory.existsSync()) {
      Navigator.of(context).pop(
        PanoSaved(
          dir: shot.dir,
          stitched: _panoFile(shot).existsSync(),
          error: _error,
        ),
      );
      return;
    }
    Navigator.of(context).pop();
  }

  File _panoFile(PanoCaptureResult shot) => File('${shot.dir}/pano.jpg');

  Future<void> _stitchThenUpload(PanoCaptureResult shot) async {
    if (!File('${shot.dir}/meta.json').existsSync()) {
      _fail(StateError('meta.json topilmadi'));
      return;
    }
    setState(() {
      _stage = _Stage.stitching;
      _progress = 0;
      _note = '';
      _elapsedS = 0;
    });
    _stitchStarted = DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _stitchStarted == null) return;
      setState(
        () => _elapsedS = DateTime.now().difference(_stitchStarted!).inSeconds,
      );
    });

    final result = await _stitch(
      dir: shot.dir,
      onProgress: (p, _) {
        if (!mounted) return;
        setState(() => _progress = p.clamp(0.0, 1.0));
      },
    );
    _ticker?.cancel();
    _ticker = null;
    if (!mounted) return;
    await _previewThenUpload(shot, File(result.panoPath));
  }

  /// Natijani sferada ko'rsatadi: qabul → yuklash; qayta tushirish → kadrlar
  /// tashlanadi va capture qaytadan ochiladi (bu safar foydalanuvchi ONGLI
  /// ravishda qaytadan aylanadi — sifat yoqmagani uchun).
  Future<void> _previewThenUpload(PanoCaptureResult shot, File pano) async {
    setState(() {
      _stage = _Stage.previewing;
      _note = '';
    });
    final action = await _preview(context, pano.path);
    if (!mounted) return;
    if (action == PanoPreviewAction.retake) {
      await shot.cleanUp();
      _shot = null;
      if (!mounted) return;
      setState(() => _stage = _Stage.capturing);
      await _run();
      return;
    }
    await _upload(shot, pano);
  }

  Future<void> _upload(PanoCaptureResult shot, File pano) async {
    setState(() {
      _stage = _Stage.uploading;
      _progress = 0;
      _note = '';
    });
    final uploaded = await _api.uploadMedia(
      role: 'panorama',
      paths: [pano.path],
    );
    if (!mounted) return;
    if (uploaded.isEmpty) {
      _fail(StateError('server kalit qaytarmadi'));
      return;
    }
    final m = uploaded.first;

    // Panorama SERVERDA — kadrlar ham, `pano.jpg` ham endi kerak emas
    // (bitta tushirish ~75 MB to'liq o'lchamli kadr). ⚠️ AYNAN SHU YERDA,
    // yuklash MUVAFFAQIYATLI bo'lgandan keyin: ilgariroq o'chirsak qayta
    // urinish uchun hech narsa qolmasdi.
    await shot.cleanUp();
    if (!mounted) return;
    Navigator.of(context).pop(PanoUploaded(storageKey: m.key, url: m.url));
  }

  void _fail(Object e) {
    _ticker?.cancel();
    _ticker = null;
    if (!mounted) return;
    setState(() {
      _stage = _Stage.failed;
      // Nativ taraf xatoni `PlatformException` qilib qaytaradi (masalan
      // `STITCH_FAILED`). Uning `toString()` i «PlatformException(
      // STITCH_FAILED, …, null, null)» bo'ladi — foydalanuvchiga shu
      // ko'rinishda chiqarish mumkin emas.
      _error = switch (e) {
        BozorApiException(:final message) => message,
        PlatformException(:final message?) => message,
        _ => e.toString(),
      };
    });
  }

  /// Qayta urinish — faqat YIQILGAN bosqichdan.
  Future<void> _retry() async {
    final shot = _shot;
    setState(() => _error = null);
    try {
      if (shot != null && shot.directory.existsSync()) {
        final pano = _panoFile(shot);
        if (pano.existsSync()) {
          // Tikish bo'lgan, yuklash yiqilgan — faqat yuklash.
          await _upload(shot, pano);
        } else {
          // Kadrlar bor, tikish yiqilgan — 30 nishonni qayta aylanmaymiz.
          await _stitchThenUpload(shot);
        }
      } else {
        setState(() => _stage = _Stage.capturing);
        await _run();
      }
    } on Object catch (e) {
      _fail(e);
    }
  }

  static String _mmss(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final fg = isDark ? Colors.white : AppColors.textBlack;

    return PopScope(
      // Tikish/yuklash ketyapti — orqaga qaytish ishni yarim yo'lda
      // qoldiradi (nativ tikish baribir tugaydi, lekin natija yo'qoladi).
      // Ataylab bloklaymiz; xato holatida orqaga surish ham `_leave` orqali
      // — kadrlar SAQLANGAN holda (`PanoSaved`) chiqadi, `null` bilan emas.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _stage == _Stage.failed) _leave();
      },
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: _stage == _Stage.failed
                  ? _errorView(l, fg)
                  : _busyView(l, fg),
            ),
          ),
        ),
      ),
    );
  }

  Widget _busyView(Locale l, Color fg) {
    final title = switch (_stage) {
      _Stage.capturing || _Stage.previewing => tr(l, 'bozor.pano.flow.opening'),
      _Stage.stitching => tr(l, 'bozor.pano.flow.stitching'),
      _ => tr(l, 'bozor.pano.flow.uploading_pano'),
    };
    // Nativ ekran ochilayotganda va yuklashda progress noma'lum —
    // aylanuvchi ko'rsatkich; tikishda yadro 0..1 beradi.
    final value = _stage == _Stage.stitching ? _progress.clamp(0.0, 1.0) : null;
    final note = _stage == _Stage.stitching
        ? '${(_progress * 100).round()}% · ${_mmss(_elapsedS)}'
        : _note;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 64,
          height: 64,
          child: CircularProgressIndicator(
            value: value,
            strokeWidth: 4,
            color: AppColors.splashGreen,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: fg,
          ),
        ),
        if (note.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            note,
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 13,
              color: fg.withValues(alpha: 0.6),
            ),
          ),
        ],
        if (_stage == _Stage.stitching) ...[
          const SizedBox(height: 16),
          Text(
            tr(l, 'bozor.pano.flow.stitch_hint'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 12,
              color: fg.withValues(alpha: 0.45),
            ),
          ),
        ],
      ],
    );
  }

  Widget _errorView(Locale l, Color fg) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(
        Icons.error_outline_rounded,
        size: 44,
        color: Color(0xFFE0492A),
      ),
      const SizedBox(height: 16),
      Text(
        tr(l, 'bozor.pano.flow.failed'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'MTSCompact',
          fontWeight: FontWeight.w700,
          fontSize: 17,
          color: fg,
        ),
      ),
      if ((_error ?? '').isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          _error!,
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'MTSText',
            fontSize: 13,
            color: fg.withValues(alpha: 0.6),
          ),
        ),
      ],
      const SizedBox(height: 24),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(onPressed: _leave, child: Text(tr(l, 'common.cancel'))),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _retry,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.splashGreen,
            ),
            child: Text(tr(l, 'bozor.pano.flow.retry')),
          ),
        ],
      ),
    ],
  );
}
