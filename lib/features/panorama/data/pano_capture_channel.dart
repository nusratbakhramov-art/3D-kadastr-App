/// Native panorama capture, processing and viewing on `kadastr/pano_capture`.
///
/// Production chooses Astra ultra-wide/CoreMotion capture when its camera,
/// motion, permission and sensor-processing capabilities are available; ARKit
/// remains the fallback. Viewer support is independent of capture support.
///
/// Both paths save camera-to-world transforms, intrinsics and JPEGs locally.
/// [stitch] invokes Astra's C++ core through `PanoStitch.swift`; Dart uploads
/// only the finished `pano.jpg` through the existing listing media API.
/// Android capture remains unavailable until its native processing port is ready.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_translations.dart';

/// Native capture paths. Production selects ultra-wide when available, then ARKit.
enum PanoCaptureMode { arkit, ultrawide }

/// Separate from panorama viewer support. Not-determined camera permission can
/// be requested on start; denied/restricted permission makes capture unavailable.
@immutable
class PanoUltraWideCapability {
  const PanoUltraWideCapability({
    required this.available,
    required this.cameraAuthorization,
    this.reason,
  });

  final bool available;
  final String cameraAuthorization;
  final String? reason;
}

/// Telefonda tikish natijasi (`stitch` javobi).
@immutable
class PanoStitchResult {
  const PanoStitchResult({
    required this.panoPath,
    required this.previewPath,
    this.width = 0,
    this.height = 0,
    this.frames = 0,
    this.coverage = 0,
    this.seconds = 0,
    this.mode = '',
  });

  /// Tayyor equirect JPEG (2:1) — SHU fayl serverga yuklanadi.
  final String panoPath;
  final String previewPath;
  final int width;
  final int height;
  final int frames;

  /// Sferaning qancha qismi kadrlar bilan qoplangan (0..1).
  final double coverage;

  /// Tikish vaqti (devor soati, s) — tashxis uchun.
  final double seconds;

  /// Selected pipeline: `mvs` | `fast`. Sensor MVS may fall back to rotation
  /// when image evidence is insufficient for translation/depth.
  final String mode;

  File get panoFile => File(panoPath);

  factory PanoStitchResult.fromChannel(Map<Object?, Object?> raw) =>
      PanoStitchResult(
        panoPath: (raw['pano'] ?? '').toString(),
        previewPath: (raw['preview'] ?? '').toString(),
        width: (raw['width'] as num?)?.toInt() ?? 0,
        height: (raw['height'] as num?)?.toInt() ?? 0,
        frames: (raw['frames'] as num?)?.toInt() ?? 0,
        coverage: (raw['coverage'] as num?)?.toDouble() ?? 0,
        seconds: (raw['seconds'] as num?)?.toDouble() ?? 0,
        mode: (raw['mode'] ?? '').toString(),
      );
}

/// Nativ ekran qaytargan natija.
@immutable
class PanoCaptureResult {
  const PanoCaptureResult({required this.dir, required this.frames});

  /// Kadrlar va `meta.json` turgan katalog.
  ///
  /// Persistent `Application Support/pano/<uuid>` directory, retained for draft
  /// recovery. [cleanUp] removes it after upload, retake or explicit deletion.
  final String dir;

  /// Nechta kadr olindi.
  final int frames;

  Directory get directory => Directory(dir);

  /// Katalogni o'chiradi. Idempotent — ikki marta chaqirilsa ham xato yo'q.
  Future<void> cleanUp() async {
    try {
      final d = directory;
      if (d.existsSync()) await d.delete(recursive: true);
    } on FileSystemException {
      // Best effort: a cleanup failure must not discard a successful upload.
      // This persistent directory can remain on disk if deletion fails.
    }
  }
}

/// Natija ko'rish ekranining javobi.
enum PanoPreviewAction { accept, retake }

/// Nativ turga beriladigan bitta xona.
@immutable
class PanoTourRoom {
  const PanoTourRoom({
    required this.key,
    required this.name,
    this.url,
    this.path,
  });

  /// Havolalar ishlatadigan identifikator (S3 kaliti).
  final String key;
  final String name;
  final String? url;
  final String? path;

  Map<String, Object?> toChannel() => <String, Object?>{
    'key': key,
    'name': name,
    'url': ?url,
    'path': ?path,
  };
}

/// Turdan «Yangi xona — hozir tushirish» tanlandi: tugma [fromKey] xonasida
/// [yawDeg]/[pitchDeg] yo'nalishga qo'yiladi, xona esa hali tushirilmagan.
@immutable
class PanoTourNewRoom {
  const PanoTourNewRoom({
    required this.fromKey,
    required this.yawDeg,
    required this.pitchDeg,
  });

  final String fromKey;
  final double yawDeg;
  final double pitchDeg;
}

@immutable
class PanoTourResult {
  const PanoTourResult({required this.links, this.newRoom});

  /// Havolalar — `{from, to, yawDeg, pitchDeg, label?}` xaritalari
  /// (`TourLink.fromJson` bilan bir xil kalitlar).
  final List<Map<String, Object?>> links;
  final PanoTourNewRoom? newRoom;

  factory PanoTourResult.fromChannel(Map<Object?, Object?> raw) {
    final links = <Map<String, Object?>>[
      for (final Object? l in (raw['links'] as List?) ?? const [])
        if (l is Map)
          <String, Object?>{
            'from': (l['from'] ?? '').toString(),
            'to': (l['to'] ?? '').toString(),
            'yawDeg': (l['yawDeg'] as num?)?.toDouble() ?? 0,
            'pitchDeg': (l['pitchDeg'] as num?)?.toDouble() ?? 0,
            if (l['label'] != null) 'label': l['label'].toString(),
          },
    ];
    PanoTourNewRoom? newRoom;
    final a = raw['action'];
    if (a is Map && a['type'] == 'newRoom') {
      newRoom = PanoTourNewRoom(
        fromKey: (a['fromKey'] ?? '').toString(),
        yawDeg: (a['yawDeg'] as num?)?.toDouble() ?? 0,
        pitchDeg: (a['pitchDeg'] as num?)?.toDouble() ?? 0,
      );
    }
    return PanoTourResult(links: links, newRoom: newRoom);
  }
}

abstract final class PanoCaptureChannel {
  static const MethodChannel _channel = MethodChannel('kadastr/pano_capture');

  /// Legacy ARKit hardware query. New callers must use the separate capture,
  /// processing and viewer capabilities below.
  static Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // Kanal ro'yxatda yo'q (masalan hali qo'llab-quvvatlanmagan platforma).
      return false;
    }
  }

  /// Whether this build can process saved CoreMotion captures. Independent of
  /// ARKit, ultra-wide camera/permission, and viewer availability.
  static Future<bool> isSensorProcessingSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSensorProcessingSupported') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// ARKit tracking and camera permission, independent of ultra-wide and viewer.
  static Future<bool> isARKitCaptureSupported() =>
      _supports('isARKitCaptureSupported');

  /// Native tour viewer availability; viewing never requires camera permission.
  static Future<bool> isViewerSupported() => _supports('isViewerSupported');

  static Future<bool> _supports(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Recheck on each capture so changes to camera permission are respected.
  /// Undetermined permission is requestable; native capture prompts on start.
  static Future<PanoCaptureMode?> preferredCaptureMode() async {
    final ultraWide = await ultraWideCapability();
    if (ultraWide.available && await isSensorProcessingSupported()) {
      return PanoCaptureMode.ultrawide;
    }
    return await isARKitCaptureSupported() ? PanoCaptureMode.arkit : null;
  }

  /// Production entry. Explicit [start] remains available for either capture path.
  static Future<PanoCaptureResult?> startPreferred(BuildContext context) async {
    final locale = Localizations.localeOf(context);
    final mode = await preferredCaptureMode();
    if (!context.mounted) return null;
    if (mode == null) {
      throw PlatformException(
        code: 'NO_CAPTURE_MODE',
        message: tr(locale, 'bozor.pano.cap.err_unavailable'),
      );
    }
    try {
      return await start(context, mode: mode);
    } on PlatformException catch (error) {
      // A capability can change between the query and native presentation.
      // Never restart after cancellation, a capture failure, or interruption.
      const unavailable = {
        'UNSUPPORTED',
        'UNSUPPORTED_IOS',
        'NO_ULTRAWIDE_CAMERA',
        'NO_DEVICE_MOTION',
      };
      if (mode == PanoCaptureMode.ultrawide &&
          unavailable.contains(error.code) &&
          await isARKitCaptureSupported()) {
        if (!context.mounted) return null;
        return start(context, mode: PanoCaptureMode.arkit);
      }
      rethrow;
    }
  }

  /// Check capture hardware/permission without opening the camera or prompting.
  static Future<PanoUltraWideCapability> ultraWideCapability() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'ultraWideCapability',
      );
      return PanoUltraWideCapability(
        available: raw?['available'] == true,
        cameraAuthorization: (raw?['cameraAuthorization'] ?? 'unknown')
            .toString(),
        reason: raw?['reason']?.toString(),
      );
    } on MissingPluginException {
      return const PanoUltraWideCapability(
        available: false,
        cameraAuthorization: 'unknown',
        reason: 'UNSUPPORTED',
      );
    } on PlatformException catch (error) {
      return PanoUltraWideCapability(
        available: false,
        cameraAuthorization: 'unknown',
        reason: error.code,
      );
    }
  }

  /// Nativ ekranni ochadi. Foydalanuvchi bekor qilsa `null`.
  ///
  /// Matnlar SHU YERDA tarjima qilinadi va nativ tarafga uzatiladi — Swift va
  /// Kotlin'da i18n takrorlanmasin.
  static Future<PanoCaptureResult?> start(
    BuildContext context, {
    PanoCaptureMode? mode,
  }) async {
    final l = Localizations.localeOf(context);
    if (mode == PanoCaptureMode.ultrawide) {
      // Older native builds/platforms must not silently ignore the requested mode.
      final capability = await ultraWideCapability();
      if (!capability.available) {
        throw PlatformException(
          code: capability.reason ?? 'UNSUPPORTED',
          message: tr(
            l,
            _captureErrorKey(capability.reason ?? 'UNSUPPORTED') ??
                'bozor.pano.cap.err_unavailable',
          ),
        );
      }
    }
    final raw = await _channel
        .invokeMethod<Map<Object?, Object?>>('start', {
          'mode': ?mode?.name,
          'strings': <String, String>{
            'tracking': tr(l, 'bozor.pano.cap.tracking'),
            'moved': tr(l, 'bozor.pano.cap.moved'),
            'ar_error': tr(l, 'bozor.pano.cap.ar_error'),
            'skip_poles': tr(l, 'bozor.pano.cap.skip_poles'),
            'finish': tr(l, 'bozor.pano.cap.finish'),
            'finish_title': tr(l, 'bozor.pano.cap.finish_title'),
            'finish_body': tr(l, 'bozor.pano.cap.finish_body'),
            'finish_yes': tr(l, 'bozor.pano.cap.finish_yes'),
            'finish_no': tr(l, 'bozor.pano.cap.finish_no'),
            'hint': tr(l, 'bozor.pano.cap.hint'),
            // Joy qulfi (Uy360 UI): qaytish ko'rsatmasi va pufakcha yorliqlari.
            'return_to': tr(l, 'bozor.pano.cap.return_to'),
            'dir_right': tr(l, 'bozor.pano.cap.dir_right'),
            'dir_left': tr(l, 'bozor.pano.cap.dir_left'),
            'dir_forward': tr(l, 'bozor.pano.cap.dir_forward'),
            'dir_back': tr(l, 'bozor.pano.cap.dir_back'),
            'dir_up': tr(l, 'bozor.pano.cap.dir_up'),
            'dir_down': tr(l, 'bozor.pano.cap.dir_down'),
            'in_place': tr(l, 'bozor.pano.cap.in_place'),
            'off_place': tr(l, 'bozor.pano.cap.off_place'),
            'early_finish': tr(l, 'bozor.pano.cap.early_finish'),
            'uw_hint': tr(l, 'bozor.pano.cap.uw_hint'),
            'uw_level': tr(l, 'bozor.pano.cap.uw_level'),
            'uw_retry': tr(l, 'bozor.pano.cap.uw_retry'),
            for (final key in [
              'permission',
              'unavailable',
              'interrupted',
              'camera',
              'motion',
              'storage',
              'photo',
              'busy',
            ])
              'err_$key': tr(l, 'bozor.pano.cap.err_$key'),
            'close': tr(l, 'common.close'),
          },
        })
        .catchError((Object error) {
          if (error is PlatformException) {
            final key = _captureErrorKey(error.code);
            if (key != null) {
              throw PlatformException(
                code: error.code,
                message: tr(l, key),
                details: error.details,
              );
            }
          }
          throw error;
        });
    if (raw == null) return null;
    return PanoCaptureResult(
      dir: (raw['dir'] ?? '').toString(),
      frames: (raw['frames'] as num?)?.toInt() ?? 0,
    );
  }

  static String? _captureErrorKey(String code) => switch (code) {
    'CAMERA_PERMISSION' => 'bozor.pano.cap.err_permission',
    'UNSUPPORTED' ||
    'UNSUPPORTED_IOS' ||
    'NO_ULTRAWIDE_CAMERA' ||
    'NO_CAPTURE_MODE' => 'bozor.pano.cap.err_unavailable',
    'CAPTURE_INTERRUPTED' ||
    'CAMERA_INTERRUPTED' => 'bozor.pano.cap.err_interrupted',
    'CAMERA_FAILED' => 'bozor.pano.cap.err_camera',
    'NO_DEVICE_MOTION' ||
    'MOTION_FAILED' ||
    'MOTION_UNAVAILABLE' => 'bozor.pano.cap.err_motion',
    'IO' || 'CAPTURE_IO' => 'bozor.pano.cap.err_storage',
    'CAPTURE_FAILED' => 'bozor.pano.cap.err_photo',
    'BUSY' => 'bozor.pano.cap.err_busy',
    _ => null,
  };

  // ── Nativ tur va natija ko'rish (`PanoTour.swift`) ───────────────────────

  /// Matnlar nativ tur/ko'rish ekranlari uchun — Swift'da i18n yo'q.
  static Map<String, String> _tourStrings(Locale l) => <String, String>{
    'room': tr(l, 'bozor.pano.tour.room'),
    'room_n': tr(l, 'bozor.pano.tour.room_n'),
    'rooms': tr(l, 'bozor.pano.tour.rooms'),
    'hotspot_title': tr(l, 'bozor.pano.tour.hotspot_title'),
    'move': tr(l, 'bozor.pano.tour.move'),
    'move_here': tr(l, 'bozor.pano.tour.move_here'),
    'remove': tr(l, 'bozor.pano.tour.remove'),
    'edit_place': tr(l, 'bozor.pano.tour.edit_place'),
    'edit_existing': tr(l, 'bozor.pano.tour.edit_existing'),
    'no_links': tr(l, 'bozor.pano.tour.no_links'),
    'pick_title': tr(l, 'bozor.pano.tour.pick_title'),
    'new_room': tr(l, 'bozor.pano.tour.new_room'),
    'linked': tr(l, 'bozor.pano.tour.linked'),
    'need_two': tr(l, 'bozor.pano.tour.need_two'),
    'limit': tr(l, 'bozor.pano.tour.limit'),
    'too_close': tr(l, 'bozor.pano.tour.too_close'),
    'view_hint': tr(l, 'bozor.pano.view.hint'),
    'err': tr(l, 'bozor.pano.view.err'),
    'err_network': tr(l, 'bozor.pano.view.err_network'),
    'err_missing': tr(l, 'bozor.pano.view.err_missing'),
    'err_decode': tr(l, 'bozor.pano.view.err_decode'),
    'retry': tr(l, 'common.retry'),
    'cancel': tr(l, 'common.cancel'),
    'close': tr(l, 'common.close'),
    'preview_title': tr(l, 'bozor.pano.preview.title'),
    'accept': tr(l, 'bozor.pano.preview.accept'),
    'retake': tr(l, 'bozor.pano.preview.retake'),
  };

  /// Tikilgan panoramani sferada ko'rsatadi. `accept` — yuklashga o'tiladi,
  /// `retake` — kadrlar tashlanib capture qaytadan ochiladi.
  static Future<PanoPreviewAction> preview(
    BuildContext context, {
    required String path,
  }) async {
    final l = Localizations.localeOf(context);
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('preview', {
      'path': path,
      'strings': _tourStrings(l),
    });
    return raw?['action'] == 'retake'
        ? PanoPreviewAction.retake
        : PanoPreviewAction.accept;
  }

  /// Nativ tur: xonalar bo'ylab yurish va (tahrirda) tugmalarni qo'yish.
  ///
  /// Qaytganda havolalarning TO'LIQ ro'yxati (`from`/`to` = [PanoTourRoom.key],
  /// `yawDeg` 0..360, `pitchDeg` −90..90 — Dart/backend konvensiyasi) va
  /// ixtiyoriy amal: foydalanuvchi turdan «Yangi xona — hozir tushirish»ni
  /// tanlagan bo'lsa [PanoTourResult.newRoom] — chaqiruvchi capture oqimini
  /// yuritib, havolani qo'shib, turni qayta ochadi. Bekor qilinsa `null`
  /// emas — tur har doim havolalar bilan qaytadi.
  static Future<PanoTourResult?> tour(
    BuildContext context, {
    required List<PanoTourRoom> panoramas,
    required List<Map<String, Object?>> links,
    required String startKey,
    required bool editable,
  }) async {
    final l = Localizations.localeOf(context);
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('tour', {
      'panoramas': [for (final r in panoramas) r.toChannel()],
      'links': links,
      'startKey': startKey,
      'editable': editable,
      'strings': _tourStrings(l),
    });
    if (raw == null) return null;
    return PanoTourResult.fromChannel(raw);
  }

  // ── Tikish ──────────────────────────────────────────────────────────────

  /// Tikish paytida nativ tarafdan keladigan `progress {p, msg}` ni oladigan
  /// tinglovchi. Bittasi bo'ladi — nativ taraf ham bir vaqtda bitta tikishga
  /// ruxsat beradi (`BUSY`).
  static void Function(double p, String msg)? _progressListener;
  static bool _handlerInstalled = false;

  static void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'progress') {
        final a = call.arguments as Map<Object?, Object?>?;
        _progressListener?.call(
          (a?['p'] as num?)?.toDouble() ?? 0,
          (a?['msg'] ?? '').toString(),
        );
      }
      return null;
    });
  }

  /// [dir] dagi kadrlarni (`frame_N.jpg` + `meta.json`) shu qurilmada tikadi;
  /// `pano.jpg` va `preview.jpg` o'sha katalogga yoziladi.
  ///
  /// Legacy ARKit [mode]: `auto` (RAM ≥ 5.5 GB → `mvs`, otherwise `fast`),
  /// `mvs`, or `fast`. CoreMotion metadata selects high-quality sensor BA/MVS
  /// with evidence-based rotation fallback, regardless of [mode].
  /// Omit [width] to use native metadata defaults: ARKit 4096, CoreMotion 6144.
  /// Explicit widths override either default; output height is half the width.
  /// [logoAsset] — nadir'ga bosiladigan brend diski (Flutter asset kaliti).
  ///
  /// [onProgress] asosiy oqimda, 0..1 + yadroning qisqa xabari (inglizcha,
  /// tashxis uchun — foydalanuvchiga ko'rsatilmaydi).
  ///
  /// Xato — `PlatformException` (`NO_FRAMES`, `STITCH_FAILED`, `BUSY`).
  static Future<PanoStitchResult> stitch({
    required String dir,
    int? width,
    String mode = 'auto',
    String? logoAsset,
    void Function(double p, String msg)? onProgress,
  }) async {
    _installHandler();
    _progressListener = onProgress;
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('stitch', {
        'dir': dir,
        'width': ?width,
        'mode': mode,
        'logoAsset': ?logoAsset,
      });
      if (raw == null) {
        throw PlatformException(code: 'STITCH_FAILED', message: 'bo\'sh javob');
      }
      final r = PanoStitchResult.fromChannel(raw);
      if (r.panoPath.isEmpty) {
        throw PlatformException(
          code: 'STITCH_FAILED',
          message: 'pano yo\'li yo\'q',
        );
      }
      return r;
    } finally {
      _progressListener = null;
    }
  }
}
