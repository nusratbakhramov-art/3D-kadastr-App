import 'models/market_filters.dart';
import 'models/market_listing.dart';

class MarketPage {
  const MarketPage({
    required this.items,
    required this.hasMore,
    required this.nextOffset,
    required this.totalCount,
  });

  final List<MarketListing> items;
  final bool hasMore;
  final int nextOffset;
  final int totalCount;
}

abstract class MarketRepository {
  Future<MarketPage> fetchPage({
    required String query,
    required String categoryId,
    required int offset,
    required int limit,
    MarketFilters filters,
  });
}

class FakeMarketRepository implements MarketRepository {
  FakeMarketRepository({
    this.delay = const Duration(milliseconds: 520),
    int seed = 42,
    int count = 60,
  }) : _items = _generate(count, seed);

  final Duration delay;
  final List<MarketListing> _items;

  static const List<String> _titles = [
    'Zamonaviy villa',
    'Panorama kvartira',
    'Biznes markaz',
    'Savdo majmuasi',
    'Yangi loyiha',
    'Shinam hovli uy',
  ];

  static const List<String> _categoryIds = [
    'residential',
    'nonresidential',
    'projects',
  ];

  static const List<String> _descriptions = [
    '3D model ko\'rinishi. Zamonaviy loyiha, qulay rejalash.',
    'Shahar markazida, infratuzilma rivojlangan hududda.',
    'Yangi qurilgan, barcha kommunikatsiyalar mavjud.',
    'Oilaviy yashash uchun ideal, bolalar maydonchasi yaqin.',
    'Tijorat uchun mos, keng hudud va oson yetib borish.',
    'Premium sinf, dizayn asosida to\'liq tayyor.',
  ];

  static List<MarketListing> _generate(int count, int seed) {
    return List<MarketListing>.generate(count, (i) {
      final k = (i + seed) & 0x7FFFFFFF;
      final primary = 'https://picsum.photos/seed/kadastr_${i}_0/960/720';
      final gallery = List<String>.generate(
        5,
        (g) => 'https://picsum.photos/seed/kadastr_${i}_$g/960/720',
      );
      return MarketListing(
        id: 'listing_$i',
        imageUrl: primary,
        priceUzs: 120000 + (k % 17) * 15000,
        title: _titles[k % _titles.length],
        district: kMarketDistricts[k % kMarketDistricts.length],
        areaM2: 52 + (k % 11) * 7,
        floor: 1 + (k % 16),
        categoryId: _categoryIds[k % _categoryIds.length],
        gallery: gallery,
        description: _descriptions[k % _descriptions.length],
      );
    });
  }

  @override
  Future<MarketPage> fetchPage({
    required String query,
    required String categoryId,
    required int offset,
    required int limit,
    MarketFilters filters = MarketFilters.empty,
  }) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }

    final q = query.trim().toLowerCase();
    final filtered = _items
        .where((l) {
          final byCategory =
              categoryId == kMarketCategoryAll || l.categoryId == categoryId;
          if (!byCategory) return false;
          if (!filters.matches(l)) return false;
          if (q.isEmpty) return true;
          return l.title.toLowerCase().contains(q) ||
              l.district.toLowerCase().contains(q);
        })
        .toList(growable: false);

    final start = offset.clamp(0, filtered.length);
    final end = (start + limit).clamp(0, filtered.length);
    final slice = filtered.sublist(start, end);

    return MarketPage(
      items: slice,
      hasMore: end < filtered.length,
      nextOffset: end,
      totalCount: filtered.length,
    );
  }
}
