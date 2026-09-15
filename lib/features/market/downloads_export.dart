import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Tugallangan marketplace faylini foydalanuvchi OSON topadigan joyga chiqaradi.
///
/// - **Android:** faylni umumiy `Downloads/3D kadastr` (MediaStore) papkasiga
///   nusxalaydi — Samsung "Fayllar → Yaqinda"/"Yuklamalar"da darhol ko'rinadi.
///   Android 10+ (API 29) uchun ruxsat kerak emas; eski versiyalarda hech narsa
///   qilmaydi (ilova ulashish oynasiga tayanadi).
/// - **iOS:** hech narsa qilmaydi — fayl allaqachon `Documents/Yuklamalar`da,
///   Info.plist (`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`)
///   tufayli Files ilovasida "On My iPhone → 3D kadastr → Yuklamalar" va
///   "Recents"da ko'rinadi.
class DownloadsExport {
  DownloadsExport._();

  static const MethodChannel _ch = MethodChannel('kadastr/downloads');

  /// Hech qachon `throw` qilmaydi — chiqarish ilova asosiy oqimiga xalaqit
  /// bermasin. Muvaffaqiyatda MediaStore `content://` uri qaytaradi (Android),
  /// aks holda `null`.
  static Future<String?> toDownloads({
    required String path,
    required String fileName,
    required String format,
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _ch.invokeMethod<String>('saveToDownloads', {
        'path': path,
        'fileName': fileName,
        'mimeType': _mimeFor(format),
      });
    } catch (_) {
      return null;
    }
  }

  /// Yuklab olingan fayl turgan joyni ochadi.
  ///
  /// - **Android:** tizimning "Downloads" ekranini ochadi (MethodChannel).
  /// - **iOS:** `Files` ilovasini `Yuklamalar` jildida ochadi
  ///   (`shareddocuments://` sxemasi — Info.plist kalitlari tufayli ishlaydi).
  ///
  /// Muvaffaqiyatda `true`. `false` bo'lsa chaqiruvchi zaxira sifatida ulashish
  /// (share) oynasini ko'rsatishi mumkin.
  static Future<bool> openLocation({required String folderPath}) async {
    try {
      if (Platform.isAndroid) {
        return await _ch.invokeMethod<bool>('openDownloads') ?? false;
      }
      if (Platform.isIOS) {
        final uri = Uri.parse('shareddocuments://${Uri.encodeFull(folderPath)}');
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
    return false;
  }

  /// Ko'p CAD formatlarining aniq MIME turi yo'q — `application/octet-stream`
  /// har doim ishlaydi va MediaStore uni Downloads'ga qabul qiladi.
  static String _mimeFor(String format) {
    switch (format.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }
}
