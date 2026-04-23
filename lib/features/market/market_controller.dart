import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'market_repository.dart';
import 'models/market_listing.dart';

class MarketController extends ChangeNotifier {
  MarketController({MarketRepository? repository})
    : _repository = repository ?? const MarketRepository();

  static const String _categoryPrefKey = 'market.category.v1';
  static const String _searchPrefKey = 'market.search.v1';
  static const int _pageSize = 12;

  final MarketRepository _repository;

  final List<MarketListing> _items = [];

  Timer? _debounce;
  int _offset = 0;
  int _requestToken = 0;
  bool _initialized = false;
  bool _disposed = false;

  String _selectedCategoryId = marketCategories.first.id;
  String _searchInput = '';
  String _searchQuery = '';
  String? _error;

  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  List<MarketListing> get items => List.unmodifiable(_items);
  String get selectedCategoryId => _selectedCategoryId;
  String get searchInput => _searchInput;
  String? get error => _error;
  bool get isInitialLoading => _isInitialLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    _selectedCategoryId =
        prefs.getString(_categoryPrefKey) ?? marketCategories.first.id;
    _searchInput = prefs.getString(_searchPrefKey) ?? '';
    _searchQuery = _searchInput.trim();

    await _fetchFirstPage();
  }

  void onSearchInputChanged(String value) {
    _searchInput = value;
    _safeNotify();

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (_disposed) return;
      final nextQuery = _searchInput.trim();
      if (nextQuery == _searchQuery) return;
      _searchQuery = nextQuery;
      unawaited(_persistFilters());
      unawaited(_fetchFirstPage());
    });
  }

  void clearSearch() {
    _debounce?.cancel();
    if (_searchInput.isEmpty && _searchQuery.isEmpty) return;

    _searchInput = '';
    if (_searchQuery == '') {
      _safeNotify();
      return;
    }

    _searchQuery = '';
    _safeNotify();
    unawaited(_persistFilters());
    unawaited(_fetchFirstPage());
  }

  void selectCategory(String categoryId) {
    if (_selectedCategoryId == categoryId) return;
    _selectedCategoryId = categoryId;
    _safeNotify();
    unawaited(_persistFilters());
    unawaited(_fetchFirstPage());
  }

  Future<void> resetFilters() async {
    _debounce?.cancel();
    _selectedCategoryId = marketCategories.first.id;
    _searchInput = '';
    _searchQuery = '';
    _safeNotify();

    await _persistFilters();
    await _fetchFirstPage();
  }

  Future<void> retry() => _fetchFirstPage();

  Future<void> loadMore() async {
    if (_isInitialLoading || _isLoadingMore || !_hasMore) return;

    _isLoadingMore = true;
    _error = null;
    _safeNotify();

    final token = _requestToken;

    try {
      final page = await _repository.fetchListings(
        query: _searchQuery,
        categoryId: _selectedCategoryId,
        offset: _offset,
        limit: _pageSize,
      );

      if (_disposed || token != _requestToken) return;

      _items.addAll(page.items);
      _offset = page.nextOffset;
      _hasMore = page.hasMore;
      _isLoadingMore = false;
      _safeNotify();
    } catch (_) {
      if (_disposed || token != _requestToken) return;
      _error = 'Ro\'yxatni yuklashda xatolik.';
      _isLoadingMore = false;
      _safeNotify();
    }
  }

  Future<void> _fetchFirstPage() async {
    _debounce?.cancel();
    _requestToken += 1;
    final token = _requestToken;

    _isInitialLoading = true;
    _isLoadingMore = false;
    _error = null;
    _hasMore = true;
    _offset = 0;
    _items.clear();
    _safeNotify();

    try {
      final page = await _repository.fetchListings(
        query: _searchQuery,
        categoryId: _selectedCategoryId,
        offset: 0,
        limit: _pageSize,
      );

      if (_disposed || token != _requestToken) return;

      _items
        ..clear()
        ..addAll(page.items);
      _offset = page.nextOffset;
      _hasMore = page.hasMore;
      _isInitialLoading = false;
      _safeNotify();
    } catch (_) {
      if (_disposed || token != _requestToken) return;
      _error = 'Ma\'lumotlarni yuklashda xatolik.';
      _isInitialLoading = false;
      _safeNotify();
    }
  }

  Future<void> _persistFilters() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_categoryPrefKey, _selectedCategoryId),
      prefs.setString(_searchPrefKey, _searchInput),
    ]);
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}
