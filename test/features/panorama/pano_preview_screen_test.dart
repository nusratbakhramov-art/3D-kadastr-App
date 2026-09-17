import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/core/i18n/app_translations.dart';
import 'package:kadastr/features/panorama/data/pano_capture_channel.dart';
import 'package:kadastr/features/panorama/screens/pano_preview_screen.dart';

void main() {
  setUp(() {
    appTranslationsNotifier.value = AppTranslations.fromJson(
      jsonDecode(File('assets/i18n/bundle.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });
  tearDown(() => appTranslationsNotifier.value = AppTranslations.empty);

  testWidgets('missing panorama cannot be accepted but can be retaken', (
    tester,
  ) async {
    PanoPreviewAction? action;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                action = await Navigator.of(context).push<PanoPreviewAction>(
                  MaterialPageRoute(
                    builder: (_) =>
                        const PanoPreviewScreen(path: '/missing/pano.jpg'),
                  ),
                );
              },
              child: const Text('Preview'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    final accept = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(accept.onPressed, isNull);
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    expect(action, PanoPreviewAction.retake);
  });

  testWidgets('decoded local panorama can be accepted', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: PanoPreviewScreen(
            path: File('test/fixtures/panorama/pano_32.jpg').absolute.path,
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (tester.widget<FilledButton>(find.byType(FilledButton)).onPressed !=
            null) {
          break;
        }
      }
    });
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });
}
