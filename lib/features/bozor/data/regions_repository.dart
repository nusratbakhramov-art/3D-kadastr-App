/// Viloyat/tuman ma'lumotnomasi — backenddan.
///
/// Manba: `GET /api/v1/marketplace/regions/tree` (`market_regions` jadvali,
/// adminkadan boshqariladi). ATAYLAB marketplace'niki: ikkinchi ro'yxat
/// yaratilsa ular bir-biridan uzoqlashib ketardi.
///
/// ⚠️ `id` — **int**. Ilgari bu yerda qo'lda yozilgan stub bor edi va uning
/// id'lari matn edi (`'tashkent_city'`); backend esa butun son qaytaradi va
/// e'lon `region_id`/`district_id` ni FK sifatida saqlaydi.
///
/// Nomlar tarjima qilinmaydi — API `?lang=` bo'yicha tayyor matn qaytaradi.
/// Davreest bu bo'limda ISHLATILMAYDI.
library;

import 'bozor_api.dart';

class Region {
  const Region({required this.id, required this.name});

  final int id;
  final String name;

  @override
  bool operator ==(Object other) => other is Region && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class District {
  const District({
    required this.id,
    required this.regionId,
    required this.name,
  });

  final int id;
  final int regionId;
  final String name;

  @override
  bool operator ==(Object other) => other is District && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

abstract class RegionsRepository {
  const RegionsRepository();

  Future<List<Region>> regions();

  Future<List<District>> districts(int regionId);
}

/// Daraxtni bir marta oladi va eslab qoladi — sehrgar ichida viloyat va
/// tuman ro'yxatlari ketma-ket ochiladi, ikki marta so'ramaymiz.
class ApiRegionsRepository extends RegionsRepository {
  ApiRegionsRepository({BozorApi? api}) : _api = api ?? BozorApi();

  final BozorApi _api;
  List<RegionNode>? _tree;

  Future<List<RegionNode>> _load() async => _tree ??= await _api.regionsTree();

  @override
  Future<List<Region>> regions() async => [
    for (final r in await _load()) Region(id: r.id, name: r.name),
  ];

  @override
  Future<List<District>> districts(int regionId) async {
    final tree = await _load();
    final region = tree.where((r) => r.id == regionId).firstOrNull;
    if (region == null) return const [];
    return [
      for (final d in region.districts)
        District(id: d.id, regionId: regionId, name: d.name),
    ];
  }
}
