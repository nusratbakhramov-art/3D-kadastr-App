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

import '../../../../core/i18n/app_translations.dart';
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
      _showError(tr(l, 'services.tz.arx.fill_required'));
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
      _showError(tr(l, 'services.tz.arx.ai_callback_missing'));
      return;
    }

    // Standalone mode (architectureOrder): backend'ga yuborish.
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null) {
      if (mounted) {
        _showError(tr(Localizations.localeOf(context), 'services.tz.arx.sign_in_first'));
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
      _showError('${tr(l, 'services.tz.arx.network_error')}: $e');
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
                            ? tr(l, 'services.tz.arx.submitting')
                            : (_editReturn
                                  ? tr(l, 'services.tz.arx.save_changes')
                                  : (_isPreview
                                        ? (widget.submitLabel ??
                                              _defaultSubmitLabel(l))
                                        : tr(l, 'services.tz.arx.continue_label'))),
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
      0 => '1/9 — ${tr(l, 'services.tz.arx.crumb_customer')}',
      1 => '2/9 — ${tr(l, 'services.tz.arx.crumb_object')}',
      2 => '3/9 — ${tr(l, 'services.tz.arx.crumb_project')}',
      3 => '4/9 — ${tr(l, 'services.tz.arx.crumb_rooms')}',
      4 => '5/9 — ${tr(l, 'services.tz.arx.crumb_architecture')}',
      5 => '6/9 — ${tr(l, 'services.tz.arx.crumb_constructive')}',
      6 => '7/9 — ${tr(l, 'services.tz.arx.crumb_engineering')}',
      7 => '8/9 — ${tr(l, 'services.tz.arx.crumb_territory')}',
      8 => '9/9 — ${tr(l, 'services.tz.arx.crumb_timeline')}',
      _previewIndex => tr(l, 'services.tz.arx.crumb_review'),
      _ => '',
    };
  }

  String _defaultSubmitLabel(Locale l) => switch (widget.mode) {
    WizardMode.aiValuation => tr(l, 'services.tz.arx.ai_valuation'),
    WizardMode.architectureOrder => tr(l, 'services.tz.arx.submit'),
  };

  String _appBarTitle(Locale l) => switch (widget.mode) {
    WizardMode.aiValuation => tr(l, 'services.tz.arx.ai_valuation'),
    WizardMode.architectureOrder => tr(l, 'services.tz.arx.arch_tz'),
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
      WizardSectionTitle(text: tr(l, 'services.tz.arx.customer_details')),
      if (_prefilledFromLast)
        WizardPrefillHint(text: tr(l, 'services.tz.arx.prefilled_hint')),
      WizardField(
        label: tr(l, 'services.tz.arx.customer_name_label'),
        controller: _customerName,
        placeholder: tr(l, 'services.tz.arx.customer_name_hint'),
        required: true,
      ),
      WizardField(
        label: tr(l, 'services.tz.arx.tin_label'),
        controller: _tin,
        placeholder: '300000000',
        numericOnly: true,
        maxLength: 14,
        errorText: _tinValid ? null : tr(l, 'services.tz.arx.tin_error'),
      ),
      WizardField(
        label: tr(l, 'services.tz.arx.phone_label'),
        controller: _phone,
        placeholder: '+998 90 123 45 67',
        keyboardType: TextInputType.phone,
        phoneFormat: true,
        maxLength: 17,
        required: true,
        errorText: _phoneError ? tr(l, 'services.tz.arx.phone_error') : null,
      ),
      WizardField(
        label: tr(l, 'services.tz.arx.email_label'),
        controller: _email,
        placeholder: 'sample@mail.com',
        keyboardType: TextInputType.emailAddress,
        errorText: isValidEmail(_email.text) ? null : tr(l, 'services.tz.arx.email_error'),
      ),
    ]);
  }

  // ── Step 2: Obyekt va manzil ─────────────────────────────────────────
  // Kadastr raqami birinchi — kiritilsa manzilni avtomatik to'ldiradi. Yer
  // maydoni + o'lchov birligi bitta qatorda, maqsadli foydalanish chip orqali,
  // ixtiyoriy "Obyekt nomi" esa pastda yopiq holatda.
  Widget _buildStep2(Locale l) {
    return _scrollableStep([
      WizardSectionTitle(text: tr(l, 'services.tz.arx.object_and_address')),
      // Kadastr raqami — raqam kiritilsa, manzil avtomatik to'ladi.
      CadastreLookupField(
        controller: _cadastreNumber,
        label: tr(l, 'services.tz.arx.cadastre_number_label'),
        onResult: _onCadastreResult,
      ),
      LocationPickerField(
        label: tr(l, 'services.tz.arx.address_label'),
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
                pill('m2', tr(l, 'services.tz.arx.unit_sqm')),
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
          tr(l, 'services.tz.arx.land_area_label'),
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
      ('turar_joy', tr(l, 'services.tz.arx.land_use_residential')),
      ('ishlab_chiqarish', tr(l, 'services.tz.arx.land_use_production')),
      ('savdo', tr(l, 'services.tz.arx.land_use_commercial')),
      ('aralash', tr(l, 'services.tz.arx.land_use_mixed')),
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
          tr(l, 'services.tz.arx.land_use_purpose_label'),
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
            _choiceChip(tr(l, 'services.tz.arx.land_use_other'), isOther, () {
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
            label: tr(l, 'services.tz.arx.land_use_other'),
            controller: _landUsePurpose,
            placeholder: tr(l, 'services.tz.arx.land_use_purpose_placeholder'),
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
        label: tr(l, 'services.tz.arx.object_name_label'),
        controller: _objectName,
        placeholder: tr(l, 'services.tz.arx.object_name_placeholder'),
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
              tr(l, 'services.tz.arx.add_object_name_optional'),
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
      WizardSectionTitle(text: tr(l, 'services.tz.arx.project_general_info')),
      _objectTypePicker(l),
      WizardChipPicker<ConstructionType>(
        label: tr(l, 'services.tz.arx.construction_type_label'),
        options: ConstructionType.values,
        labelOf: (t) => _schemaEnumLabel(
          'construction_type',
          t.apiValue,
          l,
          t == ConstructionType.yangi
              ? tr(l, 'services.tz.arx.construction_new')
              : tr(l, 'services.tz.arx.construction_reconstruction'),
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
              label: tr(l, 'services.tz.arx.floors_count_label'),
              controller: _floors,
              placeholder: '2',
              numericOnly: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: WizardField(
              label: tr(l, 'services.tz.arx.max_height_label'),
              controller: _maxHeight,
              placeholder: '12',
              suffix: tr(l, 'services.tz.arx.unit_m'),
              numericOnly: true,
              allowDecimal: true,
            ),
          ),
        ],
      ),
      if (showYear)
        WizardField(
          label: tr(l, 'services.tz.arx.construction_year_label'),
          controller: _constructionYear,
          placeholder: '2018',
          numericOnly: true,
        ),
      Row(
        children: [
          Expanded(
            child: WizardField(
              label: tr(l, 'services.tz.arx.total_area_label'),
              controller: _totalArea,
              placeholder: '350',
              suffix: tr(l, 'services.tz.arx.unit_sqm'),
              numericOnly: true,
              allowDecimal: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: WizardField(
              label: tr(l, 'services.tz.arx.building_area_label'),
              controller: _buildingArea,
              placeholder: '180',
              suffix: tr(l, 'services.tz.arx.unit_sqm'),
              numericOnly: true,
              allowDecimal: true,
            ),
          ),
        ],
      ),
      WizardSwitchTile(
        label: tr(l, 'services.tz.arx.has_basement'),
        value: _draft.hasBasement,
        onChanged: (v) => setState(() => _draft.hasBasement = v),
      ),
      WizardSwitchTile(
        label: tr(l, 'services.tz.arx.has_mansard'),
        value: _draft.hasMansard,
        onChanged: (v) => setState(() => _draft.hasMansard = v),
      ),
      WizardSwitchTile(
        label: tr(l, 'services.tz.arx.has_underground_parking'),
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
          tr(l, 'services.tz.arx.object_type_label'),
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
          label: tr(l, 'services.tz.arx.object_type_label'),
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
                      tr(l, 'services.tz.arx.change_label'),
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
          label: tr(l, 'services.tz.arx.object_subtype_label'),
          controller: _objectSubtype,
          placeholder: tr(l, 'services.tz.arx.object_subtype_placeholder'),
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
      WizardSectionTitle(text: tr(l, 'services.tz.arx.rooms_composition')),
      RoomsSelector(
        rooms: _draft.rooms,
        locale: l,
        showArea: true,
        subtitle: tr(l, 'services.tz.arx.rooms_subtitle'),
        onChanged: () => setState(() {}),
      ),
    ]);
  }

  // ── Step 5: Arxitektura yechimlari ───────────────────────────────────
  Widget _buildStep5(Locale l) {
    final styleOpts = _catalog('arxitektura.style');
    final facadeOpts = _catalog('arxitektura.facade_material');
    return _scrollableStep([
      WizardSectionTitle(text: tr(l, 'services.tz.arx.architecture_and_design')),
      _OptionalStepHint(text: tr(l, 'services.tz.arx.design_optional_hint')),
      WizardChipPicker<String>(
        label: tr(l, 'services.tz.arx.style_label'),
        options: [for (final o in styleOpts) o.value],
        labelOf: (s) => _catalogLabel(styleOpts, s, l),
        value: _draft.architecture.style,
        onChanged: (v) => setState(() => _draft.architecture.style = v),
      ),
      WizardChipPicker<String>(
        label: tr(l, 'services.tz.arx.facade_material_label'),
        options: [for (final o in facadeOpts) o.value],
        labelOf: (s) => _catalogLabel(facadeOpts, s, l),
        value: _draft.architecture.facadeMaterial,
        onChanged: (v) =>
            setState(() => _draft.architecture.facadeMaterial = v),
      ),
      // 3D vizualizatsiya — narx/ko'lamga ta'sir qiladigan yagona tanlov;
      // rang panelidan past ko'milib qolmasligi uchun yuqorida.
      WizardSwitchTile(
        label: tr(l, 'services.tz.arx.need_3d_visualization'),
        value: _draft.architecture.has3dVisualization,
        onChanged: (v) =>
            setState(() => _draft.architecture.has3dVisualization = v),
      ),
      ColorPaletteField(
        label: tr(l, 'services.tz.arx.colors_label'),
        value: _draft.architecture.colors,
        onChanged: (v) =>
            _draft.architecture.colors = v.trim().isEmpty ? null : v.trim(),
      ),
    ]);
  }

  // ── Step 6: Konstruktiv yechimlar ────────────────────────────────────
  Widget _buildStep6(Locale l) {
    return _scrollableStep([
      WizardSectionTitle(text: tr(l, 'services.tz.arx.constructive_solutions')),
      _OptionalStepHint(text: tr(l, 'services.tz.arx.technical_optional_hint')),
      _schemaChipPicker(
        l: l,
        mapsTo: 'details.constructive.scheme',
        label: tr(l, 'services.tz.arx.constructive_scheme_label'),
        fallbackOptions: const [
          'karkas',
          'monolit',
          'gisht',
          'aralash',
          'metall',
        ],
        fallbackLabelOf: (s) => switch (s) {
          'karkas' => tr(l, 'services.tz.arx.scheme_frame'),
          'monolit' => tr(l, 'services.tz.arx.scheme_monolith'),
          'gisht' => tr(l, 'services.tz.arx.material_brick'),
          'aralash' => tr(l, 'services.tz.arx.scheme_mixed'),
          'metall' => tr(l, 'services.tz.arx.material_metal'),
          _ => s,
        },
        value: _draft.constructive.scheme,
        onChanged: (v) => setState(() => _draft.constructive.scheme = v),
      ),
      _schemaChipPicker(
        l: l,
        mapsTo: 'details.constructive.foundation',
        label: tr(l, 'services.tz.arx.foundation_label'),
        fallbackOptions: const ['ustun', 'lenta', 'plita', 'svay'],
        fallbackLabelOf: (s) => switch (s) {
          'ustun' => tr(l, 'services.tz.arx.foundation_column'),
          'lenta' => tr(l, 'services.tz.arx.foundation_strip'),
          'plita' => tr(l, 'services.tz.arx.foundation_slab'),
          'svay' => tr(l, 'services.tz.arx.foundation_pile'),
          _ => s,
        },
        value: _draft.constructive.foundation,
        onChanged: (v) => setState(() => _draft.constructive.foundation = v),
      ),
      _schemaChipPicker(
        l: l,
        mapsTo: 'details.constructive.walls',
        label: tr(l, 'services.tz.arx.wall_material_label'),
        fallbackOptions: const ['gisht', 'gazoblok', 'beton', 'sendvich_panel'],
        fallbackLabelOf: (s) => switch (s) {
          'gisht' => tr(l, 'services.tz.arx.material_brick'),
          'gazoblok' => tr(l, 'services.tz.arx.material_aerocrete'),
          'beton' => tr(l, 'services.tz.arx.material_concrete'),
          'sendvich_panel' => tr(l, 'services.tz.arx.material_sandwich_panel'),
          _ => s,
        },
        value: _draft.constructive.walls,
        onChanged: (v) => setState(() => _draft.constructive.walls = v),
      ),
      _schemaChipPicker(
        l: l,
        mapsTo: 'details.constructive.ceiling',
        label: tr(l, 'services.tz.arx.ceiling_label'),
        fallbackOptions: const ['temir_beton', 'yogoch', 'metall'],
        fallbackLabelOf: (s) => switch (s) {
          'temir_beton' => tr(l, 'services.tz.arx.ceiling_reinforced_concrete'),
          'yogoch' => tr(l, 'services.tz.arx.material_wood'),
          'metall' => tr(l, 'services.tz.arx.material_metal'),
          _ => s,
        },
        value: _draft.constructive.ceiling,
        onChanged: (v) => setState(() => _draft.constructive.ceiling = v),
      ),
      _schemaChipPicker(
        l: l,
        mapsTo: 'details.constructive.roof_type',
        label: tr(l, 'services.tz.arx.roof_type_label'),
        fallbackOptions: const ['yassi', 'qiya'],
        fallbackLabelOf: (s) =>
            s == 'yassi' ? tr(l, 'services.tz.arx.roof_flat') : tr(l, 'services.tz.arx.roof_pitched'),
        value: _draft.constructive.roofType,
        onChanged: (v) => setState(() => _draft.constructive.roofType = v),
      ),
      WizardField(
        label: tr(l, 'services.tz.arx.roof_material_label'),
        controller: _roofMaterial,
        placeholder: tr(l, 'services.tz.arx.roof_material_placeholder'),
      ),
    ]);
  }

  // ── Step 7: Muhandislik tizimlari ────────────────────────────────────
  Widget _buildStep7(Locale l) {
    final eng = _draft.engineering;
    return _scrollableStep([
      WizardSectionTitle(text: tr(l, 'services.tz.arx.engineering_systems')),
      _OptionalStepHint(text: tr(l, 'services.tz.arx.technical_optional_hint')),
      _schemaChipPicker(
        l: l,
        mapsTo: 'details.engineering.water_source',
        label: tr(l, 'services.tz.arx.water_source_label'),
        fallbackOptions: const ['markaziy', 'quduq'],
        fallbackLabelOf: (s) =>
            s == 'markaziy' ? tr(l, 'services.tz.arx.central') : tr(l, 'services.tz.arx.well'),
        value: _draft.engineering.waterSource,
        onChanged: (v) => setState(() => _draft.engineering.waterSource = v),
      ),
      _schemaChipPicker(
        l: l,
        mapsTo: 'details.engineering.sewage',
        label: tr(l, 'services.tz.arx.sewage_label'),
        fallbackOptions: const ['markaziy', 'septik'],
        fallbackLabelOf: (s) =>
            s == 'markaziy' ? tr(l, 'services.tz.arx.central') : tr(l, 'services.tz.arx.septic'),
        value: _draft.engineering.sewage,
        onChanged: (v) => setState(() => _draft.engineering.sewage = v),
      ),
      _schemaChipPicker(
        l: l,
        mapsTo: 'details.engineering.heating',
        label: tr(l, 'services.tz.arx.heating_label'),
        fallbackOptions: const ['gaz', 'elektr', 'qozonxona'],
        fallbackLabelOf: (s) => switch (s) {
          'gaz' => tr(l, 'services.tz.arx.heating_gas'),
          'elektr' => tr(l, 'services.tz.arx.heating_electric'),
          'qozonxona' => tr(l, 'services.tz.arx.heating_boiler'),
          _ => s,
        },
        value: _draft.engineering.heating,
        onChanged: (v) => setState(() => _draft.engineering.heating = v),
      ),
      _schemaChipPicker(
        l: l,
        mapsTo: 'details.engineering.ventilation',
        label: tr(l, 'services.tz.arx.ventilation_label'),
        fallbackOptions: const ['tabiiy', 'mexanik'],
        fallbackLabelOf: (s) => s == 'tabiiy'
            ? tr(l, 'services.tz.arx.ventilation_natural')
            : tr(l, 'services.tz.arx.ventilation_mechanical'),
        value: _draft.engineering.ventilation,
        onChanged: (v) => setState(() => _draft.engineering.ventilation = v),
      ),
      _schemaChipPicker(
        l: l,
        mapsTo: 'details.engineering.air_conditioning',
        label: tr(l, 'services.tz.arx.air_conditioning_label'),
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
      _featureChips(tr(l, 'services.tz.arx.extra_systems_label'), [
        (
          tr(l, 'services.tz.arx.backup_generator'),
          eng.hasGenerator,
          () => setState(() => eng.hasGenerator = !eng.hasGenerator),
        ),
        (
          tr(l, 'services.tz.arx.fire_safety_system'),
          eng.hasFireSystem,
          () => setState(() => eng.hasFireSystem = !eng.hasFireSystem),
        ),
        (
          tr(l, 'services.tz.arx.alarm_system'),
          eng.hasAlarm,
          () => setState(() => eng.hasAlarm = !eng.hasAlarm),
        ),
        (
          tr(l, 'services.tz.arx.video_surveillance'),
          eng.hasVideoSurveillance,
          () => setState(
            () => eng.hasVideoSurveillance = !eng.hasVideoSurveillance,
          ),
        ),
        (
          tr(l, 'services.tz.arx.solar_panels'),
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
      WizardSectionTitle(text: tr(l, 'services.tz.arx.territory_planning')),
      _OptionalStepHint(text: tr(l, 'services.tz.arx.design_optional_hint')),
      _featureChips(tr(l, 'services.tz.arx.territory_features_label'), [
        (
          tr(l, 'services.tz.arx.parking'),
          t.hasParking,
          () => setState(() => t.hasParking = !t.hasParking),
        ),
        (
          tr(l, 'services.tz.arx.walkways'),
          t.hasPaths,
          () => setState(() => t.hasPaths = !t.hasPaths),
        ),
        (
          tr(l, 'services.tz.arx.landscape_design'),
          t.hasLandscape,
          () => setState(() => t.hasLandscape = !t.hasLandscape),
        ),
        (
          tr(l, 'services.tz.arx.pool'),
          t.hasPool,
          () => setState(() => t.hasPool = !t.hasPool),
        ),
        (
          tr(l, 'services.tz.arx.territory_lighting'),
          t.hasLighting,
          () => setState(() => t.hasLighting = !t.hasLighting),
        ),
      ]),
      if (t.hasParking)
        WizardField(
          label: tr(l, 'services.tz.arx.parking_spaces_label'),
          controller: _parkingCount,
          placeholder: '4',
          numericOnly: true,
        ),
    ]);
  }

  // ── Step 9: Muddatlar va qo'shimcha talablar ─────────────────────────
  Widget _buildStep9(Locale l) {
    return _scrollableStep([
      WizardSectionTitle(text: tr(l, 'services.tz.arx.timelines')),
      Row(
        children: [
          Expanded(
            child: WizardField(
              label: tr(l, 'services.tz.arx.sketch_project_label'),
              controller: _sketchDays,
              placeholder: '30',
              suffix: tr(l, 'services.tz.arx.unit_days'),
              numericOnly: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: WizardField(
              label: tr(l, 'services.tz.arx.working_project_label'),
              controller: _workingDays,
              placeholder: '60',
              suffix: tr(l, 'services.tz.arx.unit_days'),
              numericOnly: true,
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      WizardSectionTitle(text: tr(l, 'services.tz.arx.additional_requirements')),
      WizardField(
        label: tr(l, 'services.tz.arx.notes_label'),
        controller: _notes,
        placeholder: tr(l, 'services.tz.arx.notes_placeholder'),
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
      (tr(l, 'services.tz.arx.customer_name_label'), d.customerName.trim()),
      if (d.tin.trim().isNotEmpty) (tr(l, 'services.tz.arx.tin_label'), d.tin.trim()),
      (tr(l, 'services.tz.arx.phone_label'), d.phone.trim()),
      if (d.email.trim().isNotEmpty) ('E-mail', d.email.trim()),
    ];

    // Step 1 — Obyekt va manzil
    final object = <(String, String)>[
      if (d.objectName.trim().isNotEmpty)
        (tr(l, 'services.tz.arx.object_name_label'), d.objectName.trim()),
      if (d.address.trim().isNotEmpty)
        (tr(l, 'services.tz.arx.address_label'), d.address.trim()),
      if (d.cadastreNumber.trim().isNotEmpty)
        (tr(l, 'services.tz.arx.cadastre_number_label'), d.cadastreNumber.trim()),
      if (d.landAreaSqm != null)
        (
          tr(l, 'services.tz.arx.land_area_label'),
          '${_trimNum(d.landAreaSqm!)} ${tr(l, 'services.tz.arx.unit_sqm')}',
        ),
      if (d.landUsePurpose.trim().isNotEmpty)
        (
          tr(l, 'services.tz.arx.land_use_purpose_label'),
          _landUseDisplay(d.landUsePurpose.trim(), l),
        ),
    ];

    // Step 2 — Loyiha
    final project = <(String, String)>[
      if (d.objectType != null)
        (tr(l, 'services.tz.arx.object_type_label'), _objectTypeLabel(d.objectType!, l)),
      (
        tr(l, 'services.tz.arx.construction_type_label'),
        d.constructionType == ConstructionType.yangi
            ? tr(l, 'services.tz.arx.construction_new')
            : tr(l, 'services.tz.arx.construction_reconstruction'),
      ),
      if (d.floors != null) (tr(l, 'services.tz.arx.floors_count_label'), '${d.floors}'),
      if (d.maxHeightM != null)
        (
          tr(l, 'services.tz.arx.max_height_label'),
          '${_trimNum(d.maxHeightM!)} ${tr(l, 'services.tz.arx.unit_m')}',
        ),
      if (d.constructionYear != null)
        (tr(l, 'services.tz.arx.construction_year_label'), '${d.constructionYear}'),
      if (d.totalAreaSqm != null)
        (
          tr(l, 'services.tz.arx.total_area_label'),
          '${_trimNum(d.totalAreaSqm!)} ${tr(l, 'services.tz.arx.unit_sqm')}',
        ),
      if (d.buildingAreaSqm != null)
        (
          tr(l, 'services.tz.arx.building_area_label'),
          '${_trimNum(d.buildingAreaSqm!)} ${tr(l, 'services.tz.arx.unit_sqm')}',
        ),
    ];
    final projectChips = <String>[
      if (d.hasBasement) tr(l, 'services.tz.arx.has_basement'),
      if (d.hasMansard) tr(l, 'services.tz.arx.has_mansard'),
      if (d.hasUndergroundParking) tr(l, 'services.tz.arx.has_underground_parking'),
    ];

    // Step 3 — Xonalar
    final roomChips = [
      for (final r in d.rooms)
        '${r.kind == RoomKind.other ? (r.name?.trim().isNotEmpty ?? false ? r.name!.trim() : r.kind.label(l)) : r.kind.label(l)}'
            ' ×${r.count}${r.area != null ? ' · ${_trimNum(r.area!)} ${tr(l, 'services.tz.arx.unit_sqm')}' : ''}',
    ];

    // Step 4 — Arxitektura yechimlari
    final arch = <(String, String)>[
      if (d.architecture.style != null)
        (
          tr(l, 'services.tz.arx.style_label'),
          _catalogLabel(styleOpts, d.architecture.style, l),
        ),
      if (d.architecture.facadeMaterial != null)
        (
          tr(l, 'services.tz.arx.facade_material_label'),
          _catalogLabel(facadeOpts, d.architecture.facadeMaterial, l),
        ),
      if ((d.architecture.colors ?? '').trim().isNotEmpty)
        (tr(l, 'services.tz.arx.colors_label'), d.architecture.colors!.trim()),
    ];
    final archChips = <String>[
      if (d.architecture.has3dVisualization) tr(l, 'services.tz.arx.need_3d_visualization'),
    ];

    // Step 5 — Konstruktiv
    final constructive = <(String, String)>[
      if (d.constructive.scheme != null)
        (
          tr(l, 'services.tz.arx.constructive_scheme_label'),
          c(
            d.constructive.scheme,
            (s) => switch (s) {
              'karkas' => tr(l, 'services.tz.arx.scheme_frame'),
              'monolit' => tr(l, 'services.tz.arx.scheme_monolith'),
              'gisht' => tr(l, 'services.tz.arx.material_brick'),
              'aralash' => tr(l, 'services.tz.arx.scheme_mixed'),
              'metall' => tr(l, 'services.tz.arx.material_metal'),
              _ => s,
            },
          ),
        ),
      if (d.constructive.foundation != null)
        (
          tr(l, 'services.tz.arx.foundation_label'),
          c(
            d.constructive.foundation,
            (s) => switch (s) {
              'ustun' => tr(l, 'services.tz.arx.foundation_column'),
              'lenta' => tr(l, 'services.tz.arx.foundation_strip'),
              'plita' => tr(l, 'services.tz.arx.foundation_slab'),
              'svay' => tr(l, 'services.tz.arx.foundation_pile'),
              _ => s,
            },
          ),
        ),
      if (d.constructive.walls != null)
        (
          tr(l, 'services.tz.arx.wall_material_label'),
          c(
            d.constructive.walls,
            (s) => switch (s) {
              'gisht' => tr(l, 'services.tz.arx.material_brick'),
              'gazoblok' => tr(l, 'services.tz.arx.material_aerocrete'),
              'beton' => tr(l, 'services.tz.arx.material_concrete'),
              'sendvich_panel' => tr(l, 'services.tz.arx.material_sandwich_panel'),
              _ => s,
            },
          ),
        ),
      if (d.constructive.ceiling != null)
        (
          tr(l, 'services.tz.arx.ceiling_label'),
          c(
            d.constructive.ceiling,
            (s) => switch (s) {
              'temir_beton' => tr(l, 'services.tz.arx.ceiling_reinforced_concrete'),
              'yogoch' => tr(l, 'services.tz.arx.material_wood'),
              'metall' => tr(l, 'services.tz.arx.material_metal'),
              _ => s,
            },
          ),
        ),
      if (d.constructive.roofType != null)
        (
          tr(l, 'services.tz.arx.roof_type_label'),
          d.constructive.roofType == 'yassi'
              ? tr(l, 'services.tz.arx.roof_flat')
              : tr(l, 'services.tz.arx.roof_pitched'),
        ),
      if ((d.constructive.roofMaterial ?? '').trim().isNotEmpty)
        (tr(l, 'services.tz.arx.roof_material_label'), d.constructive.roofMaterial!.trim()),
    ];

    // Step 6 — Muhandislik
    final eng = <(String, String)>[
      if (d.engineering.waterSource != null)
        (
          tr(l, 'services.tz.arx.water_source_label'),
          d.engineering.waterSource == 'markaziy'
              ? tr(l, 'services.tz.arx.central')
              : tr(l, 'services.tz.arx.well'),
        ),
      if (d.engineering.sewage != null)
        (
          tr(l, 'services.tz.arx.sewage_label'),
          d.engineering.sewage == 'markaziy'
              ? tr(l, 'services.tz.arx.central')
              : tr(l, 'services.tz.arx.septic'),
        ),
      if (d.engineering.heating != null)
        (
          tr(l, 'services.tz.arx.heating_label'),
          c(
            d.engineering.heating,
            (s) => switch (s) {
              'gaz' => tr(l, 'services.tz.arx.heating_gas'),
              'elektr' => tr(l, 'services.tz.arx.heating_electric'),
              'qozonxona' => tr(l, 'services.tz.arx.heating_boiler'),
              _ => s,
            },
          ),
        ),
      if (d.engineering.ventilation != null)
        (
          tr(l, 'services.tz.arx.ventilation_label'),
          d.engineering.ventilation == 'tabiiy'
              ? tr(l, 'services.tz.arx.ventilation_natural')
              : tr(l, 'services.tz.arx.ventilation_mechanical'),
        ),
      if (d.engineering.airConditioning != null)
        (
          tr(l, 'services.tz.arx.air_conditioning_label'),
          d.engineering.airConditioning!.toUpperCase(),
        ),
    ];
    final engChips = <String>[
      if (d.engineering.hasGenerator) tr(l, 'services.tz.arx.backup_generator'),
      if (d.engineering.hasFireSystem) tr(l, 'services.tz.arx.fire_safety_system'),
      if (d.engineering.hasAlarm) tr(l, 'services.tz.arx.alarm_system'),
      if (d.engineering.hasVideoSurveillance) tr(l, 'services.tz.arx.video_surveillance'),
      if (d.engineering.hasSolarPanels) tr(l, 'services.tz.arx.solar_panels'),
    ];

    // Step 7 — Hudud
    final territoryChips = <String>[
      if (d.territory.hasParking)
        '${tr(l, 'services.tz.arx.parking')}${d.territory.parkingCount != null ? ' ×${d.territory.parkingCount}' : ''}',
      if (d.territory.hasPaths) tr(l, 'services.tz.arx.walkways'),
      if (d.territory.hasLandscape) tr(l, 'services.tz.arx.landscape_design'),
      if (d.territory.hasPool) tr(l, 'services.tz.arx.pool'),
      if (d.territory.hasLighting) tr(l, 'services.tz.arx.territory_lighting'),
    ];

    // Step 8 — Muddatlar va izoh
    final timeline = <(String, String)>[
      if (d.timeline.sketchDays != null)
        (
          tr(l, 'services.tz.arx.sketch_project_label'),
          '${d.timeline.sketchDays} ${tr(l, 'services.tz.arx.unit_days')}',
        ),
      if (d.timeline.workingDays != null)
        (
          tr(l, 'services.tz.arx.working_project_label'),
          '${d.timeline.workingDays} ${tr(l, 'services.tz.arx.unit_days')}',
        ),
      if (d.notes.trim().isNotEmpty) (tr(l, 'services.tz.arx.notes_label'), d.notes.trim()),
    ];

    final missingRequired = !d.canSubmit;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        Text(
          tr(l, 'services.tz.arx.review_intro'),
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
          title: tr(l, 'services.tz.arx.customer_details'),
          onEdit: () => _editStep(0),
          rows: customer,
          warning:
              (d.customerName.trim().length < 2 || d.phone.trim().length < 5)
              ? tr(l, 'services.tz.arx.fill_required')
              : null,
        ),
        WizardReviewSection(
          title: tr(l, 'services.tz.arx.object_and_address'),
          onEdit: () => _editStep(1),
          rows: object,
        ),
        WizardReviewSection(
          title: tr(l, 'services.tz.arx.project_general_info'),
          onEdit: () => _editStep(2),
          rows: project,
          chips: projectChips,
          warning: d.objectType == null ? tr(l, 'services.tz.arx.fill_required') : null,
        ),
        WizardReviewSection(
          title: tr(l, 'services.tz.arx.rooms_composition'),
          onEdit: () => _editStep(3),
          chips: roomChips,
        ),
        WizardReviewSection(
          title: tr(l, 'services.tz.arx.architecture_and_design'),
          onEdit: () => _editStep(4),
          rows: arch,
          chips: archChips,
        ),
        WizardReviewSection(
          title: tr(l, 'services.tz.arx.constructive_solutions'),
          onEdit: () => _editStep(5),
          rows: constructive,
        ),
        WizardReviewSection(
          title: tr(l, 'services.tz.arx.engineering_systems'),
          onEdit: () => _editStep(6),
          rows: eng,
          chips: engChips,
        ),
        WizardReviewSection(
          title: tr(l, 'services.tz.arx.territory_planning'),
          onEdit: () => _editStep(7),
          chips: territoryChips,
        ),
        WizardReviewSection(
          title: tr(l, 'services.tz.arx.timelines'),
          onEdit: () => _editStep(8),
          rows: timeline,
        ),
        if (missingRequired) ...[
          const SizedBox(height: 4),
          Text(
            tr(l, 'services.tz.arx.fill_required'),
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
        'turar_joy' => tr(l, 'services.tz.arx.land_use_residential'),
        'ishlab_chiqarish' => tr(l, 'services.tz.arx.land_use_production'),
        'savdo' => tr(l, 'services.tz.arx.land_use_commercial'),
        'aralash' => tr(l, 'services.tz.arx.land_use_mixed'),
        _ => codeOrText,
      };

  static String _objectTypeLabel(ArchObjectType t, Locale l) {
    final key = switch (t) {
      ArchObjectType.yakkaSmall => 'yakka_small',
      ArchObjectType.yakkaLarge => 'yakka_large',
      ArchObjectType.kopQavatli => 'kop_qavatli',
      ArchObjectType.ofis => 'ofis',
      ArchObjectType.savdoMarkazi => 'savdo_markazi',
      ArchObjectType.mehmonxona => 'mehmonxona',
      ArchObjectType.sanoat => 'sanoat',
      ArchObjectType.omborxona => 'omborxona',
      ArchObjectType.boshqa => 'boshqa',
    };
    return tr(l, 'services.tz.arx.object_type.$key');
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
