import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadastr/core/i18n/app_translations.dart';
import 'package:kadastr/features/bozor/data/bozor_api.dart';
import 'package:kadastr/features/bozor/data/bozor_draft_codec.dart';
import 'package:kadastr/features/bozor/models/bozor_draft.dart';
import 'package:kadastr/features/bozor/models/tour_link.dart';
import 'package:kadastr/features/bozor/screens/bozor_description_step_screen.dart';
import 'package:kadastr/features/bozor/widgets/media_upload_row.dart';
import 'package:kadastr/features/panorama/data/pano_capture_channel.dart';
import 'package:kadastr/features/panorama/screens/pano_capture_flow.dart';
import 'package:kadastr/features/services/models/ai_baholash_bundle.dart';
import 'package:kadastr/widgets/app_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _Ending { uploaded, stitchFailed, uploadFailed, cancelled }

const _locale = Locale('uz');
const _channel = MethodChannel('kadastr/pano_capture');
const _before = 'listings/media/before.jpg';
const _after = 'listings/media/after.jpg';
const _uploaded = 'listings/media/replacement.jpg';
const _uploadedUrl =
    'https://storage.test/$_uploaded?signature=a%2Bb&name=room%20one';

void main() {
  setUpAll(() {
    appTranslationsNotifier.value = AppTranslations.fromJson(
      jsonDecode(File('assets/i18n/bundle.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });
  tearDownAll(() => appTranslationsNotifier.value = AppTranslations.empty);

  setUp(() {
    SharedPreferences.setMockInitialValues(
      {},
    ); // No authenticated/network draft saves.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == 'isARKitCaptureSupported' ||
              call.method == 'isViewerSupported') {
            return true;
          }
          if (call.method == 'ultraWideCapability') return {'available': false};
          throw StateError('Unexpected native call: ${call.method}');
        });
  });
  tearDown(() {
    AppToast.dismiss();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  for (final resume in [false, true]) {
    testWidgets(
      '${resume ? 'resumed local' : 'new ultra-wide'} capture → accept → upload → cleanup → Step 6 viewer → resumed draft viewer',
      (tester) async {
        await tester.runAsync(() async {
          await tester.binding.setSurfaceSize(const Size(800, 1600));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final dir = Directory.systemTemp.createTempSync('pano_preferred_');
          addTearDown(() {
            if (dir.existsSync()) dir.deleteSync(recursive: true);
          });
          final draft = BozorDraft(
            deal: DealType.sale,
            kind: PropertyKind.residential,
            type: PropertyType.apartment,
          );
          final d = draft.description;
          d.panoramas.add(_before);
          d.panoramaNames[_before] = 'Existing room';
          d.panoramaUrls[_before] = 'https://storage.test/before.jpg';
          d.uploadedMedia[_before] = _before;
          if (resume) {
            final ref = LocalPano.refOf(dir.path);
            File('${dir.path}/meta.json').writeAsStringSync('[]');
            File(
              'test/fixtures/panorama/pano_32.jpg',
            ).copySync('${dir.path}/pano.jpg');
            d.panoramas.add(ref);
            d.localPanoramas[ref] = LocalPano(
              dir: dir.path,
              stage: LocalPanoStage.stitched,
            );
            d.panoramaNames[ref] = RoomKind.living.label(_locale);
          }
          var captured = false;
          var viewed = false;
          var complete = false;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(_channel, (call) async {
                switch (call.method) {
                  case 'ultraWideCapability':
                    return {
                      'available': true,
                      'cameraAuthorization': 'authorized',
                    };
                  case 'isSensorProcessingSupported':
                    return true;
                  case 'isARKitCaptureSupported':
                    return false;
                  case 'isViewerSupported':
                    return true;
                  case 'start':
                    expectSync((call.arguments as Map)['mode'], 'ultrawide');
                    captured = true;
                    File('${dir.path}/meta.json').writeAsStringSync(
                      '[{"poseSource":"sensors:coremotion"}]',
                    );
                    return {'dir': dir.path, 'frames': 17};
                  case 'stitch':
                    expectSync(
                      (call.arguments as Map).containsKey('width'),
                      isFalse,
                    );
                    File('${dir.path}/pano.jpg').writeAsBytesSync(
                      File(
                        'test/fixtures/panorama/pano_32.jpg',
                      ).readAsBytesSync(),
                    );
                    File('${dir.path}/preview.jpg').writeAsBytesSync(
                      File(
                        'test/fixtures/panorama/pano_32.jpg',
                      ).readAsBytesSync(),
                    );
                    return {
                      'pano': '${dir.path}/pano.jpg',
                      'preview': '${dir.path}/preview.jpg',
                      'width': 6144,
                      'height': 3072,
                    };
                  case 'preview':
                    // Before accepting, the native preview gets the actual local
                    // JPEG. It must still exist, including when resuming a draft.
                    final path = (call.arguments as Map)['path'] as String;
                    expectSync(path, '${dir.path}/pano.jpg');
                    expectSync(File(path).existsSync(), isTrue);
                    expectSync(
                      (call.arguments as Map).containsKey('url'),
                      isFalse,
                    );
                    return {'action': 'accept'};
                  case 'tour':
                    viewed = true;
                    final rooms = ((call.arguments as Map)['panoramas'] as List)
                        .cast<Map>();
                    expectSync(rooms.map((r) => r['key']), [
                      _before,
                      _uploaded,
                    ]);
                    expectSync(rooms.map((r) => r['name']), [
                      'Existing room',
                      RoomKind.living.label(_locale),
                    ]);
                    expectSync(rooms.map((r) => r['url']), [
                      'https://storage.test/before.jpg',
                      _uploadedUrl,
                    ]);
                    expectSync(
                      rooms.every((r) => !r.containsKey('path')),
                      isTrue,
                    );
                    expectSync((call.arguments as Map)['startKey'], _uploaded);
                    expectSync(dir.existsSync(), isFalse);
                    return {'links': []};
                  default:
                    throw StateError('Unexpected native call ${call.method}');
                }
              });
          final api = BozorApi(
            client: MockClient((request) async {
              expectSync(request.url.path, '/api/v1/listings/media');
              expectSync(
                'filename="'.allMatches(latin1.decode(request.bodyBytes)),
                hasLength(1),
              );
              expectSync(
                latin1.decode(request.bodyBytes),
                contains('filename="pano.jpg"'),
              );
              return http.Response(
                jsonEncode({
                  'files': [
                    {'key': _uploaded, 'url': _uploadedUrl},
                  ],
                }),
                201,
              );
            }),
          );
          addTearDown(api.dispose);
          await tester.pumpWidget(
            MaterialApp(
              locale: _locale,
              supportedLocales: const [_locale],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: BozorDescriptionStepScreen(
                draft: draft,
                openCapture:
                    (context, {resumeDir, onCaptured, onDiscarded}) async {
                      expectSync(resumeDir, resume ? dir.path : null);
                      final result = await Navigator.of(context)
                          .push<PanoOutcome>(
                            MaterialPageRoute(
                              builder: (_) => PanoCaptureFlow(
                                api: api,
                                resumeDir: resumeDir,
                                onCaptured: onCaptured,
                                onDiscarded: onDiscarded,
                              ),
                            ),
                          );
                      complete = true;
                      return result;
                    },
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (resume) {
            _panoRow(tester).onOpen!(1);
          } else {
            _panoRow(tester).onAdd();
            await tester.pumpAndSettle();
            await tester.tap(find.text(tr(_locale, 'bozor.pano.rooms.add')));
            await tester.pumpAndSettle();
            await tester.tap(find.text(RoomKind.living.label(_locale)));
          }
          await _pumpUntil(tester, () => complete);
          await tester.pump();
          expect(captured, !resume);
          expect(d.panoramas, [_before, _uploaded]);
          expect(d.panoramaUrls[_uploaded], _uploadedUrl);
          expect(d.panoramaNames[_uploaded], RoomKind.living.label(_locale));
          expect(d.localPanoramas, isEmpty);
          _panoRow(tester).onOpen!(1);
          await _pumpUntil(tester, () => viewed);
          expect(dir.existsSync(), isFalse);
          await tester.pumpWidget(const SizedBox());
          // The stored URL (including escaped query bytes) survives a restart;
          // the room storage key never becomes a local file or download URL.
          final restored = draftFromPayload(draftToDraftPayload(draft));
          viewed = false;
          await tester.pumpWidget(
            MaterialApp(
              locale: _locale,
              supportedLocales: const [_locale],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: BozorDescriptionStepScreen(draft: restored),
            ),
          );
          await tester.pumpAndSettle();
          _panoRow(tester).onOpen!(1);
          await _pumpUntil(tester, () => viewed);
          await tester.pumpWidget(const SizedBox());
        });
      },
    );
  }

  testWidgets(
    'existing rooms remain viewable when all capture modes are unavailable',
    (tester) async {
      final draft = BozorDraft(
        deal: DealType.sale,
        kind: PropertyKind.residential,
        type: PropertyType.apartment,
      );
      draft.description.panoramas.add(_before);
      draft.description.panoramaUrls[_before] =
          'https://storage.test/before.jpg';
      var viewed = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            if (call.method == 'ultraWideCapability') {
              return {'available': false, 'cameraAuthorization': 'denied'};
            }
            if (call.method == 'isARKitCaptureSupported') return false;
            if (call.method == 'isViewerSupported') return true;
            if (call.method == 'tour') {
              viewed = true;
              return {'links': []};
            }
            throw StateError('Unexpected native call ${call.method}');
          });
      await tester.pumpWidget(
        MaterialApp(home: BozorDescriptionStepScreen(draft: draft)),
      );
      await tester.pumpAndSettle();
      _panoRow(tester).onOpen!(0);
      await tester.pumpAndSettle();
      expect(viewed, isTrue);
      expect(draft.description.panoramas, [_before]);
    },
  );

  for (final resume in [false, true]) {
    for (final ending in _Ending.values) {
      testWidgets(
        '${resume ? 'resumed' : 'new'} capture → retake → ${ending.name}',
        (tester) async {
          await tester.runAsync(
            () => _checkRetake(tester, resume: resume, ending: ending),
          );
        },
      );
    }
  }

  testWidgets('repeated retakes preserve the resumed room slot', (
    tester,
  ) async {
    await tester.runAsync(
      () => _checkRetake(
        tester,
        resume: true,
        ending: _Ending.uploaded,
        retakes: 2,
      ),
    );
  });
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(
    done(),
    isTrue,
    reason: 'Panorama flow did not reach the expected state',
  );
}

MediaUploadRow _panoRow(WidgetTester tester) => tester
    .widgetList<MediaUploadRow>(find.byType(MediaUploadRow))
    .singleWhere((row) => row.iconAsset == 'assets/icons/upload-360.svg');

Future<void> _checkRetake(
  WidgetTester tester, {
  required bool resume,
  required _Ending ending,
  int retakes = 1,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final root = Directory.systemTemp.createTempSync('description_pano_');
  addTearDown(() => root.deleteSync(recursive: true));
  final dirs = [
    for (var i = 0; i <= retakes; i++)
      Directory('${root.path}/shot_$i')..createSync(),
  ];
  for (final dir in dirs) {
    File('${dir.path}/meta.json').writeAsStringSync('[]');
  }
  if (resume) {
    File('${dirs.first.path}/pano.jpg').writeAsBytesSync(
      File('test/fixtures/panorama/pano_32.jpg').readAsBytesSync(),
    );
  }
  final refs = dirs.map((dir) => LocalPano.refOf(dir.path)).toList();
  final roomName = resume ? 'Saved room name' : RoomKind.living.label(_locale);
  final draft = BozorDraft(
    deal: DealType.sale,
    kind: PropertyKind.residential,
    type: PropertyType.apartment,
  )..title = 'Existing listing title';
  final d = draft.description;
  d.text = 'Existing description';
  d.youtubeUrl = 'https://youtu.be/existing';
  d.photos.add('existing-photo.jpg');
  d.planFiles.add('existing-plan.jpg');
  d.panoramas.addAll([_before, if (resume) refs.first, _after]);
  d.panoramaNames.addAll({_before: 'Before', _after: 'After'});
  d.panoramaUrls.addAll({
    _before: 'https://storage.test/before.jpg',
    _after: 'https://storage.test/after.jpg',
  });
  d.uploadedMedia.addAll({_before: _before, _after: _after});
  d.tourLinks.addAll(const [
    TourLink(from: _before, to: _after, yawDeg: 45, pitchDeg: 5),
    TourLink(from: _after, to: _before, yawDeg: 225, pitchDeg: -5),
  ]);
  final existingLinks = List<TourLink>.of(d.tourLinks);
  if (resume) {
    d.localPanoramas[refs.first] = LocalPano(
      dir: dirs.first.path,
      stage: LocalPanoStage.stitched,
    );
    d.panoramaNames[refs.first] = roomName;
  }

  List<String> withRoom(String ref) => [
    _before,
    if (resume) ref,
    _after,
    if (!resume) ref,
  ];

  var uploads = 0;
  final api = BozorApi(
    client: MockClient((request) async {
      expectSync(request.url.path, '/api/v1/listings/media');
      expectSync(
        latin1.decode(request.bodyBytes),
        contains('name="role"\r\n\r\npanorama'),
      );
      expectSync(
        'filename="pano.jpg"'.allMatches(latin1.decode(request.bodyBytes)),
        hasLength(1),
      );
      uploads++;
      if (ending == _Ending.uploadFailed) {
        return http.Response('{"detail":"Upload failed"}', 500);
      }
      return http.Response(
        jsonEncode({
          'files': [
            {'key': _uploaded, 'url': _uploadedUrl},
          ],
        }),
        201,
      );
    }),
  );
  addTearDown(api.dispose);

  var captureIndex = resume ? 1 : 0;
  var previews = 0;
  var completed = false;
  final discarded = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      locale: _locale,
      supportedLocales: const [_locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: BozorDescriptionStepScreen(
        draft: draft,
        openCapture: (context, {resumeDir, onCaptured, onDiscarded}) async {
          expectSync(resumeDir, resume ? dirs.first.path : null);
          final result = await Navigator.of(context).push<PanoOutcome>(
            MaterialPageRoute(
              builder: (_) => PanoCaptureFlow(
                resumeDir: resumeDir,
                onCaptured: onCaptured,
                onDiscarded: (dir) {
                  onDiscarded?.call(dir);
                  discarded.add(dir);
                },
                api: api,
                capture: (_) async {
                  if (captureIndex > 0) {
                    // Parent draft must be cleared before the replacement camera opens.
                    expectSync(d.panoramas, [_before, _after]);
                    expectSync(d.localPanoramas, isEmpty);
                    expectSync(d.panoramaNames, {
                      _before: 'Before',
                      _after: 'After',
                    });
                    expectSync(
                      discarded,
                      dirs.take(captureIndex).map((dir) => dir.path).toList(),
                    );
                    if (ending == _Ending.cancelled) return null;
                  }
                  return PanoCaptureResult(
                    dir: dirs[captureIndex++].path,
                    frames: 4,
                  );
                },
                stitch: ({required dir, onProgress}) async {
                  final ref = LocalPano.refOf(dir);
                  expectSync(d.panoramas, withRoom(ref));
                  expectSync(d.localPanoramas.keys, [ref]);
                  expectSync(d.roomName(ref), roomName);
                  if (dir == dirs.last.path && ending == _Ending.stitchFailed) {
                    throw PlatformException(
                      code: 'STITCH_FAILED',
                      message: 'Stitch failed',
                    );
                  }
                  final pano = File('$dir/pano.jpg')
                    ..writeAsBytesSync(
                      File(
                        'test/fixtures/panorama/pano_32.jpg',
                      ).readAsBytesSync(),
                    );
                  return PanoStitchResult(panoPath: pano.path, previewPath: '');
                },
                preview: (_, _) async => previews++ < retakes
                    ? PanoPreviewAction.retake
                    : PanoPreviewAction.accept,
              ),
            ),
          );
          completed = true;
          return result;
        },
      ),
    ),
  );
  await _pumpUntil(
    tester,
    () => tester
        .widgetList<MediaUploadRow>(find.byType(MediaUploadRow))
        .any((row) => row.iconAsset == 'assets/icons/upload-360.svg'),
  );
  if (resume) {
    _panoRow(tester).onOpen!(1);
  } else {
    _panoRow(tester).onAdd();
    await tester.pumpAndSettle();
    await tester.tap(find.text(tr(_locale, 'bozor.pano.rooms.add')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(roomName));
  }

  if (ending == _Ending.stitchFailed || ending == _Ending.uploadFailed) {
    await _pumpUntil(
      tester,
      () => find
          .text(tr(_locale, 'bozor.pano.flow.failed'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.tap(
      find.widgetWithText(TextButton, tr(_locale, 'common.cancel')),
    );
  }
  await _pumpUntil(tester, () => completed);
  await tester.pump();

  final saved =
      ending == _Ending.stitchFailed || ending == _Ending.uploadFailed;
  expect(d.panoramas, switch (ending) {
    _Ending.uploaded => withRoom(_uploaded),
    _Ending.cancelled => [_before, _after],
    _ => withRoom(refs.last),
  });
  expect(d.localPanoramas.keys, saved ? [refs.last] : isEmpty);
  expect(d.panoramaNames, {
    _before: 'Before',
    _after: 'After',
    if (saved) refs.last: roomName,
    if (ending == _Ending.uploaded) _uploaded: roomName,
  });
  expect(d.panoramaUrls, {
    _before: 'https://storage.test/before.jpg',
    _after: 'https://storage.test/after.jpg',
    if (ending == _Ending.uploaded) _uploaded: _uploadedUrl,
  });
  expect(d.uploadedMedia, {
    _before: _before,
    _after: _after,
    if (ending == _Ending.uploaded) _uploaded: _uploaded,
  });
  expect(d.tourLinks, existingLinks);
  expect(d.pendingPanoramas, isEmpty);
  for (final dir in dirs.take(retakes)) {
    expect(dir.existsSync(), isFalse);
  }
  if (saved) {
    expect(d.localPanoramas[refs.last]!.stage, LocalPanoStage.failed);
    expect(d.localPanoramas[refs.last]!.error, isNotEmpty);
    expect(dirs.last.existsSync(), isTrue);
  }
  expect(
    uploads,
    ending == _Ending.uploaded || ending == _Ending.uploadFailed ? 1 : 0,
  );

  // Existing serialization must retain the replacement, not the discarded capture.
  final restored = draftFromPayload(draftToDraftPayload(draft)).description;
  expect(restored.panoramas, d.panoramas);
  expect(restored.localPanoramas.keys, d.localPanoramas.keys);
  expect(restored.panoramaNames, d.panoramaNames);
  expect(draft.title, 'Existing listing title');
  expect(d.text, 'Existing description');
  expect(d.youtubeUrl, 'https://youtu.be/existing');
  expect(d.photos, ['existing-photo.jpg']);
  expect(d.planFiles, ['existing-plan.jpg']);

  AppToast.dismiss();
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  expect(tester.takeException(), isNull);
}
