/// Yangilanish tekshiruvi — keshli, tezligi cheklangan (throttle).
///
/// Chaqiriladi: sovuq startда bir marta va ilova fondan qaytganда. Resume juda
/// tez-tez bo'ladi (har ekran o'chib-yonganda), shuning uchun [_minInterval]
/// dan tez so'rov YUBORILMAYDI — oxirgi javob keshdan ishlatiladi.
///
/// MUHIM xavfsizlik qoidasi: tarmoq/serverда nima bo'lishidan qat'i nazar
/// ilova ishlashdan TO'XTAMAYDI. Xato, timeout, 500, buzuq JSON — hammasi
/// "yangilanish yo'q" ga tushadi. Bloklovchi ekran faqat backend aniq
/// `required=true` deganда chiqadi (va faqat o'sha javob keshda turganда).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api_config.dart';
import '../app_version.dart';
import 'app_release.dart';

/// Joriy yangilanish holati — [AppUpdateGate] shuni tinglaydi.
final ValueNotifier<AppRelease> appReleaseNotifier = ValueNotifier<AppRelease>(
  AppRelease.none,
);

/// Ilova asosiy ekranga yetdimi. Yangilanish oynasi splash yoki onboarding
/// USTIDA chiqmasligi kerak: foydalanuvchi hali ilovani ko'rmagan bo'lsa,
/// "yangilang" degan oyna kontekstsiz va qo'pol ko'rinadi. `MainShell`
/// ochilganda `true` bo'ladi.
final ValueNotifier<bool> appShellReadyNotifier = ValueNotifier<bool>(false);

class AppUpdateStore {
  AppUpdateStore._();
  static final AppUpdateStore instance = AppUpdateStore._();

  static const String _cacheKey = 'app_release_latest_v1';
  static const String _checkedAtKey = 'app_release_checked_at_v1';
  static const Duration _timeout = Duration(seconds: 10);

  /// Ikki so'rov orasidagi eng kichik oraliq. Fondan qaytish signali juda
  /// tez-tez keladi; reliz esa kuniga bir marta ham chiqmaydi.
  static const Duration _minInterval = Duration(hours: 6);

  DateTime? _lastCheck;

  /// Shu sessiyada "Keyinroq" bosilgan reliz kaliti — qayta ko'rsatmaymiz.
  /// Ataylab DISKDA saqlanmaydi: ilovani qayta ochganда taklif qaytadi,
  /// lekin bir sessiyada takror bezovta qilmaydi.
  String? dismissedKey;

  @visibleForTesting
  void resetForTest() {
    _lastCheck = null;
    dismissedKey = null;
    appReleaseNotifier.value = AppRelease.none;
  }

  /// Joriy qurilma platformasi — backend `platform` parametri.
  static String get platform => Platform.isIOS ? 'ios' : 'android';

  /// Sovuq start: keshni darhol o'qib, so'ng backendni so'raydi.
  ///
  /// Sovuq start throttle'ga BO'YSUNMAYDI (`force: true`). Throttle prefs'da
  /// saqlanadi, shuning uchun bo'ysunganда ilova qayta ochilsa ham 6 soat
  /// davomida eski javob ko'rsatilaverardi — admin relizni MAJBURIY qilsa ham
  /// foydalanuvchi buni yarim kun ko'rmasdi. Ilova ishga tushishi kamdan-kam
  /// bo'ladi; bitta so'rov arzon. Throttle fondan qaytish uchun — u juda
  /// tez-tez sodir bo'ladi.
  Future<void> loadCachedThenRefresh({
    http.Client? client,
    String lang = 'uz',
  }) async {
    await _loadCache(lang);
    await refresh(client: client, lang: lang, force: true);
  }

  Future<void> _loadCache(String lang) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      final at = prefs.getInt(_checkedAtKey);
      if (at != null) {
        _lastCheck = DateTime.fromMillisecondsSinceEpoch(at);
      }
      if (raw == null || raw.isEmpty) return;
      final cached = AppRelease.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      // Til almashган bo'lsa keshdagi matnlar boshqa tilda — ko'rsatmaymiz,
      // yangi so'rov to'g'ri tilda oladi.
      if (cached.lang != lang) {
        _lastCheck = null; // til o'zgarishi throttle'ni bekor qiladi
        return;
      }
      appReleaseNotifier.value = cached;
    } catch (_) {
      // Buzuq kesh — "yangilanish yo'q" holatida qolamiz.
    }
  }

  /// Backenddan so'raydi. [force] — throttle'ni chetlab o'tadi (fondan
  /// qaytishda emas, faqat qo'lda "qayta urinish" uchun).
  Future<void> refresh({
    http.Client? client,
    String lang = 'uz',
    bool force = false,
  }) async {
    if (!force && !_shouldCheck()) return;

    final c = client ?? http.Client();
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/releases/latest').replace(
        queryParameters: {
          'platform': platform,
          'current_version': kAppVersion,
          'build_number': kAppBuild,
          'lang': lang,
        },
      );
      final response = await c
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(_timeout);
      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return;
      final release = AppRelease.fromJson(decoded);

      appReleaseNotifier.value = release;
      _lastCheck = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(release.toJson()));
      await prefs.setInt(_checkedAtKey, _lastCheck!.millisecondsSinceEpoch);
    } catch (_) {
      // Tarmoq yo'q / timeout / buzuq javob — ILOVA BEMALOL ISHLAYVERADI.
      // Keshdagi holat o'zgarmaydi: oldin majburiy deb topilgan bo'lsa
      // bloklangan qoladi, aks holda hech narsa ko'rsatilmaydi.
    } finally {
      if (client == null) c.close();
    }
  }

  bool _shouldCheck() {
    final last = _lastCheck;
    if (last == null) return true;
    return DateTime.now().difference(last) >= _minInterval;
  }

  /// Fondan qaytganда chaqiriladi — throttle bilan.
  Future<void> onResumed({String lang = 'uz'}) => refresh(lang: lang);
}
