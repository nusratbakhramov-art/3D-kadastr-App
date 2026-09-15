/// "Bozor AI" sehrgarining 2-qadami — `Адрес`.
///
/// Qatorlar mulk turiga qarab chiziladi ([PropertyTypeAddressX.addressRows]):
/// to'rttasi hammada bir xil (viloyat, tuman, manzil, mo'ljal), qolgani faqat
/// kvartira va uyda. Ro'yxat qat'iy yozilmagan — bitta `for` aylanma enum
/// bo'yicha yuradi, shunda yangi tur qo'shilsa faqat model o'zgaradi.
///
/// ## Manzilni xaritadan olish
///
/// Asosiy yo'l — GEOPORTAL uchastkalari xaritasi (AI Baholash va «Taqiqni
/// tekshirish» dagi bilan bir xil ekran). U uchta narsani birdan beradi:
/// kadastr raqami, uchastka chegarasi va markaz nuqtasi. Keyin raqam bo'yicha
/// davreestr so'raladi va bo'sh maydonlar to'ldiriladi.
///
/// Ikkinchi yo'l — eski erkin metka. U ATAYLAB qoldirilgan: geoportal hamma
/// obyektni qamramaydi, va uchastka topilmagani uchun e'lon berish yo'li
/// berkilib qolmasligi kerak.
///
/// ⚠️ AVTOTO'LDIRISH HECH QACHON USTIDAN YOZMAYDI. Faqat BO'SH maydon
/// to'ldiriladi — foydalanuvchi qo'lda yozganini reyestr ma'lumoti bilan
/// almashtirish jimgina ma'lumot yo'qotish bo'lardi (u o'zgarganini
/// sezmasligi ham mumkin).
library;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../auth/auth_storage.dart';
import '../../services/api_cadastre_service.dart';
import '../../services/data/geocoder_client.dart';
import '../../services/data/ngis_parcel_client.dart';
import '../../services/screens/map_location_picker_screen.dart';
import '../../services/screens/parcel_picker_screen.dart';
import '../../services/widgets/service_app_bar.dart';
import '../../services/widgets/step_progress_bar.dart';
import '../../services/widgets/wizard_field.dart';
import '../../services/widgets/wizard_nav_bar.dart';
import '../bozor_routes.dart';
import '../bozor_step_route.dart';
import '../data/cadastre_address.dart';
import '../data/cadastre_autofill.dart';
import '../data/regions_repository.dart';
import '../models/bozor_draft.dart';
import '../models/parcel_boundary.dart';
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

  /// Xaritadan qaytgan natija maydonlarga ko'chirilmoqda (reyestr so'rovi
  /// yoki reverse-geokod) — manzil qatorida aylanma turadi.
  bool _autofilling = false;

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
    final List<Region> list;
    try {
      list = await widget.regionsRepository.regions();
    } catch (_) {
      // Tarmoq yo'q / timeout: ilgari bu ushlanmasdi — istisno havoda qolib,
      // maydon abadiy «Yuklanmoqda…» da turardi. Endi maydon ochiladi;
      // bosilganda ro'yxat bo'sh bo'lsa qayta yuklanadi ([_pickRegion]).
      if (mounted) setState(() => _loadingRegions = false);
      return;
    }
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
    if (_regions.isEmpty) {
      // Oldingi yuklash yiqilgan — qayta urinamiz.
      setState(() => _loadingRegions = true);
      await _loadRegions();
      if (!mounted || _regions.isEmpty) return;
    }
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

  /// ASOSIY yo'l — geoportal uchastkalari xaritasi.
  ///
  /// Qaytgan uchastkadan uchta narsa olinadi: kadastr raqami, chegara va
  /// markaz nuqtasi. Keyin raqam bo'yicha davreestr so'raladi va BO'SH
  /// maydonlar to'ldiriladi.
  Future<void> _pickParcel() async {
    final center = _a.boundary?.center ??
        (_a.lat != null && _a.lng != null ? LatLng(_a.lat!, _a.lng!) : null);
    final parcel = await Navigator.of(context).push<NgisParcel>(
      MaterialPageRoute<NgisParcel>(
        settings: bozorRoute('address/parcel'),
        builder: (_) => ParcelPickerScreen(initialCenter: center),
      ),
    );
    if (parcel == null || !mounted) return;

    final boundary = ParcelBoundary.fromRings(parcel.parts);
    final point = boundary?.center ?? parcel.center;
    setState(() {
      _a.cadastreNumber = parcel.cadastreNumber;
      _a.boundary = boundary;
      if (point != null) {
        _a.lat = point.latitude;
        _a.lng = point.longitude;
      }
      _autofilling = true;
    });
    try {
      await _fillFromCadastre(parcel.cadastreNumber, point);
    } finally {
      if (mounted) setState(() => _autofilling = false);
    }
  }

  /// IKKINCHI yo'l — erkin metka (eski xulq). Uchastka ma'lumoti endi shu
  /// nuqtaga tegishli emas, shuning uchun u tozalanadi: aks holda xaritada
  /// bir joy, chegarada esa boshqa uy ko'rinardi.
  Future<void> _pickManually() async {
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
      _a.clearParcel();
      _a.lat = result.latitude;
      _a.lng = result.longitude;
      _autofilling = true;
    });
    try {
      await _reverseGeocode(result, showError: true);
    } finally {
      if (mounted) setState(() => _autofilling = false);
    }
  }

  /// Kadastr raqami bo'yicha reyestrdan so'rab, bo'sh maydonlarni to'ldiradi.
  ///
  /// Reyestr javob bermasa oqim TO'XTAMAYDI: nuqta reverse-geokodlanadi va
  /// manzil matni baribir to'ladi. Uchastka raqami va chegarasi esa
  /// saqlanib qoladi — ular xaritadan olingan, reyestrdan emas.
  Future<void> _fillFromCadastre(String number, LatLng? point) async {
    final l = Localizations.localeOf(context);
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null || token.isEmpty) {
      if (point != null) await _reverseGeocode(point);
      return;
    }
    CadastreLookupResult? info;
    try {
      // Kesh ATAYLAB ishlatiladi (`forceRefresh` yo'q): bu e'lon uchun
      // manzil, yuridik hujjat emas. Kesh javobni bir zumda beradi va
      // davreestr so'rov limitiga urilish ehtimolini kamaytiradi.
      info = await CadastreApiService().lookup(
        cadastreNumber: number,
        token: token,
      );
    } catch (_) {
      // Reyestr javob bermadi — pastda nuqtadan manzil olamiz.
      info = null;
    }
    if (!mounted) return;

    final address = info?.address?.trim() ?? '';
    if (address.isEmpty) {
      if (point != null) await _reverseGeocode(point);
      if (mounted) AppToast.error(context, _S.cadastreFailed(l));
      return;
    }
    await _applyCadastre(info!);
  }

  /// Reyestr javobini maydonlarga yozadi — FAQAT bo'shlariga.
  ///
  /// Nimani to'ldirish kerakligini `buildCadastreAutofill` hal qiladi (sof
  /// funksiya, o'z testlari bilan); bu yerda faqat qo'llash qoladi.
  Future<void> _applyCadastre(CadastreLookupResult info) async {
    final type = widget.draft.type;
    if (type == null) return;
    final plan = buildCadastreAutofill(
      info: info,
      type: type,
      currentAddress: _address.text,
      currentHouseNumber: _houseNumber.text,
      currentApartmentNumber: _apartmentNumber.text,
      hasRegion: _a.regionId != null,
      hasDistrict: _a.districtId != null,
      currentParams: widget.draft.params,
    );
    if (plan.isEmpty) return;

    setState(() {
      if (plan.address != null) _address.text = plan.address!;
      if (plan.houseNumber != null) _houseNumber.text = plan.houseNumber!;
      if (plan.apartmentNumber != null) {
        _apartmentNumber.text = plan.apartmentNumber!;
      }
      widget.draft.params.addAll(plan.params);
    });
    // Viloyat/tuman tanlash TUMANLAR RO'YXATINI yuklaydi — kutiladi, aks
    // holda aylanma to'ldirish tugamasdan o'chib qolardi.
    await _applyPlaces(plan);
  }

  /// Viloyat va tumanni nom bo'yicha tanlaydi.
  ///
  /// Mos kelmasa JIMGINA o'tkazib yuboriladi — reyestr va bazadagi nomlar
  /// har doim ham bir xil transliteratsiyada emas (masalan reyestr
  /// "Sirg'ali", baza "Sergeli" deydi). Taxmin qilib noto'g'ri tuman
  /// qo'yishdan ko'ra bo'sh qoldirgan ma'qul: foydalanuvchi bo'shligini
  /// ko'radi, noto'g'risini esa yo'q.
  Future<void> _applyPlaces(CadastreAutofill plan) async {
    if (_a.regionId == null && _regions.isNotEmpty) {
      final i = matchPlaceIndex(
        [for (final r in _regions) r.name],
        plan.regionName,
      );
      if (i == null) return;
      final region = _regions[i];
      setState(() {
        _a.setRegion(region.id, region.name);
        _districts = const [];
      });
      await _loadDistricts(region.id);
      if (!mounted) return;
    }
    if (_a.districtId != null || _districts.isEmpty) return;
    final j = matchPlaceIndex(
      [for (final d in _districts) d.name],
      plan.districtName,
    );
    if (j == null) return;
    final district = _districts[j];
    setState(() {
      _a.districtId = district.id;
      _a.districtName = district.name;
    });
  }

  /// Nuqtani manzil matniga aylantiradi (faqat maydon BO'SH bo'lsa).
  ///
  /// `GeocoderClient` uchinchi tomon geokoderiga EMAS, backend proksisiga
  /// (`/api/v1/geo/reverse`) boradi — kalit ilovada saqlanmaydi.
  Future<void> _reverseGeocode(LatLng point, {bool showError = false}) async {
    final l = Localizations.localeOf(context);
    try {
      final text = await _geocoder.reverse(point.latitude, point.longitude);
      if (!mounted) return;
      if (text != null && text.isNotEmpty) {
        if (_address.text.trim().isEmpty) _address.text = text;
      } else if (showError) {
        AppToast.error(context, _S.geocodeFailed(l));
      }
    } on GeocoderException {
      // Koordinata baribir saqlanadi — foydalanuvchi manzilni qo'lda yozadi.
      if (mounted && showError) AppToast.error(context, _S.geocodeFailed(l));
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
        onPickOnMap: _pickParcel,
        onPickManually: _pickManually,
        manualLabel: _S.manualPin(l),
        busy: _autofilling,
        point: _a.lat != null && _a.lng != null
            ? (lat: _a.lat!, lng: _a.lng!)
            : null,
        pointLabel: _S.markedOnMap(l),
        cadastreNumber: _a.cadastreNumber,
        cadastreLabel: _S.cadastreLabel(l),
        clearLabel: _S.clear(l),
        // Nuqta bilan birga uchastka ham ketadi — ular bitta tanlovning
        // natijasi, birini qoldirib ketish ma'nosiz holat yaratardi.
        onClearPoint: () => setState(() {
          _a.lat = null;
          _a.lng = null;
          _a.clearParcel();
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
  static String manualPin(Locale l) => tr(l, 'bozor.address.manual_pin');
  static String cadastreLabel(Locale l) => tr(l, 'bozor.address.cadastre');
  static String cadastreFailed(Locale l) =>
      tr(l, 'bozor.address.cadastre_failed');
  static String floorTooHigh(Locale l) => tr(l, 'bozor.address.floor_too_high');
  static String geocodeFailed(Locale l) =>
      tr(l, 'bozor.address.geocode_failed');
}
