/// `CameraGuard` — kameraning YAGONA egasi.
///
/// NEGA KERAK. Bu ilovada kamera qurilmasiga uchta mustaqil yo'l bor va ular
/// bir-birini ko'rmaydi:
///
///  1. `panorama` — `camera` plagini (`CameraController` →
///     iOS'da `camera_avfoundation`, Android'da `camera_android_camerax`);
///  2. `video`    — `kadastr/video_capture` kanali
///     (`ios/Runner/VideoCaptureRecorder.swift` ning `AVCaptureSession`i,
///     `android/.../VideoCaptureActivity.kt` ning alohida Activity'si);
///  3. `lidar`    — `kadastr/room_plan_scanner` kanali, ya'ni PCScanKit ning
///     `ARSession`i.
///
/// Ikkitasi bir vaqtda kamerani ochsa iOS'da sessiya
/// `AVCaptureSessionWasInterrupted` bilan qotadi (ba'zan butun ilova
/// yiqiladi), Android'da esa `CameraAccessException` yoki jim qora ekran
/// chiqadi. Guard shu ikkinchi ochilishni kamera qatlamiga YETIB BORMASDAN
/// to'xtatadi — ya'ni bu jimgina yiqilishni ko'rinadigan, qaytariladigan
/// xatoga ([CameraBusyException]) aylantiradi.
///
/// ⚠️ ENG XAVFLI JOY — XATO YO'LI. Guard'ning o'zi kamerani ochmaydi; u faqat
/// bitta o'zgaruvchini ([_holder]) band qiladi. Agar native chaqiruv crash
/// bilan tugasa yoki umuman qaytmasa, o'sha o'zgaruvchi ABADIY band qolib
/// ketadi va kamera butun sessiya davomida ishlamay qoladi — ya'ni guard
/// himoya qiladigan nosozlikdan ham yomonroq holat yuzaga keladi. Shuning
/// uchun ijara UCH mustaqil yo'l bilan bo'shatiladi va ularning har biri
/// yolg'iz o'zi yetarli:
///
///  1. **`finally`** — [run] har doim `try/finally` ichida chaqiradi, ya'ni
///     istisno tashlansa ham (`PlatformException`, `MissingPluginException`,
///     `TimeoutException`, hatto `Error`) ijara bo'shaydi. Bu asosiy yo'l.
///  2. **Ijara muddati** ([leaseTimeout]) — native chaqiruv umuman
///     qaytmasa `finally` ham ishlamaydi. Shu sababli [holder] o'qilganda
///     muddati o'tgan ijara avtomatik bekor qilinadi. Bu «hech qachon
///     qaytmaydi» holatining yagona yopig'i.
///  3. **Lifecycle reset** ([handleLifecycle]) — ilova fonga tushib qaytsa,
///     fonga tushishdan oldin olingan ijara bekor qilinadi: OS native kamera
///     ekranini o'zi yopgan bo'lishi mumkin va bizning Dart tomonimiz bu
///     haqda hech qachon xabar olmaydi.
///
/// Uchalasining ham NARXI bor — ijara vaqtidan oldin bo'shashi mumkin (masalan
/// Android'da tizim kamerasi ilovani `paused` holatiga tushiradi, biz esa
/// `resumed` da ijarani bekor qilamiz). Bu ATAYLAB qabul qilingan: erta
/// bo'shagan ijara eng yomon holatda bitta ziddiyat beradi va foydalanuvchi
/// qayta urinib ko'ra oladi, qotib qolgan ijara esa hech qanday yo'l bilan
/// tuzalmaydi.
///
/// MAVJUD XATTI-HARAKAT BUZILMAYDI: guard bo'sh bo'lganda [run] chaqiruvni
/// aynan avvalgidek uzatadi va natijani/istisnoni o'zgartirmasdan qaytaradi.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Kamera boshqa egasi qo'lida bo'lganda tashlanadi.
///
/// Bu YIQILISH EMAS — chaqiruvchi buni ushlab foydalanuvchiga «avval joriy
/// skanni yoping» deb ayta oladi.
class CameraBusyException implements Exception {
  const CameraBusyException(this.requested, this.holder);

  /// Kamerani so'ragan ega.
  final String requested;

  /// Hozir kamerani ushlab turgan ega.
  final String holder;

  @override
  String toString() =>
      'CameraBusyException: "$requested" kamerani so\'radi, lekin u '
      '"$holder" qo\'lida';
}

class CameraGuard {
  const CameraGuard._();

  // ── Egalar ────────────────────────────────────────────────────────────────
  /// 360° panorama capture — `camera` plagini.
  static const String panorama = 'panorama';

  /// AI Baholash video yozuvi — `kadastr/video_capture` kanali.
  static const String video = 'video';

  /// PCScanKit / RoomPlan `ARSession` — `kadastr/room_plan_scanner` kanali.
  static const String lidar = 'lidar';

  static const Set<String> owners = <String>{panorama, video, lidar};

  /// Ijaraning eng uzun muddati. Undan uzoq turgan ijara «o'lgan» deb
  /// hisoblanadi va o'z-o'zidan bekor qilinadi.
  ///
  /// 15 daqiqa ATAYLAB katta: eng uzun haqiqiy sessiya (RoomPlan skani yoki
  /// tizim kamerasida uzun video) bundan qisqa, ya'ni tirik ijara xato bilan
  /// bekor qilinmaydi. Bu chegara «hech qachon qaytmadi» holati uchun, oddiy
  /// «sekin ishladi» uchun emas.
  static const Duration defaultLeaseTimeout = Duration(minutes: 15);

  static Duration leaseTimeout = defaultLeaseTimeout;

  /// Testda vaqtni oldinga surish uchun. Ishlab chiqarishda [DateTime.now].
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  static String? _holder;
  static DateTime? _takenAt;

  /// Ijara olingandan keyin ilova fonga tushdimi. [handleLifecycle] shuni
  /// o'qiydi — «fonga umuman tushmagan» ijarani bekor qilishning ma'nosi yo'q.
  static bool _wentBackground = false;

  static bool _watcherInstalled = false;
  static final WidgetsBindingObserver _watcher = _CameraGuardObserver();

  /// Oxirgi hodisalar — probe ekrani (va `flutter logs`) shuni ko'rsatadi.
  static final List<String> _log = <String>[];
  static const int _logLimit = 60;

  /// Hozirgi ega, yoki kamera bo'sh bo'lsa `null`.
  ///
  /// ⚠️ Bu **sof getter emas**: muddati o'tgan ijarani shu yerda bekor qiladi.
  /// Ataylab shunday — guard holati faqat o'qilganda tekshiriladi, ya'ni fon
  /// taymeri yoki `Timer` kerak emas (ular o'zlari sizib ketish manbai).
  static String? get holder {
    final current = _holder;
    if (current == null) return null;
    final taken = _takenAt;
    if (taken != null && clock().difference(taken) >= leaseTimeout) {
      _clear('EXPIRE $current (ijara muddati o\'tdi)');
      return null;
    }
    return current;
  }

  static bool get isFree => holder == null;

  /// Joriy ijara qancha vaqtdan beri ushlab turilgan. Bo'sh bo'lsa `null`.
  static Duration? get heldFor {
    final taken = _takenAt;
    if (_holder == null || taken == null) return null;
    return clock().difference(taken);
  }

  static List<String> get log => List<String>.unmodifiable(_log);

  /// Kamerani [owner] nomiga band qiladi. Band bo'lsa `false` — YIQILMAYDI.
  ///
  /// Bir egaga IKKI marta berilmaydi: takroriy `acquire` ham `false` qaytaradi.
  /// Sabab — bitta feature ichidagi ikkita parallel chaqiruv ham xuddi ikki
  /// xil feature'niki kabi ikkita kamera sessiyasi ochadi, ya'ni himoya
  /// qilinayotgan nosozlikning aynan o'zi.
  static bool acquire(String owner) {
    assert(owners.contains(owner), 'noma\'lum kamera egasi: $owner');
    _installLifecycleWatcher();
    final busy = holder; // muddati o'tgan ijara shu yerda tozalanadi
    if (busy != null) {
      _note('DENY   $owner (band: $busy)');
      return false;
    }
    _holder = owner;
    _takenAt = clock();
    _wentBackground = false;
    _note('TAKE   $owner');
    return true;
  }

  /// Ijarani bo'shatadi. FAQAT ijara egasi bo'shata oladi.
  ///
  /// Egasi bo'lmagan chaqiruv jimgina e'tiborsiz qoldiriladi — bu kechikkan
  /// yoki takroriy `release` (masalan lifecycle reset ijarani allaqachon
  /// bekor qilgan, keyin esa native chaqiruv nihoyat qaytgan) yangi egadan
  /// kamerani tortib olmasligi uchun.
  static void release(String owner) {
    final current = _holder;
    if (current == null) return;
    if (current != owner) {
      _note('IGNORE release $owner (ega: $current)');
      return;
    }
    _clear('FREE   $owner');
  }

  /// Ijarani majburan bekor qiladi. Oxirgi chora — testlar va lifecycle uchun.
  static void reset([String reason = 'reset']) {
    if (_holder != null) _clear('RESET  $_holder ($reason)');
    _wentBackground = false;
  }

  /// [acquire] + `try/finally` + ixtiyoriy [timeout] — chaqiruvni o'rashning
  /// yagona to'g'ri yo'li.
  ///
  /// Band bo'lsa [CameraBusyException] tashlaydi va [action] UMUMAN
  /// chaqirilmaydi. Bo'sh bo'lsa [action] aynan avvalgidek ishlaydi va uning
  /// natijasi/istisnosi o'zgartirilmasdan uzatiladi.
  ///
  /// [timeout] ODATDA BERILMAYDI: video yozuvi yoki RoomPlan skani qancha
  /// davom etishini biz emas, foydalanuvchi hal qiladi — o'zboshimcha timeout
  /// tirik sessiyani uzib qo'yadi. «Hech qachon qaytmaydi» holati uchun
  /// [leaseTimeout] javob beradi.
  static Future<T> run<T>(
    String owner,
    Future<T> Function() action, {
    Duration? timeout,
  }) async {
    final blocker = holder; // muddati o'tgan ijarani tozalaydi
    if (!acquire(owner)) {
      throw CameraBusyException(owner, blocker ?? 'unknown');
    }
    try {
      final future = action();
      return timeout == null ? await future : await future.timeout(timeout);
    } finally {
      // ⚠️ Guard'ning eng muhim satri. `action` qanday tugashidan qat'i nazar
      // — natija, istisno, `Error`, bekor qilish — ijara shu yerda bo'shaydi.
      release(owner);
    }
  }

  /// Ilova hayot sikli. [_CameraGuardObserver] avtomatik chaqiradi; qo'lda
  /// chaqirish faqat testda kerak.
  static void handleLifecycle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        final current = _holder;
        if (current != null && _wentBackground) {
          // Fonga tushib qaytdik. Native kamera ekrani OS tomonidan yopilgan
          // bo'lishi mumkin va bizning `finally` hech qachon ishlamagan
          // bo'lishi mumkin — shuning uchun ijarani shubhali deb hisoblaymiz.
          _clear('LIFECYCLE $current (fondan qaytishda bo\'shatildi)');
        }
        _wentBackground = false;
      case AppLifecycleState.inactive:
        // ATAYLAB e'tiborsiz: iOS'da har bir tizim modali, Control Center va
        // hatto bildirishnoma pardasi `inactive` beradi. Buni fonga tushish
        // deb hisoblasak har uchinchi ijara sababsiz bekor qilinadi.
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _wentBackground = true;
    }
  }

  static void _clear(String note) {
    _holder = null;
    _takenAt = null;
    _note(note);
  }

  static void _note(String line) {
    _log.add(line);
    if (_log.length > _logLimit) _log.removeAt(0);
    if (kDebugMode) debugPrint('[CameraGuard] $line');
  }

  /// Kuzatuvchi BIR MARTA va faqat kerak bo'lganda o'rnatiladi — shu sababli
  /// `main.dart` ga tegish shart emas va guard ishlatilmagan sessiyada hech
  /// narsa qo'shilmaydi.
  static void _installLifecycleWatcher() {
    if (_watcherInstalled) return;
    try {
      WidgetsBinding.instance.addObserver(_watcher);
      _watcherInstalled = true;
    } catch (_) {
      // Binding hali tayyor emas (sof `dart test`, `main()` dan oldin). Guard
      // busiz ham ishlaydi — `finally` va [leaseTimeout] joyida qoladi.
    }
  }
}

class _CameraGuardObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      CameraGuard.handleLifecycle(state);
}
