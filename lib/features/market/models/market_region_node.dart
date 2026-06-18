/// Market filtri uchun hudud daraxti: viloyat (`name`) → tumanlar (`districts`).
/// `GET /marketplace/regions/tree` dan keladi.
library;

class MarketRegionNode {
  const MarketRegionNode({required this.name, required this.districts});

  /// Viloyat nomi (akkordeon sarlavhasi).
  final String name;

  /// Shu viloyatga tegishli tuman nomlari (filtr qiymatlari).
  final List<String> districts;

  factory MarketRegionNode.fromJson(Map<String, dynamic> j) {
    final raw = (j['districts'] as List?) ?? const [];
    final districts = <String>[];
    for (final d in raw) {
      if (d is Map) {
        final n = (d['name'] ?? d['title']) as String?;
        if (n != null && n.trim().isNotEmpty) districts.add(n.trim());
      } else if (d is String && d.trim().isNotEmpty) {
        districts.add(d.trim());
      }
    }
    return MarketRegionNode(
      name: (j['name'] ?? '').toString().trim(),
      districts: districts,
    );
  }

  /// Barcha tuman nomlari (viloyat + tumanlari) — qidiruv/tanlash uchun.
  List<String> get allValues => [name, ...districts];

  Map<String, dynamic> toJson() => {
        'name': name,
        'districts': districts,
      };
}
