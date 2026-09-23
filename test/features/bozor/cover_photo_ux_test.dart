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

/// Muqova tanlovi KO'RINIB turishi kerak (mijoz sharhi, 2026-09-23).
///
/// Funksiyaning o'zi bor edi, lekin 72pt eskiz ostidagi 9pt yo'lakni hech
/// kim topmasdi — mijoz «juda yashirin» dedi. Bu yerda TEKSHIRILADIGAN
/// narsa mana shu xulq, piksel emas:
///   * har doim AYNAN BITTA rasm «Asosiy rasm» deb belgilangan;
///   * qolganlarida bosiladigan «Asosiy qilish» bor;
///   * bosilganda belgi DARHOL yangisiga ko'chadi va eskisidan ketadi;
///   * muqova o'chirilsa qoralamada O'LIK havola qolmaydi.
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
  String makeCover() => tr(locale, 'bozor.media.make_cover');

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

  testWidgets('AYNAN BITTA rasm muqova deb belgilanadi', (tester) async {
    await pump(tester, 3);

    expect(find.text(coverBadge()), findsOneWidget);
    expect(
      find.text(makeCover()),
      findsNWidgets(2),
      reason: 'qolgan har bir rasmda tanlash tugmasi bo\'lishi kerak',
    );
  });

  testWidgets('bitta rasmda nishon bor, tugma YO\'Q', (tester) async {
    await pump(tester, 1);

    expect(
      find.text(coverBadge()),
      findsOneWidget,
      reason: 'holat har doim ko\'rinsin — bitta rasm ham muqova',
    );
    expect(
      find.text(makeCover()),
      findsNothing,
      reason: 'almashtiradigan narsa yo\'q',
    );
  });

  testWidgets('«Asosiy qilish» bosilsa belgi DARHOL ko\'chadi', (tester) async {
    final draft = await pump(tester, 3);
    final photos = draft.description.photos;

    // Oxirgi eskiz — ro'yxatdagi 3-rasm.
    await tester.tap(find.text(makeCover()).last);
    await tester.pump();

    expect(draft.description.coverPhoto, photos[2]);
    expect(draft.description.coverPhotoIndex, 2);
    expect(
      find.text(coverBadge()),
      findsOneWidget,
      reason: 'eski muqova nishonini YO\'QOTISHI shart — ikkita «Asosiy '
          'rasm» bo\'lsa foydalanuvchi qaysi biri chiqishini bilmasdi',
    );
    expect(find.text(makeCover()), findsNWidgets(2));
  });

  testWidgets('muqova o\'chirilsa havola tozalanadi va belgi birinchisiga qaytadi', (
    tester,
  ) async {
    final draft = await pump(tester, 3);
    final photos = List<String>.from(draft.description.photos);

    await tester.tap(find.text(makeCover()).last);
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
    expect(find.text(coverBadge()), findsOneWidget);
  });

  testWidgets('BOSHQA rasm o\'chsa muqova o\'z joyida qoladi', (tester) async {
    final draft = await pump(tester, 3);
    final photos = List<String>.from(draft.description.photos);

    await tester.tap(find.text(makeCover()).last);
    await tester.pump();

    photoRow(tester).onRemove(0);
    await tester.pump();

    expect(draft.description.coverPhoto, photos[2]);
    expect(find.text(coverBadge()), findsOneWidget);
  });
}
