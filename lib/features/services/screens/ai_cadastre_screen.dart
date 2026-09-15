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
import '../models/ai_scan_result.dart';
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
  Timer? _loadTimer;
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
  /// Holatni oldindan `idle` ga qaytarish shart: [_onCadastreChanged] qidiruvni
  /// faqat `idle`/`error` da boshlaydi, aks holda avvalgi uyning manzili va
  /// maydoni yangi raqam ostida turib qolardi.
  void _applyNumber(String number) {
    _loadTimer?.cancel();
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
  }

  void _useRecent(String number) {
    _cadastreController.value = TextEditingValue(
      text: number,
      selection: TextSelection.collapsed(offset: number.length),
    );
    // Filling the field to full length triggers _onCadastreChanged → lookup,
    // which now hits the backend cache first (instant for recents).
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
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
    final filled = _cadastreRe.hasMatch(text);
    if (filled) {
      if (_status == _LoadStatus.idle || _status == _LoadStatus.error) {
        _loadTimer?.cancel();
        _loadTimer = Timer(const Duration(milliseconds: 250), _runLookup);
        setState(() => _status = _LoadStatus.loading);
      }
    } else {
      _loadTimer?.cancel();
      if (_status != _LoadStatus.idle) {
        setState(() {
          _status = _LoadStatus.idle;
          _info = null;
          _errorMsg = null;
        });
        widget.onResolved?.call(null);
      }
    }
  }

  Future<void> _runLookup() async {
    final number = _cadastreController.text;
    // Already scraping this exact number — ignore the tap (see [_inFlightNumber]).
    if (_inFlightNumber == number) return;
    _loadTimer?.cancel();
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
          result.livingArea != null ||
          result.cadastreValue != null ||
          (result.objectTypeHint?.trim().isNotEmpty ?? false);
      if (!hasData) {
        setState(() {
          _status = _LoadStatus.error;
          _info = null;
          _errorMsg = _CadastreStrings.notFound(
            Localizations.localeOf(context),
          );
        });
        return;
      }
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
      if (!mounted || reqId != _lookupRequestId) return;
      setState(() {
        _status = _LoadStatus.error;
        _errorMsg = e.message;
      });
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
      await NetworkErrorHandler.maybeShow(context, e, onRetry: _runLookup);
    }
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
        // Area now comes straight from the cadastre (total_area) — the manual
        // area step was removed. widget.areaM2 is only a resume fallback.
        areaM2: info.totalArea ?? widget.areaM2,
      );
      _bundle = bundle;
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
  /// maydoni (total_area) bo'lishi shart — maydon shu yerdan olinadi (alohida
  /// maydon qadami olib tashlangan).
  bool get _areaReady =>
      _info?.totalArea != null && (_info?.totalArea ?? 0) > 0;

  bool get _canContinue => _status == _LoadStatus.loaded && _areaReady;

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
                        onBack: () => closeAiWizard(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: const StepProgressBar(count: 7, activeIndex: 0),
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
                                      else if (_status == _LoadStatus.error)
                                        _LookupErrorCard(
                                          message:
                                              _errorMsg ??
                                              _CadastreStrings.genericError(l),
                                          onRetry: _runLookup,
                                          isDark: isDark,
                                          locale: l,
                                        )
                                      else if (_info != null) ...[
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
  const _CadastreInput({required this.isDark, required this.controller});

  final bool isDark;
  final TextEditingController controller;

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
      inputFormatters: [_CadastreMaskFormatter()],
      style: TextStyle(
        fontFamily: 'MTSText',
        fontSize: 15,
        letterSpacing: 0.3,
        color: textColor,
      ),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
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
      (_CadastreStrings.area(l), fmtNum(info.totalArea, 'm²')),
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
class _AreaMissingCard extends StatelessWidget {
  const _AreaMissingCard({required this.isDark, required this.locale});

  final bool isDark;
  final Locale locale;

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
              _CadastreStrings.areaMissing(locale),
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

class _CadastreStrings {
  const _CadastreStrings._();

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

  static String notFound(Locale l) => tr(l, 'services.ai.cadastre.not_found');

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
