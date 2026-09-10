/// RoomPlan scanner — iOS 16+ Apple RoomPlan API'sini Method Channel orqali
/// chaqirish. Foydalanuvchi tugma bossa native modal RoomCaptureView ochiladi
/// va USDZ fayli + statistika qaytariladi.
///
/// Android'da hozircha qo'llab-quvvatlanmaydi.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../panorama/data/camera_guard.dart';

String _pick(
  Locale l, {
  required String uz,
  required String ru,
  required String en,
}) {
  switch (l.languageCode) {
    case 'ru':
      return ru;
    case 'en':
      return en;
    default:
      return uz;
  }
}

class RoomPlanScannerException implements Exception {
  const RoomPlanScannerException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'RoomPlanScannerException($code): $message';
}

/// Hybrid scan natijasi — server processing background'da, mobile faqat
/// `jobId` va `status` oladi. USDZ keyinroq Arizalar ekranida ko'rinadi.
class HybridScanResult {
  const HybridScanResult({required this.jobId, required this.status});

  final int jobId;
  final String status; // pending | processing | completed | failed

  factory HybridScanResult.fromMap(Map<dynamic, dynamic> m) => HybridScanResult(
        jobId: (m['jobId'] as num).toInt(),
        status: m['status'] as String? ?? 'pending',
      );
}

/// Skan natijasi — USDZ yo'li va detected obyektlar statistikasi.
/// Phase 7: saved_raw mode'da filePath null, faqat savedScanId.
class RoomScanResult {
  const RoomScanResult({
    this.filePath,
    this.fileSize = 0,
    this.walls = 0,
    this.doors = 0,
    this.windows = 0,
    this.openings = 0,
    this.objects = 0,
    this.floorAreaSqm,
    this.wallsTotal,
    this.wallsTextured,
    this.savedScanId,
    this.mode,
  });

  final String? filePath;
  final int fileSize;
  final int walls;
  final int doors;
  final int windows;
  final int openings;
  final int objects;
  final double? floorAreaSqm;

  /// Textured RoomPlan natijasi: jami devor soni va teksturalangan miqdor.
  /// Boshqa skan turlarida (oddiy RoomPlan) null.
  final int? wallsTotal;
  final int? wallsTextured;

  /// Phase 7: saved_raw mode'da scanId. Profilda ko'rsatish + qayta ishlash uchun.
  final int? savedScanId;
  /// "saved_raw" | "offline_processed" | null (legacy USDZ)
  final String? mode;

  bool get isSavedRaw => mode == 'saved_raw';

  /// Necha devor rasmga olinmadi.
  int? get wallsMissed {
    if (wallsTotal == null || wallsTextured == null) return null;
    return wallsTotal! - wallsTextured!;
  }

  factory RoomScanResult.fromMap(Map<dynamic, dynamic> m) => RoomScanResult(
        filePath: m['filePath'] as String?,
        fileSize: (m['fileSize'] as num?)?.toInt() ?? 0,
        walls: (m['walls'] as num?)?.toInt() ?? 0,
        doors: (m['doors'] as num?)?.toInt() ?? 0,
        windows: (m['windows'] as num?)?.toInt() ?? 0,
        openings: (m['openings'] as num?)?.toInt() ?? 0,
        objects: (m['objects'] as num?)?.toInt() ?? 0,
        floorAreaSqm: (m['floorAreaSqm'] as num?)?.toDouble(),
        wallsTotal: (m['wallsTotal'] as num?)?.toInt(),
        wallsTextured: (m['wallsTextured'] as num?)?.toInt(),
        savedScanId: (m['savedScanId'] as num?)?.toInt(),
        mode: m['mode'] as String?,
      );
}

class RoomPlanScanner {
  const RoomPlanScanner._();

  static const _channel = MethodChannel('kadastr/room_plan_scanner');

  /// Kamera band bo'lganda chiqadigan xato kodi — chaqiruvchilar buni boshqa
  /// nosozliklardan ajratib, foydalanuvchiga «avval joriy skanni yoping» deb
  /// ayta oladi.
  static const String busyCode = 'CAMERA_BUSY';

  /// LiDAR yo'lini [CameraGuard] ostiga oladi.
  ///
  /// NEGA. Bu kanal PCScanKit ning `ARSession` ini ochadi, ya'ni kameraning
  /// uchinchi mustaqil egasi. 360° panorama (`camera` plagini) yoki AI
  /// Baholash videosi (`kadastr/video_capture`) bilan bir vaqtda ochilsa
  /// iOS'da sessiya `AVCaptureSessionWasInterrupted` bilan qotadi, Android'da
  /// esa `CameraAccessException` chiqadi. Guard ikkinchi ochilishni kamera
  /// qatlamiga YETIB BORMASDAN to'xtatadi.
  ///
  /// [CameraBusyException] ATAYLAB [RoomPlanScannerException] ga
  /// aylantiriladi: uchala chaqiruvchi ekran (`ai_scan_intro_screen`,
  /// `ai_scan_screen`, `scan_lidar_screen`) faqat shu turni ushlaydi va
  /// boshqa istisno ularning `_busy`/`_scanning` bayrog'ini tozalanmagan
  /// holda qoldirib ketardi — ya'ni ekran qotib qolardi.
  ///
  /// Guard bo'sh bo'lganda bu funksiya hech nimani o'zgartirmaydi: [action]
  /// aynan avvalgidek chaqiriladi va natijasi/istisnosi o'zgarmasdan o'tadi.
  ///
  /// [timeout] BERILMAYDI — skan qancha davom etishini foydalanuvchi hal
  /// qiladi. «Hech qachon qaytmaydi» holati uchun `CameraGuard.leaseTimeout`
  /// javob beradi.
  static Future<T> _guarded<T>(Locale l, Future<T> Function() action) async {
    try {
      return await CameraGuard.run(CameraGuard.lidar, action);
    } on CameraBusyException catch (e) {
      throw RoomPlanScannerException(
        busyCode,
        _pick(
          l,
          uz: 'Kamera hozir band (${e.holder}) — avval uni yoping',
          ru: 'Камера сейчас занята (${e.holder}) — сначала закройте её',
          en: 'Camera is busy (${e.holder}) — close it first',
        ),
      );
    }
  }

  /// Qurilma RoomPlan'ni qo'llay oladimi tekshirish.
  /// iOS 16+ Pro qurilmalar (LiDAR) → true.
  static Future<bool> isSupported() async {
    try {
      final result = await _channel.invokeMethod<bool>('isSupported');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Native modal scanner ekranini ochadi. Foydalanuvchi "Tugatish" bossa,
  /// USDZ fayli generatsiya qilinadi va natija qaytariladi.
  /// "Bekor qilish" bosilsa `null` qaytadi.
  static Future<RoomScanResult?> startScan({Locale? locale}) async {
    final l = locale ?? const Locale('uz');
    return _guarded<RoomScanResult?>(l, () async {
      try {
        final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'startScan',
        );
        if (raw == null) return null; // cancelled
        return RoomScanResult.fromMap(raw);
      } on PlatformException catch (e) {
        throw RoomPlanScannerException(
          e.code,
          e.message ??
              _pick(
                l,
                uz: 'Skan muvaffaqiyatsiz',
                ru: 'Сканирование не удалось',
                en: 'Scan failed',
              ),
        );
      }
    });
  }

  /// ARKit + LiDAR mesh + kamera frame'lardan vertex coloring orqali
  /// fotorealistik (rangli) USDZ chiqaradi. RoomPlan'dan farqli, bu real
  /// xona ko'rinishini saqlaydi.
  static Future<RoomScanResult?> startTexturedScan({Locale? locale}) async {
    final l = locale ?? const Locale('uz');
    return _guarded<RoomScanResult?>(l, () async {
      try {
        final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'startTexturedScan',
        );
        if (raw == null) return null;
        return RoomScanResult.fromMap(raw);
      } on PlatformException catch (e) {
        throw RoomPlanScannerException(
          e.code,
          e.message ??
              _pick(
                l,
                uz: 'Rangli skan muvaffaqiyatsiz',
                ru: 'Текстурированное сканирование не удалось',
                en: 'Textured scan failed',
              ),
        );
      }
    });
  }

  /// Textured RoomPlan (iOS 16+) — RoomPlan strukturasi + ARKit foto
  /// frame'lardan har devorga to'g'ri rasm proyeksiyalanadi (perspektiv warp).
  /// Polycam'dagidek butun xona uchun ishlaydi: clean walls + photo textures.
  /// On-device, server kerak emas.
  static Future<RoomScanResult?> startTexturedRoomPlan({Locale? locale}) async {
    final l = locale ?? const Locale('uz');
    return _guarded<RoomScanResult?>(l, () async {
      try {
        final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'startTexturedRoomPlan',
        );
        if (raw == null) return null;
        return RoomScanResult.fromMap(raw);
      } on PlatformException catch (e) {
        throw RoomPlanScannerException(
          e.code,
          e.message ??
              _pick(
                l,
                uz: 'Textured RoomPlan muvaffaqiyatsiz',
                ru: 'Textured RoomPlan не удалось',
                en: 'Textured RoomPlan failed',
              ),
        );
      }
    });
  }

  /// Apple Object Capture (iOS 17+) — yo'naltirilgan capture, 50-200 foto
  /// avtomatik olinib, PhotogrammetrySession'da fotorealistik USDZ qiladi.
  /// Polycam'ga eng yaqin on-device variant.
  static Future<RoomScanResult?> startObjectCapture({Locale? locale}) async {
    final l = locale ?? const Locale('uz');
    return _guarded<RoomScanResult?>(l, () async {
      try {
        final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'startObjectCapture',
        );
        if (raw == null) return null;
        return RoomScanResult.fromMap(raw);
      } on PlatformException catch (e) {
        throw RoomPlanScannerException(
          e.code,
          e.message ??
              _pick(
                l,
                uz: 'Object Capture muvaffaqiyatsiz',
                ru: 'Object Capture не удалось',
                en: 'Object Capture failed',
              ),
        );
      }
    });
  }

  /// Hybrid photogrammetry — iPhone capture, server processing.
  ///
  /// Background flow:
  /// 1. Foydalanuvchi xona aylanib chiqadi va foto'lar saqlanadi
  /// 2. Foto'lar serverga upload qilinadi (~30s-2 daq)
  /// 3. Server PENDING job yaratadi va `job_id` qaytaradi
  /// 4. Foydalanuvchi Arizalar ekranida 3D tayyor bo'lishini kuzatadi
  ///
  /// `provider`:
  /// - `polycam` — Polycam web UI (default, max 300 foto, $16/oy)
  /// - `aws_gpu` — kadastr AWS GPU pipeline (fallback, limitsiz foto)
  /// - `kiri_engine` — Kiri Engine cloud ($1/scan)
  /// - `local_mac` — bizning Mac PhotogrammetrySession (bepul, dev)
  ///
  /// `algorithm` (faqat kiri uchun):
  /// - `3dgs` — Gaussian Splatting, eng yaxshi sifat (default)
  /// - `photo` — standart photogrammetry, oddiy obyektlar
  /// - `featureless` — NeRF, yorqin/shaffof obyektlar
  ///
  /// Qaytaradi: `HybridScanResult` (jobId + status). Foydalanuvchi bekor
  /// qilsa null.
  static Future<HybridScanResult?> startHybridScan({
    required String baseUrl,
    required String token,
    String provider = 'polycam',
    String algorithm = '3dgs',
    String quality = 'balanced', // 'draft' | 'balanced' | 'max' — aws_gpu uchun
    Locale? locale,
  }) async {
    final l = locale ?? const Locale('uz');
    return _guarded<HybridScanResult?>(l, () async {
      try {
        final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'startHybridScan',
          {
            'baseUrl': baseUrl,
            'token': token,
            'provider': provider,
            'algorithm': algorithm,
            'quality': quality,
          },
        );
        if (raw == null) return null;
        return HybridScanResult.fromMap(raw);
      } on PlatformException catch (e) {
        throw RoomPlanScannerException(
          e.code,
          e.message ??
              _pick(
                l,
                uz: 'Hybrid skan muvaffaqiyatsiz',
                ru: 'Гибридное сканирование не удалось',
                en: 'Hybrid scan failed',
              ),
        );
      }
    });
  }

  /// USDZ faylni Apple QuickLook orqali ko'rsatish — rotate/zoom/AR mode
  /// native qo'llab-quvvatlanadi.
  static Future<void> preview(String filePath, {Locale? locale}) async {
    final l = locale ?? const Locale('uz');
    try {
      await _channel.invokeMethod<void>('previewModel', {'filePath': filePath});
    } on PlatformException catch (e) {
      throw RoomPlanScannerException(
        e.code,
        e.message ??
            _pick(
              l,
              uz: 'Ko\'rsatish muvaffaqiyatsiz',
              ru: 'Не удалось показать',
              en: 'Preview failed',
            ),
      );
    }
  }
}
