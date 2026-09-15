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
      final pano = File('$dir/pano.jpg')..writeAsBytesSync([1, 2, 3]);
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
    required PanoCaptureFn capture,
    required PanoStitchFn stitch,
    required BozorApi api,
    PanoPreviewFn? preview,
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
      final body = rec.uploads.single.body;
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

      expect(captures, 1, reason: '30 nishon qayta aylanilmaydi');
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

      final out = await pump(
        tester,
        capture: (_) async {
          captures++;
          return PanoCaptureResult(
            dir: captures == 1 ? dir1.path : dir2.path,
            frames: 1,
          );
        },
        stitch: st.fn,
        api: rec.api,
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
    },
  );

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

      // 2) pano.jpg tayyor → tikish ham YO'Q, to'g'ridan ko'rish → yuklash
      final dir2 = shotDir();
      File('${dir2.path}/pano.jpg').writeAsBytesSync([1, 2, 3]);
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
