/// Arxitektura va qurilish loyihasi uchun TZ wizard.
///
/// 7 step:
///   1. Buyurtmachi rekvizitlari
///   2. Obyekt + manzil + kadastr
///   3. Loyiha umumiy + xonalar tarkibi
///   4. Arxitektura va dizayn
///   5. Konstruktiv yechimlar
///   6. Muhandislik tizimlari
///   7. Hudud + muddatlar + qo'shimcha
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../theme/app_colors.dart';
import '../../../auth/auth_storage.dart';
import '../../../home/user_profile.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../api_architecture_order_service.dart';
import '../../models/architecture_order_draft.dart';
import '../../widgets/service_app_bar.dart';
import '../../widgets/step_progress_bar.dart';
import '../../widgets/wizard_field.dart';
import 'arxitektura_tz_success_screen.dart';

class ArxitekturaTzWizardScreen extends StatefulWidget {
  const ArxitekturaTzWizardScreen({
    super.key,
    this.initialDraft,
    this.onSubmit,
    this.submitLabel,
  });

  final ArchitectureOrderDraft? initialDraft;

  /// Yakuniy step'da (oxirgi sahifada) "Yuborish" o'rniga chaqirilsin —
  /// agar berilsa, draft backend'ga yuborilmaydi va callback'ga o'tkaziladi.
  /// Bu 3D kadastr flow'i kabi embedded ishlatishlar uchun.
  final void Function(ArchitectureOrderDraft draft)? onSubmit;

  /// Oxirgi step tugmasi yorlig'i (default: "Yuborish").
  final String? submitLabel;

  @override
  State<ArxitekturaTzWizardScreen> createState() =>
      _ArxitekturaTzWizardScreenState();
}

class _ArxitekturaTzWizardScreenState extends State<ArxitekturaTzWizardScreen> {
  static const int _stepCount = 7;

  late final ArchitectureOrderDraft _draft;
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
  late final TextEditingController _cadastreNumber;
  late final TextEditingController _landArea;
  late final TextEditingController _landUsePurpose;

  // Step 3
  late final TextEditingController _floors;
  late final TextEditingController _totalArea;
  late final TextEditingController _buildingArea;
  late final TextEditingController _maxHeight;
  late final TextEditingController _objectSubtype;

  // Step 4
  late final TextEditingController _colors;

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

    _colors = TextEditingController(text: _draft.architecture.colors ?? '');
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

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in [
      _customerName,
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
      _colors,
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

  // ── Validatsiya per-step ─────────────────────────────────────────────
  bool get _canAdvance {
    switch (_stepIndex) {
      case 0:
        return _customerName.text.trim().length >= 2 &&
            _phone.text.trim().length >= 5;
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
    _draft.landAreaSqm = _parseDouble(_landArea.text);
    _draft.landUsePurpose = _landUsePurpose.text;

    _draft.floors = _parseInt(_floors.text);
    _draft.totalAreaSqm = _parseDouble(_totalArea.text);
    _draft.buildingAreaSqm = _parseDouble(_buildingArea.text);
    _draft.maxHeightM = _parseDouble(_maxHeight.text);
    _draft.objectSubtype = _objectSubtype.text;

    _draft.architecture.colors =
        _colors.text.trim().isEmpty ? null : _colors.text.trim();
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
    if (!_draft.canSubmit) {
      _showError('Majburiy maydonlarni to\'ldiring');
      return;
    }

    // Embedded mode: callback'ga uzatamiz (3D kadastr/AI baholash flow'lari).
    if (widget.onSubmit != null) {
      HapticFeedback.lightImpact();
      widget.onSubmit!(_draft);
      return;
    }

    // Standalone mode: backend'ga yuborish.
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null) {
      _showError('Buyurtma yuborish uchun avval tizimga kiring');
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
      _showError('Tarmoq xatosi: $e');
    } finally {
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
                        title: 'Arxitektura TZ',
                        subtitle: _stepTitle(_stepIndex),
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
                            : (_isLastStep
                                ? (widget.submitLabel ?? 'Yuborish')
                                : 'Davom etish'),
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
      1 => '2/7 — Obyekt va manzil',
      2 => '3/7 — Loyiha va xonalar',
      3 => '4/7 — Arxitektura',
      4 => '5/7 — Konstruktiv',
      5 => '6/7 — Muhandislik',
      6 => '7/7 — Hudud va muddatlar',
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
        placeholder: 'Asliddin Hamrayev',
        required: true,
      ),
      WizardField(
        label: 'STIR / INN',
        controller: _tin,
        placeholder: '300000000',
        numericOnly: true,
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

  // ── Step 2: Obyekt ───────────────────────────────────────────────────
  Widget _buildStep2() {
    return _scrollableStep([
      const WizardSectionTitle(text: 'Obyekt va manzil'),
      WizardField(
        label: 'Obyekt nomi',
        controller: _objectName,
        placeholder: 'Mening uyim',
      ),
      WizardField(
        label: 'Manzil',
        controller: _address,
        placeholder: 'Toshkent sh., Yakkasaroy t., …',
        maxLines: 2,
      ),
      // Kadastr raqami avvalgi step'da kiritilgan bo'lsa, qayta so'ramaymiz.
      if (_cadastreNumber.text.trim().isEmpty)
        WizardField(
          label: 'Kadastr raqami',
          controller: _cadastreNumber,
          placeholder: '10:09:00:001',
        ),
      WizardField(
        label: 'Yer maydoni',
        controller: _landArea,
        placeholder: '500',
        suffix: 'm²',
        numericOnly: true,
        allowDecimal: true,
      ),
      WizardField(
        label: 'Yerning maqsadli foydalanishi',
        controller: _landUsePurpose,
        placeholder: 'turar joy / ishlab chiqarish',
      ),
    ]);
  }

  // ── Step 3: Loyiha umumiy + xonalar ──────────────────────────────────
  Widget _buildStep3() {
    return _scrollableStep([
      const WizardSectionTitle(text: 'Loyiha umumiy ma\'lumotlari'),
      WizardChipPicker<ArchObjectType>(
        label: 'Obyekt turi',
        required: true,
        options: ArchObjectType.values,
        labelOf: _objectTypeLabel,
        value: _draft.objectType,
        onChanged: (v) => setState(() => _draft.objectType = v),
      ),
      if (_draft.objectType == ArchObjectType.boshqa)
        WizardField(
          label: 'Boshqa (qaysi turdagi)',
          controller: _objectSubtype,
          placeholder: 'Masalan: ko\'p funksiyali markaz',
        ),
      WizardChipPicker<ConstructionType>(
        label: 'Qurilish turi',
        options: ConstructionType.values,
        labelOf: (t) => t == ConstructionType.yangi ? 'Yangi' : 'Rekonstruksiya',
        value: _draft.constructionType,
        onChanged: (v) =>
            setState(() => _draft.constructionType = v ?? ConstructionType.yangi),
      ),
      Row(
        children: [
          Expanded(
            child: WizardField(
              label: 'Qavatlar soni',
              controller: _floors,
              placeholder: '2',
              numericOnly: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: WizardField(
              label: 'Maks. balandlik',
              controller: _maxHeight,
              placeholder: '12',
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
              label: 'Umumiy maydon',
              controller: _totalArea,
              placeholder: '350',
              suffix: 'm²',
              numericOnly: true,
              allowDecimal: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: WizardField(
              label: 'Qurilish maydoni',
              controller: _buildingArea,
              placeholder: '180',
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
      WizardSwitchTile(
        label: 'Yer osti avtoturargohi',
        value: _draft.hasUndergroundParking,
        onChanged: (v) => setState(() => _draft.hasUndergroundParking = v),
      ),
      const SizedBox(height: 4),
      const WizardSectionTitle(text: 'Xonalar tarkibi'),
      _buildRoomsEditor(),
    ]);
  }

  Widget _buildRoomsEditor() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < _draft.rooms.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: TextFormField(
                      initialValue: _draft.rooms[i].name,
                      onChanged: (v) => _draft.rooms[i].name = v,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Xona nomi',
                      ),
                      style: TextStyle(color: textColor, fontSize: 14),
                    ),
                  ),
                  SizedBox(
                    width: 50,
                    child: TextFormField(
                      initialValue: _draft.rooms[i].count?.toString() ?? '',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: (v) =>
                          _draft.rooms[i].count = int.tryParse(v),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Soni',
                      ),
                      style: TextStyle(color: textColor, fontSize: 14),
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    child: TextFormField(
                      initialValue: _draft.rooms[i].areaSqm?.toString() ?? '',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      onChanged: (v) => _draft.rooms[i].areaSqm =
                          double.tryParse(v.replaceAll(',', '.')),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'm²',
                      ),
                      style: TextStyle(color: textColor, fontSize: 14),
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        setState(() => _draft.rooms.removeAt(i)),
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: const Color(0xFFE0492A),
                  ),
                ],
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(
              () => _draft.rooms.add(RoomEntry(name: '')),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Xona qo\'shish'),
            style: TextButton.styleFrom(foregroundColor: AppColors.splashGreen),
          ),
        ),
      ],
    );
  }

  // ── Step 4: Arxitektura ──────────────────────────────────────────────
  Widget _buildStep4() {
    return _scrollableStep([
      const WizardSectionTitle(text: 'Arxitektura va dizayn'),
      WizardChipPicker<String>(
        label: 'Uslub',
        options: const [
          'high_tech',
          'klassik',
          'neoklassik',
          'minimalizm',
          'loft',
        ],
        labelOf: _designStyleLabel,
        value: _draft.architecture.style,
        onChanged: (v) => setState(() => _draft.architecture.style = v),
      ),
      WizardChipPicker<String>(
        label: 'Fasad materiali',
        options: const ['gisht', 'tosh', 'kompozit', 'shisha', 'boyoq'],
        labelOf: _facadeMaterialLabel,
        value: _draft.architecture.facadeMaterial,
        onChanged: (v) =>
            setState(() => _draft.architecture.facadeMaterial = v),
      ),
      WizardField(
        label: 'Ranglar',
        controller: _colors,
        placeholder: 'Bej, oq, yog\'och',
      ),
      WizardSwitchTile(
        label: '3D vizualizatsiya kerak',
        value: _draft.architecture.has3dVisualization,
        onChanged: (v) =>
            setState(() => _draft.architecture.has3dVisualization = v),
      ),
    ]);
  }

  // ── Step 5: Konstruktiv ──────────────────────────────────────────────
  Widget _buildStep5() {
    return _scrollableStep([
      const WizardSectionTitle(text: 'Konstruktiv yechimlar'),
      WizardChipPicker<String>(
        label: 'Konstruktiv sxema',
        options: const ['karkas', 'monolit', 'gisht', 'aralash', 'metall'],
        labelOf: (s) => switch (s) {
          'karkas' => 'Karkas',
          'monolit' => 'Monolit',
          'gisht' => 'G\'isht',
          'aralash' => 'Aralash',
          'metall' => 'Metall',
          _ => s,
        },
        value: _draft.constructive.scheme,
        onChanged: (v) => setState(() => _draft.constructive.scheme = v),
      ),
      WizardChipPicker<String>(
        label: 'Poydevor',
        options: const ['ustun', 'lenta', 'plita', 'svay'],
        labelOf: (s) => switch (s) {
          'ustun' => 'Ustun',
          'lenta' => 'Lenta',
          'plita' => 'Plita',
          'svay' => 'Svay',
          _ => s,
        },
        value: _draft.constructive.foundation,
        onChanged: (v) => setState(() => _draft.constructive.foundation = v),
      ),
      WizardChipPicker<String>(
        label: 'Devor materiali',
        options: const ['gisht', 'gazoblok', 'beton', 'sendvich_panel'],
        labelOf: (s) => switch (s) {
          'gisht' => 'G\'isht',
          'gazoblok' => 'Gazoblok',
          'beton' => 'Beton',
          'sendvich_panel' => 'Sendvich panel',
          _ => s,
        },
        value: _draft.constructive.walls,
        onChanged: (v) => setState(() => _draft.constructive.walls = v),
      ),
      WizardChipPicker<String>(
        label: 'Qavat yopma',
        options: const ['temir_beton', 'yogoch', 'metall'],
        labelOf: (s) => switch (s) {
          'temir_beton' => 'Temir-beton',
          'yogoch' => 'Yog\'och',
          'metall' => 'Metall',
          _ => s,
        },
        value: _draft.constructive.ceiling,
        onChanged: (v) => setState(() => _draft.constructive.ceiling = v),
      ),
      WizardChipPicker<String>(
        label: 'Tom turi',
        options: const ['yassi', 'qiya'],
        labelOf: (s) => s == 'yassi' ? 'Yassi' : 'Qiya',
        value: _draft.constructive.roofType,
        onChanged: (v) => setState(() => _draft.constructive.roofType = v),
      ),
      WizardField(
        label: 'Tom qoplama materiali',
        controller: _roofMaterial,
        placeholder: 'Metall cherepitsa, profnastil…',
      ),
    ]);
  }

  // ── Step 6: Muhandislik ──────────────────────────────────────────────
  Widget _buildStep6() {
    return _scrollableStep([
      const WizardSectionTitle(text: 'Muhandislik tizimlari'),
      WizardSwitchTile(
        label: 'Zaxira generator',
        value: _draft.engineering.hasGenerator,
        onChanged: (v) => setState(() => _draft.engineering.hasGenerator = v),
      ),
      WizardChipPicker<String>(
        label: 'Suv manbai',
        options: const ['markaziy', 'quduq'],
        labelOf: (s) => s == 'markaziy' ? 'Markaziy' : 'Quduq',
        value: _draft.engineering.waterSource,
        onChanged: (v) => setState(() => _draft.engineering.waterSource = v),
      ),
      WizardChipPicker<String>(
        label: 'Kanalizatsiya',
        options: const ['markaziy', 'septik'],
        labelOf: (s) => s == 'markaziy' ? 'Markaziy' : 'Avtonom (septik)',
        value: _draft.engineering.sewage,
        onChanged: (v) => setState(() => _draft.engineering.sewage = v),
      ),
      WizardChipPicker<String>(
        label: 'Isitish',
        options: const ['gaz', 'elektr', 'qozonxona'],
        labelOf: (s) => switch (s) {
          'gaz' => 'Gaz',
          'elektr' => 'Elektr',
          'qozonxona' => 'Qozonxona',
          _ => s,
        },
        value: _draft.engineering.heating,
        onChanged: (v) => setState(() => _draft.engineering.heating = v),
      ),
      WizardChipPicker<String>(
        label: 'Ventilyatsiya',
        options: const ['tabiiy', 'mexanik'],
        labelOf: (s) => s == 'tabiiy' ? 'Tabiiy' : 'Mexanik',
        value: _draft.engineering.ventilation,
        onChanged: (v) => setState(() => _draft.engineering.ventilation = v),
      ),
      WizardChipPicker<String>(
        label: 'Konditsioner',
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
        label: 'Yong\'in xavfsizligi tizimi',
        value: _draft.engineering.hasFireSystem,
        onChanged: (v) => setState(() => _draft.engineering.hasFireSystem = v),
      ),
      WizardSwitchTile(
        label: 'Signalizatsiya',
        value: _draft.engineering.hasAlarm,
        onChanged: (v) => setState(() => _draft.engineering.hasAlarm = v),
      ),
      WizardSwitchTile(
        label: 'Videokuzatuv',
        value: _draft.engineering.hasVideoSurveillance,
        onChanged: (v) =>
            setState(() => _draft.engineering.hasVideoSurveillance = v),
      ),
      WizardSwitchTile(
        label: 'Quyosh panellari',
        value: _draft.engineering.hasSolarPanels,
        onChanged: (v) =>
            setState(() => _draft.engineering.hasSolarPanels = v),
      ),
    ]);
  }

  // ── Step 7: Hudud + muddatlar + qo'shimcha ───────────────────────────
  Widget _buildStep7() {
    return _scrollableStep([
      const WizardSectionTitle(text: 'Hududni rejalashtirish'),
      WizardSwitchTile(
        label: 'Avtoturargoh',
        value: _draft.territory.hasParking,
        onChanged: (v) => setState(() => _draft.territory.hasParking = v),
      ),
      if (_draft.territory.hasParking)
        WizardField(
          label: 'Parking joylar soni',
          controller: _parkingCount,
          placeholder: '4',
          numericOnly: true,
        ),
      WizardSwitchTile(
        label: 'Yo\'laklar',
        value: _draft.territory.hasPaths,
        onChanged: (v) => setState(() => _draft.territory.hasPaths = v),
      ),
      WizardSwitchTile(
        label: 'Landshaft dizayni',
        value: _draft.territory.hasLandscape,
        onChanged: (v) => setState(() => _draft.territory.hasLandscape = v),
      ),
      WizardSwitchTile(
        label: 'Hovuz',
        value: _draft.territory.hasPool,
        onChanged: (v) => setState(() => _draft.territory.hasPool = v),
      ),
      WizardSwitchTile(
        label: 'Hudud yoritilishi',
        value: _draft.territory.hasLighting,
        onChanged: (v) => setState(() => _draft.territory.hasLighting = v),
      ),
      const SizedBox(height: 4),
      const WizardSectionTitle(text: 'Muddatlar'),
      Row(
        children: [
          Expanded(
            child: WizardField(
              label: 'Eskiz loyiha',
              controller: _sketchDays,
              placeholder: '30',
              suffix: 'kun',
              numericOnly: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: WizardField(
              label: 'Ishchi loyiha',
              controller: _workingDays,
              placeholder: '60',
              suffix: 'kun',
              numericOnly: true,
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      const WizardSectionTitle(text: 'Qo\'shimcha talablar'),
      WizardField(
        label: 'Izoh',
        controller: _notes,
        placeholder: 'Loyihaga doir qo\'shimcha izohlar…',
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

  static String _objectTypeLabel(ArchObjectType t) => switch (t) {
        ArchObjectType.yakkaSmall => 'Yakka uy <500 m²',
        ArchObjectType.yakkaLarge => 'Yakka uy >500 m²',
        ArchObjectType.kopQavatli => 'Ko\'p qavatli turar-joy',
        ArchObjectType.ofis => 'Ofis',
        ArchObjectType.savdoMarkazi => 'Savdo markazi',
        ArchObjectType.mehmonxona => 'Mehmonxona',
        ArchObjectType.sanoat => 'Sanoat',
        ArchObjectType.omborxona => 'Omborxona',
        ArchObjectType.boshqa => 'Boshqa',
      };

  static String _designStyleLabel(String s) => switch (s) {
        'high_tech' => 'High-tech',
        'klassik' => 'Klassik',
        'neoklassik' => 'Neoklassik',
        'minimalizm' => 'Minimalizm',
        'loft' => 'Loft',
        _ => s,
      };

  static String _facadeMaterialLabel(String s) => switch (s) {
        'gisht' => 'G\'isht',
        'tosh' => 'Tosh',
        'kompozit' => 'Kompozit panellar',
        'shisha' => 'Shisha',
        'boyoq' => 'Fasad bo\'yoqlari',
        _ => s,
      };
}
