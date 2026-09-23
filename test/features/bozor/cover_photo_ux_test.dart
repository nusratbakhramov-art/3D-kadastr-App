import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/core/i18n/app_translations.dart';
import 'package:kadastr/features/bozor/models/bozor_draft.dart';
import 'package:kadastr/features/bozor/screens/bozor_description_step_screen.dart';
import 'package:kadastr/features/bozor/widgets/media_upload_row.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'param_schema_fixture.dart';

/// MUQOVA SAHNASI (mijoz tanlagan dizayn, 2026-09-24).
///
/// Yo'lakdagi yozuvlar olib tashlandi: tanlangan rasm endi yuqorida KATTA
/// ko'rsatiladi, eskizni bosish esa uni muqova qiladi. Tekshiriladigan
/// xulq:
///   * sahna har doim AYNAN BITTA — hozirgi muqovani ko'rsatadi;
///   * eskizni bosish muqovani DARHOL almashtiradi;
///   * muqova o'chirilsa qoralamada O'LIK havola qolmaydi;
///   * boshqa rasm o'chsa muqova joyida qoladi.
///
/// `cover_photo_choice_test.dart` esa modelning o'zini (havola/indeks
/// qoidasi, qoralamaga saqlanishi) tekshiradi — ikkisi bir-birini
/// takrorlamaydi.
void main() {
  setUpAll(loadRealParamSchema);

  setUpAll(() {
    appTranslationsNotifier.value = AppTranslations.fromJson(
      jsonDecode(File('assets/i18n/bundle.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });
  tearDownAll(() => appTranslationsNotifier.value = AppTranslations.empty);

  // Tarmoqqa/qoralama saqlashga chiqmaslik uchun.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const locale = Locale('uz');
  // ⚠️ `setUpAll` DAN KEYIN o'qiladi: `main()` tanasida chaqirilsa bundle
  // hali yuklanmagan bo'ladi va `tr` kalitning O'ZINI qaytaradi.
  String coverBadge() => tr(locale, 'bozor.media.cover_badge');
  String coverHint() => tr(locale, 'bozor.media.cover_hint');

  /// Rasm eskizi `Image.file` bilan chiziladi — fayl bo'lishi kerak, mazmuni
  /// esa ahamiyatsiz (rasm ochilmasa `errorBuilder` ikonka beradi).
  List<String> tempPhotos(int n) {
    final dir = Directory.systemTemp.createTempSync('cover_ux_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    return [
      for (var i = 0; i < n; i++)
        (File('${dir.path}/photo_$i.jpg')..writeAsStringSync('x')).path,
    ];
  }

  BozorDraft draftWith(List<String> photos) {
    final d = BozorDraft(
      deal: DealType.sale,
      kind: PropertyKind.residential,
      type: PropertyType.apartment,
    );
    d.description.photos.addAll(photos);
    return d;
  }

  Future<BozorDraft> pump(WidgetTester tester, int photos) async {
    // Sakkizta qator sukutdagi ekranga sig'maydi va ko'rinmagan element
    // QURILMAYDI — `find.text` esa faqat qurilganini topadi.
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final draft = draftWith(tempPhotos(photos));
    await tester.pumpWidget(
      MaterialApp(
        // Ekran tilni `Localizations.localeOf` dan oladi — delegatlarsiz
        // `MaterialApp` o'zbekchani qo'llamaydi va inglizchaga tushadi.
        locale: locale,
        supportedLocales: const [locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: BozorDescriptionStepScreen(draft: draft),
      ),
    );
    await tester.pump();
    return draft;
  }

  /// Foto qatori — muqova tushunchasi FAQAT unda bor (planirovka va 360° da
  /// yo'q), shuning uchun uni `coverLabel` bo'yicha topamiz.
  MediaUploadRow photoRow(WidgetTester tester) => tester
      .widgetList<MediaUploadRow>(find.byType(MediaUploadRow))
      .firstWhere((r) => r.coverLabel != null);

  /// Foto qatoridagi [i]-eskiz.
  ///
  /// ⚠️ Aynan TASMA (`ListView`) ichidan izlaymiz. Qatorning o'zidan
  /// izlansa birinchi topilgan narsa SAHNA bo'lib chiqadi (u ham bosiladi)
  /// va hamma indeks bittaga suriladi. Har eskizda ikkita bosish nishoni
  /// bor: rasmning o'zi va o'chirish tugmasi — shuning uchun `i * 2`.
  Finder thumbAt(WidgetTester tester, int i) => find
      .descendant(
        of: find.descendant(
          of: find.byWidget(photoRow(tester)),
          matching: find.byType(ListView),
        ),
        matching: find.byType(GestureDetector),
      )
      .at(i * 2);

  /// Sahna — muqovani KATTA ko'rsatadigan blok. Uni o'z nishoni bo'yicha
  /// topamiz: «Asosiy rasm» yozuvi endi FAQAT shu yerda bo'ladi.
  Finder stage() => find.text(coverBadge());

  /// Sahnadagi rasm — foto qatoridagi eng birinchi `Image.file`.
  String stagePath(WidgetTester tester) {
    final img = tester.widgetList<Image>(find.byType(Image)).first;
    return ((img.image) as FileImage).file.path;
  }

  testWidgets('sahna AYNAN BITTA va hozirgi muqovani ko\'rsatadi', (
    tester,
  ) async {
    final draft = await pump(tester, 3);

    expect(stage(), findsOneWidget);
    expect(find.text(coverHint()), findsOneWidget);
    expect(stagePath(tester), draft.description.photos.first);
  });

  testWidgets('bitta rasmda ham sahna bor', (tester) async {
    await pump(tester, 1);
    expect(stage(), findsOneWidget);
  });

  testWidgets('eskizni bosish muqovani DARHOL almashtiradi', (tester) async {
    final draft = await pump(tester, 3);
    final photos = List<String>.from(draft.description.photos);

    await tester.tap(thumbAt(tester, 2));
    await tester.pump();

    expect(draft.description.coverPhoto, photos[2]);
    expect(draft.description.coverPhotoIndex, 2);
    expect(
      stagePath(tester),
      photos[2],
      reason: 'sahna tanlovni darhol ko\'rsatmasa, dizaynning butun ma\'nosi '
          'yo\'qoladi — u aynan natijani ko\'rsatish uchun qo\'yilgan',
    );
    expect(stage(), findsOneWidget, reason: 'nishon faqat sahnada bo\'lsin');
  });

  testWidgets('muqova o\'chirilsa havola tozalanadi va birinchisiga qaytadi', (
    tester,
  ) async {
    final draft = await pump(tester, 3);
    final photos = List<String>.from(draft.description.photos);

    await tester.tap(thumbAt(tester, 2));
    await tester.pump();
    expect(draft.description.coverPhoto, photos[2]);

    photoRow(tester).onRemove(2);
    await tester.pump();

    expect(
      draft.description.coverPhoto,
      isNull,
      reason: 'o\'chirilgan faylga havola qolsa, o\'sha fayl qayta '
          'tanlanganda muqova kutilmaganda unga qaytardi',
    );
    expect(draft.description.coverPhotoIndex, 0);
    expect(stagePath(tester), photos[0]);
  });

  testWidgets('BOSHQA rasm o\'chsa muqova o\'z joyida qoladi', (tester) async {
    final draft = await pump(tester, 3);
    final photos = List<String>.from(draft.description.photos);

    await tester.tap(thumbAt(tester, 2));
    await tester.pump();

    photoRow(tester).onRemove(0);
    await tester.pump();

    expect(draft.description.coverPhoto, photos[2]);
    expect(stagePath(tester), photos[2]);
  });
}
