import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/panorama/data/camera_guard.dart';
import 'package:kadastr/features/services/data/room_plan_scanner.dart';
import 'package:kadastr/features/services/data/video_capture.dart';

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

  // ── `VideoCapture` ning guard ostidagi xatti-harakati ────────────────────
  //
  // Mavjud yagona chaqiruvchi (`ai_start_screen.dart`) faqat
  // [VideoCaptureException] ni ushlaydi, boshqa istisno esa uning `_busy`
  // bayrog'ini tozalanmagan qoldirib ekranni qotirib qo'yadi. Shuning uchun
  // guard xatosi ham AYNAN shu turga o'giriladi.
  group('VideoCapture + CameraGuard', () {
    const channel = MethodChannel('kadastr/video_capture');
    late List<String> calls;

    setUp(() {
      calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return <dynamic, dynamic>{'path': '/tmp/a.mp4', 'sizeBytes': 1024};
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('guard bo\'sh bo\'lsa hammasi avvalgidek ishlaydi', () async {
      final result = await VideoCapture.capture();
      expect(result?.path, '/tmp/a.mp4');
      expect(calls, isNotEmpty, reason: 'native kanal chaqirilishi kerak');
      expect(CameraGuard.isFree, isTrue, reason: 'ijara bo\'shashi kerak');
    });

    test('panorama ushlab turganda kanalga UMUMAN bormaydi', () async {
      expect(CameraGuard.acquire(CameraGuard.panorama), isTrue);
      await expectLater(
        VideoCapture.capture(),
        throwsA(isA<VideoCaptureException>().having(
          (e) => e.code,
          'code',
          VideoCapture.busyCode,
        )),
      );
      expect(calls, isEmpty);
      expect(CameraGuard.holder, CameraGuard.panorama);
    });

    test('native xatodan keyin ham ijara bo\'shaydi', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'REC_FAIL', message: 'yozib bo\'lmadi');
      });
      await expectLater(
        VideoCapture.record(),
        throwsA(isA<VideoCaptureException>()),
      );
      expect(CameraGuard.isFree, isTrue);
    });
  });

  // ── LiDAR (`kadastr/room_plan_scanner`) ────────────────────────────────────
  //
  // Uchinchi ega. U guard'ga ENG OXIRI qo'shildi va shu sababli eng muhim
  // da'vo bu yerda TESKARI yo'nalishda tekshiriladi: skan ketayotganda
  // panorama va video RAD ETILISHI kerak. Faqat «band bo'lsa skan
  // boshlanmaydi» ni tekshirish yetmasdi — lidar ijarani UMUMAN olmasa ham
  // o'sha test yashil qolardi.
  group('RoomPlanScanner + CameraGuard', () {
    const channel = MethodChannel('kadastr/room_plan_scanner');
    late List<String> calls;

    void mock(Future<Object?> Function(MethodCall) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) {
        calls.add(call.method);
        return handler(call);
      });
    }

    setUp(() {
      calls = <String>[];
      mock((call) async => <dynamic, dynamic>{'filePath': '/tmp/a.usdz'});
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('guard bo\'sh bo\'lsa hammasi avvalgidek ishlaydi', () async {
      final r = await RoomPlanScanner.startScan();
      expect(r?.filePath, '/tmp/a.usdz');
      expect(calls, ['startScan']);
      expect(CameraGuard.isFree, isTrue, reason: 'ijara bo\'shashi kerak');
    });

    test('skan KETAYOTGANDA panorama va video rad etiladi', () async {
      // Eng muhim test: lidar ijarani HAQIQATAN oladimi.
      final native = Completer<Object?>();
      mock((call) => native.future);

      final scan = RoomPlanScanner.startScan();
      await pumpEventQueue();

      expect(CameraGuard.holder, CameraGuard.lidar);
      expect(CameraGuard.acquire(CameraGuard.panorama), isFalse);
      expect(CameraGuard.acquire(CameraGuard.video), isFalse);

      native.complete(<dynamic, dynamic>{'filePath': '/tmp/a.usdz'});
      await scan;
      expect(CameraGuard.isFree, isTrue);
    });

    test('panorama ushlab turganda kanalga UMUMAN bormaydi', () async {
      expect(CameraGuard.acquire(CameraGuard.panorama), isTrue);
      await expectLater(
        RoomPlanScanner.startScan(),
        throwsA(isA<RoomPlanScannerException>().having(
          (e) => e.code,
          'code',
          RoomPlanScanner.busyCode,
        )),
      );
      expect(calls, isEmpty);
      expect(CameraGuard.holder, CameraGuard.panorama);
    });

    test('HAMMA skan yo\'li guard ostida', () async {
      // Bittasi o'ralmay qolsa shu test uni ushlaydi.
      expect(CameraGuard.acquire(CameraGuard.video), isTrue);
      final starts = <String, Future<Object?>>{
        'startScan': RoomPlanScanner.startScan(),
        'startTexturedScan': RoomPlanScanner.startTexturedScan(),
        'startTexturedRoomPlan': RoomPlanScanner.startTexturedRoomPlan(),
        'startObjectCapture': RoomPlanScanner.startObjectCapture(),
        'startHybridScan':
            RoomPlanScanner.startHybridScan(baseUrl: 'x', token: 'y'),
      };
      for (final e in starts.entries) {
        await expectLater(
          e.value,
          throwsA(isA<RoomPlanScannerException>()
              .having((x) => x.code, 'code', RoomPlanScanner.busyCode)),
          reason: '${e.key} guard ostida emas',
        );
      }
      expect(calls, isEmpty, reason: 'hech biri kanalga bormasligi kerak');
    });

    test('native xatodan keyin ham ijara bo\'shaydi', () async {
      mock((call) async =>
          throw PlatformException(code: 'SCAN_FAIL', message: 'yiqildi'));
      await expectLater(
        RoomPlanScanner.startTexturedScan(),
        throwsA(isA<RoomPlanScannerException>()
            .having((e) => e.code, 'code', 'SCAN_FAIL')),
      );
      expect(CameraGuard.isFree, isTrue);
    });

    test('`isSupported` va `preview` ATAYLAB guard ostida EMAS', () async {
      // `isSupported` faqat qobiliyat so'raydi, `previewModel` esa QuickLook
      // ni ochadi — ikkalasi ham kamerani ochmaydi. Ularni guard'lash
      // panorama ketayotganda natijani ko'rsatishni bloklab qo'yardi.
      expect(CameraGuard.acquire(CameraGuard.panorama), isTrue);
      mock((call) async => call.method == 'isSupported' ? true : null);
      expect(await RoomPlanScanner.isSupported(), isTrue);
      await RoomPlanScanner.preview('/tmp/a.usdz');
      expect(calls, ['isSupported', 'previewModel']);
      expect(CameraGuard.holder, CameraGuard.panorama);
    });
  });
}
