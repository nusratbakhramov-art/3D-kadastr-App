/// RoomPlan scanner — iOS 16+ Apple RoomPlan API'sini Method Channel orqali
/// chaqirish. Foydalanuvchi tugma bossa native modal RoomCaptureView ochiladi
/// va USDZ fayli + statistika qaytariladi.
///
/// Android'da hozircha qo'llab-quvvatlanmaydi.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
class RoomScanResult {
  const RoomScanResult({
    required this.filePath,
    required this.fileSize,
    required this.walls,
    required this.doors,
    required this.windows,
    required this.openings,
    required this.objects,
    this.floorAreaSqm,
    this.wallsTotal,
    this.wallsTextured,
  });

  final String filePath;
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

  /// Necha devor rasmga olinmadi.
  int? get wallsMissed {
    if (wallsTotal == null || wallsTextured == null) return null;
    return wallsTotal! - wallsTextured!;
  }

  factory RoomScanResult.fromMap(Map<dynamic, dynamic> m) => RoomScanResult(
        filePath: m['filePath'] as String,
        fileSize: (m['fileSize'] as num?)?.toInt() ?? 0,
        walls: (m['walls'] as num?)?.toInt() ?? 0,
        doors: (m['doors'] as num?)?.toInt() ?? 0,
        windows: (m['windows'] as num?)?.toInt() ?? 0,
        openings: (m['openings'] as num?)?.toInt() ?? 0,
        objects: (m['objects'] as num?)?.toInt() ?? 0,
        floorAreaSqm: (m['floorAreaSqm'] as num?)?.toDouble(),
        wallsTotal: (m['wallsTotal'] as num?)?.toInt(),
        wallsTextured: (m['wallsTextured'] as num?)?.toInt(),
      );
}

class RoomPlanScanner {
  const RoomPlanScanner._();

  static const _channel = MethodChannel('kadastr/room_plan_scanner');

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
  }

  /// ARKit + LiDAR mesh + kamera frame'lardan vertex coloring orqali
  /// fotorealistik (rangli) USDZ chiqaradi. RoomPlan'dan farqli, bu real
  /// xona ko'rinishini saqlaydi.
  static Future<RoomScanResult?> startTexturedScan({Locale? locale}) async {
    final l = locale ?? const Locale('uz');
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
  }

  /// Textured RoomPlan (iOS 16+) — RoomPlan strukturasi + ARKit foto
  /// frame'lardan har devorga to'g'ri rasm proyeksiyalanadi (perspektiv warp).
  /// Polycam'dagidek butun xona uchun ishlaydi: clean walls + photo textures.
  /// On-device, server kerak emas.
  static Future<RoomScanResult?> startTexturedRoomPlan({Locale? locale}) async {
    final l = locale ?? const Locale('uz');
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
  }

  /// Apple Object Capture (iOS 17+) — yo'naltirilgan capture, 50-200 foto
  /// avtomatik olinib, PhotogrammetrySession'da fotorealistik USDZ qiladi.
  /// Polycam'ga eng yaqin on-device variant.
  static Future<RoomScanResult?> startObjectCapture({Locale? locale}) async {
    final l = locale ?? const Locale('uz');
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
