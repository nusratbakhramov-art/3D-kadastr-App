/// Dizayn loyihasi uchun TZ wizard.
///
/// 7 step:
///   1. Buyurtmachi rekvizitlari
///   2. Obyekt va o'lchamlar
///   3. Qo'shimcha xonalar
///   4. Interyer dizayni
///   5. Muhandislik tizimlari
///   6. Eksteryer dizayni
///   7. Muddatlar + qo'shimcha talablar
///
/// Online kalkulator natijasidan keyin ochiladi (`dizayn_form_screen`), obyekt
/// turi / uslub / maydon oldindan to'ldirib beriladi. Yakunda
/// `/services/design/orders` ga yuboriladi.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/input_validators.dart';
import '../../../../theme/app_colors.dart';
import '../../../auth/auth_storage.dart';
import '../../../home/user_profile.dart';
import '../../../settings/settings_state.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../api_design_order_service.dart';
import '../../api_forms_service.dart';
import '../../data/calculator_pricing_store.dart';
import '../../data/last_customer_store.dart';
import '../../models/calculator_pricing.dart';
import '../../models/design_order_draft.dart';
import '../../models/dynamic_form_schema.dart';
import '../../widgets/service_app_bar.dart';
import '../../widgets/step_progress_bar.dart';
import '../../widgets/color_palette_field.dart';
import '../../widgets/location_picker_field.dart';
import '../../widgets/wizard_field.dart';
import '../../widgets/wizard_review_section.dart';
import 'arxitektura_tz_success_screen.dart';

class DizaynTzWizardScreen extends StatefulWidget {
  const DizaynTzWizardScreen({super.key, this.initialDraft, this.onSubmit});

  /// Kalkulator natijasidan oldindan to'ldirilgan draft.
  final DizaynOrderDraft? initialDraft;

  /// Berilsa, yakuniy step'da backend'ga YUBORILMAYDI — draft callback'ga
  /// uzatiladi (birlashtirilgan kalkulyator orchestratori o'zi yuboradi).
  final void Function(DizaynOrderDraft draft)? onSubmit;

  @override
  State<DizaynTzWizardScreen> createState() => _DizaynTzWizardScreenState();
}

class _DizaynTzWizardScreenState extends State<DizaynTzWizardScreen> {
  static const int _inputStepCount = 7;
  static const int _previewIndex = _inputStepCount; // 7

  late final DizaynOrderDraft _draft;
  late final PageController _pageController;
  int _stepIndex = 0;

  // Bo'lim qalamchasi orqali tahrirga kirilganda — "Davom etish" o'rniga
  // "Saqlash" va saqlangach to'g'ridan-to'g'ri Preview'ga qaytadi.
  bool _editReturn = false;
  // Buyurtmachi bo'limi oxirgi arizadan to'ldirilganini ko'rsatish uchun.
  bool _prefilledFromLast = false;

  // Step 1 controllers
  late final TextEditingController _customerName;
  late final TextEditingController _tin;
  late final TextEditingController _phone;
  late final TextEditingController _email;

  // Step 2
  late final TextEditingController _objectName;
  late final TextEditingController _address;
  late final TextEditingController _objectSubtype;
  late final TextEditingController _floors;
  late final TextEditingController _roomsCount;
  late final TextEditingController _totalArea;
  late final TextEditingController _interiorArea;
  late final TextEditingController _designArea;
  late final TextEditingController _ceilingHeight;

  // Step 3
  late final TextEditingController _extraRooms;

  // Step 6
  late final TextEditingController _parkingCount;

  // Step 7
  late final TextEditingController _designDays;
  late final TextEditingController _workingDrawingsDays;
  late final TextEditingController _notes;

  bool _submitting = false;

  // Backend forma sxemasi (dizayn_tz) — variant ro'yxatlari/labellarni
  // adminkadan beradi; yuklanmaguncha hardcoded fallback ishlatiladi.
  FormSchema? _formSchema;

  // Gating controllerlar (validatsiyaga ta'sir qiladi) — bularga listener
  // qo'shamiz, shunda "Davom etish" tugmasi har doim sinxron bo'ladi.
  late final List<TextEditingController> _gating = [
    _customerName,
    _tin,
    _phone,
  ];

  @override
  void initState() {
    super.initState();
    _draft = widget.initialDraft ?? DizaynOrderDraft();
    _pageController = PageController();

    // Profil ma'lumotlaridan default qiymatlar.
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
    _objectSubtype = TextEditingController(text: _draft.objectSubtype);
    _floors = TextEditingController(text: _draft.floors?.toString() ?? '');
    _roomsCount = TextEditingController(
      text: _draft.roomsCount?.toString() ?? '',
    );
    _totalArea = TextEditingController(
      text: _draft.totalAreaSqm?.toString() ?? '',
    );
    _interiorArea = TextEditingController(
      text: _draft.interiorAreaSqm?.toString() ?? '',
    );
    _designArea = TextEditingController(
      text: _draft.designAreaSqm?.toString() ?? '',
    );
    _ceilingHeight = TextEditingController(
      text: _draft.ceilingHeightM?.toString() ?? '',
    );

    _extraRooms = TextEditingController(text: _draft.extraRooms);

    _parkingCount = TextEditingController(
      text: _draft.exterior.parkingCount?.toString() ?? '',
    );

    _designDays = TextEditingController(
      text: _draft.timeline.designDays?.toString() ?? '',
    );
    _workingDrawingsDays = TextEditingController(
      text: _draft.timeline.workingDrawingsDays?.toString() ?? '',
    );
    _notes = TextEditingController(text: _draft.notes);

    for (final c in _gating) {
      c.addListener(_onCtrlChanged);
    }

    // Oxirgi yuborilgan buyurtmachidan to'ldirish (faqat bo'sh maydonlar).
    _prefillFromLastCustomer();
    _loadFormSchema();
  }

  Future<void> _loadFormSchema() async {
    try {
      final schema = await FormsApiService().getForm('dizayn_tz');
      if (mounted) setState(() => _formSchema = schema);
    } catch (_) {
      /* sxema yetib bormasa — hardcoded fallback */
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

  void _onCtrlChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _gating) {
      c.removeListener(_onCtrlChanged);
    }
    for (final c in [
      _customerName,
      _tin,
      _phone,
      _email,
      _objectName,
      _address,
      _objectSubtype,
      _floors,
      _roomsCount,
      _totalArea,
      _interiorArea,
      _designArea,
      _ceilingHeight,
      _extraRooms,
      _parkingCount,
      _designDays,
      _workingDrawingsDays,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // STIR (9) yoki INN (14) — kiritilgan bo'lsa, uzunligi shu ikkitadan biri.
  bool get _tinValid => isValidTin(_tin.text);

  // Telefon — kiritilgan bo'lsa formati to'g'ri bo'lsin (xato matni uchun).
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
      case 1:
        return _draft.objectType != null;
      case _previewIndex:
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
    _draft.objectSubtype = _objectSubtype.text;
    _draft.floors = _parseInt(_floors.text);
    _draft.roomsCount = _parseInt(_roomsCount.text);
    _draft.totalAreaSqm = _parseDouble(_totalArea.text);
    _draft.interiorAreaSqm = _parseDouble(_interiorArea.text);
    _draft.designAreaSqm = _parseDouble(_designArea.text);
    _draft.ceilingHeightM = _parseDouble(_ceilingHeight.text);

    _draft.extraRooms = _extraRooms.text;

    // Ranglar (interyer/eksteryer) ColorPaletteField orqali draftga yoziladi.
    _draft.exterior.parkingCount = _parseInt(_parkingCount.text);

    _draft.timeline.designDays = _parseInt(_designDays.text);
    _draft.timeline.workingDrawingsDays = _parseInt(_workingDrawingsDays.text);
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

  /// Preview'dagi qalamcha bosilganda — shu bo'lim step'iga "Saqlash" rejimida.
  void _editStep(int index) {
    HapticFeedback.lightImpact();
    setState(() => _editReturn = true);
    _animateToPage(index);
  }

  Future<void> _next() async {
    _syncDraftFromControllers();
    if (!_canAdvance) return;
    HapticFeedback.lightImpact();

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

  Locale get _locale =>
      Localizations.maybeLocaleOf(context) ?? localeNotifier.value;

  // Katalog (backend → kesh → default) — adminkadan tahrirlanadigan variantlar.
  static List<CalcOption> _catalog(String group) =>
      calculatorPricingNotifier.value.optionsFor(group);

  String _catalogLabel(List<CalcOption> opts, String? v) {
    if (v == null) return '';
    for (final o in opts) {
      if (o.value == v) return o.localized(_locale);
    }
    return v;
  }

  // ── Forma sxemasi (form_definitions) variantlari ─────────────────────────
  // `maps_to` bo'yicha backend sxemasidan variant ro'yxati/labellarini beradi;
  // sxema yo'q / maydon topilmasa, chaqiruvchi hardcoded fallback'ga tushadi.
  List<FormOption> _schemaOptsByPath(String mapsTo) {
    final schema = _formSchema;
    if (schema == null) return const [];
    for (final f in schema.allFields) {
      if (f.mapsTo == mapsTo) return f.options;
    }
    return const [];
  }

  String _schemaOptLabel(List<FormOption> opts, String? code) {
    if (code == null) return '';
    for (final o in opts) {
      if (o.value == code) return trMap(o.label, _locale);
    }
    return code;
  }

  /// String-pikerlar uchun: variantlar backend sxemasidan (bor bo'lsa), aks
  /// holda [fallbackOptions] + [fallbackLabelOf]. Kodlar bir xil — ko'rinish
  /// o'zgarmaydi.
  Widget _schemaChipPicker({
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
      labelOf: (v) => useSchema ? _schemaOptLabel(opts, v) : fallbackLabelOf(v),
      value: value,
      onChanged: onChanged,
    );
  }

  /// Enum-pikerlar uchun: kod (apiValue) bo'yicha sxema labeli, topilmasa
  /// [fallback]. Variant ro'yxati/saqlanishi o'zgarmaydi — faqat label.
  String _schemaEnumLabel(String mapsTo, String code, String fallback) {
    for (final o in _schemaOptsByPath(mapsTo)) {
      if (o.value == code) return trMap(o.label, _locale);
    }
    return fallback;
  }

  Future<void> _submit() async {
    final s = _Strings(_locale);
    if (!_draft.canSubmit) {
      _showError(s.fillRequiredFields);
      return;
    }

    // Embedded (birlashtirilgan kalkulyator) rejimi — draft'ni callback'ga
    // uzatamiz; orchestrator o'zi yuboradi.
    if (widget.onSubmit != null) {
      HapticFeedback.lightImpact();
      widget.onSubmit!(_draft);
      return;
    }

    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null) {
      if (mounted) {
        _showError(s.signInFirst);
      }
      return;
    }

    setState(() => _submitting = true);
    final api = DesignOrderApiService();
    try {
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
    } on DesignOrderApiException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('${_Strings(_locale).networkError}: $e');
    } finally {
      api.dispose();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final s = _Strings(Localizations.localeOf(context));

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
                        title: s.appBarTitle,
                        subtitle: _stepTitle(_stepIndex, s),
                        onBack: _back,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: StepProgressBar(
                        count: _inputStepCount,
                        activeIndex: _isPreview
                            ? _inputStepCount - 1
                            : _stepIndex,
                      ),
                    ),
                    Expanded(
                      child: PageView(
                        controller: _pageController,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _buildStep1(),
                          _buildStep2(),
                          _buildStep3(),
                          _buildStep4(),
                          _buildStep5(),
                          _buildStep6(),
                          _buildStep7(),
                          _buildPreview(s),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: ListingCtaButton(
                        label: _submitting
                            ? s.submitting
                            : (_editReturn
                                  ? s.saveChanges
                                  : (_isPreview ? s.submit : s.continueLabel)),
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

  String _stepTitle(int i, _Strings s) {
    return switch (i) {
      0 => '1/7 — ${s.crumbCustomer}',
      1 => '2/7 — ${s.crumbObject}',
      2 => '3/7 — ${s.crumbExtraRooms}',
      3 => '4/7 — ${s.crumbInterior}',
      4 => '5/7 — ${s.crumbEngineering}',
      5 => '6/7 — ${s.crumbExterior}',
      6 => '7/7 — ${s.crumbTimeline}',
      _previewIndex => s.crumbReview,
      _ => '',
    };
  }

  Widget _scrollableStep(List<Widget> children) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        for (final c in children) ...[c, const SizedBox(height: 14)],
      ],
    );
  }

  // ── Step 1: Buyurtmachi ──────────────────────────────────────────────
  Widget _buildStep1() {
    final s = _Strings(_locale);
    return _scrollableStep([
      WizardSectionTitle(text: s.customerDetails),
      if (_prefilledFromLast) WizardPrefillHint(text: s.prefilledHint),
      WizardField(
        label: s.fullNameOrCompany,
        controller: _customerName,
        placeholder: s.namePlaceholder,
        required: true,
      ),
      WizardField(
        label: switch (_locale.languageCode) {
          'ru' => 'ИНН',
          'en' => 'TIN',
          _ => 'STIR',
        },
        controller: _tin,
        placeholder: '300000000',
        numericOnly: true,
        maxLength: 14,
        errorText: _tinValid ? null : s.tinError,
      ),
      WizardField(
        label: s.phone,
        controller: _phone,
        placeholder: '+998 90 123 45 67',
        keyboardType: TextInputType.phone,
        phoneFormat: true,
        maxLength: 17,
        required: true,
        errorText: _phoneError ? s.phoneError : null,
      ),
      WizardField(
        label: 'E-mail',
        controller: _email,
        placeholder: 'sample@mail.com',
        keyboardType: TextInputType.emailAddress,
        errorText: isValidEmail(_email.text) ? null : s.emailError,
      ),
    ]);
  }

  // ── Step 2: Obyekt va o'lchamlar ─────────────────────────────────────
  Widget _buildStep2() {
    final s = _Strings(_locale);
    return _scrollableStep([
      WizardSectionTitle(text: s.objectAndDimensions),
      WizardField(
        label: s.objectName,
        controller: _objectName,
        placeholder: s.objectNamePlaceholder,
      ),
      LocationPickerField(
        label: s.address,
        value: _draft.location,
        onChanged: (loc) => setState(() {
          _draft.location = loc;
          if (loc.addressText != null) {
            _address.text = loc.addressText!;
          }
        }),
      ),
      WizardChipPicker<DizObjectType>(
        label: s.objectType,
        required: true,
        options: DizObjectType.values,
        labelOf: (t) =>
            _schemaEnumLabel('object_type', t.apiValue, _objectTypeLabel(t, s)),
        value: _draft.objectType,
        onChanged: (v) => setState(() => _draft.objectType = v),
      ),
      if (_draft.objectType == DizObjectType.boshqa)
        WizardField(
          label: s.otherWhichType,
          controller: _objectSubtype,
          placeholder: s.otherTypePlaceholder,
        ),
      WizardChipPicker<DizDesignType>(
        label: s.designType,
        options: DizDesignType.values,
        labelOf: (t) => _schemaEnumLabel(
          'design_type',
          t.apiValue,
          t == DizDesignType.yangi ? s.designNew : s.designReconstruction,
        ),
        value: _draft.designType,
        onChanged: (v) =>
            setState(() => _draft.designType = v ?? DizDesignType.yangi),
      ),
      Row(
        children: [
          Expanded(
            child: WizardField(
              label: s.floorsCount,
              controller: _floors,
              placeholder: '1',
              numericOnly: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: WizardField(
              label: s.roomsCount,
              controller: _roomsCount,
              placeholder: '4',
              numericOnly: true,
            ),
          ),
        ],
      ),
      Row(
        children: [
          Expanded(
            child: WizardField(
              label: s.totalArea,
              controller: _totalArea,
              placeholder: '120',
              suffix: 'm²',
              numericOnly: true,
              allowDecimal: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: WizardField(
              label: s.ceilingHeight,
              controller: _ceilingHeight,
              placeholder: '3',
              suffix: 'm',
              numericOnly: true,
              allowDecimal: true,
            ),
          ),
        ],
      ),
      Row(
        children: [
          Expanded(
            child: WizardField(
              label: s.interiorArea,
              controller: _interiorArea,
              placeholder: '100',
              suffix: 'm²',
              numericOnly: true,
              allowDecimal: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: WizardField(
              label: s.designArea,
              controller: _designArea,
              placeholder: '100',
              suffix: 'm²',
              numericOnly: true,
              allowDecimal: true,
            ),
          ),
        ],
      ),
      WizardSwitchTile(
        label: s.hasBasement,
        value: _draft.hasBasement,
        onChanged: (v) => setState(() => _draft.hasBasement = v),
      ),
      WizardSwitchTile(
        label: s.hasMansard,
        value: _draft.hasMansard,
        onChanged: (v) => setState(() => _draft.hasMansard = v),
      ),
    ]);
  }

  // ── Step 3: Qo'shimcha xonalar ───────────────────────────────────────
  Widget _buildStep3() {
    final s = _Strings(_locale);
    return _scrollableStep([
      WizardSectionTitle(text: s.extraRoomsTitle),
      WizardField(
        label: s.extraRoomsLabel,
        controller: _extraRooms,
        placeholder: s.extraRoomsPlaceholder,
        maxLines: 5,
      ),
    ]);
  }

  // ── Step 4: Interyer dizayni ─────────────────────────────────────────
  Widget _buildStep4() {
    final s = _Strings(_locale);
    return _scrollableStep([
      WizardSectionTitle(text: s.interiorDesign),
      Builder(
        builder: (_) {
          final opts = _catalog('dizayn.interior.style');
          return WizardChipPicker<String>(
            label: s.style,
            options: [for (final o in opts) o.value],
            labelOf: (k) => _catalogLabel(opts, k),
            value: _draft.interior.style,
            onChanged: (v) => setState(() => _draft.interior.style = v),
          );
        },
      ),
      Builder(
        builder: (_) {
          final opts = _catalog('dizayn.interior.material');
          return WizardChipPicker<String>(
            label: s.interiorMaterial,
            options: [for (final o in opts) o.value],
            labelOf: (k) => _catalogLabel(opts, k),
            value: _draft.interior.interiorMaterial,
            onChanged: (v) =>
                setState(() => _draft.interior.interiorMaterial = v),
          );
        },
      ),
      Builder(
        builder: (_) {
          final opts = _catalog('dizayn.floor_material');
          return WizardChipPicker<String>(
            label: s.floorMaterial,
            options: [for (final o in opts) o.value],
            labelOf: (k) => _catalogLabel(opts, k),
            value: _draft.interior.floorMaterial,
            onChanged: (v) => setState(() => _draft.interior.floorMaterial = v),
          );
        },
      ),
      ColorPaletteField(
        label: s.colors,
        value: _draft.interior.colors,
        onChanged: (v) =>
            _draft.interior.colors = v.trim().isEmpty ? null : v.trim(),
      ),
      WizardSwitchTile(
        label: s.need3dVisualization,
        value: _draft.interior.has3dVisualization,
        onChanged: (v) =>
            setState(() => _draft.interior.has3dVisualization = v),
      ),
      WizardSwitchTile(
        label: s.projectWorkingDrawings,
        value: _draft.interior.hasWorkingDrawings,
        onChanged: (v) =>
            setState(() => _draft.interior.hasWorkingDrawings = v),
      ),
      WizardSwitchTile(
        label: s.authorSupervision,
        value: _draft.interior.hasAuthorSupervision,
        onChanged: (v) =>
            setState(() => _draft.interior.hasAuthorSupervision = v),
      ),
    ]);
  }

  // ── Step 5: Muhandislik tizimlari ────────────────────────────────────
  Widget _buildStep5() {
    final s = _Strings(_locale);
    return _scrollableStep([
      WizardSectionTitle(text: s.engineeringSystems),
      WizardSwitchTile(
        label: s.electricalDrawings,
        value: _draft.engineering.hasElectricalDrawings,
        onChanged: (v) =>
            setState(() => _draft.engineering.hasElectricalDrawings = v),
      ),
      WizardSwitchTile(
        label: s.plumbingDrawings,
        value: _draft.engineering.hasPlumbingDrawings,
        onChanged: (v) =>
            setState(() => _draft.engineering.hasPlumbingDrawings = v),
      ),
      WizardSwitchTile(
        label: s.demolitionPlan,
        value: _draft.engineering.hasDemolitionPlan,
        onChanged: (v) =>
            setState(() => _draft.engineering.hasDemolitionPlan = v),
      ),
      WizardSwitchTile(
        label: s.montagePlan,
        value: _draft.engineering.hasMontagePlan,
        onChanged: (v) => setState(() => _draft.engineering.hasMontagePlan = v),
      ),
      WizardSwitchTile(
        label: s.gypsumPlan,
        value: _draft.engineering.hasGypsumPlan,
        onChanged: (v) => setState(() => _draft.engineering.hasGypsumPlan = v),
      ),
      _schemaChipPicker(
        mapsTo: 'details.engineering.partition_material',
        label: s.partitionLabel,
        fallbackOptions: _partitionMaterials,
        fallbackLabelOf: (k) => s.materialLabel(k),
        value: _draft.engineering.partitionMaterial,
        onChanged: (v) =>
            setState(() => _draft.engineering.partitionMaterial = v),
      ),
      _schemaChipPicker(
        mapsTo: 'details.engineering.air_conditioning',
        label: s.airConditioning,
        fallbackOptions: _acTypes,
        fallbackLabelOf: (k) => s.acLabel(k),
        value: _draft.engineering.airConditioning,
        onChanged: (v) =>
            setState(() => _draft.engineering.airConditioning = v),
      ),
      WizardSwitchTile(
        label: s.fireSystem,
        value: _draft.engineering.hasFireSystem,
        onChanged: (v) => setState(() => _draft.engineering.hasFireSystem = v),
      ),
      WizardSwitchTile(
        label: s.videoSurveillance,
        value: _draft.engineering.hasVideoSurveillance,
        onChanged: (v) =>
            setState(() => _draft.engineering.hasVideoSurveillance = v),
      ),
      WizardSwitchTile(
        label: s.furnitureLayout,
        value: _draft.engineering.hasFurnitureLayout,
        onChanged: (v) =>
            setState(() => _draft.engineering.hasFurnitureLayout = v),
      ),
    ]);
  }

  // ── Step 6: Eksteryer dizayni ────────────────────────────────────────
  Widget _buildStep6() {
    final s = _Strings(_locale);
    return _scrollableStep([
      WizardSectionTitle(text: s.exteriorDesign),
      Builder(
        builder: (_) {
          final opts = _catalog('dizayn.exterior.style');
          return WizardChipPicker<String>(
            label: s.style,
            options: [for (final o in opts) o.value],
            labelOf: (k) => _catalogLabel(opts, k),
            value: _draft.exterior.style,
            onChanged: (v) => setState(() => _draft.exterior.style = v),
          );
        },
      ),
      Builder(
        builder: (_) {
          final opts = _catalog('dizayn.exterior.material');
          return WizardChipPicker<String>(
            label: s.exteriorMaterial,
            options: [for (final o in opts) o.value],
            labelOf: (k) => _catalogLabel(opts, k),
            value: _draft.exterior.exteriorMaterial,
            onChanged: (v) =>
                setState(() => _draft.exterior.exteriorMaterial = v),
          );
        },
      ),
      ColorPaletteField(
        label: s.colors,
        value: _draft.exterior.colors,
        onChanged: (v) =>
            _draft.exterior.colors = v.trim().isEmpty ? null : v.trim(),
      ),
      WizardSwitchTile(
        label: s.parking,
        value: _draft.exterior.hasParking,
        onChanged: (v) => setState(() => _draft.exterior.hasParking = v),
      ),
      if (_draft.exterior.hasParking)
        WizardField(
          label: s.parkingSpacesCount,
          controller: _parkingCount,
          placeholder: '4',
          numericOnly: true,
        ),
      WizardSwitchTile(
        label: s.paths,
        value: _draft.exterior.hasPaths,
        onChanged: (v) => setState(() => _draft.exterior.hasPaths = v),
      ),
      WizardSwitchTile(
        label: s.landscapeDesign,
        value: _draft.exterior.hasLandscape,
        onChanged: (v) => setState(() => _draft.exterior.hasLandscape = v),
      ),
      WizardSwitchTile(
        label: s.pool,
        value: _draft.exterior.hasPool,
        onChanged: (v) => setState(() => _draft.exterior.hasPool = v),
      ),
      WizardSwitchTile(
        label: s.areaLighting,
        value: _draft.exterior.hasLighting,
        onChanged: (v) => setState(() => _draft.exterior.hasLighting = v),
      ),
    ]);
  }

  // ── Step 7: Muddatlar va izoh ────────────────────────────────────────
  Widget _buildStep7() {
    final s = _Strings(_locale);
    return _scrollableStep([
      WizardSectionTitle(text: s.timeline),
      Row(
        children: [
          Expanded(
            child: WizardField(
              label: s.designProject,
              controller: _designDays,
              placeholder: '30',
              suffix: s.daysUnit,
              numericOnly: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: WizardField(
              label: s.workingDrawings,
              controller: _workingDrawingsDays,
              placeholder: '20',
              suffix: s.daysUnit,
              numericOnly: true,
            ),
          ),
        ],
      ),
      WizardSectionTitle(text: s.additionalRequirements),
      WizardField(
        label: s.notes,
        controller: _notes,
        placeholder: s.notesPlaceholder,
        maxLines: 5,
      ),
    ]);
  }

  // ── Preview / Tekshirish ─────────────────────────────────────────────
  // Yuborishdan oldin to'ldirilgan ma'lumotlarning umumiy ko'rinishi. Har
  // bo'lim qalamcha ("✎") orqali to'g'ridan-to'g'ri tahrirga ochiladi.
  Widget _buildPreview(_Strings s) {
    final d = _draft;
    final interiorStyleOpts = _catalog('dizayn.interior.style');
    final interiorMatOpts = _catalog('dizayn.interior.material');
    final floorMatOpts = _catalog('dizayn.floor_material');
    final exteriorStyleOpts = _catalog('dizayn.exterior.style');
    final exteriorMatOpts = _catalog('dizayn.exterior.material');

    String num(double? v) =>
        v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : '$v');

    // Step 0 — Buyurtmachi
    final customer = <(String, String)>[
      (s.fullNameOrCompany, d.customerName.trim()),
      if (d.tin.trim().isNotEmpty)
        (
          switch (_locale.languageCode) {
            'ru' => 'ИНН',
            'en' => 'TIN',
            _ => 'STIR',
          },
          d.tin.trim(),
        ),
      (s.phone, d.phone.trim()),
      if (d.email.trim().isNotEmpty) ('E-mail', d.email.trim()),
    ];

    // Step 1 — Obyekt va o'lchamlar
    final object = <(String, String)>[
      if (d.objectName.trim().isNotEmpty) (s.objectName, d.objectName.trim()),
      if (d.address.trim().isNotEmpty) (s.address, d.address.trim()),
      if (d.objectType != null)
        (s.objectType, _objectTypeLabel(d.objectType!, s)),
      (
        s.designType,
        d.designType == DizDesignType.yangi
            ? s.designNew
            : s.designReconstruction,
      ),
      if (d.floors != null) (s.floorsCount, '${d.floors}'),
      if (d.roomsCount != null) (s.roomsCount, '${d.roomsCount}'),
      if (d.totalAreaSqm != null) (s.totalArea, '${num(d.totalAreaSqm)} m²'),
      if (d.interiorAreaSqm != null)
        (s.interiorArea, '${num(d.interiorAreaSqm)} m²'),
      if (d.designAreaSqm != null) (s.designArea, '${num(d.designAreaSqm)} m²'),
      if (d.ceilingHeightM != null)
        (s.ceilingHeight, '${num(d.ceilingHeightM)} m'),
    ];
    final objectChips = <String>[
      if (d.hasBasement) s.hasBasement,
      if (d.hasMansard) s.hasMansard,
    ];

    // Step 2 — Qo'shimcha xonalar
    final extra = <(String, String)>[
      if (d.extraRooms.trim().isNotEmpty)
        (s.extraRoomsLabel, d.extraRooms.trim()),
    ];

    // Step 3 — Interyer
    final interior = <(String, String)>[
      if (d.interior.style != null)
        (s.style, _catalogLabel(interiorStyleOpts, d.interior.style)),
      if (d.interior.interiorMaterial != null)
        (
          s.interiorMaterial,
          _catalogLabel(interiorMatOpts, d.interior.interiorMaterial),
        ),
      if (d.interior.floorMaterial != null)
        (
          s.floorMaterial,
          _catalogLabel(floorMatOpts, d.interior.floorMaterial),
        ),
      if ((d.interior.colors ?? '').trim().isNotEmpty)
        (s.colors, d.interior.colors!.trim()),
    ];
    final interiorChips = <String>[
      if (d.interior.has3dVisualization) s.need3dVisualization,
      if (d.interior.hasWorkingDrawings) s.projectWorkingDrawings,
      if (d.interior.hasAuthorSupervision) s.authorSupervision,
    ];

    // Step 4 — Muhandislik
    final engineering = <(String, String)>[
      if (d.engineering.partitionMaterial != null)
        (s.partitionLabel, s.materialLabel(d.engineering.partitionMaterial!)),
      if (d.engineering.airConditioning != null)
        (s.airConditioning, s.acLabel(d.engineering.airConditioning!)),
    ];
    final engineeringChips = <String>[
      if (d.engineering.hasElectricalDrawings) s.electricalDrawings,
      if (d.engineering.hasPlumbingDrawings) s.plumbingDrawings,
      if (d.engineering.hasDemolitionPlan) s.demolitionPlan,
      if (d.engineering.hasMontagePlan) s.montagePlan,
      if (d.engineering.hasGypsumPlan) s.gypsumPlan,
      if (d.engineering.hasFireSystem) s.fireSystem,
      if (d.engineering.hasVideoSurveillance) s.videoSurveillance,
      if (d.engineering.hasFurnitureLayout) s.furnitureLayout,
    ];

    // Step 5 — Eksteryer
    final exterior = <(String, String)>[
      if (d.exterior.style != null)
        (s.style, _catalogLabel(exteriorStyleOpts, d.exterior.style)),
      if (d.exterior.exteriorMaterial != null)
        (
          s.exteriorMaterial,
          _catalogLabel(exteriorMatOpts, d.exterior.exteriorMaterial),
        ),
      if ((d.exterior.colors ?? '').trim().isNotEmpty)
        (s.colors, d.exterior.colors!.trim()),
    ];
    final exteriorChips = <String>[
      if (d.exterior.hasParking)
        '${s.parking}${d.exterior.parkingCount != null ? ' ×${d.exterior.parkingCount}' : ''}',
      if (d.exterior.hasPaths) s.paths,
      if (d.exterior.hasLandscape) s.landscapeDesign,
      if (d.exterior.hasPool) s.pool,
      if (d.exterior.hasLighting) s.areaLighting,
    ];

    // Step 6 — Muddatlar va izoh
    final timeline = <(String, String)>[
      if (d.timeline.designDays != null)
        (s.designProject, '${d.timeline.designDays} ${s.daysUnit}'),
      if (d.timeline.workingDrawingsDays != null)
        (s.workingDrawings, '${d.timeline.workingDrawingsDays} ${s.daysUnit}'),
      if (d.notes.trim().isNotEmpty) (s.notes, d.notes.trim()),
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        Text(
          s.reviewIntro,
          style: TextStyle(
            fontFamily: 'MTSText',
            fontSize: 13,
            color: isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278),
          ),
        ),
        const SizedBox(height: 14),
        WizardReviewSection(
          title: s.customerDetails,
          onEdit: () => _editStep(0),
          rows: customer,
          warning:
              (d.customerName.trim().length < 2 || d.phone.trim().length < 5)
              ? s.fillRequiredFields
              : null,
        ),
        WizardReviewSection(
          title: s.objectAndDimensions,
          onEdit: () => _editStep(1),
          rows: object,
          chips: objectChips,
          warning: d.objectType == null ? s.fillRequiredFields : null,
        ),
        WizardReviewSection(
          title: s.extraRoomsTitle,
          onEdit: () => _editStep(2),
          rows: extra,
        ),
        WizardReviewSection(
          title: s.interiorDesign,
          onEdit: () => _editStep(3),
          rows: interior,
          chips: interiorChips,
        ),
        WizardReviewSection(
          title: s.engineeringSystems,
          onEdit: () => _editStep(4),
          rows: engineering,
          chips: engineeringChips,
        ),
        WizardReviewSection(
          title: s.exteriorDesign,
          onEdit: () => _editStep(5),
          rows: exterior,
          chips: exteriorChips,
        ),
        WizardReviewSection(
          title: s.timeline,
          onEdit: () => _editStep(6),
          rows: timeline,
        ),
        if (!d.canSubmit) ...[
          const SizedBox(height: 4),
          Text(
            s.fillRequiredFields,
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

  // ── Label helpers ────────────────────────────────────────────────────
  static String _objectTypeLabel(DizObjectType t, _Strings s) => switch (t) {
    DizObjectType.yakka => s.objTypeYakka,
    DizObjectType.kopQavatliKvartira => s.objTypeKopQavatli,
    DizObjectType.savdoMarkazi => s.objTypeSavdoMarkazi,
    DizObjectType.ofis => s.objTypeOfis,
    DizObjectType.mehmonxona => s.objTypeMehmonxona,
    DizObjectType.sanoat => s.objTypeSanoat,
    DizObjectType.omborxona => s.objTypeOmborxona,
    DizObjectType.boshqa => s.objTypeBoshqa,
  };

  static const _partitionMaterials = ['gisht', 'gipsokarton', 'gazoblok'];

  static const _acTypes = ['split', 'vrf', 'chiller'];
}

// ── Parse yordamchilari ────────────────────────────────────────────────
int? _parseInt(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  return int.tryParse(t);
}

double? _parseDouble(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  return double.tryParse(t.replaceAll(',', '.'));
}

// ── Lokalizatsiya matnlari (uz/ru/en) ──────────────────────────────────
class _Strings {
  const _Strings(this.locale);
  final Locale locale;

  String _s(String ru, String en, String uz) => switch (locale.languageCode) {
    'ru' => ru,
    'en' => en,
    _ => uz,
  };

  // App bar / navigatsiya / tugmalar
  String get appBarTitle => _s('Дизайн', 'Design', 'Dizayn');
  String get continueLabel => _s('Продолжить', 'Continue', 'Davom etish');
  String get submit => _s('Отправить', 'Submit', 'Yuborish');
  String get saveChanges => _s('Сохранить', 'Save', 'Saqlash');
  String get crumbReview =>
      _s('Проверка и отправка', 'Review and submit', 'Tekshirish va yuborish');
  String get reviewIntro => _s(
    'Проверьте данные перед отправкой. Нажмите ✎, чтобы изменить раздел.',
    'Check the details before submitting. Tap ✎ to edit a section.',
    'Yuborishdan oldin ma\'lumotlarni tekshiring. Bo\'limni o\'zgartirish uchun ✎ ni bosing.',
  );
  String get prefilledHint => _s(
    'Заполнено по последней заявке — можно изменить',
    'Filled from your last order — you can edit it',
    'Oxirgi arizangizdan to\'ldirildi — o\'zgartirsangiz bo\'ladi',
  );
  String get submitting => _s('Отправка…', 'Submitting…', 'Yuborilmoqda…');

  // Step crumbs
  String get crumbCustomer => _s('Заказчик', 'Customer', 'Buyurtmachi');
  String get crumbObject =>
      _s('Объект и размеры', 'Object and dimensions', 'Obyekt va o\'lchamlar');
  String get crumbExtraRooms =>
      _s('Доп. комнаты', 'Extra rooms', 'Qo\'shimcha xonalar');
  String get crumbInterior =>
      _s('Дизайн интерьера', 'Interior design', 'Interyer dizayni');
  String get crumbEngineering =>
      _s('Инженерные системы', 'Engineering systems', 'Muhandislik tizimlari');
  String get crumbExterior =>
      _s('Дизайн экстерьера', 'Exterior design', 'Eksteryer dizayni');
  String get crumbTimeline =>
      _s('Сроки и комментарий', 'Timeline and comment', 'Muddatlar va izoh');

  // Snackbar / validatsiya
  String get fillRequiredFields => _s(
    'Заполните обязательные поля',
    'Fill in the required fields',
    'Majburiy maydonlarni to\'ldiring',
  );
  String get signInFirst => _s(
    'Чтобы отправить заявку, сначала войдите в систему',
    'Please sign in first to submit the order',
    'Buyurtma yuborish uchun avval tizimga kiring',
  );
  String get networkError =>
      _s('Сетевая ошибка', 'Network error', 'Tarmoq xatosi');

  // Step 1: Buyurtmachi
  String get customerDetails =>
      _s('Реквизиты заказчика', 'Customer details', 'Buyurtmachi rekvizitlari');
  String get fullNameOrCompany => _s(
    'Ф.И.О или название компании',
    'Full name or company name',
    'F.I.SH yoki kompaniya nomi',
  );
  String get namePlaceholder =>
      _s('Имя Фамилия', 'First name Last name', 'Ism Familiya');
  String get tinError => _s(
    '9 (СТИР) или 14 (ИНН) цифр',
    'Must be 9 (STIR) or 14 (INN) digits',
    '9 (STIR) yoki 14 (INN) raqamdan iborat bo\'lsin',
  );
  String get phone => _s('Телефон', 'Phone', 'Telefon');
  String get phoneError => _s(
    'Введите корректный номер, напр. +998 90 123 45 67',
    'Enter a valid number, e.g. +998 90 123 45 67',
    'To\'g\'ri raqam kiriting, masalan +998 90 123 45 67',
  );
  String get emailError => _s(
    'Введите корректный e-mail',
    'Enter a valid e-mail',
    'To\'g\'ri e-mail kiriting',
  );

  // Step 2: Obyekt va o'lchamlar
  String get objectAndDimensions =>
      _s('Объект и размеры', 'Object and dimensions', 'Obyekt va o\'lchamlar');
  String get objectName => _s('Название объекта', 'Object name', 'Obyekt nomi');
  String get objectNamePlaceholder =>
      _s('Моя квартира', 'My apartment', 'Mening kvartiram');
  String get address => _s('Адрес', 'Address', 'Manzil');
  String get objectType => _s('Тип объекта', 'Object type', 'Obyekt turi');
  String get otherWhichType => _s(
    'Другое (какого типа)',
    'Other (which type)',
    'Boshqa (qaysi turdagi)',
  );
  String get otherTypePlaceholder => _s(
    'Например: многофункциональный центр',
    'E.g.: multi-functional center',
    'Masalan: ko\'p funksiyali markaz',
  );
  String get designType => _s('Тип дизайна', 'Design type', 'Dizayn turi');
  String get designNew => _s('Новый', 'New', 'Yangi');
  String get designReconstruction =>
      _s('Реконструкция', 'Reconstruction', 'Rekonstruksiya');
  String get floorsCount =>
      _s('Количество этажей', 'Number of floors', 'Qavatlar soni');
  String get roomsCount =>
      _s('Количество комнат', 'Number of rooms', 'Xonalar soni');
  String get totalArea => _s('Общая площадь', 'Total area', 'Umumiy maydon');
  String get ceilingHeight =>
      _s('Высота потолков', 'Ceiling height', 'Honalar balandligi');
  String get interiorArea =>
      _s('Площадь интерьера', 'Interior area', 'Interyer maydoni');
  String get designArea =>
      _s('Площадь дизайна', 'Design area', 'Dizayn maydoni');
  String get hasBasement =>
      _s('С подвалом', 'With basement', 'Podval bo\'lsin');
  String get hasMansard =>
      _s('С мансардой', 'With mansard', 'Mansarda bo\'lsin');

  // Object type labels
  String get objTypeYakka =>
      _s('Индивидуальный дом', 'Detached house', 'Yakka tartibdagi uy');
  String get objTypeKopQavatli => _s(
    'Многоэтажка — квартира',
    'Multi-storey — apartment',
    'Ko\'p qavatli — kvartira',
  );
  String get objTypeSavdoMarkazi =>
      _s('Торговый центр', 'Shopping center', 'Savdo markazi');
  String get objTypeOfis => _s('Офис', 'Office', 'Ofis');
  String get objTypeMehmonxona => _s('Гостиница', 'Hotel', 'Mehmonxona');
  String get objTypeSanoat => _s('Промышленный', 'Industrial', 'Sanoat');
  String get objTypeOmborxona => _s('Склад', 'Warehouse', 'Omborxona');
  String get objTypeBoshqa => _s('Другое', 'Other', 'Boshqa');

  // Step 3: Qo'shimcha xonalar
  String get extraRoomsTitle =>
      _s('Дополнительные комнаты', 'Additional rooms', 'Qo\'shimcha xonalar');
  String get extraRoomsLabel => _s(
    'Дополнительные (другие) комнаты',
    'Additional (other) rooms',
    'Qo\'shimcha (boshqa) xonalar',
  );
  String get extraRoomsPlaceholder => _s(
    'Например: кабинет, гардеробная, библиотека…',
    'E.g.: office, dressing room, library…',
    'Masalan: ish kabineti, kiyim xonasi, kutubxona…',
  );

  // Step 4: Interyer dizayni
  String get interiorDesign =>
      _s('Дизайн интерьера', 'Interior design', 'Interyer dizayni');
  String get style => _s('Стиль', 'Style', 'Uslub');
  String get interiorMaterial =>
      _s('Материал интерьера', 'Interior material', 'Interyer materiali');
  String get floorMaterial =>
      _s('Материал пола', 'Floor material', 'Pol materiali');
  String get colors => _s('Цвета', 'Colors', 'Ranglar');
  String get need3dVisualization => _s(
    'Нужна 3D-визуализация',
    '3D visualization needed',
    '3D vizualizatsiya kerak',
  );
  String get projectWorkingDrawings => _s(
    'Рабочие чертежи проекта',
    'Project working drawings',
    'Loyihaning ishchi chizmalari',
  );
  String get authorSupervision =>
      _s('Авторский надзор', 'Author supervision', 'Mualliflik nazorati');

  // Step 5: Muhandislik tizimlari
  String get engineeringSystems =>
      _s('Инженерные системы', 'Engineering systems', 'Muhandislik tizimlari');
  String get electricalDrawings =>
      _s('Чертежи электрики', 'Electrical drawings', 'Elektrika chizmalari');
  String get plumbingDrawings => _s(
    'Чертежи разводки сантехники',
    'Plumbing layout drawings',
    'Santexnika joylashuv chizmalari',
  );
  String get demolitionPlan => _s(
    'Раздел демонтажа стен',
    'Wall demolition section',
    'Demontaj devorlar bo\'linmasi',
  );
  String get montagePlan => _s(
    'Раздел монтажа стен',
    'Wall montage section',
    'Montaj devorlar bo\'linmasi',
  );
  String get gypsumPlan => _s(
    'Разделы и чертежи гипсокартона',
    'Gypsum board sections and drawings',
    'Gipsokarton bo\'linmalari va chizmalari',
  );
  String get partitionLabel =>
      _s('Перегородки комнат', 'Room partitions', 'Honalar bo\'linmalari');
  String get airConditioning =>
      _s('Кондиционер', 'Air conditioning', 'Konditsioner');
  String get fireSystem => _s(
    'Система пожарной безопасности',
    'Fire safety system',
    'Yong\'in xavfsizligi tizimi',
  );
  String get videoSurveillance =>
      _s('Видеонаблюдение', 'Video surveillance', 'Videokuzatuv');
  String get furnitureLayout =>
      _s('Расстановка мебели', 'Furniture layout', 'Mebellar joylashuvi');

  // Step 6: Eksteryer dizayni
  String get exteriorDesign =>
      _s('Дизайн экстерьера', 'Exterior design', 'Eksteryer dizayni');
  String get exteriorMaterial =>
      _s('Материал экстерьера', 'Exterior material', 'Eksteryer materiali');
  String get parking => _s('Автостоянка', 'Parking', 'Avtoturargoh');
  String get parkingSpacesCount => _s(
    'Количество парковочных мест',
    'Number of parking spaces',
    'Parking joylar soni',
  );
  String get paths => _s('Дорожки', 'Paths', 'Yo\'laklar');
  String get landscapeDesign =>
      _s('Ландшафтный дизайн', 'Landscape design', 'Landshaft dizayni');
  String get pool => _s('Бассейн', 'Pool', 'Hovuz');
  String get areaLighting =>
      _s('Освещение территории', 'Area lighting', 'Hudud yoritilishi');

  // Step 7: Muddatlar va izoh
  String get timeline => _s('Сроки', 'Timeline', 'Muddatlar');
  String get designProject =>
      _s('Дизайн-проект', 'Design project', 'Dizayn loyiha');
  String get workingDrawings =>
      _s('Рабочие чертежи', 'Working drawings', 'Ishchi chizmalar');
  String get daysUnit => _s('дн.', 'days', 'kun');
  String get additionalRequirements => _s(
    'Дополнительные требования',
    'Additional requirements',
    'Qo\'shimcha talablar',
  );
  String get notes => _s('Комментарий', 'Comment', 'Izoh');
  String get notesPlaceholder => _s(
    'Дополнительные требования и комментарии…',
    'Additional requirements and comments…',
    'Qo\'shimcha talab va izohlar…',
  );

  // Style options
  String styleLabel(String key) => switch (key) {
    'high_tech' => 'High-tech',
    'klassik' => _s('Классика', 'Classic', 'Klassik'),
    'neoklassik' => _s('Неоклассика', 'Neoclassic', 'Neoklassik'),
    'minimalizm' => _s('Минимализм', 'Minimalism', 'Minimalizm'),
    'loft' => _s('Лофт', 'Loft', 'Loft'),
    'modern' => _s('Модерн', 'Modern', 'Modern'),
    'boshqa' => _s('Другое', 'Other', 'Boshqa'),
    _ => key,
  };

  // Material options
  String materialLabel(String key) => switch (key) {
    'boyoq' => _s('Краска', 'Paint', 'Bo\'yoq'),
    'tosh' => _s('Камень', 'Stone', 'Tosh'),
    'kompozit' => _s(
      'Композитные панели',
      'Composite panels',
      'Kompozit panellar',
    ),
    'shisha' => _s('Стекло', 'Glass', 'Shisha'),
    'bambuk' => _s('Бамбуковые панели', 'Bamboo panels', 'Bambuk panellar'),
    'laminat' => _s('Ламинат', 'Laminate', 'Laminat'),
    'kafel' => _s('Кафель', 'Tile', 'Kafel'),
    'boshqa' => _s('Другое', 'Other', 'Boshqa'),
    'gisht' => _s('Кирпич', 'Brick', 'G\'isht'),
    'gipsokarton' => _s('Гипсокартон', 'Gypsum board', 'Gipsokarton'),
    'gazoblok' => _s('Газоблок', 'Aerated block', 'Gazoblok'),
    _ => key,
  };

  // Air conditioning options
  String acLabel(String key) => switch (key) {
    'split' => 'Split',
    'vrf' => 'VRF',
    'chiller' => _s('Чиллер', 'Chiller', 'Chiller'),
    _ => key,
  };
}
