/// Qurilma sensorlaridan BARQAROR yo'nalish — yaw/pitch/roll, gradusda.
///
/// ⚠️ `OrientationEvent.yaw` NI TO'G'RIDAN O'QIB BO'LMAYDI. Suratga olish
/// uchun tik ushlangan telefon qurilma pitch'i ~90° da turadi, bu esa
/// yaw/pitch/roll dekompozitsiyasining GIMBAL-LOCK singulyarligi — ya'ni
/// butun capture oqimi ishlatadigan AYNAN o'sha holatda xom yaw keskin
/// sakraydi.
///
/// Yechim — kvaternionni qayta yig'ib, qutbdan CHETDA o'qish:
///
///     q = axisAngle(Z, screenRad) · euler(−rz, −ry, −rx) · axisAngle(X, π/2)
///
/// Oxirgi 90° aylanish o'qishni qutbdan olib chiqadi. Bu `panorama_viewer`
/// bajaradigan kompozitsiyaning aynan o'zi.
///
/// ⚠️ NISBIY (`orientation`) OQIM ishlatiladi, `absoluteOrientation` EMAS.
/// Sabab o'lchangan: magnitometr ichkarida va metall yonida siljiydi, iOS'da
/// esa capture o'rtasida kamera UI ustiga tizimning «sakkiz chizing»
/// kalibrlash oynasini chiqarishi mumkin. Panoramaga faqat FOYDALANUVCHI
/// BOSHLAGAN NUQTAGA nisbatan burchak kerak — tikilgan tasvirning o'z noli
/// baribir ixtiyoriy.
///
/// Plagin manbasida tasdiqlangan: iOS'da nisbiy oqim
/// `xArbitraryCorrectedZVertical` (gyro+akselerometr, magnitometrsiz),
/// Android'da `TYPE_GAME_ROTATION_VECTOR`.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:dchs_motion_sensors/dchs_motion_sensors.dart';
import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart';

/// Sensor burchaklaridan yo'nalish burchaklari — SOF funksiya.
///
/// Ajratilgani sababi: butun matematika shu yerda va u sensor, qurilma,
/// taymer bo'lmasdan tekshiriladi. Barqarorlik hisobi ([HeadingSource]
/// ichida) o'zgaruvchan holatga tayanadi, shuning uchun bu yerga kirmaydi.
///
/// [ex], [ey], [ez] — `OrientationEvent` ning yaw/pitch/roll'i, RADIANDA.
/// [screenRad] — ekran burilishi, radianda.
///
/// ⚠️ O'LCHANGAN: ekran burilishi natijada FAQAT [rollDeg] ga tushadi
/// (0°→0, 90°→90, 180°→180, 270°→−90), yaw va pitch esa TEGILMAYDI. Bu
/// fizik jihatdan to'g'ri — ekranni burish kadrni linza o'qi atrofida
/// aylantiradi, kamera qayerga qaraganini emas. «Ekran burilsa yaw ham
/// o'zgarishi kerak» degan kutish XATO.
({double yawDeg, double pitchDeg, double rollDeg}) aimAngles(
  double ex,
  double ey,
  double ez,
  double screenRad, {
  bool clockwisePositive = true,
}) {
  Quaternion q = Quaternion.axisAngle(Vector3(0, 0, 1), screenRad);
  q *= Quaternion.euler(-ez, -ey, -ex);
  q *= Quaternion.axisAngle(Vector3(1, 0, 0), math.pi * 0.5);

  final Float64List s = q.storage;
  final double x = s[0], y = s[1], z = s[2], w = s[3];

  // Kompozitsiyalangan kvaterniondan uch burchak o'qiladi.
  final double yawRad = math.atan2(
    -2 * (x * z - w * y),
    1.0 - 2 * (x * x + y * y),
  );
  // ⚠️ QISILADI: suzuvchi nuqta xatosi argumentni 1.0000001 qilib qo'yishi
  // mumkin va `asin` NaN qaytaradi — keyin butun capture yo'nalishsiz qoladi.
  final double pitchRad = math.asin((2 * (y * z + w * x)).clamp(-1.0, 1.0));

  // Uchinchi burchak — LINZA O'QI atrofidagi burilish. Aynan shu proyektorga
  // kerak bo'lgan kattalik, xom qurilma roll'i esa NOTO'G'RI: u bu holatda
  // singulyarlikda o'tiradi va ±180 atrofida sakraydi.
  //
  // Haqiqiy capture'da o'lchangan: gorizont qatorida ~+0.8°, +45 qatorida
  // −1.8°, −45 qatorida +2.5°. Kichik, lekin QATOR BO'YICHA TIZIMLI, va
  // 2–3° kadrning yuqori/quyi chetida 6–15 tuval pikseli — aynan shu sababli
  // egilgan qatorlar gorizont halqasiga toza tushmasdi.
  final double lensRollRad = math.atan2(
    -2 * (x * y - w * z),
    1.0 - 2 * (x * x + z * z),
  );

  final double yawDeg = clockwisePositive
      ? yawRad * 180 / math.pi
      : -yawRad * 180 / math.pi;

  return (
    // ⚠️ Normallashtirish `clockwisePositive` shoxidan KEYIN bo'ladi, ya'ni
    // bayroqni almashtirish 30 ↔ 330 beradi, manfiy son EMAS.
    //
    // Tashqi `+ 360) % 360` — ataylab qo'yilgan zaxira. Dart'ning `%` si
    // musbat bo'luvchi uchun allaqachon manfiy bo'lmagan natija beradi, ya'ni
    // u ortiqcha; lekin manbada shunday va «soddalashtirish» xavfi foydasidan
    // katta.
    yawDeg: (yawDeg % 360 + 360) % 360,
    pitchDeg: -pitchRad * 180 / math.pi,
    rollDeg: lensRollRad * 180 / math.pi,
  );
}

class HeadingSource {
  HeadingSource({this.clockwisePositive = true});

  /// Yaw foydalanuvchi O'NGGA burilganda O'SADI.
  ///
  /// ⚠️ Bu bayroq va uning sukuti O'LCHANGAN. Ilgari «xom sensor yaw'i o'ngga
  /// burilganda kamayadi» deb taxmin qilingan va negatsiya qo'yilgan edi.
  /// Taxmin XATO chiqdi, va u hech qachon tekshirilmagandi, chunki tekshirish
  /// uchun qurilma kerakdek tuyulardi. Kerak emas ekan: yaw'lari farq qiladigan
  /// ikki kadr xonaning bir tasmasini bo'lishadi va o'sha tasma har birida
  /// qayerda turgani qaysi biri o'ngroqda olinganini aytadi. Haqiqiy
  /// sessiyaning gorizont qatorida qo'shni yettita juftning HAMMASI keyingi
  /// kadr — ya'ni yuqoriroq yaw — CHAPROQDA ekanini ko'rsatdi.
  ///
  /// Ya'ni negatsiya yaw'ni chapga o'stirayotgan edi va quyi oqimdagi hamma
  /// narsa shuni meros qilib olgandi: yo'riqnoma odamni noto'g'ri tomonga
  /// yuborardi va panorama ko'zguga aylanardi — o'n bir kadrdan o'ntasining
  /// mazmuni teskari yotqizilgandi. Negatsiyani olib tashlash ikkalasini ham
  /// tuzatadi.
  final bool clockwisePositive;

  /// Oxirgi yo'nalish; birinchi sensor namunasigacha `null`.
  final ValueNotifier<DeviceAim?> aim = ValueNotifier<DeviceAim?>(null);

  /// Sensor namunalari widget daraxtiga TEGMASDAN shu yerga tushadi.
  /// 60 Hz da `setState` chaqirish kamera preview'i bilan kadr byudjeti uchun
  /// kurashardi.
  final Vector3 _euler = Vector3(0, math.pi / 2, 0);
  double _screenRad = 0;
  bool _gotSample = false;

  StreamSubscription<OrientationEvent>? _orientation;
  StreamSubscription<ScreenOrientationEvent>? _screen;
  Timer? _pump;

  bool get isRunning => _pump != null;

  int _hz = 30;

  /// Oxirgi ishlatilgan tezlik. `stop()` dan KEYIN ham saqlanadi — ekran
  /// fondan qaytganda `start(hz: source.hz)` bilan o'sha tezlikda tiklash
  /// uchun.
  int get hz => _hz;

  /// Idempotent — ikki marta chaqirish ikkinchi nasos yaratmaydi.
  void start({int hz = 30}) {
    if (isRunning) return;
    _hz = hz;
    _steadiness = Steadiness(_hz);

    // ⚠️ Bu setter MIKROSEKUNDDA, millisekundda ham, gertsda ham EMAS.
    // Bundan tashqari `dchs_motion_sensors 2.0.2` da iOS tomonda sensor turi
    // konstantalari almashib ketgan, ya'ni bu chaqiruv u yerda aslida
    // absolyut ishlovchini sozlaydi. Ikki holatda ham bu faqat TEZLIK
    // MASLAHATI — biz pastda o'z taymerimizda qayta namuna olamiz.
    motionSensors.orientationUpdateInterval =
        Duration.microsecondsPerSecond ~/ 60;

    _orientation = motionSensors.orientation.listen((OrientationEvent e) {
      _euler.setValues(e.yaw, e.pitch, e.roll);
      _gotSample = true;
    });
    _screen = motionSensors.screenOrientation.listen((ScreenOrientationEvent e) {
      _screenRad = (e.angle ?? 0) * math.pi / 180;
    });

    _pump = Timer.periodic(Duration(milliseconds: 1000 ~/ hz), (_) {
      if (!_gotSample) return;
      // ⚠️ TARTIB MUHIM va u BIR TIK KECHIKISH beradi: `_currentAim()`
      // `_trackSteadiness` dan OLDIN chaqiriladi, ya'ni chop etilgan
      // `steady`/`steadyProgress` OLDINGI tikning hisobidan keladi.
      //
      // O'lchangan: har tik chegaradan past bo'lsa chop etilgan progress
      // 0.000, 0.000, 0.095, 0.190 … 0.952 (12-tik), 1.000 (13-tik) —
      // ya'ni `steady` 13-tikda rost bo'ladi, 11 yoki 12 da emas.
      //
      // «Tabiiy» tartib (avval hisobla, keyin yig') zatvorni bir tik erta
      // ochadi. Tartib ATAYLAB shunday qoldirilgan.
      final DeviceAim next = _currentAim();
      _steadiness.add(next.yawDeg, next.pitchDeg);
      aim.value = next;
    });
  }

  Future<void> stop() async {
    // Nasos AVVAL, birinchi `await` dan oldin to'xtatiladi — aks holda
    // to'xtatish jarayonida yana bir tik o'tib ketishi mumkin.
    _pump?.cancel();
    _pump = null;
    await _orientation?.cancel();
    await _screen?.cancel();
    _orientation = null;
    _screen = null;
  }

  void dispose() {
    unawaited(stop());
    aim.dispose();
  }

  /// Telefon «qimirlamayapti» deb hisoblanadigan burchak tezligi, grad/s.
  ///
  /// Sweep o'rtasida suratga olish kadrga HARAKAT XIRALIGINI kiritadi va bu
  /// kosmetik muammo emas: moslashtirish burchak nuqtalarini solishtiradi,
  /// surtilgan burchak esa yo hech narsaga mos kelmaydi, yo NOTO'G'RI joyga
  /// mos keladi. Ro'yxatga olinmagan kadr tashlanadi; NOTO'G'RI ro'yxatga
  /// olingani esa YOMONROQ — u absurd pitch'ga o'raladi, u yerda sferik
  /// proyeksiya chegarasiz kattalashtiradi va panorama bo'ylab qora tortadi.
  ///
  /// ⚠️ Manbadagi izoh bu yerda «8 grad/s» deb yozilgan, kod esa `3` beradi —
  /// izoh eskirgan. Qiymat `3`: tik turgan odamning qo'l titrashi bundan
  /// ancha past, ataylab burilish esa bir necha barobar tez.
  static const double steadyThresholdDegPerSec = 3;

  /// Zatvor ochilishidan oldin shuncha vaqt shu chegaradan past turishi kerak.
  static const Duration steadyHold = Duration(milliseconds: 350);

  /// ⚠️ `late final` EMAS. `start(hz:)` boshqa tezlik bilan qayta
  /// chaqirilishi mumkin va `late final` birinchi murojaatdagi `_hz` ni
  /// abadiy ushlab qolardi — zatvor keyin noto'g'ri vaqtda ochilardi.
  Steadiness _steadiness = Steadiness(30);

  DeviceAim _currentAim() {
    final a = aimAngles(
      _euler.x,
      _euler.y,
      _euler.z,
      _screenRad,
      clockwisePositive: clockwisePositive,
    );
    return DeviceAim(
      yawDeg: a.yawDeg,
      pitchDeg: a.pitchDeg,
      rollDeg: a.rollDeg,
      rawDeviceRollDeg: _euler.z * 180 / math.pi,
      steady: _steadiness.steady,
      steadyProgress: _steadiness.fraction,
    );
  }
}

/// Telefon qayerga qaragan.
@immutable
class DeviceAim {
  const DeviceAim({
    required this.yawDeg,
    required this.pitchDeg,
    this.rollDeg = 0,
    this.rawDeviceRollDeg = 0,
    this.steady = false,
    this.steadyProgress = 0,
  });

  /// Kompas uslubidagi yo'nalish, 0..360.
  final double yawDeg;

  /// Balandlik: −90 (tik pastga) … +90 (tik yuqoriga). Tortishishga
  /// bog'langan, ya'ni yaw'dan farqli bog'lashni TALAB QILMAYDI — +30 dagi
  /// qator har sessiyada bir xil +30.
  final double pitchDeg;

  /// LINZA O'QI atrofidagi burilish — [yawDeg] va [pitchDeg] bilan bir xil
  /// kvaterniondan o'qiladi.
  ///
  /// Proyektorga kerak bo'lgan burchak AYNAN shu, sensor bergan qurilma
  /// roll'i emas — [rawDeviceRollDeg] ga qara.
  final double rollDeg;

  /// Xom qurilma roll'i — FAQAT sessiya hisoboti uchun.
  ///
  /// ⚠️ Proyektorga foydasiz va [rollDeg] bilan adashtirilsa HALOKATLI:
  /// portretda tik ushlangan telefon shu burchakning singulyarligida o'tiradi
  /// va ±180 atrofida o'qiladi, ya'ni uni berish har kadrni teskari
  /// aylantiradi. Yozib qo'yiladi, chunki sensor shunday degan va hisobot
  /// sensor nima deganini aytishi kerak.
  final double rawDeviceRollDeg;

  /// Telefon xiralashsiz suratga olish uchun yetarlicha ushlab turildimi.
  final bool steady;

  /// [steady] gacha progress, 0..1.
  final double steadyProgress;

  @override
  bool operator ==(Object other) =>
      other is DeviceAim &&
      other.yawDeg == yawDeg &&
      other.pitchDeg == pitchDeg &&
      other.rollDeg == rollDeg &&
      other.rawDeviceRollDeg == rawDeviceRollDeg &&
      other.steady == steady &&
      other.steadyProgress == steadyProgress;

  /// ⚠️ [ValueNotifier] faqat qiymat O'ZGARSA xabar beradi, ya'ni `==` shu
  /// yerda xatti-harakatga ta'sir qiladi: sensor qotib qolsa hech qanday
  /// qayta chizish bo'lmaydi. Maydon qo'shilsa bu yerga ham qo'shilsin.
  @override
  int get hashCode => Object.hash(
    yawDeg,
    pitchDeg,
    rollDeg,
    rawDeviceRollDeg,
    steady,
    steadyProgress,
  );
}


/// Barqarorlik hisobi — nechta ketma-ket «qimirlamagan» tik bo'lgani.
///
/// [HeadingSource] ichidan AJRATILGAN, chunki uning yagona qiziq xatti-
/// harakati — to'lish ketma-ketligi — aks holda taymer va sensor oqimisiz
/// tekshirib bo'lmasdi.
@visibleForTesting
class Steadiness {
  Steadiness(this.hz);

  final int hz;
  double? _prevYaw;
  double? _prevPitch;
  int _ticks = 0;

  int get ticks => _ticks;

  /// Yangi o'lchov qo'shadi. Birinchi chaqiruv faqat tayanch nuqtani
  /// belgilaydi — tezlikni hisoblash uchun ikkita nuqta kerak.
  void add(double yawDeg, double pitchDeg) {
    final double? py = _prevYaw;
    final double? pp = _prevPitch;
    _prevYaw = yawDeg;
    _prevPitch = pitchDeg;
    if (py == null || pp == null) {
      _ticks = 0;
      return;
    }
    // Yaw QISQA yo'l bilan — aks holda 359 → 1 o'tishi 358° sakrash bo'lib
    // o'qilardi va zatvor hech qachon ochilmasdi.
    final double dYaw = shortestTurn(py, yawDeg).abs();
    final double dPitch = (pitchDeg - pp).abs();
    final double speed = math.sqrt(dYaw * dYaw + dPitch * dPitch) * hz;

    if (speed <= HeadingSource.steadyThresholdDegPerSec) {
      _ticks++;
    } else {
      _ticks = 0;
    }
  }

  /// Ushlab turish qanchalik bajarilgani, 0..1.
  double get fraction {
    final double need = HeadingSource.steadyHold.inMilliseconds *
        hz /
        Duration.millisecondsPerSecond;
    if (need <= 0) return 1;
    final double f = _ticks / need;
    return f > 1 ? 1 : f;
  }

  bool get steady => fraction >= 1;

  void reset() {
    _prevYaw = null;
    _prevPitch = null;
    _ticks = 0;
  }

  /// [from] dan [to] gacha eng qisqa ishorali burilish, -180..180.
  static double shortestTurn(double from, double to) {
    final double delta = (to - from) % 360;
    return delta > 180 ? delta - 360 : delta;
  }
}
