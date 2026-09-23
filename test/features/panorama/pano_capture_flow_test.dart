import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadastr/core/i18n/app_translations.dart';
import 'package:kadastr/features/bozor/data/bozor_api.dart';
import 'package:kadastr/features/panorama/data/pano_capture_channel.dart';
import 'package:kadastr/features/panorama/screens/pano_capture_flow.dart';

/// 360° oqimi: capture → TELEFONDA tikish → faqat tayyor `pano.jpg` yuklanadi.
///
/// Qo'riqlanadigan shartnoma:
///  * serverga KADRLAR ketmaydi — faqat bitta fayl, `role=panorama`;
///  * natija `PanoUploaded(storageKey, url)` — server bergan kalit, `job:` emas;
///  * katalog FAQAT muvaffaqiyatli yuklashdan keyin o'chiriladi;
///  * qayta urinish faqat YIQILGAN bosqichdan: tikish yiqilsa capture
///    takrorlanmaydi, yuklash yiqilsa tikish takrorlanmaydi.
/// `testWidgets` + `runAsync` — haqiqiy async IO uchun (yuqoridagi izoh).
void testWidgetsAsync(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) => tester.runAsync(() => callback(tester)));
}

void main() {
  const key = 'listings/media/3/ab12cd34ef56.jpg';
  const url = 'https://storage.test/$key';

  setUpAll(() {
    appTranslationsNotifier.value = AppTranslations.fromJson(
      jsonDecode(File('assets/i18n/bundle.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });
  tearDownAll(() => appTranslationsNotifier.value = AppTranslations.empty);

  /// Nativ capture yozadigan katalog: `meta.json` + bitta kadr.
  Directory shotDir() {
    final d = Directory.systemTemp.createTempSync('pano_flow_');
    File('${d.path}/meta.json').writeAsStringSync('[{"file":"frame_0.jpg"}]');
    File('${d.path}/frame_0.jpg').writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
    return d;
  }

  /// `POST /listings/media` ni yozib boradigan API.
  ({BozorApi api, List<http.Request> uploads}) recorder({int failFirst = 0}) {
    final uploads = <http.Request>[];
    var failures = failFirst;
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/listings/media')) {
        uploads.add(req);
        if (failures > 0) {
          failures--;
          return http.Response('{"detail":"S3 yotibdi"}', 500);
        }
        return http.Response(
          '{"role":"panorama","files":[{"key":"$key","url":"$url"}]}',
          201,
        );
      }
      return http.Response('not found', 404);
    });
    return (api: BozorApi(client: client), uploads: uploads);
  }

  /// Tikish stub'i: `pano.jpg` yozadi, progress beradi; [failTimes] marta
  /// yiqiladi.
  ({PanoStitchFn fn, List<String> dirs}) stitcher({int failTimes = 0}) {
    final dirs = <String>[];
    var failures = failTimes;
    Future<PanoStitchResult> fn({
      required String dir,
      void Function(double p, String msg)? onProgress,
    }) async {
      dirs.add(dir);
      onProgress?.call(0.5, 'BA');
      if (failures > 0) {
        failures--;
        throw PlatformException(code: 'STITCH_FAILED', message: 'kam kadr');
      }
      final pano = File('$dir/pano.jpg')
        ..writeAsBytesSync(
          File('test/fixtures/panorama/pano_32.jpg').readAsBytesSync(),
        );
      onProgress?.call(1, 'done');
      return PanoStitchResult(panoPath: pano.path, previewPath: '');
    }

    return (fn: fn, dirs: dirs);
  }

  /// `pumpAndSettle` bu ekranda ISHLAMAYDI: aylanuvchi ko'rsatkich va 1 s
  /// ticker hech qachon «tinchimaydi». Shart bajarilguncha qadam-baqadam.
  ///
  /// ⚠️ Testlar `tester.runAsync` ichida yuradi: `cleanUp()` va katalog
  /// tekshiruvlari HAQIQIY `dart:io` async — FakeAsync zonasida hech qachon
  /// tugamaydi. `Future.delayed` real event loop'ga navbat beradi.
  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Ekranni ochib natijani qaytaradi.
  Future<PanoOutcome?> pump(
    WidgetTester tester, {
    PanoCaptureFn? capture,
    PanoStitchFn? stitch,
    required BozorApi api,
    PanoPreviewFn? preview,
    String? resumeDir,
    void Function(String dir)? onCaptured,
    void Function(String dir)? onDiscarded,
  }) async {
    PanoOutcome? outcome;
    var popped = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('uz'),
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              outcome = await Navigator.of(ctx).push<PanoOutcome>(
                MaterialPageRoute(
                  builder: (_) => PanoCaptureFlow(
                    resumeDir: resumeDir,
                    onCaptured: onCaptured,
                    onDiscarded: onDiscarded,
                    api: api,
                    capture: capture,
                    stitch: stitch,
                    preview:
                        preview ?? (_, _) async => PanoPreviewAction.accept,
                  ),
                ),
              );
              popped = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await pumpUntil(tester, () => popped);
    return outcome;
  }

  testWidgetsAsync(
    'happy path: bitta fayl yuklanadi, kalit qaytadi, katalog o\'chadi',
    (tester) async {
      final dir = shotDir();
      final rec = recorder();
      final st = stitcher();
      var captures = 0;

      final out = await pump(
        tester,
        capture: (_) async {
          captures++;
          return PanoCaptureResult(dir: dir.path, frames: 1);
        },
        stitch: st.fn,
        api: rec.api,
      );

      expect(captures, 1);
      expect(st.dirs, [dir.path]);
      expect(out, isNotNull);
      expect(out, isA<PanoUploaded>());
      final up = out! as PanoUploaded;
      expect(up.storageKey, key);
      expect(up.url, url);
      expect(
        up.storageKey.startsWith('job:'),
        isFalse,
        reason: 'server kaliti, vaqtinchalik havola emas',
      );

      // Faqat BITTA so'rov, BITTA fayl, `role=panorama` — kadrlar ketmagan.
      // (MockClient multipart'ni oddiy `Request` ga yig'adi — tanani o'qiymiz.)
      expect(rec.uploads, hasLength(1));
      final body = latin1.decode(rec.uploads.single.bodyBytes);
      expect(body, contains('name="role"\r\n\r\npanorama'));
      expect('filename="pano.jpg"'.allMatches(body), hasLength(1));
      expect(body, isNot(contains('frame_0.jpg')));

      expect(dir.existsSync(), isFalse, reason: 'yuklangach tozalanadi');
    },
  );

  testWidgetsAsync('bekor qilinsa null va hech narsa yuklanmaydi', (
    tester,
  ) async {
    final rec = recorder();
    final st = stitcher();
    final out = await pump(
      tester,
      capture: (_) async => null,
      stitch: st.fn,
      api: rec.api,
    );
    expect(out, isNull);
    expect(st.dirs, isEmpty);
    expect(rec.uploads, isEmpty);
  });

  testWidgetsAsync(
    'truncated saved JPEG is restitched before preview and upload',
    (tester) async {
      final dir = shotDir();
      final jpeg = File('test/fixtures/panorama/pano_32.jpg').readAsBytesSync();
      File(
        '${dir.path}/pano.jpg',
      ).writeAsBytesSync(jpeg.sublist(0, jpeg.length - 2));
      final rec = recorder();
      final st = stitcher();
      var previews = 0;
      final result = await pump(
        tester,
        resumeDir: dir.path,
        api: rec.api,
        stitch: st.fn,
        capture: (_) async => throw StateError('Saved frames must be reused'),
        preview: (_, _) async {
          previews++;
          return PanoPreviewAction.accept;
        },
      );
      expect(result, isA<PanoUploaded>());
      expect(st.dirs, [dir.path]);
      expect(previews, 1);
      expect(rec.uploads, hasLength(1));
    },
  );

  testWidgetsAsync('incomplete stitch result is never previewed or uploaded', (
    tester,
  ) async {
    final dir = shotDir();
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final rec = recorder();
    var previews = 0;
    await pump(
      tester,
      api: rec.api,
      capture: (_) async => PanoCaptureResult(dir: dir.path, frames: 17),
      stitch: ({required dir, onProgress}) async {
        File('$dir/pano.jpg').writeAsBytesSync([0xff, 0xd8, 0, 0]);
        return PanoStitchResult(
          panoPath: '$dir/pano.jpg',
          previewPath: '$dir/preview.jpg',
        );
      },
      preview: (_, _) async {
        previews++;
        return PanoPreviewAction.accept;
      },
    );
    expect(previews, 0);
    expect(rec.uploads, isEmpty);
    expect(dir.existsSync(), isTrue);
    expect(
      find.text(tr(const Locale('en'), 'bozor.pano.flow.failed')),
      findsWidgets,
    );
  });

  testWidgetsAsync(
    'retry after viewer failure requires acceptance before upload',
    (tester) async {
      final dir = shotDir();
      final rec = recorder();
      final st = stitcher();
      var previews = 0;
      await pump(
        tester,
        api: rec.api,
        stitch: st.fn,
        capture: (_) async => PanoCaptureResult(dir: dir.path, frames: 17),
        preview: (_, _) async {
          if (previews++ == 0) {
            throw PlatformException(
              code: 'VIEWER_FAILED',
              message: 'Viewer failed',
            );
          }
          return PanoPreviewAction.accept;
        },
      );
      expect(rec.uploads, isEmpty);
      await tester.tap(find.byType(FilledButton));
      await pumpUntil(tester, () => !dir.existsSync());
      expect(previews, 2);
      expect(st.dirs, [dir.path]);
      expect(rec.uploads, hasLength(1));
    },
  );

  testWidgetsAsync('missing server key keeps the completed capture for retry', (
    tester,
  ) async {
    final dir = shotDir();
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final api = BozorApi(
      client: MockClient(
        (_) async => http.Response(
          '{"files":[{"key":"","url":"https://storage.test/pano.jpg"}]}',
          201,
        ),
      ),
    );
    addTearDown(api.dispose);
    await pump(
      tester,
      api: api,
      stitch: stitcher().fn,
      capture: (_) async => PanoCaptureResult(dir: dir.path, frames: 17),
    );
    expect(dir.existsSync(), isTrue);
    expect(File('${dir.path}/pano.jpg').existsSync(), isTrue);
    expect(find.byType(FilledButton), findsOneWidget);
  });

  testWidgetsAsync(
    'production capture selects ultra-wide then previews and uploads only pano',
    (tester) async {
      final dir = shotDir();
      final rec = recorder();
      const channel = MethodChannel('kadastr/pano_capture');
      final methods = <String>[];
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        methods.add(call.method);
        final args = call.arguments as Map?;
        switch (call.method) {
          case 'ultraWideCapability':
            return {'available': true, 'cameraAuthorization': 'authorized'};
          case 'isSensorProcessingSupported':
            return true;
          case 'start':
            expect(args!['mode'], 'ultrawide');
            return {'dir': dir.path, 'frames': 17};
          case 'stitch':
            expect(args!['dir'], dir.path);
            expect(args.containsKey('width'), isFalse);
            expect(args['mode'], 'auto');
            expect(args['logoAsset'], 'assets/branding/nadir_logo.png');
            File('${dir.path}/pano.jpg').writeAsBytesSync(
              File('test/fixtures/panorama/pano_32.jpg').readAsBytesSync(),
            );
            File('${dir.path}/preview.jpg').writeAsBytesSync(
              File('test/fixtures/panorama/pano_32.jpg').readAsBytesSync(),
            );
            return {
              'pano': '${dir.path}/pano.jpg',
              'preview': '${dir.path}/preview.jpg',
              'width': 6144,
              'height': 3072,
              'frames': 17,
              'mode': 'mvs',
            };
          case 'preview':
            expect(args!['path'], '${dir.path}/pano.jpg');
            return {'action': 'accept'};
          default:
            fail('Unexpected channel method: ${call.method}');
        }
      });

      final out = await pump(
        tester,
        preview: (ctx, path) => PanoCaptureChannel.preview(ctx, path: path),
        api: rec.api,
      );
      expect(methods, [
        'ultraWideCapability',
        'isSensorProcessingSupported',
        'ultraWideCapability',
        'start',
        'stitch',
        'preview',
      ]);
      expect(out, isA<PanoUploaded>());
      final uploaded = out! as PanoUploaded;
      expect(uploaded.storageKey, key);
      expect(uploaded.url, url);
      expect(rec.uploads, hasLength(1));
      final body = latin1.decode(rec.uploads.single.bodyBytes);
      expect(body, contains('name="role"\r\n\r\npanorama'));
      expect('filename="pano.jpg"'.allMatches(body), hasLength(1));
      expect('filename="'.allMatches(body), hasLength(1));
      expect(body, isNot(contains('preview.jpg')));
      expect(body, isNot(contains('frame_0.jpg')));
      expect(body, isNot(contains('meta.json')));
      expect(dir.existsSync(), isFalse);
    },
  );

  testWidgetsAsync(
    'tikish yiqilsa: xato ekrani, qayta urinish CAPTURE\'ni takrorlamaydi',
    (tester) async {
      final dir = shotDir();
      final rec = recorder();
      final st = stitcher(failTimes: 1);
      var captures = 0;

      PanoOutcome? outcome;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('uz'),
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                outcome = await Navigator.of(ctx).push<PanoOutcome>(
                  MaterialPageRoute(
                    builder: (_) => PanoCaptureFlow(
                      api: rec.api,
                      capture: (_) async {
                        captures++;
                        return PanoCaptureResult(dir: dir.path, frames: 1);
                      },
                      stitch: st.fn,
                      preview: (_, _) async => PanoPreviewAction.accept,
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await pumpUntil(
        tester,
        () => find.text('kam kadr').evaluate().isNotEmpty,
      );

      // Xato ekrani: nativ xabar «kam kadr» xom PlatformException emas.
      expect(find.text('kam kadr'), findsOneWidget);
      expect(find.textContaining('PlatformException'), findsNothing);
      expect(
        dir.existsSync(),
        isTrue,
        reason: 'kadrlar qayta urinish uchun qoladi',
      );
      expect(rec.uploads, isEmpty);

      await tester.tap(find.byType(FilledButton)); // «Qayta urinish»
      await pumpUntil(tester, () => outcome != null);

      expect(captures, 1, reason: 'Saved frames avoid repeating capture');
      expect(st.dirs, hasLength(2), reason: 'faqat tikish takrorlanadi');
      expect((outcome as PanoUploaded?)?.storageKey, key);
      expect(dir.existsSync(), isFalse);
    },
  );

  testWidgetsAsync('yuklash yiqilsa: qayta urinish TIKISHni takrorlamaydi', (
    tester,
  ) async {
    final dir = shotDir();
    final rec = recorder(failFirst: 1);
    final st = stitcher();

    PanoOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('uz'),
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              outcome = await Navigator.of(ctx).push<PanoOutcome>(
                MaterialPageRoute(
                  builder: (_) => PanoCaptureFlow(
                    api: rec.api,
                    capture: (_) async =>
                        PanoCaptureResult(dir: dir.path, frames: 1),
                    stitch: st.fn,
                    preview: (_, _) async => PanoPreviewAction.accept,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await pumpUntil(
      tester,
      () => find.text('S3 yotibdi').evaluate().isNotEmpty,
    );

    expect(find.text('S3 yotibdi'), findsOneWidget);
    expect(
      File('${dir.path}/pano.jpg').existsSync(),
      isTrue,
      reason: 'tikilgan fayl qayta yuklash uchun qoladi',
    );

    await tester.tap(find.byType(FilledButton)); // «Qayta urinish»
    await pumpUntil(tester, () => outcome != null);

    expect(st.dirs, hasLength(1), reason: 'tikish bir marta');
    expect(rec.uploads, hasLength(2));
    expect((outcome as PanoUploaded?)?.storageKey, key);
    expect(dir.existsSync(), isFalse);
  });

  testWidgetsAsync(
    'natija ko\'rishda «Qayta tushirish» — kadrlar tashlanadi, capture qaytadan',
    (tester) async {
      final dir1 = shotDir();
      final dir2 = shotDir();
      final rec = recorder();
      final st = stitcher();
      var captures = 0;
      var previews = 0;
      final events = <String>[];

      final out = await pump(
        tester,
        capture: (_) async {
          captures++;
          events.add('capture:$captures');
          return PanoCaptureResult(
            dir: captures == 1 ? dir1.path : dir2.path,
            frames: 1,
          );
        },
        stitch: st.fn,
        api: rec.api,
        onCaptured: (dir) => events.add('captured:$dir'),
        onDiscarded: (dir) {
          expect(Directory(dir).existsSync(), isFalse);
          events.add('discarded:$dir');
        },
        preview: (_, path) async {
          previews++;
          expect(
            File(path).existsSync(),
            isTrue,
            reason: 'ko\'rish tikilgan faylni oladi',
          );
          return previews == 1
              ? PanoPreviewAction.retake
              : PanoPreviewAction.accept;
        },
      );

      expect(captures, 2, reason: 'retake → capture qaytadan');
      expect(st.dirs, [dir1.path, dir2.path]);
      expect(
        dir1.existsSync(),
        isFalse,
        reason: 'rad etilgan kadrlar o\'chadi',
      );
      expect(
        rec.uploads,
        hasLength(1),
        reason: 'faqat qabul qilingani yuklanadi',
      );
      expect((out as PanoUploaded?)?.storageKey, key);
      expect(dir2.existsSync(), isFalse);
      expect(events, [
        'capture:1',
        'captured:${dir1.path}',
        'discarded:${dir1.path}',
        'capture:2',
        'captured:${dir2.path}',
      ]);
    },
  );

  testWidgetsAsync('retake never resumes a discarded directory again', (
    tester,
  ) async {
    final dir = shotDir();
    File('${dir.path}/pano.jpg').writeAsBytesSync(
      File('test/fixtures/panorama/pano_32.jpg').readAsBytesSync(),
    );
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final rec = recorder();
    final st = stitcher();
    var previews = 0;
    var captures = 0;
    final discarded = <String>[];

    final out = await pump(
      tester,
      resumeDir: dir.path,
      capture: (_) async {
        captures++;
        expect(discarded, [dir.path]);
        return null;
      },
      stitch: st.fn,
      api: rec.api,
      preview: (_, _) async {
        previews++;
        return PanoPreviewAction.retake;
      },
      onDiscarded: (path) {
        discarded.add(path);
        // Cleanup is best effort. Simulate files remaining at the old path.
        dir.createSync(recursive: true);
        File('${dir.path}/pano.jpg').writeAsBytesSync(
          File('test/fixtures/panorama/pano_32.jpg').readAsBytesSync(),
        );
      },
    );

    expect(out, isNull);
    expect(previews, 1);
    expect(captures, 1);
    expect(st.dirs, isEmpty);
    expect(rec.uploads, isEmpty);
  });

  testWidgetsAsync('onCaptured — tikishdan OLDIN katalog beriladi', (
    tester,
  ) async {
    final dir = shotDir();
    final rec = recorder();
    final st = stitcher();
    String? captured;
    var stitchedWhenCaptured = false;

    PanoOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              outcome = await Navigator.of(ctx).push<PanoOutcome>(
                MaterialPageRoute(
                  builder: (_) => PanoCaptureFlow(
                    api: rec.api,
                    capture: (_) async =>
                        PanoCaptureResult(dir: dir.path, frames: 1),
                    stitch: ({required dir, onProgress}) {
                      stitchedWhenCaptured = captured != null;
                      return st.fn(dir: dir, onProgress: onProgress);
                    },
                    preview: (_, _) async => PanoPreviewAction.accept,
                    onCaptured: (d) => captured = d,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await pumpUntil(tester, () => outcome != null);

    expect(captured, dir.path);
    expect(stitchedWhenCaptured, isTrue, reason: 'onCaptured tikishdan oldin');
  });

  testWidgetsAsync('xato ekranidan chiqish — kadrlar SAQLANADI (PanoSaved)', (
    tester,
  ) async {
    final dir = shotDir();
    final rec = recorder();
    final st = stitcher(failTimes: 1);

    PanoOutcome? outcome;
    var popped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              outcome = await Navigator.of(ctx).push<PanoOutcome>(
                MaterialPageRoute(
                  builder: (_) => PanoCaptureFlow(
                    api: rec.api,
                    capture: (_) async =>
                        PanoCaptureResult(dir: dir.path, frames: 1),
                    stitch: st.fn,
                    preview: (_, _) async => PanoPreviewAction.accept,
                  ),
                ),
              );
              popped = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await pumpUntil(tester, () => find.text('kam kadr').evaluate().isNotEmpty);
    await tester.tap(find.byType(TextButton).last); // «Bekor qilish»
    await pumpUntil(tester, () => popped);

    expect(outcome, isA<PanoSaved>());
    final saved = outcome! as PanoSaved;
    expect(saved.dir, dir.path);
    expect(saved.stitched, isFalse);
    expect(saved.error, 'kam kadr');
    expect(dir.existsSync(), isTrue, reason: 'katalog o\'chirilmaydi');
  });

  testWidgetsAsync(
    'resumeDir — kadrlar bo\'lsa tikishdan, pano.jpg bo\'lsa yuklashdan',
    (tester) async {
      // 1) faqat kadrlar → capture YO'Q, tikish bor
      final dir1 = shotDir();
      final rec = recorder();
      final st = stitcher();
      var captures = 0;
      PanoOutcome? out1;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                out1 = await Navigator.of(ctx).push<PanoOutcome>(
                  MaterialPageRoute(
                    builder: (_) => PanoCaptureFlow(
                      resumeDir: dir1.path,
                      api: rec.api,
                      capture: (_) async {
                        captures++;
                        return null;
                      },
                      stitch: st.fn,
                      preview: (_, _) async => PanoPreviewAction.accept,
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await pumpUntil(tester, () => out1 != null);
      expect(captures, 0);
      expect(st.dirs, [dir1.path]);
      expect((out1 as PanoUploaded?)?.storageKey, key);

      // The route result resolves before its reverse transition finishes.
      // Finish that transition before replacing the app for the second case.
      await tester.pumpAndSettle();

      // 2) pano.jpg tayyor → tikish ham YO'Q, to'g'ridan ko'rish → yuklash
      final dir2 = shotDir();
      File('${dir2.path}/pano.jpg').writeAsBytesSync(
        File('test/fixtures/panorama/pano_32.jpg').readAsBytesSync(),
      );
      PanoOutcome? out2;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                out2 = await Navigator.of(ctx).push<PanoOutcome>(
                  MaterialPageRoute(
                    builder: (_) => PanoCaptureFlow(
                      resumeDir: dir2.path,
                      api: rec.api,
                      capture: (_) async {
                        captures++;
                        return null;
                      },
                      stitch: st.fn,
                      preview: (_, _) async => PanoPreviewAction.accept,
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await pumpUntil(tester, () => out2 != null);
      expect(captures, 0);
      expect(st.dirs, [dir1.path], reason: 'ikkinchisida tikish yo\'q');
      expect((out2 as PanoUploaded?)?.storageKey, key);
      expect(dir2.existsSync(), isFalse);
    },
  );

  test('yangi i18n kalitlari bundle\'da bor', () {
    for (final k in [
      'bozor.pano.flow.stitching',
      'bozor.pano.flow.uploading_pano',
      'bozor.pano.flow.stitch_hint',
      'bozor.pano.flow.ready',
      'bozor.pano.preview.title',
      'bozor.pano.preview.accept',
      'bozor.pano.preview.retake',
      'bozor.pano.tour.new_room',
      'bozor.pano.tour.room_n',
      'bozor.pano.cap.early_finish',
      'bozor.pano.cap.return_to',
      'bozor.pano.gate.local',
    ]) {
      for (final l in const [Locale('uz'), Locale('ru'), Locale('en')]) {
        expect(
          tr(l, k),
          isNot(k),
          reason: '$k ${l.languageCode} tarjimasi yo\'q',
        );
      }
    }
  });
}
