/// Panorama capture → on-device processing → preview → listing media upload.
///
/// Production selects Astra ultra-wide/CoreMotion (17 required targets), with
/// ARKit as the compatibility path. Frames and metadata live in the persistent
/// `Application Support/pano/<uuid>` directory and are registered in the draft
/// before processing starts.
///
/// Native Astra processing writes `pano.jpg` and `preview.jpg`. The existing
/// preview asks for acceptance or retake; only the finished panorama is uploaded.
/// The storage key and URL feed the existing listing/room/draft contract.
///
/// Recovery validates saved JPEGs and repeats only the failed stage. Source
/// frames survive processing/upload failures; successful upload or explicit
/// retake removes the directory. Legacy server-job drafts retain their watcher.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

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
/// kadrlar egasiz qolmasin. [onDiscarded] — qayta tushirish uchun eski
/// katalog tashlanganda, yangi capture ochilishidan OLDIN chaqiriladi.
///
/// [upload] — tayyor `pano.jpg` ni qayerga yuklash. Sukut bo'yicha Bozor
/// (`POST /listings/media`, role=panorama); AI Baholash o'zining
/// `/ai-valuations/upload` (category=panorama) yo'lini beradi.
Future<PanoOutcome?> openPanoCapture(
  BuildContext context, {
  String? resumeDir,
  void Function(String dir)? onCaptured,
  void Function(String dir)? onDiscarded,
  PanoUploadFn? upload,
}) => Navigator.of(context).push<PanoOutcome>(
  MaterialPageRoute<PanoOutcome>(
    builder: (_) => PanoCaptureFlow(
      resumeDir: resumeDir,
      onCaptured: onCaptured,
      onDiscarded: onDiscarded,
      upload: upload,
    ),
  ),
);

/// Yuklash natijasi: saqlash kaliti + ko'rsatish manzili (URL yoki lokal yo'l).
typedef PanoUploadResult = ({String key, String url});

/// Tayyor panoramani yuklaydi. `null` yoki bo'sh kalit — xato ekrani.
typedef PanoUploadFn = Future<PanoUploadResult?> Function(String panoPath);

typedef PanoCaptureOpener =
    Future<PanoOutcome?> Function(
      BuildContext context, {
      String? resumeDir,
      void Function(String dir)? onCaptured,
      void Function(String dir)? onDiscarded,
    });

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
    this.onDiscarded,
    this.api,
    this.upload,
    this.capture,
    this.stitch,
    this.preview,
  });

  /// Yuklash yo'li — [openPanoCapture] izohi. `null` — Bozor ([api]).
  final PanoUploadFn? upload;

  /// Saqlangan tushirish katalogi — capture o'tkazib yuboriladi.
  final String? resumeDir;

  /// Capture tugashi bilan chaqiriladi (katalog). [openPanoCapture] izohi.
  final void Function(String dir)? onCaptured;

  /// Qayta tushirishda eski katalog tashlandi — qoralamadagi havolani
  /// olib tashlash uchun.
  final void Function(String dir)? onDiscarded;

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
      widget.capture ?? PanoCaptureChannel.startPreferred;
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
  bool _stitched = false;
  bool _previewAccepted = false;
  bool _started = false;
  bool _resumeAttempted = false;

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
      // Faqat birinchi kirishda davom ettiramiz. Retake'da tozalash
      // muvaffaqiyatsiz bo'lsa ham rad etilgan katalog qayta ochilmasin.
      final resume = _resumeAttempted ? null : widget.resumeDir;
      _resumeAttempted = true;
      if (resume != null && _shot == null && Directory(resume).existsSync()) {
        // Saqlangan tushirish — capture yo'q, yiqilgan bosqichdan.
        final frames = Directory(resume)
            .listSync()
            .where(
              (f) =>
                  f is File &&
                  f.uri.pathSegments.last.startsWith('frame_') &&
                  f.path.endsWith('.jpg'),
            )
            .length;
        final shot = PanoCaptureResult(dir: resume, frames: frames);
        _shot = shot;
        final pano = _panoFile(shot);
        _stitched = await _completePanorama(pano);
        if (!mounted) return;
        if (_stitched) {
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
      Navigator.of(
        context,
      ).pop(PanoSaved(dir: shot.dir, stitched: _stitched, error: _error));
      return;
    }
    Navigator.of(context).pop();
  }

  File _panoFile(PanoCaptureResult shot) => File('${shot.dir}/pano.jpg');

  /// Old drafts may contain a JPEG interrupted while being written. Validate
  /// without decoding a full 6144-pixel texture or requiring a legacy preview.
  static Future<bool> _completePanorama(File file) async {
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length < 4 ||
          bytes[0] != 0xff ||
          bytes[1] != 0xd8 ||
          bytes[bytes.length - 2] != 0xff ||
          bytes.last != 0xd9) {
        return false;
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          if (descriptor.height <= 0 ||
              descriptor.width != descriptor.height * 2) {
            return false;
          }
          final codec = await descriptor.instantiateCodec(targetWidth: 32);
          try {
            final frame = await codec.getNextFrame();
            frame.image.dispose();
          } finally {
            codec.dispose();
          }
          return true;
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
    } on Object {
      return false;
    }
  }

  Future<void> _stitchThenUpload(PanoCaptureResult shot) async {
    _stitched = false;
    _previewAccepted = false;
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
    _stitched = await _completePanorama(File(result.panoPath));
    if (!mounted) return;
    if (!_stitched) {
      throw PlatformException(
        code: 'STITCH_FAILED',
        message: tr(Localizations.localeOf(context), 'bozor.pano.flow.failed'),
      );
    }
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
      _stitched = false;
      _previewAccepted = false;
      if (!mounted) return;
      widget.onDiscarded?.call(shot.dir);
      setState(() => _stage = _Stage.capturing);
      await _run();
      return;
    }
    _previewAccepted = true;
    await _upload(shot, pano);
  }

  Future<void> _upload(PanoCaptureResult shot, File pano) async {
    setState(() {
      _stage = _Stage.uploading;
      _progress = 0;
      _note = '';
    });
    final PanoUploadResult? m;
    final upload = widget.upload;
    if (upload != null) {
      m = await upload(pano.path);
    } else {
      final uploaded = await _api.uploadMedia(
        role: 'panorama',
        paths: [pano.path],
      );
      m = uploaded.isEmpty
          ? null
          : (key: uploaded.first.key, url: uploaded.first.url);
    }
    if (!mounted) return;
    if (m == null || m.key.trim().isEmpty || m.url.trim().isEmpty) {
      _fail(StateError('server kalit qaytarmadi'));
      return;
    }

    // Panorama SERVERDA — kadrlar ham, `pano.jpg` ham endi kerak emas
    // Yuklash MUVAFFAQIYATLI bo'lgandan keyin: ilgariroq o'chirsak qayta
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
        _stitched = await _completePanorama(pano);
        if (!mounted) return;
        if (_stitched) {
          if (_previewAccepted) {
            await _upload(shot, pano);
          } else {
            // A failed viewer must never turn retry into an unapproved upload.
            await _previewThenUpload(shot, pano);
          }
        } else {
          // Saved frames can be processed again without repeating capture.
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
