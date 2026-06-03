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

  Future<void> _submit() async {
    if (!_draft.canSubmit) {
      _showError('Majburiy maydonlarni to\'ldiring');
      return;
    }

    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null) {
      _showError('Buyurtma yuborish uchun avval tizimga kiring');
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
      _showError('Tarmoq xatosi: $e');
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
                        title: 'Dizayn TZ',
                        subtitle: _stepTitle(_stepIndex),
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
                            ? 'Yuborilmoqda…'
                            : (_isLastStep ? 'Yuborish' : 'Davom etish'),
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
      0 => '1/7 — Buyurtmachi',
      1 => '2/7 — Obyekt va o\'lchamlar',
      2 => '3/7 — Qo\'shimcha xonalar',
      3 => '4/7 — Interyer dizayni',
      4 => '5/7 — Muhandislik tizimlari',
      5 => '6/7 — Eksteryer dizayni',
      6 => '7/7 — Muddatlar va izoh',
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
      const WizardSectionTitle(text: 'Buyurtmachi rekvizitlari'),
      WizardField(
        label: 'F.I.SH yoki kompaniya nomi',
        controller: _customerName,
        placeholder: 'Ism Familiya',
        required: true,
      ),
      WizardField(
        label: 'STIR / INN',
        controller: _tin,
        placeholder: '300000000',
        numericOnly: true,
        maxLength: 14,
        errorText:
            _tinValid ? null : '9 (STIR) yoki 14 (INN) raqamdan iborat bo\'lsin',
      ),
      WizardField(
        label: 'Telefon',
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
    return _scrollableStep([
      const WizardSectionTitle(text: 'Obyekt va o\'lchamlar'),
      WizardField(
        label: 'Obyekt nomi',
        controller: _objectName,
        placeholder: 'Mening kvartiram',
      ),
      LocationPickerField(
        label: 'Manzil',
        value: _draft.location,
        onChanged: (loc) => setState(() {
          _draft.location = loc;
          if (loc.addressText != null) {
            _address.text = loc.addressText!;
          }
        }),
      ),
      WizardChipPicker<DizObjectType>(
        label: 'Obyekt turi',
        required: true,
        options: DizObjectType.values,
        labelOf: _objectTypeLabel,
        value: _draft.objectType,
        onChanged: (v) => setState(() => _draft.objectType = v),
      ),
      if (_draft.objectType == DizObjectType.boshqa)
        WizardField(
          label: 'Boshqa (qaysi turdagi)',
          controller: _objectSubtype,
          placeholder: 'Masalan: ko\'p funksiyali markaz',
        ),
      WizardChipPicker<DizDesignType>(
        label: 'Dizayn turi',
        options: DizDesignType.values,
        labelOf: (t) => t == DizDesignType.yangi ? 'Yangi' : 'Rekonstruksiya',
        value: _draft.designType,
        onChanged: (v) =>
            setState(() => _draft.designType = v ?? DizDesignType.yangi),
      ),
      Row(
        children: [
          Expanded(
            child: WizardField(
              label: 'Qavatlar soni',
              controller: _floors,
              placeholder: '1',
              numericOnly: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: WizardField(
              label: 'Xonalar soni',
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
              label: 'Umumiy maydon',
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
              label: 'Honalar balandligi',
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
              label: 'Interyer maydoni',
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
              label: 'Dizayn maydoni',
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
        label: 'Podval bo\'lsin',
        value: _draft.hasBasement,
        onChanged: (v) => setState(() => _draft.hasBasement = v),
      ),
      WizardSwitchTile(
        label: 'Mansarda bo\'lsin',
        value: _draft.hasMansard,
        onChanged: (v) => setState(() => _draft.hasMansard = v),
      ),
    ]);
  }

  // ── Step 3: Qo'shimcha xonalar ───────────────────────────────────────
  Widget _buildStep3() {
    return _scrollableStep([
      const WizardSectionTitle(text: 'Qo\'shimcha xonalar'),
      WizardField(
        label: 'Qo\'shimcha (boshqa) xonalar',
        controller: _extraRooms,
        placeholder: 'Masalan: ish kabineti, kiyim xonasi, kutubxona…',
        maxLines: 5,
      ),
    ]);
  }

  // ── Step 4: Interyer dizayni ─────────────────────────────────────────
  Widget _buildStep4() {
    return _scrollableStep([
      const WizardSectionTitle(text: 'Interyer dizayni'),
      WizardChipPicker<String>(
        label: 'Uslub',
        options: _interiorStyles,
        labelOf: (s) => _styleLabels[s] ?? s,
        value: _draft.interior.style,
        onChanged: (v) => setState(() => _draft.interior.style = v),
      ),
      WizardChipPicker<String>(
        label: 'Interyer materiali',
        options: _interiorMaterials,
        labelOf: (s) => _materialLabels[s] ?? s,
        value: _draft.interior.interiorMaterial,
        onChanged: (v) => setState(() => _draft.interior.interiorMaterial = v),
      ),
      WizardChipPicker<String>(
        label: 'Pol materiali',
        options: _floorMaterials,
        labelOf: (s) => _materialLabels[s] ?? s,
        value: _draft.interior.floorMaterial,
        onChanged: (v) => setState(() => _draft.interior.floorMaterial = v),
      ),
      ColorPaletteField(
        label: 'Ranglar',
        value: _draft.interior.colors,
        onChanged: (v) =>
            _draft.interior.colors = v.trim().isEmpty ? null : v.trim(),
      ),
      WizardSwitchTile(
        label: '3D vizualizatsiya kerak',
        value: _draft.interior.has3dVisualization,
        onChanged: (v) =>
            setState(() => _draft.interior.has3dVisualization = v),
      ),
      WizardSwitchTile(
        label: 'Loyihaning ishchi chizmalari',
        value: _draft.interior.hasWorkingDrawings,
        onChanged: (v) => setState(() => _draft.interior.hasWorkingDrawings = v),
      ),
      WizardSwitchTile(
        label: 'Mualliflik nazorati',
        value: _draft.interior.hasAuthorSupervision,
        onChanged: (v) =>
            setState(() => _draft.interior.hasAuthorSupervision = v),
      ),
    ]);
  }

  // ── Step 5: Muhandislik tizimlari ────────────────────────────────────
  Widget _buildStep5() {
    return _scrollableStep([
      const WizardSectionTitle(text: 'Muhandislik tizimlari'),
      WizardSwitchTile(
        label: 'Elektrika chizmalari',
        value: _draft.engineering.hasElectricalDrawings,
        onChanged: (v) =>
            setState(() => _draft.engineering.hasElectricalDrawings = v),
      ),
      WizardSwitchTile(
        label: 'Santexnika joylashuv chizmalari',
        value: _draft.engineering.hasPlumbingDrawings,
        onChanged: (v) =>
            setState(() => _draft.engineering.hasPlumbingDrawings = v),
      ),
      WizardSwitchTile(
        label: 'Demontaj devorlar bo\'linmasi',
        value: _draft.engineering.hasDemolitionPlan,
        onChanged: (v) =>
            setState(() => _draft.engineering.hasDemolitionPlan = v),
      ),
      WizardSwitchTile(
        label: 'Montaj devorlar bo\'linmasi',
        value: _draft.engineering.hasMontagePlan,
        onChanged: (v) => setState(() => _draft.engineering.hasMontagePlan = v),
      ),
      WizardSwitchTile(
        label: 'Gipsokarton bo\'linmalari va chizmalari',
        value: _draft.engineering.hasGypsumPlan,
        onChanged: (v) => setState(() => _draft.engineering.hasGypsumPlan = v),
      ),
      WizardChipPicker<String>(
        label: 'Honalar bo\'linmalari',
        options: _partitionMaterials,
        labelOf: (s) => _materialLabels[s] ?? s,
        value: _draft.engineering.partitionMaterial,
        onChanged: (v) =>
            setState(() => _draft.engineering.partitionMaterial = v),
      ),
      WizardChipPicker<String>(
        label: 'Konditsioner',
        options: _acTypes,
        labelOf: (s) => _acLabels[s] ?? s,
        value: _draft.engineering.airConditioning,
        onChanged: (v) =>
            setState(() => _draft.engineering.airConditioning = v),
      ),
      WizardSwitchTile(
        label: 'Yong\'in xavfsizligi tizimi',
        value: _draft.engineering.hasFireSystem,
        onChanged: (v) => setState(() => _draft.engineering.hasFireSystem = v),
      ),
      WizardSwitchTile(
        label: 'Videokuzatuv',
        value: _draft.engineering.hasVideoSurveillance,
        onChanged: (v) =>
            setState(() => _draft.engineering.hasVideoSurveillance = v),
      ),
      WizardSwitchTile(
        label: 'Mebellar joylashuvi',
        value: _draft.engineering.hasFurnitureLayout,
        onChanged: (v) =>
            setState(() => _draft.engineering.hasFurnitureLayout = v),
      ),
    ]);
  }

  // ── Step 6: Eksteryer dizayni ────────────────────────────────────────
  Widget _buildStep6() {
    return _scrollableStep([
      const WizardSectionTitle(text: 'Eksteryer dizayni'),
      WizardChipPicker<String>(
        label: 'Uslub',
        options: _exteriorStyles,
        labelOf: (s) => _styleLabels[s] ?? s,
        value: _draft.exterior.style,
        onChanged: (v) => setState(() => _draft.exterior.style = v),
      ),
      WizardChipPicker<String>(
        label: 'Eksteryer materiali',
        options: _exteriorMaterials,
        labelOf: (s) => _materialLabels[s] ?? s,
        value: _draft.exterior.exteriorMaterial,
        onChanged: (v) => setState(() => _draft.exterior.exteriorMaterial = v),
      ),
      ColorPaletteField(
        label: 'Ranglar',
        value: _draft.exterior.colors,
        onChanged: (v) =>
            _draft.exterior.colors = v.trim().isEmpty ? null : v.trim(),
      ),
      WizardSwitchTile(
        label: 'Avtoturargoh',
        value: _draft.exterior.hasParking,
        onChanged: (v) => setState(() => _draft.exterior.hasParking = v),
      ),
      if (_draft.exterior.hasParking)
        WizardField(
          label: 'Parking joylar soni',
          controller: _parkingCount,
          placeholder: '4',
          numericOnly: true,
        ),
      WizardSwitchTile(
        label: 'Yo\'laklar',
        value: _draft.exterior.hasPaths,
        onChanged: (v) => setState(() => _draft.exterior.hasPaths = v),
      ),
      WizardSwitchTile(
        label: 'Landshaft dizayni',
        value: _draft.exterior.hasLandscape,
        onChanged: (v) => setState(() => _draft.exterior.hasLandscape = v),
      ),
      WizardSwitchTile(
        label: 'Hovuz',
        value: _draft.exterior.hasPool,
        onChanged: (v) => setState(() => _draft.exterior.hasPool = v),
      ),
      WizardSwitchTile(
        label: 'Hudud yoritilishi',
        value: _draft.exterior.hasLighting,
        onChanged: (v) => setState(() => _draft.exterior.hasLighting = v),
      ),
    ]);
  }

  // ── Step 7: Muddatlar va izoh ────────────────────────────────────────
  Widget _buildStep7() {
    return _scrollableStep([
      const WizardSectionTitle(text: 'Muddatlar'),
      Row(
        children: [
          Expanded(
            child: WizardField(
              label: 'Dizayn loyiha',
              controller: _designDays,
              placeholder: '30',
              suffix: 'kun',
              numericOnly: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: WizardField(
              label: 'Ishchi chizmalar',
              controller: _workingDrawingsDays,
              placeholder: '20',
              suffix: 'kun',
              numericOnly: true,
            ),
          ),
        ],
      ),
      const WizardSectionTitle(text: 'Qo\'shimcha talablar'),
      WizardField(
        label: 'Izoh',
        controller: _notes,
        placeholder: 'Qo\'shimcha talab va izohlar…',
        maxLines: 5,
      ),
    ]);
  }

  // ── Label helpers ────────────────────────────────────────────────────
  static String _objectTypeLabel(DizObjectType t) => switch (t) {
        DizObjectType.yakka => 'Yakka tartibdagi uy',
        DizObjectType.kopQavatliKvartira => 'Ko\'p qavatli — kvartira',
        DizObjectType.savdoMarkazi => 'Savdo markazi',
        DizObjectType.ofis => 'Ofis',
        DizObjectType.mehmonxona => 'Mehmonxona',
        DizObjectType.sanoat => 'Sanoat',
        DizObjectType.omborxona => 'Omborxona',
        DizObjectType.boshqa => 'Boshqa',
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
  static const _styleLabels = {
    'high_tech': 'High-tech',
    'klassik': 'Klassik',
    'neoklassik': 'Neoklassik',
    'minimalizm': 'Minimalizm',
    'loft': 'Loft',
    'modern': 'Modern',
    'boshqa': 'Boshqa',
  };

  static const _interiorMaterials = ['boyoq', 'tosh', 'kompozit', 'shisha', 'bambuk'];
  static const _floorMaterials = ['laminat', 'tosh', 'kafel', 'boshqa'];
  static const _exteriorMaterials = ['boyoq', 'tosh', 'kompozit', 'shisha'];
  static const _partitionMaterials = ['gisht', 'gipsokarton', 'gazoblok'];
  static const _materialLabels = {
    'boyoq': 'Bo\'yoq',
    'tosh': 'Tosh',
    'kompozit': 'Kompozit panellar',
    'shisha': 'Shisha',
    'bambuk': 'Bambuk panellar',
    'laminat': 'Laminat',
    'kafel': 'Kafel',
    'boshqa': 'Boshqa',
    'gisht': 'G\'isht',
    'gipsokarton': 'Gipsokarton',
    'gazoblok': 'Gazoblok',
  };

  static const _acTypes = ['split', 'vrf', 'chiller'];
  static const _acLabels = {'split': 'Split', 'vrf': 'VRF', 'chiller': 'Chiller'};
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
