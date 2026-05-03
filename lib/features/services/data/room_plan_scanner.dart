/// RoomPlan scanner — iOS 16+ Apple RoomPlan API'sini Method Channel orqali
/// chaqirish. Foydalanuvchi tugma bossa native modal RoomCaptureView ochiladi
/// va USDZ fayli + statistika qaytariladi.
///
/// Android'da hozircha qo'llab-quvvatlanmaydi.
library;

import 'package:flutter/services.dart';

class RoomPlanScannerException implements Exception {
  const RoomPlanScannerException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'RoomPlanScannerException($code): $message';
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
  });

  final String filePath;
  final int fileSize;
  final int walls;
  final int doors;
  final int windows;
  final int openings;
  final int objects;
  final double? floorAreaSqm;

  factory RoomScanResult.fromMap(Map<dynamic, dynamic> m) => RoomScanResult(
        filePath: m['filePath'] as String,
        fileSize: (m['fileSize'] as num?)?.toInt() ?? 0,
        walls: (m['walls'] as num?)?.toInt() ?? 0,
        doors: (m['doors'] as num?)?.toInt() ?? 0,
        windows: (m['windows'] as num?)?.toInt() ?? 0,
        openings: (m['openings'] as num?)?.toInt() ?? 0,
        objects: (m['objects'] as num?)?.toInt() ?? 0,
        floorAreaSqm: (m['floorAreaSqm'] as num?)?.toDouble(),
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
  static Future<RoomScanResult?> startScan() async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'startScan',
      );
      if (raw == null) return null; // cancelled
      return RoomScanResult.fromMap(raw);
    } on PlatformException catch (e) {
      throw RoomPlanScannerException(e.code, e.message ?? 'Scan failed');
    }
  }

  /// ARKit + LiDAR mesh + kamera frame'lardan vertex coloring orqali
  /// fotorealistik (rangli) USDZ chiqaradi. RoomPlan'dan farqli, bu real
  /// xona ko'rinishini saqlaydi.
  static Future<RoomScanResult?> startTexturedScan() async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'startTexturedScan',
      );
      if (raw == null) return null;
      return RoomScanResult.fromMap(raw);
    } on PlatformException catch (e) {
      throw RoomPlanScannerException(e.code, e.message ?? 'Textured scan failed');
    }
  }

  /// USDZ faylni Apple QuickLook orqali ko'rsatish — rotate/zoom/AR mode
  /// native qo'llab-quvvatlanadi.
  static Future<void> preview(String filePath) async {
    try {
      await _channel.invokeMethod<void>('previewModel', {'filePath': filePath});
    } on PlatformException catch (e) {
      throw RoomPlanScannerException(e.code, e.message ?? 'Preview failed');
    }
  }
}
