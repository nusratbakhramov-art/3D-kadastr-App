/// "Bozor AI" sehrgarining 2-qadami — `Адрес`.
///
/// Qatorlar mulk turiga qarab chiziladi ([PropertyTypeAddressX.addressRows]):
/// to'rttasi hammada bir xil (viloyat, tuman, manzil, mo'ljal), qolgani faqat
/// kvartira va uyda. Ro'yxat qat'iy yozilmagan — bitta `for` aylanma enum
/// bo'yicha yuradi, shunda yangi tur qo'shilsa faqat model o'zgaradi.
library;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../services/data/geocoder_client.dart';
import '../../services/screens/map_location_picker_screen.dart';
import '../../services/widgets/service_app_bar.dart';
import '../../services/widgets/step_progress_bar.dart';
import '../../services/widgets/wizard_field.dart';
import '../../services/widgets/wizard_nav_bar.dart';
import '../bozor_routes.dart';
import '../bozor_step_route.dart';
import '../data/regions_repository.dart';
import '../models/bozor_draft.dart';
import '../widgets/address_pin_field.dart';
import '../widgets/option_picker_sheet.dart';
import '../widgets/select_field.dart';

/// Bitta nusxa — daraxt bir marta olinadi va sehrgar bo'ylab keshda qoladi.
final RegionsRepository _defaultRegions = ApiRegionsRepository();

class BozorAddressStepScreen extends StatefulWidget {
  BozorAddressStepScreen({
    super.key,
    required this.draft,
    RegionsRepository? regionsRepository,
  }) : regionsRepository = regionsRepository ?? _defaultRegions;

  final BozorDraft draft;

  /// Viloyat/tuman manbai. Sukut bo'yicha backend
  /// (`GET /marketplace/regions/tree`); testda boshqasini berish mumkin.
  final RegionsRepository regionsRepository;

  @override
  State<BozorAddressStepScreen> createState() => _BozorAddressStepScreenState();
}

class _BozorAddressStepScreenState extends State<BozorAddressStepScreen> {
  final _address = TextEditingController();
  final _landmark = TextEditingController();
  final _apartmentNumber = TextEditingController();
  final _entrance = TextEditingController();
  final _houseNumber = TextEditingController();
  final _totalFloors = TextEditingController();
  final _floor = TextEditingController();

  late final List<TextEditingController> _all = [
    _address,
    _landmark,
    _apartmentNumber,
    _entrance,
    _houseNumber,
    _totalFloors,
    _floor,
  ];

  final GeocoderClient _geocoder = GeocoderClient();
  bool _geocoding = false;

  List<Region> _regions = const [];
  List<District> _districts = const [];
  bool _loadingRegions = true;
  bool _loadingDistricts = false;

  AddressDraft get _a => widget.draft.address;

  @override
  void initState() {
    super.initState();
    // Qoralamadagi (yoki tahrirlanayotgan e'londagi) qiymatlarni maydonlarga
    // TIKLAYMIZ.
    //
    // ⚠️ BUSIZ IKKI XATO BIRDAN BO'LARDI. Ekran qoralamani davom ettirganda
    // yoki e'lonni tahrirlaganda ochilsa, viloyat/tuman va xarita nuqtasi
    // ko'rinardi (ular `_a` dan to'g'ridan o'qiladi), MATN maydonlari esa
    // bo'sh chiqardi — foydalanuvchi "ma'lumotlarim yo'qolibdi" deb o'ylaydi.
    // Yomoni ikkinchisi: `_onContinue` shu bo'sh kontrollerlarni `_a` ga
    // ustidan yozardi, ya'ni "Keyingisi" bosilishi bilan manzil, uy raqami va
    // qavatlar `PATCH` da JIMGINA yo'qolardi.
    //
    // Tinglovchilardan OLDIN to'ldiriladi — aks holda har bir tayinlash
    // keraksiz `setState` chaqirardi.
    _address.text = _a.address;
    _landmark.text = _a.landmark;
    _apartmentNumber.text = _a.apartmentNumber;
    _entrance.text = _a.entrance;
    _houseNumber.text = _a.houseNumber;
    _totalFloors.text = _a.totalFloors;
    _floor.text = _a.floor;

    // "Далее" har bosishda qayta hisoblanadi.
    for (final c in _all) {
      c.addListener(_rebuild);
    }
    _loadRegions();
  }

  @override
  void dispose() {
    for (final c in _all) {
      c.removeListener(_rebuild);
      c.dispose();
    }
    _geocoder.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  Future<void> _loadRegions() async {
    final list = await widget.regionsRepository.regions();
    if (!mounted) return;
    setState(() {
      _regions = list;
      _loadingRegions = false;
    });
    final id = _a.regionId;
    if (id != null) _loadDistricts(id);
  }

  Future<void> _loadDistricts(int regionId) async {
    setState(() => _loadingDistricts = true);
    final list = await widget.regionsRepository.districts(regionId);
    if (!mounted) return;
    setState(() {
      _districts = list;
      _loadingDistricts = false;
    });
  }

  Future<void> _pickRegion() async {
    if (_loadingRegions) return;
    final l = Localizations.localeOf(context);
    final picked = await showOptionPickerSheet<Region>(
      context,
      title: _S.region(l),
      options: _regions,
      labelOf: (r) => r.name,
      selected: _regions.where((r) => r.id == _a.regionId).firstOrNull,
    );
    if (picked == null || !mounted) return;
    setState(() {
      // Viloyat o'zgarsa tuman tozalanadi — boshqa viloyatning tumani
      // qolib ketmasin.
      _a.setRegion(picked.id, picked.name);
      _districts = const [];
    });
    _loadDistricts(picked.id);
  }

  Future<void> _pickDistrict() async {
    final regionId = _a.regionId;
    if (regionId == null || _loadingDistricts) return;
    final l = Localizations.localeOf(context);
    final picked = await showOptionPickerSheet<District>(
      context,
      title: _S.district(l),
      options: _districts,
      labelOf: (d) => d.name,
      selected: _districts.where((d) => d.id == _a.districtId).firstOrNull,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _a.districtId = picked.id;
      _a.districtName = picked.name;
    });
  }

  Future<void> _pickOnMap() async {
    final l = Localizations.localeOf(context);
    final lat = _a.lat;
    final lng = _a.lng;
    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute<LatLng>(
        settings: bozorRoute('address/map'),
        builder: (_) => MapLocationPickerScreen(
          initialPoint: lat != null && lng != null ? LatLng(lat, lng) : null,
          title: _S.mapTitle(l),
          subtitle: _S.mapSubtitle(l),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _a.lat = result.latitude;
      _a.lng = result.longitude;
      _geocoding = true;
    });
    // Nuqtani manzil matniga aylantirib, maydonni avtomatik to'ldiramiz.
    // `GeocoderClient` uchinchi tomon geokoderiga EMAS, backend proksisiga
    // (`/api/v1/geo/reverse`) boradi — kalit ilovada saqlanmaydi.
    try {
      final text = await _geocoder.reverse(result.latitude, result.longitude);
      if (!mounted) return;
      if (text != null && text.isNotEmpty) {
        _address.text = text;
      } else {
        AppToast.error(context, _S.geocodeFailed(l));
      }
    } on GeocoderException {
      // Koordinata baribir saqlanadi — foydalanuvchi manzilni qo'lda yozadi.
      if (mounted) AppToast.error(context, _S.geocodeFailed(l));
    } finally {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  /// `Этаж` `Этажей в доме` dan katta bo'lolmaydi — dizaynda yo'q, lekin
  /// aks holda ma'nosiz e'lon chiqadi.
  String? get _floorError {
    final total = int.tryParse(_totalFloors.text.trim());
    final floor = int.tryParse(_floor.text.trim());
    if (total == null || floor == null) return null;
    return floor > total ? _S.floorTooHigh(Localizations.localeOf(context)) : null;
  }

  bool get _isComplete {
    final type = widget.draft.type;
    if (type == null) return false;
    if (_a.regionId == null || _a.districtId == null) return false;
    if (_address.text.trim().isEmpty) return false;
    for (final row in type.addressRows) {
      final required = switch (row) {
        AddressRow.apartmentNumber => _apartmentNumber,
        AddressRow.houseNumber => _houseNumber,
        AddressRow.totalFloors => _totalFloors,
        AddressRow.floor => _floor,
        // Mo'ljal va podyezd — ixtiyoriy; viloyat/tuman/manzil yuqorida
        // tekshirilgan.
        _ => null,
      };
      if (required != null && required.text.trim().isEmpty) return false;
    }
    return _floorError == null;
  }

  void _onBlocked() =>
      AppToast.error(context, _S.fillRequired(Localizations.localeOf(context)));

  Future<void> _onContinue() async {
    // Manzil matni kontrollerda yashaydi — keyingi qadamga o'tishdan oldin
    // qoralamaga ko'chiramiz.
    _a.address = _address.text.trim();
    _a.landmark = _landmark.text.trim();
    _a.apartmentNumber = _apartmentNumber.text.trim();
    _a.entrance = _entrance.text.trim();
    _a.houseNumber = _houseNumber.text.trim();
    _a.totalFloors = _totalFloors.text.trim();
    _a.floor = _floor.text.trim();
    // Keyingisi qaysi ekran ekani (e'lon turi × mulk turi) juftligiga
    // bog'liq: ijarada odatda «Параметры», "Boshqa noturar joy" da esa u
    // yo'q, sotuvda esa o'sha holatda to'g'ridan «Сделка» keladi. Tanlov
    // BITTA joyda — `openNextBozorStep`.
    await openNextBozorStep(context, widget.draft, WizardStep.address);
    if (mounted) setState(() {});
  }

  Widget _row(AddressRow row, Locale l) {
    final type = widget.draft.type!;
    return switch (row) {
      AddressRow.region => SelectField(
        label: _S.region(l),
        value: _a.regionName,
        placeholder: _loadingRegions ? _S.loading(l) : _S.regionHint(l),
        enabled: !_loadingRegions,
        required: true,
        onTap: _pickRegion,
      ),
      AddressRow.district => SelectField(
        label: _S.district(l),
        value: _a.districtName,
        // Viloyat tanlanmaguncha tumanlar ro'yxati ma'lum emas.
        placeholder: _a.regionId == null
            ? _S.regionFirst(l)
            : (_loadingDistricts ? _S.loading(l) : _S.districtHint(l)),
        enabled: _a.regionId != null && !_loadingDistricts,
        required: true,
        onTap: _pickDistrict,
      ),
      AddressRow.address => AddressPinField(
        label: type.addressRowLabel(l),
        controller: _address,
        placeholder: _S.addressHint(l),
        required: true,
        onPickOnMap: _pickOnMap,
        busy: _geocoding,
        point: _a.lat != null && _a.lng != null
            ? (lat: _a.lat!, lng: _a.lng!)
            : null,
        pointLabel: _S.markedOnMap(l),
        clearLabel: _S.clear(l),
        onClearPoint: () => setState(() {
          _a.lat = null;
          _a.lng = null;
        }),
      ),
      AddressRow.landmark => WizardField(
        label: _S.landmark(l),
        controller: _landmark,
        placeholder: _S.landmarkHint(l),
      ),
      // `Дом` va `Номер квартиры` ataylab RAQAM EMAS: haqiqiy manzillarda
      // "12а", "45/2", "3-uy" uchraydi, qat'iy raqam ularni yozdirmaydi.
      AddressRow.apartmentNumber => WizardField(
        label: _S.apartmentNumber(l),
        controller: _apartmentNumber,
        placeholder: _S.numberHint(l),
        maxLength: 10,
        required: true,
      ),
      AddressRow.houseNumber => WizardField(
        label: _S.houseNumber(l),
        controller: _houseNumber,
        placeholder: _S.numberHint(l),
        maxLength: 10,
        required: true,
      ),
      AddressRow.entrance => WizardField(
        label: _S.entrance(l),
        controller: _entrance,
        placeholder: '0',
        numericOnly: true,
        maxLength: 3,
      ),
      AddressRow.totalFloors => WizardField(
        label: _S.totalFloors(l),
        controller: _totalFloors,
        placeholder: '0',
        numericOnly: true,
        maxLength: 3,
        required: true,
      ),
      AddressRow.floor => WizardField(
        label: _S.floor(l),
        controller: _floor,
        placeholder: '0',
        numericOnly: true,
        maxLength: 3,
        required: true,
        errorText: _floorError,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final subColor = isDark ? Colors.white70 : const Color(0xFF8A9097);
    final type = widget.draft.type;

    // 1-qadam to'ldirilmasdan bu ekranga kelib bo'lmaydi; himoya sifatida.
    if (type == null) return Scaffold(backgroundColor: bg, body: const SizedBox());

    final rows = type.addressRows;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final maxContent = c.maxWidth.clamp(0.0, 640.0);
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContent),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: ServiceAppBar(
                        title: _S.stepTitle(l),
                        subtitle:
                            '${widget.draft.stepNumber(WizardStep.address)}'
                            '/${widget.draft.stepCount}',
                        onBack: () => closeBozorWizard(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: StepProgressBar(
                        count: widget.draft.stepCount,
                        activeIndex: widget.draft.stepIndex(WizardStep.address),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          Text(
                            _S.hint(l),
                            style: TextStyle(
                              fontFamily: 'MTSText',
                              fontSize: 13,
                              height: 1.35,
                              color: subColor,
                            ),
                          ),
                          const SizedBox(height: 16),
                          for (final row in rows) ...[
                            _row(row, l),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: WizardNavBar(
                        onBack: () => Navigator.of(context).maybePop(),
                        continueLabel: _S.next(l),
                        continueEnabled: _isComplete,
                        onContinue: _onContinue,
                        onBlockedTap: _onBlocked,
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

class _S {
  const _S._();

  static String stepTitle(Locale l) => tr(l, 'bozor.address.title');
  static String hint(Locale l) => tr(l, 'bozor.address.hint');
  static String region(Locale l) => tr(l, 'bozor.address.field.region');
  static String regionHint(Locale l) => tr(l, 'bozor.address.hint.region');
  static String regionFirst(Locale l) => tr(l, 'bozor.address.region_first');
  static String district(Locale l) => tr(l, 'bozor.address.field.district');
  static String districtHint(Locale l) => tr(l, 'bozor.address.hint.district');
  static String addressHint(Locale l) => tr(l, 'bozor.address.hint.address');
  static String landmark(Locale l) => tr(l, 'bozor.address.field.landmark');
  static String landmarkHint(Locale l) => tr(l, 'bozor.address.hint.landmark');
  static String apartmentNumber(Locale l) =>
      tr(l, 'bozor.address.field.apartment_number');
  static String entrance(Locale l) => tr(l, 'bozor.address.field.entrance');
  static String houseNumber(Locale l) =>
      tr(l, 'bozor.address.field.house_number');
  static String totalFloors(Locale l) =>
      tr(l, 'bozor.address.field.total_floors');
  static String floor(Locale l) => tr(l, 'bozor.address.field.floor');
  static String numberHint(Locale l) => tr(l, 'bozor.address.hint.number');
  static String loading(Locale l) => tr(l, 'bozor.common.loading');
  static String next(Locale l) => tr(l, 'bozor.common.next');
  static String fillRequired(Locale l) => tr(l, 'bozor.common.fill_required');
  static String markedOnMap(Locale l) => tr(l, 'bozor.address.marked_on_map');
  static String clear(Locale l) => tr(l, 'bozor.common.clear');
  static String mapTitle(Locale l) => tr(l, 'bozor.address.map_title');
  static String mapSubtitle(Locale l) => tr(l, 'bozor.address.map_subtitle');
  static String floorTooHigh(Locale l) => tr(l, 'bozor.address.floor_too_high');
  static String geocodeFailed(Locale l) =>
      tr(l, 'bozor.address.geocode_failed');
}
