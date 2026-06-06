import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_colors.dart';
import '../../theme/color_tokens.dart';
import '../auth/auth_storage.dart';
import '../settings/settings_state.dart';
import '../services/api_ai_valuation_job_service.dart';
import '../services/api_architecture_order_service.dart';
import '../services/api_calculator_order_service.dart';
import '../services/api_kadastr_3d_job_service.dart';
import '../services/api_photogrammetry_service.dart';
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
  List<ApplicationItem> _allItems = const <ApplicationItem>[];
  final List<ApplicationItem> _items = <ApplicationItem>[];
  String? _loadError;

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
      _loadError = null;
    });

    // Backend dan olamiz (faqat birinchi marta yoki refresh paytida).
    if (_allItems.isEmpty) {
      try {
        await _fetchAllFromBackend();
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _loadError = '$e';
          _loadingInitial = false;
          _initialized = _initialized || markInitialized;
        });
        return;
      }
    }

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

  Future<void> _fetchAllFromBackend() async {
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null) {
      // Login qilinmagan: hech narsa ko'rsatmaymiz, mock'ka qaytmaymiz.
      _allItems = const <ApplicationItem>[];
      return;
    }

    // Uch manbadan parallel yig'amiz: arxitektura buyurtmalari, AI baholash
    // tasdiqlash arizalari va photogrammetry skan job'lari. Birortasi xato
    // qaytarsa, qolganini ko'rsatamiz.
    final ordersFuture = ArchitectureOrderApiService()
        .list(token: token, page: 1, size: 100)
        .then(
          (page) =>
              page.items.map(_orderToApplicationItem).toList(growable: false),
        )
        .catchError((_) => <ApplicationItem>[]);

    // AI Baholash arizalari = async valuation JOBS (`GET /ai-valuations`).
    // Eski kod `/valuations/ai/confirmations` (admin tasdiqlash arizalari)
    // ni o'qigan — bu boshqa jadval, shuning uchun oddiy AI baholash hech
    // qachon ko'rinmasdi. Endi foydalanuvchining baholash job'larini olamiz.
    final aiJobsFuture = AiValuationJobService()
        .list(token: token)
        .then(
          (list) => list.map(_aiJobToApplicationItem).toList(growable: false),
        )
        .catchError((_) => <ApplicationItem>[]);

    final photogrammetryFuture = PhotogrammetryApiService()
        .listJobs()
        .then(
          (list) => list
              .map(_photogrammetryToApplicationItem)
              .toList(growable: false),
        )
        .catchError((_) => <ApplicationItem>[]);

    // Kalkulyator arizalari (`GET /services/calculator/orders`).
    final calcFuture = CalculatorOrderApiService()
        .list(token: token)
        .then(
          (list) => list.map(_calcToApplicationItem).toList(growable: false),
        )
        .catchError((_) => <ApplicationItem>[]);

    // 3D Kadastr arizalari (`GET /3d-kadastr-jobs`).
    final kadastr3dFuture = Kadastr3dJobService()
        .list(token: token)
        .then(
          (list) =>
              list.map(_kadastr3dToApplicationItem).toList(growable: false),
        )
        .catchError((_) => <ApplicationItem>[]);

    final results = await Future.wait([
      ordersFuture,
      aiJobsFuture,
      photogrammetryFuture,
      calcFuture,
      kadastr3dFuture,
    ]);
    final combined = <ApplicationItem>[
      ...results[0],
      ...results[1],
      ...results[2],
      ...results[3],
      ...results[4],
    ];
    // Yangidan eskigacha tartiblash — sanalar string sifatida saqlangan,
    // lekin DD.MM.YYYY format saqlanadi → teskari sort.
    combined.sort((a, b) => b.dateValue.compareTo(a.dateValue));
    _allItems = combined;
  }

  static ApplicationItem _orderToApplicationItem(OrderSummary o) {
    final lang = localeNotifier.value.languageCode;
    final group = _statusToGroup(o.status);
    final date = _formatDate(o.createdAt);
    return ApplicationItem(
      id: 'arch_${o.id}',
      serviceId: 'arch',
      serviceLabel: _ApplicationsStrings.serviceLabel(lang, 'arch'),
      statusGroup: group,
      addressLabel: _ApplicationsStrings.address(lang),
      addressValue: (o.address ?? o.cadastreNumber ?? '—'),
      dateLabel: _ApplicationsStrings.applicationDate(lang),
      dateValue: date,
      detailRows: [
        (_ApplicationsStrings.address(lang), o.address ?? '—'),
        if (o.cadastreNumber != null)
          (_ApplicationsStrings.cadastreNumber(lang), o.cadastreNumber!),
        (_ApplicationsStrings.status(lang), _groupLabel(group)),
        (_ApplicationsStrings.applicationDate(lang), date),
      ],
      timeline: _basicTimeline(group, o.createdAt),
    );
  }

  static ApplicationItem _aiJobToApplicationItem(AiJobSummary j) {
    final lang = localeNotifier.value.languageCode;
    final hasValue = j.estimatedValue != null;
    final group = _aiJobStatusToGroup(j.status);
    final date = _formatDate(j.createdAt);
    return ApplicationItem(
      id: 'aival_${j.id}',
      serviceId: 'ai_eval',
      serviceLabel: _ApplicationsStrings.serviceLabel(lang, 'ai_eval'),
      statusGroup: group,
      addressLabel: hasValue
          ? _ApplicationsStrings.estimatedValue(lang)
          : _ApplicationsStrings.cadastreNumber(lang),
      addressValue: hasValue
          ? _formatUzs(j.estimatedValue!)
          : (j.cadastreNumber ?? '—'),
      dateLabel: _ApplicationsStrings.applicationDate(lang),
      dateValue: date,
      typeLabel: hasValue && j.cadastreNumber != null
          ? _ApplicationsStrings.cadastre(lang)
          : null,
      typeValue: hasValue ? j.cadastreNumber : null,
      detailRows: [
        if (j.cadastreNumber != null)
          (_ApplicationsStrings.cadastreNumber(lang), j.cadastreNumber!),
        if (hasValue)
          (_ApplicationsStrings.estimatedValue(lang), _formatUzs(j.estimatedValue!)),
        (_ApplicationsStrings.status(lang), _groupLabel(group)),
        (_ApplicationsStrings.applicationDate(lang), date),
      ],
      timeline: _basicTimeline(group, j.createdAt),
    );
  }

  static ApplicationItem _calcToApplicationItem(CalculatorOrderSummary o) {
    final lang = localeNotifier.value.languageCode;
    final group = _calcStatusToGroup(o.status);
    final date = _formatDate(o.createdAt);
    return ApplicationItem(
      id: 'calc_${o.id}',
      serviceId: 'calc',
      serviceLabel: _ApplicationsStrings.serviceLabel(lang, 'calc'),
      statusGroup: group,
      addressLabel: _ApplicationsStrings.type(lang),
      addressValue: o.categoryTitle,
      dateLabel: _ApplicationsStrings.applicationDate(lang),
      dateValue: date,
      typeLabel: _ApplicationsStrings.price(lang),
      typeValue: _formatUzs(o.totalUzs),
      detailRows: [
        (_ApplicationsStrings.type(lang), o.categoryTitle),
        (_ApplicationsStrings.price(lang), _formatUzs(o.totalUzs)),
        (_ApplicationsStrings.status(lang), _groupLabel(group)),
        (_ApplicationsStrings.applicationDate(lang), date),
      ],
      timeline: _basicTimeline(group, o.createdAt),
    );
  }

  static ApplicationItem _kadastr3dToApplicationItem(Kadastr3dJobSummary j) {
    final lang = localeNotifier.value.languageCode;
    final group = _kadastr3dStatusToGroup(j.status);
    final date = _formatDate(j.createdAt);
    final objectType = _objectTypeLabel(j.objectType);
    return ApplicationItem(
      id: 'kad3d_${j.id}',
      serviceId: 'kad_3d',
      serviceLabel: _ApplicationsStrings.serviceLabel(lang, 'kad_3d'),
      statusGroup: group,
      addressLabel: _ApplicationsStrings.cadastreNumber(lang),
      addressValue: j.cadastreNumber ?? '—',
      dateLabel: _ApplicationsStrings.applicationDate(lang),
      dateValue: date,
      typeLabel: objectType != null
          ? _ApplicationsStrings.objectType(lang)
          : null,
      typeValue: objectType,
      detailRows: [
        if (j.cadastreNumber != null)
          (_ApplicationsStrings.cadastreNumber(lang), j.cadastreNumber!),
        if (objectType != null)
          (_ApplicationsStrings.objectType(lang), objectType),
        (_ApplicationsStrings.status(lang), _groupLabel(group)),
        (_ApplicationsStrings.applicationDate(lang), date),
      ],
      timeline: _basicTimeline(group, j.createdAt),
    );
  }

  static ApplicationStatusGroup _kadastr3dStatusToGroup(Kadastr3dJobStatus s) {
    return switch (s) {
      Kadastr3dJobStatus.completed => ApplicationStatusGroup.completed,
      Kadastr3dJobStatus.failed => ApplicationStatusGroup.cancelled,
      Kadastr3dJobStatus.processing => ApplicationStatusGroup.inProgress,
      Kadastr3dJobStatus.submitted => ApplicationStatusGroup.sent,
    };
  }

  static String? _objectTypeLabel(String? wire) {
    final lang = localeNotifier.value.languageCode;
    return switch (wire) {
      'residential' => _ApplicationsStrings.residential(lang),
      'non_residential' => _ApplicationsStrings.nonResidential(lang),
      'warehouse' => _ApplicationsStrings.warehouse(lang),
      'industrial' => _ApplicationsStrings.industrial(lang),
      _ => null,
    };
  }

  static String _groupLabel(ApplicationStatusGroup g) {
    final lang = localeNotifier.value.languageCode;
    return switch (g) {
      ApplicationStatusGroup.sent => _ApplicationsStrings.submitted(lang),
      ApplicationStatusGroup.inProgress => _ApplicationsStrings.inProgress(lang),
      ApplicationStatusGroup.completed => _ApplicationsStrings.ready(lang),
      ApplicationStatusGroup.cancelled => _ApplicationsStrings.cancelled(lang),
    };
  }

  /// Minimal honest timeline from what we know (creation + current status).
  /// We don't have a per-step history from the backend, so we surface the
  /// accepted step always, and the report-ready step when completed.
  static List<ApplicationTimelineStep> _basicTimeline(
    ApplicationStatusGroup group,
    DateTime createdAt,
  ) {
    if (group == ApplicationStatusGroup.cancelled) {
      return [
        ApplicationTimelineStep(
          status: ApplicationTimelineStatus.accepted,
          at: createdAt,
          completed: true,
        ),
      ];
    }
    return [
      ApplicationTimelineStep(
        status: ApplicationTimelineStatus.accepted,
        at: createdAt,
        completed: true,
      ),
      ApplicationTimelineStep(
        status: ApplicationTimelineStatus.sentToSystem,
        at: createdAt,
        completed: true,
      ),
      ApplicationTimelineStep(
        status: ApplicationTimelineStatus.reportReady,
        at: createdAt,
        completed: group == ApplicationStatusGroup.completed,
      ),
    ];
  }

  static ApplicationStatusGroup _calcStatusToGroup(String status) {
    return switch (status) {
      'done' => ApplicationStatusGroup.completed,
      'cancelled' => ApplicationStatusGroup.cancelled,
      'processing' => ApplicationStatusGroup.inProgress,
      // 'submitted' (and anything else) → freshly sent.
      _ => ApplicationStatusGroup.sent,
    };
  }

  static ApplicationStatusGroup _statusToGroup(String status) {
    return switch (status) {
      'accepted' || 'quoted' => ApplicationStatusGroup.completed,
      'rejected' => ApplicationStatusGroup.cancelled,
      _ => ApplicationStatusGroup.inProgress,
    };
  }

  static ApplicationStatusGroup _aiJobStatusToGroup(AiJobStatus s) {
    return switch (s) {
      AiJobStatus.completed => ApplicationStatusGroup.completed,
      AiJobStatus.failed => ApplicationStatusGroup.cancelled,
      _ => ApplicationStatusGroup.inProgress,
    };
  }

  static ApplicationItem _photogrammetryToApplicationItem(
    PhotogrammetryJobSummary j,
  ) {
    final lang = localeNotifier.value.languageCode;
    final group = _photogrammetryStatusToGroup(j.status);
    final date = _formatDate(j.createdAt);
    final photoCountValue =
        '${j.photoCount} ${_ApplicationsStrings.pcsUnit(lang)}';
    return ApplicationItem(
      id: 'photo_${j.id}',
      serviceId: 'kad_3d',
      serviceLabel: _ApplicationsStrings.serviceLabel(lang, '3d_scan'),
      statusGroup: group,
      addressLabel: _ApplicationsStrings.photoCount(lang),
      addressValue: photoCountValue,
      dateLabel: _ApplicationsStrings.submitted(lang),
      dateValue: date,
      typeLabel: j.isCompleted
          ? _ApplicationsStrings.model3d(lang)
          : (j.status == 'failed'
              ? _ApplicationsStrings.error(lang)
              : _ApplicationsStrings.status(lang)),
      typeValue: j.isCompleted
          ? _ApplicationsStrings.ready(lang)
          : (j.errorMessage ?? _photogrammetryStatusLabel(j.status)),
      detailRows: [
        (_ApplicationsStrings.photoCount(lang), photoCountValue),
        (_ApplicationsStrings.status(lang), _photogrammetryStatusLabel(j.status)),
        if (j.errorMessage != null)
          (_ApplicationsStrings.error(lang), j.errorMessage!),
        (_ApplicationsStrings.submitted(lang), date),
      ],
      // Completed photogrammetry jobs have a downloadable 3D model.
      hasDeliverable: j.isCompleted,
      timeline: _basicTimeline(group, j.createdAt),
    );
  }

  static ApplicationStatusGroup _photogrammetryStatusToGroup(String status) {
    return switch (status) {
      'completed' => ApplicationStatusGroup.completed,
      'failed' || 'cancelled' => ApplicationStatusGroup.cancelled,
      _ => ApplicationStatusGroup.inProgress,
    };
  }

  static String _photogrammetryStatusLabel(String status) {
    final lang = localeNotifier.value.languageCode;
    return switch (status) {
      'pending' => _ApplicationsStrings.queued(lang),
      'processing' => _ApplicationsStrings.processing(lang),
      'completed' => _ApplicationsStrings.ready(lang),
      'failed' => _ApplicationsStrings.error(lang),
      'cancelled' => _ApplicationsStrings.cancelled(lang),
      _ => status,
    };
  }

  static String _formatUzs(double value) {
    final lang = localeNotifier.value.languageCode;
    final s = value.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '${buf.toString()} ${_ApplicationsStrings.soumUnit(lang)}';
  }

  static String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
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
      _loadError = null;
    });

    // Pull-to-refresh: backend dan qayta olamiz.
    try {
      _allItems = const <ApplicationItem>[];
      await _fetchAllFromBackend();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _refreshing = false;
      });
      return;
    }

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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final locale = Localizations.localeOf(context);

    return Scaffold(
      backgroundColor: ColorTokens.scaffoldBg(context),
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
                          _Title(locale: locale),
                          const SizedBox(height: 14),
                          _ServiceChips(
                            locale: locale,
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
                  else if (_loadError != null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _ErrorState(locale: locale, message: _loadError!),
                    )
                  else if (_initialized && _items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(locale: locale),
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
            color: ColorTokens.cardBg(context),
            elevation: 6,
            shadowColor: ColorTokens.shadow(context),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  Icons.keyboard_arrow_up_rounded,
                  size: 24,
                  color: ColorTokens.primaryText(context),
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
        final dividerColor = ColorTokens.divider(context);
        return Container(
          constraints: const BoxConstraints(minHeight: 125),
          width: 335,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ColorTokens.cardBg(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ColorTokens.outline(context), width: 0.5),
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
              Divider(height: 1, thickness: 1, color: dividerColor),
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
              Divider(height: 1, thickness: 1, color: dividerColor),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF2A3032) : const Color(0xFFE9ECEF);
    final highlight = isDark
        ? const Color(0xFF3A4145)
        : const Color(0xFFF7F8FA);
    return ClipRRect(
      borderRadius: borderRadius,
      child: ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) {
          return LinearGradient(
            colors: [base, highlight, base],
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
  const _EmptyState({required this.locale});

  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        _ApplicationsStrings.empty(locale),
        style: TextStyle(
          fontFamily: 'MTSCompact',
          fontWeight: FontWeight.w500,
          fontSize: 15,
          color: ColorTokens.secondaryText(context),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.locale, required this.message});
  final Locale locale;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: ColorTokens.secondaryText(context),
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              _ApplicationsStrings.loadFailed(locale),
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: ColorTokens.primaryText(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'MTSText',
                fontSize: 13,
                color: ColorTokens.secondaryText(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.locale});

  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return Text(
      _ApplicationsStrings.title(locale),
      style: TextStyle(
        fontFamily: 'MTSCompact',
        fontWeight: FontWeight.w700,
        fontSize: 24,
        height: 1.3,
        color: ColorTokens.primaryText(context),
      ),
    );
  }
}

class _ServiceChips extends StatelessWidget {
  const _ServiceChips({
    required this.locale,
    required this.selectedId,
    required this.onChanged,
  });

  final Locale locale;
  final String selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return CategoryChips(
      categories: applicationServiceChips
          .map(
            (chip) => MarketCategory(
              id: chip.id,
              label: _ApplicationsStrings.serviceChip(locale, chip.id),
            ),
          )
          .toList(growable: false),
      selectedId: selectedId,
      onSelected: onChanged,
      padding: EdgeInsets.zero,
    );
  }
}

class _ApplicationsStrings {
  const _ApplicationsStrings._();

  static String title(Locale l) => switch (l.languageCode) {
    'ru' => 'Заявки',
    'en' => 'Applications',
    _ => 'Arizalar',
  };

  static String empty(Locale l) => switch (l.languageCode) {
    'ru' => 'Заявки не найдены',
    'en' => 'No applications found',
    _ => 'Arizalar topilmadi',
  };

  static String loadFailed(Locale l) => switch (l.languageCode) {
    'ru' => 'Не удалось загрузить',
    'en' => 'Failed to load',
    _ => 'Yuklab boʻlmadi',
  };

  static String serviceChip(Locale l, String id) => switch (id) {
    'all' => switch (l.languageCode) {
      'ru' => 'Все',
      'en' => 'All',
      _ => 'Barchasi',
    },
    'kad_3d' => switch (l.languageCode) {
      'ru' => '3D кадастр',
      'en' => '3D cadastre',
      _ => '3D Kadastr',
    },
    'ai_eval' => switch (l.languageCode) {
      'ru' => 'AI оценка',
      'en' => 'AI valuation',
      _ => 'AI Baholash',
    },
    'calc' => switch (l.languageCode) {
      'ru' => 'Калькулятор',
      'en' => 'Calculator',
      _ => 'Kalkulyator',
    },
    _ => id,
  };

  // ---------------------------------------------------------------------------
  // Static mapper helpers (no BuildContext available → take a language code).
  // These mirror the switch (l.languageCode) style above. Uzbek = default.
  // ---------------------------------------------------------------------------

  static String serviceLabel(String lang, String serviceId) =>
      switch (serviceId) {
        'arch' => switch (lang) {
          'ru' => 'Архитектура ТЗ',
          'en' => 'Architecture TZ',
          _ => 'Arxitektura TZ',
        },
        'ai_eval' => switch (lang) {
          'ru' => 'AI оценка',
          'en' => 'AI valuation',
          _ => 'AI Baholash',
        },
        'calc' => switch (lang) {
          'ru' => 'Калькулятор',
          'en' => 'Calculator',
          _ => 'Kalkulyator',
        },
        'kad_3d' => switch (lang) {
          'ru' => '3D кадастр',
          'en' => '3D cadastre',
          _ => '3D Kadastr',
        },
        // photogrammetry reuses 'kad_3d' serviceId but has its own label
        '3d_scan' => switch (lang) {
          'ru' => '3D скан',
          'en' => '3D scan',
          _ => '3D Skan',
        },
        _ => serviceId,
      };

  static String address(String lang) => switch (lang) {
    'ru' => 'Адрес',
    'en' => 'Address',
    _ => 'Manzil',
  };

  static String estimatedValue(String lang) => switch (lang) {
    'ru' => 'Примерная стоимость',
    'en' => 'Estimated value',
    _ => 'Taxminiy qiymat',
  };

  static String cadastreNumber(String lang) => switch (lang) {
    'ru' => 'Кадастровый номер',
    'en' => 'Cadastre number',
    _ => 'Kadastr raqami',
  };

  static String cadastre(String lang) => switch (lang) {
    'ru' => 'Кадастр',
    'en' => 'Cadastre',
    _ => 'Kadastr',
  };

  static String type(String lang) => switch (lang) {
    'ru' => 'Тип',
    'en' => 'Type',
    _ => 'Turi',
  };

  static String photoCount(String lang) => switch (lang) {
    'ru' => 'Кол-во фото',
    'en' => 'Photo count',
    _ => 'Foto soni',
  };

  static String applicationDate(String lang) => switch (lang) {
    'ru' => 'Дата заявки',
    'en' => 'Application date',
    _ => 'Ariza sanasi',
  };

  static String submitted(String lang) => switch (lang) {
    'ru' => 'Отправлено',
    'en' => 'Submitted',
    _ => 'Yuborilgan',
  };

  static String status(String lang) => switch (lang) {
    'ru' => 'Статус',
    'en' => 'Status',
    _ => 'Holat',
  };

  static String price(String lang) => switch (lang) {
    'ru' => 'Цена',
    'en' => 'Price',
    _ => 'Narx',
  };

  static String objectType(String lang) => switch (lang) {
    'ru' => 'Тип объекта',
    'en' => 'Object type',
    _ => 'Obyekt turi',
  };

  static String model3d(String lang) => switch (lang) {
    'ru' => '3D модель',
    'en' => '3D model',
    _ => '3D model',
  };

  static String error(String lang) => switch (lang) {
    'ru' => 'Ошибка',
    'en' => 'Error',
    _ => 'Xato',
  };

  static String inProgress(String lang) => switch (lang) {
    'ru' => 'В процессе',
    'en' => 'In progress',
    _ => 'Jarayonda',
  };

  static String ready(String lang) => switch (lang) {
    'ru' => 'Готово',
    'en' => 'Ready',
    _ => 'Tayyor',
  };

  static String cancelled(String lang) => switch (lang) {
    'ru' => 'Отменено',
    'en' => 'Cancelled',
    _ => 'Bekor qilingan',
  };

  static String residential(String lang) => switch (lang) {
    'ru' => 'Жилое',
    'en' => 'Residential',
    _ => 'Turar joy',
  };

  static String nonResidential(String lang) => switch (lang) {
    'ru' => 'Нежилое',
    'en' => 'Non-residential',
    _ => 'Noturar joy',
  };

  static String warehouse(String lang) => switch (lang) {
    'ru' => 'Склад',
    'en' => 'Warehouse',
    _ => 'Ombor',
  };

  static String industrial(String lang) => switch (lang) {
    'ru' => 'Промышленное',
    'en' => 'Industrial',
    _ => 'Sanoat',
  };

  static String queued(String lang) => switch (lang) {
    'ru' => 'В очереди',
    'en' => 'Queued',
    _ => 'Navbatda',
  };

  static String processing(String lang) => switch (lang) {
    'ru' => 'Обрабатывается',
    'en' => 'Processing',
    _ => 'Ishlamoqda',
  };

  static String viewResult(String lang) => switch (lang) {
    'ru' => 'Посмотреть результат',
    'en' => 'View result',
    _ => 'Natijani ko‘rish',
  };

  /// Currency-unit suffix word only ("so'm" / "сум" / "soum").
  static String soumUnit(String lang) => switch (lang) {
    'ru' => 'сум',
    'en' => 'soum',
    _ => 'so\'m',
  };

  /// Quantity-unit suffix word only ("ta" / "шт" / "pcs").
  static String pcsUnit(String lang) => switch (lang) {
    'ru' => 'шт',
    'en' => 'pcs',
    _ => 'ta',
  };
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({required this.item, required this.onTap});

  final ApplicationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final status = _StatusStyle.fromGroup(item.statusGroup, lang);
    final showResultButton =
        item.statusGroup == ApplicationStatusGroup.completed;

    final dividerColor = ColorTokens.divider(context);
    return Material(
      color: ColorTokens.cardBg(context),
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
            border: Border.all(color: ColorTokens.outline(context), width: 0.5),
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
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        height: 1.3,
                        color: ColorTokens.primaryText(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusBadge(style: status),
                ],
              ),
              const SizedBox(height: 12),
              Divider(height: 1, thickness: 1, color: dividerColor),
              const SizedBox(height: 12),
              _MetaRow(
                label: '${item.addressLabel}:',
                value: item.addressValue,
              ),
              const SizedBox(height: 12),
              Divider(height: 1, thickness: 1, color: dividerColor),
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
                              _ApplicationsStrings.viewResult(
                                Localizations.localeOf(context).languageCode,
                              ),
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
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w500,
                fontSize: 14,
                height: 1.3,
                color: ColorTokens.secondaryText(context),
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
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w500,
              fontSize: 14,
              height: 1.3,
              color: ColorTokens.primaryText(context),
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

  static _StatusStyle fromGroup(ApplicationStatusGroup group, String lang) =>
      switch (group) {
        ApplicationStatusGroup.sent => _StatusStyle(
          label: _ApplicationsStrings.submitted(lang),
          bgColor: const Color(0xFFE2ECFD),
          fgColor: const Color(0xFF2B7FFF),
          iconAsset: 'assets/icons/application-pending.svg',
        ),
        ApplicationStatusGroup.inProgress => _StatusStyle(
          label: _ApplicationsStrings.inProgress(lang),
          bgColor: const Color(0xFFFCEDE3),
          fgColor: const Color(0xFFF27523),
          iconAsset: 'assets/icons/application-pending.svg',
        ),
        ApplicationStatusGroup.completed => _StatusStyle(
          label: _ApplicationsStrings.ready(lang),
          bgColor: const Color(0xFFD5F3E0),
          fgColor: const Color(0xFF00B447),
          iconAsset: 'assets/icons/application-ready.svg',
        ),
        ApplicationStatusGroup.cancelled => _StatusStyle(
          label: _ApplicationsStrings.cancelled(lang),
          bgColor: const Color(0xFFF8E1E1),
          fgColor: const Color(0xFFEF4444),
          iconAsset: 'assets/icons/application-cancelled.svg',
        ),
      };
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.style});

  final _StatusStyle style;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? style.fgColor.withValues(alpha: 0.18) : style.bgColor;
    return Container(
      height: 24,
      padding: const EdgeInsets.fromLTRB(3, 3, 8, 3),
      decoration: BoxDecoration(
        color: bg,
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
