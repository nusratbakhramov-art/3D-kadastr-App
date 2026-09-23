import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:kadastr/features/market/api_market_repository.dart';
import 'package:kadastr/features/market/api_marketplace_service.dart';
import 'package:kadastr/features/market/market_controller.dart';
import 'package:kadastr/features/market/market_repository.dart';
import 'package:kadastr/features/market/models/market_filters.dart';
import 'package:kadastr/features/market/models/market_listing.dart';

/// Filtr yoqilganda ro'yxat OXIRIGACHA aylanishi kerak.
///
/// ⚠️ NEGA SHU TEST BOR (2026-09-23, qurilmada ko'rindi). Sahifa raqami
/// offsetdan hisoblanadi (`offset ~/ size + 1`), filtr esa yozuvlarni
/// ILOVADA tashlab yuboradi. `nextOffset` filtrlangan songa surilardi, ya'ni
/// tashlangan har bir yozuv kursorni ORQAGA tortardi. Natijada filtr bilan
/// 1-sahifa CHEKSIZ qayta so'ralardi va ro'yxat umuman o'smasdi.
///
/// Shuning uchun bu yerda soxta HTTP orqali AYNAN so'ralgan sahifa raqamlari
/// tekshiriladi — `MarketPage.items` ni sanash buni ushlamaydi.
void main() {
  const size = 12;
  const total = 50;

  /// `id` juft bo'lsa maydon 100 m², toq bo'lsa 0 — ya'ni quyidagi filtr
  /// har sahifaning YARMINI tashlab yuboradi.
  Map<String, Object?> model(int id) => {
    'id': id,
    'name': 'Model $id',
    'region': 'Toshkent shahri',
    'area': id.isEven ? '100.00' : null,
    'price': null,
    'category': 'interior',
    'preview_image_url': null,
    'scenes': <Object?>[],
    'files': <Object?>[],
    'is_free': true,
  };

  late List<int> requestedPages;

  ApiMarketRepository repo() {
    requestedPages = [];
    final client = MockClient((req) async {
      final page = int.parse(req.url.queryParameters['page']!);
      requestedPages.add(page);
      final start = (page - 1) * size;
      final items = [
        for (var i = start; i < start + size && i < total; i++) model(i),
      ];
      return http.Response(
        jsonEncode({'items': items, 'total': total, 'page': page, 'size': size}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    return ApiMarketRepository(
      service: MarketplaceApiService(
        client: client,
        baseUrl: 'https://test.local/api/v1',
        locale: 'uz',
      ),
    );
  }

  /// Ekran qiladigan ishni takrorlaydi: `nextOffset` ni keyingi so'rovga
  /// uzatib, `hasMore` tugaguncha yuradi.
  Future<List<int>> walk(MarketFilters filters, {int maxRequests = 30}) async {
    final r = repo();
    final seen = <int>[];
    var offset = 0;
    for (var i = 0; i < maxRequests; i++) {
      final page = await r.fetchPage(
        query: '',
        categoryId: 'all',
        offset: offset,
        limit: size,
        filters: filters,
      );
      seen.addAll(page.items.map((l) => int.parse(l.id)));
      offset = page.nextOffset;
      if (!page.hasMore) break;
    }
    return seen;
  }

  test('filtrsiz — har sahifa BIR marta, dublikatsiz', () async {
    final seen = await walk(MarketFilters.empty);

    expect(requestedPages, [1, 2, 3, 4, 5]);
    expect(seen.length, total);
    expect(seen.toSet().length, total);
  });

  test('filtr YARIM sahifani tashlasa ham kursor OLDINGA yuradi', () async {
    // 30..200 m² — toq `id` li yozuvlar (maydonsiz) tashlanadi.
    final seen = await walk(
      const MarketFilters(areaMin: 30, areaMax: 200),
    );

    expect(
      requestedPages,
      [1, 2, 3, 4, 5],
      reason: 'sahifa raqami hech qachon TAKRORLANMASLIGI kerak — takrorlansa '
          'foydalanuvchi uchun aylantirish butunlay to\'xtaydi',
    );
    expect(seen, [for (var i = 0; i < total; i += 2) i]);
    expect(seen.toSet().length, seen.length, reason: 'dublikat bo\'lmasin');
  });

  test('filtr BUTUN sahifani tashlasa ham oxiriga yetadi', () async {
    // Hech bir yozuv mos kelmaydi: har sahifa bo'sh qaytadi, lekin kursor
    // baribir surilishi va ro'yxat oxiriga yetishi kerak.
    final seen = await walk(const MarketFilters(areaMin: 100000));

    expect(requestedPages, [1, 2, 3, 4, 5]);
    expect(seen, isEmpty);
  });

  _controllerTests();
  _regionTests();
}

/// Kontroller darajasi: BIRINCHI sahifa ham to'liq filtrlanib ketishi mumkin.
///
/// Bu alohida yo'l: `loadMore` ni aylantirish chaqiradi, birinchi sahifani esa
/// ekran ochilishi. Birinchi sahifa bo'sh qaytsa ro'yxat umuman chizilmaydi,
/// ya'ni aylantirish ham bo'lmaydi va `loadMore` HECH QACHON chaqirilmaydi —
/// foydalanuvchi mos e'lonlar bor bo'lsa ham «Hech narsa topilmadi» ko'radi.
class _RawPagingRepo implements MarketRepository {
  _RawPagingRepo(this.all);

  final List<MarketListing> all;
  final List<int> requestedOffsets = [];

  @override
  Future<MarketPage> fetchPage({
    required String query,
    required String categoryId,
    required int offset,
    required int limit,
    MarketFilters filters = MarketFilters.empty,
  }) async {
    requestedOffsets.add(offset);
    final raw = all.skip(offset).take(limit).toList(growable: false);
    final kept = raw.where(filters.matches).toList(growable: false);
    // `ApiMarketRepository` kabi: kursor XOM songa suriladi.
    return MarketPage(
      items: kept,
      hasMore: offset + raw.length < all.length,
      nextOffset: offset + raw.length,
      totalCount: all.length,
    );
  }
}

MarketListing _listing(int id, int area) => MarketListing(
  id: '$id',
  imageUrl: '',
  priceUzs: 0,
  title: 'Model $id',
  district: '',
  areaM2: area,
  categoryId: 'interior',
);

void _controllerTests() {
  test('birinchi sahifa TO\'LIQ filtrlansa ham mos e\'lon topiladi', () async {
    // Yagona mos e'lon 30-o'rinda — birinchi sahifadan (12 ta) TASHQARIDA.
    final all = [
      for (var i = 0; i < 60; i++) _listing(i, i == 30 ? 150 : 0),
    ];
    final repo = _RawPagingRepo(all);
    final c = MarketController(repository: repo);

    await c.initialize();
    c.applyFilters(const MarketFilters(areaMin: 100, areaMax: 200));
    // Filtr qo'llanishi qayta yuklashni boshlaydi.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      c.items.map((l) => l.id),
      contains('30'),
      reason: 'ilova filtri serverdagi sahifalash ustidan ishlaydi — birinchi '
          'sahifa bo\'sh chiqsa, ro\'yxat chizilmaydi va aylantirish '
          'bo\'lmaydi, ya\'ni `loadMore` hech qachon chaqirilmaydi',
    );
  });
}

/// Hudud filtri SERVERGA uzatiladi (bitta hudud tanlanganda).
///
/// `GET /marketplace/` `region` ni qo'llab-quvvatlaydi va uni
/// `MarketModel.region` bilan tenglik bo'yicha solishtiradi — ya'ni
/// ilovadagi `MarketFilters.matches` bilan BIR XIL. Ilgari ilova uni
/// yubormasdi va hududni o'zi saralardi: natijada «jami» soni noto'g'ri
/// chiqardi va faqat yuklangan sahifalar ichidan qidirilardi.
///
/// Test SO'ROV parametrini tekshiradi — natijani sanash buni ushlamaydi,
/// chunki ikkala yo'l ham bir xil to'plamni beradi.
void _regionTests() {
  const size = 12;

  Future<List<String?>> regionParams(MarketFilters filters) async {
    final seen = <String?>[];
    final client = MockClient((req) async {
      seen.add(req.url.queryParameters['region']);
      return http.Response(
        jsonEncode({'items': [], 'total': 0, 'page': 1, 'size': size}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final repo = ApiMarketRepository(
      service: MarketplaceApiService(
        client: client,
        baseUrl: 'https://test.local/api/v1',
        locale: 'uz',
      ),
    );
    await repo.fetchPage(
      query: '',
      categoryId: 'all',
      offset: 0,
      limit: size,
      filters: filters,
    );
    return seen;
  }

  test('bitta hudud — so\'rovga `region` qo\'shiladi', () async {
    expect(
      await regionParams(const MarketFilters(districts: {'Nukus shahri'})),
      ['Nukus shahri'],
    );
  });

  test('hudud tanlanmagan — `region` YUBORILMAYDI', () async {
    expect(await regionParams(MarketFilters.empty), [null]);
  });

  test('bir nechta hudud — server bitta satr oladi, ilovada saralanadi', () async {
    expect(
      await regionParams(
        const MarketFilters(districts: {'Nukus shahri', 'Navoiy shahri'}),
      ),
      [null],
    );
  });
}
