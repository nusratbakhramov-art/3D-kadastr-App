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
        'tracking',
        'moved',
        'ar_error',
        'skip_poles',
        'finish',
        'finish_title',
        'finish_body',
        'finish_yes',
        'finish_no',
        'hint',
      ]),
      reason:
          'nativ ekran shu kalitlarni kutadi; yetishmagani INGLIZCHA '
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

  testWidgets('stitch — argumentlar va natija, progress TESKARI keladi', (
    tester,
  ) async {
    Map<Object?, Object?>? args;
    mock((c) async {
      if (c.method != 'stitch') return null;
      args = c.arguments as Map<Object?, Object?>;
      // Nativ taraf tikish davomida shu kanalga `progress` yuboradi —
      // Dart tomonidagi handler'ni platforma xabari bilan uyg'otamiz.
      final codec = channel.codec;
      await binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(
          const MethodCall('progress', {'p': 0.42, 'msg': 'MVS: depth 3/28'}),
        ),
        (_) {},
      );
      return <Object?, Object?>{
        'pano': '/tmp/pano/x/pano.jpg',
        'preview': '/tmp/pano/x/preview.jpg',
        'width': 4096,
        'height': 2048,
        'frames': 28,
        'coverage': 0.87,
        'seconds': 101.5,
        'mode': 'mvs',
      };
    });

    final got = <(double, String)>[];
    final r = await PanoCaptureChannel.stitch(
      dir: '/tmp/pano/x',
      onProgress: (p, m) => got.add((p, m)),
    );

    expect(args!['dir'], '/tmp/pano/x');
    expect(args!['width'], 4096);
    expect(args!['mode'], 'auto');
    expect(args!.containsKey('logoAsset'), isFalse);
    expect(r.panoPath, '/tmp/pano/x/pano.jpg');
    expect(r.width, 4096);
    expect(r.frames, 28);
    expect(r.mode, 'mvs');
    expect(got, [(0.42, 'MVS: depth 3/28')]);
  });

  testWidgets('stitch — nativ xato PlatformException bo\'lib chiqadi', (
    tester,
  ) async {
    mock(
      (_) async =>
          throw PlatformException(code: 'STITCH_FAILED', message: 'kam kadr'),
    );
    await expectLater(
      PanoCaptureChannel.stitch(dir: '/tmp/pano/x'),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.message,
          'message',
          'kam kadr',
        ),
      ),
    );
  });

  testWidgets('stitch — pano yo\'li bo\'sh javob xato', (tester) async {
    mock((_) async => <Object?, Object?>{'pano': ''});
    await expectLater(
      PanoCaptureChannel.stitch(dir: '/tmp/pano/x'),
      throwsA(isA<PlatformException>()),
    );
  });

  testWidgets('tour — argumentlar Swift shartnomasida, matnlar tarjimada', (
    tester,
  ) async {
    Map<Object?, Object?>? args;
    mock((c) async {
      if (c.method != 'tour') return null;
      args = c.arguments as Map<Object?, Object?>;
      return <Object?, Object?>{
        'links': <Object?>[
          <Object?, Object?>{
            'from': 'k1',
            'to': 'k2',
            'yawDeg': 12.5,
            'pitchDeg': -1.0,
          },
        ],
      };
    });
    final res = await PanoCaptureChannel.tour(
      await contextOf(tester),
      panoramas: const [
        PanoTourRoom(key: 'k1', name: 'Xona 1', url: 'https://x/1.jpg'),
        PanoTourRoom(key: 'k2', name: 'Xona 2', url: 'https://x/2.jpg'),
      ],
      links: const [],
      startKey: 'k2',
      editable: true,
    );
    expect(res, isNotNull);
    expect(res!.links.single['from'], 'k1');
    expect(res.newRoom, isNull);

    final rooms = (args!['panoramas'] as List).cast<Map>();
    expect(rooms.first['key'], 'k1');
    expect(rooms.first['url'], 'https://x/1.jpg');
    expect(rooms.first.containsKey('path'), isFalse);
    expect(args!['startKey'], 'k2');
    expect(args!['editable'], true);
    final strings = (args!['strings'] as Map).cast<String, String>();
    expect(
      strings.keys.toSet(),
      containsAll(<String>[
        'room_n',
        'rooms',
        'hotspot_title',
        'move',
        'move_here',
        'remove',
        'edit_place',
        'edit_existing',
        'no_links',
        'pick_title',
        'new_room',
        'linked',
        'need_two',
        'limit',
        'too_close',
        'view_hint',
        'err',
        'err_network',
        'cancel',
        'close',
        'preview_title',
        'accept',
        'retake',
      ]),
    );
    for (final e in strings.entries) {
      expect(e.value, isNotEmpty, reason: '${e.key} tarjimasi bo\'sh');
      expect(
        e.value.startsWith('bozor.pano.') || e.value.startsWith('common.'),
        isFalse,
        reason: '${e.key} tarjima qilinmagan — xom kalit ketyapti',
      );
    }
  });

  testWidgets('preview — accept / retake', (tester) async {
    mock((c) async => <Object?, Object?>{'action': 'retake'});
    expect(
      await PanoCaptureChannel.preview(await contextOf(tester), path: '/p.jpg'),
      PanoPreviewAction.retake,
    );
    mock((c) async => <Object?, Object?>{'action': 'accept'});
    expect(
      await PanoCaptureChannel.preview(await contextOf(tester), path: '/p.jpg'),
      PanoPreviewAction.accept,
    );
  });

  testWidgets('start — capture ekrani Uy360 UI kalitlarini ham oladi', (
    tester,
  ) async {
    Map<Object?, Object?>? args;
    mock((c) async {
      args = c.arguments as Map<Object?, Object?>;
      return <Object?, Object?>{'dir': '/d', 'frames': 1};
    });
    await PanoCaptureChannel.start(await contextOf(tester));
    final strings = (args!['strings'] as Map).cast<String, String>();
    expect(
      strings.keys.toSet(),
      containsAll(<String>[
        'return_to',
        'dir_right',
        'dir_left',
        'dir_forward',
        'dir_back',
        'dir_up',
        'dir_down',
        'in_place',
        'off_place',
        'early_finish',
      ]),
    );
    // Nativ dialog `%d` (olingan) va `%t` (jami) ni o'zi almashtiradi.
    expect(strings['finish_body'], contains('%d'));
    expect(strings['finish_body'], contains('%t'));
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
