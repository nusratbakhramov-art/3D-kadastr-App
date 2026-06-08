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

import '../../../../theme/app_colors.dart';
import '../../../auth/auth_storage.dart';
import '../../../home/user_profile.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../api_architecture_order_service.dart';
import '../../api_cadastre_service.dart';
import '../../models/architecture_order_draft.dart';
import '../../widgets/cadastre_lookup_field.dart';
import '../../widgets/color_palette_field.dart';
import '../../widgets/location_picker_field.dart';
import '../../widgets/rooms_selector.dart';
import '../../widgets/service_app_bar.dart';
import '../../widgets/step_progress_bar.dart';
import '../../widgets/wizard_field.dart';
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
  static const int _stepCount = 9;

  late final ArchitectureOrderDraft _draft;
  late final PageController _pageController;
  int _stepIndex = 0;

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
  }

  void _onCtrlChanged() {
    if (mounted) setState(() {});
  }

  // Kadastr lookup natijasidan manzil va maydonni avtomatik to'ldiramiz.
  void _onCadastreResult(CadastreLookupResult r) {
    setState(() {
      if ((r.address ?? '').trim().isNotEmpty) {
        _address.text = r.address!.trim();
      }
      final area = r.totalArea ?? r.livingArea;
      if (area != null && area > 0) {
        _landUnit = 'm2';
        _totalArea.text = _trimNum(area);
      }
    });
  }

  static String _trimNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

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
      case 2:
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
                        count: _stepCount,
                        activeIndex: _stepIndex,
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
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: ListingCtaButton(
                        label: _submitting
                            ? _Strings.submitting(l)
                            : (_isLastStep
                                ? (widget.submitLabel ?? _defaultSubmitLabel(l))
                                : _Strings.continueLabel(l)),
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
      WizardField(
        label: _Strings.customerNameLabel(l),
        controller: _customerName,
        placeholder: 'Asliddin Hamrayev',
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

  // ── Step 2: Obyekt va manzil ─────────────────────────────────────────
  Widget _buildStep2(Locale l) {
    return _scrollableStep([
      WizardSectionTitle(text: _Strings.objectAndAddress(l)),
      WizardField(
        label: _Strings.objectNameLabel(l),
        controller: _objectName,
        placeholder: _Strings.objectNamePlaceholder(l),
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
      // Kadastr raqami — raqam kiritilsa, manzil va maydon avtomatik to'ladi.
      CadastreLookupField(
        controller: _cadastreNumber,
        label: _Strings.cadastreNumberLabel(l),
        onResult: _onCadastreResult,
      ),
      WizardField(
        label: _Strings.landAreaLabel(l),
        controller: _landArea,
        placeholder: '500',
        suffix: _landUnit == 'sotix' ? 'sotix' : _Strings.unitSqm(l),
        numericOnly: true,
        allowDecimal: true,
      ),
      WizardChipPicker<String>(
        label: _Strings.landUnitLabel(l),
        options: const ['m2', 'sotix'],
        labelOf: (s) => s == 'sotix' ? 'sotix' : _Strings.unitSqm(l),
        value: _landUnit,
        onChanged: (v) => setState(() => _landUnit = v ?? 'm2'),
      ),
      WizardField(
        label: _Strings.landUsePurposeLabel(l),
        controller: _landUsePurpose,
        placeholder: _Strings.landUsePurposePlaceholder(l),
      ),
    ]);
  }

  // ── Step 3: Loyiha haqida ────────────────────────────────────────────
  Widget _buildStep3(Locale l) {
    return _scrollableStep([
      WizardSectionTitle(text: _Strings.projectGeneralInfo(l)),
      WizardChipPicker<ArchObjectType>(
        label: _Strings.objectTypeLabel(l),
        required: true,
        options: ArchObjectType.values,
        labelOf: (t) => _objectTypeLabel(t, l),
        value: _draft.objectType,
        onChanged: (v) => setState(() => _draft.objectType = v),
      ),
      if (_draft.objectType == ArchObjectType.boshqa)
        WizardField(
          label: _Strings.objectSubtypeLabel(l),
          controller: _objectSubtype,
          placeholder: _Strings.objectSubtypePlaceholder(l),
        ),
      WizardChipPicker<ConstructionType>(
        label: _Strings.constructionTypeLabel(l),
        options: ConstructionType.values,
        labelOf: (t) => t == ConstructionType.yangi
            ? _Strings.constructionNew(l)
            : _Strings.constructionReconstruction(l),
        value: _draft.constructionType,
        onChanged: (v) =>
            setState(() => _draft.constructionType = v ?? ConstructionType.yangi),
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
    return _scrollableStep([
      WizardSectionTitle(text: _Strings.architectureAndDesign(l)),
      WizardChipPicker<String>(
        label: _Strings.styleLabel(l),
        options: const [
          'high_tech',
          'klassik',
          'neoklassik',
          'minimalizm',
          'loft',
        ],
        labelOf: (s) => _designStyleLabel(s, l),
        value: _draft.architecture.style,
        onChanged: (v) => setState(() => _draft.architecture.style = v),
      ),
      WizardChipPicker<String>(
        label: _Strings.facadeMaterialLabel(l),
        options: const ['gisht', 'tosh', 'kompozit', 'shisha', 'boyoq'],
        labelOf: (s) => _facadeMaterialLabel(s, l),
        value: _draft.architecture.facadeMaterial,
        onChanged: (v) =>
            setState(() => _draft.architecture.facadeMaterial = v),
      ),
      ColorPaletteField(
        label: _Strings.colorsLabel(l),
        value: _draft.architecture.colors,
        onChanged: (v) =>
            _draft.architecture.colors = v.trim().isEmpty ? null : v.trim(),
      ),
      WizardSwitchTile(
        label: _Strings.need3dVisualization(l),
        value: _draft.architecture.has3dVisualization,
        onChanged: (v) =>
            setState(() => _draft.architecture.has3dVisualization = v),
      ),
    ]);
  }

  // ── Step 6: Konstruktiv yechimlar ────────────────────────────────────
  Widget _buildStep6(Locale l) {
    return _scrollableStep([
      WizardSectionTitle(text: _Strings.constructiveSolutions(l)),
      WizardChipPicker<String>(
        label: _Strings.constructiveSchemeLabel(l),
        options: const ['karkas', 'monolit', 'gisht', 'aralash', 'metall'],
        labelOf: (s) => switch (s) {
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
      WizardChipPicker<String>(
        label: _Strings.foundationLabel(l),
        options: const ['ustun', 'lenta', 'plita', 'svay'],
        labelOf: (s) => switch (s) {
          'ustun' => _Strings.foundationColumn(l),
          'lenta' => _Strings.foundationStrip(l),
          'plita' => _Strings.foundationSlab(l),
          'svay' => _Strings.foundationPile(l),
          _ => s,
        },
        value: _draft.constructive.foundation,
        onChanged: (v) => setState(() => _draft.constructive.foundation = v),
      ),
      WizardChipPicker<String>(
        label: _Strings.wallMaterialLabel(l),
        options: const ['gisht', 'gazoblok', 'beton', 'sendvich_panel'],
        labelOf: (s) => switch (s) {
          'gisht' => _Strings.materialBrick(l),
          'gazoblok' => _Strings.materialAerocrete(l),
          'beton' => _Strings.materialConcrete(l),
          'sendvich_panel' => _Strings.materialSandwichPanel(l),
          _ => s,
        },
        value: _draft.constructive.walls,
        onChanged: (v) => setState(() => _draft.constructive.walls = v),
      ),
      WizardChipPicker<String>(
        label: _Strings.ceilingLabel(l),
        options: const ['temir_beton', 'yogoch', 'metall'],
        labelOf: (s) => switch (s) {
          'temir_beton' => _Strings.ceilingReinforcedConcrete(l),
          'yogoch' => _Strings.materialWood(l),
          'metall' => _Strings.materialMetal(l),
          _ => s,
        },
        value: _draft.constructive.ceiling,
        onChanged: (v) => setState(() => _draft.constructive.ceiling = v),
      ),
      WizardChipPicker<String>(
        label: _Strings.roofTypeLabel(l),
        options: const ['yassi', 'qiya'],
        labelOf: (s) =>
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
    return _scrollableStep([
      WizardSectionTitle(text: _Strings.engineeringSystems(l)),
      WizardSwitchTile(
        label: _Strings.backupGenerator(l),
        value: _draft.engineering.hasGenerator,
        onChanged: (v) => setState(() => _draft.engineering.hasGenerator = v),
      ),
      WizardChipPicker<String>(
        label: _Strings.waterSourceLabel(l),
        options: const ['markaziy', 'quduq'],
        labelOf: (s) =>
            s == 'markaziy' ? _Strings.central(l) : _Strings.well(l),
        value: _draft.engineering.waterSource,
        onChanged: (v) => setState(() => _draft.engineering.waterSource = v),
      ),
      WizardChipPicker<String>(
        label: _Strings.sewageLabel(l),
        options: const ['markaziy', 'septik'],
        labelOf: (s) =>
            s == 'markaziy' ? _Strings.central(l) : _Strings.septic(l),
        value: _draft.engineering.sewage,
        onChanged: (v) => setState(() => _draft.engineering.sewage = v),
      ),
      WizardChipPicker<String>(
        label: _Strings.heatingLabel(l),
        options: const ['gaz', 'elektr', 'qozonxona'],
        labelOf: (s) => switch (s) {
          'gaz' => _Strings.heatingGas(l),
          'elektr' => _Strings.heatingElectric(l),
          'qozonxona' => _Strings.heatingBoiler(l),
          _ => s,
        },
        value: _draft.engineering.heating,
        onChanged: (v) => setState(() => _draft.engineering.heating = v),
      ),
      WizardChipPicker<String>(
        label: _Strings.ventilationLabel(l),
        options: const ['tabiiy', 'mexanik'],
        labelOf: (s) => s == 'tabiiy'
            ? _Strings.ventilationNatural(l)
            : _Strings.ventilationMechanical(l),
        value: _draft.engineering.ventilation,
        onChanged: (v) => setState(() => _draft.engineering.ventilation = v),
      ),
      WizardChipPicker<String>(
        label: _Strings.airConditioningLabel(l),
        options: const ['split', 'vrf', 'chiller'],
        labelOf: (s) => switch (s) {
          'split' => 'Split',
          'vrf' => 'VRF',
          'chiller' => 'Chiller',
          _ => s,
        },
        value: _draft.engineering.airConditioning,
        onChanged: (v) =>
            setState(() => _draft.engineering.airConditioning = v),
      ),
      WizardSwitchTile(
        label: _Strings.fireSafetySystem(l),
        value: _draft.engineering.hasFireSystem,
        onChanged: (v) => setState(() => _draft.engineering.hasFireSystem = v),
      ),
      WizardSwitchTile(
        label: _Strings.alarmSystem(l),
        value: _draft.engineering.hasAlarm,
        onChanged: (v) => setState(() => _draft.engineering.hasAlarm = v),
      ),
      WizardSwitchTile(
        label: _Strings.videoSurveillance(l),
        value: _draft.engineering.hasVideoSurveillance,
        onChanged: (v) =>
            setState(() => _draft.engineering.hasVideoSurveillance = v),
      ),
      WizardSwitchTile(
        label: _Strings.solarPanels(l),
        value: _draft.engineering.hasSolarPanels,
        onChanged: (v) =>
            setState(() => _draft.engineering.hasSolarPanels = v),
      ),
    ]);
  }

  // ── Step 8: Hudud rejalashtirish ─────────────────────────────────────
  Widget _buildStep8(Locale l) {
    return _scrollableStep([
      WizardSectionTitle(text: _Strings.territoryPlanning(l)),
      WizardSwitchTile(
        label: _Strings.parking(l),
        value: _draft.territory.hasParking,
        onChanged: (v) => setState(() => _draft.territory.hasParking = v),
      ),
      if (_draft.territory.hasParking)
        WizardField(
          label: _Strings.parkingSpacesLabel(l),
          controller: _parkingCount,
          placeholder: '4',
          numericOnly: true,
        ),
      WizardSwitchTile(
        label: _Strings.walkways(l),
        value: _draft.territory.hasPaths,
        onChanged: (v) => setState(() => _draft.territory.hasPaths = v),
      ),
      WizardSwitchTile(
        label: _Strings.landscapeDesign(l),
        value: _draft.territory.hasLandscape,
        onChanged: (v) => setState(() => _draft.territory.hasLandscape = v),
      ),
      WizardSwitchTile(
        label: _Strings.pool(l),
        value: _draft.territory.hasPool,
        onChanged: (v) => setState(() => _draft.territory.hasPool = v),
      ),
      WizardSwitchTile(
        label: _Strings.territoryLighting(l),
        value: _draft.territory.hasLighting,
        onChanged: (v) => setState(() => _draft.territory.hasLighting = v),
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

  static String _objectTypeLabel(ArchObjectType t, Locale l) {
    final ru = l.languageCode == 'ru';
    final en = l.languageCode == 'en';
    return switch (t) {
      ArchObjectType.yakkaSmall => ru
          ? 'Частный дом <500 m²'
          : en
              ? 'Single house <500 m²'
              : 'Yakka uy <500 m²',
      ArchObjectType.yakkaLarge => ru
          ? 'Частный дом >500 m²'
          : en
              ? 'Single house >500 m²'
              : 'Yakka uy >500 m²',
      ArchObjectType.kopQavatli => ru
          ? 'Многоэтажное жильё'
          : en
              ? 'Multi-storey residential'
              : 'Ko\'p qavatli turar-joy',
      ArchObjectType.ofis => ru
          ? 'Офис'
          : en
              ? 'Office'
              : 'Ofis',
      ArchObjectType.savdoMarkazi => ru
          ? 'Торговый центр'
          : en
              ? 'Shopping mall'
              : 'Savdo markazi',
      ArchObjectType.mehmonxona => ru
          ? 'Гостиница'
          : en
              ? 'Hotel'
              : 'Mehmonxona',
      ArchObjectType.sanoat => ru
          ? 'Промышленный'
          : en
              ? 'Industrial'
              : 'Sanoat',
      ArchObjectType.omborxona => ru
          ? 'Склад'
          : en
              ? 'Warehouse'
              : 'Omborxona',
      ArchObjectType.boshqa => ru
          ? 'Другое'
          : en
              ? 'Other'
              : 'Boshqa',
    };
  }

  static String _designStyleLabel(String s, Locale l) => switch (s) {
        'high_tech' => 'High-tech',
        'klassik' => switch (l.languageCode) {
            'ru' => 'Классика',
            'en' => 'Classic',
            _ => 'Klassik',
          },
        'neoklassik' => switch (l.languageCode) {
            'ru' => 'Неоклассика',
            'en' => 'Neoclassic',
            _ => 'Neoklassik',
          },
        'minimalizm' => switch (l.languageCode) {
            'ru' => 'Минимализм',
            'en' => 'Minimalism',
            _ => 'Minimalizm',
          },
        'loft' => 'Loft',
        _ => s,
      };

  static String _facadeMaterialLabel(String s, Locale l) => switch (s) {
        'gisht' => _Strings.materialBrick(l),
        'tosh' => switch (l.languageCode) {
            'ru' => 'Камень',
            'en' => 'Stone',
            _ => 'Tosh',
          },
        'kompozit' => switch (l.languageCode) {
            'ru' => 'Композитные панели',
            'en' => 'Composite panels',
            _ => 'Kompozit panellar',
          },
        'shisha' => switch (l.languageCode) {
            'ru' => 'Стекло',
            'en' => 'Glass',
            _ => 'Shisha',
          },
        'boyoq' => switch (l.languageCode) {
            'ru' => 'Фасадные краски',
            'en' => 'Facade paints',
            _ => 'Fasad bo\'yoqlari',
          },
        _ => s,
      };

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

  static String submit(Locale l) => switch (l.languageCode) {
        'ru' => 'Отправить',
        'en' => 'Submit',
        _ => 'Yuborish',
      };

  static String archTz(Locale l) => switch (l.languageCode) {
        'ru' => 'Архитектурное ТЗ',
        'en' => 'Architecture TZ',
        _ => 'Arxitektura TZ',
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
        'ru' => 'СТИР / ИНН',
        'en' => 'TIN',
        _ => 'STIR / INN',
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

  static String landUnitLabel(Locale l) => switch (l.languageCode) {
        'ru' => 'Единица измерения',
        'en' => 'Unit',
        _ => 'O\'lchov birligi',
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

  static String landUsePurposePlaceholder(Locale l) =>
      switch (l.languageCode) {
        'ru' => 'жилая / производственная',
        'en' => 'residential / production',
        _ => 'turar joy / ishlab chiqarish',
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

  static String objectSubtypePlaceholder(Locale l) =>
      switch (l.languageCode) {
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

  static String ceilingReinforcedConcrete(Locale l) =>
      switch (l.languageCode) {
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
