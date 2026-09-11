/// Nativ 360° suratga olish ekrani — platforma kanali.
///
/// Ekranning O'ZI nativ (iOS: ARKit, `ios/Runner/PanoCapture.swift`), chunki
/// har kadr bilan KAMERA POZASI kerak: `transform` (camera→world 4×4) va
/// `intrinsics`. Flutter'ning `camera` paketi ikkalasini ham bermaydi —
/// shuning uchun sensor burchaklariga tayangan eski oqim tikishni ham
/// qurilmada qilishga majbur edi va sifat past chiqardi.
///
/// Nativ taraf faqat KADR YIG'ADI. Tikish serverda ([PanoApi]).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_translations.dart';

/// Nativ ekran qaytargan natija.
@immutable
class PanoCaptureResult {
  const PanoCaptureResult({required this.dir, required this.frames});

  /// Kadrlar va `meta.json` turgan katalog.
  ///
  /// ⚠️ VAQTINCHALIK (`tmp/`). Yuklash tugagach [cleanUp] bilan o'chiriladi —
  /// bitta tushirish ~6 MB, va foydalanuvchi ketma-ket bir necha xona
  /// oladi.
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
      // Tozalash yiqilsa e'lon baribir yuboriladi — OS `tmp` ni o'zi tozalaydi.
    }
  }
}

abstract final class PanoCaptureChannel {
  static const MethodChannel _channel = MethodChannel('kadastr/pano_capture');

  /// Qurilma 360° suratga olishni qo'llaydimi.
  ///
  /// iOS: ARKit dunyo-kuzatuvi (A9+, simulyatorda `false`).
  /// Android: ARCore (Google Play Services for AR) — hamma qurilmada yo'q.
  ///
  /// `false` bo'lsa 360 bo'limi UMUMAN ko'rsatilmaydi (mahsulot qarori):
  /// eski sensorli oqim o'chirilgan va galereyadan yuklash ham olib
  /// tashlangan, ya'ni taklif qiladigan muqobil yo'q.
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

  /// Nativ ekranni ochadi. Foydalanuvchi bekor qilsa `null`.
  ///
  /// Matnlar SHU YERDA tarjima qilinadi va nativ tarafga uzatiladi — Swift va
  /// Kotlin'da i18n takrorlanmasin.
  static Future<PanoCaptureResult?> start(BuildContext context) async {
    final l = Localizations.localeOf(context);
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('start', {
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
      },
    });
    if (raw == null) return null;
    return PanoCaptureResult(
      dir: (raw['dir'] ?? '').toString(),
      frames: (raw['frames'] as num?)?.toInt() ?? 0,
    );
  }
}
