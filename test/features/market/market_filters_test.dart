import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/market/models/market_filters.dart';
import 'package:kadastr/features/market/models/market_listing.dart';

MarketListing _mk({
  int price = 200000,
  int area = 80,
  String district = 'Yashnabod tumani',
}) {
  return MarketListing(
    id: 'x',
    imageUrl: 'u',
    priceUzs: price,
    title: 't',
    district: district,
    areaM2: area,
    categoryId: 'residential',
  );
}

void main() {
  group('MarketFilters', () {
    test('empty matches any listing and activeCount=0', () {
      const f = MarketFilters.empty;
      expect(f.isEmpty, isTrue);
      expect(f.activeCount, 0);
      expect(f.matches(_mk()), isTrue);
    });

    test('price bounds are enforced', () {
      const f = MarketFilters(priceMin: 150000, priceMax: 250000);
      expect(f.activeCount, 1);
      expect(f.matches(_mk(price: 100000)), isFalse);
      expect(f.matches(_mk(price: 200000)), isTrue);
      expect(f.matches(_mk(price: 300000)), isFalse);
    });

    test('area bounds are enforced', () {
      const f = MarketFilters(areaMin: 60, areaMax: 100);
      expect(f.activeCount, 1);
      expect(f.matches(_mk(area: 50)), isFalse);
      expect(f.matches(_mk(area: 70)), isTrue);
      expect(f.matches(_mk(area: 110)), isFalse);
    });

    test('districts whitelist is enforced', () {
      final f = MarketFilters(districts: {'Yashnabod tumani'});
      expect(f.activeCount, 1);
      expect(f.matches(_mk(district: 'Yashnabod tumani')), isTrue);
      expect(f.matches(_mk(district: 'Chilonzor tumani')), isFalse);
    });

    test('activeCount adds up across groups', () {
      final f = MarketFilters(
        priceMin: 100000,
        areaMax: 100,
        districts: {'Yashnabod tumani'},
      );
      expect(f.activeCount, 3);
    });

    test('equality ignores set identity', () {
      final a = MarketFilters(districts: {'A', 'B'});
      final b = MarketFilters(districts: {'B', 'A'});
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });
}
