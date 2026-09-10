import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/bozor/widgets/pano_source_sheet.dart';

/// 360° manba tanlash varag'i.
///
/// Bu Bozor sehrgaridagi «360 foto qo'shish» qatorining yagona kirish
/// nuqtasi. Test uning IKKALA yo'lni ham berishini qotiradi — capture
/// qo'shilgach galereya yo'lini tushirib qoldirish oson xato bo'lardi
/// va boshqa ilovada yasalgan panoramani yuklash imkoni yo'qolardi.
void main() {
  Widget host(void Function(PanoSource?) onResult) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async => onResult(await showPanoSourceSheet(context)),
          child: const Text('och'),
        ),
      ),
    ),
  );

  testWidgets('IKKALA yo‘l ham taklif qilinadi', (t) async {
    await t.pumpWidget(host((_) {}));
    await t.tap(find.text('och'));
    await t.pumpAndSettle();

    // Bundle yuklanmagan — `tr` xom kalitni qaytaradi, ya'ni kalitlar
    // bo'yicha topamiz.
    expect(find.text('bozor.pano.source.capture'), findsOneWidget);
    expect(find.text('bozor.pano.source.gallery'), findsOneWidget);
  });

  testWidgets('«Suratga olish» capture qaytaradi', (t) async {
    PanoSource? got;
    await t.pumpWidget(host((r) => got = r));
    await t.tap(find.text('och'));
    await t.pumpAndSettle();
    await t.tap(find.text('bozor.pano.source.capture'));
    await t.pumpAndSettle();
    expect(got, PanoSource.capture);
  });

  testWidgets('«Galereyadan» gallery qaytaradi', (t) async {
    PanoSource? got;
    await t.pumpWidget(host((r) => got = r));
    await t.tap(find.text('och'));
    await t.pumpAndSettle();
    await t.tap(find.text('bozor.pano.source.gallery'));
    await t.pumpAndSettle();
    expect(got, PanoSource.gallery);
  });

  testWidgets('BEKOR qilinsa null', (t) async {
    var called = false;
    PanoSource? got;
    await t.pumpWidget(host((r) {
      called = true;
      got = r;
    }));
    await t.tap(find.text('och'));
    await t.pumpAndSettle();
    // Varaqdan tashqariga bosish.
    await t.tapAt(const Offset(200, 60));
    await t.pumpAndSettle();
    expect(called, isTrue);
    expect(got, isNull);
  });

  test('i18n kalitlari uchala tilda bor', () {
    final raw = File('assets/i18n/bundle.json').readAsStringSync();
    final locales =
        (jsonDecode(raw) as Map<String, dynamic>)['locales']
            as Map<String, dynamic>;
    const keys = <String>[
      'bozor.pano.source.title',
      'bozor.pano.source.capture',
      'bozor.pano.source.capture_hint',
      'bozor.pano.source.gallery',
      'bozor.pano.source.gallery_hint',
    ];
    for (final lang in locales.keys) {
      final m = locales[lang] as Map<String, dynamic>;
      for (final k in keys) {
        expect(m.containsKey(k), isTrue, reason: '$lang: $k yo‘q');
        expect((m[k] as String).trim(), isNotEmpty, reason: '$lang: $k bo‘sh');
      }
    }
  });

  test('360 qatori CAPTURE ga ulangan, to‘g‘ridan galereyaga EMAS', () {
    // Foydalanuvchi aynan shuni so'ragan: tugma capture ekranini ochsin.
    // Ilgari u to'g'ridan `_pick(...)` chaqirardi.
    final src = File(
      'lib/features/bozor/screens/bozor_description_step_screen.dart',
    ).readAsStringSync();
    expect(src, contains('onAdd: _add360'));
    expect(src, contains('showPanoSourceSheet'));
    expect(src, contains('openPanoCapture'));
    // Eski to'g'ridan-galereya yo'li QOLMAGAN.
    expect(src, isNot(contains('_pick(_d.panoramas, multiple: false),\n')));
  });
}
