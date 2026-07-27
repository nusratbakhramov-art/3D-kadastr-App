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

import '../../../../core/i18n/app_translations.dart';
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
    if (!_draft.canSubmit) {
      _showError(tr(_locale, 'services.tz.dizayn.fill_required_fields'));
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
        _showError(tr(_locale, 'services.tz.dizayn.sign_in_first'));
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
      _showError('${tr(_locale, 'services.tz.dizayn.network_error')}: $e');
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
                        title: tr(_locale, 'services.tz.dizayn.app_bar_title'),
                        subtitle: _stepTitle(_stepIndex),
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
                          _buildPreview(),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: ListingCtaButton(
                        label: _submitting
                            ? tr(_locale, 'services.tz.dizayn.submitting')
                            : (_editReturn
                                  ? tr(_locale, 'services.tz.dizayn.save_changes')
                                  : (_isPreview ? tr(_locale, 'services.tz.dizayn.submit') : tr(_locale, 'services.tz.dizayn.continue_label'))),
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

  String _stepTitle(int i) {
    return switch (i) {
      0 => '1/7 — ${tr(_locale, 'services.tz.dizayn.crumb_customer')}',
      1 => '2/7 — ${tr(_locale, 'services.tz.dizayn.crumb_object')}',
      2 => '3/7 — ${tr(_locale, 'services.tz.dizayn.crumb_extra_rooms')}',
      3 => '4/7 — ${tr(_locale, 'services.tz.dizayn.crumb_interior')}',
      4 => '5/7 — ${tr(_locale, 'services.tz.dizayn.crumb_engineering')}',
      5 => '6/7 — ${tr(_locale, 'services.tz.dizayn.crumb_exterior')}',
      6 => '7/7 — ${tr(_locale, 'services.tz.dizayn.crumb_timeline')}',
      _previewIndex => tr(_locale, 'services.tz.dizayn.crumb_review'),
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
    return _scrollableStep([
      WizardSectionTitle(text: tr(_locale, 'services.tz.dizayn.customer_details')),
      if (_prefilledFromLast) WizardPrefillHint(text: tr(_locale, 'services.tz.dizayn.prefilled_hint')),
      WizardField(
        label: tr(_locale, 'services.tz.dizayn.full_name_or_company'),
        controller: _customerName,
        placeholder: tr(_locale, 'services.tz.dizayn.name_placeholder'),
        required: true,
      ),
      WizardField(
        label: tr(_locale, 'services.tz.dizayn.tin_label'),
        controller: _tin,
        placeholder: '300000000',
        numericOnly: true,
        maxLength: 14,
        errorText: _tinValid ? null : tr(_locale, 'services.tz.dizayn.tin_error'),
      ),
      WizardField(
        label: tr(_locale, 'services.tz.dizayn.phone'),
        controller: _phone,
        placeholder: '+998 90 123 45 67',
        keyboardType: TextInputType.phone,
        phoneFormat: true,
        maxLength: 17,
        required: true,
        errorText: _phoneError ? tr(_locale, 'services.tz.dizayn.phone_error') : null,
      ),
      WizardField(
        label: 'E-mail',
        controller: _email,
        placeholder: 'sample@mail.com',
        keyboardType: TextInputType.emailAddress,
        errorText: isValidEmail(_email.text) ? null : tr(_locale, 'services.tz.dizayn.email_error'),
      ),
    ]);
  }

  // ── Step 2: Obyekt va o'lchamlar ─────────────────────────────────────
  Widget _buildStep2() {
    return _scrollableStep([
      WizardSectionTitle(text: tr(_locale, 'services.tz.dizayn.object_and_dimensions')),
      WizardField(
        label: tr(_locale, 'services.tz.dizayn.object_name'),
        controller: _objectName,
        placeholder: tr(_locale, 'services.tz.dizayn.object_name_placeholder'),
      ),
      LocationPickerField(
        label: tr(_locale, 'services.tz.dizayn.address'),
        value: _draft.location,
        onChanged: (loc) => setState(() {
          _draft.location = loc;
          if (loc.addressText != null) {
            _address.text = loc.addressText!;
          }
        }),
      ),
      WizardChipPicker<DizObjectType>(
        label: tr(_locale, 'services.tz.dizayn.object_type_label'),
        required: true,
        options: DizObjectType.values,
        labelOf: (t) =>
            _schemaEnumLabel('object_type', t.apiValue, _objectTypeLabel(t, _locale)),
        value: _draft.objectType,
        onChanged: (v) => setState(() => _draft.objectType = v),
      ),
      if (_draft.objectType == DizObjectType.boshqa)
        WizardField(
          label: tr(_locale, 'services.tz.dizayn.other_which_type'),
          controller: _objectSubtype,
          placeholder: tr(_locale, 'services.tz.dizayn.other_type_placeholder'),
        ),
      WizardChipPicker<DizDesignType>(
        label: tr(_locale, 'services.tz.dizayn.design_type'),
        options: DizDesignType.values,
        labelOf: (t) => _schemaEnumLabel(
          'design_type',
          t.apiValue,
          t == DizDesignType.yangi ? tr(_locale, 'services.tz.dizayn.design_new') : tr(_locale, 'services.tz.dizayn.design_reconstruction'),
        ),
        value: _draft.designType,
        onChanged: (v) =>
            setState(() => _draft.designType = v ?? DizDesignType.yangi),
      ),
      Row(
        children: [
          Expanded(
            child: WizardField(
              label: tr(_locale, 'services.tz.dizayn.floors_count'),
              controller: _floors,
              placeholder: '1',
              numericOnly: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: WizardField(
              label: tr(_locale, 'services.tz.dizayn.rooms_count'),
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
              label: tr(_locale, 'services.tz.dizayn.total_area'),
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
              label: tr(_locale, 'services.tz.dizayn.ceiling_height'),
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
              label: tr(_locale, 'services.tz.dizayn.interior_area'),
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
              label: tr(_locale, 'services.tz.dizayn.design_area'),
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
        label: tr(_locale, 'services.tz.dizayn.has_basement'),
        value: _draft.hasBasement,
        onChanged: (v) => setState(() => _draft.hasBasement = v),
      ),
      WizardSwitchTile(
        label: tr(_locale, 'services.tz.dizayn.has_mansard'),
        value: _draft.hasMansard,
        onChanged: (v) => setState(() => _draft.hasMansard = v),
      ),
    ]);
  }

  // ── Step 3: Qo'shimcha xonalar ───────────────────────────────────────
  Widget _buildStep3() {
    return _scrollableStep([
      WizardSectionTitle(text: tr(_locale, 'services.tz.dizayn.extra_rooms_title')),
      WizardField(
        label: tr(_locale, 'services.tz.dizayn.extra_rooms_label'),
        controller: _extraRooms,
        placeholder: tr(_locale, 'services.tz.dizayn.extra_rooms_placeholder'),
        maxLines: 5,
      ),
    ]);
  }

  // ── Step 4: Interyer dizayni ─────────────────────────────────────────
  Widget _buildStep4() {
    return _scrollableStep([
      WizardSectionTitle(text: tr(_locale, 'services.tz.dizayn.interior_design')),
      Builder(
        builder: (_) {
          final opts = _catalog('dizayn.interior.style');
          return WizardChipPicker<String>(
            label: tr(_locale, 'services.tz.dizayn.style'),
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
            label: tr(_locale, 'services.tz.dizayn.interior_material'),
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
            label: tr(_locale, 'services.tz.dizayn.floor_material'),
            options: [for (final o in opts) o.value],
            labelOf: (k) => _catalogLabel(opts, k),
            value: _draft.interior.floorMaterial,
            onChanged: (v) => setState(() => _draft.interior.floorMaterial = v),
          );
        },
      ),
      ColorPaletteField(
        label: tr(_locale, 'services.tz.dizayn.colors'),
        value: _draft.interior.colors,
        onChanged: (v) =>
            _draft.interior.colors = v.trim().isEmpty ? null : v.trim(),
      ),
      WizardSwitchTile(
        label: tr(_locale, 'services.tz.dizayn.need_3d_visualization'),
        value: _draft.interior.has3dVisualization,
        onChanged: (v) =>
            setState(() => _draft.interior.has3dVisualization = v),
      ),
      WizardSwitchTile(
        label: tr(_locale, 'services.tz.dizayn.project_working_drawings'),
        value: _draft.interior.hasWorkingDrawings,
        onChanged: (v) =>
            setState(() => _draft.interior.hasWorkingDrawings = v),
      ),
      WizardSwitchTile(
        label: tr(_locale, 'services.tz.dizayn.author_supervision'),
        value: _draft.interior.hasAuthorSupervision,
        onChanged: (v) =>
            setState(() => _draft.interior.hasAuthorSupervision = v),
      ),
    ]);
  }

  // ── Step 5: Muhandislik tizimlari ────────────────────────────────────
  Widget _buildStep5() {
    return _scrollableStep([
      WizardSectionTitle(text: tr(_locale, 'services.tz.dizayn.engineering_systems')),
      WizardSwitchTile(
        label: tr(_locale, 'services.tz.dizayn.electrical_drawings'),
        value: _draft.engineering.hasElectricalDrawings,
        onChanged: (v) =>
            setState(() => _draft.engineering.hasElectricalDrawings = v),
      ),
      WizardSwitchTile(
        label: tr(_locale, 'services.tz.dizayn.plumbing_drawings'),
        value: _draft.engineering.hasPlumbingDrawings,
        onChanged: (v) =>
            setState(() => _draft.engineering.hasPlumbingDrawings = v),
      ),
      WizardSwitchTile(
        label: tr(_locale, 'services.tz.dizayn.demolition_plan'),
        value: _draft.engineering.hasDemolitionPlan,
        onChanged: (v) =>
            setState(() => _draft.engineering.hasDemolitionPlan = v),
      ),
      WizardSwitchTile(
        label: tr(_locale, 'services.tz.dizayn.montage_plan'),
        value: _draft.engineering.hasMontagePlan,
        onChanged: (v) => setState(() => _draft.engineering.hasMontagePlan = v),
      ),
      WizardSwitchTile(
        label: tr(_locale, 'services.tz.dizayn.gypsum_plan'),
        value: _draft.engineering.hasGypsumPlan,
        onChanged: (v) => setState(() => _draft.engineering.hasGypsumPlan = v),
      ),
      _schemaChipPicker(
        mapsTo: 'details.engineering.partition_material',
        label: tr(_locale, 'services.tz.dizayn.partition_label'),
        fallbackOptions: _partitionMaterials,
        fallbackLabelOf: (k) => _materialLabel(_locale, k),
        value: _draft.engineering.partitionMaterial,
        onChanged: (v) =>
            setState(() => _draft.engineering.partitionMaterial = v),
      ),
      _schemaChipPicker(
        mapsTo: 'details.engineering.air_conditioning',
        label: tr(_locale, 'services.tz.dizayn.air_conditioning'),
        fallbackOptions: _acTypes,
        fallbackLabelOf: (k) => _acLabel(_locale, k),
        value: _draft.engineering.airConditioning,
        onChanged: (v) =>
            setState(() => _draft.engineering.airConditioning = v),
      ),
      WizardSwitchTile(
        label: tr(_locale, 'services.tz.dizayn.fire_system'),
        value: _draft.engineering.hasFireSystem,
        onChanged: (v) => setState(() => _draft.engineering.hasFireSystem = v),
      ),
      WizardSwitchTile(
        label: tr(_locale, 'services.tz.dizayn.video_surveillance'),
        value: _draft.engineering.hasVideoSurveillance,
        onChanged: (v) =>
            setState(() => _draft.engineering.hasVideoSurveillance = v),
      ),
      WizardSwitchTile(
        label: tr(_locale, 'services.tz.dizayn.furniture_layout'),
        value: _draft.engineering.hasFurnitureLayout,
        onChanged: (v) =>
            setState(() => _draft.engineering.hasFurnitureLayout = v),
      ),
    ]);
  }

  // ── Step 6: Eksteryer dizayni ────────────────────────────────────────
  Widget _buildStep6() {
    return _scrollableStep([
      WizardSectionTitle(text: tr(_locale, 'services.tz.dizayn.exterior_design')),
      Builder(
        builder: (_) {
          final opts = _catalog('dizayn.exterior.style');
          return WizardChipPicker<String>(
            label: tr(_locale, 'services.tz.dizayn.style'),
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
            label: tr(_locale, 'services.tz.dizayn.exterior_material'),
            options: [for (final o in opts) o.value],
            labelOf: (k) => _catalogLabel(opts, k),
            value: _draft.exterior.exteriorMaterial,
            onChanged: (v) =>
                setState(() => _draft.exterior.exteriorMaterial = v),
          );
        },
      ),
      ColorPaletteField(
        label: tr(_locale, 'services.tz.dizayn.colors'),
        value: _draft.exterior.colors,
        onChanged: (v) =>
            _draft.exterior.colors = v.trim().isEmpty ? null : v.trim(),
      ),
      WizardSwitchTile(
        label: tr(_locale, 'services.tz.dizayn.parking'),
        value: _draft.exterior.hasParking,
        onChanged: (v) => setState(() => _draft.exterior.hasParking = v),
      ),
      if (_draft.exterior.hasParking)
        WizardField(
          label: tr(_locale, 'services.tz.dizayn.parking_spaces_count'),
          controller: _parkingCount,
          placeholder: '4',
          numericOnly: true,
        ),
      WizardSwitchTile(
        label: tr(_locale, 'services.tz.dizayn.paths'),
        value: _draft.exterior.hasPaths,
        onChanged: (v) => setState(() => _draft.exterior.hasPaths = v),
      ),
      WizardSwitchTile(
        label: tr(_locale, 'services.tz.dizayn.landscape_design'),
        value: _draft.exterior.hasLandscape,
        onChanged: (v) => setState(() => _draft.exterior.hasLandscape = v),
      ),
      WizardSwitchTile(
        label: tr(_locale, 'services.tz.dizayn.pool'),
        value: _draft.exterior.hasPool,
        onChanged: (v) => setState(() => _draft.exterior.hasPool = v),
      ),
      WizardSwitchTile(
        label: tr(_locale, 'services.tz.dizayn.area_lighting'),
        value: _draft.exterior.hasLighting,
        onChanged: (v) => setState(() => _draft.exterior.hasLighting = v),
      ),
    ]);
  }

  // ── Step 7: Muddatlar va izoh ────────────────────────────────────────
  Widget _buildStep7() {
    return _scrollableStep([
      WizardSectionTitle(text: tr(_locale, 'services.tz.dizayn.timeline')),
      Row(
        children: [
          Expanded(
            child: WizardField(
              label: tr(_locale, 'services.tz.dizayn.design_project'),
              controller: _designDays,
              placeholder: '30',
              suffix: tr(_locale, 'services.tz.dizayn.days_unit'),
              numericOnly: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: WizardField(
              label: tr(_locale, 'services.tz.dizayn.working_drawings'),
              controller: _workingDrawingsDays,
              placeholder: '20',
              suffix: tr(_locale, 'services.tz.dizayn.days_unit'),
              numericOnly: true,
            ),
          ),
        ],
      ),
      WizardSectionTitle(text: tr(_locale, 'services.tz.dizayn.additional_requirements')),
      WizardField(
        label: tr(_locale, 'services.tz.dizayn.notes'),
        controller: _notes,
        placeholder: tr(_locale, 'services.tz.dizayn.notes_placeholder'),
        maxLines: 5,
      ),
    ]);
  }

  // ── Preview / Tekshirish ─────────────────────────────────────────────
  // Yuborishdan oldin to'ldirilgan ma'lumotlarning umumiy ko'rinishi. Har
  // bo'lim qalamcha ("✎") orqali to'g'ridan-to'g'ri tahrirga ochiladi.
  Widget _buildPreview() {
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
      (tr(_locale, 'services.tz.dizayn.full_name_or_company'), d.customerName.trim()),
      if (d.tin.trim().isNotEmpty)
        (tr(_locale, 'services.tz.dizayn.tin_label'), d.tin.trim()),
      (tr(_locale, 'services.tz.dizayn.phone'), d.phone.trim()),
      if (d.email.trim().isNotEmpty) ('E-mail', d.email.trim()),
    ];

    // Step 1 — Obyekt va o'lchamlar
    final object = <(String, String)>[
      if (d.objectName.trim().isNotEmpty) (tr(_locale, 'services.tz.dizayn.object_name'), d.objectName.trim()),
      if (d.address.trim().isNotEmpty) (tr(_locale, 'services.tz.dizayn.address'), d.address.trim()),
      if (d.objectType != null)
        (tr(_locale, 'services.tz.dizayn.object_type_label'), _objectTypeLabel(d.objectType!, _locale)),
      (
        tr(_locale, 'services.tz.dizayn.design_type'),
        d.designType == DizDesignType.yangi
            ? tr(_locale, 'services.tz.dizayn.design_new')
            : tr(_locale, 'services.tz.dizayn.design_reconstruction'),
      ),
      if (d.floors != null) (tr(_locale, 'services.tz.dizayn.floors_count'), '${d.floors}'),
      if (d.roomsCount != null) (tr(_locale, 'services.tz.dizayn.rooms_count'), '${d.roomsCount}'),
      if (d.totalAreaSqm != null) (tr(_locale, 'services.tz.dizayn.total_area'), '${num(d.totalAreaSqm)} m²'),
      if (d.interiorAreaSqm != null)
        (tr(_locale, 'services.tz.dizayn.interior_area'), '${num(d.interiorAreaSqm)} m²'),
      if (d.designAreaSqm != null) (tr(_locale, 'services.tz.dizayn.design_area'), '${num(d.designAreaSqm)} m²'),
      if (d.ceilingHeightM != null)
        (tr(_locale, 'services.tz.dizayn.ceiling_height'), '${num(d.ceilingHeightM)} m'),
    ];
    final objectChips = <String>[
      if (d.hasBasement) tr(_locale, 'services.tz.dizayn.has_basement'),
      if (d.hasMansard) tr(_locale, 'services.tz.dizayn.has_mansard'),
    ];

    // Step 2 — Qo'shimcha xonalar
    final extra = <(String, String)>[
      if (d.extraRooms.trim().isNotEmpty)
        (tr(_locale, 'services.tz.dizayn.extra_rooms_label'), d.extraRooms.trim()),
    ];

    // Step 3 — Interyer
    final interior = <(String, String)>[
      if (d.interior.style != null)
        (tr(_locale, 'services.tz.dizayn.style'), _catalogLabel(interiorStyleOpts, d.interior.style)),
      if (d.interior.interiorMaterial != null)
        (
          tr(_locale, 'services.tz.dizayn.interior_material'),
          _catalogLabel(interiorMatOpts, d.interior.interiorMaterial),
        ),
      if (d.interior.floorMaterial != null)
        (
          tr(_locale, 'services.tz.dizayn.floor_material'),
          _catalogLabel(floorMatOpts, d.interior.floorMaterial),
        ),
      if ((d.interior.colors ?? '').trim().isNotEmpty)
        (tr(_locale, 'services.tz.dizayn.colors'), d.interior.colors!.trim()),
    ];
    final interiorChips = <String>[
      if (d.interior.has3dVisualization) tr(_locale, 'services.tz.dizayn.need_3d_visualization'),
      if (d.interior.hasWorkingDrawings) tr(_locale, 'services.tz.dizayn.project_working_drawings'),
      if (d.interior.hasAuthorSupervision) tr(_locale, 'services.tz.dizayn.author_supervision'),
    ];

    // Step 4 — Muhandislik
    final engineering = <(String, String)>[
      if (d.engineering.partitionMaterial != null)
        (tr(_locale, 'services.tz.dizayn.partition_label'), _materialLabel(_locale, d.engineering.partitionMaterial!)),
      if (d.engineering.airConditioning != null)
        (tr(_locale, 'services.tz.dizayn.air_conditioning'), _acLabel(_locale, d.engineering.airConditioning!)),
    ];
    final engineeringChips = <String>[
      if (d.engineering.hasElectricalDrawings) tr(_locale, 'services.tz.dizayn.electrical_drawings'),
      if (d.engineering.hasPlumbingDrawings) tr(_locale, 'services.tz.dizayn.plumbing_drawings'),
      if (d.engineering.hasDemolitionPlan) tr(_locale, 'services.tz.dizayn.demolition_plan'),
      if (d.engineering.hasMontagePlan) tr(_locale, 'services.tz.dizayn.montage_plan'),
      if (d.engineering.hasGypsumPlan) tr(_locale, 'services.tz.dizayn.gypsum_plan'),
      if (d.engineering.hasFireSystem) tr(_locale, 'services.tz.dizayn.fire_system'),
      if (d.engineering.hasVideoSurveillance) tr(_locale, 'services.tz.dizayn.video_surveillance'),
      if (d.engineering.hasFurnitureLayout) tr(_locale, 'services.tz.dizayn.furniture_layout'),
    ];

    // Step 5 — Eksteryer
    final exterior = <(String, String)>[
      if (d.exterior.style != null)
        (tr(_locale, 'services.tz.dizayn.style'), _catalogLabel(exteriorStyleOpts, d.exterior.style)),
      if (d.exterior.exteriorMaterial != null)
        (
          tr(_locale, 'services.tz.dizayn.exterior_material'),
          _catalogLabel(exteriorMatOpts, d.exterior.exteriorMaterial),
        ),
      if ((d.exterior.colors ?? '').trim().isNotEmpty)
        (tr(_locale, 'services.tz.dizayn.colors'), d.exterior.colors!.trim()),
    ];
    final exteriorChips = <String>[
      if (d.exterior.hasParking)
        '${tr(_locale, 'services.tz.dizayn.parking')}${d.exterior.parkingCount != null ? ' ×${d.exterior.parkingCount}' : ''}',
      if (d.exterior.hasPaths) tr(_locale, 'services.tz.dizayn.paths'),
      if (d.exterior.hasLandscape) tr(_locale, 'services.tz.dizayn.landscape_design'),
      if (d.exterior.hasPool) tr(_locale, 'services.tz.dizayn.pool'),
      if (d.exterior.hasLighting) tr(_locale, 'services.tz.dizayn.area_lighting'),
    ];

    // Step 6 — Muddatlar va izoh
    final timeline = <(String, String)>[
      if (d.timeline.designDays != null)
        (tr(_locale, 'services.tz.dizayn.design_project'), '${d.timeline.designDays} ${tr(_locale, 'services.tz.dizayn.days_unit')}'),
      if (d.timeline.workingDrawingsDays != null)
        (tr(_locale, 'services.tz.dizayn.working_drawings'), '${d.timeline.workingDrawingsDays} ${tr(_locale, 'services.tz.dizayn.days_unit')}'),
      if (d.notes.trim().isNotEmpty) (tr(_locale, 'services.tz.dizayn.notes'), d.notes.trim()),
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        Text(
          tr(_locale, 'services.tz.dizayn.review_intro'),
          style: TextStyle(
            fontFamily: 'MTSText',
            fontSize: 13,
            color: isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278),
          ),
        ),
        const SizedBox(height: 14),
        WizardReviewSection(
          title: tr(_locale, 'services.tz.dizayn.customer_details'),
          onEdit: () => _editStep(0),
          rows: customer,
          warning:
              (d.customerName.trim().length < 2 || d.phone.trim().length < 5)
              ? tr(_locale, 'services.tz.dizayn.fill_required_fields')
              : null,
        ),
        WizardReviewSection(
          title: tr(_locale, 'services.tz.dizayn.object_and_dimensions'),
          onEdit: () => _editStep(1),
          rows: object,
          chips: objectChips,
          warning: d.objectType == null ? tr(_locale, 'services.tz.dizayn.fill_required_fields') : null,
        ),
        WizardReviewSection(
          title: tr(_locale, 'services.tz.dizayn.extra_rooms_title'),
          onEdit: () => _editStep(2),
          rows: extra,
        ),
        WizardReviewSection(
          title: tr(_locale, 'services.tz.dizayn.interior_design'),
          onEdit: () => _editStep(3),
          rows: interior,
          chips: interiorChips,
        ),
        WizardReviewSection(
          title: tr(_locale, 'services.tz.dizayn.engineering_systems'),
          onEdit: () => _editStep(4),
          rows: engineering,
          chips: engineeringChips,
        ),
        WizardReviewSection(
          title: tr(_locale, 'services.tz.dizayn.exterior_design'),
          onEdit: () => _editStep(5),
          rows: exterior,
          chips: exteriorChips,
        ),
        WizardReviewSection(
          title: tr(_locale, 'services.tz.dizayn.timeline'),
          onEdit: () => _editStep(6),
          rows: timeline,
        ),
        if (!d.canSubmit) ...[
          const SizedBox(height: 4),
          Text(
            tr(_locale, 'services.tz.dizayn.fill_required_fields'),
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
  static String _objectTypeLabel(DizObjectType t, Locale l) {
    final key = switch (t) {
      DizObjectType.yakka => 'yakka',
      DizObjectType.kopQavatliKvartira => 'kop_qavatli',
      DizObjectType.savdoMarkazi => 'savdo_markazi',
      DizObjectType.ofis => 'ofis',
      DizObjectType.mehmonxona => 'mehmonxona',
      DizObjectType.sanoat => 'sanoat',
      DizObjectType.omborxona => 'omborxona',
      DizObjectType.boshqa => 'boshqa',
    };
    return tr(l, 'services.tz.dizayn.object_type.$key');
  }

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

// ── Kod → lokalizatsiyalangan label yordamchilari ──────────────────────
String _materialLabel(Locale l, String key) => switch (key) {
  'boyoq' => tr(l, 'services.tz.dizayn.material.boyoq'),
  'tosh' => tr(l, 'services.tz.dizayn.material.tosh'),
  'kompozit' => tr(l, 'services.tz.dizayn.material.kompozit'),
  'shisha' => tr(l, 'services.tz.dizayn.material.shisha'),
  'bambuk' => tr(l, 'services.tz.dizayn.material.bambuk'),
  'laminat' => tr(l, 'services.tz.dizayn.material.laminat'),
  'kafel' => tr(l, 'services.tz.dizayn.material.kafel'),
  'boshqa' => tr(l, 'services.tz.dizayn.material.boshqa'),
  'gisht' => tr(l, 'services.tz.dizayn.material.gisht'),
  'gipsokarton' => tr(l, 'services.tz.dizayn.material.gipsokarton'),
  'gazoblok' => tr(l, 'services.tz.dizayn.material.gazoblok'),
  _ => key,
};

String _acLabel(Locale l, String key) => switch (key) {
  'split' => 'Split',
  'vrf' => 'VRF',
  'chiller' => tr(l, 'services.tz.dizayn.ac.chiller'),
  _ => key,
};
