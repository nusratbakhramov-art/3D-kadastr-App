import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'market_controller.dart';
import 'models/market_listing.dart';
import 'widgets/category_chips.dart';
import 'widgets/listing_grid.dart';
import 'widgets/market_empty_state.dart';
import 'widgets/market_header.dart';
import 'widgets/market_search_bar.dart';

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  late final MarketController _controller;
  late final ScrollController _scrollController;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _controller = MarketController();
    _scrollController = ScrollController()..addListener(_handleScroll);
    _searchController = TextEditingController();
    _controller.addListener(_syncSearchInput);
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await _controller.initialize();
    _syncSearchInput();
  }

  void _syncSearchInput() {
    final next = _controller.searchInput;
    if (_searchController.text == next) return;
    _searchController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  void _handleScroll() {
    if (_scrollController.hasClients == false) return;
    final position = _scrollController.position;
    final remaining = position.maxScrollExtent - position.pixels;
    if (remaining <= 200) {
      unawaited(_controller.loadMore());
    }
  }

  void _openFilters() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Filtrlar bo\'limi tez orada qo\'shiladi')),
    );
  }

  void _openDetails(MarketListing listing) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${listing.title} tafsilotlari tez orada')),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_syncSearchInput);
    _controller.dispose();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageColor = isDark ? AppColors.greenBlack : AppColors.lightBackground;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: pageColor,
          body: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverAppBar(
                pinned: true,
                automaticallyImplyLeading: false,
                backgroundColor: pageColor,
                surfaceTintColor: Colors.transparent,
                toolbarHeight: 86,
                titleSpacing: 16,
                title: MarketHeader(title: 'Market', onFilterTap: _openFilters),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    children: [
                      MarketSearchBar(
                        controller: _searchController,
                        onChanged: _controller.onSearchInputChanged,
                        onClear: () {
                          _searchController.clear();
                          _controller.clearSearch();
                        },
                      ),
                      const SizedBox(height: 12),
                      CategoryChips(
                        categories: marketCategories,
                        selectedId: _controller.selectedCategoryId,
                        onSelected: _controller.selectCategory,
                      ),
                    ],
                  ),
                ),
              ),
              if (_controller.isInitialLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: ListingGrid.skeleton(skeletonCount: 6),
                  ),
                )
              else if (_controller.error != null && _controller.items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: MarketEmptyState(
                    title: 'Xatolik yuz berdi',
                    subtitle: _controller.error!,
                    buttonLabel: 'Qayta urinib ko\'rish',
                    onPressed: _controller.retry,
                  ),
                )
              else if (_controller.items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: MarketEmptyState(
                    title: 'Hech narsa topilmadi',
                    subtitle:
                        'Qidiruv yoki kategoriyani o\'zgartirib ko\'ring.',
                    buttonLabel: 'Filtrlarni tozalash',
                    onPressed: _controller.resetFilters,
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: ListingGrid(
                      items: _controller.items,
                      onDetailsTap: _openDetails,
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: _PaginationTail(controller: _controller),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PaginationTail extends StatelessWidget {
  const _PaginationTail({required this.controller});

  final MarketController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.items.isEmpty && controller.isInitialLoading == false) {
      return const SizedBox(height: 24);
    }

    if (controller.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(0, 18, 0, 28),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
        ),
      );
    }

    if (controller.error != null && controller.items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        child: Center(
          child: TextButton(
            onPressed: controller.loadMore,
            child: const Text('Yana urinish'),
          ),
        ),
      );
    }

    if (controller.hasMore) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        child: Center(
          child: OutlinedButton.icon(
            onPressed: controller.loadMore,
            icon: const Icon(Icons.expand_more_rounded),
            label: const Text('Yana yuklash'),
          ),
        ),
      );
    }

    return const SizedBox(height: 24);
  }
}
