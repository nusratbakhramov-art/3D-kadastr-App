/// "Bozor" — Home'dagi «Bozor AI» kartasi ochadigan ekran.
///
/// Ikki tab:
///   «E'lonlar»          — ommaviy lenta (`GET /listings/`, faqat `approved`)
///   «Mening e'lonlarim» — tugatilmagan QORALAMALAR + hamma holatdagi e'lonlarim
///
/// Sehrgar shu ekranning ichidagi «E'lon qo'shish» tugmasi orqali ochiladi —
/// ilgari Home kartasi to'g'ridan-to'g'ri sehrgarga olib borardi.
///
/// ⚠️ Bu ekran `bozorRoute(...)` marshrutini ISHLATMAYDI. `closeBozorWizard()`
/// `bozor/` prefiksli hamma marshrutni pop qiladi (`bozor_routes.dart`), ya'ni
/// shu prefiks bilan push qilinsa sehrgar tugagach foydalanuvchi lentaga emas,
/// Home'ga tushib qolardi — 8/8 dagi `pushAndRemoveUntil` ham lentani olib
/// tashlardi.
///
/// "Mening e'lonlarim" IKKI manbani qo'shib ko'rsatadi: qoralamalar alohida
/// jadvalda yashaydi (`bozor_listing_drafts`), ya'ni ularning `id` fazosi
/// e'lonlardan boshqa. Shu sababli ular alohida so'rov bilan olinadi va
/// ro'yxatda alohida karta bilan chiziladi.
library;

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/app_toast.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../bozor_resume.dart';
import '../bozor_routes.dart';
import '../data/bozor_api.dart';
import '../models/bozor_draft.dart';
import '../models/bozor_listing.dart';
import '../screens/bozor_type_step_screen.dart';
import 'bozor_draft_card.dart';
import 'bozor_listing_card.dart';
import 'bozor_listing_detail_screen.dart';

class BozorHomeScreen extends StatefulWidget {
  const BozorHomeScreen({super.key, this.api});

  /// Faqat testlar uchun.
  final BozorApi? api;

  @override
  State<BozorHomeScreen> createState() => _BozorHomeScreenState();
}

class _BozorHomeScreenState extends State<BozorHomeScreen>
    with SingleTickerProviderStateMixin {
  late final BozorApi _api = widget.api ?? BozorApi();
  late final TabController _tabs = TabController(length: 2, vsync: this);

  // ── «E'lonlar» tabi ───────────────────────────────────────────────────────
  BozorListingPage _feed = BozorListingPage.empty;
  bool _feedLoading = true;
  String? _feedError;

  // ── «Mening e'lonlarim» tabi ──────────────────────────────────────────────
  List<BozorDraftSummary> _drafts = const [];
  List<BozorListing> _mine = const [];
  bool _mineLoading = true;
  String? _mineError;
  bool _authed = false;

  @override
  void initState() {
    super.initState();
    _loadFeed();
    _loadMine();
  }

  @override
  void dispose() {
    _tabs.dispose();
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  Future<void> _loadFeed() async {
    setState(() {
      _feedLoading = true;
      _feedError = null;
    });
    try {
      final page = await _api.listings();
      if (!mounted) return;
      setState(() {
        _feed = page;
        _feedLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _feedError = 'bozor.feed.load_failed';
        _feedLoading = false;
      });
    }
  }

  /// Qoralamalar va e'lonlar BIR VAQTDA olinadi.
  ///
  /// Ikkinchisi yiqilsa birinchisi baribir ko'rsatiladi: qoralama
  /// foydalanuvchining tugatilmagan ishi, uni yashirish mehnatini yo'qotgandek
  /// ko'rinardi.
  ///
  /// Tizimga kirgan-kirmagani SERVER javobidan aniqlanadi, `AuthStorage` dan
  /// emas: token bor, lekin muddati o'tgan bo'lishi ham mumkin — bunda lokal
  /// tekshiruv "kirgan" deb aytadi, server esa rad etadi. Server yagona
  /// haqiqat manbai. (Sarlavha umuman bo'lmasa backend **403** qaytaradi,
  /// 401 esa token yaroqsiz bo'lganda — ikkalasi ham "kirmagan".)
  Future<void> _loadMine() async {
    setState(() {
      _mineLoading = true;
      _mineError = null;
    });
    final results = await Future.wait([
      _api.drafts().then<Object?>((v) => v).catchError(_asError),
      _api.myListings().then<Object?>((v) => v).catchError(_asError),
    ]);
    if (!mounted) return;
    final drafts = results[0];
    final mine = results[1];
    setState(() {
      _drafts = drafts is List<BozorDraftSummary> ? drafts : const [];
      _mine = mine is BozorListingPage ? mine.items : const [];
      _authed = !(_isAuthError(drafts) || _isAuthError(mine));
      // Xato faqat IKKALASI ham yiqilganda ko'rsatiladi.
      _mineError = (drafts is BozorApiException && mine is BozorApiException)
          ? 'bozor.feed.load_failed'
          : null;
      _mineLoading = false;
    });
  }

  /// `catchError` uchun: istisnoni QAYTARADI, yutmaydi — chaqiruvchi 401/403
  /// ni boshqa xatolardan ajratishi kerak.
  static Object? _asError(Object e) =>
      e is BozorApiException ? e : BozorApiException(e.toString());

  static bool _isAuthError(Object? v) =>
      v is BozorApiException && (v.statusCode == 401 || v.statusCode == 403);

  Future<void> _openWizard() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: bozorRoute('type'),
        builder: (_) => BozorTypeStepScreen(draft: BozorDraft()),
      ),
    );
    // Sehrgardan qaytilganda ro'yxat eskirgan bo'ladi: qoralama saqlangan
    // yoki e'lon yuborilgan bo'lishi mumkin.
    if (mounted) {
      _loadMine();
      _loadFeed();
    }
  }

  Future<void> _openListing(BozorListing listing) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BozorListingDetailScreen(listingId: listing.id),
      ),
    );
    // Detalda e'lon arxivlangan/tahrirlangan bo'lishi mumkin.
    if (mounted) _loadMine();
  }

  Future<void> _openDraft(BozorDraftSummary d) async {
    await openBozorDraft(context, d);
    if (mounted) {
      _loadMine();
      _loadFeed();
    }
  }

  Future<void> _deleteDraft(BozorDraftSummary d) async {
    final l = Localizations.localeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ColorTokens.sheetBg(ctx),
        title: Text(tr(l, 'bozor.draft.delete_title')),
        content: Text(tr(l, 'bozor.draft.delete_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr(l, 'common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              tr(l, 'bozor.draft.delete'),
              style: const TextStyle(color: Color(0xFFE0492A)),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      // O'chirish JIM EMAS (qadam saqlashlaridan farqli): foydalanuvchi
      // ataylab bosgan, natijani ko'rishi kerak.
      await _api.deleteDraft(d.id);
      if (!mounted) return;
      // Serverga qayta so'rov yubormasdan ro'yxatdan olib tashlaymiz.
      setState(() => _drafts = [for (final x in _drafts) if (x.id != d.id) x]);
    } catch (_) {
      if (mounted) AppToast.error(context, tr(l, 'bozor.draft.delete_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final fg = isDark ? Colors.white : AppColors.textBlack;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: fg,
        title: Text(
          tr(l, 'bozor.feed.title'),
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: fg,
          ),
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.splashGreen,
          unselectedLabelColor: ColorTokens.secondaryText(context),
          indicatorColor: AppColors.splashGreen,
          labelStyle: const TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          tabs: [
            Tab(text: tr(l, 'bozor.feed.tab_all')),
            Tab(text: tr(l, 'bozor.feed.tab_mine')),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [_buildFeedTab(l), _buildMineTab(l)],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: ListingCtaButton(
                label: tr(l, 'bozor.feed.add'),
                onTap: _openWizard,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedTab(Locale l) {
    if (_feedLoading) return const _Spinner();
    if (_feedError != null) {
      return _ErrorState(messageKey: _feedError!, onRetry: _loadFeed);
    }
    if (_feed.items.isEmpty) {
      return _EmptyState(
        icon: Icons.storefront_outlined,
        messageKey: 'bozor.feed.empty_all',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFeed,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        itemCount: _feed.items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final item = _feed.items[i];
          return BozorListingCard(
            listing: item,
            onTap: () => _openListing(item),
          );
        },
      ),
    );
  }

  Widget _buildMineTab(Locale l) {
    if (!_authed && !_mineLoading) {
      return _EmptyState(
        icon: Icons.lock_outline_rounded,
        messageKey: 'bozor.feed.login_required',
      );
    }
    if (_mineLoading) return const _Spinner();
    if (_mineError != null) {
      return _ErrorState(messageKey: _mineError!, onRetry: _loadMine);
    }
    if (_drafts.isEmpty && _mine.isEmpty) {
      return _EmptyState(
        icon: Icons.inbox_outlined,
        messageKey: 'bozor.feed.empty_mine',
      );
    }
    // Qoralamalar TEPADA: ular tugatilmagan ish, ya'ni foydalanuvchidan
    // harakat kutadi. Tasdiqlangan e'lon esa allaqachon ishlab turadi.
    final total = _drafts.length + _mine.length;
    return RefreshIndicator(
      onRefresh: _loadMine,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        itemCount: total,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          if (i < _drafts.length) {
            final d = _drafts[i];
            return BozorDraftCard(
              draft: d,
              onTap: () => _openDraft(d),
              onDelete: () => _deleteDraft(d),
            );
          }
          final item = _mine[i - _drafts.length];
          return BozorListingCard(
            listing: item,
            showStatus: true,
            onTap: () => _openListing(item),
          );
        },
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const Center(
    child: SizedBox(
      width: 26,
      height: 26,
      child: CircularProgressIndicator(strokeWidth: 2.4),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.messageKey});

  final IconData icon;
  final String messageKey;

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final color = ColorTokens.secondaryText(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 12),
            Text(
              tr(l, messageKey),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'MTSText',
                fontSize: 14,
                height: 1.4,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.messageKey, required this.onRetry});

  final String messageKey;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final color = ColorTokens.secondaryText(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 40, color: color),
            const SizedBox(height: 12),
            Text(
              tr(l, messageKey),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'MTSText',
                fontSize: 14,
                height: 1.4,
                color: color,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              child: Text(
                tr(l, 'bozor.feed.retry'),
                style: const TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  color: AppColors.splashGreen,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
