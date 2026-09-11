import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/core/i18n/app_translations.dart';
import 'package:kadastr/features/panorama/data/pano_capture_channel.dart';

/// Nativ kanal shartnomasi — iOS va Android AYNAN bir xil javob qaytaradi.
///
/// ⚠️ NEGA BU TEST BOR. `dir` va `frames` kalitlari uch joyda QO'LDA
/// yozilgan: `PanoCapture.swift`, `MainActivity.kt` va shu fayl. Bittasida
/// adashilsa Dart `dir: ''` oladi, `meta.json` topilmaydi va oqim
/// «kadrlar yo'q» deb yiqiladi — foydalanuvchi 30 nishonni aylanib
/// chiqqandan KEYIN. Test qurilmasiz ishlaydi: kanal mock qilinadi.
void main() {
  const channel = MethodChannel('kadastr/pano_capture');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  void mock(Future<Object?>? Function(MethodCall) handler) {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, handler);
  }

  setUp(() {
    // Tarjimalar bo'lmasa `tr()` XOM KALIT qaytaradi va pastdagi tekshiruv
    // aynan shuni ushlaydi — seed'ni yuklab qo'yamiz (repodagi odatiy usul).
    appTranslationsNotifier.value = AppTranslations.fromJson(
      jsonDecode(File('assets/i18n/bundle.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    appTranslationsNotifier.value = AppTranslations.empty;
  });

  /// `start` uchun lokalizatsiyalangan kontekst kerak (matnlar tarjima
  /// qilinib nativ tarafga uzatiladi).
  Future<BuildContext> contextOf(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('uz'),
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return ctx;
  }

  testWidgets('isSupported — kanal ulanmagan bo\'lsa false', (tester) async {
    // Nativ taraf yo'q (masalan hali qo'llab-quvvatlanmagan platforma).
    // ⚠️ Bu holat ATAYLAB mock bilan yasaladi: mock'siz `invokeMethod`
    // `testWidgets` ning soxta vaqtida hech qachon tugamaydi va test 10
    // daqiqadan keyin timeout bilan yiqiladi (bir marta shunday bo'ldi).
    mock((_) async => throw MissingPluginException('kanal yo\'q'));
    expect(await PanoCaptureChannel.isSupported(), isFalse);
  });

  testWidgets('isSupported — PlatformException false ga tushadi', (t) async {
    mock((_) async => throw PlatformException(code: 'X'));
    expect(await PanoCaptureChannel.isSupported(), isFalse);
  });

  testWidgets('isSupported — nativ true ni o\'tkazadi', (tester) async {
    mock((c) async => c.method == 'isSupported' ? true : null);
    expect(await PanoCaptureChannel.isSupported(), isTrue);
  });

  testWidgets('start — nativ javob o\'qiladi', (tester) async {
    Map<Object?, Object?>? args;
    mock((c) async {
      args = c.arguments as Map<Object?, Object?>;
      return <Object?, Object?>{'dir': '/data/pano/abc', 'frames': 28};
    });

    final res = await PanoCaptureChannel.start(await contextOf(tester));

    expect(res, isNotNull);
    expect(res!.dir, '/data/pano/abc');
    expect(res.frames, 28);

    // Matnlar SHU YERDA tarjima qilinadi — Swift va Kotlin'da i18n yo'q.
    final strings = (args!['strings'] as Map).cast<String, String>();
    expect(
      strings.keys.toSet(),
      containsAll(<String>[
        'tracking', 'moved', 'ar_error', 'skip_poles', 'finish',
        'finish_title', 'finish_body', 'finish_yes', 'finish_no', 'hint',
      ]),
      reason: 'nativ ekran shu kalitlarni kutadi; yetishmagani INGLIZCHA '
          'zaxira matn bo\'lib chiqadi',
    );
    for (final e in strings.entries) {
      expect(e.value, isNotEmpty, reason: '${e.key} tarjimasi bo\'sh');
      expect(
        e.value.startsWith('bozor.pano.'),
        isFalse,
        reason: '${e.key} tarjima qilinmagan — xom kalit ketyapti',
      );
    }
  });

  testWidgets('start — bekor qilinsa null', (tester) async {
    mock((_) async => null);
    expect(await PanoCaptureChannel.start(await contextOf(tester)), isNull);
  });

  testWidgets('start — buzuq javobda ham yiqilmaydi', (tester) async {
    // `frames` yo'q / `dir` yo'q: oqim buni o'zi «kadrlar yo'q» deb
    // ushlaydi, kanal esa istisno tashlamasligi kerak.
    mock((_) async => <Object?, Object?>{});
    final res = await PanoCaptureChannel.start(await contextOf(tester));
    expect(res, isNotNull);
    expect(res!.dir, '');
    expect(res.frames, 0);
  });
}
