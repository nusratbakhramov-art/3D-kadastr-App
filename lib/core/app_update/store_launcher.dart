/// Do'konni ochish — App Store / Play Store.
///
/// Havolaning birinchi manbasi — backenddagi `store_url` (adminka kiritadi).
/// U bo'lmasa qattiq kodlangan zaxira ishlatiladi, chunki "Yangilash" tugmasi
/// hech qachon hech narsa qilmasdan qolmasligi kerak — ayniqsa MAJBURIY
/// yangilanish ekranida, u yerda foydalanuvchining boshqa yo'li yo'q.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/app_banner.dart';
import '../i18n/app_translations.dart';

/// App Store ilova ID'si — `settings_screen.dart` dagi baho so'rash oqimi ham
/// shu ilovani ko'rsatadi.
const String kAppStoreId = '6744487945';

/// Android paket nomi — `android/app/build.gradle.kts` dagi `applicationId`.
const String kAndroidPackage = 'uz.kadastr.kadastr';

String get _fallbackStoreUrl => Platform.isIOS
    ? 'https://apps.apple.com/app/id$kAppStoreId'
    : 'https://play.google.com/store/apps/details?id=$kAndroidPackage';

/// Do'kon sahifasini ochadi. `url` bo'sh bo'lsa platforma zaxirasi ishlatiladi.
/// Ochib bo'lmasa `false` qaytaradi (chaqiruvchi xabar ko'rsatadi) — hech
/// qachon exception otmaydi.
Future<bool> openStore([String? url]) async {
  final target = (url == null || url.trim().isEmpty)
      ? _fallbackStoreUrl
      : url.trim();
  try {
    return await launchUrl(
      Uri.parse(target),
      mode: LaunchMode.externalApplication,
    );
  } catch (e) {
    debugPrint('openStore: ochib bo\'lmadi ($target): $e');
    // Backend havolasi buzuq bo'lsa zaxirani bir marta sinaymiz.
    if (target != _fallbackStoreUrl) {
      try {
        return await launchUrl(
          Uri.parse(_fallbackStoreUrl),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {}
    }
    return false;
  }
}

/// Do'konni ochadi, ochilmasa snackbar ko'rsatadi.
///
/// Yangilanish ekrani ham, bildirishnomalar ro'yxatidagi `app_update` xabari
/// ham SHU yo'ldan yuradi: push'ni bosganda do'kon ochilib, ro'yxatdagi o'sha
/// xabar boshi berk ko'cha bo'lib qolgani — takrorlangan mantiq emas, YO'Q
/// bo'lgan mantiq edi.
Future<void> openStoreOrWarn(
  BuildContext context,
  String? url,
  Locale locale,
) async {
  final ok = await openStore(url);
  if (ok || !context.mounted) return;
  showAppBanner(context, tr(locale, 'update.open_failed'), isError: true);
}
