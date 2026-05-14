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
      search: query.isEmpty ? null : query,
      page: page,
      size: size,
    );

    final filtered = filters.isEmpty
        ? result.items
        : result.items.where(filters.matches).toList(growable: false);

    final consumed = offset + filtered.length;
    return MarketPage(
      items: filtered,
      hasMore: result.hasMore,
      nextOffset: consumed,
      totalCount: result.total,
    );
  }
}
