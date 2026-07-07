/// Arxitektura va qurilish loyihasi uchun TZ wizard.
///
/// 9 step:
///   1. Buyurtmachi rekvizitlari
///   2. Obyekt + manzil + kadastr
///   3. Loyiha haqida (turi, qavatlar, maydon, balandlik)
///   4. Xonalar tarkibi
///   5. Arxitektura va dizayn yechimlari
///   6. Konstruktiv yechimlar
///   7. Muhandislik tizimlari
///   8. Hudud rejalashtirish
///   9. Muddatlar + qo'shimcha talablar
///
/// `mode` parametri orqali ikki maqsadda ishlaydi:
///   - `architectureOrder` — yakuniy step'da mutaxassisga yuborish
///   - `aiValuation` — yakuniy step'da AI baholash chaqirish
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/input_validators.dart';
import '../../../../theme/app_colors.dart';
import '../../../auth/auth_storage.dart';
import '../../../home/user_profile.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../api_architecture_order_service.dart';
import '../../api_cadastre_service.dart';
import '../../api_forms_service.dart';
import '../../data/calculator_pricing_store.dart';
import '../../data/last_customer_store.dart';
import '../../models/calculator_pricing.dart';
import '../../models/dynamic_form_schema.dart';
import '../../models/ai_baholash_bundle.dart' show RoomKind, AiLocationInfo;
import '../../models/architecture_order_draft.dart';
import '../../widgets/cadastre_lookup_field.dart';
import '../../widgets/color_palette_field.dart';
import '../../widgets/location_picker_field.dart';
import '../../widgets/rooms_selector.dart';
import '../../widgets/service_app_bar.dart';
import '../../widgets/step_progress_bar.dart';
import '../../widgets/wizard_field.dart';
import '../../widgets/wizard_review_section.dart';
import 'arxitektura_tz_success_screen.dart';

/// Wizard'ning ikki ish rejimi: arxitektura buyurtmasini mutaxassisga yuborish,
/// yoki shu fieldlarni AI baholash uchun ishlatish.
enum WizardMode { architectureOrder, aiValuation }

class ArxitekturaTzWizardScreen extends StatefulWidget {
  const ArxitekturaTzWizardScreen({
    super.key,
    this.initialDraft,
    this.onSubmit,
    this.submitLabel,
    this.mode = WizardMode.architectureOrder,
  });

  final ArchitectureOrderDraft? initialDraft;

  /// Yakuniy step'da (oxirgi sahifada) "Yuborish" o'rniga chaqirilsin —
  /// agar berilsa, draft backend'ga yuborilmaydi va callback'ga o'tkaziladi.
  /// Bu 3D kadastr flow'i kabi embedded ishlatishlar uchun.
  final void Function(ArchitectureOrderDraft draft)? onSubmit;

  /// Oxirgi step tugmasi yorlig'i (default: mode'ga qarab).
  final String? submitLabel;

  /// Wizard'ning ish rejimi (architectureOrder yoki aiValuation).
  /// Default: architectureOrder (eski xulq-atvor saqlanadi).
  final WizardMode mode;

  @override
  State<ArxitekturaTzWizardScreen> createState() =>
      _ArxitekturaTzWizardScreenState();
}

class _ArxitekturaTzWizardScreenState extends State<ArxitekturaTzWizardScreen> {
  // To'ldiriladigan step'lar soni (progress bar shu sonni ko'rsatadi). Oxirgi
  // sahifa — `_previewIndex` — bu sanoqqa kirmaydigan "Tekshirish" ekrani.
  static const int _inputStepCount = 9;
  static const int _previewIndex = _inputStepCount; // 9

  late final ArchitectureOrderDraft _draft;
  late final PageController _pageController;
  int _stepIndex = 0;

  // Bo'lim qalamchasi ("✎") orqali tahrirga kirilganda, "Davom etish" o'rniga
  // "Saqlash" ko'rsatiladi va saqlangach to'g'ridan-to'g'ri Preview'ga qaytadi.
  bool _editReturn = false;

  // Step 1 controllers
  late final TextEditingController _customerName;
  late final TextEditingController _tin;
  late final TextEditingController _phone;
  late final TextEditingController _email;

  // Step 2 — manzil xaritadan tanlanadi (`_draft.location`); `_address` matni
  // shundan to'ldiriladi.
  late final TextEditingController _objectName;
  late final TextEditingController _address;
  late final TextEditingController _cadastreNumber;
  late final TextEditingController _landArea;
  late final TextEditingController _landUsePurpose;
  // Yer maydoni o'lchov birligi: 'm2' yoki 'sotix' (1 sotix = 100 m²).
  String _landUnit = 'm2';
  // Maqsadli foydalanish "Boshqa" tanlanganda erkin matn ko'rsatiladi.
  bool _landUseCustom = false;
  // "Obyekt nomi" (ixtiyoriy) — yopiq holatda; foydalanuvchi ochsa ko'rinadi.
  bool _showObjectName = false;
  // Obyekt turi grid'i — kalkulyatordan tanlangan bo'lsa yopiq (yashil chip),
  // "O'zgartirish" bosilganda to'liq ro'yxat ochiladi.
  bool _showObjectTypeGrid = false;

  // Step 3
  late final TextEditingController _floors;
  late final TextEditingController _totalArea;
  late final TextEditingController _buildingArea;
  late final TextEditingController _maxHeight;
  late final TextEditingController _objectSubtype;
  late final TextEditingController _constructionYear;

  // Step 5
  late final TextEditingController _roofMaterial;

  // Step 7
  late final TextEditingController _parkingCount;
  late final TextEditingController _sketchDays;
  late final TextEditingController _workingDays;
  late final TextEditingController _notes;

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialDraft ?? ArchitectureOrderDraft();
    _pageController = PageController();

    // Profil ma'lumotlaridan default qiymatlar (foydalanuvchi qaytadan
    // yozmasligi uchun). Draft'da allaqachon qiymat bo'lsa, profil ustiga
    // yozmaymiz.
    final profile = userProfileNotifier.value;
    if (profile != null) {
      if (_draft.customerName.isEmpty && profile.name.isNotEmpty) {
        _draft.customerName = profile.name;
      }
      if (_draft.phone.isEmpty && (profile.phone ?? '').isNotEmpty) {
        _draft.phone = profile.phone!;
      }
    }

    _customerName = TextEditingController(text: _draft.customerName);
    _tin = TextEditingController(text: _draft.tin);
    _phone = TextEditingController(text: _draft.phone);
    _email = TextEditingController(text: _draft.email);

    _objectName = TextEditingController(text: _draft.objectName);
    _address = TextEditingController(text: _draft.address);
    _cadastreNumber = TextEditingController(text: _draft.cadastreNumber);
    _landArea = TextEditingController(
      text: _draft.landAreaSqm?.toString() ?? '',
    );
    _landUsePurpose = TextEditingController(text: _draft.landUsePurpose);

    _floors = TextEditingController(text: _draft.floors?.toString() ?? '');
    _totalArea = TextEditingController(
      text: _draft.totalAreaSqm?.toString() ?? '',
    );
    _buildingArea = TextEditingController(
      text: _draft.buildingAreaSqm?.toString() ?? '',
    );
    _maxHeight = TextEditingController(
      text: _draft.maxHeightM?.toString() ?? '',
    );
    _objectSubtype = TextEditingController(text: _draft.objectSubtype);
    _constructionYear = TextEditingController(
      text: _draft.constructionYear?.toString() ?? '',
    );

    _roofMaterial = TextEditingController(
      text: _draft.constructive.roofMaterial ?? '',
    );

    _parkingCount = TextEditingController(
      text: _draft.territory.parkingCount?.toString() ?? '',
    );
    _sketchDays = TextEditingController(
      text: _draft.timeline.sketchDays?.toString() ?? '',
    );
    _workingDays = TextEditingController(
      text: _draft.timeline.workingDays?.toString() ?? '',
    );
    _notes = TextEditingController(text: _draft.notes);

    // Per-step "Davom etish" tugmasi tekstdan kelishi sababli, har controller
    // o'zgarganda butun ekranni qayta hisoblash uchun listenerlar.
    for (final c in [
      _customerName,
      _tin,
      _phone,
      _floors,
      _totalArea,
      _objectSubtype,
    ]) {
      c.addListener(_onCtrlChanged);
    }

    // Oxirgi yuborilgan buyurtmachidan to'ldirish (profilda STIR/INN va e-mail
    // bo'lmaganda ham qaytadan yozmaslik uchun). Bo'sh maydonlarnigina to'ldiramiz.
    _prefillFromLastCustomer();
    _loadFormSchema();
  }

  // Backend sxemasini fon rejimida yuklaymiz (kesh bor — tez). Muvaffaqiyatda
  // variant ro'yxatlari backend'dan, aks holda joriy hardcoded fallback'dan keladi.
  Future<void> _loadFormSchema() async {
    try {
      final schema = await FormsApiService().getForm('arxitektura_tz');
      if (mounted) setState(() => _formSchema = schema);
    } catch (_) {
      /* sxema yetib bormasa — hardcoded fallback ishlatiladi */
    }
  }

  Future<void> _prefillFromLastCustomer() async {
    final last = await const LastCustomerStore().load();
    if (last == null || !mounted) return;
    setState(() {
      if (_customerName.text.trim().isEmpty && last.name.isNotEmpty) {
        _customerName.text = last.name;
      }
      if (_tin.text.trim().isEmpty && last.tin.isNotEmpty) {
        _tin.text = last.tin;
      }
      if (_phone.text.trim().isEmpty && last.phone.isNotEmpty) {
        _phone.text = last.phone;
      }
      if (_email.text.trim().isEmpty && last.email.isNotEmpty) {
        _email.text = last.email;
      }
      _prefilledFromLast = true;
    });
  }

  // Buyurtmachi bo'limi oxirgi arizadan to'ldirilganini ko'rsatish uchun.
  bool _prefilledFromLast = false;

  // Backend forma sxemasi (arxitektura_tz) — qattiq-kodlangan variant ro'yxatlari
  // o'rniga adminkadan tahrirlanadigan variantlarni beradi. Yuklanmaguncha (yoki
  // xatoda) wizard joriy hardcoded fallback'ni ishlatadi.
  FormSchema? _formSchema;

  void _onCtrlChanged() {
    if (mounted) setState(() {});
  }

  // Kadastr lookup natijasidan manzil va maydonni avtomatik to'ldiramiz.
  void _onCadastreResult(CadastreLookupResult r) {
    setState(() {
      final addr = (r.address ?? '').trim();
      if (addr.isNotEmpty) {
        _address.text = addr;
        // "Manzil" (xaritadan tanlash) maydonida ham ko'rinsin. Lookup faqat
        // matnli manzil beradi (koordinatasiz) — bor koordinatalarni saqlab,
        // manzil matnini yangilaymiz (foydalanuvchi xaritadan aniqlashtirishi
        // mumkin).
        final loc = _draft.location;
        _draft.location = AiLocationInfo(
          lat: loc?.lat ?? 0,
          lng: loc?.lng ?? 0,
          addressText: addr,
        );
      }
      final area = r.totalArea ?? r.livingArea;
      if (area != null && area > 0) {
        final txt = _trimNum(area);
        _landUnit = 'm2';
        // "Yer maydoni" (2-qadamda ko'rinadigan maydon) bo'sh bo'lsa to'ldiramiz.
        if (_landArea.text.trim().isEmpty) _landArea.text = txt;
        _totalArea.text = txt;
      }
    });
  }

  static String _trimNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  // Katalog (backend → kesh → default) — adminkadan tahrirlanadigan variantlar.
  static List<CalcOption> _catalog(String group) =>
      calculatorPricingNotifier.value.optionsFor(group);

  static String _catalogLabel(List<CalcOption> opts, String? v, Locale l) {
    if (v == null) return '';
    for (final o in opts) {
      if (o.value == v) return o.localized(l);
    }
    return v;
  }

  // ── Forma sxemasi (form_definitions) variantlari ─────────────────────────
  // `_catalog`'ga o'xshash, lekin backend forma sxemasidan `maps_to` bo'yicha
  // o'qiydi. Sxema yo'q / maydon topilmasa bo'sh — chaqiruvchi hardcoded'ga tushadi.
  List<FormOption> _schemaOptsByPath(String mapsTo) {
    final schema = _formSchema;
    if (schema == null) return const [];
    for (final f in schema.allFields) {
      if (f.mapsTo == mapsTo) return f.options;
    }
    return const [];
  }

  static String _schemaOptLabel(List<FormOption> opts, String? v, Locale l) {
    if (v == null) return '';
    for (final o in opts) {
      if (o.value == v) return trMap(o.label, l);
    }
    return v;
  }

  /// Variant ro'yxati backend sxemasidan (bor bo'lsa), aks holda [fallbackOptions]
  /// + [fallbackLabelOf] (joriy qattiq-kodlangan ro'yxat). Tanlangan qiymat kodi
  /// ikkala manbada bir xil — shu sababli ko'rinish o'zgarmaydi.
  Widget _schemaChipPicker({
    required Locale l,
    required String mapsTo,
    required String label,
    required List<String> fallbackOptions,
    required String Function(String) fallbackLabelOf,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    final opts = _schemaOptsByPath(mapsTo);
    final useSchema = opts.isNotEmpty;
    return WizardChipPicker<String>(
      label: label,
      options: useSchema ? [for (final o in opts) o.value] : fallbackOptions,
      labelOf: (s) =>
          useSchema ? _schemaOptLabel(opts, s, l) : fallbackLabelOf(s),
      value: value,
      onChanged: onChanged,
    );
  }

  /// Enum-pikerlar uchun: kod (apiValue) bo'yicha sxema labeli, topilmasa
  /// [fallback]. Variant ro'yxati/saqlanishi o'zgarmaydi — faqat label.
  String _schemaEnumLabel(
    String mapsTo,
    String code,
    Locale l,
    String fallback,
  ) {
    for (final o in _schemaOptsByPath(mapsTo)) {
      if (o.value == code) return trMap(o.label, l);
    }
    return fallback;
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in [
      _customerName,
      _tin,
      _phone,
      _floors,
      _totalArea,
      _objectSubtype,
    ]) {
      c.removeListener(_onCtrlChanged);
    }
    for (final c in [
      _customerName,
      _tin,
      _phone,
      _email,
      _objectName,
      _address,
      _cadastreNumber,
      _landArea,
      _landUsePurpose,
      _floors,
      _totalArea,
      _buildingArea,
      _maxHeight,
      _objectSubtype,
      _constructionYear,
      _roofMaterial,
      _parkingCount,
      _sketchDays,
      _workingDays,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // STIR (9) yoki INN (14) — kiritilgan bo'lsa, uzunligi shu ikkitadan biri.
  bool get _tinValid => isValidTin(_tin.text);

  // Telefon — kiritilgan bo'lsa formati to'g'ri bo'lsin (xato matnni ko'rsatish
  // uchun; bo'sh holatda majburiy `*` belgisi yetarli).
  bool get _phoneError =>
      _phone.text.trim().isNotEmpty && !isValidUzPhone(_phone.text);

  // ── Validatsiya per-step ─────────────────────────────────────────────
  bool get _canAdvance {
    switch (_stepIndex) {
      case 0:
        return _customerName.text.trim().length >= 2 &&
            isValidUzPhone(_phone.text) &&
            _tinValid &&
            isValidEmail(_email.text);
      case 2:
        return _draft.objectType != null;
      case _previewIndex:
        // Preview'da "Yuborish" — barcha majburiy maydonlar to'ldirilgan bo'lsin.
        return _draft.canSubmit;
      default:
        return true;
    }
  }

  bool get _isPreview => _stepIndex == _previewIndex;

  void _syncDraftFromControllers() {
    _draft.customerName = _customerName.text;
    _draft.tin = _tin.text;
    _draft.phone = _phone.text;
    _draft.email = _email.text;

    _draft.objectName = _objectName.text;
    _draft.address = _address.text;
    _draft.cadastreNumber = _cadastreNumber.text;
    final landVal = _parseDouble(_landArea.text);
    _draft.landAreaSqm = landVal == null
        ? null
        : (_landUnit == 'sotix' ? landVal * 100 : landVal);
    _draft.landUsePurpose = _landUsePurpose.text;

    _draft.floors = _parseInt(_floors.text);
    _draft.totalAreaSqm = _parseDouble(_totalArea.text);
    _draft.buildingAreaSqm = _parseDouble(_buildingArea.text);
    _draft.maxHeightM = _parseDouble(_maxHeight.text);
    _draft.objectSubtype = _objectSubtype.text;
    _draft.constructionYear = _parseInt(_constructionYear.text);

    // Ranglar ColorPaletteField orqali to'g'ridan-to'g'ri draftga yoziladi.
    _draft.constructive.roofMaterial = _roofMaterial.text.trim().isEmpty
        ? null
        : _roofMaterial.text.trim();

    _draft.territory.parkingCount = _parseInt(_parkingCount.text);
    _draft.timeline.sketchDays = _parseInt(_sketchDays.text);
    _draft.timeline.workingDays = _parseInt(_workingDays.text);
    _draft.notes = _notes.text;
  }

  void _animateToPage(int index) {
    setState(() => _stepIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  /// Preview'dagi qalamcha bosilganda — shu bo'lim step'iga o'tib, "Saqlash"
  /// rejimini yoqamiz (saqlangach Preview'ga qaytadi).
  void _editStep(int index) {
    HapticFeedback.lightImpact();
    setState(() => _editReturn = true);
    _animateToPage(index);
  }

  Future<void> _next() async {
    _syncDraftFromControllers();
    if (!_canAdvance) return;
    HapticFeedback.lightImpact();

    // Bo'limni tahrirlash rejimida — to'g'ridan-to'g'ri Preview'ga qaytamiz.
    if (_editReturn) {
      setState(() => _editReturn = false);
      _animateToPage(_previewIndex);
      return;
    }

    if (_isPreview) {
      await _submit();
      return;
    }

    _animateToPage(_stepIndex + 1);
  }

  void _back() {
    // Tahrirlash rejimidan — saqlamasdan Preview'ga qaytamiz.
    if (_editReturn) {
      _syncDraftFromControllers();
      setState(() => _editReturn = false);
      _animateToPage(_previewIndex);
      return;
    }
    if (_stepIndex == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    HapticFeedback.lightImpact();
    _animateToPage(_stepIndex - 1);
  }

  Future<void> _submit() async {
    final l = Localizations.localeOf(context);
    if (!_draft.canSubmit) {
      _showError(_Strings.fillRequired(l));
      return;
    }

    // Embedded mode: callback'ga uzatamiz (3D kadastr/AI baholash flow'lari).
    if (widget.onSubmit != null) {
      HapticFeedback.lightImpact();
      widget.onSubmit!(_draft);
      return;
    }

    // AI valuation mode: callback berilmagan bo'lsa ham, foydalanuvchi
    // wizard'ni mustaqil ochishi mumkin emas (ai_scan_screen orqali keladi).
    // Shu sababli onSubmit majburiy hisoblanadi va backend submission'siz
    // qaytaramiz.
    if (widget.mode == WizardMode.aiValuation) {
      _showError(_Strings.aiCallbackMissing(l));
      return;
    }

    // Standalone mode (architectureOrder): backend'ga yuborish.
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null) {
      if (mounted) {
        _showError(switch (Localizations.localeOf(context).languageCode) {
          'ru' => 'Чтобы отправить заявку, сначала войдите в систему',
          'en' => 'Please sign in first to submit the order',
          _ => 'Buyurtma yuborish uchun avval tizimga kiring',
        });
      }
      return;
    }

    setState(() => _submitting = true);
    try {
      final api = ArchitectureOrderApiService();
      final created = await api.submit(draft: _draft, token: token);
      // Keyingi ariza uchun buyurtmachi rekvizitlarini eslab qolamiz.
      await const LastCustomerStore().save(
        LastCustomer(
          name: _draft.customerName,
          tin: _draft.tin,
          phone: _draft.phone,
          email: _draft.email,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ArxitekturaTzSuccessScreen(orderId: created.id),
        ),
      );
    } on ArchitectureOrderApiException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('${_Strings.networkError(l)}: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: const Color(0xFFE0492A),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
  }

  // ── UI ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;

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
                        title: _appBarTitle(l),
                        subtitle: _stepTitle(_stepIndex, l),
                        onBack: _back,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: StepProgressBar(
                        count: _inputStepCount,
                        // Preview'da barcha step'lar bajarilgan ko'rinadi.
                        activeIndex: _isPreview
                            ? _inputStepCount - 1
                            : _stepIndex,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: PageView(
                        controller: _pageController,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _buildStep1(l),
                          _buildStep2(l),
                          _buildStep3(l),
                          _buildStep4(l),
                          _buildStep5(l),
                          _buildStep6(l),
                          _buildStep7(l),
                          _buildStep8(l),
                          _buildStep9(l),
                          _buildPreview(l),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: ListingCtaButton(
                        label: _submitting
                            ? _Strings.submitting(l)
                            : (_editReturn
                                  ? _Strings.saveChanges(l)
                                  : (_isPreview
                                        ? (widget.submitLabel ??
                                              _defaultSubmitLabel(l))
                                        : _Strings.continueLabel(l))),
                        enabled: _canAdvance && !_submitting,
                        onTap: _next,
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

  String _stepTitle(int i, Locale l) {
    return switch (i) {
      0 => '1/9 — ${_Strings.crumbCustomer(l)}',
      1 => '2/9 — ${_Strings.crumbObject(l)}',
      2 => '3/9 — ${_Strings.crumbProject(l)}',
      3 => '4/9 — ${_Strings.crumbRooms(l)}',
      4 => '5/9 — ${_Strings.crumbArchitecture(l)}',
      5 => '6/9 — ${_Strings.crumbConstructive(l)}',
      6 => '7/9 — ${_Strings.crumbEngineering(l)}',
      7 => '8/9 — ${_Strings.crumbTerritory(l)}',
      8 => '9/9 — ${_Strings.crumbTimeline(l)}',
      _previewIndex => _Strings.crumbReview(l),
      _ => '',
    };
  }

  String _defaultSubmitLabel(Locale l) => switch (widget.mode) {
    WizardMode.aiValuation => _Strings.aiValuation(l),
    WizardMode.architectureOrder => _Strings.submit(l),
  };

  String _appBarTitle(Locale l) => switch (widget.mode) {
    WizardMode.aiValuation => _Strings.aiValuation(l),
    WizardMode.architectureOrder => _Strings.archTz(l),
  };

  Widget _scrollableStep(List<Widget> children) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        for (final c in children) ...[c, const SizedBox(height: 14)],
      ],
    );
  }

  // ── Step 1: Buyurtmachi ──────────────────────────────────────────────
  Widget _buildStep1(Locale l) {
    return _scrollableStep([
      WizardSectionTitle(text: _Strings.customerDetails(l)),
      if (_prefilledFromLast)
        WizardPrefillHint(text: _Strings.prefilledHint(l)),
      WizardField(
        label: _Strings.customerNameLabel(l),
        controller: _customerName,
        placeholder: switch (l.languageCode) {
          'ru' => 'Аслиддин Хамраев',
          'en' => 'Asliddin Hamrayev',
          _ => 'Asliddin Hamrayev',
        },
        required: true,
      ),
      WizardField(
        label: _Strings.tinLabel(l),
        controller: _tin,
        placeholder: '300000000',
        numericOnly: true,
        maxLength: 14,
        errorText: _tinValid ? null : _Strings.tinError(l),
      ),
      WizardField(
        label: _Strings.phoneLabel(l),
        controller: _phone,
        placeholder: '+998 90 123 45 67',
        keyboardType: TextInputType.phone,
        phoneFormat: true,
        maxLength: 17,
        required: true,
        errorText: _phoneError ? _Strings.phoneError(l) : null,
      ),
      WizardField(
        label: switch (l.languageCode) {
          'ru' => 'E-mail',
          'en' => 'E-mail',
          _ => 'E-mail',
        },
        controller: _email,
        placeholder: 'sample@mail.com',
        keyboardType: TextInputType.emailAddress,
        errorText: isValidEmail(_email.text) ? null : _Strings.emailError(l),
      ),
    ]);
  }

  // ── Step 2: Obyekt va manzil ─────────────────────────────────────────
  // Kadastr raqami birinchi — kiritilsa manzilni avtomatik to'ldiradi. Yer
  // maydoni + o'lchov birligi bitta qatorda, maqsadli foydalanish chip orqali,
  // ixtiyoriy "Obyekt nomi" esa pastda yopiq holatda.
  Widget _buildStep2(Locale l) {
    return _scrollableStep([
      WizardSectionTitle(text: _Strings.objectAndAddress(l)),
      // Kadastr raqami — raqam kiritilsa, manzil avtomatik to'ladi.
      CadastreLookupField(
        controller: _cadastreNumber,
        label: _Strings.cadastreNumberLabel(l),
        onResult: _onCadastreResult,
      ),
      LocationPickerField(
        label: _Strings.addressLabel(l),
        value: _draft.location,
        onChanged: (loc) => setState(() {
          _draft.location = loc;
          if (loc.addressText != null) {
            _address.text = loc.addressText!;
          }
        }),
      ),
      _landAreaField(l),
      _landUsePurposeField(l),
      _optionalObjectNameField(l),
    ]);
  }

  // Yer maydoni — son maydoni + ichki m²/sotix segmentli toggle (bitta qator).
  Widget _landAreaField(Locale l) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark ? Colors.white : AppColors.textBlack;
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : const Color(0xFFB4B9BF);

    // Segmentli toggle — faqat yashil indikator suriladi (ikki alohida
    // konteynerni qayta bo'yash "miltillash"ini oldini olish uchun).
    const double toggleW = 122;
    const double toggleH = 34;
    Widget unitToggle() {
      Widget pill(String unit, String label) {
        final selected = _landUnit == unit;
        return Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _landUnit = unit),
            child: Center(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 160),
                style: TextStyle(
                  fontFamily: 'MTSText',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: selected ? Colors.white : hintColor,
                ),
                child: Text(label),
              ),
            ),
          ),
        );
      }

      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        width: toggleW,
        height: toggleH,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF15191B) : const Color(0xFFF1F2F4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              alignment: _landUnit == 'm2'
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: Container(
                width: (toggleW - 6) / 2,
                height: toggleH - 6,
                decoration: BoxDecoration(
                  color: AppColors.splashGreen,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            Row(
              children: [
                pill('m2', _Strings.unitSqm(l)),
                pill('sotix', 'sotix'),
              ],
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _Strings.landAreaLabel(l),
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            height: 1.25,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          padding: const EdgeInsets.only(left: 14, right: 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _landArea,
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 14.5,
                    color: textColor,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    hintText: '500',
                    hintStyle: TextStyle(
                      fontFamily: 'MTSText',
                      fontSize: 14.5,
                      color: hintColor,
                    ),
                  ),
                ),
              ),
              unitToggle(),
            ],
          ),
        ),
      ],
    );
  }

  // Yerning maqsadli foydalanishi — chip tanlash, "Boshqa" erkin matn ochadi.
  Widget _landUsePurposeField(Locale l) {
    final labelColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : AppColors.textBlack;
    final opts = <(String, String)>[
      ('turar_joy', _Strings.landUseResidential(l)),
      ('ishlab_chiqarish', _Strings.landUseProduction(l)),
      ('savdo', _Strings.landUseCommercial(l)),
      ('aralash', _Strings.landUseMixed(l)),
    ];
    final current = _landUsePurpose.text.trim();
    String? selectedKey;
    for (final (k, _) in opts) {
      if (k == current) selectedKey = k;
    }
    final isOther =
        _landUseCustom || (current.isNotEmpty && selectedKey == null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _Strings.landUsePurposeLabel(l),
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            height: 1.25,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (k, label) in opts)
              _choiceChip(label, !isOther && selectedKey == k, () {
                setState(() {
                  _landUseCustom = false;
                  _landUsePurpose.text = k;
                });
              }),
            _choiceChip(_Strings.landUseOther(l), isOther, () {
              setState(() {
                _landUseCustom = true;
                _landUsePurpose.text = '';
              });
            }),
          ],
        ),
        if (isOther) ...[
          const SizedBox(height: 12),
          WizardField(
            label: _Strings.landUseOther(l),
            controller: _landUsePurpose,
            placeholder: _Strings.landUsePurposePlaceholder(l),
          ),
        ],
      ],
    );
  }

  // Ixtiyoriy "Obyekt nomi" — yopiq holatda; matn bo'lsa avtomatik ochiq.
  Widget _optionalObjectNameField(Locale l) {
    final show = _showObjectName || _objectName.text.trim().isNotEmpty;
    if (show) {
      return WizardField(
        label: _Strings.objectNameLabel(l),
        controller: _objectName,
        placeholder: _Strings.objectNamePlaceholder(l),
      );
    }
    return InkWell(
      onTap: () => setState(() => _showObjectName = true),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            const Icon(
              Icons.add_rounded,
              size: 18,
              color: AppColors.splashGreen,
            ),
            const SizedBox(width: 6),
            Text(
              _Strings.addObjectNameOptional(l),
              style: const TextStyle(
                fontFamily: 'MTSText',
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                color: AppColors.splashGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Bitta tanlov chipi. `showCheck` — ko'p tanlovli (multi-select) guruhlarda
  // tanlanganini aniqroq ko'rsatish uchun belgi qo'shadi.
  Widget _choiceChip(
    String label,
    bool selected,
    VoidCallback onTap, {
    bool showCheck = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final idleBorder = isDark
        ? const Color(0xFF2C3133)
        : const Color(0xFFE3E5E8);
    final idleBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final idleText = isDark
        ? Colors.white.withValues(alpha: 0.85)
        : AppColors.textBlack;
    return Material(
      color: selected ? AppColors.splashGreen : idleBg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? AppColors.splashGreen : idleBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showCheck && selected) ...[
                const Icon(Icons.check, size: 15, color: Colors.white),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'MTSText',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: selected ? Colors.white : idleText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Ko'p tanlovli "xususiyatlar" guruhi — bir nechta boolean'ni alohida
  // switch qatorlari o'rniga ixcham chip wrap sifatida ko'rsatadi.
  Widget _featureChips(String label, List<(String, bool, VoidCallback)> items) {
    final labelColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : AppColors.textBlack;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            height: 1.25,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (lbl, sel, tap) in items)
              _choiceChip(lbl, sel, () {
                HapticFeedback.selectionClick();
                tap();
              }, showCheck: true),
          ],
        ),
      ],
    );
  }

  // ── Step 3: Loyiha haqida ────────────────────────────────────────────
  Widget _buildStep3(Locale l) {
    // Qurilish yili faqat rekonstruksiyada (yoki AI baholashda — mavjud
    // bino qiymati uchun) muhim; yangi qurilishda ko'rsatilmaydi.
    final showYear =
        _draft.constructionType == ConstructionType.rekonstruksiya ||
        widget.mode == WizardMode.aiValuation;
    return _scrollableStep([
      WizardSectionTitle(text: _Strings.projectGeneralInfo(l)),
      _objectTypePicker(l),
      WizardChipPicker<ConstructionType>(
        label: _Strings.constructionTypeLabel(l),
        options: ConstructionType.values,
        labelOf: (t) => _schemaEnumLabel(
          'construction_type',
          t.apiValue,
          l,
          t == ConstructionType.yangi
              ? _Strings.constructionNew(l)
              : _Strings.constructionReconstruction(l),
        ),
        value: _draft.constructionType,
        onChanged: (v) => setState(
          () => _draft.constructionType = v ?? ConstructionType.yangi,
        ),
      ),
      Row(
        children: [
          Expanded(
            child: WizardField(
              label: _Strings.floorsCountLabel(l),
              controller: _floors,
              placeholder: '2',
              numericOnly: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: WizardField(
              label: _Strings.maxHeightLabel(l),
              controller: _maxHeight,
              placeholder: '12',
              suffix: _Strings.unitM(l),
              numericOnly: true,
              allowDecimal: true,
            ),
          ),
        ],
      ),
      if (showYear)
        WizardField(
          label: _Strings.constructionYearLabel(l),
          controller: _constructionYear,
          placeholder: '2018',
          numericOnly: true,
        ),
      Row(
        children: [
          Expanded(
            child: WizardField(
              label: _Strings.totalAreaLabel(l),
              controller: _totalArea,
              placeholder: '350',
              suffix: _Strings.unitSqm(l),
              numericOnly: true,
              allowDecimal: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: WizardField(
              label: _Strings.buildingAreaLabel(l),
              controller: _buildingArea,
              placeholder: '180',
              suffix: _Strings.unitSqm(l),
              numericOnly: true,
              allowDecimal: true,
            ),
          ),
        ],
      ),
      WizardSwitchTile(
        label: _Strings.hasBasement(l),
        value: _draft.hasBasement,
        onChanged: (v) => setState(() => _draft.hasBasement = v),
      ),
      WizardSwitchTile(
        label: _Strings.hasMansard(l),
        value: _draft.hasMansard,
        onChanged: (v) => setState(() => _draft.hasMansard = v),
      ),
      WizardSwitchTile(
        label: _Strings.hasUndergroundParking(l),
        value: _draft.hasUndergroundParking,
        onChanged: (v) => setState(() => _draft.hasUndergroundParking = v),
      ),
    ]);
  }

  // Obyekt turi — kalkulyatordan tanlangan bo'lsa yopiq ko'rinish (yashil chip
  // + "O'zgartirish"); aks holda (masalan AI baholash) to'liq ro'yxat ochiq.
  Widget _objectTypePicker(Locale l) {
    final labelColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : AppColors.textBlack;
    final expanded = _showObjectTypeGrid || _draft.objectType == null;

    Widget header() => Row(
      children: [
        Text(
          _Strings.objectTypeLabel(l),
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            height: 1.25,
            color: labelColor,
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text(
            '*',
            style: TextStyle(color: Color(0xFFE0492A), fontSize: 14),
          ),
        ),
      ],
    );

    final children = <Widget>[];
    if (expanded) {
      children.add(
        WizardChipPicker<ArchObjectType>(
          label: _Strings.objectTypeLabel(l),
          required: true,
          options: ArchObjectType.values,
          labelOf: (t) => _schemaEnumLabel(
            'object_type',
            t.apiValue,
            l,
            _objectTypeLabel(t, l),
          ),
          value: _draft.objectType,
          onChanged: (v) => setState(() {
            _draft.objectType = v;
            // Tanlangach yopib qo'yamiz (kompakt ko'rinishga qaytadi).
            if (v != null) _showObjectTypeGrid = false;
          }),
        ),
      );
    } else {
      children.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(),
            const SizedBox(height: 8),
            Row(
              children: [
                _choiceChip(
                  _objectTypeLabel(_draft.objectType!, l),
                  true,
                  () => setState(() => _showObjectTypeGrid = true),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () => setState(() => _showObjectTypeGrid = true),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    child: Text(
                      _Strings.changeLabel(l),
                      style: const TextStyle(
                        fontFamily: 'MTSText',
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        color: AppColors.splashGreen,
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
    if (_draft.objectType == ArchObjectType.boshqa) {
      children.add(const SizedBox(height: 14));
      children.add(
        WizardField(
          label: _Strings.objectSubtypeLabel(l),
          controller: _objectSubtype,
          placeholder: _Strings.objectSubtypePlaceholder(l),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  // ── Step 4: Xonalar tarkibi ──────────────────────────────────────────
  Widget _buildStep4(Locale l) {
    return _scrollableStep([
      WizardSectionTitle(text: _Strings.roomsComposition(l)),
      RoomsSelector(
        rooms: _draft.rooms,
        locale: l,
        showArea: true,
        subtitle: switch (l.languageCode) {
          'ru' => 'Выберите типы комнат, укажите кол-во и площадь (м²)',
          'en' => 'Pick room types, enter count and area (m²)',
          _ => 'Xona turlarini tanlang, soni va maydonini (m²) kiriting',
        },
        onChanged: () => setState(() {}),
      ),
    ]);
  }

  // ── Step 5: Arxitektura yechimlari ───────────────────────────────────
  Widget _buildStep5(Locale l) {
    final styleOpts = _catalog('arxitektura.style');
    final facadeOpts = _catalog('arxitektura.facade_material');
    return _scrollableStep([
      WizardSectionTitle(text: _Strings.architectureAndDesign(l)),
      _OptionalStepHint(text: _Strings.designOptionalHint(l)),
      WizardChipPicker<String>(
        label: _Strings.styleLabel(l),
        options: [for (final o in styleOpts) o.value],
        labelOf: (s) => _catalogLabel(styleOpts, s, l),
        value: _draft.architecture.style,
        onChanged: (v) => setState(() => _draft.architecture.style = v),
      ),
      WizardChipPicker<String>(
        label: _Strings.facadeMaterialLabel(l),
        options: [for (final o in facadeOpts) o.value],
        labelOf: (s) => _catalogLabel(facadeOpts, s, l),
        value: _draft.architecture.facadeMaterial,
        onChanged: (v) =>
            setState(() => _draft.architecture.facadeMaterial = v),
      ),
      // 3D vizualizatsiya — narx/ko'lamga ta'sir qiladigan yagona tanlov;
      // rang panelidan past ko'milib qolmasligi uchun yuqorida.
      WizardSwitchTile(
        label: _Strings.need3dVisualization(l),
        value: _draft.architecture.has3dVisualization,
        onChanged: (v) =>
            setState(() => _draft.architecture.has3dVisualization = v),
      ),
      ColorPaletteField(
        label: _Strings.colorsLabel(l),
        value: _draft.architecture.colors,
        onChanged: (v) =>
            _draft.architecture.colors = v.trim().isEmpty ? null : v.trim(),
      ),
    ]);
  }

  // ── Step 6: Konstruktiv yechimlar ────────────────────────────────────
  Widget _buildStep6(Locale l) {
    return _scrollableStep([
      WizardSectionTitle(text: _Strings.constructiveSolutions(l)),
      _OptionalStepHint(text: _Strings.technicalOptionalHint(l)),
      _schemaChipPicker(
        l: l,
        mapsTo: 'details.constructive.scheme',
        label: _Strings.constructiveSchemeLabel(l),
        fallbackOptions: const [
          'karkas',
          'monolit',
          'gisht',
          'aralash',
          'metall',
        ],
        fallbackLabelOf: (s) => switch (s) {
          'karkas' => _Strings.schemeFrame(l),
          'monolit' => _Strings.schemeMonolith(l),
          'gisht' => _Strings.materialBrick(l),
          'aralash' => _Strings.schemeMixed(l),
          'metall' => _Strings.materialMetal(l),
          _ => s,
        },
        value: _draft.constructive.scheme,
        onChanged: (v) => setState(() => _draft.constructive.scheme = v),
      ),
      _schemaChipPicker(
        l: l,
        mapsTo: 'details.constructive.foundation',
        label: _Strings.foundationLabel(l),
        fallbackOptions: const ['ustun', 'lenta', 'plita', 'svay'],
        fallbackLabelOf: (s) => switch (s) {
          'ustun' => _Strings.foundationColumn(l),
          'lenta' => _Strings.foundationStrip(l),
          'plita' => _Strings.foundationSlab(l),
          'svay' => _Strings.foundationPile(l),
          _ => s,
        },
        value: _draft.constructive.foundation,
        onChanged: (v) => setState(() => _draft.constructive.foundation = v),
      ),
      _schemaChipPicker(
        l: l,
        mapsTo: 'details.constructive.walls',
        label: _Strings.wallMaterialLabel(l),
        fallbackOptions: const ['gisht', 'gazoblok', 'beton', 'sendvich_panel'],
        fallbackLabelOf: (s) => switch (s) {
          'gisht' => _Strings.materialBrick(l),
          'gazoblok' => _Strings.materialAerocrete(l),
          'beton' => _Strings.materialConcrete(l),
          'sendvich_panel' => _Strings.materialSandwichPanel(l),
          _ => s,
        },
        value: _draft.constructive.walls,
        onChanged: (v) => setState(() => _draft.constructive.walls = v),
      ),
      _schemaChipPicker(
        l: l,
        mapsTo: 'details.constructive.ceiling',
        label: _Strings.ceilingLabel(l),
        fallbackOptions: const ['temir_beton', 'yogoch', 'metall'],
        fallbackLabelOf: (s) => switch (s) {
          'temir_beton' => _Strings.ceilingReinforcedConcrete(l),
          'yogoch' => _Strings.materialWood(l),
          'metall' => _Strings.materialMetal(l),
          _ => s,
        },
        value: _draft.constructive.ceiling,
        onChanged: (v) => setState(() => _draft.constructive.ceiling = v),
      ),
      _schemaChipPicker(
        l: l,
        mapsTo: 'details.constructive.roof_type',
        label: _Strings.roofTypeLabel(l),
        fallbackOptions: const ['yassi', 'qiya'],
        fallbackLabelOf: (s) =>
            s == 'yassi' ? _Strings.roofFlat(l) : _Strings.roofPitched(l),
        value: _draft.constructive.roofType,
        onChanged: (v) => setState(() => _draft.constructive.roofType = v),
      ),
      WizardField(
        label: _Strings.roofMaterialLabel(l),
        controller: _roofMaterial,
        placeholder: _Strings.roofMaterialPlaceholder(l),
      ),
    ]);
  }

  // ── Step 7: Muhandislik tizimlari ────────────────────────────────────
  Widget _buildStep7(Locale l) {
    final eng = _draft.engineering;
    return _scrollableStep([
      WizardSectionTitle(text: _Strings.engineeringSystems(l)),
      _OptionalStepHint(text: _Strings.technicalOptionalHint(l)),
      _schemaChipPicker(
        l: l,
        mapsTo: 'details.engineering.water_source',
        label: _Strings.waterSourceLabel(l),
        fallbackOptions: const ['markaziy', 'quduq'],
        fallbackLabelOf: (s) =>
            s == 'markaziy' ? _Strings.central(l) : _Strings.well(l),
        value: _draft.engineering.waterSource,
        onChanged: (v) => setState(() => _draft.engineering.waterSource = v),
      ),
      _schemaChipPicker(
        l: l,
        mapsTo: 'details.engineering.sewage',
        label: _Strings.sewageLabel(l),
        fallbackOptions: const ['markaziy', 'septik'],
        fallbackLabelOf: (s) =>
            s == 'markaziy' ? _Strings.central(l) : _Strings.septic(l),
        value: _draft.engineering.sewage,
        onChanged: (v) => setState(() => _draft.engineering.sewage = v),
      ),
      _schemaChipPicker(
        l: l,
        mapsTo: 'details.engineering.heating',
        label: _Strings.heatingLabel(l),
        fallbackOptions: const ['gaz', 'elektr', 'qozonxona'],
        fallbackLabelOf: (s) => switch (s) {
          'gaz' => _Strings.heatingGas(l),
          'elektr' => _Strings.heatingElectric(l),
          'qozonxona' => _Strings.heatingBoiler(l),
          _ => s,
        },
        value: _draft.engineering.heating,
        onChanged: (v) => setState(() => _draft.engineering.heating = v),
      ),
      _schemaChipPicker(
        l: l,
        mapsTo: 'details.engineering.ventilation',
        label: _Strings.ventilationLabel(l),
        fallbackOptions: const ['tabiiy', 'mexanik'],
        fallbackLabelOf: (s) => s == 'tabiiy'
            ? _Strings.ventilationNatural(l)
            : _Strings.ventilationMechanical(l),
        value: _draft.engineering.ventilation,
        onChanged: (v) => setState(() => _draft.engineering.ventilation = v),
      ),
      _schemaChipPicker(
        l: l,
        mapsTo: 'details.engineering.air_conditioning',
        label: _Strings.airConditioningLabel(l),
        fallbackOptions: const ['split', 'vrf', 'chiller'],
        fallbackLabelOf: (s) => switch (s) {
          'split' => 'Split',
          'vrf' => 'VRF',
          'chiller' => 'Chiller',
          _ => s,
        },
        value: _draft.engineering.airConditioning,
        onChanged: (v) =>
            setState(() => _draft.engineering.airConditioning = v),
      ),
      _featureChips(_Strings.extraSystemsLabel(l), [
        (
          _Strings.backupGenerator(l),
          eng.hasGenerator,
          () => setState(() => eng.hasGenerator = !eng.hasGenerator),
        ),
        (
          _Strings.fireSafetySystem(l),
          eng.hasFireSystem,
          () => setState(() => eng.hasFireSystem = !eng.hasFireSystem),
        ),
        (
          _Strings.alarmSystem(l),
          eng.hasAlarm,
          () => setState(() => eng.hasAlarm = !eng.hasAlarm),
        ),
        (
          _Strings.videoSurveillance(l),
          eng.hasVideoSurveillance,
          () => setState(
            () => eng.hasVideoSurveillance = !eng.hasVideoSurveillance,
          ),
        ),
        (
          _Strings.solarPanels(l),
          eng.hasSolarPanels,
          () => setState(() => eng.hasSolarPanels = !eng.hasSolarPanels),
        ),
      ]),
    ]);
  }

  // ── Step 8: Hudud rejalashtirish ─────────────────────────────────────
  Widget _buildStep8(Locale l) {
    final t = _draft.territory;
    return _scrollableStep([
      WizardSectionTitle(text: _Strings.territoryPlanning(l)),
      _OptionalStepHint(text: _Strings.designOptionalHint(l)),
      _featureChips(_Strings.territoryFeaturesLabel(l), [
        (
          _Strings.parking(l),
          t.hasParking,
          () => setState(() => t.hasParking = !t.hasParking),
        ),
        (
          _Strings.walkways(l),
          t.hasPaths,
          () => setState(() => t.hasPaths = !t.hasPaths),
        ),
        (
          _Strings.landscapeDesign(l),
          t.hasLandscape,
          () => setState(() => t.hasLandscape = !t.hasLandscape),
        ),
        (
          _Strings.pool(l),
          t.hasPool,
          () => setState(() => t.hasPool = !t.hasPool),
        ),
        (
          _Strings.territoryLighting(l),
          t.hasLighting,
          () => setState(() => t.hasLighting = !t.hasLighting),
        ),
      ]),
      if (t.hasParking)
        WizardField(
          label: _Strings.parkingSpacesLabel(l),
          controller: _parkingCount,
          placeholder: '4',
          numericOnly: true,
        ),
    ]);
  }

  // ── Step 9: Muddatlar va qo'shimcha talablar ─────────────────────────
  Widget _buildStep9(Locale l) {
    return _scrollableStep([
      WizardSectionTitle(text: _Strings.timelines(l)),
      Row(
        children: [
          Expanded(
            child: WizardField(
              label: _Strings.sketchProjectLabel(l),
              controller: _sketchDays,
              placeholder: '30',
              suffix: _Strings.unitDays(l),
              numericOnly: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: WizardField(
              label: _Strings.workingProjectLabel(l),
              controller: _workingDays,
              placeholder: '60',
              suffix: _Strings.unitDays(l),
              numericOnly: true,
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      WizardSectionTitle(text: _Strings.additionalRequirements(l)),
      WizardField(
        label: _Strings.notesLabel(l),
        controller: _notes,
        placeholder: _Strings.notesPlaceholder(l),
        maxLines: 5,
      ),
    ]);
  }

  // ── Preview / Tekshirish ─────────────────────────────────────────────
  // Yuborishdan oldin to'ldirilgan ma'lumotlarning umumiy ko'rinishi. Har
  // bo'lim qalamcha ("✎") orqali to'g'ridan-to'g'ri tahrirga ochiladi va
  // saqlangach shu yerga qaytadi (foydalanuvchi qaytadan o'tib chiqmaydi).
  Widget _buildPreview(Locale l) {
    final d = _draft;
    final styleOpts = _catalog('arxitektura.style');
    final facadeOpts = _catalog('arxitektura.facade_material');

    String c(String? v, String Function(String) f) =>
        (v == null || v.isEmpty) ? '' : f(v);

    // Step 0 — Buyurtmachi
    final customer = <(String, String)>[
      (_Strings.customerNameLabel(l), d.customerName.trim()),
      if (d.tin.trim().isNotEmpty) (_Strings.tinLabel(l), d.tin.trim()),
      (_Strings.phoneLabel(l), d.phone.trim()),
      if (d.email.trim().isNotEmpty) ('E-mail', d.email.trim()),
    ];

    // Step 1 — Obyekt va manzil
    final object = <(String, String)>[
      if (d.objectName.trim().isNotEmpty)
        (_Strings.objectNameLabel(l), d.objectName.trim()),
      if (d.address.trim().isNotEmpty)
        (_Strings.addressLabel(l), d.address.trim()),
      if (d.cadastreNumber.trim().isNotEmpty)
        (_Strings.cadastreNumberLabel(l), d.cadastreNumber.trim()),
      if (d.landAreaSqm != null)
        (
          _Strings.landAreaLabel(l),
          '${_trimNum(d.landAreaSqm!)} ${_Strings.unitSqm(l)}',
        ),
      if (d.landUsePurpose.trim().isNotEmpty)
        (
          _Strings.landUsePurposeLabel(l),
          _landUseDisplay(d.landUsePurpose.trim(), l),
        ),
    ];

    // Step 2 — Loyiha
    final project = <(String, String)>[
      if (d.objectType != null)
        (_Strings.objectTypeLabel(l), _objectTypeLabel(d.objectType!, l)),
      (
        _Strings.constructionTypeLabel(l),
        d.constructionType == ConstructionType.yangi
            ? _Strings.constructionNew(l)
            : _Strings.constructionReconstruction(l),
      ),
      if (d.floors != null) (_Strings.floorsCountLabel(l), '${d.floors}'),
      if (d.maxHeightM != null)
        (
          _Strings.maxHeightLabel(l),
          '${_trimNum(d.maxHeightM!)} ${_Strings.unitM(l)}',
        ),
      if (d.constructionYear != null)
        (_Strings.constructionYearLabel(l), '${d.constructionYear}'),
      if (d.totalAreaSqm != null)
        (
          _Strings.totalAreaLabel(l),
          '${_trimNum(d.totalAreaSqm!)} ${_Strings.unitSqm(l)}',
        ),
      if (d.buildingAreaSqm != null)
        (
          _Strings.buildingAreaLabel(l),
          '${_trimNum(d.buildingAreaSqm!)} ${_Strings.unitSqm(l)}',
        ),
    ];
    final projectChips = <String>[
      if (d.hasBasement) _Strings.hasBasement(l),
      if (d.hasMansard) _Strings.hasMansard(l),
      if (d.hasUndergroundParking) _Strings.hasUndergroundParking(l),
    ];

    // Step 3 — Xonalar
    final roomChips = [
      for (final r in d.rooms)
        '${r.kind == RoomKind.other ? (r.name?.trim().isNotEmpty ?? false ? r.name!.trim() : r.kind.label(l)) : r.kind.label(l)}'
            ' ×${r.count}${r.area != null ? ' · ${_trimNum(r.area!)} ${_Strings.unitSqm(l)}' : ''}',
    ];

    // Step 4 — Arxitektura yechimlari
    final arch = <(String, String)>[
      if (d.architecture.style != null)
        (
          _Strings.styleLabel(l),
          _catalogLabel(styleOpts, d.architecture.style, l),
        ),
      if (d.architecture.facadeMaterial != null)
        (
          _Strings.facadeMaterialLabel(l),
          _catalogLabel(facadeOpts, d.architecture.facadeMaterial, l),
        ),
      if ((d.architecture.colors ?? '').trim().isNotEmpty)
        (_Strings.colorsLabel(l), d.architecture.colors!.trim()),
    ];
    final archChips = <String>[
      if (d.architecture.has3dVisualization) _Strings.need3dVisualization(l),
    ];

    // Step 5 — Konstruktiv
    final constructive = <(String, String)>[
      if (d.constructive.scheme != null)
        (
          _Strings.constructiveSchemeLabel(l),
          c(
            d.constructive.scheme,
            (s) => switch (s) {
              'karkas' => _Strings.schemeFrame(l),
              'monolit' => _Strings.schemeMonolith(l),
              'gisht' => _Strings.materialBrick(l),
              'aralash' => _Strings.schemeMixed(l),
              'metall' => _Strings.materialMetal(l),
              _ => s,
            },
          ),
        ),
      if (d.constructive.foundation != null)
        (
          _Strings.foundationLabel(l),
          c(
            d.constructive.foundation,
            (s) => switch (s) {
              'ustun' => _Strings.foundationColumn(l),
              'lenta' => _Strings.foundationStrip(l),
              'plita' => _Strings.foundationSlab(l),
              'svay' => _Strings.foundationPile(l),
              _ => s,
            },
          ),
        ),
      if (d.constructive.walls != null)
        (
          _Strings.wallMaterialLabel(l),
          c(
            d.constructive.walls,
            (s) => switch (s) {
              'gisht' => _Strings.materialBrick(l),
              'gazoblok' => _Strings.materialAerocrete(l),
              'beton' => _Strings.materialConcrete(l),
              'sendvich_panel' => _Strings.materialSandwichPanel(l),
              _ => s,
            },
          ),
        ),
      if (d.constructive.ceiling != null)
        (
          _Strings.ceilingLabel(l),
          c(
            d.constructive.ceiling,
            (s) => switch (s) {
              'temir_beton' => _Strings.ceilingReinforcedConcrete(l),
              'yogoch' => _Strings.materialWood(l),
              'metall' => _Strings.materialMetal(l),
              _ => s,
            },
          ),
        ),
      if (d.constructive.roofType != null)
        (
          _Strings.roofTypeLabel(l),
          d.constructive.roofType == 'yassi'
              ? _Strings.roofFlat(l)
              : _Strings.roofPitched(l),
        ),
      if ((d.constructive.roofMaterial ?? '').trim().isNotEmpty)
        (_Strings.roofMaterialLabel(l), d.constructive.roofMaterial!.trim()),
    ];

    // Step 6 — Muhandislik
    final eng = <(String, String)>[
      if (d.engineering.waterSource != null)
        (
          _Strings.waterSourceLabel(l),
          d.engineering.waterSource == 'markaziy'
              ? _Strings.central(l)
              : _Strings.well(l),
        ),
      if (d.engineering.sewage != null)
        (
          _Strings.sewageLabel(l),
          d.engineering.sewage == 'markaziy'
              ? _Strings.central(l)
              : _Strings.septic(l),
        ),
      if (d.engineering.heating != null)
        (
          _Strings.heatingLabel(l),
          c(
            d.engineering.heating,
            (s) => switch (s) {
              'gaz' => _Strings.heatingGas(l),
              'elektr' => _Strings.heatingElectric(l),
              'qozonxona' => _Strings.heatingBoiler(l),
              _ => s,
            },
          ),
        ),
      if (d.engineering.ventilation != null)
        (
          _Strings.ventilationLabel(l),
          d.engineering.ventilation == 'tabiiy'
              ? _Strings.ventilationNatural(l)
              : _Strings.ventilationMechanical(l),
        ),
      if (d.engineering.airConditioning != null)
        (
          _Strings.airConditioningLabel(l),
          d.engineering.airConditioning!.toUpperCase(),
        ),
    ];
    final engChips = <String>[
      if (d.engineering.hasGenerator) _Strings.backupGenerator(l),
      if (d.engineering.hasFireSystem) _Strings.fireSafetySystem(l),
      if (d.engineering.hasAlarm) _Strings.alarmSystem(l),
      if (d.engineering.hasVideoSurveillance) _Strings.videoSurveillance(l),
      if (d.engineering.hasSolarPanels) _Strings.solarPanels(l),
    ];

    // Step 7 — Hudud
    final territoryChips = <String>[
      if (d.territory.hasParking)
        '${_Strings.parking(l)}${d.territory.parkingCount != null ? ' ×${d.territory.parkingCount}' : ''}',
      if (d.territory.hasPaths) _Strings.walkways(l),
      if (d.territory.hasLandscape) _Strings.landscapeDesign(l),
      if (d.territory.hasPool) _Strings.pool(l),
      if (d.territory.hasLighting) _Strings.territoryLighting(l),
    ];

    // Step 8 — Muddatlar va izoh
    final timeline = <(String, String)>[
      if (d.timeline.sketchDays != null)
        (
          _Strings.sketchProjectLabel(l),
          '${d.timeline.sketchDays} ${_Strings.unitDays(l)}',
        ),
      if (d.timeline.workingDays != null)
        (
          _Strings.workingProjectLabel(l),
          '${d.timeline.workingDays} ${_Strings.unitDays(l)}',
        ),
      if (d.notes.trim().isNotEmpty) (_Strings.notesLabel(l), d.notes.trim()),
    ];

    final missingRequired = !d.canSubmit;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        Text(
          _Strings.reviewIntro(l),
          style: TextStyle(
            fontFamily: 'MTSText',
            fontSize: 13,
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF9BA1A6)
                : const Color(0xFF6C7278),
          ),
        ),
        const SizedBox(height: 14),
        WizardReviewSection(
          title: _Strings.customerDetails(l),
          onEdit: () => _editStep(0),
          rows: customer,
          warning:
              (d.customerName.trim().length < 2 || d.phone.trim().length < 5)
              ? _Strings.fillRequired(l)
              : null,
        ),
        WizardReviewSection(
          title: _Strings.objectAndAddress(l),
          onEdit: () => _editStep(1),
          rows: object,
        ),
        WizardReviewSection(
          title: _Strings.projectGeneralInfo(l),
          onEdit: () => _editStep(2),
          rows: project,
          chips: projectChips,
          warning: d.objectType == null ? _Strings.fillRequired(l) : null,
        ),
        WizardReviewSection(
          title: _Strings.roomsComposition(l),
          onEdit: () => _editStep(3),
          chips: roomChips,
        ),
        WizardReviewSection(
          title: _Strings.architectureAndDesign(l),
          onEdit: () => _editStep(4),
          rows: arch,
          chips: archChips,
        ),
        WizardReviewSection(
          title: _Strings.constructiveSolutions(l),
          onEdit: () => _editStep(5),
          rows: constructive,
        ),
        WizardReviewSection(
          title: _Strings.engineeringSystems(l),
          onEdit: () => _editStep(6),
          rows: eng,
          chips: engChips,
        ),
        WizardReviewSection(
          title: _Strings.territoryPlanning(l),
          onEdit: () => _editStep(7),
          chips: territoryChips,
        ),
        WizardReviewSection(
          title: _Strings.timelines(l),
          onEdit: () => _editStep(8),
          rows: timeline,
        ),
        if (missingRequired) ...[
          const SizedBox(height: 4),
          Text(
            _Strings.fillRequired(l),
            style: const TextStyle(
              fontFamily: 'MTSText',
              fontSize: 12.5,
              color: Color(0xFFE0492A),
            ),
          ),
        ],
      ],
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────
  static double? _parseDouble(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t.replaceAll(',', '.'));
  }

  static int? _parseInt(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  // Land use kodi -> ko'rsatiladigan label (kod emas). Eski/erkin matn o'zgarmas.
  static String _landUseDisplay(String codeOrText, Locale l) =>
      switch (codeOrText) {
        'turar_joy' => _Strings.landUseResidential(l),
        'ishlab_chiqarish' => _Strings.landUseProduction(l),
        'savdo' => _Strings.landUseCommercial(l),
        'aralash' => _Strings.landUseMixed(l),
        _ => codeOrText,
      };

  static String _objectTypeLabel(ArchObjectType t, Locale l) {
    final ru = l.languageCode == 'ru';
    final en = l.languageCode == 'en';
    return switch (t) {
      ArchObjectType.yakkaSmall =>
        ru
            ? 'Частный дом <500 m²'
            : en
            ? 'Single house <500 m²'
            : 'Yakka uy <500 m²',
      ArchObjectType.yakkaLarge =>
        ru
            ? 'Частный дом >500 m²'
            : en
            ? 'Single house >500 m²'
            : 'Yakka uy >500 m²',
      ArchObjectType.kopQavatli =>
        ru
            ? 'Многоэтажное жильё'
            : en
            ? 'Multi-storey residential'
            : 'Ko\'p qavatli turar-joy',
      ArchObjectType.ofis =>
        ru
            ? 'Офис'
            : en
            ? 'Office'
            : 'Ofis',
      ArchObjectType.savdoMarkazi =>
        ru
            ? 'Торговый центр'
            : en
            ? 'Shopping mall'
            : 'Savdo markazi',
      ArchObjectType.mehmonxona =>
        ru
            ? 'Гостиница'
            : en
            ? 'Hotel'
            : 'Mehmonxona',
      ArchObjectType.sanoat =>
        ru
            ? 'Промышленный'
            : en
            ? 'Industrial'
            : 'Sanoat',
      ArchObjectType.omborxona =>
        ru
            ? 'Склад'
            : en
            ? 'Warehouse'
            : 'Omborxona',
      ArchObjectType.boshqa =>
        ru
            ? 'Другое'
            : en
            ? 'Other'
            : 'Boshqa',
    };
  }
}

// Bo'lim ixtiyoriy ekanini bildiruvchi yumshoq izoh (majburiy emas — to'ldirsa
// bo'ladi, bo'lmasa davom etish mumkin).
class _OptionalStepHint extends StatelessWidget {
  const _OptionalStepHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);
    return Row(
      children: [
        Icon(Icons.info_outline_rounded, size: 15, color: muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 12.5,
              color: muted,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Localized UI strings ────────────────────────────────────────────────
class _Strings {
  const _Strings._();

  // Buttons / common
  static String continueLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Продолжить',
    'en' => 'Continue',
    _ => 'Davom etish',
  };

  static String submitting(Locale l) => switch (l.languageCode) {
    'ru' => 'Отправка…',
    'en' => 'Submitting…',
    _ => 'Yuborilmoqda…',
  };

  static String saveChanges(Locale l) => switch (l.languageCode) {
    'ru' => 'Сохранить',
    'en' => 'Save',
    _ => 'Saqlash',
  };

  static String prefilledHint(Locale l) => switch (l.languageCode) {
    'ru' => 'Заполнено по последней заявке — можно изменить',
    'en' => 'Filled from your last order — you can edit it',
    _ => 'Oxirgi arizangizdan to\'ldirildi — o\'zgartirsangiz bo\'ladi',
  };

  static String crumbReview(Locale l) => switch (l.languageCode) {
    'ru' => 'Проверка и отправка',
    'en' => 'Review and submit',
    _ => 'Tekshirish va yuborish',
  };

  static String reviewIntro(Locale l) => switch (l.languageCode) {
    'ru' =>
      'Проверьте данные перед отправкой. Нажмите ✎, чтобы изменить раздел.',
    'en' => 'Check the details before submitting. Tap ✎ to edit a section.',
    _ =>
      'Yuborishdan oldin ma\'lumotlarni tekshiring. Bo\'limni o\'zgartirish uchun ✎ ni bosing.',
  };

  static String submit(Locale l) => switch (l.languageCode) {
    'ru' => 'Отправить',
    'en' => 'Submit',
    _ => 'Yuborish',
  };

  static String archTz(Locale l) => switch (l.languageCode) {
    'ru' => 'Архитектура',
    'en' => 'Architecture',
    _ => 'Arxitektura',
  };

  static String aiValuation(Locale l) => switch (l.languageCode) {
    'ru' => 'AI оценка',
    'en' => 'AI valuation',
    _ => 'AI Baholash',
  };

  // Units
  static String unitSqm(Locale l) => switch (l.languageCode) {
    'ru' => 'м²',
    _ => 'm²',
  };

  static String unitM(Locale l) => switch (l.languageCode) {
    'ru' => 'м',
    _ => 'm',
  };

  static String unitDays(Locale l) => switch (l.languageCode) {
    'ru' => 'дней',
    'en' => 'days',
    _ => 'kun',
  };

  // Step crumbs
  static String crumbCustomer(Locale l) => switch (l.languageCode) {
    'ru' => 'Заказчик',
    'en' => 'Customer',
    _ => 'Buyurtmachi',
  };

  static String crumbObject(Locale l) => switch (l.languageCode) {
    'ru' => 'Объект и адрес',
    'en' => 'Object and address',
    _ => 'Obyekt va manzil',
  };

  static String crumbProject(Locale l) => switch (l.languageCode) {
    'ru' => 'О проекте',
    'en' => 'About the project',
    _ => 'Loyiha haqida',
  };

  static String crumbRooms(Locale l) => switch (l.languageCode) {
    'ru' => 'Состав комнат',
    'en' => 'Room composition',
    _ => 'Xonalar tarkibi',
  };

  static String crumbArchitecture(Locale l) => switch (l.languageCode) {
    'ru' => 'Архитектурные решения',
    'en' => 'Architectural solutions',
    _ => 'Arxitektura yechimlari',
  };

  static String crumbConstructive(Locale l) => switch (l.languageCode) {
    'ru' => 'Конструктивные решения',
    'en' => 'Structural solutions',
    _ => 'Konstruktiv yechimlar',
  };

  static String crumbEngineering(Locale l) => switch (l.languageCode) {
    'ru' => 'Инженерные системы',
    'en' => 'Engineering systems',
    _ => 'Muhandislik tizimlari',
  };

  static String crumbTerritory(Locale l) => switch (l.languageCode) {
    'ru' => 'Планировка территории',
    'en' => 'Territory planning',
    _ => 'Hudud rejalashtirish',
  };

  static String crumbTimeline(Locale l) => switch (l.languageCode) {
    'ru' => 'Сроки и комментарий',
    'en' => 'Timeline and notes',
    _ => 'Muddatlar va izoh',
  };

  // Submit / validation messages
  static String fillRequired(Locale l) => switch (l.languageCode) {
    'ru' => 'Заполните обязательные поля',
    'en' => 'Fill in the required fields',
    _ => 'Majburiy maydonlarni to\'ldiring',
  };

  static String aiCallbackMissing(Locale l) => switch (l.languageCode) {
    'ru' => 'Callback для AI оценки не подключён',
    'en' => 'AI valuation callback is not connected',
    _ => 'AI baholash uchun callback bog\'lanmagan',
  };

  static String networkError(Locale l) => switch (l.languageCode) {
    'ru' => 'Ошибка сети',
    'en' => 'Network error',
    _ => 'Tarmoq xatosi',
  };

  // Step 1 — Customer
  static String customerDetails(Locale l) => switch (l.languageCode) {
    'ru' => 'Реквизиты заказчика',
    'en' => 'Customer details',
    _ => 'Buyurtmachi rekvizitlari',
  };

  static String customerNameLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Ф.И.О или название компании',
    'en' => 'Full name or company name',
    _ => 'F.I.SH yoki kompaniya nomi',
  };

  static String tinLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'ИНН',
    'en' => 'TIN',
    _ => 'STIR',
  };

  static String tinError(Locale l) => switch (l.languageCode) {
    'ru' => '9 (СТИР) или 14 (ИНН) цифр',
    'en' => 'Must be 9 (TIN) or 14 (PINFL) digits',
    _ => '9 (STIR) yoki 14 (INN) raqamdan iborat bo\'lsin',
  };

  static String phoneLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Телефон',
    'en' => 'Phone',
    _ => 'Telefon',
  };

  static String phoneError(Locale l) => switch (l.languageCode) {
    'ru' => 'Введите корректный номер, напр. +998 90 123 45 67',
    'en' => 'Enter a valid number, e.g. +998 90 123 45 67',
    _ => 'To\'g\'ri raqam kiriting, masalan +998 90 123 45 67',
  };

  static String emailError(Locale l) => switch (l.languageCode) {
    'ru' => 'Введите корректный e-mail',
    'en' => 'Enter a valid e-mail',
    _ => 'To\'g\'ri e-mail kiriting',
  };

  // Step 2 — Object and address
  static String objectAndAddress(Locale l) => switch (l.languageCode) {
    'ru' => 'Объект и адрес',
    'en' => 'Object and address',
    _ => 'Obyekt va manzil',
  };

  static String objectNameLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Название объекта',
    'en' => 'Object name',
    _ => 'Obyekt nomi',
  };

  static String objectNamePlaceholder(Locale l) => switch (l.languageCode) {
    'ru' => 'Мой дом',
    'en' => 'My house',
    _ => 'Mening uyim',
  };

  static String addressLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Адрес',
    'en' => 'Address',
    _ => 'Manzil',
  };

  static String cadastreNumberLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Кадастровый номер',
    'en' => 'Cadastre number',
    _ => 'Kadastr raqami',
  };

  static String landAreaLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Площадь участка',
    'en' => 'Land area',
    _ => 'Yer maydoni',
  };

  static String landUsePurposeLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Целевое назначение земли',
    'en' => 'Land use purpose',
    _ => 'Yerning maqsadli foydalanishi',
  };

  static String landUsePurposePlaceholder(Locale l) => switch (l.languageCode) {
    'ru' => 'Например: садоводство',
    'en' => 'E.g. gardening',
    _ => 'Masalan: bog\'dorchilik',
  };

  static String landUseResidential(Locale l) => switch (l.languageCode) {
    'ru' => 'Жилая',
    'en' => 'Residential',
    _ => 'Turar joy',
  };

  static String landUseProduction(Locale l) => switch (l.languageCode) {
    'ru' => 'Производственная',
    'en' => 'Production',
    _ => 'Ishlab chiqarish',
  };

  static String landUseCommercial(Locale l) => switch (l.languageCode) {
    'ru' => 'Торговая',
    'en' => 'Commercial',
    _ => 'Savdo',
  };

  static String landUseMixed(Locale l) => switch (l.languageCode) {
    'ru' => 'Смешанная',
    'en' => 'Mixed',
    _ => 'Aralash',
  };

  static String landUseOther(Locale l) => switch (l.languageCode) {
    'ru' => 'Другое',
    'en' => 'Other',
    _ => 'Boshqa',
  };

  static String designOptionalHint(Locale l) => switch (l.languageCode) {
    'ru' => 'Необязательно — заполните, если есть пожелания',
    'en' => 'Optional — fill in if you have preferences',
    _ => 'Ixtiyoriy — afzalliklaringiz bo\'lsa to\'ldiring',
  };

  static String technicalOptionalHint(Locale l) => switch (l.languageCode) {
    'ru' => 'Необязательно — заполните, если знаете (иначе решит архитектор)',
    'en' => 'Optional — fill in if you know (the architect decides otherwise)',
    _ =>
      'Ixtiyoriy — agar bilsangiz to\'ldiring (aks holda arxitektor hal qiladi)',
  };

  static String extraSystemsLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Дополнительные системы',
    'en' => 'Additional systems',
    _ => 'Qo\'shimcha tizimlar',
  };

  static String territoryFeaturesLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Что разместить на участке',
    'en' => 'What to include on the plot',
    _ => 'Hududda nimalar bo\'lsin',
  };

  static String changeLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Изменить',
    'en' => 'Change',
    _ => 'O\'zgartirish',
  };

  static String addObjectNameOptional(Locale l) => switch (l.languageCode) {
    'ru' => 'Добавить название объекта (необязательно)',
    'en' => 'Add object name (optional)',
    _ => 'Obyekt nomi qo\'shish (ixtiyoriy)',
  };

  // Step 3 — Project
  static String projectGeneralInfo(Locale l) => switch (l.languageCode) {
    'ru' => 'Общие сведения о проекте',
    'en' => 'General project information',
    _ => 'Loyiha umumiy ma\'lumotlari',
  };

  static String objectTypeLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Тип объекта',
    'en' => 'Object type',
    _ => 'Obyekt turi',
  };

  static String objectSubtypeLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Другое (какого типа)',
    'en' => 'Other (which type)',
    _ => 'Boshqa (qaysi turdagi)',
  };

  static String objectSubtypePlaceholder(Locale l) => switch (l.languageCode) {
    'ru' => 'Например: многофункциональный центр',
    'en' => 'For example: multi-purpose center',
    _ => 'Masalan: ko\'p funksiyali markaz',
  };

  static String constructionTypeLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Тип строительства',
    'en' => 'Construction type',
    _ => 'Qurilish turi',
  };

  static String constructionNew(Locale l) => switch (l.languageCode) {
    'ru' => 'Новое',
    'en' => 'New',
    _ => 'Yangi',
  };

  static String constructionReconstruction(Locale l) =>
      switch (l.languageCode) {
        'ru' => 'Реконструкция',
        'en' => 'Reconstruction',
        _ => 'Rekonstruksiya',
      };

  static String floorsCountLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Этажность',
    'en' => 'Number of floors',
    _ => 'Qavatlar soni',
  };

  static String maxHeightLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Макс. высота',
    'en' => 'Max. height',
    _ => 'Maks. balandlik',
  };

  static String constructionYearLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Год постройки',
    'en' => 'Construction year',
    _ => 'Qurilish yili',
  };

  static String totalAreaLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Общая площадь',
    'en' => 'Total area',
    _ => 'Umumiy maydon',
  };

  static String buildingAreaLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Площадь застройки',
    'en' => 'Building area',
    _ => 'Qurilish maydoni',
  };

  static String hasBasement(Locale l) => switch (l.languageCode) {
    'ru' => 'С подвалом',
    'en' => 'With basement',
    _ => 'Podval bo\'lsin',
  };

  static String hasMansard(Locale l) => switch (l.languageCode) {
    'ru' => 'С мансардой',
    'en' => 'With mansard',
    _ => 'Mansarda bo\'lsin',
  };

  static String hasUndergroundParking(Locale l) => switch (l.languageCode) {
    'ru' => 'Подземный паркинг',
    'en' => 'Underground parking',
    _ => 'Yer osti avtoturargohi',
  };

  // Step 4 — Rooms
  static String roomsComposition(Locale l) => switch (l.languageCode) {
    'ru' => 'Состав комнат',
    'en' => 'Room composition',
    _ => 'Xonalar tarkibi',
  };

  // Step 5 — Architecture and design
  static String architectureAndDesign(Locale l) => switch (l.languageCode) {
    'ru' => 'Архитектура и дизайн',
    'en' => 'Architecture and design',
    _ => 'Arxitektura va dizayn',
  };

  static String styleLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Стиль',
    'en' => 'Style',
    _ => 'Uslub',
  };

  static String facadeMaterialLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Материал фасада',
    'en' => 'Facade material',
    _ => 'Fasad materiali',
  };

  static String colorsLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Цвета',
    'en' => 'Colors',
    _ => 'Ranglar',
  };

  static String need3dVisualization(Locale l) => switch (l.languageCode) {
    'ru' => 'Нужна 3D визуализация',
    'en' => '3D visualization needed',
    _ => '3D vizualizatsiya kerak',
  };

  // Step 6 — Constructive solutions
  static String constructiveSolutions(Locale l) => switch (l.languageCode) {
    'ru' => 'Конструктивные решения',
    'en' => 'Structural solutions',
    _ => 'Konstruktiv yechimlar',
  };

  static String constructiveSchemeLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Конструктивная схема',
    'en' => 'Structural scheme',
    _ => 'Konstruktiv sxema',
  };

  static String schemeFrame(Locale l) => switch (l.languageCode) {
    'ru' => 'Каркас',
    'en' => 'Frame',
    _ => 'Karkas',
  };

  static String schemeMonolith(Locale l) => switch (l.languageCode) {
    'ru' => 'Монолит',
    'en' => 'Monolith',
    _ => 'Monolit',
  };

  static String schemeMixed(Locale l) => switch (l.languageCode) {
    'ru' => 'Смешанная',
    'en' => 'Mixed',
    _ => 'Aralash',
  };

  static String foundationLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Фундамент',
    'en' => 'Foundation',
    _ => 'Poydevor',
  };

  static String foundationColumn(Locale l) => switch (l.languageCode) {
    'ru' => 'Столбчатый',
    'en' => 'Column',
    _ => 'Ustun',
  };

  static String foundationStrip(Locale l) => switch (l.languageCode) {
    'ru' => 'Ленточный',
    'en' => 'Strip',
    _ => 'Lenta',
  };

  static String foundationSlab(Locale l) => switch (l.languageCode) {
    'ru' => 'Плитный',
    'en' => 'Slab',
    _ => 'Plita',
  };

  static String foundationPile(Locale l) => switch (l.languageCode) {
    'ru' => 'Свайный',
    'en' => 'Pile',
    _ => 'Svay',
  };

  static String wallMaterialLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Материал стен',
    'en' => 'Wall material',
    _ => 'Devor materiali',
  };

  static String ceilingLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Перекрытия',
    'en' => 'Floor slabs',
    _ => 'Qavat yopma',
  };

  static String ceilingReinforcedConcrete(Locale l) => switch (l.languageCode) {
    'ru' => 'Железобетон',
    'en' => 'Reinforced concrete',
    _ => 'Temir-beton',
  };

  static String roofTypeLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Тип крыши',
    'en' => 'Roof type',
    _ => 'Tom turi',
  };

  static String roofFlat(Locale l) => switch (l.languageCode) {
    'ru' => 'Плоская',
    'en' => 'Flat',
    _ => 'Yassi',
  };

  static String roofPitched(Locale l) => switch (l.languageCode) {
    'ru' => 'Скатная',
    'en' => 'Pitched',
    _ => 'Qiya',
  };

  static String roofMaterialLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Материал кровли',
    'en' => 'Roofing material',
    _ => 'Tom qoplama materiali',
  };

  static String roofMaterialPlaceholder(Locale l) => switch (l.languageCode) {
    'ru' => 'Металлочерепица, профнастил…',
    'en' => 'Metal tiles, corrugated sheet…',
    _ => 'Metall cherepitsa, profnastil…',
  };

  // Shared materials
  static String materialBrick(Locale l) => switch (l.languageCode) {
    'ru' => 'Кирпич',
    'en' => 'Brick',
    _ => 'G\'isht',
  };

  static String materialMetal(Locale l) => switch (l.languageCode) {
    'ru' => 'Металл',
    'en' => 'Metal',
    _ => 'Metall',
  };

  static String materialAerocrete(Locale l) => switch (l.languageCode) {
    'ru' => 'Газоблок',
    'en' => 'Aerated concrete',
    _ => 'Gazoblok',
  };

  static String materialConcrete(Locale l) => switch (l.languageCode) {
    'ru' => 'Бетон',
    'en' => 'Concrete',
    _ => 'Beton',
  };

  static String materialSandwichPanel(Locale l) => switch (l.languageCode) {
    'ru' => 'Сэндвич-панель',
    'en' => 'Sandwich panel',
    _ => 'Sendvich panel',
  };

  static String materialWood(Locale l) => switch (l.languageCode) {
    'ru' => 'Дерево',
    'en' => 'Wood',
    _ => 'Yog\'och',
  };

  // Step 7 — Engineering systems
  static String engineeringSystems(Locale l) => switch (l.languageCode) {
    'ru' => 'Инженерные системы',
    'en' => 'Engineering systems',
    _ => 'Muhandislik tizimlari',
  };

  static String backupGenerator(Locale l) => switch (l.languageCode) {
    'ru' => 'Резервный генератор',
    'en' => 'Backup generator',
    _ => 'Zaxira generator',
  };

  static String waterSourceLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Источник воды',
    'en' => 'Water source',
    _ => 'Suv manbai',
  };

  static String central(Locale l) => switch (l.languageCode) {
    'ru' => 'Центральный',
    'en' => 'Central',
    _ => 'Markaziy',
  };

  static String well(Locale l) => switch (l.languageCode) {
    'ru' => 'Скважина',
    'en' => 'Well',
    _ => 'Quduq',
  };

  static String sewageLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Канализация',
    'en' => 'Sewerage',
    _ => 'Kanalizatsiya',
  };

  static String septic(Locale l) => switch (l.languageCode) {
    'ru' => 'Автономная (септик)',
    'en' => 'Autonomous (septic)',
    _ => 'Avtonom (septik)',
  };

  static String heatingLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Отопление',
    'en' => 'Heating',
    _ => 'Isitish',
  };

  static String heatingGas(Locale l) => switch (l.languageCode) {
    'ru' => 'Газ',
    'en' => 'Gas',
    _ => 'Gaz',
  };

  static String heatingElectric(Locale l) => switch (l.languageCode) {
    'ru' => 'Электричество',
    'en' => 'Electric',
    _ => 'Elektr',
  };

  static String heatingBoiler(Locale l) => switch (l.languageCode) {
    'ru' => 'Котельная',
    'en' => 'Boiler room',
    _ => 'Qozonxona',
  };

  static String ventilationLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Вентиляция',
    'en' => 'Ventilation',
    _ => 'Ventilyatsiya',
  };

  static String ventilationNatural(Locale l) => switch (l.languageCode) {
    'ru' => 'Естественная',
    'en' => 'Natural',
    _ => 'Tabiiy',
  };

  static String ventilationMechanical(Locale l) => switch (l.languageCode) {
    'ru' => 'Механическая',
    'en' => 'Mechanical',
    _ => 'Mexanik',
  };

  static String airConditioningLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Кондиционирование',
    'en' => 'Air conditioning',
    _ => 'Konditsioner',
  };

  static String fireSafetySystem(Locale l) => switch (l.languageCode) {
    'ru' => 'Система пожарной безопасности',
    'en' => 'Fire safety system',
    _ => 'Yong\'in xavfsizligi tizimi',
  };

  static String alarmSystem(Locale l) => switch (l.languageCode) {
    'ru' => 'Сигнализация',
    'en' => 'Alarm system',
    _ => 'Signalizatsiya',
  };

  static String videoSurveillance(Locale l) => switch (l.languageCode) {
    'ru' => 'Видеонаблюдение',
    'en' => 'Video surveillance',
    _ => 'Videokuzatuv',
  };

  static String solarPanels(Locale l) => switch (l.languageCode) {
    'ru' => 'Солнечные панели',
    'en' => 'Solar panels',
    _ => 'Quyosh panellari',
  };

  // Step 8 — Territory
  static String territoryPlanning(Locale l) => switch (l.languageCode) {
    'ru' => 'Планировка территории',
    'en' => 'Territory planning',
    _ => 'Hududni rejalashtirish',
  };

  static String parking(Locale l) => switch (l.languageCode) {
    'ru' => 'Парковка',
    'en' => 'Parking',
    _ => 'Avtoturargoh',
  };

  static String parkingSpacesLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Кол-во парковочных мест',
    'en' => 'Number of parking spaces',
    _ => 'Parking joylar soni',
  };

  static String walkways(Locale l) => switch (l.languageCode) {
    'ru' => 'Дорожки',
    'en' => 'Walkways',
    _ => 'Yo\'laklar',
  };

  static String landscapeDesign(Locale l) => switch (l.languageCode) {
    'ru' => 'Ландшафтный дизайн',
    'en' => 'Landscape design',
    _ => 'Landshaft dizayni',
  };

  static String pool(Locale l) => switch (l.languageCode) {
    'ru' => 'Бассейн',
    'en' => 'Pool',
    _ => 'Hovuz',
  };

  static String territoryLighting(Locale l) => switch (l.languageCode) {
    'ru' => 'Освещение территории',
    'en' => 'Territory lighting',
    _ => 'Hudud yoritilishi',
  };

  // Step 9 — Timeline
  static String timelines(Locale l) => switch (l.languageCode) {
    'ru' => 'Сроки',
    'en' => 'Timeline',
    _ => 'Muddatlar',
  };

  static String sketchProjectLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Эскизный проект',
    'en' => 'Sketch design',
    _ => 'Eskiz loyiha',
  };

  static String workingProjectLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Рабочий проект',
    'en' => 'Working design',
    _ => 'Ishchi loyiha',
  };

  static String additionalRequirements(Locale l) => switch (l.languageCode) {
    'ru' => 'Дополнительные требования',
    'en' => 'Additional requirements',
    _ => 'Qo\'shimcha talablar',
  };

  static String notesLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Комментарий',
    'en' => 'Notes',
    _ => 'Izoh',
  };

  static String notesPlaceholder(Locale l) => switch (l.languageCode) {
    'ru' => 'Дополнительные комментарии по проекту…',
    'en' => 'Additional notes about the project…',
    _ => 'Loyihaga doir qo\'shimcha izohlar…',
  };
}
