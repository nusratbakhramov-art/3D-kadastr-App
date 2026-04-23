import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/market/market_controller.dart';
import 'package:kadastr/features/market/market_repository.dart';
import 'package:kadastr/features/market/models/market_filters.dart';
import 'package:kadastr/features/market/models/market_listing.dart';

class _FakeRepo implements MarketRepository {
  _FakeRepo(this.items);

  final List<MarketListing> items;
  int calls = 0;
  bool fail = false;
  String? lastQuery;
  String? lastCategory;
  MarketFilters? lastFilters;

  @override
  Future<MarketPage> fetchPage({
    required String query,
    required String categoryId,
    required int offset,
    required int limit,
    MarketFilters filters = MarketFilters.empty,
  }) async {
    calls++;
    lastQuery = query;
    lastCategory = categoryId;
    lastFilters = filters;
    if (fail) throw Exception('boom');

    final filtered = items
        .where((l) {
          final byCat =
              categoryId == kMarketCategoryAll || l.categoryId == categoryId;
          final byQ = query.isEmpty || l.title.toLowerCase().contains(query);
          return byCat && byQ && filters.matches(l);
        })
        .toList(growable: false);

    final start = offset.clamp(0, filtered.length);
    final end = (start + limit).clamp(0, filtered.length);
    return MarketPage(
      items: filtered.sublist(start, end),
      hasMore: end < filtered.length,
      nextOffset: end,
      totalCount: filtered.length,
    );
  }
}

MarketListing _mk(int i, {String cat = 'residential', String title = 'Villa'}) {
  return MarketListing(
    id: 'id_$i',
    imageUrl: 'url',
    priceUzs: 100000 + i,
    title: title,
    district: 'Yashnabod tumani',
    areaM2: 60 + i,
    categoryId: cat,
  );
}

void main() {
  group('MarketController', () {
    test('initial status is initial before initialize()', () {
      final c = MarketController(repository: _FakeRepo(const []));
      expect(c.status, MarketStatus.initial);
      expect(c.items, isEmpty);
      c.dispose();
    });

    test('initialize() loads the first page', () async {
      final repo = _FakeRepo([for (var i = 0; i < 20; i++) _mk(i)]);
      final c = MarketController(repository: repo, pageSize: 5);

      final future = c.initialize();
      expect(c.status, MarketStatus.loading);
      await future;

      expect(c.status, MarketStatus.success);
      expect(c.items, hasLength(5));
      expect(c.hasMore, isTrue);
      expect(c.totalCount, 20);
      c.dispose();
    });

    test('loadMore() appends next page', () async {
      final repo = _FakeRepo([for (var i = 0; i < 12; i++) _mk(i)]);
      final c = MarketController(repository: repo, pageSize: 5);
      await c.initialize();
      expect(c.items, hasLength(5));

      await c.loadMore();
      expect(c.items, hasLength(10));
      expect(c.hasMore, isTrue);

      await c.loadMore();
      expect(c.items, hasLength(12));
      expect(c.hasMore, isFalse);
      c.dispose();
    });

    test('selectCategory refetches with new category', () async {
      final repo = _FakeRepo([
        _mk(0, cat: 'residential'),
        _mk(1, cat: 'projects'),
        _mk(2, cat: 'projects'),
      ]);
      final c = MarketController(repository: repo, pageSize: 10);
      await c.initialize();
      expect(c.items, hasLength(3));

      c.selectCategory('projects');
      await Future<void>.delayed(Duration.zero);
      expect(repo.lastCategory, 'projects');
      expect(c.items, hasLength(2));
      c.dispose();
    });

    test('onSearchInputChanged debounces then fetches', () async {
      final repo = _FakeRepo([
        _mk(0, title: 'villa'),
        _mk(1, title: 'panorama'),
      ]);
      final c = MarketController(
        repository: repo,
        pageSize: 10,
        searchDebounce: const Duration(milliseconds: 30),
      );
      await c.initialize();
      final initialCalls = repo.calls;

      c.onSearchInputChanged('pan');
      c.onSearchInputChanged('pano');
      c.onSearchInputChanged('panor');
      // Before debounce elapses
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(repo.calls, initialCalls);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(repo.calls, initialCalls + 1);
      expect(repo.lastQuery, 'panor');
      expect(c.items.single.title, 'panorama');
      c.dispose();
    });

    test('clearSearch resets and refetches when had query', () async {
      final repo = _FakeRepo([
        _mk(0, title: 'villa'),
        _mk(1, title: 'panorama'),
      ]);
      final c = MarketController(
        repository: repo,
        pageSize: 10,
        searchDebounce: const Duration(milliseconds: 20),
      );
      await c.initialize();
      c.onSearchInputChanged('pan');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(c.items, hasLength(1));

      final before = repo.calls;
      c.clearSearch();
      await Future<void>.delayed(Duration.zero);
      expect(repo.calls, before + 1);
      expect(c.items, hasLength(2));
      c.dispose();
    });

    test('error on first load surfaces status=error', () async {
      final repo = _FakeRepo([_mk(0)])..fail = true;
      final c = MarketController(repository: repo);
      await c.initialize();
      expect(c.status, MarketStatus.error);
      expect(c.error, isNotNull);

      repo.fail = false;
      await c.retry();
      expect(c.status, MarketStatus.success);
      expect(c.items, hasLength(1));
      c.dispose();
    });
  });
}
