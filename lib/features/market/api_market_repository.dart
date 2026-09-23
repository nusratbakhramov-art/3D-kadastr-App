import 'api_marketplace_service.dart';
import 'market_repository.dart';
import 'models/market_filters.dart';
import 'models/market_listing.dart';

/// Real backend repository — calls `GET /api/v1/marketplace/`. Pagination
/// uses page numbers (1-based). Mobile [MarketRepository] talks in offsets
/// to match the existing controller, so we translate.
class ApiMarketRepository implements MarketRepository {
  ApiMarketRepository({MarketplaceApiService? service})
    : _service = service ?? MarketplaceApiService();

  final MarketplaceApiService _service;

  /// Hududni SERVER filtrlay oladimi — shu qiymat bilan, yoki `null`.
  ///
  /// `GET /marketplace/` `region` ni biladi va uni `MarketModel.region` bilan
  /// TENGLIK bo'yicha solishtiradi — ilovadagi `MarketFilters.matches` ham
  /// aynan shunday solishtiradi, ya'ni javob to'plami o'zgarmaydi, faqat
  /// saralash serverga o'tadi. Bu muhim: ilova filtri faqat O'ZI YUKLAGAN
  /// sahifalarni ko'radi, server esa butun bazani — shu sababli sanoq ham
  /// («jami») to'g'ri chiqadi.
  ///
  /// ⚠️ Faqat BITTA hudud tanlanganda: endpoint bitta satr oladi, filtr
  /// oynasi esa ko'p tanlashga ruxsat beradi. Ko'p tanlansa eskicha —
  /// ilovada saralanadi.
  static String? _serverRegion(MarketFilters f) =>
      f.districts.length == 1 ? f.districts.first : null;

  @override
  Future<MarketPage> fetchPage({
    required String query,
    required String categoryId,
    required int offset,
    required int limit,
    MarketFilters filters = MarketFilters.empty,
  }) async {
    final size = limit;
    final page = (offset ~/ size) + 1;
    final result = await _service.listModels(
      category: categoryId == kMarketCategoryAll ? null : categoryId,
      region: _serverRegion(filters),
      search: query.isEmpty ? null : query,
      page: page,
      size: size,
    );

    final filtered = filters.isEmpty
        ? result.items
        : result.items.where(filters.matches).toList(growable: false);

    // ⚠️ KURSOR SERVER QAYTARGAN SONGA SURILADI, ko'rsatilgan songa EMAS.
    //
    // Sahifa raqami shu offsetdan hisoblanadi (`offset ~/ size + 1`), filtr
    // esa yozuvlarni ILOVADA tashlab yuboradi. Ilgari offset filtrlangan
    // songa surilardi, ya'ni tashlangan har bir yozuv kursorni ORQAGA
    // tortardi: filtr yoqilganda 1-sahifa qayta-qayta so'ralar, ro'yxat
    // esa umuman o'smasdi (cheksiz aylanish).
    final consumed = offset + result.items.length;
    return MarketPage(
      items: filtered,
      hasMore: result.hasMore,
      nextOffset: consumed,
      totalCount: result.total,
    );
  }
}
