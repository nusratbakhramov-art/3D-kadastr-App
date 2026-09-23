import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../core/network_error_handler.dart';
import '../../../theme/app_colors.dart';
import '../../auth/auth_storage.dart';
import '../ai_draft_saver.dart';
import '../api_cadastre_service.dart';
import '../data/ngis_parcel_client.dart';
import '../models/ai_baholash_bundle.dart';
import '../models/ai_wizard_steps.dart';
import '../models/ai_scan_result.dart';
import '../../../widgets/sheet_button.dart';
import '../widgets/parcel_map.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';
import '../widgets/wizard_nav_bar.dart';
import 'ai_client_form_screen.dart';
import 'ai_scan_resume_screen.dart';
import 'parcel_picker_screen.dart';

enum _LoadStatus { idle, loading, loaded, error }

class AiCadastreScreen extends StatefulWidget {
  const AiCadastreScreen({
    super.key,
    this.scan,
    this.draftId,
    this.scanJobId,
    this.areaM2,
    this.initial,
    this.onResolved,
    this.resumeBundle,
  });

  /// Resume oqimi: draft'dan to'liq tiklangan bundle. Berilsa, bu ekran uni
  /// eslab qoladi — Orqaga qaytib Davom etish bosilganda keyingi qadamlar
  /// (mijoz, joylashuv, ...) ma'lumotlari saqlanadi, yangi bo'sh bundle
  /// yaratilmaydi.
  final AiBaholashBundle? resumeBundle;

  /// Resume oqimi: draft'dan tiklangan davreestr natijasi. Berilsa, ekran shu
  /// yuklangan holat bilan ochiladi (qayta lookup qilinmaydi) — foydalanuvchi
  /// Orqaga qaytib bu qadamni ko'ra oladi.
  final CadastreLookupResult? initial;

  /// Har safar davreestr natijasi o'zgarganda chaqiriladi (topildi → natija,
  /// tozalandi → null). Oldingi (maydon) qadam buni eslab qoladi, shunda
  /// foydalanuvchi Orqaga qaytib qayta oldinga bosганда kadastr yo'qolmaydi.
  final ValueChanged<CadastreLookupResult?>? onResolved;

  /// AI Baholashning 3D skan qadami natijasi (oldingi qadamdan uzatiladi).
  final AiScanResult? scan;

  /// Skandan keyin yaratilgan DRAFT ariza id (bundle ichiga ko'chiriladi).
  final int? draftId;

  /// Oldingi (maydon) qadamda kiritilган obyekt maydoni (m²) — bundle'ga
  /// uzatiladi; davreestr skip qilinsa ham baholash maydonini biladi.
  final double? areaM2;

  /// Resume oqimi: skanlangan 3D model bor draft id. Bo'lsa, "3D modelni
  /// ko'rish" tugmasi chiqadi (model backend'dan yuklanib QuickLook'da ochiladi).
  final int? scanJobId;

  @override
  State<AiCadastreScreen> createState() => _AiCadastreScreenState();
}

class _AiCadastreScreenState extends State<AiCadastreScreen> {
  static const _fullMaskLength = 19;
  // Base NN:NN:NN:NN:NN:NNNN, optionally followed by sub-parcel / building /
  // unit blocks, e.g. 10:09:01:01:02:5942:0001:039.
  static final _cadastreRe = RegExp(
    r'^\d{2}:\d{2}:\d{2}:\d{2}:\d{2}:\d{4}(:\d{1,4})*$',
  );
  final TextEditingController _cadastreController = TextEditingController();
  _LoadStatus _status = _LoadStatus.idle;
  CadastreLookupResult? _info;
  String? _errorMsg;
  int _lookupRequestId = 0;

  /// Kadastr number of the lookup currently in flight, if any. Guards the
  /// manual "Ma'lumot noto'g'rimi? Yangilash" / "Qayta urinish" buttons: repeat
  /// taps on the same number are dropped instead of firing another
  /// davreest.uz scrape, which can get the user rate-limited or blocked.
  String? _inFlightNumber;
  List<String> _recent = const [];

  /// Shu RAQAM uchun nechta reyestr urinishi natijasiz tugadi.
  ///
  /// ⚠️ NIMA SANALADI. Faqat haqiqatan yuborilgan va natijasiz qaytgan
  /// so'rov: format xatosi (so'rov umuman ketmagan) ham, foydalanuvchi
  /// ekrandan chiqib ketgani ham sanalmaydi. Tarmoq uzilishi SANALADI —
  /// foydalanuvchi uchun natija bir xil (ma'lumot yo'q), lekin xabar
  /// boshqacha bo'lib qoladi ([_performLookup] dagi uch tarmoq).
  int _failedAttempts = 0;

  /// Sanoq qaysi raqamga tegishli — raqam o'zgarsa nolga tushadi.
  String? _failedNumber;

  /// Zaxira varag'i hozir ochiqmi. Ikki marta bosish ikkita varaq
  /// ochmasligi uchun (`bozor_routes.dart` dagi bilan bir xil qulf).
  bool _fallbackSheetOpen = false;

  /// Foydalanuvchi «hujjat bilan davom etish» ni tanladimi.
  bool _documentMode = false;

  /// Xaritadan tanlangan uchastka — ichki xaritada ajratib ko'rsatiladi va
  /// tanlagich qayta ochilganda o'sha joydan boshlanadi.
  NgisParcel? _parcel;

  /// The bundle this screen created, kept so that returning here (Back from a
  /// later step) and pressing Davom etish again REUSES it instead of building a
  /// fresh one — which would wipe every downstream edit (client, joylashuv,
  /// maqsad, intake). Rebuilt only when the cadastre number itself changes.
  AiBaholashBundle? _bundle;

  /// Skan YO'Q yo'lda draft aynan shu ekranda tug'iladi (video qadami oqimdan
  /// olib tashlangach, undan oldin draft yaratadigan qadam qolmadi). Future
  /// eslab qolinadi: bir wizard yurishi uchun BITTA draft, va "Davom etish"
  /// bosilganda u odatda allaqachon tayyor bo'ladi.
  Future<int?>? _draftFuture;

  @override
  void initState() {
    super.initState();
    // Resume: keep the fully-restored bundle so Back → Davom etish preserves
    // the later steps instead of rebuilding an empty bundle.
    _bundle = widget.resumeBundle;
    // Resume: show the saved davreestr result as already loaded, without a
    // re-lookup. Set the loaded state BEFORE wiring the text listener so filling
    // the field doesn't kick off a fresh lookup.
    if (widget.initial != null) {
      _status = _LoadStatus.loaded;
      _info = widget.initial;
      final n = widget.initial!.cadastreNumber;
      _cadastreController.value = TextEditingValue(
        text: n,
        selection: TextSelection.collapsed(offset: n.length),
      );
    }
    _cadastreController.addListener(_onCadastreChanged);
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null) return;
    final list = await CadastreApiService().recent(token: token);
    if (!mounted) return;
    setState(() => _recent = list);
  }

  /// Xaritadan uy tanlash. Qaytgan kadastr raqami maydonga yoziladi va
  /// oddiy qidiruv oqimi ishga tushadi — manzil va maydon avvalgidek
  /// davreestr'dan keladi (geoportalning ochiq qatlamida ular yo'q).
  Future<void> _pickFromMap() async {
    HapticFeedback.lightImpact();
    final parcel = await Navigator.of(context).push<NgisParcel>(
      MaterialPageRoute<NgisParcel>(
        settings: const RouteSettings(name: 'ai/parcel-map'),
        builder: (_) => ParcelPickerScreen(
          initialCenter: _parcel?.center,
          initialSelection: _parcel,
        ),
      ),
    );
    if (parcel == null || !mounted) return;
    setState(() => _parcel = parcel);
    _applyNumber(parcel.cadastreNumber);
  }

  /// Raqamni maydonga qo'yadi va qidiruvni MAJBURAN qaytadan boshlaydi.
  ///
  /// Holatni oldin `idle` ga qaytaramiz, aks holda avvalgi uyning manzili va
  /// maydoni yangi raqam ostida turib qolardi.
  ///
  /// Qidiruv bu yerda ATAYLAB o'zi boshlanadi — maydonni qo'lda terishdan
  /// farqli o'laroq, xaritadan uy tanlash yoki oxirgi raqamni bosish allaqachon
  /// ONGLI tanlov; odamni yana tugma bosishga majburlash ortiqcha.
  void _applyNumber(String number) {
    setState(() {
      _status = _LoadStatus.idle;
      _info = null;
      _errorMsg = null;
    });
    widget.onResolved?.call(null);
    _cadastreController.value = TextEditingValue(
      text: number,
      selection: TextSelection.collapsed(offset: number.length),
    );
    if (_cadastreRe.hasMatch(number)) unawaited(_runLookup());
  }

  /// Oxirgi qidirilgan raqamni bosish — tayyor javobni qayta olish, shuning
  /// uchun qidiruv shu yerda boshlanadi ([_applyNumber] ga qarang).
  void _useRecent(String number) => _applyNumber(number);

  @override
  void dispose() {
    _cadastreController.removeListener(_onCadastreChanged);
    _cadastreController.dispose();
    super.dispose();
  }

  void _onCadastreChanged() {
    final text = _cadastreController.text;
    // Qo'lda boshqa raqam yozilsa, xaritadagi yashil ajratma endi shu raqamga
    // tegishli emas — uni olib tashlaymiz, aks holda xarita bir uyni, maydon
    // esa boshqasini ko'rsatib turardi.
    if (_parcel != null && _parcel!.cadastreNumber != text) {
      _parcel = null;
    }
    // Boshqa raqam — boshqa hikoya: muvaffaqiyatsiz urinishlar sanog'i
    // nolga tushadi, aks holda birinchi raqamda ikki marta xato qilgan
    // odam ikkinchi raqamni bir marta terishi bilanoq zaxira varag'ini
    // ko'rardi.
    if (_failedNumber != null && _failedNumber != text) {
      _failedAttempts = 0;
      _failedNumber = null;
    }
    // ⚠️ BU YERDA QIDIRUV BOSHLANMAYDI. Ilgari raqam to'lishi bilan 250 ms
    // dan keyin so'rov o'zi ketardi — raqamning dumini tahrir qilgan odam
    // har tuzatishida davreestr'ni qaytadan qirqib olardi. Endi qidiruvni
    // faqat foydalanuvchi boshlaydi: maydon ichidagi tugma yoki klaviatura
    // «done» tugmasi. Tugma raqam to'liq bo'lgach o'zi yonadi va bir-ikki
    // marta "puls" beradi — bosish mumkinligi shundan bilinadi.
    if (!_cadastreRe.hasMatch(text) && _status != _LoadStatus.idle) {
      setState(() {
        _status = _LoadStatus.idle;
        _info = null;
        _errorMsg = null;
      });
      widget.onResolved?.call(null);
    }
  }

  /// Maydon ichidagi qidiruv tugmasi / klaviatura «done» tugmasi.
  void _onSearchPressed() {
    if (!_cadastreRe.hasMatch(_cadastreController.text)) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
    unawaited(_runLookup());
  }

  Future<void> _runLookup() async {
    final number = _cadastreController.text;
    // Already scraping this exact number — ignore the tap (see [_inFlightNumber]).
    if (_inFlightNumber == number) return;
    _inFlightNumber = number;
    final reqId = ++_lookupRequestId;
    // Manual refresh / retry enters here with the status still `loaded` or
    // `error`, so flip to `loading` — that swaps the card for the skeleton, hides
    // the button (no double-taps) and disables "Davom etish" until fresh data
    // lands.
    setState(() {
      _status = _LoadStatus.loading;
      _errorMsg = null;
    });
    try {
      await _performLookup(number, reqId);
    } finally {
      if (_inFlightNumber == number) _inFlightNumber = null;
    }
  }

  Future<void> _performLookup(String number, int reqId) async {
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null) {
      if (!mounted || reqId != _lookupRequestId) return;
      setState(() {
        _status = _LoadStatus.error;
        _errorMsg = _CadastreStrings.signInFirst(
          Localizations.localeOf(context),
        );
      });
      return;
    }
    try {
      // AI Baholash never reads the shared davreestr cache — the area/value here
      // become part of a legal valuation document, so we always scrape fresh.
      final result = await CadastreApiService().lookup(
        cadastreNumber: number,
        token: token,
        forceRefresh: true,
      );
      if (!mounted || reqId != _lookupRequestId) return;
      // davreest.uz returns an all-null result for a non-existent number
      // instead of an error — treat that as "not found" so the user can't
      // continue with empty property data.
      final hasData =
          (result.address?.trim().isNotEmpty ?? false) ||
          result.totalArea != null ||
          result.landArea != null ||
          result.livingArea != null ||
          result.cadastreValue != null ||
          (result.objectTypeHint?.trim().isNotEmpty ?? false);
      if (!hasData) {
        // 2-holat: so'rov o'tdi, javob keldi, lekin reyestrda foydali
        // ma'lumot yo'q. `hasUsableData` bilan bir xil mezon —
        // `davreestr_client.dart` dagi izohga qarang; bitta maydonga
        // (masalan kadastr qiymatiga) qarab qaror qilinmaydi.
        setState(() {
          _status = _LoadStatus.error;
          _info = null;
          _errorMsg = _CadastreStrings.notFoundRetry(
            Localizations.localeOf(context),
          );
        });
        await _registerFailure(number);
        return;
      }
      // Muvaffaqiyat — sanoq tozalanadi.
      _failedAttempts = 0;
      _failedNumber = null;
      setState(() {
        _info = result;
        _status = _LoadStatus.loaded;
        _errorMsg = null;
      });
      // Draft ERTA boshlanadi — foydalanuvchi natijani o'qib turganda. Ataylab
      // aynan shu yerda: kadastr topilgan payt oqimning birinchi jiddiy
      // qadami, bo'sh raqam terib chiqib ketgan odam ortida ariza qoldirmaydi.
      unawaited(_ensureDraft());
      // Remember it upstream so back→forward re-prefills instead of clearing.
      widget.onResolved?.call(result);
    } on CadastreLookupException catch (e) {
      // 1-holat: reyestrning o'zi rad etdi (raqam topilmadi, limit, captcha).
      // Xabar SERVERNIKI — uni "topilmadi" bilan almashtirmaymiz.
      if (!mounted || reqId != _lookupRequestId) return;
      setState(() {
        _status = _LoadStatus.error;
        _errorMsg = e.message;
      });
      await _registerFailure(number);
    } catch (e) {
      if (!mounted || reqId != _lookupRequestId) return;
      setState(() {
        _status = _LoadStatus.error;
        _errorMsg = _CadastreStrings.networkError(
          Localizations.localeOf(context),
          '$e',
        );
      });
      // Release the in-flight guard before awaiting the error sheet — its
      // "retry" calls back into _runLookup, which would otherwise be dropped as
      // a duplicate of this (already finished) request.
      _inFlightNumber = null;
      // 3-holat: tarmoq/server uzilishi. Foydalanuvchiga «topilmadi»
      // DEYILMAYDI — uning raqami to'g'ri bo'lishi mumkin. Lekin urinish
      // baribir natijasiz, shuning uchun sanoqqa kiradi: ikki marta
      // uzilgandan keyin ham zaxira yo'lini ko'rsatish kerak.
      await NetworkErrorHandler.maybeShow(context, e, onRetry: _runLookup);
      await _registerFailure(number);
    }
  }

  /// Natijasiz urinishni qayd qiladi va ikkinchisidan keyin zaxira varag'ini
  /// ochadi.
  ///
  /// Ikki marta — ataylab: birinchi xatodan keyin odam raqamni tekshirib
  /// qayta urinadi, uchinchisiga yetguncha esa u allaqachon «ilova ishlamas
  /// ekan» degan xulosaga keladi. Zaxira yo'li BOR ekan, u haqda ikkinchi
  /// xatodayoq aytish kerak.
  Future<void> _registerFailure(String number) async {
    if (!mounted) return;
    _failedNumber = number;
    _failedAttempts++;
    if (_failedAttempts >= 2) await _showFallbackSheet();
  }

  /// «Topa olmadingizmi?» zaxira varag'i.
  ///
  /// Ikki natijasiz urinishdan keyin O'ZI ochiladi, undan oldin esa maydon
  /// yonidagi «Topa olmayapsizmi?» tugmasi bilan qo'lda ham ochiladi —
  /// foydalanuvchi zaxira yo'li borligini bilish uchun ikki marta
  /// muvaffaqiyatsizlikka uchrashi SHART emas.
  ///
  /// Ilovaning qolgan so'rov oynalari kabi pastki drawer
  /// (`login_required_sheet`, `bozor_routes._ExitWizardSheet`), tugmalari
  /// `SheetButton` dan.
  Future<void> _showFallbackSheet() async {
    if (_fallbackSheetOpen || !mounted) return;
    _fallbackSheetOpen = true;
    try {
      final choice = await showModalBottomSheet<_FallbackChoice>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _CadastreFallbackSheet(),
      );
      if (!mounted) return;
      switch (choice) {
        case _FallbackChoice.retry:
          _runLookup();
        case _FallbackChoice.document:
          _continueWithDocument();
        case null:
          break;
      }
    } finally {
      _fallbackSheetOpen = false;
    }
  }

  /// «Hujjat bilan davom etish» — reyestr tekshiruvi HAL BO'LMAGANI
  /// yozib qo'yiladi va oqim davom etadi.
  ///
  /// Holat bundle'da (`AiCadastreResolution.documentRequired`) va qoralama
  /// payload'ida saqlanadi, ya'ni orqaga/oldinga yurishda ham, qoralamadan
  /// tiklashda ham yo'qolmaydi. Joylashuv esa noma'lumligicha qoladi —
  /// shuning uchun qo'lda xarita qadami KO'RSATILADI.
  void _continueWithDocument() {
    final info = _info;
    setState(() {
      _status = _LoadStatus.loaded;
      _errorMsg = null;
      _documentMode = true;
      // Reyestr hech narsa bermagan bo'lsa ham oqim davom etishi uchun
      // minimal yozuv kerak: raqamning o'zi.
      _info = info ??
          CadastreLookupResult(
            cadastreNumber: _cadastreController.text.trim(),
          );
    });
    widget.onResolved?.call(_info);
  }

  /// DRAFT arizani (bir marta) yaratadi. Skan qilingan yo'lda draft allaqachon
  /// bor (`widget.draftId`) — u holda hech narsa qilinmaydi.
  ///
  /// `createAiDraft` login/tarmoq yo'q bo'lsa jim `null` qaytaradi; oqim
  /// to'xtamaydi, shunchaki draft saqlanmaydi (ilgari video qadamida ham
  /// shunday edi).
  Future<int?> _ensureDraft() {
    if (widget.draftId != null) return Future<int?>.value(widget.draftId);
    return _draftFuture ??= createAiDraft(currentStep: 'cadastre');
  }

  Future<void> _goNext(CadastreLookupResult info) async {
    HapticFeedback.lightImpact();
    // Odatda kutish YO'Q: draft lookup muvaffaqiyatli tugaganda boshlangan va
    // shu paytga qadar tayyor. Tarmoq sekin bo'lsagina bu yerda kutiladi.
    final draftId = await _ensureDraft();
    if (!mounted) return;
    // Reuse the bundle we already built (so downstream edits survive Back →
    // Davom etish). Rebuild only when the cadastre number actually changed —
    // a different property should legitimately reset the later steps.
    final existing = _bundle;
    final AiBaholashBundle bundle;
    if (existing != null &&
        existing.kadastr.cadastreNumber == info.cadastreNumber) {
      bundle = existing;
      // Resume bundle'da draft id bor; yangi yaratilgani esa faqat shu yerda
      // ma'lum bo'ladi — aks holda keyingi qadamlar id'siz qolib, saqlash
      // jimgina o'tkazib yuborilardi.
      bundle.draftId ??= draftId;
    } else {
      bundle = AiBaholashBundle(
        kadastr: info,
        scan: widget.scan,
        draftId: draftId,
        // Area now comes straight from the cadastre — the manual area step
        // was removed. Yer uchastkasida maydon `land_area` da keladi, shuning
        // uchun `effectiveArea`. widget.areaM2 is only a resume fallback.
        areaM2: info.effectiveArea ?? widget.areaM2,
      );
      _bundle = bundle;
    }
    // Xaritada tanlangan UCHASTKANING markazi joylashuv qadamiga olib
    // o'tiladi. Busiz o'sha qadam pinni kadastr MANZILI matnini geokodlab
    // qo'yardi va manzil topilmasa Toshkent markazida qolardi — foydalanuvchi
    // obyektni allaqachon xaritada ko'rsatgan bo'lsa ham.
    //
    // Raqam qo'lda o'zgartirilgan bo'lsa (`_parcel` shunda tozalanadi) markaz
    // ham yozilmaydi — eski uyning nuqtasi yangi raqam ostida qolib ketmasin.
    final parcelCenter = _parcel?.cadastreNumber == info.cadastreNumber
        ? _parcel?.center
        : null;
    // Reyestr hal bo'lmagan bo'lsa buni YOZIB qo'yamiz: keyingi qadamlar
    // (hujjat talabi, qo'lda xarita) shu holatga qarab ishlaydi va u
    // qoralamada ham saqlanadi.
    bundle.cadastreResolution = _documentMode
        ? AiCadastreResolution.documentRequired
        : AiCadastreResolution.resolved;
    if (parcelCenter != null) {
      bundle.parcelCenter = AiParcelPoint(
        lat: parcelCenter.latitude,
        lng: parcelCenter.longitude,
        cadastreNumber: info.cadastreNumber,
      );
      // Uchastka markazi obyektning ISHONCHLI nuqtasi — joylashuvni shu
      // yerda YAKUNLAYMIZ va qo'lda xarita qadami oqimdan tushib qoladi
      // (`AiBaholashBundle.needsManualLocation`). Nuqta ham, uning manbai
      // ham yoziladi: keyingi qadamlar koordinataga emas, MANBAGA qarab
      // qaror qiladi.
      bundle.location = AiLocationInfo(
        lat: parcelCenter.latitude,
        lng: parcelCenter.longitude,
        addressText: info.address,
      );
      bundle.locationSource = AiLocationSource.parcel;
    } else {
      // Raqam QO'LDA kiritilgan. Reyestr javobi koordinata bermaydi
      // (`CadastreLookupResult` da lat/lng yo'q), ya'ni obyektning joyi hali
      // noma'lum — qo'lda xarita qadami KERAK bo'ladi. Eski qiymatni
      // tozalaymiz: foydalanuvchi avval uchastka tanlab, keyin boshqa raqam
      // yozgan bo'lsa, eski uyning nuqtasi qolib ketmasin.
      if (bundle.locationSource == AiLocationSource.parcel) {
        bundle.parcelCenter = null;
        bundle.location = null;
        bundle.locationSource = AiLocationSource.none;
      }
    }
    // Fon rejimida saqlash — sekin backend "Davom etish"'ni muzlatmasin.
    saveAiDraftStepInBackground(bundle, 'client');
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'ai/client'),
        builder: (_) => AiClientFormScreen(bundle: bundle),
      ),
    );
  }

  /// Kadastr endi MAJBURIY: davom etish uchun davreestr topilishi VA obyekt
  /// maydoni bo'lishi shart — maydon shu yerdan olinadi (alohida maydon qadami
  /// olib tashlangan).
  ///
  /// Maydon `total_area` YOKI `land_area` dan olinadi
  /// ([CadastreLookupResult.effectiveArea]): yer uchastkasi yozuvida birinchisi
  /// hech qachon bo'lmaydi, shu sababli avval har bir yer uchastkasi
  /// «maydon yo'q» deb bloklanardi.
  bool get _areaReady =>
      _info?.effectiveArea != null && (_info?.effectiveArea ?? 0) > 0;

  /// «Davom etish» bosiladimi.
  ///
  /// HUJJAT REJIMIDA maydon SHART EMAS: reyestr hech narsa bermagani uchun
  /// bu rejim umuman paydo bo'lgan, maydonni talab qilish esa foydalanuvchini
  /// o'sha boshi berk ko'chaga qaytarardi. Maydon keyinroq — kadastr
  /// hujjatidan olinadi.
  bool get _canContinue =>
      _status == _LoadStatus.loaded && (_areaReady || _documentMode);

  Future<void> _continue() async {
    if (!_canContinue || _info == null) return;
    await _goNext(_info!);
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final labelColor = isDark ? Colors.white : AppColors.textBlack;
    final dividerColor = isDark
        ? const Color(0xFF2C3133)
        : const Color(0xFFE3E5E8);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxContent = constraints.maxWidth.clamp(0.0, 640.0);
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContent),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: ServiceAppBar(
                        title: _CadastreStrings.title(l),
                        subtitle: _CadastreStrings.subtitle(l),
                        // Bu tugma butun oqimni yopadi — bitta qadam
                        // orqaga EMAS. Qadamma-qadam qaytish pastda.
                        onBack: () => confirmCloseAiWizard(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      // Bo'laklar soni «Joylashuv» qadami kerak bo'ladimi-yo'qmi
                      // ga bog'liq. Bu qadamda buni uchastka tanlanganidan
                      // bilamiz: tanlangan bo'lsa nuqta bor, ya'ni qo'lda
                      // xarita qadami tushib qoladi va chiziq 6 bo'lak bo'ladi.
                      child: StepProgressBar(
                        count: aiStepsFor(
                          needsManualLocation: _parcel == null,
                        ).length,
                        activeIndex: 0,
                      ),
                    ),
                    if (widget.scanJobId != null) ...[
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _ScanModelBar(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  AiScanResumeScreen(jobId: widget.scanJobId!),
                            ),
                          ),
                        ),
                      ),
                    ],
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          _SectionLabel(
                            _CadastreStrings.mapLabel(l),
                            color: labelColor,
                          ),
                          const SizedBox(height: 10),
                          _MapCard(
                            parcel: _parcel,
                            isDark: isDark,
                            locale: l,
                            onTap: _pickFromMap,
                          ),
                          const SizedBox(height: 20),
                          _SectionLabel(
                            _CadastreStrings.cadastreNumber(l),
                            color: labelColor,
                          ),
                          const SizedBox(height: 10),
                          _CadastreInput(
                            isDark: isDark,
                            controller: _cadastreController,
                            onSearch: _onSearchPressed,
                            isBusy: _status == _LoadStatus.loading,
                          ),
                          if (_status == _LoadStatus.idle &&
                              _recent.isNotEmpty &&
                              _cadastreController.text.length <
                                  _fullMaskLength) ...[
                            const SizedBox(height: 16),
                            _SectionLabel(
                              _CadastreStrings.recentSearches(l),
                              color: labelColor,
                            ),
                            const SizedBox(height: 10),
                            _RecentChips(
                              numbers: _recent,
                              isDark: isDark,
                              onTap: _useRecent,
                            ),
                          ],
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 240),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SizeTransition(
                                    sizeFactor: animation,
                                    axisAlignment: -1,
                                    child: child,
                                  ),
                                ),
                            child: _status == _LoadStatus.idle
                                ? const SizedBox.shrink(key: ValueKey('idle'))
                                : Column(
                                    key: const ValueKey('details'),
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 18),
                                      Container(height: 1, color: dividerColor),
                                      const SizedBox(height: 18),
                                      _SectionLabel(
                                        _CadastreStrings.propertyInfo(l),
                                        color: labelColor,
                                      ),
                                      const SizedBox(height: 10),
                                      if (_status == _LoadStatus.loading)
                                        _PropertyInfoCardSkeleton(
                                          isDark: isDark,
                                        )
                                      else if (_status == _LoadStatus.error) ...[
                                        _LookupErrorCard(
                                          message:
                                              _errorMsg ??
                                              _CadastreStrings.genericError(l),
                                          onRetry: _runLookup,
                                          isDark: isDark,
                                          locale: l,
                                        ),
                                        // «Topa olmayapsizmi?» — zaxira
                                        // yo'lini IKKI marta xato qilmasdan
                                        // ham ochish mumkin. Ataylab past
                                        // ovozli matn-tugma: ekranda
                                        // allaqachon xato kartasi turibdi,
                                        // yana bitta yorqin tugma qo'ysak
                                        // asosiy amal («qayta urinish»)
                                        // ko'rinmay qolardi.
                                        const SizedBox(height: 10),
                                        Center(
                                          child: TextButton.icon(
                                            onPressed: _showFallbackSheet,
                                            icon: const Icon(
                                              Icons.help_outline_rounded,
                                              size: 18,
                                            ),
                                            label: Text(
                                              _CadastreStrings.helpCta(l),
                                            ),
                                            style: TextButton.styleFrom(
                                              foregroundColor:
                                                  AppColors.splashGreen,
                                              textStyle: const TextStyle(
                                                fontFamily: 'MTSCompact',
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ]
                                      else if (_info != null) ...[
                                        // Hujjat rejimida reyestr kartasi
                                        // deyarli bo'sh bo'ladi — nima
                                        // bo'layotganini aytib qo'yamiz,
                                        // aks holda foydalanuvchi «ma'lumot
                                        // chiqmadi» deb o'ylaydi.
                                        if (_documentMode) ...[
                                          _AreaMissingCard(
                                            isDark: isDark,
                                            locale: l,
                                            message:
                                                _CadastreStrings.documentMode(
                                                  l,
                                                ),
                                          ),
                                          const SizedBox(height: 10),
                                        ],
                                        _PropertyInfoCard(
                                          isDark: isDark,
                                          info: _info!,
                                          locale: l,
                                        ),
                                        if (!_areaReady) ...[
                                          const SizedBox(height: 10),
                                          _AreaMissingCard(
                                            isDark: isDark,
                                            locale: l,
                                          ),
                                        ],
                                        const SizedBox(height: 10),
                                        // "Our side didn't catch it" safety net:
                                        // davreestr may have returned the data but
                                        // our parse dropped a field. Let the user
                                        // force a fresh (cache-free) re-lookup.
                                        _RefreshRow(
                                          isDark: isDark,
                                          locale: l,
                                          onTap: _runLookup,
                                        ),
                                      ] else
                                        const SizedBox.shrink(),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: WizardNavBar(
                        onBack: () => Navigator.of(context).maybePop(),
                        onContinue: _continue,
                        continueLabel: _CadastreStrings.continueLabel(l),
                        continueEnabled: _canContinue,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Resume oqimi banneri — "Skanlangan 3D modelni ko'rish". Bosilganda
/// [AiScanResumeScreen] ochiladi (model QuickLook'da).
class _ScanModelBar extends StatelessWidget {
  const _ScanModelBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : AppColors.textBlack;
    final label = tr(l, 'services.ai.common.view_3d_model');
    return Material(
      color: AppColors.splashGreen.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.view_in_ar_rounded,
                  size: 22, color: AppColors.splashGreen),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: fg,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 22, color: fg.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kadastr raqamini xaritadan olish kartochkasi.
///
/// Ichkaridagi xarita ATAYLAB surilmaydi (`interactive: false`): u ro'yxat
/// ichida turibdi va surish imkoniyati ro'yxatning vertikal siljishini
/// o'g'irlab, ekranni "yopishqoq" qilib qo'yardi. Bosilganda esa to'liq
/// ekranli tanlagich ochiladi — u yerda surish ham, masshtablash ham bemalol.
class _MapCard extends StatelessWidget {
  const _MapCard({
    required this.parcel,
    required this.isDark,
    required this.locale,
    required this.onTap,
  });

  final NgisParcel? parcel;
  final bool isDark;
  final Locale locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final p = parcel;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 190,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ParcelMap(
                  // Kalit tanlov o'zgarganda xaritani o'sha uyga qayta
                  // markazlaydi — `initialCenter` faqat qurilishda o'qiladi.
                  key: ValueKey(p?.cadastreNumber ?? 'empty'),
                  initialCenter: p?.center,
                  initialZoom: p == null ? 12 : 18,
                  selected: p,
                  interactive: false,
                  onTap: (_, _) {},
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: _MapCardBadge(parcel: p, isDark: isDark, locale: locale),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapCardBadge extends StatelessWidget {
  const _MapCardBadge({
    required this.parcel,
    required this.isDark,
    required this.locale,
  });

  final NgisParcel? parcel;
  final bool isDark;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final p = parcel;
    final bg = isDark
        ? Colors.black.withValues(alpha: 0.68)
        : Colors.white.withValues(alpha: 0.95);
    final textColor = isDark ? Colors.white : AppColors.textBlack;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.map_outlined, size: 18,
              color: AppColors.splashGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              p == null
                  ? tr(locale, 'services.ai.cadastre.map_cta')
                  : p.cadastreNumber,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            tr(
              locale,
              p == null
                  ? 'services.ai.cadastre.map_open'
                  : 'services.ai.cadastre.map_change',
            ),
            style: const TextStyle(
              fontFamily: 'MTSText',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.splashGreen,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'MTSCompact',
        fontWeight: FontWeight.w700,
        fontSize: 16,
        height: 1.25,
        color: color,
      ),
    );
  }
}

/// Quick-pick chips of the user's recent kadastr numbers. Tapping one fills
/// the field (which then resolves instantly from the backend cache).
class _RecentChips extends StatelessWidget {
  const _RecentChips({
    required this.numbers,
    required this.isDark,
    required this.onTap,
  });

  final List<String> numbers;
  final bool isDark;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final n in numbers)
          GestureDetector(
            onTap: () => onTap(n),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1F2426)
                    : const Color(0xFFF1F3F5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF2C3133)
                      : const Color(0xFFE3E5E8),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 14,
                    color: isDark ? Colors.white70 : const Color(0xFF8A9097),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    n,
                    style: TextStyle(
                      fontFamily: 'MTSText',
                      fontSize: 13,
                      color: isDark ? Colors.white : AppColors.textBlack,
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

class _CadastreInput extends StatelessWidget {
  const _CadastreInput({
    required this.isDark,
    required this.controller,
    required this.onSearch,
    required this.isBusy,
  });

  final bool isDark;
  final TextEditingController controller;

  /// Qidiruvni boshlash — tugma yoki klaviaturaning «done» tugmasi.
  final VoidCallback onSearch;

  /// Qidiruv ketyapti: tugma spinnerga aylanadi va bosilmaydi.
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final fillColor = isDark ? const Color(0xFF1F2426) : Colors.white;
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : const Color(0xFFB4B9BF);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final borderColor = isDark
        ? const Color(0xFF2C3133)
        : const Color(0xFFE3E5E8);

    return TextField(
      controller: controller,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      // `phone` (not `number`) — Android's number keyboard/clipboard layer
      // silently strips non-digit characters from pasted text, so a clipboard
      // value like "11:14:04:01:01:1630" never reaches our formatter. The
      // phone keyboard accepts arbitrary characters on paste; the mask
      // formatter below then strips/re-inserts the colons.
      keyboardType: TextInputType.phone,
      // Klaviaturada «done» — qidiruvning ikkinchi yo'li. Odam raqamni terib
      // bo'lib klaviaturani yopmoqchi bo'lganda tugmani qidirishi shart emas.
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => onSearch(),
      // Aks holda `InputDecorator` matnni ham, suffiksdagi tugmani ham
      // asosga (baseline) tekislaydi va tugma maydon ichida pastroqda turadi.
      textAlignVertical: TextAlignVertical.center,
      inputFormatters: [_CadastreMaskFormatter()],
      style: TextStyle(
        fontFamily: 'MTSText',
        fontSize: 15,
        letterSpacing: 0.3,
        color: textColor,
      ),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.fromLTRB(16, 18, 6, 18),
        // Tugma o'z eniga yoyilsin. Balandlik chegarasi YO'Q: `maxHeight`
        // qo'yilsa, `InputDecorator` suffiksni matn qatoriga emas, o'sha
        // quticha ichiga tekislaydi va tugma bir necha punkt pastda qoladi.
        suffixIconConstraints: const BoxConstraints(),
        // TUGMA UMUMAN YO'Q, TO RAQAM TO'LIQ BO'LMAGUNCHA.
        //
        // O'chiq tugma foydasiz: u joy egallaydi, «bosib bo'lmaydi» deb
        // turadi va nima yetishmayotganini aytmaydi. Paydo bo'lishning o'zi
        // — «raqam to'g'ri, endi qidirsa bo'ladi» degan ishora.
        //
        // Mezon «Davom etish» nikiga TENG: bitta [_cadastreRe]. Ikki joyda
        // ikki xil qoida bo'lsa, tugma chiqib, qidiruv esa ishlamasligi
        // mumkin edi.
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final ready = _AiCadastreScreenState._cadastreRe.hasMatch(
              value.text,
            );
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 190),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: ready
                  ? _CadastreSearchButton(
                      key: const ValueKey('search'),
                      isBusy: isBusy,
                      onPressed: onSearch,
                    )
                  : const SizedBox.shrink(key: ValueKey('empty')),
            );
          },
        ),
        hintText: 'XX:XX:XX:XX:XX:XXXX',
        hintStyle: TextStyle(
          fontFamily: 'MTSText',
          fontSize: 15,
          letterSpacing: 0.3,
          color: hintColor,
        ),
        filled: true,
        fillColor: fillColor,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.splashGreen, width: 1.4),
        ),
      ),
    );
  }
}

/// Maydon ichidagi «Qidirish» tugmasi.
///
/// Bu vidjet FAQAT raqam to'liq bo'lganda quriladi — o'chiq holati yo'q
/// (chaqirilishiga qarang). Shuning uchun paydo bo'lishning o'zi asosiy
/// ishora, ustiga esa bir marta yorug'lik yo'li o'tkazamiz.
///
/// KENGAYUVCHI HALQA ATAYLAB YO'Q: u tugmadan TASHQARIGA chiqadi, qo'shni
/// elementlarni turtadi va Android'ning eski «ripple» ini eslatadi. Yorug'lik
/// yo'li tugma chegarasidan chiqmaydi.
class _CadastreSearchButton extends StatefulWidget {
  const _CadastreSearchButton({
    super.key,
    required this.isBusy,
    required this.onPressed,
  });

  final bool isBusy;
  final VoidCallback onPressed;

  @override
  State<_CadastreSearchButton> createState() => _CadastreSearchButtonState();
}

class _CadastreSearchButtonState extends State<_CadastreSearchButton>
    with SingleTickerProviderStateMixin {
  /// Yorug'lik yo'li necha marta o'tadi. Ikkitadan ko'pi «diqqat!» deb
  /// qichqirishga aylanadi.
  static const _sweepCount = 2;

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  )..addStatusListener(_onIntroDone);

  /// Yorug'lik yo'li — sikl boshidagi yarmi harakat, qolgani JIMLIK. Ikki
  /// yo'l ketma-ket o'tsa, ular bir-biriga ulanib ketgan bo'lardi.
  late final Animation<double> _sweep = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0, 0.48, curve: Curves.easeInOut),
  );

  int _sweepsLeft = 0;

  void _onIntroDone(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_sweepsLeft > 0) {
      _sweepsLeft--;
      _intro.forward(from: 0);
    } else {
      _intro.reset();
    }
  }

  @override
  void initState() {
    super.initState();
    // Vidjet paydo bo'lishining o'zi «raqam tayyor» degani, shuning uchun
    // ishora shu yerda, boshqa shartsiz boshlanadi.
    _sweepsLeft = _sweepCount - 1;
    _intro.forward(from: 0);
  }

  /// So'zning o'lchangan eni — spinner chiqqanda tugma torayib ketmasligi
  /// uchun. O'lchov matn uslubi bilan bir xil bo'lishi shart.
  double _labelWidth(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontFamily: 'MTSCompact',
          fontSize: 13,
          height: 1.15,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width;
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Tugma ko'rinib turgan bo'lsa, u doim yashil — shuning uchun bu yerda
    // qorong'i rejimga qarash kerak emas: yashil fonda oq matn ikkalasida
    // ham bir xil.
    //
    // Yagona farq — qidiruv ketayotganda bosib bo'lmaydi.
    final active = !widget.isBusy;

    final label = tr(Localizations.localeOf(context), 'common.search');
    const radius = BorderRadius.all(Radius.circular(10));

    final content = widget.isBusy
        // Spinner SO'ZNING o'rnini egallaydi — tugmaning eni o'zgarmasligi
        // uchun kengligi so'zga tenglashtiriladi.
        ? SizedBox(
            height: 15,
            width: _labelWidth(context, label),
            child: const Center(
              child: SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
          )
        : Text(
            label,
            style: const TextStyle(
              fontFamily: 'MTSCompact',
              fontSize: 13,
              height: 1.15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          );

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        enabled: active,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.splashGreen,
            borderRadius: radius,
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: active ? widget.onPressed : null,
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      child: content,
                    ),
                    // Yorug'lik yo'li. Tugmadan TASHQARIGA chiqmaydi:
                    // yuqoridagi `clipBehavior` uni chegarada qirqadi.
                    if (active)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _sweep,
                            builder: (context, _) {
                              final t = _sweep.value;
                              if (t == 0 || t == 1) {
                                return const SizedBox.shrink();
                              }
                              return FractionallySizedBox(
                                widthFactor: 0.42,
                                // -1.7 dan 1.7 gacha: yo'l tugmaning bir
                                // chetidan kirib, ikkinchisidan chiqadi.
                                alignment: Alignment(-1.7 + t * 3.4, 0),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.white.withValues(alpha: 0),
                                        Colors.white.withValues(alpha: 0.3),
                                        Colors.white.withValues(alpha: 0),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CadastreMaskFormatter extends TextInputFormatter {
  static const _segments = [2, 2, 2, 2, 2, 4];
  // Base = 14 digits; allow extra for sub-parcel / building / unit tail
  // (e.g. 10:09:01:01:02:5942:0001:039).
  static const _maxDigits = 25;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final allDigits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final digits = allDigits.substring(
      0,
      allDigits.length.clamp(0, _maxDigits),
    );

    // Count how many digits sit to the LEFT of the incoming caret, so we can
    // put the caret back after the same digit once the colons are re-inserted
    // (instead of always jumping to the end — which broke mid-string edits).
    final selEnd = newValue.selection.end.clamp(0, newValue.text.length);
    final digitsBeforeCaret = newValue.text
        .substring(0, selEnd)
        .replaceAll(RegExp(r'\D'), '')
        .length
        .clamp(0, digits.length);

    final buffer = StringBuffer();
    var consumed = 0;
    for (var i = 0; i < _segments.length; i++) {
      if (consumed >= digits.length) break;
      final take = _segments[i];
      final end = (consumed + take).clamp(0, digits.length);
      if (i > 0) buffer.write(':');
      buffer.write(digits.substring(consumed, end));
      consumed = end;
    }
    // Extended tail (beyond the 6-block base): group remaining digits into
    // blocks of up to 4 so a pasted/typed sub-parcel number keeps its colons.
    while (consumed < digits.length) {
      final end = (consumed + 4).clamp(0, digits.length);
      buffer.write(':');
      buffer.write(digits.substring(consumed, end));
      consumed = end;
    }
    final formatted = buffer.toString();

    // Map "N digits before caret" → an offset in the formatted string, walking
    // past the inserted colons.
    var offset = 0;
    var seen = 0;
    while (offset < formatted.length && seen < digitsBeforeCaret) {
      if (formatted[offset] != ':') seen++;
      offset++;
    }
    // If we land right before a separator after completing a group, step past
    // it so forward typing flows into the next segment naturally.
    if (offset < formatted.length && formatted[offset] == ':') offset++;

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: offset.clamp(0, formatted.length),
      ),
    );
  }
}

class _PropertyInfoCardSkeleton extends StatefulWidget {
  const _PropertyInfoCardSkeleton({required this.isDark});

  final bool isDark;

  @override
  State<_PropertyInfoCardSkeleton> createState() =>
      _PropertyInfoCardSkeletonState();
}

class _PropertyInfoCardSkeletonState extends State<_PropertyInfoCardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final divider = isDark ? const Color(0xFF2C3133) : const Color(0xFFEEF0F2);
    final baseA = isDark ? const Color(0xFF1A2024) : const Color(0xFFE7EAEE);
    final baseB = isDark ? const Color(0xFF262C31) : const Color(0xFFF2F4F7);

    const labelWidths = [56.0, 36.0, 64.0, 48.0, 110.0];
    const valueWidths = [140.0, 150.0, 90.0, 50.0, 80.0];

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final shade = Color.lerp(baseA, baseB, _pulse.value)!;

        return Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < labelWidths.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _bar(shade, width: labelWidths[i], height: 11),
                      _bar(shade, width: valueWidths[i], height: 12),
                    ],
                  ),
                ),
                if (i != labelWidths.length - 1)
                  Container(height: 1, color: divider),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _bar(Color color, {required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

class _PropertyInfoCard extends StatelessWidget {
  const _PropertyInfoCard({
    required this.isDark,
    required this.info,
    required this.locale,
  });

  final bool isDark;
  final CadastreLookupResult info;
  final Locale locale;

  List<(String, String)> get _rows {
    final l = locale;
    String fmtNum(double? v, String unit) =>
        v == null ? '—' : '${_formatDecimal(v)} $unit';
    String fmtUzs(double? v) {
      if (v == null) return '—';
      if (v >= 1e9) {
        return '${(v / 1e9).toStringAsFixed(2)} ${_CadastreStrings.billion(l)}';
      }
      if (v >= 1e6) {
        return '${(v / 1e6).toStringAsFixed(1)} ${_CadastreStrings.million(l)}';
      }
      return _formatDecimal(v);
    }

    return [
      (_CadastreStrings.address(l), info.address ?? '—'),
      if (info.objectTypeHint != null)
        (_CadastreStrings.type(l), info.objectTypeHint!),
      (_CadastreStrings.area(l), fmtNum(info.effectiveArea, 'm²')),
      if (info.livingArea != null)
        (_CadastreStrings.livingArea(l), fmtNum(info.livingArea, 'm²')),
      (_CadastreStrings.cadastreValue(l), fmtUzs(info.cadastreValue)),
    ];
  }

  static String _formatDecimal(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final divider = isDark ? const Color(0xFF2C3133) : const Color(0xFFEEF0F2);
    final labelColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final valueColor = isDark ? Colors.white : AppColors.textBlack;

    final rows = _rows;
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${rows[i].$1}:',
                    style: TextStyle(
                      fontFamily: 'MTSText',
                      fontSize: 14,
                      height: 1.25,
                      color: labelColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Qiymat — qolgan joyni egallaydi va uzun matn (masalan to'liq
                  // manzil) bir necha qatorga o'raladi, satrdan toshib ketmaydi.
                  Expanded(
                    child: Text(
                      rows[i].$2,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        height: 1.25,
                        color: valueColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (i != rows.length - 1) Container(height: 1, color: divider),
          ],
        ],
      ),
    );
  }
}

class _LookupErrorCard extends StatelessWidget {
  const _LookupErrorCard({
    required this.message,
    required this.onRetry,
    required this.isDark,
    required this.locale,
  });

  final String message;
  final VoidCallback onRetry;
  final bool isDark;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0492A)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.error_outline,
                color: Color(0xFFE0492A),
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _CadastreStrings.lookupFailed(locale),
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 13,
              height: 1.35,
              color: hintColor,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(_CadastreStrings.retry(locale)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.splashGreen,
                side: const BorderSide(color: AppColors.splashGreen),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the lookup succeeded but no usable object area (total_area) came
/// back — the area is now REQUIRED (it feeds the valuation), so the user can't
/// continue. Nudges a fresh re-lookup.
/// Sariq ogohlantirish kartasi.
///
/// Sukut bo'yicha «maydon yo'q» matni, [message] berilsa — o'sha (hujjat
/// rejimi izohi). Ko'rinish bir xil, shuning uchun yangi karta yasalmadi.
class _AreaMissingCard extends StatelessWidget {
  const _AreaMissingCard({
    required this.isDark,
    required this.locale,
    this.message,
  });

  final bool isDark;
  final Locale locale;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark
        ? const Color(0xFF2A2410)
        : const Color(0xFFFFF7E6);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0A32A)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFE0A32A), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message ?? _CadastreStrings.areaMissing(locale),
              style: TextStyle(
                fontFamily: 'MTSText',
                fontSize: 13,
                height: 1.35,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A subtle "data wrong? re-fetch" affordance under the loaded property card.
class _RefreshRow extends StatelessWidget {
  const _RefreshRow({
    required this.isDark,
    required this.locale,
    required this.onTap,
  });

  final bool isDark;
  final Locale locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.refresh, size: 18),
        label: Text(_CadastreStrings.refresh(locale)),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.splashGreen,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
      ),
    );
  }
}

/// Zaxira varag'idagi tanlov.
enum _FallbackChoice { retry, document }

/// «Kadastr ma'lumotlari topilmadimi?» drawer'i — [_showFallbackSheet].
class _CadastreFallbackSheet extends StatelessWidget {
  const _CadastreFallbackSheet();

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkSurface : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

    // Rangli konteyner TASHQARIDA — fon pastki xavfsiz zonani ham to'ldiradi
    // (`login_required_sheet` dagi bilan bir xil sabab).
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
              const SizedBox(height: 20),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.splashGreen.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.description_outlined,
                  size: 26,
                  color: AppColors.splashGreen,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _CadastreStrings.fallbackTitle(l),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _CadastreStrings.fallbackBody(l),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontSize: 14,
                  height: 1.4,
                  color: muted,
                ),
              ),
              const SizedBox(height: 24),
              // Asosiy amal — QAYTA URINISH: ko'pchilikda raqam shunchaki
              // xato terilgan bo'ladi va reyestr yo'li aniqroq natija beradi.
              SheetButton(
                label: _CadastreStrings.fallbackRetry(l),
                filled: true,
                isDark: isDark,
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).pop(_FallbackChoice.retry);
                },
              ),
              const SizedBox(height: 10),
              SheetButton(
                label: _CadastreStrings.fallbackDocument(l),
                isDark: isDark,
                icon: Icons.upload_file_rounded,
                onTap: () =>
                    Navigator.of(context).pop(_FallbackChoice.document),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CadastreStrings {
  const _CadastreStrings._();

  static String notFoundRetry(Locale l) =>
      tr(l, 'services.ai.cadastre.not_found_retry');

  static String helpCta(Locale l) => tr(l, 'services.ai.cadastre.help_cta');

  static String fallbackTitle(Locale l) =>
      tr(l, 'services.ai.cadastre.fallback_title');

  static String fallbackBody(Locale l) =>
      tr(l, 'services.ai.cadastre.fallback_body');

  static String fallbackRetry(Locale l) =>
      tr(l, 'services.ai.cadastre.fallback_retry');

  static String fallbackDocument(Locale l) =>
      tr(l, 'services.ai.cadastre.fallback_document');

  static String documentMode(Locale l) =>
      tr(l, 'services.ai.cadastre.document_mode');

  static String areaMissing(Locale l) =>
      tr(l, 'services.ai.cadastre.area_missing');

  static String refresh(Locale l) => tr(l, 'services.ai.cadastre.refresh');

  static String title(Locale l) => tr(l, 'services.ai.common.brand_title');

  static String subtitle(Locale l) => tr(l, 'services.ai.cadastre.subtitle');

  static String cadastreNumber(Locale l) =>
      tr(l, 'services.ai.cadastre.cadastre_number');

  static String mapLabel(Locale l) => tr(l, 'services.ai.cadastre.map_label');

  static String recentSearches(Locale l) =>
      tr(l, 'services.ai.cadastre.recent_searches');

  static String propertyInfo(Locale l) =>
      tr(l, 'services.ai.cadastre.property_info');

  static String continueLabel(Locale l) => tr(l, 'services.ai.common.continue');

  static String signInFirst(Locale l) =>
      tr(l, 'services.ai.common.sign_in_first');

  // `services.ai.cadastre.not_found` OLIB TASHLANDI: uning o'rnini
  // `not_found_retry` egalladi — bir xil ma'no, lekin nima qilish kerakligini
  // ham aytadi («raqamni tekshirib, qayta urinib ko'ring»). Kalitning o'zi
  // adminkada qoldi, chunki seed hech qachon qator o'chirmaydi.

  static String networkError(Locale l, String err) =>
      '${tr(l, 'services.ai.cadastre.network_error')}: $err';

  static String genericError(Locale l) =>
      tr(l, 'services.ai.cadastre.generic_error');

  static String lookupFailed(Locale l) =>
      tr(l, 'services.ai.cadastre.lookup_failed');

  static String retry(Locale l) => tr(l, 'services.ai.cadastre.retry');

  static String address(Locale l) => tr(l, 'services.ai.cadastre.address');

  static String type(Locale l) => tr(l, 'services.ai.cadastre.type');

  static String area(Locale l) => tr(l, 'services.ai.cadastre.area');

  static String livingArea(Locale l) =>
      tr(l, 'services.ai.cadastre.living_area');

  static String cadastreValue(Locale l) =>
      tr(l, 'services.ai.cadastre.cadastre_value');

  static String billion(Locale l) => tr(l, 'services.ai.cadastre.billion');

  static String million(Locale l) => tr(l, 'services.ai.cadastre.million');
}
