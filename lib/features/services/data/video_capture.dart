/// Debug-only video capture — `kadastr/video_capture` native kanali.
///
/// Ikki yo'l bor:
/// - [VideoCapture.record] — o'z recorder'imiz: eng past zoom (0.5x/0.6x —
///   qurilmada nima bo'lsa) va qurilma qo'llaydigan eng yuqori sifat (4K
///   gacha) + stabilizatsiya. Lens va sifatni DASTURIY boshqaramiz.
///   iOS: `ios/Runner/VideoCaptureRecorder.swift` (AVFoundation).
///   Android: `android/.../VideoCaptureActivity.kt` (CameraX).
/// - [VideoCapture.recordSystem] — qurilmaning O'Z kamera ilovasi: OEM ishlov
///   berish quvuri, eng yuqori sifat, lekin zoom/sifatni boshqarib bo'lmaydi.
///   Android: `ACTION_VIDEO_CAPTURE` intent.
///   iOS: Camera.app'ni ochib faylni qaytarib olish API'si YO'Q — shu sababli
///   galereyadan import qilinadi (PHPicker originalni transkodsiz beradi).
///
/// Odatda [VideoCapture.capture] chaqiriladi — u platformaga qarab
/// yuqoridagi ikkitasidan mosini tanlaydi. AI Baholashning 1-qadami
/// (`ai_start_screen.dart`) shuni ishlatadi.
///
/// Uchala ommaviy yo'l ham [CameraGuard] ning `video` egaligi ostida ishlaydi:
/// kamera boshqa egada (`panorama` yoki `lidar`) bo'lsa chaqiruv native
/// qatlamga umuman yetib bormaydi va [CameraBusyException] tashlanadi. Guard
/// bo'sh bo'lganda esa hech nima o'zgarmaydi — natija ham, istisnolar ham
/// avvalgidek.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../panorama/data/camera_guard.dart';

class VideoCaptureException implements Exception {
  const VideoCaptureException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'VideoCaptureException($code): $message';
}

/// Yozib olingan video haqida ma'lumot — fayl temp/cache papkada turadi.
class VideoCaptureResult {
  const VideoCaptureResult({
    required this.path,
    required this.sizeBytes,
    required this.durationMs,
    required this.width,
    required this.height,
    required this.zoom,
    required this.quality,
    required this.lens,
    this.bitrate = 0,
    this.fps = 0,
    this.realFps = 0,
    this.droppedPercent = 0,
    this.endedEarly = false,
    this.endReason = '',
    this.freeSpaceBytes = 0,
  });

  final String path;
  final int sizeBytes;
  final int durationMs;
  final int width;
  final int height;

  /// Haqiqiy qo'llangan zoom: "0.5x" | "0.6x" | "1x", tizim kamerasida
  /// "system" (u yerda zoom'ni foydalanuvchi tanlaydi).
  final String zoom;

  /// "2160p" | "1080p" | "720p" — yozilgan faylning haqiqiy o'lchami.
  final String quality;

  /// Kamera nomi — iOS'da AVCaptureDevice localizedName
  /// ("Back Ultra Wide Camera"), Android'da "Back camera id=2".
  final String lens;

  /// Bit/s. Sifatni raqam bilan solishtirish uchun.
  final int bitrate;

  /// SO'RALGAN kadr tezligi. 3DGS quvuri 60 ni talab qiladi — qurilma
  /// bermasa 30 bo'lib qoladi va shu yerda ko'rinadi.
  final int fps;

  /// FAYLGA TUSHGAN o'rtacha kadr tezligi. [fps] dan sezilarli past bo'lsa
  /// kamera kadr tashlagan (telefon qizigan yoki rejim juda og'ir).
  final double realFps;

  /// [fps] ga nisbatan tashlangan kadrlar foizi. 0 — hammasi yozilgan.
  final int droppedPercent;

  /// Yozuv foydalanuvchi to'xtatmasdan tugadimi (xotira tugadi, telefon
  /// qizidi, ilova fonga o'tdi...). Shunday bo'lsa videoni JIMGINA yuklash
  /// mumkin emas — foydalanuvchidan so'rash kerak.
  final bool endedEarly;

  /// [endedEarly] bo'lsa — sababi, foydalanuvchiga ko'rsatish uchun.
  final String endReason;

  /// Yozuvdan keyin qurilmada qolgan bo'sh joy.
  final int freeSpaceBytes;

  factory VideoCaptureResult.fromMap(Map<dynamic, dynamic> m) =>
      VideoCaptureResult(
        path: m['path'] as String? ?? '',
        sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
        durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
        width: (m['width'] as num?)?.toInt() ?? 0,
        height: (m['height'] as num?)?.toInt() ?? 0,
        zoom: m['zoom'] as String? ?? '',
        quality: m['quality'] as String? ?? '',
        lens: m['lens'] as String? ?? '',
        bitrate: (m['bitrate'] as num?)?.toInt() ?? 0,
        fps: (m['fps'] as num?)?.toInt() ?? 0,
        realFps: (m['realFps'] as num?)?.toDouble() ?? 0,
        droppedPercent: (m['droppedPercent'] as num?)?.toInt() ?? 0,
        endedEarly: m['endedEarly'] as bool? ?? false,
        endReason: m['endReason'] as String? ?? '',
        freeSpaceBytes: (m['freeSpaceBytes'] as num?)?.toInt() ?? 0,
      );

  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
  }

  String get durationLabel {
    final s = (durationMs / 1000).round();
    return '${(s ~/ 60).toString().padLeft(2, '0')}:'
        '${(s % 60).toString().padLeft(2, '0')}';
  }

  String get bitrateLabel => '${(bitrate / 1000000).toStringAsFixed(1)} Mbps';

  /// Kadr tezligi yorlig'i. Kamera so'ralganini bermasa IKKALASI ko'rinadi
  /// ("60→46fps") — aks holda yorliq yolg'on gapirgan bo'ladi.
  String get fpsLabel {
    if (fps <= 0) return '';
    if (droppedPercent >= 5 && realFps > 1) {
      return '@$fps→${realFps.round()}fps';
    }
    return '@${fps}fps';
  }

  /// Toast uchun — noma'lum qiymatlar tushirib qoldiriladi.
  String get summary => [
        if (zoom.isNotEmpty) zoom,
        if (width > 0 && height > 0)
          '${width}x$height$fpsLabel'
        else if (quality.isNotEmpty)
          quality,
        if (durationMs > 0) durationLabel,
        sizeLabel,
        if (bitrate > 0) bitrateLabel,
      ].join(' · ');
}

class VideoCapture {
  const VideoCapture._();

  static const _channel = MethodChannel('kadastr/video_capture');

  /// Qurilmada orqa kamera bormi (iOS simulyatorida — yo'q).
  static Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Platformaga qarab eng yaxshi yo'l:
  /// - Android — qurilmaning o'z kamera ilovasi (OEM ishlov berish quvuri,
  ///   4K/HDR — sifat bo'yicha eng yaxshisi);
  /// - iOS — o'zimizning AVFoundation recorder'i, chunki Camera.app'ni ochib
  ///   faylni qaytarib olish API'si yo'q, galereya importi esa foydalanuvchi
  ///   uchun ikki qadamli qo'l ishi.
  static Future<VideoCaptureResult?> capture() => _guarded(_capture);

  /// O'z recorder'imiz — eng past zoom + eng yuqori sifat, dasturiy nazorat.
  /// Bekor qilinsa `null`.
  static Future<VideoCaptureResult?> record() => _guarded(_record);

  /// Qurilmaning o'z kamera ilovasi (Android) / galereyadan import (iOS).
  /// Zoom va sifat foydalanuvchi qo'lida — lekin OEM sifati eng yuqorisi.
  static Future<VideoCaptureResult?> recordSystem() => _guarded(_recordSystem);

  /// Kamera band bo'lganda chiqadigan xato kodi — `capture` chaqiruvchilari
  /// buni boshqa nosozliklardan ajratib, foydalanuvchiga «avval joriy skanni
  /// yoping» deb ayta oladi.
  static const String busyCode = 'CAMERA_BUSY';

  /// Guard'ni o'rash. [CameraBusyException] ATAYLAB [VideoCaptureException]
  /// ga aylantiriladi: mavjud chaqiruvchilar (`ai_start_screen.dart`) faqat
  /// shu turni ushlaydi va boshqa istisno ularning `_busy` bayrog'ini
  /// tozalanmagan holda qoldirib ketardi — ya'ni ekran qotib qolardi.
  /// Guard bo'sh bo'lganda bu funksiya hech nimani o'zgartirmaydi.
  static Future<VideoCaptureResult?> _guarded(
    Future<VideoCaptureResult?> Function() action,
  ) async {
    try {
      return await CameraGuard.run(CameraGuard.video, action);
    } on CameraBusyException catch (e) {
      throw VideoCaptureException(
        busyCode,
        'Kamera hozir band (${e.holder}) — avval uni yoping',
      );
    }
  }

  // ── Guard'siz ichki yo'llar ───────────────────────────────────────────────
  // [capture] ichkarida [_record]/[_recordSystem] ni chaqiradi. Agar u ommaviy
  // (guard'langan) metodlarni chaqirsa, ijara IKKI marta so'ralgan bo'lardi va
  // guard o'z-o'zini bloklab qo'yardi — `acquire` bir egaga takroran `false`
  // qaytaradi. Shu sababli ichki chaqiruvlar guard'dan o'tmaydi.

  static Future<VideoCaptureResult?> _capture() =>
      defaultTargetPlatform == TargetPlatform.android
          ? _recordSystem()
          : _record();

  static Future<VideoCaptureResult?> _record() => _invoke('record');

  static Future<VideoCaptureResult?> _recordSystem() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _invoke('recordSystem');
    }
    // iOS: Camera.app'ni ochib faylni qaytarib oladigan API mavjud emas —
    // foydalanuvchi o'zi yozib, shu yerdan tanlaydi. PHPicker originalni
    // (4K/HDR, transkodsiz) beradi.
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked == null) return null;
    final file = File(picked.path);
    return VideoCaptureResult(
      path: picked.path,
      sizeBytes: await file.length(),
      durationMs: 0,
      width: 0,
      height: 0,
      zoom: 'system',
      quality: 'original',
      lens: 'Camera app (import)',
    );
  }

  static Future<VideoCaptureResult?> _invoke(String method) async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(method);
      if (raw == null) return null; // bekor qilindi
      return VideoCaptureResult.fromMap(raw);
    } on PlatformException catch (e) {
      throw VideoCaptureException(e.code, e.message ?? 'Video yozib bo\'lmadi');
    } on MissingPluginException {
      // Faqat desktop/web host'da (iOS + Android'da kanal ro'yxatda turadi).
      throw const VideoCaptureException(
        'UNSUPPORTED',
        'Bu platformada video capture yo\'q',
      );
    }
  }
}
