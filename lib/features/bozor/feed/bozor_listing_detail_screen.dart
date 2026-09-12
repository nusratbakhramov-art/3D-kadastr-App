/// "Bozor AI" e'lonining detal ekrani.
///
/// Ekran `listingId` ni oladi, e'lonni O'ZI yuklaydi va shu bilan uchta
/// chaqiruvchiga birdan yaraydi: lenta kartasi, "Mening e'lonlarim" qatori va
/// e'lon yuborilgandan keyingi "E'lonimni ko'rish" tugmasi — hech biri e'lonni
/// oldindan to'liq yuklab kelishi shart emas (kartada `params`, kontakt va
/// `rejection_reason` yo'q).
///
/// ⚠️ ENG NOZIK JOY — PARAMETRLAR. `params` da YORLIQ emas, KOD saqlanadi
/// (`renovation: "euro"`, `parking: "garage"`). Yorliqlar `/listings/options`
/// dan tilga qarab keladi ([ApiParamOptions]). Ro'yxat kelmasa (offline, 500)
/// kod bo'yicha qatorlar UMUMAN chizilmaydi: "Ta'mir: euro" degan xom kod
/// ekranga chiqib qolgandan ko'ra qator yo'qligi arzon. Sonli va matnli
/// parametrlar (maydon, qavat, GSK nomi) bunda ham ko'rinishda davom etadi,
/// ya'ni ekran bo'shab qolmaydi.
///
/// ⚠️ Yorliq so'rovi ekranni GAROVGA OLMAYDI: e'lonning o'zi kelgach ekran
/// darhol chiziladi, `/listings/options` esa FONDA yuklanadi va kelgach
/// select qatorlari qo'shiladi. Ro'yxat osilib qolsa (20s timeout) ham
/// foydalanuvchi e'lonni ko'rib turadi.
///
/// Anonim foydalanuvchi ham ochadi: `GET /listings/{id}` tokensiz ishlaydi
/// (`AuthHttpClient` token bo'lmasa uni qo'shmaydi). Tasdiqlanmagan e'lonni
/// backend faqat EGASIGA beradi (`get_for_viewer`), begonaga 404 — shuning
/// uchun bu ekranda `pending`/`rejected` ko'rinsa, uni ko'rayotgan odam
/// e'lonning egasi.
library;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api_config.dart';
import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/color_tokens.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../../market/widgets/listing_gallery_pager.dart';
import '../../../core/haptics.dart';
import '../../panorama/screens/pano_tour_screen.dart';
import '../../market/widgets/listing_info_card.dart';
import '../../market/widgets/listing_meta_pills.dart';
import '../../../widgets/app_toast.dart';
import '../bozor_routes.dart';
import '../data/bozor_api.dart';
import '../data/bozor_draft_codec.dart';
import '../data/param_options.dart';
import '../models/bozor_draft.dart';
import '../models/bozor_listing.dart';
import '../models/param_schema.dart';
import '../widgets/listing_location_map.dart';
import '../screens/bozor_type_step_screen.dart';

class BozorListingDetailScreen extends StatefulWidget {
  const BozorListingDetailScreen({
    super.key,
    required this.listingId,
    this.isOwner = false,
    this.api,
  });

  /// `GET /listings/{id}` uchun e'lon id'si.
  final int listingId;

  /// Ko'rayotgan odam e'lonning EGASIMI.
  ///
  /// Server buni aytmaydi: `ListingOut` da egasining id'si YO'Q (ataylab —
  /// ommaviy lentada begona odamning id'si oshkor bo'lmasin). Shu sababli
  /// javobgarlik chaqiruvchida: "Mening e'lonlarim" tabi `true` beradi,
  /// ommaviy lenta `false`.
  ///
  /// Sukut `false` — xavfsiz taraf: begonaga tahrirlash tugmasi
  /// ko'rsatilgandan ko'ra egasiga ko'rsatilmasligi arzon (server baribir
  /// 404 berardi, lekin foydalanuvchi chalg'iydi).
  final bool isOwner;

  /// Faqat testlar uchun — tarmoq klientini almashtirish.
  final BozorApi? api;

  @override
  State<BozorListingDetailScreen> createState() =>
      _BozorListingDetailScreenState();
}

class _BozorListingDetailScreenState extends State<BozorListingDetailScreen> {
  late final BozorApi _api = widget.api ?? BozorApi();

  /// Yorliq ro'yxatlari. Til `didChangeDependencies` da ma'lum bo'ladi,
  /// shuning uchun bu yerda `late` emas.
  ParamOptionsRepository? _options;

  /// `_options` QAYSI tilda yasalgan. Til almashsa ro'yxatlar shu tilda
  /// qayta olinadi — yorliqlar tilga bog'liq.
  String? _localeCode;

  /// Fon yuklashning navbat raqami: til almashganda eskisining javobi
  /// yangisini bosib ketmasin.
  int _labelsRun = 0;

  bool _requested = false;
  bool _loading = true;
  BozorListing? _listing;
  List<_ParamRow> _rows = const [];

  /// Xato matnining tarjima KALITI (`null` — xato yo'q).
  String? _errorKey;

  /// 404 — "yo'q" va "hali tasdiqlanmagan" ataylab ajratilmaydi (backend
  /// begonaga e'lonning mavjudligini oshkor qilmaydi). Bunda "Qayta urinish"
  /// ko'rsatilmaydi: qayta so'rov ham xuddi shu 404 ni qaytaradi.
  bool _notFound = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final code = Localizations.localeOf(context).languageCode;
    if (!_requested) {
      _requested = true;
      _localeCode = code;
      _load();
      return;
    }
    if (code == _localeCode) return;
    // Til almashdi. Ekranning qolgan matni `tr(locale, ...)` bilan o'zi
    // yangilanadi, parametr yorliqlari esa TARMOQDAN keladi — ro'yxatni
    // yangi tilda qayta olmasak ekran ARALASH TILLI bo'lib qoladi.
    _localeCode = code;
    _options = null;
    final listing = _listing;
    if (listing != null) _showParamRows(listing);
  }

  @override
  void dispose() {
    // Klient testdan berilgan bo'lsa uni yopish testning ishi.
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorKey = null;
      _notFound = false;
    });
    try {
      final listing = await _api.listing(widget.listingId);
      if (!mounted) return;
      // Tilni so'rovdan KEYIN o'qiymiz. So'rov davomida til almashsa
      // `didChangeDependencies` `_localeCode` ni yangilaydi, lekin `_listing`
      // hali `null` bo'lgani uchun qatorlarni qayta hisoblay olmaydi — bu
      // yerda eski (so'rov boshida qo'lga olingan) tilni ishlatsak yorliqlar
      // ESKI tilda qotib qolardi.
      final locale = Localizations.localeOf(context);
      setState(() {
        _listing = listing;
        // Yorliqsiz qatorlar DARHOL chiziladi: son/matn/toggle uchun tarmoq
        // kerak emas. Select qatorlari yorliq kelgach qo'shiladi — ekran
        // `/listings/options` ni KUTMAYDI.
        _rows = _paramRows(listing, locale, null);
        _loading = false;
      });
      _loadParamLabels(listing, locale);
    } on BozorApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _notFound = e.statusCode == 404;
        _errorKey = _notFound
            ? 'bozor.detail.not_found'
            : 'bozor.detail.load_failed';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorKey = 'bozor.detail.load_failed';
        _loading = false;
      });
    }
  }

  // ── Egasining harakatlari ─────────────────────────────────────────────────
  /// Tahrirlash/arxivlash tugmalari.
  ///
  /// Ro'yxat HOLATGA bog'liq va serverdagi o'tishlar jadvaliga mos
  /// (`bozor_listing.LISTING_TRANSITIONS`): server tahrirlashga
  /// `pending`/`rejected` da ruxsat beradi (boshqasini 400 bilan rad
  /// etadi), arxivlash esa `archived` dan tashqari hamma holatda — u
  /// OXIRGI holat, undan qaytish yo'q.
  ///
  /// ⚠️ MODERATSIYADAGI (`pending`) E'LON TAHRIRLANMAYDI — 2026-09-12 da
  /// ATAYLAB yopildi. Sabab: `draftFromListing` e'londagi MAVJUD fayllarni
  /// (foto, planirovka, 360) faqat `existingMedia` ga soladi, sehrgar esa
  /// uni umuman o'qimaydi — ya'ni tahrirlashda uchala qator ham BO'SH
  /// chiqadi. Fayllar yo'qolmaydi (yuborishda `keep` bilan qaytariladi),
  /// lekin foydalanuvchi ularni ko'rmaydi va eng muhimi: YANGI xonani
  /// eskisiga TUR bilan bog'lay olmaydi — tur muharriri ham faqat
  /// `description.panoramas` ni ko'radi.
  ///
  /// `rejected` ATAYLAB qoldirildi: rad etilgan e'lonni tuzatib bo'lmasa u
  /// abadiy o'lik qolardi. U ham shu nosoz yo'ldan ketadi, lekin matn va
  /// narxni tuzatish ishlaydi.
  ///
  /// QAYTARISH: `draftFromListing` da `role == 'panorama'` media'ni
  /// `existingMedia` ga EMAS, `description.panoramas` +
  /// `panoramaUrls` + `uploadedMedia` ga soling (va `existingMedia` dan
  /// chiqaring — aks holda yuborishda ikki marta ketadi). Shundan keyin
  /// pastdagi `pending` shartini qaytaring.
  List<Widget> _ownerActions(BozorListing listing) {
    final l = Localizations.localeOf(context);
    final canEdit =
        // TODO(bozor): media ko'rinadigan bo'lgach qaytarilsin —
        // yuqoridagi izohga qarang.
        // listing.status == ListingStatus.pending ||
        listing.status == ListingStatus.rejected;
    final canArchive = listing.status != ListingStatus.archived;
    return [
      if (canEdit)
        Expanded(
          child: _OutlinedAction(
            label: tr(l, 'bozor.detail.edit'),
            icon: Icons.edit_outlined,
            onTap: () => _edit(listing),
          ),
        ),
      if (canEdit && canArchive) const SizedBox(width: 10),
      if (canArchive)
        Expanded(
          child: _OutlinedAction(
            label: tr(l, 'bozor.detail.archive'),
            icon: Icons.inventory_2_outlined,
            onTap: () => _archive(listing),
          ),
        ),
    ];
  }

  /// Sehrgarni TO'LDIRILGAN qoralama bilan ochadi. Oxirida yuborish
  /// `POST` emas `PATCH` ga ketadi (`BozorDraft.editingListingId`).
  Future<void> _edit(BozorListing listing) async {
    final draft = draftFromListing(listing);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: bozorRoute('type'),
        builder: (_) => BozorTypeStepScreen(draft: draft),
      ),
    );
    // Tahrirlangan bo'lsa holat o'zgargan (`rejected` → `pending`).
    if (mounted) _load();
  }

  /// Arxivlash — QAYTARIB BO'LMAYDI (`archived` oxirgi holat), shuning uchun
  /// tasdiq so'raladi.
  Future<void> _archive(BozorListing listing) async {
    final l = Localizations.localeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ColorTokens.sheetBg(ctx),
        title: Text(tr(l, 'bozor.detail.archive_title')),
        content: Text(tr(l, 'bozor.detail.archive_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr(l, 'common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              tr(l, 'bozor.detail.archive'),
              style: const TextStyle(color: Color(0xFFE0492A)),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _api.archiveListing(listing.id);
      if (mounted) _load();
    } on BozorApiException catch (e) {
      if (mounted) AppToast.error(context, e.message);
    } catch (_) {
      if (mounted) {
        AppToast.error(context, tr(l, 'bozor.detail.archive_failed'));
      }
    }
  }

  // ── Parametrlar ───────────────────────────────────────────────────────────
  /// Yorliqsiz qatorlarni darhol chizadi va ro'yxatlarni fonda yuklaydi.
  /// Til almashganda ham shu yo'l bosib o'tiladi.
  void _showParamRows(BozorListing listing) {
    final locale = Localizations.localeOf(context);
    setState(() => _rows = _paramRows(listing, locale, null));
    _loadParamLabels(listing, locale);
  }

  /// `params` (kodlar) → ekrandagi yorliqli qatorlar. SINXRON: tarmoq
  /// kerak bo'lgan yagona narsa — [labels], u tashqaridan beriladi.
  ///
  /// [labels]: `optionsKey` → (kod → yorliq). `null` bo'lsa ro'yxatlar hali
  /// kelmagan (yoki umuman kelmadi) — select qatorlari CHIZILMAYDI, xom kod
  /// ekranga chiqmaydi.
  ///
  /// Sxemadan TASHQARIDAGI kalitlar tashlab yuboriladi: server yangi maydon
  /// qo'shsa uning qiymati kodmi yoki sonmi — bilmaymiz, ya'ni xom kod chiqib
  /// qolish xavfi bor. Yangi maydon `param_schema.dart` ga qo'shilganda o'zi
  /// paydo bo'ladi.
  List<_ParamRow> _paramRows(
    BozorListing listing,
    Locale locale,
    Map<String, Map<String, String>>? labels,
  ) {
    final type = _propertyTypeOf(listing.propertyType);
    if (type == null || listing.params.isEmpty) return const [];
    final rows = <_ParamRow>[];
    for (final f in visibleParams(type.paramFields, listing.params)) {
      final raw = listing.params[f.key];
      if (raw == null) continue;
      final value = switch (f.control) {
        ParamControl.toggle => _toggleValue(locale, raw),
        ParamControl.number || ParamControl.integer => _numberValue(
          locale,
          f,
          raw,
        ),
        ParamControl.text => raw.toString().trim(),
        ParamControl.select ||
        ParamControl.multiSelect => _labelsFor(labels, f, raw),
      };
      if (value == null || value.isEmpty) continue;
      rows.add(_ParamRow(tr(locale, f.labelKey), value));
    }
    return rows;
  }

  /// Yorliq ro'yxatlarini FONDA yuklaydi va qatorlarni qayta chizadi.
  ///
  /// Ikkita muhim xususiyat:
  /// 1. Ekran bu so'rovni kutmaydi — `/listings/options` osilib qolsa ham
  ///    e'lon ko'rinib turadi.
  /// 2. So'rov BITTA: [ApiParamOptions] barcha ro'yxatni bir marta oladi va
  ///    keshlaydi, birinchi XATODA esa ilmoq uziladi. Ilgari `_labelsFor`
  ///    xatoni O'ZI yutib yuborardi, `ApiParamOptions` esa xatoni
  ///    keshlamaydi (`_inflight = null` + rethrow) — natijada qiymati bor
  ///    HAR BIR select maydoniga alohida so'rov ketardi (har biri 20s
  ///    timeout bilan).
  Future<void> _loadParamLabels(BozorListing listing, Locale locale) async {
    final type = _propertyTypeOf(listing.propertyType);
    if (type == null || listing.params.isEmpty) return;
    final keys = <String>{
      for (final f in visibleParams(type.paramFields, listing.params))
        if (listing.params[f.key] != null &&
            (f.control == ParamControl.select ||
                f.control == ParamControl.multiSelect))
          ?f.optionsKey,
    };
    if (keys.isEmpty) return;
    final repo =
        _options ??= ApiParamOptions(locale: locale.languageCode, api: _api);
    final run = ++_labelsRun;
    final labels = <String, Map<String, String>>{};
    try {
      for (final k in keys) {
        final opts = await repo.options(k);
        labels[k] = {for (final o in opts) o.code: o.label};
      }
    } catch (_) {
      // Offline/500 — xom kod ko'rsatmaymiz (fayl boshidagi izohga qarang).
      return;
    }
    // Til almashib, yangi yuklash boshlangan bo'lsa bu javob ESKI.
    if (!mounted || run != _labelsRun) return;
    setState(() => _rows = _paramRows(listing, locale, labels));
  }

  /// Kod(lar)ni shu tildagi yorliqqa aylantiradi.
  ///
  /// `null` qaytsa qator umuman chizilmaydi: ro'yxat kelmagan, kalit yo'q,
  /// yoki kodlardan BIRI ro'yxatda topilmagan. Qismiy ro'yxat ataylab
  /// chizilmaydi — `security: ['guard','cctv']` da faqat "Qorovul" ni
  /// ko'rsatish ro'yxat TO'LIQ degan yolg'on taassurot beradi, ya'ni xom
  /// koddan ham yomon: xato ko'zga tashlanmaydi.
  String? _labelsFor(
    Map<String, Map<String, String>>? labels,
    ParamField f,
    Object raw,
  ) {
    final key = f.optionsKey;
    if (key == null) return null;
    final byCode = labels?[key];
    if (byCode == null) return null;
    final codes = raw is List
        ? raw.map((e) => e.toString())
        : [raw.toString()];
    final out = <String>[];
    for (final c in codes) {
      final label = byCode[c];
      if (label == null) return null;
      out.add(label);
    }
    return out.isEmpty ? null : out.join(', ');
  }

  /// Toggle qiymati. Backend `params` ni TIPSIZ `dict` sifatida saqlaydi
  /// (`app/schemas/bozor_listing.py` — `params: dict`, validatsiya yo'q),
  /// ya'ni `"gas": "true"` yoki `"gas": 1` bo'lib ham kelishi mumkin.
  /// Tushunarsiz qiymatda `null`: "Yo'q" deb yozib qo'yish jimgina
  /// NOTO'G'RI ma'lumot bo'ladi, qator yo'qligi esa shunchaki kamchilik.
  String? _toggleValue(Locale locale, Object raw) {
    final value = switch (raw) {
      final bool b => b,
      final num n when n == 0 || n == 1 => n == 1,
      _ => switch (raw.toString().trim().toLowerCase()) {
        'true' || '1' => true,
        'false' || '0' => false,
        _ => null,
      },
    };
    if (value == null) return null;
    return tr(locale, value ? 'bozor.detail.yes' : 'bozor.detail.no');
  }

  String _numberValue(Locale locale, ParamField f, Object raw) {
    final n = raw is num ? raw : num.tryParse(raw.toString());
    // Son kutilgan joyda son emas — qatorni tashlaymiz (buzuq qiymat
    // ko'rsatgandan ko'ra ko'rsatmaslik yaxshi).
    if (n == null) return '';
    final unit = f.unit;
    final text = formatBozorAmount(n);
    return unit == null ? text : '$text ${tr(locale, 'bozor.unit.$unit')}';
  }

  // ── Amallar ───────────────────────────────────────────────────────────────
  void _close() => Navigator.of(context).maybePop();

  Future<void> _call(String phone) async {
    // Loyihadagi mavjud usul (`home_screen`, `support_sheet`) — `tel:` sxemasi
    // va tashqi ilova rejimi; ochilmasa jimgina o'tamiz.
    final uri = Uri(scheme: 'tel', path: phone.trim());
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Telefoni yo'q qurilma (planshet, simulyator) — xato ko'rsatmaymiz.
    }
  }

  void _share() {
    final listing = _listing;
    if (listing == null) return;
    final locale = Localizations.localeOf(context);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    // ⚠️ HAVOLA QO'SHILMAYDI: "Bozor AI" e'lonining ommaviy veb sahifasi hali
    // YO'Q (`/api/v1/listings/{id}` — JSON API). Ishlamaydigan havola
    // yuborgandan ko'ra matnning o'zi to'g'ri.
    final meta = [
      if (listing.regionLine.isNotEmpty) listing.regionLine,
      ?listing.roomsAreaLine(locale),
      listing.formattedPrice(locale),
    ].join(' · ');
    Share.share(
      [
        listing.title,
        meta,
        if (listing.address.trim().isNotEmpty) listing.address.trim(),
        '',
        tr(locale, 'bozor.detail.share_cta'),
      ].join('\n'),
      subject: listing.title,
      sharePositionOrigin: origin,
    );
  }

  // ── Ko'rinish ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorTokens.scaffoldBg(context),
      body: SafeArea(bottom: false, child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    final listing = _listing;
    if (listing == null) {
      return _ErrorView(
        messageKey: _errorKey ?? 'bozor.detail.load_failed',
        onRetry: _notFound ? null : _load,
        onClose: _close,
      );
    }
    return _content(listing);
  }

  /// E'londagi 360° fayllar, e'londagi TARTIBDA.
  ///
  /// Tartib muhim: tur birinchisidan boshlanadi va havolalar shu
  /// ro'yxatdagi kalitlar bo'yicha topiladi.
  List<BozorListingMedia> _panoramas(BozorListing listing) => <BozorListingMedia>[
    for (final BozorListingMedia m in listing.media)
      if (m.role == 'panorama' && m.storageKey.isNotEmpty) m,
  ];

  void _openTour(BozorListing listing) {
    final List<BozorListingMedia> panos = _panoramas(listing);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PanoTourScreen(
          panoramas: <TourPano>[
            for (final BozorListingMedia m in panos)
              TourPano(
                // ⚠️ `ref` — `storage_key`. Havolalar serverda aynan shu
                // bilan saqlanadi; `url` ishlatilsa hech bir havola
                // topilmasdi va tur bo'sh ko'rinardi.
                ref: m.storageKey,
                url: ApiConfig.resolveUrl(m.url),
                thumbUrl: m.thumbUrl == null
                    ? null
                    : ApiConfig.resolveUrl(m.thumbUrl!),
              ),
          ],
          links: listing.tour,
        ),
      ),
    );
  }

  Widget _content(BozorListing listing) {
    final locale = Localizations.localeOf(context);
    final type = _propertyTypeOf(listing.propertyType);
    final pills = <Widget>[
      if (listing.regionLine.isNotEmpty)
        ListingMetaPill(
          iconAsset: 'assets/icons/map.svg',
          text: listing.regionLine,
        ),
      if (listing.areaSqm != null)
        ListingMetaPill(
          iconAsset: 'assets/icons/ruler-triangle.svg',
          text:
              '${formatBozorAmount(listing.areaSqm!)} '
              '${tr(locale, 'bozor.unit.m²')}',
        ),
      if (listing.rooms != null && listing.rooms! > 0)
        ListingMetaPill(
          text: '${listing.rooms} ${tr(locale, 'bozor.listing.rooms_short')}',
        ),
      // `propertyTypeLabel` NOTANISH kodni o'zini qaytaradi (model ataylab
      // shunday — greplansin), nishonda esa `dacha` kabi xom kod ko'rinmasin:
      // tur tanilmasa nishon UMUMAN chizilmaydi. Qolgan nishonlar joyida.
      if (type != null) ListingMetaPill(text: type.label(locale)),
    ];

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ListingGalleryPager(
            // ⚠️ NISBIY havolalar bo'ladi: S3 sozlanmagan muhitda backend
            // `/kadastr-3d-files/listings/media/...` qaytaradi va
            // `Image.network` bunday manzilni ochmaydi. `resolveUrl` absolyut
            // havolaga tegmaydi, ya'ni prod'da hech narsa o'zgarmaydi.
            images: [
              for (final u in listing.galleryUrls) ApiConfig.resolveUrl(u),
            ],
            onClose: _close,
            onShare: _share,
          ),
        ),
        // 360° tur — galereyadan KEYIN va alohida tugma bilan.
        //
        // Galereyaga qo'shib yuborilmadi: panorama tekis ko'rsatilganda
        // cho'zilgan lenta bo'lib chiqadi va xaridor uni sifatsiz rasm
        // deb o'ylaydi. Tugma esa u SFERADA ochilishini oldindan aytadi.
        if (_panoramas(listing).isNotEmpty) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _TourButton(
              count: _panoramas(listing).length,
              onTap: () => _openTour(listing),
            ),
          ),
        ],
        // Egasiga ko'rinadigan holat — begona bu ekranga umuman kirmaydi
        // (`approved` bo'lmagan e'longa 404, `get_for_viewer`). `archived`
        // ham shu ro'yxatda: arxivlangan e'lon tirik e'londan ajralib
        // turishi kerak, aks holda egasi uni lentada bor deb o'ylaydi.
        if (listing.status == ListingStatus.rejected ||
            listing.status == ListingStatus.pending ||
            listing.status == ListingStatus.archived) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _StatusBanner(listing: listing),
          ),
        ],
        // Egasining harakatlari. `isOwner` chaqiruvchidan keladi — server
        // e'lonning egasini aytmaydi.
        if (widget.isOwner && _ownerActions(listing).isNotEmpty) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: _ownerActions(listing)),
          ),
        ],
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, runSpacing: 8, children: pills),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ListingInfoCard(
            // Narx so'mdan boshqa valyutada ham bo'ladi va ijarada davri bor
            // ("4 500 000 so'm/oy") — shuning uchun tayyor satr beriladi.
            priceText: listing.formattedPrice(locale),
            title: listing.title,
            description: listing.description,
          ),
        ),
        if (listing.negotiable) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ListingMetaPill(text: tr(locale, 'bozor.price.negotiable')),
          ),
        ],
        if (_rows.isNotEmpty) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _SectionCard(
              title: tr(locale, 'bozor.params.title'),
              rows: _rows,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _SectionCard(
            title: tr(locale, 'bozor.address.title'),
            rows: _addressRows(listing, locale),
          ),
        ),
        // Xarita manzil kartochkasidan KEYIN: matnli manzil asosiy javob,
        // xarita esa uni tasdiqlaydi. Nuqta ham, chegara ham bo'lmasa
        // vidjet o'zi bo'sh qaytadi.
        if (listing.latitude != null || listing.boundary != null) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ListingLocationMap(
              point: listing.latitude != null && listing.longitude != null
                  ? LatLng(listing.latitude!, listing.longitude!)
                  : null,
              boundary: listing.boundary,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _SectionCard(
            title: tr(locale, 'bozor.contacts.title'),
            rows: _contactRows(listing, locale),
          ),
        ),
        if (listing.contactPhone.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ListingCtaButton(
              label: tr(locale, 'bozor.detail.call'),
              onTap: () => _call(listing.contactPhone),
            ),
          ),
        ],
      ],
    );
  }

  List<_ParamRow> _addressRows(BozorListing listing, Locale locale) {
    String? nonEmpty(String? v) {
      final s = v?.trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    final floor = listing.floor;
    final totalFloors = listing.totalFloors;
    return [
      if (listing.regionLine.isNotEmpty)
        _ParamRow(tr(locale, 'bozor.address.field.region'), listing.regionLine),
      if (nonEmpty(listing.address) != null)
        _ParamRow(
          tr(locale, 'bozor.address.field.address'),
          listing.address.trim(),
        ),
      if (nonEmpty(listing.landmark) != null)
        _ParamRow(
          tr(locale, 'bozor.address.field.landmark'),
          listing.landmark!.trim(),
        ),
      if (nonEmpty(listing.houseNumber) != null)
        _ParamRow(
          tr(locale, 'bozor.address.field.house_number'),
          listing.houseNumber!.trim(),
        ),
      if (nonEmpty(listing.entrance) != null)
        _ParamRow(
          tr(locale, 'bozor.address.field.entrance'),
          listing.entrance!.trim(),
        ),
      if (nonEmpty(listing.apartmentNumber) != null)
        _ParamRow(
          tr(locale, 'bozor.address.field.apartment_number'),
          listing.apartmentNumber!.trim(),
        ),
      if (floor != null)
        _ParamRow(
          tr(locale, 'bozor.address.field.floor'),
          totalFloors != null ? '$floor / $totalFloors' : '$floor',
        )
      else if (totalFloors != null)
        _ParamRow(
          tr(locale, 'bozor.address.field.total_floors'),
          '$totalFloors',
        ),
    ];
  }

  List<_ParamRow> _contactRows(BozorListing listing, Locale locale) {
    // Asosiy raqam `contact_phones` ichida ham takrorlanishi mumkin —
    // ikki marta chizilmasin.
    final extra = [
      for (final p in listing.contactPhones)
        if (p.trim().isNotEmpty && p.trim() != listing.contactPhone.trim())
          p.trim(),
    ];
    return [
      if (listing.contactName.trim().isNotEmpty)
        _ParamRow(
          tr(locale, 'bozor.contacts.name'),
          listing.contactName.trim(),
        ),
      if (listing.contactPhone.trim().isNotEmpty)
        _ParamRow(
          tr(locale, 'bozor.contacts.phone'),
          listing.contactPhone.trim(),
        ),
      for (final p in extra)
        _ParamRow(tr(locale, 'bozor.contacts.phone'), p),
      if ((listing.contactEmail ?? '').trim().isNotEmpty)
        _ParamRow(
          tr(locale, 'bozor.contacts.email'),
          listing.contactEmail!.trim(),
        ),
    ];
  }
}

/// Yorliq + qiymat juftligi (parametr, manzil qatori, kontakt).
@immutable
class _ParamRow {
  const _ParamRow(this.label, this.value);

  final String label;
  final String value;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.rows});

  final String title;
  final List<_ParamRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final fg = ColorTokens.primaryText(context);
    final muted = ColorTokens.secondaryText(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: ColorTokens.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: isDark ? null : Border.all(color: const Color(0xFFE3E5E8)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              height: 1.25,
              color: fg,
            ),
          ),
          const SizedBox(height: 6),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      row.label,
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontWeight: FontWeight.w500,
                        fontSize: 13.5,
                        height: 1.3,
                        color: muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      row.value,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontWeight: FontWeight.w500,
                        fontSize: 13.5,
                        height: 1.3,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Egasi uchun moderatsiya/arxiv holati. `rejected` da sabab HAR DOIM
/// ko'rsatiladi — backend uni bo'sh qoldirmaydi (rad etish sababsiz
/// bo'lmaydi), lekin `null` kelsa ham ekran yiqilmasligi kerak.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.listing});

  final BozorListing listing;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final rejected = listing.status == ListingStatus.rejected;
    final archived = listing.status == ListingStatus.archived;
    final fg = ColorTokens.primaryText(context);
    // Arxiv — na xato, na kutish: neytral kul rang (yashil "hammasi joyida"
    // degan noto'g'ri xabar berardi).
    final accent = rejected
        ? AppColors.declineRed
        : archived
        ? ColorTokens.secondaryText(context)
        : AppColors.brandGreen;
    final reason = listing.rejectionReason?.trim();

    return Container(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                rejected
                    ? Icons.error_outline_rounded
                    : archived
                    ? Icons.inventory_2_outlined
                    : Icons.hourglass_top_rounded,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  rejected
                      ? tr(locale, 'bozor.detail.rejected_title')
                      : archived
                      ? tr(locale, 'listings.status.archived')
                      : tr(locale, 'listings.status.moderation'),
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    height: 1.25,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (!rejected)
            Text(
              tr(
                locale,
                archived
                    ? 'bozor.detail.archived_note'
                    : 'bozor.detail.pending_note',
              ),
              style: TextStyle(
                fontFamily: 'MTSText',
                fontSize: 13,
                height: 1.35,
                color: ColorTokens.secondaryText(context),
              ),
            )
          else ...[
            Text(
              tr(locale, 'bozor.detail.rejection_reason'),
              style: TextStyle(
                fontFamily: 'MTSText',
                fontSize: 12.5,
                height: 1.3,
                color: ColorTokens.secondaryText(context),
              ),
            ),
            const SizedBox(height: 2),
            if (reason != null && reason.isNotEmpty)
              Text(
                reason,
                style: TextStyle(
                  fontFamily: 'MTSText',
                  fontWeight: FontWeight.w500,
                  fontSize: 13.5,
                  height: 1.35,
                  color: fg,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.messageKey,
    required this.onRetry,
    required this.onClose,
  });

  final String messageKey;

  /// `null` — qayta urinishdan foyda yo'q (404).
  final Future<void> Function()? onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final fg = ColorTokens.primaryText(context);
    final retry = onRetry;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 44,
            color: ColorTokens.secondaryText(context),
          ),
          const SizedBox(height: 12),
          Text(
            tr(locale, messageKey),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 17,
              height: 1.3,
              color: fg,
            ),
          ),
          const SizedBox(height: 20),
          if (retry != null)
            ListingCtaButton(
              label: tr(locale, 'common.retry'),
              onTap: () => retry(),
            ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onClose,
            child: Text(
              tr(locale, 'common.close'),
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Server bergan tur kodi → sehrgardagi enum. Sxema (`param_schema.dart`)
/// aynan shu enum bo'yicha tuzilgan, `params` ni yorliqqa aylantirish uchun
/// esa sxema kerak. Notanish kod (server yangi tur qo'shsa) — `null`, ya'ni
/// parametrlar bloki chizilmaydi, qolgan ekran ishlaydi.
PropertyType? _propertyTypeOf(String code) => switch (code) {
  'apartment' => PropertyType.apartment,
  'house' => PropertyType.house,
  'land' => PropertyType.land,
  'commercial' => PropertyType.commercial,
  'garage' => PropertyType.garage,
  'other_non_residential' => PropertyType.otherNonResidential,
  _ => null,
};

// Son formatlash bu yerda TAKRORLANMAYDI: `bozor_listing.dart` dagi
// [formatBozorAmount] ishlatiladi (ilgari shu faylda aynan nusxasi turardi
// va ikkisi vaqt o'tib ajralib ketishi mumkin edi).

/// Egasining ikkilamchi tugmasi — `ListingCtaButton` bilan bir o'lchamda,
/// lekin konturli: "Qo'ng'iroq" asosiy harakat bo'lib qolishi kerak.
class _OutlinedAction extends StatelessWidget {
  const _OutlinedAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final fg = isDark ? Colors.white : AppColors.textBlack;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// «360° tur» tugmasi — galereya ostida.
class _TourButton extends StatelessWidget {
  const _TourButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color fill = isDark ? const Color(0xFF20262A) : const Color(0xFFFCFDFF);
    final Color border = isDark
        ? const Color(0xFF2C3133)
        : const Color(0xFFE3E5E8);
    final BorderRadius radius = BorderRadius.circular(14);

    return Material(
      color: fill,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hapticTap(onTap),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: border),
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.threesixty_rounded,
                size: 24,
                color: AppColors.splashGreen,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tr(Localizations.localeOf(context), 'bozor.pano.tour.open'),
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: isDark ? Colors.white : const Color(0xFF1B2124),
                  ),
                ),
              ),
              Text(
                '$count',
                style: const TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.splashGreen,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
