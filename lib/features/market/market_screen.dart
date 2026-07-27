import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n/app_translations.dart';
import '../../core/network_error_handler.dart';
import '../../theme/app_colors.dart';
import '../settings/settings_state.dart';
import 'listing_detail_screen.dart';
import 'market_controller.dart';
import 'models/market_filters.dart';
import 'models/market_listing.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'widgets/category_chips.dart';
import 'widgets/filter_sheet.dart';
import 'widgets/listing_card.dart';
import 'widgets/listing_skeleton_card.dart';
import 'widgets/market_empty_state.dart';
import 'widgets/market_header.dart';
import 'widgets/market_search_bar.dart';

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key, this.controller});

  /// Optional override — useful for tests. When null, the shared app-wide
  /// controller is used so data persists across tab switches.
  final MarketController? controller;

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  static const double _scrollToTopThreshold = 600;

  late final MarketController _controller;
  late final ScrollController _scroll;
  late final TextEditingController _searchText;
  late final _StickyHeaderDelegate _headerDelegate;

  final ValueNotifier<bool> _showScrollTop = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _headerScrolled = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        sharedMarketController(locale: localeNotifier.value.languageCode);
    _scroll = ScrollController()..addListener(_onScroll);
    _searchText = TextEditingController(text: _controller.searchInput);
    _controller.addListener(_syncSearchText);
    _controller.addListener(_handleControllerError);
    _headerDelegate = _StickyHeaderDelegate(
      height: 60,
      scrolled: _headerScrolled,
      child: _StickyHeader(onFilterTap: _onFilterTap, controller: _controller),
    );
    // Idempotent — only fetches on the very first open.
    unawaited(_controller.initialize());
  }

  Object? _lastSeenError;
  void _handleControllerError() {
    final err = _controller.lastErrorObject;
    if (err == null || identical(err, _lastSeenError)) return;
    _lastSeenError = err;
    // Only surface the sheet when there's no cached list to show — keeps
    // background "loadMore" failures silent if user already sees items.
    if (_controller.items.isNotEmpty) return;
    if (!mounted) return;
    NetworkErrorHandler.maybeShow(context, err, onRetry: _controller.retry);
  }

  void _syncSearchText() {
    final next = _controller.searchInput;
    if (_searchText.text == next) return;
    _searchText.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    if (p.maxScrollExtent - p.pixels <= 400) {
      unawaited(_controller.loadMore());
    }
    final shouldShow = p.pixels > _scrollToTopThreshold;
    if (_showScrollTop.value != shouldShow) {
      _showScrollTop.value = shouldShow;
    }
    final scrolled = p.pixels > 4;
    if (_headerScrolled.value != scrolled) {
      _headerScrolled.value = scrolled;
    }
  }

  Future<void> _scrollToTop() async {
    HapticFeedback.selectionClick();
    if (!_scroll.hasClients) return;
    await _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _onFilterTap() async {
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    final next = await showMarketFilterSheet(
      context,
      initial: _controller.filters,
    );
    if (next != null) _controller.applyFilters(next);
  }

  void _onCardTap(MarketListing listing) {
    final isIos = Theme.of(context).platform == TargetPlatform.iOS;
    final Route<void> route = isIos
        // iOS: native slide-from-right + edge-swipe-back gesture for free.
        ? CupertinoPageRoute<void>(
            builder: (_) => ListingDetailScreen(listing: listing),
          )
        // Android: custom fade + slight slide-up. System back button just works.
        : PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 360),
            reverseTransitionDuration: const Duration(milliseconds: 280),
            pageBuilder: (_, _, _) => ListingDetailScreen(listing: listing),
            transitionsBuilder: (_, animation, _, child) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.06),
                    end: Offset.zero,
                  ).animate(curved),
                  child: child,
                ),
              );
            },
          );
    Navigator.of(context).push(route);
  }

  void _resetAll() {
    _searchText.clear();
    _controller
      ..clearSearch()
      ..selectCategory(kMarketCategoryAll)
      ..applyFilters(MarketFilters.empty);
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    // Do NOT dispose the shared controller — it lives for the app lifetime
    // so data persists across tab switches.
    _controller.removeListener(_syncSearchText);
    _controller.removeListener(_handleControllerError);
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _searchText.dispose();
    _showScrollTop.dispose();
    _headerScrolled.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;

    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _dismissKeyboard,
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              RefreshIndicator(
                color: AppColors.splashGreen,
                onRefresh: _controller.refresh,
                child: CustomScrollView(
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  cacheExtent: 800,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _headerDelegate,
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: MarketSearchBar(
                          controller: _searchText,
                          onChanged: _controller.onSearchInputChanged,
                          onClear: () {
                            _searchText.clear();
                            _controller.clearSearch();
                          },
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _ChipsRow(controller: _controller),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 20)),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: _BodySliver(
                        controller: _controller,
                        locale: locale,
                        onCardTap: _onCardTap,
                        onResetAll: _resetAll,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _TailSliver(controller: _controller),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 28)),
                  ],
                ),
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _showScrollTop,
                  builder: (context, visible, _) {
                    return _ScrollToTopButton(
                      visible: visible,
                      onTap: _scrollToTop,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StickyHeader extends StatelessWidget {
  const _StickyHeader({required this.onFilterTap, required this.controller});

  final VoidCallback onFilterTap;
  final MarketController controller;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return MarketHeader(
            title: tr(locale, 'market.screen.title'),
            onFilterTap: onFilterTap,
            filterActiveCount: controller.filters.activeCount,
          );
        },
      ),
    );
  }
}

class _ChipsRow extends StatelessWidget {
  const _ChipsRow({required this.controller});

  final MarketController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // Labels are already localized by the controller: static chips via
        // tr('market.controller.*'), remote chips via the backend-provided name.
        return CategoryChips(
          categories: controller.categories,
          selectedId: controller.categoryId,
          onSelected: controller.selectCategory,
        );
      },
    );
  }
}

class _BodySliver extends StatelessWidget {
  const _BodySliver({
    required this.controller,
    required this.locale,
    required this.onCardTap,
    required this.onResetAll,
  });

  final MarketController controller;
  final Locale locale;
  final ValueChanged<MarketListing> onCardTap;
  final VoidCallback onResetAll;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;

        if (c.status == MarketStatus.loading && c.items.isEmpty) {
          return _grid(
            childCount: 6,
            builder: (_, _) =>
                const RepaintBoundary(child: ListingSkeletonCard()),
          );
        }

        if (c.status == MarketStatus.error && c.items.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: MarketEmptyState(
              icon: Icons.wifi_off_rounded,
              title: tr(locale, 'market.screen.error_title'),
              subtitle: c.error ?? tr(locale, 'market.screen.error_subtitle'),
              actionLabel: tr(locale, 'market.screen.retry'),
              onAction: () => unawaited(c.retry()),
            ),
          );
        }

        if (c.items.isEmpty) {
          final filtered =
              c.searchInput.isNotEmpty ||
              c.categoryId != kMarketCategoryAll ||
              !c.filters.isEmpty;
          return SliverFillRemaining(
            hasScrollBody: false,
            child: MarketEmptyState(
              icon: Icons.search_off_rounded,
              title: tr(locale, 'market.screen.empty_title'),
              subtitle: tr(locale, 'market.screen.empty_subtitle'),
              actionLabel: filtered
                  ? tr(locale, 'market.screen.clear_filters')
                  : null,
              onAction: filtered ? onResetAll : null,
            ),
          );
        }

        return _grid(
          childCount: c.items.length,
          builder: (context, i) => RepaintBoundary(
            child: ListingCard(listing: c.items[i], onTap: onCardTap),
          ),
        );
      },
    );
  }

  Widget _grid({
    required int childCount,
    required IndexedWidgetBuilder builder,
  }) {
    return SliverMasonryGrid.count(
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childCount: childCount,
      itemBuilder: builder,
    );
  }
}

class _TailSliver extends StatelessWidget {
  const _TailSliver({required this.controller});

  final MarketController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        if (c.isLoadingMore) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.splashGreen,
                ),
              ),
            ),
          );
        }
        if (c.error != null && c.items.isNotEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: TextButton(
                onPressed: () => unawaited(c.loadMore()),
                child: Text(
                  tr(Localizations.localeOf(context), 'market.screen.retry'),
                ),
              ),
            ),
          );
        }
        return const SizedBox(height: 8);
      },
    );
  }
}

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  _StickyHeaderDelegate({
    required this.height,
    required this.child,
    required this.scrolled,
  });

  final double height;
  final Widget child;
  final ValueListenable<bool> scrolled;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    return ValueListenableBuilder<bool>(
      valueListenable: scrolled,
      child: child,
      builder: (context, isScrolled, inner) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: bg,
            boxShadow: isScrolled
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.32 : 0.06,
                      ),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: inner,
        );
      },
    );
  }

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate old) =>
      height != old.height || child != old.child || scrolled != old.scrolled;
}

class _ScrollToTopButton extends StatelessWidget {
  const _ScrollToTopButton({required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 1.4),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Material(
            color: AppColors.splashGreen,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            elevation: 4,
            shadowColor: Colors.black.withValues(alpha: 0.3),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  Icons.keyboard_arrow_up_rounded,
                  size: 28,
                  color: AppColors.buttonTextBlack,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
