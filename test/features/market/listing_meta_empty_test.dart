import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/core/i18n/app_translations.dart';
import 'package:kadastr/features/market/models/market_listing.dart';
import 'package:kadastr/features/market/widgets/listing_card.dart';
import 'package:kadastr/features/market/widgets/listing_meta_pills.dart';

/// Hudud va maydon PROD'da ko'pincha BO'SH.
///
/// 2026-09-23 da `GET /marketplace/` dagi 265 modeldan 245 tasida hudud,
/// 213 tasida maydon yo'q edi. Karta esa ikkala qatorni HAR DOIM chizardi:
/// xarita ikonkasi yonida bo'sh joy, o'lchagich yonida esa «0 m²» — ya'ni
/// e'lon 0 kvadrat metr deb turardi. Ulashish matni va karusel allaqachon
/// bo'sh qiymatni tashlab ketardi; endi karta va detal nishonlari ham
/// shunday.
void main() {
  setUpAll(() {
    appTranslationsNotifier.value = AppTranslations.fromJson(
      jsonDecode(File('assets/i18n/bundle.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });
  tearDownAll(() => appTranslationsNotifier.value = AppTranslations.empty);

  const locale = Locale('uz');
  String m2() => tr(locale, 'bozor.unit.m²');

  MarketListing listing({String district = '', int areaM2 = 0}) =>
      MarketListing(
        id: '305',
        imageUrl: 'https://example.com/a.jpg',
        priceUzs: 0,
        title: 'Test',
        district: district,
        areaM2: areaM2,
        categoryId: 'interior',
      );

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: const [locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Karta masonry setkada CHEKSIZ balandlikda o'lchanadi.
      home: Scaffold(
        body: SizedBox(width: 320, child: ListView(children: [child])),
      ),
    ),
  );

  group('ListingCard', () {
    // Kartadagi YAGONA `SvgPicture` lar — shu ikki qatorning ikonkasi
    // («Batafsil» tugmasi Material `Icon` ishlatadi). Ya'ni ikonkalar soni
    // = chizilgan qatorlar soni, matni bo'sh bo'lsa ham.
    Finder metaIcons() => find.byType(SvgPicture);

    testWidgets('maydon yo\'q — «0 m²» YOZILMAYDI', (tester) async {
      await pump(
        tester,
        ListingCard(listing: listing(district: 'Nukus shahri'), onTap: (_) {}),
      );

      expect(find.text('Nukus shahri'), findsOneWidget);
      expect(find.text('0 ${m2()}'), findsNothing);
      expect(metaIcons(), findsOneWidget);
    });

    testWidgets('hudud yo\'q — bo\'sh qator chizilmaydi', (tester) async {
      await pump(
        tester,
        ListingCard(listing: listing(areaM2: 65), onTap: (_) {}),
      );

      expect(find.text('65 ${m2()}'), findsOneWidget);
      // Xarita ikonkasi yolg'iz qolmasin: qator butunlay yo'q.
      expect(metaIcons(), findsOneWidget);
    });

    testWidgets('ikkalasi ham yo\'q — ikkala qator ham yo\'q', (tester) async {
      await pump(tester, ListingCard(listing: listing(), onTap: (_) {}));

      expect(metaIcons(), findsNothing);
    });

    testWidgets('ikkalasi ham bor — ikkala qator chiziladi', (tester) async {
      await pump(
        tester,
        ListingCard(
          listing: listing(district: 'Toshkent shahri', areaM2: 579),
          onTap: (_) {},
        ),
      );

      expect(find.text('Toshkent shahri'), findsOneWidget);
      expect(find.text('579 ${m2()}'), findsOneWidget);
      expect(metaIcons(), findsNWidgets(2));
    });
  });

  group('ListingMetaPills', () {
    testWidgets('ikkala qiymat bo\'sh — hech narsa chizilmaydi', (
      tester,
    ) async {
      await pump(tester, const ListingMetaPills(district: '  ', areaM2: 0));

      expect(find.byType(ListingMetaPill), findsNothing);
    });

    testWidgets('faqat maydon — bitta nishon', (tester) async {
      await pump(tester, const ListingMetaPills(district: '', areaM2: 122));

      expect(find.byType(ListingMetaPill), findsOneWidget);
      expect(find.text('122 ${m2()}'), findsOneWidget);
    });

    testWidgets('faqat hudud — bitta nishon', (tester) async {
      await pump(
        tester,
        const ListingMetaPills(district: 'Navoiy shahri', areaM2: 0),
      );

      expect(find.byType(ListingMetaPill), findsOneWidget);
      expect(find.text('Navoiy shahri'), findsOneWidget);
    });
  });
}
