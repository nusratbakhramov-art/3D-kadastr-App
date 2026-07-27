import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/haptics.dart';
import '../../core/i18n/app_translations.dart';
import '../../theme/app_colors.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/app_header_back.dart';
import '../auth/auth_storage.dart';
import '../settings/settings_state.dart';
import '../services/ai_draft_resume.dart';
import '../services/api_ai_valuation_job_service.dart';
import '../services/screens/ai_status_screen.dart';
import '../services/api_architecture_order_service.dart';
import '../services/api_calculator_order_service.dart';
import '../services/api_design_order_service.dart';
import '../services/api_kadastr_3d_job_service.dart';
import '../services/api_photogrammetry_service.dart';
import 'application_detail_screen.dart';
import '../market/models/market_listing.dart' show MarketCategory;
import '../market/widgets/category_chips.dart';
import 'application_model.dart';

class ApplicationsScreen extends StatefulWidget {
  const ApplicationsScreen({
    super.key,
    this.animateToken = 0,
    this.lockedServiceId,
    this.titleOverride,
  });

  final int animateToken;

  /// Agar berilsa, ekran faqat shu xizmat arizalarini ko'rsatadi: chiplar
  /// yashiriladi va tepada orqaga qaytish sarlavhasi chiqadi (profil menyusidan
  /// "Mening arizalarim" = `calc`, "Baholashlarim" = `ai_eval` uchun).
  final String? lockedServiceId;

  /// Locked rejimda ko'rsatiladigan sarlavha (yo'q bo'lsa "Arizalar").
  final String? titleOverride;

  @override
  State<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends State<ApplicationsScreen>
    with AutomaticKeepAliveClientMixin {
  static const int _pageSize = 6;
  static const double _scrollToTopThreshold = 620;
  static const double _loadMoreThreshold = 360;

  late String _selectedServiceId;
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

  // ── Qidiruv + filtrlar (mijoz tomonida — barcha arizalar `_allItems` da) ──
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';
  final Set<ApplicationStatusGroup> _statusFilter = <ApplicationStatusGroup>{};
  DateTime? _dateFrom;
  DateTime? _dateTo;

  int get _activeFilterCount =>
      _statusFilter.length + ((_dateFrom != null || _dateTo != null) ? 1 : 0);

  bool get _hasAnyFilter => _activeFilterCount > 0 || _searchQuery.isNotEmpty;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _selectedServiceId =
        widget.lockedServiceId ?? applicationServiceChips.first.id;
    _scrollController = ScrollController()..addListener(_onScroll);
    // Locked rejim push qilingan ekran — animateToken kelmaydi, shuning uchun
    // darhol yuklaymiz.
    if (widget.lockedServiceId != null || widget.animateToken > 0) {
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
    // Tab qayta ochilganda fonда yangilaymiz — boshqa oqimda yaratilgan yangi
    // ariza (masalan, kalkulyator buyurtmasi) darhol ro'yxatda chiqishi uchun.
    unawaited(_silentRefresh());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
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

  /// Kartaga bosilganda: preview tayyor-yu to'lanmagan AI ariza bo'lsa —
  /// natija + to'lov ekranini qayta ochamiz; aks holda oddiy detal ekrani.
  Future<void> _onCardTap(ApplicationItem item) {
    final previewJobId = item.aiPreviewJobId;
    if (previewJobId != null) return _openAiPreviewPayment(previewJobId);
    return _openDetails(item);
  }

  /// "Jarayonda" (preview_ready) AI arizasini — foydalanuvchi natijani ko'rgan,
  /// lekin to'lamagan — o'sha natija + to'lov ekranida qayta ochadi (qolgan
  /// qadam). Qaytganda ro'yxatni yangilaymiz: to'lov holatni o'zgartirgan
  /// bo'lishi mumkin (preview_ready → under_review).
  Future<void> _openAiPreviewPayment(int jobId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'ai/preview-payment'),
        builder: (_) => AiStatusScreen.existing(jobId: jobId),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _openDetails(ApplicationItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ApplicationDetailScreen(item: item),
      ),
    );
  }

  /// DRAFT AI Baholash arizasini saqlangan qadamdan davom ettiradi, qaytganda
  /// ro'yxatni yangilaydi (draft tugallanib status o'zgargan bo'lishi mumkin).
  Future<void> _resumeDraft(int jobId) async {
    try {
      await resumeAiDraft(context, jobId);
    } catch (_) {
      // resume ichidagi xatolar (token / tarmoq) — jim; ro'yxat o'zgarmaydi.
    }
    if (mounted) await _refresh();
  }

  List<ApplicationItem> get _sourceItems {
    Iterable<ApplicationItem> items = _allItems;

    // Xizmat chipi.
    if (_selectedServiceId != 'all') {
      items = items.where((item) => item.serviceId == _selectedServiceId);
    }
    // Holat (status) filtri.
    if (_statusFilter.isNotEmpty) {
      items = items.where((item) => _statusFilter.contains(item.statusGroup));
    }
    // Sana oralig'i (ariza yaratilgan sana bo'yicha).
    if (_dateFrom != null) {
      final from = DateTime(_dateFrom!.year, _dateFrom!.month, _dateFrom!.day);
      items = items.where((item) => !item.createdAt.isBefore(from));
    }
    if (_dateTo != null) {
      final toEnd = DateTime(_dateTo!.year, _dateTo!.month, _dateTo!.day)
          .add(const Duration(days: 1));
      items = items.where((item) => item.createdAt.isBefore(toEnd));
    }
    // Matnli qidiruv — #id, kadastr/manzil, tur bo'yicha.
    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      items = items.where((item) => _matchesQuery(item, q));
    }
    return items.toList(growable: false);
  }

  bool _matchesQuery(ApplicationItem item, String q) {
    final buf = StringBuffer()
      ..write(item.addressValue)
      ..write(' ')
      ..write(item.typeValue ?? '')
      ..write(' ')
      ..write(item.serviceLabel);
    if (item.orderNo != null) {
      buf.write(' #${item.orderNo} ${item.orderNo}');
    }
    return buf.toString().toLowerCase().contains(q);
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

    // Dizayn TZ buyurtmalari (`GET /services/design/orders`).
    final designFuture = DesignOrderApiService()
        .list(token: token, page: 1, size: 100)
        .then(
          (page) =>
              page.items.map(_designToApplicationItem).toList(growable: false),
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
      designFuture,
    ]);
    final combined = <ApplicationItem>[
      ...results[0],
      ...results[1],
      ...results[2],
      ...results[3],
      ...results[4],
      ...results[5],
    ];
    // Yangidan eskigacha tartiblash — haqiqiy DateTime (updatedAt) bo'yicha,
    // oxirgi yangilangani tepada.
    combined.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _allItems = combined;
  }

  static ApplicationItem _orderToApplicationItem(OrderSummary o) {
    final lang = localeNotifier.value.languageCode;
    final group = _statusToGroup(o.status);
    return ApplicationItem(
      id: 'arch_${o.id}',
      orderNo: o.id,
      // Arxitektura/Dizayn TZ — kalkulyator xizmatlari, "Kalkulyator" chipi
      // ostida ko'rsatamiz (serviceLabel kartada turini ko'rsatadi).
      serviceId: 'calc',
      serviceLabel: tr(Locale(lang), 'applications.service.arch'),
      statusGroup: group,
      createdAt: o.createdAt,
      updatedAt: o.updatedAt,
      addressLabel: tr(Locale(lang), 'applications.address'),
      addressValue: (o.address ?? o.cadastreNumber ?? '—'),
      dateLabel: tr(Locale(lang), 'applications.application_date'),
      dateValue: _formatDateTime(o.updatedAt),
      // Detail ekran arizani backend sxemasi bo'yicha to'liq ko'rsatadi
      // (barcha to'ldirilgan maydonlar, bo'limga ajratilgan). `raw` — list
      // javobining xom payload'i (barcha ustunlar + details).
      formKey: 'arxitektura_tz',
      formPayload: o.raw,
      detailRows: [
        (tr(Locale(lang), 'applications.address'), o.address ?? '—'),
        if (o.cadastreNumber != null)
          (tr(Locale(lang), 'applications.cadastre_number'), o.cadastreNumber!),
        (tr(Locale(lang), 'applications.status'), _groupLabel(group)),
        (tr(Locale(lang), 'applications.application_date'), _formatDateTime(o.createdAt)),
        (tr(Locale(lang), 'applications.updated_at'), _formatDateTime(o.updatedAt)),
      ],
      timeline: _basicTimeline(group, o.createdAt),
    );
  }

  static ApplicationItem _designToApplicationItem(DesignOrderSummary o) {
    final lang = localeNotifier.value.languageCode;
    final group = _statusToGroup(o.status);
    return ApplicationItem(
      id: 'design_${o.id}',
      orderNo: o.id,
      serviceId: 'calc',
      serviceLabel: tr(Locale(lang), 'applications.service.design'),
      statusGroup: group,
      createdAt: o.createdAt,
      updatedAt: o.updatedAt,
      addressLabel: tr(Locale(lang), 'applications.address'),
      addressValue: o.address ?? '—',
      dateLabel: tr(Locale(lang), 'applications.application_date'),
      dateValue: _formatDateTime(o.updatedAt),
      formKey: 'dizayn_tz',
      formPayload: o.raw,
      detailRows: [
        if (o.address != null)
          (tr(Locale(lang), 'applications.address'), o.address!),
        (tr(Locale(lang), 'applications.status'), _groupLabel(group)),
        (tr(Locale(lang), 'applications.application_date'), _formatDateTime(o.createdAt)),
        (tr(Locale(lang), 'applications.updated_at'), _formatDateTime(o.updatedAt)),
      ],
      timeline: _basicTimeline(group, o.createdAt),
    );
  }

  static ApplicationItem _aiJobToApplicationItem(AiJobSummary j) {
    final lang = localeNotifier.value.languageCode;
    final hasValue = j.estimatedValue != null;
    final isDraft = j.status.isDraft;
    final group = _aiJobStatusToGroup(j.status);
    return ApplicationItem(
      id: 'aival_${j.id}',
      orderNo: j.id,
      aiJobId: j.id,
      serviceId: 'ai_eval',
      serviceLabel: tr(Locale(lang), 'applications.service.ai_eval'),
      statusGroup: group,
      isDraft: isDraft,
      resumeJobId: isDraft ? j.id : null,
      aiScanJobId: j.hasScan ? j.id : null,
      // Yakuniy Xulosa (PDF) faqat ariza COMPLETED bo'lganda yuklab olinadi.
      aiReportJobId: j.status == AiJobStatus.completed ? j.id : null,
      estimatorComment: j.estimatorComment,
      estimatorCause: j.estimatorCause,
      // Natija (taxminiy qiymat) tayyor — under_review yoki completed.
      hasResultPreview: hasValue && j.status.hasResult,
      // Preview tayyor, lekin hali to'lanmagan — kartaga bosilganda natija +
      // to'lov ekrani qayta ochiladi (foydalanuvchi qolgan joyidan davom etadi).
      aiPreviewJobId:
          j.status == AiJobStatus.previewReady ? j.id : null,
      createdAt: j.createdAt,
      updatedAt: j.updatedAt,
      addressLabel: hasValue
          ? tr(Locale(lang), 'applications.estimated_value')
          : tr(Locale(lang), 'applications.cadastre_number'),
      addressValue: hasValue
          ? _formatUzs(j.estimatedValue!)
          : (j.cadastreNumber ?? '—'),
      dateLabel: tr(Locale(lang), 'applications.application_date'),
      dateValue: _formatDateTime(j.updatedAt),
      typeLabel: hasValue && j.cadastreNumber != null
          ? tr(Locale(lang), 'applications.cadastre')
          : null,
      typeValue: hasValue ? j.cadastreNumber : null,
      detailRows: [
        if (j.cadastreNumber != null)
          (tr(Locale(lang), 'applications.cadastre_number'), j.cadastreNumber!),
        if (hasValue)
          (tr(Locale(lang), 'applications.estimated_value'), _formatUzs(j.estimatedValue!)),
        (tr(Locale(lang), 'applications.status'), _groupLabel(group)),
        (tr(Locale(lang), 'applications.application_date'), _formatDateTime(j.createdAt)),
        (tr(Locale(lang), 'applications.updated_at'), _formatDateTime(j.updatedAt)),
      ],
      // A draft was NOT submitted — show a single "Qoralama" step, not the
      // accepted → sent-to-system timeline of a real application.
      timeline: isDraft
          ? [
              ApplicationTimelineStep(
                status: ApplicationTimelineStatus.draft,
                at: j.updatedAt,
                completed: true,
              ),
            ]
          : _basicTimeline(group, j.createdAt),
    );
  }

  static ApplicationItem _calcToApplicationItem(CalculatorOrderSummary o) {
    final lang = localeNotifier.value.languageCode;
    final group = _calcStatusToGroup(o.status);
    return ApplicationItem(
      id: 'calc_${o.id}',
      orderNo: o.id,
      serviceId: 'calc',
      serviceLabel: tr(Locale(lang), 'applications.service.calc'),
      statusGroup: group,
      createdAt: o.createdAt,
      updatedAt: o.updatedAt,
      addressLabel: tr(Locale(lang), 'applications.type'),
      addressValue: o.categoryTitle,
      dateLabel: tr(Locale(lang), 'applications.application_date'),
      dateValue: _formatDateTime(o.updatedAt),
      typeLabel: tr(Locale(lang), 'applications.price'),
      typeValue: _formatUzs(o.totalUzs),
      detailRows: [
        (tr(Locale(lang), 'applications.type'), o.categoryTitle),
        (tr(Locale(lang), 'applications.price'), _formatUzs(o.totalUzs)),
        (tr(Locale(lang), 'applications.status'), _groupLabel(group)),
        (tr(Locale(lang), 'applications.application_date'), _formatDateTime(o.createdAt)),
        (tr(Locale(lang), 'applications.updated_at'), _formatDateTime(o.updatedAt)),
      ],
      timeline: _basicTimeline(group, o.createdAt),
    );
  }

  static ApplicationItem _kadastr3dToApplicationItem(Kadastr3dJobSummary j) {
    final lang = localeNotifier.value.languageCode;
    final group = _kadastr3dStatusToGroup(j.status);
    final objectType = _objectTypeLabel(j.objectType);
    // Once delivered (COMPLETED) the specialist's PDF / 3D model are downloadable
    // — wire the detail-screen cards to the per-job download endpoints.
    final delivered = j.status == Kadastr3dJobStatus.completed;
    return ApplicationItem(
      id: 'kad3d_${j.id}',
      orderNo: j.id,
      serviceId: 'kad_3d',
      serviceLabel: tr(Locale(lang), 'applications.service.kad_3d'),
      statusGroup: group,
      k3dJobId: j.id,
      k3dReportJobId: delivered && j.hasReport ? j.id : null,
      k3dModelJobId: delivered && j.hasModel ? j.id : null,
      k3dModelExt: j.modelExt,
      createdAt: j.createdAt,
      updatedAt: j.updatedAt,
      addressLabel: tr(Locale(lang), 'applications.cadastre_number'),
      addressValue: j.cadastreNumber ?? '—',
      dateLabel: tr(Locale(lang), 'applications.application_date'),
      dateValue: _formatDateTime(j.updatedAt),
      typeLabel: objectType != null
          ? tr(Locale(lang), 'applications.object_type')
          : null,
      typeValue: objectType,
      detailRows: [
        if (j.cadastreNumber != null)
          (tr(Locale(lang), 'applications.cadastre_number'), j.cadastreNumber!),
        if (objectType != null)
          (tr(Locale(lang), 'applications.object_type'), objectType),
        (tr(Locale(lang), 'applications.status'), _groupLabel(group)),
        (tr(Locale(lang), 'applications.application_date'), _formatDateTime(j.createdAt)),
        (tr(Locale(lang), 'applications.updated_at'), _formatDateTime(j.updatedAt)),
      ],
      timeline: _basicTimeline(group, j.createdAt),
    );
  }

  static ApplicationStatusGroup _kadastr3dStatusToGroup(Kadastr3dJobStatus s) {
    return switch (s) {
      Kadastr3dJobStatus.completed => ApplicationStatusGroup.completed,
      Kadastr3dJobStatus.failed => ApplicationStatusGroup.cancelled,
      Kadastr3dJobStatus.processing => ApplicationStatusGroup.inProgress,
      // Admin acknowledged it — user sees a distinct "Qabul qilindi" state.
      Kadastr3dJobStatus.received => ApplicationStatusGroup.received,
      Kadastr3dJobStatus.submitted => ApplicationStatusGroup.sent,
    };
  }

  static String? _objectTypeLabel(String? wire) {
    final lang = localeNotifier.value.languageCode;
    return switch (wire) {
      'residential' => tr(Locale(lang), 'applications.object.residential'),
      'non_residential' => tr(Locale(lang), 'applications.object.non_residential'),
      'warehouse' => tr(Locale(lang), 'applications.object.warehouse'),
      'industrial' => tr(Locale(lang), 'applications.object.industrial'),
      _ => null,
    };
  }

  static String _groupLabel(ApplicationStatusGroup g) {
    final lang = localeNotifier.value.languageCode;
    return switch (g) {
      ApplicationStatusGroup.sent => tr(Locale(lang), 'applications.submitted'),
      ApplicationStatusGroup.received => tr(Locale(lang), 'applications.received'),
      ApplicationStatusGroup.inProgress => tr(Locale(lang), 'applications.in_progress'),
      ApplicationStatusGroup.completed => tr(Locale(lang), 'applications.ready'),
      ApplicationStatusGroup.cancelled => tr(Locale(lang), 'applications.cancelled'),
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
      // AI dastlabki natija tayyor, lekin to'lov qilinmagan — ariza hali
      // YUBORILMAGAN. "Jarayonda" ko'rinadi (natija ko'rinadi, to'lov kutilmoqda).
      AiJobStatus.previewReady => ApplicationStatusGroup.inProgress,
      // AI natija tayyor, lekin mutaxassis hisobotni hali yakunlamagan —
      // foydalanuvchiga "Yuborildi" ko'rinadi (natija ko'rinadi, hisobot kutilmoqda).
      AiJobStatus.underReview => ApplicationStatusGroup.sent,
      // Mutaxassis arizani qabul qildi — "Qabul qilindi" (Yuborildi → Tayyor oralig'i).
      AiJobStatus.received => ApplicationStatusGroup.received,
      _ => ApplicationStatusGroup.inProgress,
    };
  }

  static ApplicationItem _photogrammetryToApplicationItem(
    PhotogrammetryJobSummary j,
  ) {
    final lang = localeNotifier.value.languageCode;
    final group = _photogrammetryStatusToGroup(j.status);
    final photoCountValue =
        '${j.photoCount} ${tr(Locale(lang), 'applications.unit.pcs')}';
    return ApplicationItem(
      id: 'photo_${j.id}',
      orderNo: j.id,
      serviceId: 'kad_3d',
      serviceLabel: tr(Locale(lang), 'applications.service.3d_scan'),
      statusGroup: group,
      createdAt: j.createdAt,
      updatedAt: j.updatedAt,
      addressLabel: tr(Locale(lang), 'applications.photo_count'),
      addressValue: photoCountValue,
      dateLabel: tr(Locale(lang), 'applications.submitted'),
      dateValue: _formatDateTime(j.updatedAt),
      typeLabel: j.isCompleted
          ? tr(Locale(lang), 'applications.model_3d')
          : (j.status == 'failed'
              ? tr(Locale(lang), 'applications.error')
              : tr(Locale(lang), 'applications.status')),
      typeValue: j.isCompleted
          ? tr(Locale(lang), 'applications.ready')
          : (j.errorMessage ?? _photogrammetryStatusLabel(j.status)),
      detailRows: [
        (tr(Locale(lang), 'applications.photo_count'), photoCountValue),
        (tr(Locale(lang), 'applications.status'), _photogrammetryStatusLabel(j.status)),
        if (j.errorMessage != null)
          (tr(Locale(lang), 'applications.error'), j.errorMessage!),
        (tr(Locale(lang), 'applications.submitted'), _formatDateTime(j.createdAt)),
        (tr(Locale(lang), 'applications.updated_at'), _formatDateTime(j.updatedAt)),
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
      'pending' => tr(Locale(lang), 'applications.queued'),
      'processing' => tr(Locale(lang), 'applications.processing'),
      'completed' => tr(Locale(lang), 'applications.ready'),
      'failed' => tr(Locale(lang), 'applications.error'),
      'cancelled' => tr(Locale(lang), 'applications.cancelled'),
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
    return '${buf.toString()} ${tr(Locale(lang), 'applications.unit.soum')}';
  }


  static String _formatDateTime(DateTime dt) {
    final d = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
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

  /// Fonда yangilash — eski ro'yxatni bo'sh ko'rsatmasdan backend'dan qayta
  /// oladi va ko'rinishni yangilaydi (tab qayta faollashganda). Xato bo'lsa
  /// eski ro'yxat saqlanadi (jim).
  Future<void> _silentRefresh() async {
    if (_loadingInitial || _refreshing) return;
    final requestId = ++_requestId;
    try {
      await _fetchAllFromBackend();
    } catch (_) {
      return; // tarmoq/token xatosi — eski ro'yxat qoladi
    }
    if (!mounted || requestId != _requestId) return;
    final source = _sourceItems;
    // Hozir ko'rsatilayotgan miqdorni saqlaymiz (skroll uzilmasligi uchun),
    // kamida bitta sahifa.
    final keep = _items.length < _pageSize ? _pageSize : _items.length;
    final next = source.take(keep).toList(growable: false);
    setState(() {
      _items
        ..clear()
        ..addAll(next);
      _nextOffset = next.length;
      _hasMore = _nextOffset < source.length;
      _entryEpoch++;
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

  void _reapply() {
    if (_initialized) unawaited(_loadFirstPage());
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 260), () {
      if (!mounted || value == _searchQuery) return;
      setState(() => _searchQuery = value);
      _reapply();
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    if (_searchQuery.isEmpty) return;
    setState(() => _searchQuery = '');
    _reapply();
  }

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<_FilterResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterSheet(
        initialStatuses: _statusFilter,
        initialFrom: _dateFrom,
        initialTo: _dateTo,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _statusFilter
        ..clear()
        ..addAll(result.statuses);
      _dateFrom = result.from;
      _dateTo = result.to;
    });
    _reapply();
  }

  void _removeStatus(ApplicationStatusGroup group) {
    setState(() => _statusFilter.remove(group));
    _reapply();
  }

  void _clearDateRange() {
    setState(() {
      _dateFrom = null;
      _dateTo = null;
    });
    _reapply();
  }

  void _clearAllFilters() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    setState(() {
      _statusFilter.clear();
      _dateFrom = null;
      _dateTo = null;
      _searchQuery = '';
    });
    _reapply();
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
            CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  // Native iOS "spin + ticks" tortib-yangilash indikatori.
                  CupertinoSliverRefreshControl(onRefresh: _refresh),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.lockedServiceId != null)
                            AppHeaderBack(
                              title: widget.titleOverride ??
                                  tr(locale, 'applications.title'),
                            )
                          else ...[
                            _Title(locale: locale),
                            const SizedBox(height: 14),
                            _ServiceChips(
                              locale: locale,
                              selectedId: _selectedServiceId,
                              onChanged: _onServiceChanged,
                            ),
                          ],
                          const SizedBox(height: 12),
                          _SearchFilterBar(
                            locale: locale,
                            controller: _searchCtrl,
                            onChanged: _onSearchChanged,
                            onClear: _clearSearch,
                            hasQuery: _searchQuery.isNotEmpty,
                            activeFilterCount: _activeFilterCount,
                            onOpenFilters: _openFilterSheet,
                          ),
                          if (_activeFilterCount > 0) ...[
                            const SizedBox(height: 10),
                            _ActiveFilters(
                              locale: locale,
                              statuses: _statusFilter,
                              from: _dateFrom,
                              to: _dateTo,
                              onRemoveStatus: _removeStatus,
                              onClearDates: _clearDateRange,
                              onClearAll: _clearAllFilters,
                            ),
                          ],
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
                      child: _EmptyState(
                        locale: locale,
                        filtered: _hasAnyFilter,
                        onReset: _clearAllFilters,
                      ),
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
                                onTap: () => _onCardTap(item),
                                onResume: item.resumeJobId == null
                                    ? null
                                    : () => _resumeDraft(item.resumeJobId!),
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
              onTap: hapticTap(onTap),
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
  const _EmptyState({required this.locale, this.filtered = false, this.onReset});

  final Locale locale;
  final bool filtered;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final lang = locale.languageCode;
    if (!filtered) {
      return Center(
        child: Text(
          tr(locale, 'applications.empty'),
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w500,
            fontSize: 15,
            color: ColorTokens.secondaryText(context),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                size: 34, color: ColorTokens.secondaryText(context)),
            const SizedBox(height: 10),
            Text(
              tr(Locale(lang), 'applications.no_results'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: ColorTokens.primaryText(context),
              ),
            ),
            if (onReset != null) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: hapticTap(onReset),
                child: Text(
                  tr(Locale(lang), 'applications.reset'),
                  style: const TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: AppColors.splashGreen,
                  ),
                ),
              ),
            ],
          ],
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
              tr(locale, 'applications.load_failed'),
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
      tr(locale, 'applications.title'),
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
              label: tr(locale, 'applications.chip.${chip.id}'),
            ),
          )
          .toList(growable: false),
      selectedId: selectedId,
      onSelected: onChanged,
      padding: EdgeInsets.zero,
    );
  }
}

// ── Qidiruv maydoni + filtr tugmasi ──────────────────────────────────────
class _SearchFilterBar extends StatelessWidget {
  const _SearchFilterBar({
    required this.locale,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.hasQuery,
    required this.activeFilterCount,
    required this.onOpenFilters,
  });

  final Locale locale;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool hasQuery;
  final int activeFilterCount;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = locale.languageCode;
    final fill = isDark ? const Color(0xFF1C2123) : const Color(0xFFF1F2F4);
    final border = isDark ? const Color(0xFF2A2F31) : const Color(0xFFE3E5E8);
    final textColor = ColorTokens.primaryText(context);
    final hint = ColorTokens.secondaryText(context);

    return Row(
      children: [
        Expanded(
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                Icon(Icons.search, size: 20, color: hint),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                    textInputAction: TextInputAction.search,
                    style: TextStyle(
                      fontFamily: 'MTSText',
                      fontSize: 15,
                      color: textColor,
                    ),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: tr(Locale(lang), 'applications.search_hint'),
                      hintStyle: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 15,
                        color: hint,
                      ),
                    ),
                  ),
                ),
                if (hasQuery)
                  GestureDetector(
                    onTap: hapticTap(onClear),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(Icons.close_rounded, size: 18, color: hint),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: hapticTap(onOpenFilters),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: activeFilterCount > 0 ? AppColors.splashGreen : fill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: activeFilterCount > 0 ? AppColors.splashGreen : border,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 22,
                  color: activeFilterCount > 0 ? Colors.white : hint,
                ),
                if (activeFilterCount > 0)
                  Positioned(
                    top: 5,
                    right: 5,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 15),
                      height: 15,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$activeFilterCount',
                        style: const TextStyle(
                          fontFamily: 'MTSCompact',
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          height: 1,
                          color: AppColors.splashGreen,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Faol filtrlar (o'chirib bo'ladigan chiplar) ──────────────────────────
class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({
    required this.locale,
    required this.statuses,
    required this.from,
    required this.to,
    required this.onRemoveStatus,
    required this.onClearDates,
    required this.onClearAll,
  });

  final Locale locale;
  final Set<ApplicationStatusGroup> statuses;
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<ApplicationStatusGroup> onRemoveStatus;
  final VoidCallback onClearDates;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final lang = locale.languageCode;
    final chips = <Widget>[];
    for (final g in ApplicationStatusGroup.values) {
      if (!statuses.contains(g)) continue;
      final st = _StatusStyle.fromGroup(g, lang);
      chips.add(_FilterChipPill(
        label: st.label,
        color: st.fgColor,
        onRemove: () => onRemoveStatus(g),
      ));
    }
    if (from != null || to != null) {
      chips.add(_FilterChipPill(
        label: _dateRangeLabel(lang, from, to),
        color: AppColors.splashGreen,
        onRemove: onClearDates,
      ));
    }
    if (chips.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i < chips.length) return chips[i];
          return GestureDetector(
            onTap: hapticTap(onClearAll),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                tr(Locale(lang), 'applications.reset'),
                style: TextStyle(
                  fontFamily: 'MTSText',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ColorTokens.secondaryText(context),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FilterChipPill extends StatelessWidget {
  const _FilterChipPill({
    required this.label,
    required this.color,
    required this.onRemove,
  });

  final String label;
  final Color color;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 0, 7, 0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 3),
          GestureDetector(
            onTap: hapticTap(onRemove),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 14, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

String _shortDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${(d.year % 100).toString().padLeft(2, '0')}';

String _fullDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String _dateRangeLabel(String lang, DateTime? from, DateTime? to) {
  if (from != null && to != null) return '${_shortDate(from)} – ${_shortDate(to)}';
  if (from != null) return '${tr(Locale(lang), 'applications.from')} ${_shortDate(from)}';
  if (to != null) return '${tr(Locale(lang), 'applications.to')} ${_shortDate(to)}';
  return '';
}

// ── Filtr natijasi (bottom-sheet qaytaradi) ──────────────────────────────
class _FilterResult {
  const _FilterResult({required this.statuses, this.from, this.to});
  final Set<ApplicationStatusGroup> statuses;
  final DateTime? from;
  final DateTime? to;
}

// ── Filtr bottom-sheet (holat + sana oralig'i) ───────────────────────────
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.initialStatuses,
    required this.initialFrom,
    required this.initialTo,
  });

  final Set<ApplicationStatusGroup> initialStatuses;
  final DateTime? initialFrom;
  final DateTime? initialTo;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final Set<ApplicationStatusGroup> _statuses =
      {...widget.initialStatuses};
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _from = widget.initialFrom;
    _to = widget.initialTo;
  }

  Future<void> _pick({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = (isFrom ? _from : _to) ?? now;
    final picked = await _showDateWheel(
      initial: initial,
      first: DateTime(now.year - 3),
      last: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to != null && _to!.isBefore(picked)) _to = picked;
      } else {
        _to = picked;
        if (_from != null && _from!.isAfter(picked)) _from = picked;
      }
    });
  }

  /// Native iOS-uslubidagi g'ildirak (wheel) date-picker — aylantirilganda
  /// haptik javob beradi (CupertinoDatePicker). Tanlangan sanani qaytaradi.
  Future<DateTime?> _showDateWheel({
    required DateTime initial,
    required DateTime first,
    required DateTime last,
  }) {
    final lang = Localizations.localeOf(context).languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1B1F21) : Colors.white;
    final divider = isDark ? const Color(0xFF2A2F31) : const Color(0xFFE3E5E8);
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);
    var temp = initial;

    return showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).padding.bottom;
        return Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(bottom: bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: hapticTap(() => Navigator.of(ctx).pop()),
                      child: Text(
                        tr(Locale(lang), 'applications.cancel'),
                        style: TextStyle(
                          fontFamily: 'MTSText',
                          fontSize: 15,
                          color: muted,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        tr(Locale(lang), 'applications.select_date'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'MTSCompact',
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: titleColor,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: hapticTap(() => Navigator.of(ctx).pop(temp)),
                      child: Text(
                        tr(Locale(lang), 'applications.done'),
                        style: const TextStyle(
                          fontFamily: 'MTSCompact',
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: AppColors.splashGreen,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: divider),
              SizedBox(
                height: 232,
                child: CupertinoTheme(
                  data: CupertinoThemeData(
                    brightness: isDark ? Brightness.dark : Brightness.light,
                  ),
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: initial,
                    minimumDate: first,
                    maximumDate: last,
                    onDateTimeChanged: (d) => temp = d,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF14181A) : Colors.white;
    final textColor = ColorTokens.primaryText(context);
    final muted = ColorTokens.secondaryText(context);
    final media = MediaQuery.of(context);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + media.padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: muted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            tr(Locale(lang), 'applications.filters'),
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w900,
              fontSize: 19,
              color: textColor,
            ),
          ),
          const SizedBox(height: 18),

          // Holat
          _SheetLabel(text: tr(Locale(lang), 'applications.status')),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final g in ApplicationStatusGroup.values)
                _StatusToggle(
                  style: _StatusStyle.fromGroup(g, lang),
                  selected: _statuses.contains(g),
                  onTap: () => setState(() {
                    if (!_statuses.add(g)) _statuses.remove(g);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 22),

          // Sana oralig'i
          _SheetLabel(text: tr(Locale(lang), 'applications.date_range')),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _DateField(
                  label: tr(Locale(lang), 'applications.from'),
                  value: _from == null ? null : _fullDate(_from!),
                  placeholder: tr(Locale(lang), 'applications.any_date'),
                  onTap: () => _pick(isFrom: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DateField(
                  label: tr(Locale(lang), 'applications.to'),
                  value: _to == null ? null : _fullDate(_to!),
                  placeholder: tr(Locale(lang), 'applications.any_date'),
                  onTap: () => _pick(isFrom: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: hapticTap(() => setState(() {
                    _statuses.clear();
                    _from = null;
                    _to = null;
                  })),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: muted.withValues(alpha: 0.4)),
                    ),
                  ),
                  child: Text(
                    tr(Locale(lang), 'applications.reset'),
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: textColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: hapticTap(() => Navigator.of(context).pop(
                    _FilterResult(statuses: _statuses, from: _from, to: _to),
                  )),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.splashGreen,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    tr(Locale(lang), 'applications.apply'),
                    style: const TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontFamily: 'MTSCompact',
          fontWeight: FontWeight.w700,
          fontSize: 13.5,
          color: ColorTokens.secondaryText(context),
        ),
      );
}

class _StatusToggle extends StatelessWidget {
  const _StatusToggle({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final _StatusStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = style.fgColor;
    return GestureDetector(
      onTap: hapticTap(onTap),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: EdgeInsets.fromLTRB(selected ? 11 : 14, 9, 14, 9),
        decoration: BoxDecoration(
          // Har bir holat o'z rangida — tanlangани to'qroq bo'yaladi.
          color: c.withValues(alpha: selected ? 0.18 : 0.07),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: c.withValues(alpha: selected ? 1 : 0.45),
            width: selected ? 1.6 : 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check_rounded, size: 15, color: c),
              const SizedBox(width: 5),
            ],
            Text(
              style.label,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                color: c,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onTap,
  });

  final String label;
  final String? value;
  final String placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? const Color(0xFF1C2123) : const Color(0xFFF1F2F4);
    final border = isDark ? const Color(0xFF2A2F31) : const Color(0xFFE3E5E8);
    final muted = ColorTokens.secondaryText(context);
    final hasValue = value != null;

    return GestureDetector(
      onTap: hapticTap(onTap),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontFamily: 'MTSText', fontSize: 11, color: muted),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: 14, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    hasValue ? value! : placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: hasValue
                          ? ColorTokens.primaryText(context)
                          : muted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Kartaning pastki yashil tugmasi — "Natijani ko'rish" (completed) yoki
/// "Davom etish" (draft).
class _CardActionButton extends StatelessWidget {
  const _CardActionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF00E135),
      borderRadius: BorderRadius.circular(10000),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hapticTap(onTap),
        child: SizedBox(
          width: double.infinity,
          height: 32,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 20,
                  color: Colors.black,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({
    required this.item,
    required this.onTap,
    this.onResume,
  });

  final ApplicationItem item;
  final VoidCallback onTap;

  /// DRAFT arizada "Davom etish" tugmasi bosilganda (resume).
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final status = item.isDraft
        ? _StatusStyle.draft(lang)
        : _StatusStyle.fromGroup(item.statusGroup, lang);
    // Show "Natijani ko'rish" once the ariza is completed, or when an AI result
    // is already viewable (under_review → "Yuborildi") even before the report.
    final showResultButton =
        item.statusGroup == ApplicationStatusGroup.completed ||
            item.hasResultPreview;

    return Material(
      color: ColorTokens.cardBg(context),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hapticTap(onTap),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Service glyph in a rounded chip — gives each card a clear
                  // at-a-glance identity.
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: ColorTokens.iconBg(context),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      _serviceIcon(item.serviceId),
                      size: 22,
                      color: ColorTokens.brandPrimary(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.serviceLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'MTSCompact',
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            height: 1.25,
                            color: ColorTokens.primaryText(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (item.orderNo != null)
                              Text(
                                '#${item.orderNo}',
                                style: TextStyle(
                                  fontFamily: 'MTSCompact',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  height: 1.1,
                                  color: ColorTokens.secondaryText(context),
                                ),
                              ),
                            if (item.orderNo != null && item.typeValue != null)
                              const SizedBox(width: 8),
                            if (item.typeValue != null)
                              Flexible(child: _TypeChip(label: item.typeValue!)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusBadge(style: status),
                ],
              ),
              const SizedBox(height: 14),
              // Grouped meta in a subtly inset panel (label left / value right).
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: ColorTokens.scaffoldBg(context),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    _MetaRow(
                      label: '${item.addressLabel}:',
                      value: item.addressValue,
                    ),
                    const SizedBox(height: 9),
                    _MetaRow(label: '${item.dateLabel}:', value: item.dateValue),
                  ],
                ),
              ),
              if (item.isDraft) ...[
                const SizedBox(height: 14),
                _CardActionButton(
                  label: tr(Locale(lang), 'applications.resume'),
                  onTap: onResume ?? onTap,
                ),
              ] else if (showResultButton) ...[
                const SizedBox(height: 14),
                _CardActionButton(
                  label: tr(Locale(lang), 'applications.view_result'),
                  onTap: onTap,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Service → glyph for the card's leading chip.
IconData _serviceIcon(String serviceId) => switch (serviceId) {
      'kad_3d' => Icons.view_in_ar_rounded,
      'ai_eval' => Icons.insights_rounded,
      'calc' => Icons.calculate_rounded,
      _ => Icons.description_rounded,
    };

/// Small pill for the object type (e.g. "Turar joy") shown next to the #number.
class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ColorTokens.iconBg(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'MTSCompact',
          fontWeight: FontWeight.w600,
          fontSize: 11,
          height: 1.1,
          color: ColorTokens.secondaryText(context),
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

  /// DRAFT (tugallanmagan) ariza badge'i — "Qoralama", amber.
  static _StatusStyle draft(String lang) => _StatusStyle(
        label: tr(Locale(lang), 'applications.draft'),
        bgColor: const Color(0xFFFBEFD6),
        fgColor: const Color(0xFFC98A00),
        iconAsset: 'assets/icons/application-pending.svg',
      );

  static _StatusStyle fromGroup(ApplicationStatusGroup group, String lang) =>
      switch (group) {
        ApplicationStatusGroup.sent => _StatusStyle(
          label: tr(Locale(lang), 'applications.submitted'),
          bgColor: const Color(0xFFE2ECFD),
          fgColor: const Color(0xFF2B7FFF),
          iconAsset: 'assets/icons/application-pending.svg',
        ),
        ApplicationStatusGroup.received => _StatusStyle(
          label: tr(Locale(lang), 'applications.received'),
          bgColor: const Color(0xFFFBEFD6),
          fgColor: const Color(0xFFC98A00),
          iconAsset: 'assets/icons/application-pending.svg',
        ),
        ApplicationStatusGroup.inProgress => _StatusStyle(
          label: tr(Locale(lang), 'applications.in_progress'),
          bgColor: const Color(0xFFFCEDE3),
          fgColor: const Color(0xFFF27523),
          iconAsset: 'assets/icons/application-pending.svg',
        ),
        ApplicationStatusGroup.completed => _StatusStyle(
          label: tr(Locale(lang), 'applications.ready'),
          bgColor: const Color(0xFFD5F3E0),
          fgColor: const Color(0xFF00B447),
          iconAsset: 'assets/icons/application-ready.svg',
        ),
        ApplicationStatusGroup.cancelled => _StatusStyle(
          label: tr(Locale(lang), 'applications.cancelled'),
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
