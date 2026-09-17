import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/core/i18n/app_translations.dart';
import 'package:kadastr/features/panorama/data/pano_capture_channel.dart';

/// Nativ kanal shartnomasi — iOS va Android AYNAN bir xil javob qaytaradi.
///
/// ⚠️ NEGA BU TEST BOR. `dir` va `frames` kalitlari uch joyda QO'LDA
/// yozilgan: `PanoCapture.swift`, `MainActivity.kt` va shu fayl. Bittasida
/// adashilsa Dart `dir: ''` oladi, `meta.json` topilmaydi va oqim
/// «kadrlar yo'q» deb yiqiladi — foydalanuvchi nishonlarni aylanib
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
        supportedLocales: const [Locale('uz'), Locale('ru'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
    expect(args!.containsKey('mode'), isFalse); // Legacy callers keep ARKit.

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

  testWidgets('sensor processing support is independent of capture support', (
    tester,
  ) async {
    mock((call) async {
      switch (call.method) {
        case 'isSupported':
          return false;
        case 'ultraWideCapability':
          return {
            'available': false,
            'cameraAuthorization': 'denied',
            'reason': 'CAMERA_PERMISSION',
          };
        case 'isSensorProcessingSupported':
          return true;
        default:
          fail('Unexpected capability query: ${call.method}');
      }
    });
    expect(await PanoCaptureChannel.isSupported(), isFalse);
    expect((await PanoCaptureChannel.ultraWideCapability()).available, isFalse);
    expect(await PanoCaptureChannel.isSensorProcessingSupported(), isTrue);
  });

  testWidgets(
    'Android prefers ultra-wide and retains measured ARCore fallback',
    (tester) async {
      var ultra = true;
      mock(
        (call) async => switch (call.method) {
          'ultraWideCapability' => {
            'available': ultra,
            'cameraAuthorization': 'authorized',
          },
          'isSensorProcessingSupported' => true,
          'isARKitCaptureSupported' => false,
          'isARCoreCaptureSupported' => true,
          'start' => {'dir': '/data/pano/android', 'frames': ultra ? 17 : 28},
          _ => null,
        },
      );
      expect(
        await PanoCaptureChannel.preferredCaptureMode(),
        PanoCaptureMode.ultrawide,
      );
      ultra = false;
      expect(
        await PanoCaptureChannel.preferredCaptureMode(),
        PanoCaptureMode.arcore,
      );
      expect(
        (await PanoCaptureChannel.startPreferred(
          await contextOf(tester),
        ))!.frames,
        28,
      );
    },
  );

  testWidgets('old native builds report sensor processing unavailable', (
    tester,
  ) async {
    mock((_) async => throw MissingPluginException());
    expect(await PanoCaptureChannel.isSensorProcessingSupported(), isFalse);
  });

  testWidgets('sensor processing capability failures are controlled', (
    tester,
  ) async {
    mock((_) async => throw PlatformException(code: 'UNSUPPORTED'));
    expect(await PanoCaptureChannel.isSensorProcessingSupported(), isFalse);
  });

  testWidgets('start — bekor qilinsa null', (tester) async {
    mock((_) async => null);
    expect(await PanoCaptureChannel.start(await contextOf(tester)), isNull);
  });

  for (final ultraWide in [false, true]) {
    for (final processing in [false, true]) {
      for (final arkit in [false, true]) {
        testWidgets(
          'preferred capture UW=$ultraWide processing=$processing ARKit=$arkit',
          (tester) async {
            mock(
              (call) async => switch (call.method) {
                'ultraWideCapability' => {
                  'available': ultraWide,
                  'cameraAuthorization': 'authorized',
                },
                'isSensorProcessingSupported' => processing,
                'isARKitCaptureSupported' => arkit,
                'isARCoreCaptureSupported' => false,
                _ => fail('Capture selection must not query ${call.method}'),
              },
            );
            expect(
              await PanoCaptureChannel.preferredCaptureMode(),
              ultraWide && processing
                  ? PanoCaptureMode.ultrawide
                  : arkit
                  ? PanoCaptureMode.arkit
                  : null,
            );
          },
        );
      }
    }
  }

  testWidgets('viewer support does not depend on capture or permission', (
    tester,
  ) async {
    mock((call) async {
      expect(call.method, 'isViewerSupported');
      return true;
    });
    expect(await PanoCaptureChannel.isViewerSupported(), isTrue);
  });

  testWidgets('unavailable capabilities fail closed', (tester) async {
    mock((_) async => throw MissingPluginException());
    expect(await PanoCaptureChannel.isViewerSupported(), isFalse);
    expect(await PanoCaptureChannel.isARKitCaptureSupported(), isFalse);
    expect(await PanoCaptureChannel.preferredCaptureMode(), isNull);
    await expectLater(
      PanoCaptureChannel.startPreferred(await contextOf(tester)),
      throwsA(
        isA<PlatformException>()
            .having((e) => e.code, 'code', 'NO_CAPTURE_MODE')
            .having(
              (e) => e.message,
              'message',
              tr(const Locale('uz'), 'bozor.pano.cap.err_unavailable'),
            ),
      ),
    );
  });

  testWidgets(
    'production capture falls back to ARKit on unsupported hardware',
    (tester) async {
      mock(
        (call) async => switch (call.method) {
          'ultraWideCapability' => {
            'available': false,
            'cameraAuthorization': 'authorized',
            'reason': 'NO_ULTRAWIDE_CAMERA',
          },
          'isARKitCaptureSupported' => true,
          'start' => (() {
            expect((call.arguments as Map)['mode'], 'arkit');
            return {'dir': '/data/pano/legacy', 'frames': 28};
          })(),
          _ => fail('Unexpected query ${call.method}'),
        },
      );
      final result = await PanoCaptureChannel.startPreferred(
        await contextOf(tester),
      );
      expect(result!.frames, 28);
    },
  );

  testWidgets('capability lost before presentation falls back once', (
    tester,
  ) async {
    final starts = <String>[];
    mock((call) async {
      if (call.method == 'ultraWideCapability') return {'available': true};
      if (call.method == 'isSensorProcessingSupported' ||
          call.method == 'isARKitCaptureSupported') {
        return true;
      }
      final mode = (call.arguments as Map)['mode'] as String;
      starts.add(mode);
      if (mode == 'ultrawide') {
        throw PlatformException(code: 'NO_ULTRAWIDE_CAMERA');
      }
      return null;
    });
    expect(
      await PanoCaptureChannel.startPreferred(await contextOf(tester)),
      isNull,
    );
    expect(starts, ['ultrawide', 'arkit']);
  });

  for (final failure in [
    null,
    'CAMERA_PERMISSION',
    'CAPTURE_INTERRUPTED',
    'CAPTURE_IO',
  ]) {
    testWidgets(
      'production capture never restarts after ${failure ?? 'cancel'}',
      (tester) async {
        var starts = 0;
        mock((call) async {
          if (call.method == 'ultraWideCapability') return {'available': true};
          if (call.method == 'isSensorProcessingSupported') return true;
          expect(call.method, 'start');
          starts++;
          if (failure != null) throw PlatformException(code: failure);
          return null;
        });
        final future = PanoCaptureChannel.startPreferred(
          await contextOf(tester),
        );
        if (failure == null) {
          expect(await future, isNull);
        } else {
          await expectLater(
            future,
            throwsA(
              isA<PlatformException>().having((e) => e.code, 'code', failure),
            ),
          );
        }
        expect(starts, 1);
      },
    );
  }

  testWidgets('explicit ultra-wide probes capability and passes mode', (
    tester,
  ) async {
    final methods = <String>[];
    Map<Object?, Object?>? args;
    mock((call) async {
      methods.add(call.method);
      if (call.method == 'ultraWideCapability') {
        return {'available': true, 'cameraAuthorization': 'notDetermined'};
      }
      args = call.arguments as Map<Object?, Object?>;
      return {'dir': '/data/pano/sensor', 'frames': 17};
    });
    final result = await PanoCaptureChannel.start(
      await contextOf(tester),
      mode: PanoCaptureMode.ultrawide,
    );
    expect(methods, ['ultraWideCapability', 'start']);
    expect(args!['mode'], 'ultrawide');
    expect(result!.dir, '/data/pano/sensor');
    expect(result.frames, 17);
    expect(
      (args!['strings'] as Map).keys,
      containsAll(['uw_hint', 'uw_level', 'uw_retry', 'close']),
    );
  });

  testWidgets('explicit ARKit skips ultra-wide capability', (tester) async {
    mock((call) async {
      expect(call.method, 'start');
      expect((call.arguments as Map)['mode'], 'arkit');
      return null;
    });
    expect(
      await PanoCaptureChannel.start(
        await contextOf(tester),
        mode: PanoCaptureMode.arkit,
      ),
      isNull,
    );
  });

  testWidgets('unsupported ultra-wide never silently starts legacy capture', (
    tester,
  ) async {
    mock((call) async {
      expect(call.method, 'ultraWideCapability');
      return {
        'available': false,
        'cameraAuthorization': 'authorized',
        'reason': 'NO_ULTRAWIDE_CAMERA',
      };
    });
    await expectLater(
      PanoCaptureChannel.start(
        await contextOf(tester),
        mode: PanoCaptureMode.ultrawide,
      ),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'NO_ULTRAWIDE_CAMERA',
        ),
      ),
    );
  });

  testWidgets('camera permission errors propagate from ultra-wide start', (
    tester,
  ) async {
    mock((call) async {
      if (call.method == 'ultraWideCapability') {
        return {'available': true, 'cameraAuthorization': 'notDetermined'};
      }
      throw PlatformException(code: 'CAMERA_PERMISSION');
    });
    await expectLater(
      PanoCaptureChannel.start(
        await contextOf(tester),
        mode: PanoCaptureMode.ultrawide,
      ),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'CAMERA_PERMISSION',
        ),
      ),
    );
  });

  testWidgets(
    'capture errors use the app locale and send localized native states',
    (tester) async {
      final ctx = await contextOf(tester);
      mock((call) async {
        final strings = ((call.arguments as Map)['strings'] as Map)
            .cast<String, String>();
        for (final key in [
          'permission',
          'unavailable',
          'interrupted',
          'camera',
          'motion',
          'storage',
          'photo',
          'busy',
        ]) {
          expect(
            strings['err_$key'],
            tr(const Locale('uz'), 'bozor.pano.cap.err_$key'),
          );
          expect(strings['err_$key'], isNot(startsWith('bozor.')));
        }
        throw PlatformException(
          code: 'CAPTURE_INTERRUPTED',
          message: 'Native fallback',
          details: {'test': true},
        );
      });
      await expectLater(
        PanoCaptureChannel.start(ctx, mode: PanoCaptureMode.arkit),
        throwsA(
          isA<PlatformException>()
              .having(
                (e) => e.message,
                'message',
                tr(const Locale('uz'), 'bozor.pano.cap.err_interrupted'),
              )
              .having((e) => e.details, 'details', {'test': true}),
        ),
      );
      for (final locale in ['en', 'ru', 'uz']) {
        for (final key in [
          'permission',
          'unavailable',
          'interrupted',
          'camera',
          'motion',
          'storage',
          'photo',
          'busy',
        ]) {
          expect(
            tr(Locale(locale), 'bozor.pano.cap.err_$key'),
            isNot(startsWith('bozor.')),
          );
        }
      }
    },
  );

  testWidgets('ultra-wide capability is separate from legacy support', (
    tester,
  ) async {
    mock((call) async {
      if (call.method == 'isSupported') return true;
      return {
        'available': false,
        'cameraAuthorization': 'denied',
        'reason': 'CAMERA_PERMISSION',
      };
    });
    expect(await PanoCaptureChannel.isSupported(), isTrue);
    final capability = await PanoCaptureChannel.ultraWideCapability();
    expect(capability.available, isFalse);
    expect(capability.cameraAuthorization, 'denied');
    expect(capability.reason, 'CAMERA_PERMISSION');
  });

  testWidgets('old native builds report ultra-wide unavailable', (
    tester,
  ) async {
    mock((_) async => throw MissingPluginException());
    final capability = await PanoCaptureChannel.ultraWideCapability();
    expect(capability.available, isFalse);
    expect(capability.reason, 'UNSUPPORTED');
  });

  testWidgets('capability query failure is controlled', (tester) async {
    mock((_) async => throw PlatformException(code: 'CAPABILITY_FAILED'));
    final capability = await PanoCaptureChannel.ultraWideCapability();
    expect(capability.available, isFalse);
    expect(capability.reason, 'CAPABILITY_FAILED');
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
    expect(args!.containsKey('width'), isFalse);
    expect(args!['mode'], 'auto');
    expect(args!.containsKey('logoAsset'), isFalse);
    expect(r.panoPath, '/tmp/pano/x/pano.jpg');
    expect(r.width, 4096);
    expect(r.frames, 28);
    expect(r.mode, 'mvs');
    expect(got, [(0.42, 'MVS: depth 3/28')]);
  });

  testWidgets('stitch leaves sensor defaults to native saved metadata', (
    tester,
  ) async {
    mock((call) async {
      expect(call.method, 'stitch');
      expect(call.arguments, {'dir': '/data/pano/sensor', 'mode': 'auto'});
      return {
        'pano': '/data/pano/sensor/pano.jpg',
        'preview': '/data/pano/sensor/preview.jpg',
        'width': 6144,
        'height': 3072,
        'frames': 17,
        'mode': 'mvs',
      };
    });
    final result = await PanoCaptureChannel.stitch(dir: '/data/pano/sensor');
    expect(result.width, 6144);
    expect(result.height, 3072);
    expect(result.frames, 17);
    expect(result.mode, 'mvs');
    expect(result.panoPath, '/data/pano/sensor/pano.jpg');
    expect(result.previewPath, '/data/pano/sensor/preview.jpg');
  });

  testWidgets('stitch retains explicit width mode and logo overrides', (
    tester,
  ) async {
    mock((call) async {
      expect(call.arguments, {
        'dir': '/data/pano/x',
        'width': 2048,
        'mode': 'fast',
        'logoAsset': 'assets/branding/nadir_logo.png',
      });
      return {'pano': '/data/pano/x/pano.jpg'};
    });
    await PanoCaptureChannel.stitch(
      dir: '/data/pano/x',
      width: 2048,
      mode: 'fast',
      logoAsset: 'assets/branding/nadir_logo.png',
    );
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
