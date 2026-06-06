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

import '../../../../theme/app_colors.dart';
import '../../../auth/auth_storage.dart';
import '../../../home/user_profile.dart';
import '../../../settings/settings_state.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../api_design_order_service.dart';
import '../../models/design_order_draft.dart';
import '../../widgets/service_app_bar.dart';
import '../../widgets/step_progress_bar.dart';
import '../../widgets/color_palette_field.dart';
import '../../widgets/location_picker_field.dart';
import '../../widgets/wizard_field.dart';
import 'arxitektura_tz_success_screen.dart';

class DizaynTzWizardScreen extends StatefulWidget {
  const DizaynTzWizardScreen({super.key, this.initialDraft});

  /// Kalkulator natijasidan oldindan to'ldirilgan draft.
  final DizaynOrderDraft? initialDraft;

  @override
  State<DizaynTzWizardScreen> createState() => _DizaynTzWizardScreenState();
}

class _DizaynTzWizardScreenState extends State<DizaynTzWizardScreen> {
  static const int _stepCount = 7;

  late final DizaynOrderDraft _draft;
  late final PageController _pageController;
  int _stepIndex = 0;

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

  // Gating controllerlar (validatsiyaga ta'sir qiladi) — bularga listener
  // qo'shamiz, shunda "Davom etish" tugmasi har doim sinxron bo'ladi.
  late final List<TextEditingController> _gating = [_customerName, _tin, _phone];

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
    _roomsCount =
        TextEditingController(text: _draft.roomsCount?.toString() ?? '');
    _totalArea =
        TextEditingController(text: _draft.totalAreaSqm?.toString() ?? '');
    _interiorArea =
        TextEditingController(text: _draft.interiorAreaSqm?.toString() ?? '');
    _designArea =
        TextEditingController(text: _draft.designAreaSqm?.toString() ?? '');
    _ceilingHeight =
        TextEditingController(text: _draft.ceilingHeightM?.toString() ?? '');

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
  bool get _tinValid {
    final t = _tin.text.trim();
    return t.isEmpty || t.length == 9 || t.length == 14;
  }

  // ── Validatsiya per-step ─────────────────────────────────────────────
  bool get _canAdvance {
    switch (_stepIndex) {
      case 0:
        return _customerName.text.trim().length >= 2 &&
            _phone.text.trim().length >= 5 &&
            _tinValid;
      case 1:
        return _draft.objectType != null;
      default:
        return true;
    }
  }

  bool get _isLastStep => _stepIndex == _stepCount - 1;

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

  Future<void> _next() async {
    _syncDraftFromControllers();
    if (!_canAdvance) return;
    HapticFeedback.lightImpact();

    if (_isLastStep) {
      await _submit();
      return;
    }

    setState(() => _stepIndex++);
    _pageController.animateToPage(
      _stepIndex,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  void _back() {
    if (_stepIndex == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _stepIndex--);
    _pageController.animateToPage(
      _stepIndex,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  Locale get _locale =>
      Localizations.maybeLocaleOf(context) ?? localeNotifier.value;

  Future<void> _submit() async {
    final s = _Strings(_locale);
    if (!_draft.canSubmit) {
      _showError(s.fillRequiredFields);
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFFE0492A)),
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
                        count: _stepCount,
                        activeIndex: _stepIndex,
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
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: ListingCtaButton(
                        label: _submitting
                            ? s.submitting
                            : (_isLastStep ? s.submit : s.continueLabel),
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
      WizardField(
        label: s.fullNameOrCompany,
        controller: _customerName,
        placeholder: s.namePlaceholder,
        required: true,
      ),
      WizardField(
        label: 'STIR / INN',
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
        required: true,
      ),
      WizardField(
        label: 'E-mail',
        controller: _email,
        placeholder: 'sample@mail.com',
        keyboardType: TextInputType.emailAddress,
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
        labelOf: (t) => _objectTypeLabel(t, s),
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
        labelOf: (t) =>
            t == DizDesignType.yangi ? s.designNew : s.designReconstruction,
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
      WizardChipPicker<String>(
        label: s.style,
        options: _interiorStyles,
        labelOf: (k) => s.styleLabel(k),
        value: _draft.interior.style,
        onChanged: (v) => setState(() => _draft.interior.style = v),
      ),
      WizardChipPicker<String>(
        label: s.interiorMaterial,
        options: _interiorMaterials,
        labelOf: (k) => s.materialLabel(k),
        value: _draft.interior.interiorMaterial,
        onChanged: (v) => setState(() => _draft.interior.interiorMaterial = v),
      ),
      WizardChipPicker<String>(
        label: s.floorMaterial,
        options: _floorMaterials,
        labelOf: (k) => s.materialLabel(k),
        value: _draft.interior.floorMaterial,
        onChanged: (v) => setState(() => _draft.interior.floorMaterial = v),
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
        onChanged: (v) => setState(() => _draft.interior.hasWorkingDrawings = v),
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
      WizardChipPicker<String>(
        label: s.partitionLabel,
        options: _partitionMaterials,
        labelOf: (k) => s.materialLabel(k),
        value: _draft.engineering.partitionMaterial,
        onChanged: (v) =>
            setState(() => _draft.engineering.partitionMaterial = v),
      ),
      WizardChipPicker<String>(
        label: s.airConditioning,
        options: _acTypes,
        labelOf: (k) => s.acLabel(k),
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
      WizardChipPicker<String>(
        label: s.style,
        options: _exteriorStyles,
        labelOf: (k) => s.styleLabel(k),
        value: _draft.exterior.style,
        onChanged: (v) => setState(() => _draft.exterior.style = v),
      ),
      WizardChipPicker<String>(
        label: s.exteriorMaterial,
        options: _exteriorMaterials,
        labelOf: (k) => s.materialLabel(k),
        value: _draft.exterior.exteriorMaterial,
        onChanged: (v) => setState(() => _draft.exterior.exteriorMaterial = v),
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

  static const _interiorStyles = [
    'high_tech',
    'klassik',
    'neoklassik',
    'minimalizm',
    'loft',
    'boshqa',
  ];
  static const _exteriorStyles = [
    'high_tech',
    'klassik',
    'neoklassik',
    'minimalizm',
    'loft',
    'modern',
  ];

  static const _interiorMaterials = ['boyoq', 'tosh', 'kompozit', 'shisha', 'bambuk'];
  static const _floorMaterials = ['laminat', 'tosh', 'kafel', 'boshqa'];
  static const _exteriorMaterials = ['boyoq', 'tosh', 'kompozit', 'shisha'];
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

  String _s(String ru, String en, String uz) =>
      switch (locale.languageCode) { 'ru' => ru, 'en' => en, _ => uz };

  // App bar / navigatsiya / tugmalar
  String get appBarTitle => _s('Дизайн ТЗ', 'Design TZ', 'Dizayn TZ');
  String get continueLabel => _s('Продолжить', 'Continue', 'Davom etish');
  String get submit => _s('Отправить', 'Submit', 'Yuborish');
  String get submitting => _s('Отправка…', 'Submitting…', 'Yuborilmoqda…');

  // Step crumbs
  String get crumbCustomer => _s('Заказчик', 'Customer', 'Buyurtmachi');
  String get crumbObject =>
      _s('Объект и размеры', 'Object and dimensions', 'Obyekt va o\'lchamlar');
  String get crumbExtraRooms =>
      _s('Доп. комнаты', 'Extra rooms', 'Qo\'shimcha xonalar');
  String get crumbInterior =>
      _s('Дизайн интерьера', 'Interior design', 'Interyer dizayni');
  String get crumbEngineering => _s(
      'Инженерные системы', 'Engineering systems', 'Muhandislik tizimlari');
  String get crumbExterior =>
      _s('Дизайн экстерьера', 'Exterior design', 'Eksteryer dizayni');
  String get crumbTimeline =>
      _s('Сроки и комментарий', 'Timeline and comment', 'Muddatlar va izoh');

  // Snackbar / validatsiya
  String get fillRequiredFields => _s('Заполните обязательные поля',
      'Fill in the required fields', 'Majburiy maydonlarni to\'ldiring');
  String get signInFirst => _s(
      'Чтобы отправить заявку, сначала войдите в систему',
      'Please sign in first to submit the order',
      'Buyurtma yuborish uchun avval tizimga kiring');
  String get networkError =>
      _s('Сетевая ошибка', 'Network error', 'Tarmoq xatosi');

  // Step 1: Buyurtmachi
  String get customerDetails =>
      _s('Реквизиты заказчика', 'Customer details', 'Buyurtmachi rekvizitlari');
  String get fullNameOrCompany => _s('Ф.И.О или название компании',
      'Full name or company name', 'F.I.SH yoki kompaniya nomi');
  String get namePlaceholder =>
      _s('Имя Фамилия', 'First name Last name', 'Ism Familiya');
  String get tinError => _s(
      '9 (СТИР) или 14 (ИНН) цифр',
      'Must be 9 (STIR) or 14 (INN) digits',
      '9 (STIR) yoki 14 (INN) raqamdan iborat bo\'lsin');
  String get phone => _s('Телефон', 'Phone', 'Telefon');

  // Step 2: Obyekt va o'lchamlar
  String get objectAndDimensions =>
      _s('Объект и размеры', 'Object and dimensions', 'Obyekt va o\'lchamlar');
  String get objectName => _s('Название объекта', 'Object name', 'Obyekt nomi');
  String get objectNamePlaceholder =>
      _s('Моя квартира', 'My apartment', 'Mening kvartiram');
  String get address => _s('Адрес', 'Address', 'Manzil');
  String get objectType => _s('Тип объекта', 'Object type', 'Obyekt turi');
  String get otherWhichType => _s(
      'Другое (какого типа)', 'Other (which type)', 'Boshqa (qaysi turdagi)');
  String get otherTypePlaceholder => _s('Например: многофункциональный центр',
      'E.g.: multi-functional center', 'Masalan: ko\'p funksiyali markaz');
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
  String get hasBasement => _s('С подвалом', 'With basement', 'Podval bo\'lsin');
  String get hasMansard => _s('С мансардой', 'With mansard', 'Mansarda bo\'lsin');

  // Object type labels
  String get objTypeYakka => _s(
      'Индивидуальный дом', 'Detached house', 'Yakka tartibdagi uy');
  String get objTypeKopQavatli => _s('Многоэтажка — квартира',
      'Multi-storey — apartment', 'Ko\'p qavatli — kvartira');
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
  String get extraRoomsLabel => _s('Дополнительные (другие) комнаты',
      'Additional (other) rooms', 'Qo\'shimcha (boshqa) xonalar');
  String get extraRoomsPlaceholder => _s(
      'Например: кабинет, гардеробная, библиотека…',
      'E.g.: office, dressing room, library…',
      'Masalan: ish kabineti, kiyim xonasi, kutubxona…');

  // Step 4: Interyer dizayni
  String get interiorDesign =>
      _s('Дизайн интерьера', 'Interior design', 'Interyer dizayni');
  String get style => _s('Стиль', 'Style', 'Uslub');
  String get interiorMaterial => _s(
      'Материал интерьера', 'Interior material', 'Interyer materiali');
  String get floorMaterial =>
      _s('Материал пола', 'Floor material', 'Pol materiali');
  String get colors => _s('Цвета', 'Colors', 'Ranglar');
  String get need3dVisualization => _s('Нужна 3D-визуализация',
      '3D visualization needed', '3D vizualizatsiya kerak');
  String get projectWorkingDrawings => _s('Рабочие чертежи проекта',
      'Project working drawings', 'Loyihaning ishchi chizmalari');
  String get authorSupervision =>
      _s('Авторский надзор', 'Author supervision', 'Mualliflik nazorati');

  // Step 5: Muhandislik tizimlari
  String get engineeringSystems => _s(
      'Инженерные системы', 'Engineering systems', 'Muhandislik tizimlari');
  String get electricalDrawings => _s(
      'Чертежи электрики', 'Electrical drawings', 'Elektrika chizmalari');
  String get plumbingDrawings => _s('Чертежи разводки сантехники',
      'Plumbing layout drawings', 'Santexnika joylashuv chizmalari');
  String get demolitionPlan => _s('Раздел демонтажа стен',
      'Wall demolition section', 'Demontaj devorlar bo\'linmasi');
  String get montagePlan => _s('Раздел монтажа стен',
      'Wall montage section', 'Montaj devorlar bo\'linmasi');
  String get gypsumPlan => _s('Разделы и чертежи гипсокартона',
      'Gypsum board sections and drawings',
      'Gipsokarton bo\'linmalari va chizmalari');
  String get partitionLabel => _s('Перегородки комнат',
      'Room partitions', 'Honalar bo\'linmalari');
  String get airConditioning =>
      _s('Кондиционер', 'Air conditioning', 'Konditsioner');
  String get fireSystem => _s('Система пожарной безопасности',
      'Fire safety system', 'Yong\'in xavfsizligi tizimi');
  String get videoSurveillance =>
      _s('Видеонаблюдение', 'Video surveillance', 'Videokuzatuv');
  String get furnitureLayout => _s('Расстановка мебели',
      'Furniture layout', 'Mebellar joylashuvi');

  // Step 6: Eksteryer dizayni
  String get exteriorDesign =>
      _s('Дизайн экстерьера', 'Exterior design', 'Eksteryer dizayni');
  String get exteriorMaterial => _s(
      'Материал экстерьера', 'Exterior material', 'Eksteryer materiali');
  String get parking => _s('Автостоянка', 'Parking', 'Avtoturargoh');
  String get parkingSpacesCount => _s('Количество парковочных мест',
      'Number of parking spaces', 'Parking joylar soni');
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
  String get additionalRequirements => _s('Дополнительные требования',
      'Additional requirements', 'Qo\'shimcha talablar');
  String get notes => _s('Комментарий', 'Comment', 'Izoh');
  String get notesPlaceholder => _s(
      'Дополнительные требования и комментарии…',
      'Additional requirements and comments…',
      'Qo\'shimcha talab va izohlar…');

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
        'kompozit' =>
          _s('Композитные панели', 'Composite panels', 'Kompozit panellar'),
        'shisha' => _s('Стекло', 'Glass', 'Shisha'),
        'bambuk' =>
          _s('Бамбуковые панели', 'Bamboo panels', 'Bambuk panellar'),
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
