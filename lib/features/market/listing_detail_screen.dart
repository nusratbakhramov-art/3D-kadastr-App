import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/i18n/app_translations.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../auth/auth_storage.dart';
import '../auth/widgets/login_required_sheet.dart';
import '../home/user_profile.dart' show paymentsHidden;
import '../settings/settings_state.dart';
import 'api_marketplace_service.dart';
import 'listing_3d_viewer_screen.dart';
import 'models/market_listing.dart';
import 'widgets/listing_cta_button.dart';
import 'widgets/listing_formats_card.dart';
import 'widgets/listing_gallery_pager.dart';
import 'widgets/listing_info_card.dart';
import 'widgets/listing_meta_pills.dart';
import 'widgets/market_payment_sheet.dart';

class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({
    super.key,
    required this.listing,
    this.api,
    this.authStorage = const AuthStorage(),
  });

  final MarketListing listing;
  final MarketplaceApiService? api;
  final AuthStorage authStorage;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen>
    with WidgetsBindingObserver {
  late final MarketplaceApiService _api;
  late MarketListing _listing = widget.listing;
  int? _downloadingFileId;

  /// Bepul yoki sotib olingan — yuklab olish/3D ochiq. Aks holda — locked
  /// (formatlar ko'rinadi, lekin bosilganda sotib olishga yo'naltiradi).
  bool get _unlocked => _listing.isFree || _listing.isOwned;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? MarketplaceApiService();
    WidgetsBinding.instance.addObserver(this);
    // Egalik holatini (is_owned) va fayllarni serverdan yangilab olamiz —
    // ro'yxatdan kelgan keshlangan nusxa eskirgan bo'lishi mumkin.
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Payme'dan qaytgach (to'lov tugagan bo'lishi mumkin) egalikni yangilaymiz —
    // yuklab olish/3D tugmalari ochiladi.
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  /// Modelni backenddan qayta oladi — `is_owned` va fayllar yangilanadi. Mock
  /// (backendId yo'q) yoki tarmoq xatosida joriy holat saqlanadi.
  Future<void> _refresh() async {
    final id = widget.listing.backendId;
    if (id == null) return;
    try {
      final fresh = await _api.getModel(id);
      if (mounted) setState(() => _listing = fresh);
    } catch (_) {
      // tarmoq xatosi — joriy holatni saqlaymiz
    }
  }

  void _close() => Navigator.of(context).maybePop();

  bool get _has3DViewable {
    for (final f in _listing.files) {
      final fmt = f.format.toUpperCase();
      if (fmt == 'GLB' || fmt == 'GLTF') return true;
    }
    return false;
  }

  Future<void> _open3DViewer() async {
    // 3D ko'rish BEPUL (sotib olish shart emas) — faqat ko'rish, yuklab olish
    // emas. Mehmonni toza login drawer bilan kutib olamiz (auth talab qilinadi,
    // chunki preview ham token bilan ishlaydi), buzilgan viewer o'rniga.
    if (!await ensureLoggedIn(
      context,
      storage: widget.authStorage,
      message: _loginMsgView(localeNotifier.value),
    )) {
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Listing3DViewerScreen(
          listing: _listing,
          api: _api,
          authStorage: widget.authStorage,
        ),
      ),
    );
  }

  Future<void> _onBuy() async {
    // Reviewer (demo) akkaunti hech qachon sotib ololmaydi — to'lov oqimi
    // ko'rsatilmaydi (locked format bosilsa ham hech narsa qilmaymiz).
    if (paymentsHidden) return;
    // Mehmon → login drawer (xom 401 o'rniga). Login'dan keyin egalik allaqachon
    // bo'lishi mumkin (ilgari shu akkaunt sotib olgan) — qayta tekshiramiz.
    if (!await ensureLoggedIn(
      context,
      storage: widget.authStorage,
      message: _loginMsgBuy(localeNotifier.value),
    )) {
      return;
    }
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    if (_listing.isFree || _listing.isOwned) return; // allaqachon ochiq
    await showMarketPaymentSheet(context, listing: _listing);
  }

  void _share() {
    final l = _listing;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    Share.share(
      '${l.title}\n${l.district} · ${l.areaM2} m²',
      subject: l.title,
      sharePositionOrigin: origin,
    );
  }

  Future<void> _downloadFormat(MarketListingFile file) async {
    if (_downloadingFileId != null) return;
    // Pullik va hali sotib olinmagan — chip ko'rinadi, lekin bosilganda
    // yuklab olish o'rniga sotib olish oqimi ochiladi.
    if (!_unlocked) {
      await _onBuy();
      return;
    }
    final id = _listing.backendId;
    if (id == null) {
      AppToast.error(
        context,
        tr(localeNotifier.value, 'market.viewer.model_id_not_found'),
      );
      return;
    }
    // Gate: mehmon foydalanuvchi → toza login drawer (xom 401/toast emas).
    if (!await ensureLoggedIn(
      context,
      storage: widget.authStorage,
      message: _loginMsgDownload(localeNotifier.value),
    )) {
      return;
    }
    if (!mounted) return;
    final session = await widget.authStorage.loadSession();
    final token = session.token;
    if (token == null) return;
    setState(() => _downloadingFileId = file.id);
    try {
      final info = await _api.getDownloadUrl(
        modelId: id,
        fileId: file.id,
        token: token,
      );
      final bytes = await _bytesFor(info.url);
      final dir = await getTemporaryDirectory();
      final safeTitle = _listing.title
          .replaceAll(RegExp(r'[^A-Za-z0-9_\- ]'), '')
          .replaceAll(' ', '_');
      final ext = file.format.toLowerCase();
      final filename = '${safeTitle.isEmpty ? 'model' : safeTitle}.$ext';
      final outFile = File('${dir.path}/$filename');
      await outFile.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      final origin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null;
      await Share.shareXFiles(
        [XFile(outFile.path, name: filename)],
        subject: _listing.title,
        sharePositionOrigin: origin,
      );
      if (!mounted) return;
      AppToast.success(
        context,
        '$filename ${tr(localeNotifier.value, 'market.listing.file_ready')}',
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.error(
        context,
        '${tr(localeNotifier.value, 'market.listing.download_error')}: $e',
      );
    } finally {
      if (mounted) setState(() => _downloadingFileId = null);
    }
  }

  Future<List<int>> _bytesFor(String src) async {
    if (src.startsWith('http://') || src.startsWith('https://')) {
      final res = await http
          .get(Uri.parse(src))
          .timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(src));
      }
      return res.bodyBytes;
    }
    if (src.startsWith('file://')) {
      return await File.fromUri(Uri.parse(src)).readAsBytes();
    }
    throw StateError('Unknown source: $src');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final listing = _listing;
    final locale = Localizations.localeOf(context);
    // Bepul yoki sotib olingan — yuklab olish/3D ochiq. Aks holda — sotib olish CTA.
    final unlocked = listing.isFree || listing.isOwned;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListingGalleryPager(
                images: listing.galleryImages,
                onClose: _close,
                onShare: _share,
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListingMetaPills(
                district: listing.district,
                areaM2: listing.areaM2,
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListingInfoCard(
                priceUzs: listing.priceUzs,
                title: listing.title,
                description: listing.description,
              ),
            ),
            if (unlocked && listing.isOwned && !listing.isFree) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _OwnedBadge(label: _ownedLabel(locale)),
              ),
            ],
            // 3D ko'rish doim ochiq (bepul preview). Formatlar ham doim
            // ko'rinadi (xaridor nima olishini ko'radi), lekin locked bo'lsa
            // bosilganda sotib olish oqimi ochiladi.
            if (_has3DViewable) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _View3DButton(onTap: _open3DViewer),
              ),
            ],
            if (listing.files.isNotEmpty) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ListingFormatsCard(
                  files: listing.files,
                  downloadingFileId: _downloadingFileId,
                  locked: !unlocked,
                  onTap: _downloadFormat,
                ),
              ),
            ],
            // Reviewer (demo) akkaunti uchun "Sotib olish" ko'rsatilmaydi —
            // bepul modellardan foydalanadi (pulli formatlar locked qoladi).
            if (!unlocked && !paymentsHidden) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ListingCtaButton(
                  label: _buyLabel(locale),
                  onTap: _onBuy,
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

String _buyLabel(Locale l) => tr(l, 'market.listing.buy');

String _ownedLabel(Locale l) => tr(l, 'market.listing.owned');

// Guest-gate xabarlari — login drawer (`ensureLoggedIn`) ichida ko'rsatiladi.
String _loginMsgBuy(Locale l) => tr(l, 'market.listing.login_buy');

String _loginMsgDownload(Locale l) => tr(l, 'market.listing.login_download');

String _loginMsgView(Locale l) => tr(l, 'market.listing.login_view');

class _OwnedBadge extends StatelessWidget {
  const _OwnedBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.splashGreen.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.verified_rounded,
            size: 18,
            color: AppColors.splashGreen,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppColors.splashGreen,
            ),
          ),
        ],
      ),
    );
  }
}

class _View3DButton extends StatelessWidget {
  const _View3DButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final bg = AppColors.splashGreen;
    final fg = AppColors.buttonTextBlack;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.view_in_ar_rounded, size: 22, color: fg),
              const SizedBox(width: 10),
              Text(
                tr(locale, 'market.listing.view_3d_model'),
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  height: 1.2,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
