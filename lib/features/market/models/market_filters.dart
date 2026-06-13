import 'market_listing.dart';

class MarketFilters {
  const MarketFilters({
    this.priceMin,
    this.priceMax,
    this.areaMin,
    this.areaMax,
    this.floorMin,
    this.floorMax,
    this.districts = const <String>{},
  });

  final int? priceMin;
  final int? priceMax;
  final int? areaMin;
  final int? areaMax;
  // Qavat oralig'i. Hozircha narx o'rniga ko'rsatiladi; e'londa qavat bo'lmasa
  // filtrlanmaydi (matches'da null'ni o'tkazib yuboramiz).
  final int? floorMin;
  final int? floorMax;
  final Set<String> districts;

  static const MarketFilters empty = MarketFilters();

  bool get isEmpty =>
      priceMin == null &&
      priceMax == null &&
      areaMin == null &&
      areaMax == null &&
      floorMin == null &&
      floorMax == null &&
      districts.isEmpty;

  int get activeCount {
    var n = 0;
    if (priceMin != null || priceMax != null) n++;
    if (areaMin != null || areaMax != null) n++;
    if (floorMin != null || floorMax != null) n++;
    if (districts.isNotEmpty) n++;
    return n;
  }

  bool matches(MarketListing l) {
    if (priceMin != null && l.priceUzs < priceMin!) return false;
    if (priceMax != null && l.priceUzs > priceMax!) return false;
    if (areaMin != null && l.areaM2 < areaMin!) return false;
    if (areaMax != null && l.areaM2 > areaMax!) return false;
    // Qavat faqat e'londa mavjud bo'lganda filtrlanadi.
    if (floorMin != null && l.floor != null && l.floor! < floorMin!) {
      return false;
    }
    if (floorMax != null && l.floor != null && l.floor! > floorMax!) {
      return false;
    }
    if (districts.isNotEmpty && !districts.contains(l.district)) return false;
    return true;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MarketFilters &&
        other.priceMin == priceMin &&
        other.priceMax == priceMax &&
        other.areaMin == areaMin &&
        other.areaMax == areaMax &&
        other.floorMin == floorMin &&
        other.floorMax == floorMax &&
        _setEq(other.districts, districts);
  }

  @override
  int get hashCode => Object.hash(
    priceMin,
    priceMax,
    areaMin,
    areaMax,
    floorMin,
    floorMax,
    Object.hashAllUnordered(districts),
  );

  static bool _setEq(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final v in a) {
      if (!b.contains(v)) return false;
    }
    return true;
  }
}

const List<String> kMarketDistricts = [
  'Yashnabod tumani',
  'Mirzo Ulug\'bek tumani',
  'Yunusobod tumani',
  'Chilonzor tumani',
  'Sergeli tumani',
];

const int kMarketPriceFloor = 100000;
const int kMarketPriceCeil = 500000;
const int kMarketAreaFloor = 30;
const int kMarketAreaCeil = 200;
const int kMarketFloorFloor = 1;
const int kMarketFloorCeil = 20;
