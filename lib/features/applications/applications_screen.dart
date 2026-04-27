import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_colors.dart';
import 'application_detail_screen.dart';
import '../market/models/market_listing.dart' show MarketCategory;
import '../market/widgets/category_chips.dart';
import 'application_model.dart';

class ApplicationsScreen extends StatefulWidget {
  const ApplicationsScreen({super.key, this.animateToken = 0});

  final int animateToken;

  @override
  State<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends State<ApplicationsScreen>
    with AutomaticKeepAliveClientMixin {
  static const int _pageSize = 6;
  static const double _scrollToTopThreshold = 620;
  static const double _loadMoreThreshold = 360;

  String _selectedServiceId = applicationServiceChips.first.id;
  late final ScrollController _scrollController;
  final ValueNotifier<bool> _showScrollTop = ValueNotifier<bool>(false);
  late final List<ApplicationItem> _allItems;
  final List<ApplicationItem> _items = <ApplicationItem>[];

  bool _initialized = false;
  bool _loadingInitial = false;
  bool _loadingMore = false;
  bool _refreshing = false;
  bool _hasMore = true;
  int _nextOffset = 0;
  int _requestId = 0;
  int _entryEpoch = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _allItems = _buildSeedItems();
    _scrollController = ScrollController()..addListener(_onScroll);
    if (widget.animateToken > 0) {
      unawaited(_ensureInitialized());
    }
  }

  @override
  void didUpdateWidget(covariant ApplicationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animateToken == oldWidget.animateToken) return;
    if (!_initialized) {
      unawaited(_ensureInitialized());
      return;
    }
    setState(() => _entryEpoch++);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _showScrollTop.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final p = _scrollController.position;
    final shouldShow = p.pixels > _scrollToTopThreshold;
    if (_showScrollTop.value != shouldShow) {
      _showScrollTop.value = shouldShow;
    }
    if (p.maxScrollExtent - p.pixels <= _loadMoreThreshold) {
      unawaited(_loadMore());
    }
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openDetails(ApplicationItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ApplicationDetailScreen(item: item),
      ),
    );
  }

  List<ApplicationItem> get _sourceItems {
    if (_selectedServiceId == 'all') return _allItems;
    return _allItems
        .where((item) => item.serviceId == _selectedServiceId)
        .toList(growable: false);
  }

  Future<void> _ensureInitialized() async {
    if (_initialized || _loadingInitial) return;
    await _loadFirstPage(markInitialized: true);
  }

  Future<void> _loadFirstPage({bool markInitialized = false}) async {
    if (_loadingInitial) return;
    final requestId = ++_requestId;
    setState(() {
      _loadingInitial = true;
      _loadingMore = false;
      _refreshing = false;
      _nextOffset = 0;
      _hasMore = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 260));
    final source = _sourceItems;
    final next = source.take(_pageSize).toList(growable: false);

    if (!mounted) return;
    if (requestId != _requestId) {
      setState(() => _loadingInitial = false);
      return;
    }
    setState(() {
      _items
        ..clear()
        ..addAll(next);
      _nextOffset = next.length;
      _hasMore = _nextOffset < source.length;
      _loadingInitial = false;
      _initialized = _initialized || markInitialized;
      _entryEpoch++;
    });
  }

  Future<void> _loadMore() async {
    if (!_initialized ||
        _loadingInitial ||
        _loadingMore ||
        _refreshing ||
        !_hasMore) {
      return;
    }

    final requestId = ++_requestId;
    setState(() => _loadingMore = true);

    await Future<void>.delayed(const Duration(milliseconds: 220));
    final source = _sourceItems;
    final next = source
        .skip(_nextOffset)
        .take(_pageSize)
        .toList(growable: false);

    if (!mounted) return;
    if (requestId != _requestId) {
      setState(() => _loadingMore = false);
      return;
    }
    setState(() {
      _items.addAll(next);
      _nextOffset += next.length;
      _hasMore = _nextOffset < source.length;
      _loadingMore = false;
    });
  }

  Future<void> _refresh() async {
    if (!_initialized) {
      await _ensureInitialized();
      return;
    }
    if (_refreshing) return;
    final requestId = ++_requestId;
    setState(() {
      _refreshing = true;
      _loadingMore = false;
    });

    await Future<void>.delayed(const Duration(milliseconds: 260));
    final source = _sourceItems;
    final next = source.take(_pageSize).toList(growable: false);

    if (!mounted) return;
    if (requestId != _requestId) {
      setState(() => _refreshing = false);
      return;
    }
    setState(() {
      _items
        ..clear()
        ..addAll(next);
      _nextOffset = next.length;
      _hasMore = _nextOffset < source.length;
      _refreshing = false;
      _entryEpoch++;
    });
  }

  void _onServiceChanged(String id) {
    if (id == _selectedServiceId) return;
    setState(() => _selectedServiceId = id);
    if (!_initialized) return;
    unawaited(_loadFirstPage());
  }

  List<ApplicationItem> _buildSeedItems() {
    final seed = mockApplicationItems;
    if (seed.isEmpty) return const <ApplicationItem>[];
    return List<ApplicationItem>.generate(30, (i) {
      final base = seed[i % seed.length];
      final month = (i % 12) + 1;
      final day = (i % 28) + 1;
      final dateValue =
          '${day.toString().padLeft(2, '0')}.${month.toString().padLeft(2, '0')}.2026';
      return ApplicationItem(
        id: '${base.id}_$i',
        serviceId: base.serviceId,
        serviceLabel: base.serviceLabel,
        statusGroup: base.statusGroup,
        addressLabel: base.addressLabel,
        addressValue: base.addressValue,
        dateLabel: base.dateLabel,
        dateValue: dateValue,
        timeline: base.timeline,
        typeLabel: base.typeLabel,
        typeValue: base.typeValue,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(
              color: AppColors.splashGreen,
              onRefresh: _refresh,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _Title(),
                          const SizedBox(height: 14),
                          _ServiceChips(
                            selectedId: _selectedServiceId,
                            onChanged: _onServiceChanged,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_loadingInitial)
                    const SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverToBoxAdapter(
                        child: _CardLoadingBlock(count: 3),
                      ),
                    )
                  else if (_initialized && _items.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(),
                    )
                  else if (_initialized)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          if (index >= _items.length) {
                            return const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: _CardLoadingSkeleton(),
                            );
                          }
                          final item = _items[index];
                          final seed = _entryEpoch + widget.animateToken;
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom:
                                  index == _items.length - 1 && !_loadingMore
                                  ? 0
                                  : 8,
                            ),
                            child: _AnimatedCardEntry(
                              index: index,
                              seed: seed,
                              child: _ApplicationCard(
                                item: item,
                                onTap: () => _openDetails(item),
                              ),
                            ),
                          );
                        }, childCount: _items.length + (_loadingMore ? 2 : 0)),
                      ),
                    )
                  else
                    const SliverToBoxAdapter(child: SizedBox.shrink()),
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
    );
  }
}

class _AnimatedCardEntry extends StatelessWidget {
  const _AnimatedCardEntry({
    required this.index,
    required this.seed,
    required this.child,
  });

  final int index;
  final int seed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delay = index > 5 ? 5 : index;
    return TweenAnimationBuilder<double>(
      key: ValueKey('${seed}_$index'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + delay * 40),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Transform.translate(
          offset: Offset(0, (1 - t) * 14),
          child: Opacity(opacity: t, child: child),
        );
      },
      child: child,
    );
  }
}

class _ScrollToTopButton extends StatelessWidget {
  const _ScrollToTopButton({required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: AnimatedScale(
          scale: visible ? 1 : 0.86,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: Material(
            color: Colors.white,
            elevation: 6,
            shadowColor: Colors.black.withValues(alpha: 0.16),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  Icons.keyboard_arrow_up_rounded,
                  size: 24,
                  color: AppColors.textBlack,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardLoadingBlock extends StatelessWidget {
  const _CardLoadingBlock({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List<Widget>.generate(count, (i) {
        return Padding(
          padding: EdgeInsets.only(bottom: i == count - 1 ? 0 : 8),
          child: const _CardLoadingSkeleton(),
        );
      }, growable: false),
    );
  }
}

class _CardLoadingSkeleton extends StatefulWidget {
  const _CardLoadingSkeleton();

  @override
  State<_CardLoadingSkeleton> createState() => _CardLoadingSkeletonState();
}

class _CardLoadingSkeletonState extends State<_CardLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, _) {
        final t = _shimmer.value;
        return Container(
          constraints: const BoxConstraints(minHeight: 125),
          width: 335,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFDADADA), width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _ShimmerBone(
                      shimmer: t,
                      height: 18,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ShimmerBone(
                    shimmer: t,
                    width: 146,
                    height: 40,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, thickness: 1, color: Color(0xFFE8E8E8)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ShimmerBone(
                      shimmer: t,
                      width: 86,
                      height: 14,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _ShimmerBone(
                        shimmer: t,
                        width: 160,
                        height: 14,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, thickness: 1, color: Color(0xFFE8E8E8)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ShimmerBone(
                      shimmer: t,
                      width: 116,
                      height: 14,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _ShimmerBone(
                        shimmer: t,
                        width: 122,
                        height: 14,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ShimmerBone extends StatelessWidget {
  const _ShimmerBone({
    required this.shimmer,
    required this.height,
    required this.borderRadius,
    this.width,
  });

  final double shimmer;
  final double? width;
  final double height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    const base = Color(0xFFE9ECEF);
    const highlight = Color(0xFFF7F8FA);
    return ClipRRect(
      borderRadius: borderRadius,
      child: ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) {
          return LinearGradient(
            colors: const [base, highlight, base],
            stops: const [0.25, 0.5, 0.75],
            begin: const Alignment(-1, -0.2),
            end: const Alignment(1, 0.2),
            transform: _SlidingGradientTransform(shimmer),
          ).createShader(bounds);
        },
        child: Container(width: width, height: height, color: base),
      ),
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform(this.slidePercent);

  final double slidePercent;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(
      bounds.width * (slidePercent * 2 - 1),
      0,
      0,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Arizalar topilmadi',
        style: TextStyle(
          fontFamily: 'MTSCompact',
          fontWeight: FontWeight.w500,
          fontSize: 15,
          color: Color(0xFF8A8A8A),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Arizalar',
      style: TextStyle(
        fontFamily: 'MTSCompact',
        fontWeight: FontWeight.w700,
        fontSize: 24,
        height: 1.3,
        color: AppColors.textBlack,
      ),
    );
  }
}

class _ServiceChips extends StatelessWidget {
  const _ServiceChips({required this.selectedId, required this.onChanged});

  final String selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return CategoryChips(
      categories: applicationServiceChips
          .map((chip) => MarketCategory(id: chip.id, label: chip.label))
          .toList(growable: false),
      selectedId: selectedId,
      onSelected: onChanged,
      padding: EdgeInsets.zero,
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({required this.item, required this.onTap});

  final ApplicationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = _StatusStyle.fromGroup(item.statusGroup);
    final showResultButton =
        item.statusGroup == ApplicationStatusGroup.completed;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 125),
          width: 335,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFDADADA), width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.serviceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        height: 1.3,
                        color: AppColors.textBlack,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusBadge(style: status),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, thickness: 1, color: Color(0xFFE8E8E8)),
              const SizedBox(height: 12),
              _MetaRow(
                label: '${item.addressLabel}:',
                value: item.addressValue,
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, thickness: 1, color: Color(0xFFE8E8E8)),
              const SizedBox(height: 12),
              _MetaRow(label: '${item.dateLabel}:', value: item.dateValue),
              if (showResultButton) ...[
                const SizedBox(height: 14),
                Material(
                  color: const Color(0xFF00E135),
                  borderRadius: BorderRadius.circular(10000),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onTap,
                    child: SizedBox(
                      width: double.infinity,
                      height: 32,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Natijani ko‘rish',
                              style: TextStyle(
                                fontFamily: 'MTSCompact',
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: Colors.black,
                              ),
                            ),
                            SizedBox(width: 6),
                            SvgPicture.asset(
                              'assets/icons/arrow.svg',
                              width: 20,
                              height: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w500,
                fontSize: 14,
                height: 1.3,
                color: Color(0xFF8A8A8A),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w500,
              fontSize: 14,
              height: 1.3,
              color: AppColors.textBlack,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusStyle {
  const _StatusStyle({
    required this.label,
    required this.bgColor,
    required this.fgColor,
    required this.iconAsset,
  });

  final String label;
  final Color bgColor;
  final Color fgColor;
  final String iconAsset;

  static _StatusStyle fromGroup(ApplicationStatusGroup group) =>
      switch (group) {
        ApplicationStatusGroup.inProgress => const _StatusStyle(
          label: 'Jarayonda',
          bgColor: Color(0xFFFCEDE3),
          fgColor: Color(0xFFF27523),
          iconAsset: 'assets/icons/application-pending.svg',
        ),
        ApplicationStatusGroup.completed => const _StatusStyle(
          label: 'Tayyor',
          bgColor: Color(0xFFD5F3E0),
          fgColor: Color(0xFF00B447),
          iconAsset: 'assets/icons/application-ready.svg',
        ),
        ApplicationStatusGroup.cancelled => const _StatusStyle(
          label: 'Bekor qilingan',
          bgColor: Color(0xFFF8E1E1),
          fgColor: Color(0xFFEF4444),
          iconAsset: 'assets/icons/application-cancelled.svg',
        ),
      };
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.style});

  final _StatusStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.fromLTRB(3, 3, 8, 3),
      decoration: BoxDecoration(
        color: style.bgColor,
        borderRadius: BorderRadius.circular(10000),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            style.iconAsset,
            width: 18,
            height: 18,
            colorFilter: ColorFilter.mode(style.fgColor, BlendMode.srcIn),
          ),
          const SizedBox(width: 4),
          Text(
            style.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 12,
              height: 1.3,
              color: style.fgColor,
            ),
          ),
        ],
      ),
    );
  }
}
