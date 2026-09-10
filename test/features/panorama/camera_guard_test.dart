
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/panorama/data/camera_guard.dart';

/// [CameraGuard] — kameraning yagona egaligi.
///
/// Testlarning yarmi «guard bloklaydimi» degan savolga emas, **«guard o'zini
/// bo'shata oladimi»** degan savolga javob beradi. Sabab: qotib qolgan ijara
/// kamerani butun sessiya davomida o'chirib qo'yadi va uni tuzatish yo'li
/// yo'q, ya'ni bu himoya qilinayotgan nosozlikdan ham yomonroq.
void main() {
  // Guard `WidgetsBinding.instance.addObserver` ni chaqiradi — binding
  // bo'lmasa u jimgina o'tkazib yuboriladi, lekin biz haqiqiy yo'lni
  // sinamoqchimiz.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CameraGuard.reset('test');
    CameraGuard.clock = DateTime.now;
    CameraGuard.leaseTimeout = CameraGuard.defaultLeaseTimeout;
  });

  tearDown(() => CameraGuard.reset('test'));

  test('bo\'sh guard birinchi egaga beriladi', () {
    expect(CameraGuard.isFree, isTrue);
    expect(CameraGuard.acquire(CameraGuard.panorama), isTrue);
    expect(CameraGuard.holder, CameraGuard.panorama);
    expect(CameraGuard.isFree, isFalse);
  });

  test('band bo\'lganda boshqa ega `false` oladi', () {
    expect(CameraGuard.acquire(CameraGuard.panorama), isTrue);
    expect(CameraGuard.acquire(CameraGuard.video), isFalse);
    expect(CameraGuard.acquire(CameraGuard.lidar), isFalse);
    // Rad etilgan urinish egani O'ZGARTIRMAYDI.
    expect(CameraGuard.holder, CameraGuard.panorama);
  });

  test('bir ega ikki marta ololmaydi', () {
    expect(CameraGuard.acquire(CameraGuard.video), isTrue);
    // Bitta feature ichidagi ikkita parallel chaqiruv ham ikkita kamera
    // sessiyasi ochadi — ya'ni aynan himoya qilinayotgan nosozlik.
    expect(CameraGuard.acquire(CameraGuard.video), isFalse);
  });

  test('release\'dan keyin yana beriladi', () {
    expect(CameraGuard.acquire(CameraGuard.panorama), isTrue);
    CameraGuard.release(CameraGuard.panorama);
    expect(CameraGuard.isFree, isTrue);
    expect(CameraGuard.acquire(CameraGuard.video), isTrue);
    expect(CameraGuard.holder, CameraGuard.video);
  });

  test('egasi bo\'lmagan release ijarani tortib olmaydi', () {
    expect(CameraGuard.acquire(CameraGuard.panorama), isTrue);
    // Kechikkan yoki takroriy `release` — masalan lifecycle reset ijarani
    // allaqachon bekor qilgan va uni yangi ega olgan.
    CameraGuard.release(CameraGuard.video);
    expect(CameraGuard.holder, CameraGuard.panorama);
  });

  test('bo\'sh guardda release yiqilmaydi', () {
    expect(() => CameraGuard.release(CameraGuard.video), returnsNormally);
    expect(CameraGuard.isFree, isTrue);
  });

  // ── Xato yo'llari ────────────────────────────────────────────────────────

  test('`run` istisno tashlasa ham ijara `finally` da bo\'shaydi', () async {
    await expectLater(
      CameraGuard.run<void>(
        CameraGuard.video,
        () async => throw StateError('native yiqildi'),
      ),
      throwsA(isA<StateError>()),
    );
    expect(CameraGuard.isFree, isTrue,
        reason: '`finally` ishlamasa kamera abadiy band qolardi');
  });

  test('`run` sinxron tashlangan istisnoda ham bo\'shaydi', () async {
    await expectLater(
      CameraGuard.run<void>(CameraGuard.video, () => throw ArgumentError('x')),
      throwsA(isA<ArgumentError>()),
    );
    expect(CameraGuard.isFree, isTrue);
  });

  test('`run` natijani o\'zgartirmaydi va ijarani bo\'shatadi', () async {
    final value = await CameraGuard.run(CameraGuard.video, () async => 42);
    expect(value, 42);
    expect(CameraGuard.isFree, isTrue);
  });

  test('`run` band guardda `action` ni UMUMAN chaqirmaydi', () async {
    expect(CameraGuard.acquire(CameraGuard.panorama), isTrue);
    var called = false;
    await expectLater(
      CameraGuard.run<void>(CameraGuard.video, () async {
        called = true;
      }),
      throwsA(isA<CameraBusyException>()),
    );
    expect(called, isFalse);
    // Rad etilgan chaqiruvning `finally` si asl egani bo'shatib yubormaydi.
    expect(CameraGuard.holder, CameraGuard.panorama);
  });

  test('`run` timeout\'da ham ijarani bo\'shatadi', () async {
    await expectLater(
      CameraGuard.run<void>(
        CameraGuard.video,
        () => Future<void>.delayed(const Duration(seconds: 5)),
        timeout: const Duration(milliseconds: 20),
      ),
      throwsA(isA<Exception>()),
    );
    expect(CameraGuard.isFree, isTrue);
  });

  test('muddati o\'tgan ijara o\'z-o\'zidan bekor qilinadi', () {
    var now = DateTime(2026, 1, 1, 12);
    CameraGuard.clock = () => now;
    CameraGuard.leaseTimeout = const Duration(minutes: 15);

    expect(CameraGuard.acquire(CameraGuard.lidar), isTrue);
    // 14 daqiqadan keyin — hali tirik. Uzun RoomPlan skani uzilib qolmasligi
    // kerak.
    now = now.add(const Duration(minutes: 14));
    expect(CameraGuard.holder, CameraGuard.lidar);
    expect(CameraGuard.acquire(CameraGuard.video), isFalse);

    // 16 daqiqadan keyin — «hech qachon qaytmadi» deb hisoblanadi.
    now = now.add(const Duration(minutes: 2));
    expect(CameraGuard.holder, isNull);
    expect(CameraGuard.acquire(CameraGuard.video), isTrue);
  });

  // ── Lifecycle ────────────────────────────────────────────────────────────

  test('fonga tushib qaytish ijarani bo\'shatadi', () {
    expect(CameraGuard.acquire(CameraGuard.video), isTrue);
    CameraGuard.handleLifecycle(AppLifecycleState.paused);
    // Fonda ekan ijara hali ham egasida — uni o'sha yerda bo'shatishning
    // ma'nosi yo'q, chunki native ekran hali ishlayotgan bo'lishi mumkin.
    expect(CameraGuard.holder, CameraGuard.video);
    CameraGuard.handleLifecycle(AppLifecycleState.resumed);
    expect(CameraGuard.isFree, isTrue);
  });

  test('`hidden` ham fonga tushish deb hisoblanadi', () {
    expect(CameraGuard.acquire(CameraGuard.video), isTrue);
    CameraGuard.handleLifecycle(AppLifecycleState.hidden);
    CameraGuard.handleLifecycle(AppLifecycleState.resumed);
    expect(CameraGuard.isFree, isTrue);
  });

  test('`inactive` ijarani bo\'shatmaydi', () {
    expect(CameraGuard.acquire(CameraGuard.panorama), isTrue);
    // iOS'da Control Center, bildirishnoma pardasi va har bir tizim modali
    // `inactive` beradi — buni fonga tushish deb hisoblasak har uchinchi
    // ijara sababsiz uziladi.
    CameraGuard.handleLifecycle(AppLifecycleState.inactive);
    CameraGuard.handleLifecycle(AppLifecycleState.resumed);
    expect(CameraGuard.holder, CameraGuard.panorama);
  });

  test('fonga tushmasdan `resumed` kelsa ijara qoladi', () {
    expect(CameraGuard.acquire(CameraGuard.panorama), isTrue);
    CameraGuard.handleLifecycle(AppLifecycleState.resumed);
    expect(CameraGuard.holder, CameraGuard.panorama);
  });

  test('lifecycle reset yangi egadan kamerani tortib olmaydi', () {
    expect(CameraGuard.acquire(CameraGuard.video), isTrue);
    CameraGuard.handleLifecycle(AppLifecycleState.paused);
    CameraGuard.handleLifecycle(AppLifecycleState.resumed);
    expect(CameraGuard.acquire(CameraGuard.panorama), isTrue);
    // Kechikkan native javob endi `release('video')` chaqiradi — u yangi
    // egaga tegmasligi kerak.
    CameraGuard.release(CameraGuard.video);
    expect(CameraGuard.holder, CameraGuard.panorama);
  });

  testWidgets(
    'kuzatuvchi HAQIQATAN o\'rnatilgan — haqiqiy lifecycle hodisasi yetadi',
    (tester) async {
      // Yuqoridagi testlar [CameraGuard.handleLifecycle] ni QO'LDA chaqiradi,
      // ya'ni ular «kuzatuvchi `WidgetsBinding` ga qo'shilganmi» degan
      // savolga javob bermaydi. Qo'shilmagan bo'lsa lifecycle himoyasi
      // qurilmada jimgina ishlamay qolardi.
      expect(CameraGuard.acquire(CameraGuard.video), isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(CameraGuard.isFree, isTrue);
    },
  );

  // ⚠️ AI BAHOLASH FAYLLARIGA TEGILMAYDI.
  //
  // Dastlab `video_capture.dart` va `room_plan_scanner.dart` ham
  // `CameraGuard` ga o'ralgan edi va bu yerda ular bilan integratsiya
  // testlari turardi. Ular OLIB TASHLANDI: 360° Bozor e'lon sehrgari
  // uchun so'ralgan, AI Baholash kamerasini qayta qurish uchun emas.
  //
  // Ziddiyat hozir YUZAGA KELMAYDI ham — panorama capture ekrani
  // (19-qadam) hali yozilmagan, ya'ni kamerani ochadigan ikkinchi
  // egasi yo'q va qulf hech narsadan himoya qilmasdi.
  //
  // 19-qadamda ziddiyat haqiqiy bo'ladi. O'shanda MAVJUD kodga
  // tegishdan oldin so'raladi; birinchi ko'riladigan muqobil —
  // panorama ekrani o'zi ochilishdan oldin bandlikni tekshirsin, ya'ni
  // AI Baholash fayllariga umuman tegilmasin.
}
