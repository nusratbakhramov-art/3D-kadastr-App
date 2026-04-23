import 'models/market_listing.dart';

class MarketPage {
  const MarketPage({
    required this.items,
    required this.hasMore,
    required this.nextOffset,
  });

  final List<MarketListing> items;
  final bool hasMore;
  final int nextOffset;
}

class MarketRepository {
  const MarketRepository();

  static const List<String> _districts = [
    'Yashnabod tumani',
    'Mirzo Ulug\'bek tumani',
    'Yunusobod tumani',
    'Chilonzor tumani',
    'Sergeli tumani',
  ];

  static const List<String> _titles = [
    'Zamonaviy villa',
    'Panorama apartment',
    'Business center',
    'Savdo majmuasi',
    'Yangi loyiha',
    'Shinam hovli uy',
  ];

  static const List<String> _categories = [
    'residential',
    'nonresidential',
    'projects',
  ];

  static final List<MarketListing> _all = List.generate(120, (i) {
    final categoryId = _categories[i % _categories.length];
    final district = _districts[i % _districts.length];
    final title = _titles[i % _titles.length];

    return MarketListing(
      id: 'listing_$i',
      imageUrl: 'https://picsum.photos/seed/kadastr_$i/960/720',
      priceUzs: 120000 + (i % 17) * 18000,
      title: title,
      district: district,
      areaM2: 52 + (i % 11) * 7,
      categoryId: categoryId,
    );
  });

  Future<MarketPage> fetchListings({
    required String query,
    required String categoryId,
    required int offset,
    required int limit,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 520));

    final q = query.trim().toLowerCase();
    final filtered = _all
        .where((item) {
          final byCategory =
              categoryId == 'all' || item.categoryId == categoryId;
          final byQuery =
              q.isEmpty ||
              item.title.toLowerCase().contains(q) ||
              item.district.toLowerCase().contains(q);
          return byCategory && byQuery;
        })
        .toList(growable: false);

    final start = offset.clamp(0, filtered.length);
    final end = (start + limit).clamp(0, filtered.length);
    final pageItems = filtered.sublist(start, end);

    return MarketPage(
      items: pageItems,
      hasMore: end < filtered.length,
      nextOffset: end,
    );
  }
}
