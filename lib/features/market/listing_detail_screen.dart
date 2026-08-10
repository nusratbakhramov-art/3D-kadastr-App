import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import '../../core/i18n/app_translations.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../auth/auth_storage.dart';
import '../auth/widgets/login_required_sheet.dart';
import '../home/user_profile.dart' show paymentsHidden;
import '../settings/settings_state.dart';
import 'api_marketplace_service.dart';
import 'downloads_store.dart';
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

  /// Shu model bo'yicha allaqachon yuklab olingan fayllar (fileId → yozuv).
  Map<int, MarketDownload> _downloads = const {};

  /// Joriy yuklab olishning bajarilgan ulushi (0..1). Server `Content-Length`
  /// bermasa `null` — qator aylanma indikator ko'rsatadi.
  double? _downloadProgress;

  /// Joriy yuklab olish klienti — bekor qilish uchun saqlanadi: `close()`
  /// oqimni uzadi va `saveStream` chala `.part` faylni o'chirib tashlaydi.
  http.Client? _downloadClient;

  /// Uzilish foydalanuvchi tomonidan bo'ldimi — shunda xato toast'i
  /// ko'rsatilmaydi.
  bool _downloadCancelled = false;

  void _cancelDownload() {
    _downloadCancelled = true;
    _downloadClient?.close();
  }

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
    unawaited(_loadDownloads());
  }

  /// Yuklab olingan fayllar indeksini o'qiydi — chip qaysi holatda
  /// ko'rsatilishini shu belgilaydi (yuklab olish / ochish).
  Future<void> _loadDownloads() async {
    final id = widget.listing.backendId;
    if (id == null) return;
    final saved = await MarketDownloads.forModel(id);
    if (mounted) setState(() => _downloads = saved);
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
    // Havola bilan ulashamiz: (1) qabul qiluvchi bosib ochadi — ilova
    // o'rnatilgan bo'lsa Universal Link uni to'g'ridan-to'g'ri shu e'longa olib
    // keladi, (2) matn emas, URL ulashilgani uchun iOS share oynasida Telegram,
    // WhatsApp va boshqa ilovalar chiqadi (fayl ulashishda ular chiqmasdi).
    final locale = localeNotifier.value;
    final link = marketListingLink(l.backendId);
    // Tuman/maydon/narx har doim ham to'ldirilmagan — bo'shini qo'shsak matn
    // " · 0 m²" bo'lib chiqadi, shuning uchun faqat mavjudlarini yig'amiz.
    final meta = [
      if (l.district.trim().isNotEmpty) l.district.trim(),
      if (l.areaM2 > 0) '${l.areaM2} m²',
      if (l.isFree)
        tr(locale, 'market.listing.free')
      else if (l.priceUzs > 0)
        '${marketGroupDigits(l.priceUzs)} ${tr(locale, 'market.pay_sheet.soum')}',
    ].join(' · ');
    Share.share(
      [
        l.title,
        if (meta.isNotEmpty) meta,
        // E'lonning o'z tavsifi — ulashilgan xabar quruq sarlavha va havola
        // bo'lib qolmasin. Uzun tavsif xabarni bosib ketadi, shuning uchun
        // qisqartiriladi.
        ?marketShareDescription(l.description),
        '',
        tr(locale, 'market.share.cta'),
        ?link,
      ].join('\n'),
      subject: l.title,
      sharePositionOrigin: origin,
    );
  }


  /// Chip bosilganda: yuklab olingan bo'lsa — amallar oynasi, aks holda yuklab
  /// olish.
  Future<void> _onFileTap(MarketListingFile file) async {
    // Shu fayl hozir yuklanmoqda — bosilishi bekor qilish demak.
    if (_downloadingFileId == file.id) {
      _cancelDownload();
      return;
    }
    // Boshqa fayl yuklanayotgan bo'lsa — ikkinchisini boshlamaymiz.
    if (_downloadingFileId != null) return;
    if (!_unlocked) {
      await _onBuy();
      return;
    }
    final existing = _downloads[file.id];
    if (existing != null) {
      await _showDownloadedSheet(file, existing);
      return;
    }
    await _downloadFormat(file);
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
    setState(() {
      _downloadingFileId = file.id;
      _downloadProgress = null;
      _downloadCancelled = false;
    });
    try {
      final info = await _api.getDownloadUrl(
        modelId: id,
        fileId: file.id,
        token: token,
      );
      // `Documents/Yuklamalar` ichiga — vaqtinchalik papkaga emas: iOS `tmp`ni
      // istalgan vaqtda tozalaydi, ya'ni 1.5 GB `.max` fayl yo'qolib, keyingi
      // safar qaytadan yuklab olinardi.
      final rec = await _saveStreamed(id, file, info.url);

      if (!mounted) return;
      setState(() => _downloads = {..._downloads, rec.fileId: rec});
      AppToast.success(
        context,
        '${rec.fileName} — ${tr(localeNotifier.value, 'market.download.saved')}',
      );
    } catch (e) {
      if (!mounted) return;
      // Foydalanuvchi o'zi bekor qildi — bu xato emas.
      if (!_downloadCancelled) {
        AppToast.error(
          context,
          '${tr(localeNotifier.value, 'market.listing.download_error')}: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloadingFileId = null;
          _downloadProgress = null;
          _downloadCancelled = false;
        });
      }
    }
  }

  /// Allaqachon yuklab olingan fayl uchun amallar oynasi.
  ///
  /// `.max` / `.dwg` / `.cdr` fayllarini iOS'ning o'zi ocholmaydi (mos ilova
  /// Allaqachon yuklab olingan fayl uchun amallar oynasi.
  ///
  /// Bitta yaxlit drawer: to'liq enlikdagi panel, yuqori burchaklari yumaloq,
  /// ichida sarlavha va qatorlar. Ilgari bu ikkita suzuvchi karta edi — ular
  /// orasidagi tirqishdan sahifa matni ko'rinib turardi va oyna fonsiz, chala
  /// ko'rinardi.
  ///
  /// `.max` / `.dwg` / `.cdr` fayllarini iOS o'zi ocholmaydi (mos ilova yo'q),
  /// shuning uchun "ochish" tizim oynasini chaqiradi — u yerdan foydalanuvchi
  /// Files'ga saqlaydi yoki mos ilovada ochadi.
  Future<void> _showDownloadedSheet(
    MarketListingFile file,
    MarketDownload rec,
  ) async {
    final locale = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panel = isDark ? const Color(0xFF15191B) : Colors.white;
    final fg = isDark ? Colors.white : AppColors.textBlack;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);
    final sep = isDark ? const Color(0xFF262C2F) : const Color(0xFFECEDEF);
    final size = ListingFormatsCard.sizeLabel(rec.sizeBytes);

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (sheetContext) => Container(
        // Drawer'ning O'Z foni — pastki xavfsiz zonagacha to'ldiradi, aks holda
        // home-indicator yo'lagi ostidan scrim ko'rinib qolardi.
        decoration: BoxDecoration(
          color: panel,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2C3133)
                      : const Color(0xFFE3E5E8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                child: Column(
                  children: [
                    Text(
                      rec.fileName,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (size.isNotEmpty) size,
                        tr(locale, 'market.download.location'),
                      ].join(' · '),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontSize: 13,
                        height: 1.35,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
              _ActionRow(
                label: tr(locale, 'market.download.open'),
                asset: 'assets/icons/share.svg',
                fg: fg,
                separator: sep,
                onTap: () => Navigator.of(sheetContext).pop('open'),
              ),
              _ActionRow(
                label: tr(locale, 'market.download.redownload'),
                asset: 'assets/icons/rotate.svg',
                fg: fg,
                separator: sep,
                onTap: () => Navigator.of(sheetContext).pop('redownload'),
              ),
              _ActionRow(
                label: tr(locale, 'market.download.delete'),
                asset: 'assets/icons/trash.svg',
                fg: const Color(0xFFD63A31),
                separator: sep,
                onTap: () => Navigator.of(sheetContext).pop('delete'),
              ),
              // Bekor qilish — shu panel ichida, qolgan qatorlar bilan bir xil
              // ingichka ajratgich orqali. Uni qalin kulrang yo'l bilan
              // ajratish oq panel ichida adashib qolgan chiziqdek ko'rinardi;
              // qalin shrift o'zi yetarli farq beradi.
              InkWell(
                onTap: () => Navigator.of(sheetContext).pop(),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: sep, width: 0.5)),
                  ),
                  height: 56,
                  width: double.infinity,
                  child: Center(
                    child: Text(
                      tr(locale, 'market.download.cancel'),
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: fg,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || action == null) return;

    switch (action) {
      case 'open':
        final f = await MarketDownloads.fileFor(rec);
        if (!mounted) return;
        if (!await f.exists()) {
          // Foydalanuvchi Files'dan o'chirib yuborgan — indeksni tozalab,
          // chipni yana "yuklab olish" holatiga qaytaramiz.
          await MarketDownloads.remove(rec.fileId);
          if (!mounted) return;
          setState(() => _downloads = {..._downloads}..remove(rec.fileId));
          return;
        }
        if (!mounted) return;
        final box = context.findRenderObject() as RenderBox?;
        await Share.shareXFiles(
          [XFile(f.path, name: rec.fileName)],
          subject: _listing.title,
          sharePositionOrigin: box != null
              ? box.localToGlobal(Offset.zero) & box.size
              : null,
        );
      case 'redownload':
        setState(() => _downloads = {..._downloads}..remove(rec.fileId));
        await _downloadFormat(file);
      case 'delete':
        await MarketDownloads.remove(rec.fileId);
        if (!mounted) return;
        setState(() => _downloads = {..._downloads}..remove(rec.fileId));
        AppToast.success(context, tr(locale, 'market.download.deleted'));
    }
  }

  /// Faylni oqim bilan yuklab, `Documents/Yuklamalar`ga yozadi.
  ///
  /// Butun javobni xotiraga yig'maymiz — `.max` fayllar 1.5 GB'gacha bo'ladi,
  /// bunday hajm qurilmada ilovani o'ldiradi.
  Future<MarketDownload> _saveStreamed(
    int modelId,
    MarketListingFile file,
    String src,
  ) async {
    Future<MarketDownload> saveFrom(
      Stream<List<int>> stream, {
      int totalBytes = 0,
    }) {
      var lastPercent = -1;
      return MarketDownloads.saveStream(
        fileId: file.id,
        modelId: modelId,
        title: _listing.title,
        format: file.format,
        stream: stream,
        onProgress: totalBytes <= 0
            ? null
            : (received) {
                // Har chunkda emas, foiz o'zgargandagina qayta chizamiz.
                final percent = (received * 100 ~/ totalBytes).clamp(0, 100);
                if (percent == lastPercent || !mounted) return;
                lastPercent = percent;
                setState(() => _downloadProgress = percent / 100);
              },
      );
    }

    if (src.startsWith('http://') || src.startsWith('https://')) {
      final client = http.Client();
      _downloadClient = client;
      try {
        final res = await client
            .send(http.Request('GET', Uri.parse(src)))
            .timeout(const Duration(seconds: 60));
        if (res.statusCode != 200) {
          throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(src));
        }
        return await saveFrom(
          res.stream,
          totalBytes: res.contentLength ?? file.fileSize,
        );
      } finally {
        client.close();
        _downloadClient = null;
      }
    }
    if (src.startsWith('file://')) {
      return saveFrom(File.fromUri(Uri.parse(src)).openRead());
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
                  downloadProgress: _downloadProgress,
                  downloadedFileIds: _downloads.keys.toSet(),
                  locked: !unlocked,
                  onTap: _onFileTap,
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

/// Ulashish matni uchun tavsifni bir xatboshiga qisqartiradi.
///
/// Xabar quruq sarlavha va havoladan iborat bo'lib qolmasligi uchun e'lon
/// tavsifi ham qo'shiladi, lekin to'liq tavsif xabarni bosib ketadi — 180
/// belgidan uzuni so'z chegarasida kesiladi. Bo'sh tavsifda `null` qaytadi,
/// shunda qatorning o'zi umuman qo'shilmaydi.
String? marketShareDescription(String? raw) {
  final text = (raw ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return null;
  if (text.length <= 180) return text;
  final cut = text.substring(0, 180);
  final lastSpace = cut.lastIndexOf(' ');
  return '${cut.substring(0, lastSpace > 120 ? lastSpace : 180).trimRight()}…';
}

/// 12500000 → "12 500 000" (`ListingInfoCard` bilan bir xil ko'rinish).
String marketGroupDigits(int v) {
  final s = v.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    buf.write(s[i]);
    final remaining = s.length - i - 1;
    if (remaining > 0 && remaining % 3 == 0) buf.write(' ');
  }
  return buf.toString();
}

/// Ulashiladigan (va ilovaga qaytadigan) e'lon havolasi.
///
/// `api.3dkadastr.uz` allaqachon `Runner.entitlements`da associated-domain
/// sifatida ro'yxatdan o'tgan (Payme `pay-return` uchun), shuning uchun bu
/// havola iOS'da ilovani ochadi — qo'shimcha sozlash kerak emas.
String? marketListingLink(int? backendId) =>
    backendId == null ? null : 'https://api.3dkadastr.uz/market/$backendId';

/// iOS action-sheet qatori: chapda yorliq, o'ngda belgi, tepasida ingichka
/// ajratgich.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.label,
    required this.asset,
    required this.fg,
    required this.separator,
    required this.onTap,
  });

  final String label;
  final String asset;
  final Color fg;
  final Color separator;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: separator, width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        height: 56,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                  color: fg,
                ),
              ),
            ),
            SvgPicture.asset(
              asset,
              width: 20,
              height: 20,
              colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
            ),
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
