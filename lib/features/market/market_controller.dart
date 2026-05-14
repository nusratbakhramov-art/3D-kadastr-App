import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_market_repository.dart';
import 'api_marketplace_service.dart';
import 'market_repository.dart';
import 'models/market_filters.dart';
import 'models/market_listing.dart';

enum MarketStatus { initial, loading, success, error }

class MarketController extends ChangeNotifier {
  MarketController({
    required MarketRepository repository,
    MarketplaceApiService? categoriesService,
    Duration searchDebounce = const Duration(milliseconds: 400),
    int pageSize = 12,
  }) : _repository = repository,
       _categoriesService = categoriesService,
       _debounce = searchDebounce,
       _pageSize = pageSize;

  final MarketRepository _repository;
  final MarketplaceApiService? _categoriesService;
  final Duration _debounce;
  final int _pageSize;

  List<MarketCategory> _categories = const [
    MarketCategory(id: kMarketCategoryAll, label: 'Barchasi'),
  ];
  List<MarketCategory> get categories => _categories;

  final List<MarketListing> _items = [];
  Timer? _searchTimer;
  int _offset = 0;
  int _totalCount = 0;
  int _requestToken = 0;
  bool _disposed = false;

  MarketStatus _status = MarketStatus.initial;
  String _categoryId = kMarketCategoryAll;
  String _searchInput = '';
  String _searchQuery = '';
  MarketFilters _filters = MarketFilters.empty;
  String? _error;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  List<MarketListing> get items => List.unmodifiable(_items);
  MarketStatus get status => _status;
  String get categoryId => _categoryId;
  String get searchInput => _searchInput;
  MarketFilters get filters => _filters;
  String? get error => _error;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  int get totalCount => _totalCount;

  Future<void> initialize() async {
    if (_status != MarketStatus.initial) return;
    unawaited(_loadCategories());
    await _fetchFirstPage();
  }

  Future<void> _loadCategories() async {
    final svc = _categoriesService;
    if (svc == null) return;
    try {
      final remote = await svc.fetchCategories();
      if (_disposed) return;
      _categories = [
        const MarketCategory(id: kMarketCategoryAll, label: 'Barchasi'),
        ...remote.map(
          (c) => MarketCategory(id: c.slug, label: c.name),
        ),
      ];
      _notify();
    } catch (_) {
      // Silent fallback — keep the default "Barchasi" entry.
    }
  }

  void selectCategory(String id) {
    if (_categoryId == id) return;
    _categoryId = id;
    _notify();
    unawaited(_fetchFirstPage());
  }

  void onSearchInputChanged(String next) {
    if (_searchInput == next) return;
    _searchInput = next;
    _notify();

    _searchTimer?.cancel();
    _searchTimer = Timer(_debounce, () {
      if (_disposed) return;
      final trimmed = _searchInput.trim();
      if (trimmed == _searchQuery) return;
      _searchQuery = trimmed;
      unawaited(_fetchFirstPage());
    });
  }

  void clearSearch() {
    _searchTimer?.cancel();
    if (_searchInput.isEmpty && _searchQuery.isEmpty) return;
    final hadQuery = _searchQuery.isNotEmpty;
    _searchInput = '';
    _searchQuery = '';
    _notify();
    if (hadQuery) unawaited(_fetchFirstPage());
  }

  void applyFilters(MarketFilters next) {
    if (_filters == next) return;
    _filters = next;
    _notify();
    unawaited(_fetchFirstPage());
  }

  Future<void> refresh() => _fetchFirstPage();

  Future<void> retry() => _fetchFirstPage();

  Future<void> loadMore() async {
    if (_status != MarketStatus.success) return;
    if (_isLoadingMore || !_hasMore) return;

    _isLoadingMore = true;
    _notify();

    final token = ++_requestToken;
    try {
      final page = await _repository.fetchPage(
        query: _searchQuery,
        categoryId: _categoryId,
        offset: _offset,
        limit: _pageSize,
        filters: _filters,
      );
      if (_disposed || token != _requestToken) return;
      _items.addAll(page.items);
      _offset = page.nextOffset;
      _hasMore = page.hasMore;
      _totalCount = page.totalCount;
      _isLoadingMore = false;
      _notify();
    } catch (_) {
      if (_disposed || token != _requestToken) return;
      _isLoadingMore = false;
      _error = 'Yana yuklashda xatolik.';
      _notify();
    }
  }

  Future<void> _fetchFirstPage() async {
    _searchTimer?.cancel();
    final token = ++_requestToken;

    _status = MarketStatus.loading;
    _error = null;
    _offset = 0;
    _hasMore = true;
    _isLoadingMore = false;
    _items.clear();
    _notify();

    try {
      final page = await _repository.fetchPage(
        query: _searchQuery,
        categoryId: _categoryId,
        offset: 0,
        limit: _pageSize,
        filters: _filters,
      );
      if (_disposed || token != _requestToken) return;
      _items
        ..clear()
        ..addAll(page.items);
      _offset = page.nextOffset;
      _hasMore = page.hasMore;
      _totalCount = page.totalCount;
      _status = MarketStatus.success;
      _notify();
    } catch (_) {
      if (_disposed || token != _requestToken) return;
      _status = MarketStatus.error;
      _error = 'Ma\'lumotlarni yuklab bo\'lmadi.';
      _notify();
    }
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchTimer?.cancel();
    super.dispose();
  }
}

MarketController? _shared;
String? _sharedLocale;

/// App-wide MarketController singleton — keeps list/filters/scroll-state
/// alive across tab switches so the user doesn't see loading skeletons
/// every time they come back to Market. Pull-to-refresh still refetches.
///
/// Recreated when [locale] differs from the cached one so category labels
/// (and any other localized fields) re-fetch in the new language.
MarketController sharedMarketController({String? locale}) {
  if (_shared != null && _sharedLocale == locale) return _shared!;
  _shared?.dispose();
  final svc = MarketplaceApiService(locale: locale);
  _shared = MarketController(
    repository: ApiMarketRepository(service: svc),
    categoriesService: svc,
  );
  _sharedLocale = locale;
  return _shared!;
}
