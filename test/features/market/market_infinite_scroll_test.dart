import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/core/i18n/app_translations.dart';
import 'package:kadastr/features/market/market_controller.dart';
import 'package:kadastr/features/market/market_repository.dart';
import 'package:kadastr/features/market/market_screen.dart';
import 'package:kadastr/features/market/models/market_filters.dart';
import 'package:kadastr/features/market/models/market_listing.dart';
import 'package:kadastr/features/market/widgets/listing_card.dart';
import 'package:kadastr/features/market/widgets/listing_skeleton_card.dart';

/// Cheksiz aylantirish EKRAN tomoni.
///
/// ⚠️ NEGA SHU TEST BOR (mijoz, 2026-09-23: «infinite scroll not working»).
/// Yuklashni `ScrollController` tinglovchisi boshlaydi, u esa faqat
/// AYLANTIRISH hodisasida ishlaydi. Ikki holatda hodisa umuman bo'lmaydi:
///   * birinchi sahifa ekranni to'ldirmasa — aylantirishga joy yo'q;
///   * foydalanuvchi eng pastda turganda ro'yxat o'ssa — `maxScrollExtent`
///     o'zgaradi, `pixels` esa yo'q, ya'ni xabar kelmaydi.
/// Ikkalasida ham ro'yxat jimgina to'xtab qolardi.
void main() {
  setUpAll(() {
    appTranslationsNotifier.value = AppTranslations.fromJson(
      jsonDecode(File('assets/i18n/bundle.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });
  tearDownAll(() => appTranslationsNotifier.value = AppTranslations.empty);

  MarketListing listing(int i) => MarketListing(
    id: '$i',
    imageUrl: '',
    priceUzs: 0,
    title: 'Model $i',
    district: 'Toshkent shahri',
    areaM2: 50 + i,
    categoryId: 'interior',
  );

  Future<void> pump(WidgetTester tester, MarketController c) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('uz'),
        supportedLocales: const [Locale('uz')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: MarketScreen(controller: c),
      ),
    );
  }

  testWidgets('birinchi sahifa ekranni to\'ldirmasa ham yuklash DAVOM etadi', (
    tester,
  ) async {
    // Ataylab BALAND ekran: bitta sahifa (12 ta) unga sig'ib ketadi, ya'ni
    // foydalanuvchi aylantira olmaydi va hech qanday hodisa bo'lmaydi.
    tester.view.physicalSize = const Size(1200, 9000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final repo = _FakeRepo(List.generate(60, listing));
    final c = MarketController(repository: repo);

    await pump(tester, c);
    await tester.pumpAndSettle();

    expect(
      repo.calls,
      greaterThan(1),
      reason: 'bitta sahifadan keyin to\'xtasa, foydalanuvchi qolgan '
          'e\'lonlarni HECH QACHON ko\'rmaydi',
    );
    expect(c.items.length, greaterThan(12));
    expect(find.byType(ListingCard), findsWidgets);
  });

  testWidgets('yuklanayotganda skeleton ko\'rinadi', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final repo = _FakeRepo(List.generate(60, listing), delay: true);
    final c = MarketController(repository: repo);

    await pump(tester, c);
    // Birinchi so'rov hali tugamagan — butun setka skeleton.
    await tester.pump();
    expect(find.byType(ListingSkeletonCard), findsWidgets);

    await tester.pumpAndSettle();
  });
}

class _FakeRepo implements MarketRepository {
  _FakeRepo(this.all, {this.delay = false});

  final List<MarketListing> all;
  final bool delay;
  int calls = 0;

  @override
  Future<MarketPage> fetchPage({
    required String query,
    required String categoryId,
    required int offset,
    required int limit,
    MarketFilters filters = MarketFilters.empty,
  }) async {
    calls++;
    if (delay) await Future<void>.delayed(const Duration(milliseconds: 40));
    final raw = all.skip(offset).take(limit).toList(growable: false);
    return MarketPage(
      items: raw,
      hasMore: offset + raw.length < all.length,
      nextOffset: offset + raw.length,
      totalCount: all.length,
    );
  }
}
