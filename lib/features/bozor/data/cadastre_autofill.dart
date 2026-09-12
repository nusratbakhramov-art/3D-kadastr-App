/// Reyestr javobidan e'lon maydonlariga NIMA tushishi.
///
/// Qaror ekrandan ajratilgan, chunki eng qimmat xatolar aynan shu yerda
/// yashiringan va ularning hech biri ekranda ko'rinmaydi:
///
///   * BIRLIK. Yer maydoni parametrlar qadamida SOTIXDA so'raladi
///     (1 sotix = 100 m²), bino maydoni esa m² da. Chalkashtirsak e'lon 100
///     barobar katta (yoki kichik) maydon bilan chiqadi.
///   * QAYSI PARAMETR. Har mulk turida asosiy maydonning kaliti boshqacha
///     (`total_area` / `house_area` / `land_area` / `premises_area` /
///     `garage_area`) va u backenddagi `primary_area_key` bilan mos
///     bo'lishi kerak.
///   * USTIDAN YOZMASLIK. Foydalanuvchi qo'lda kiritgan qiymat reyestrniki
///     bilan almashtirilmaydi — u o'zgarganini sezmasligi mumkin.
///
/// Shuning uchun bu yerda faqat sof hisob bor: kiruvchi javob va hozirgi
/// qiymatlar → nimani to'ldirish kerakligi. Ekran natijani shunchaki
/// qo'llaydi.
library;

import '../../services/api_cadastre_service.dart';
import '../models/bozor_draft.dart';
import 'cadastre_address.dart';

/// 1 sotix = 100 m².
const double kSquareMetersPerSotix = 100;

/// To'ldirilishi KERAK bo'lgan qiymatlar. `null` yoki yo'q kalit —
/// "tegilmasin" degani, "bo'sh qilinsin" emas.
class CadastreAutofill {
  const CadastreAutofill({
    this.address,
    this.houseNumber,
    this.apartmentNumber,
    this.regionName,
    this.districtName,
    this.params = const {},
  });

  final String? address;
  final String? houseNumber;
  final String? apartmentNumber;

  /// Reyestrdagi NOMLAR — ekran ularni `matchPlaceIndex` bilan bazadagi
  /// ro'yxatga solishtiradi (bu yerda ro'yxat yo'q).
  final String? regionName;
  final String? districtName;

  /// Parametrlar qadamining kalitlari → matn qiymat (maydon boshqaruvi
  /// qiymatni MATN sifatida saqlaydi).
  final Map<String, String> params;

  bool get isEmpty =>
      address == null &&
      houseNumber == null &&
      apartmentNumber == null &&
      regionName == null &&
      districtName == null &&
      params.isEmpty;
}

/// Mulk turining ASOSIY maydon parametri — backenddagi `primary_area_key`
/// bilan bir xil bo'lishi shart.
String? primaryAreaKey(PropertyType type) => switch (type) {
  PropertyType.apartment || PropertyType.newBuildingApartment => 'total_area',
  PropertyType.house => 'house_area',
  PropertyType.land => 'land_area',
  PropertyType.commercial => 'premises_area',
  PropertyType.garage => 'garage_area',
  // Bu turda «Параметры» qadami umuman yo'q.
  PropertyType.otherNonResidential => null,
};

/// Reyestr javobidan to'ldirish rejasini quradi.
///
/// [currentParams] va matn qiymatlari HOZIRGI holat: bo'sh bo'lmaganlari
/// natijaga umuman tushmaydi.
CadastreAutofill buildCadastreAutofill({
  required CadastreLookupResult info,
  required PropertyType type,
  String currentAddress = '',
  String currentHouseNumber = '',
  String currentApartmentNumber = '',
  bool hasRegion = false,
  bool hasDistrict = false,
  Map<String, Object?> currentParams = const {},
}) {
  final address = info.address?.trim() ?? '';
  if (address.isEmpty) return const CadastreAutofill();

  final parts = parseCadastreAddress(address);
  final params = <String, String>{};

  void put(String key, double? value, {bool toSotix = false}) {
    if (value == null || value <= 0) return;
    final current = currentParams[key];
    if (current != null && current.toString().trim().isNotEmpty) return;
    params[key] = formatAreaValue(
      toSotix ? value / kSquareMetersPerSotix : value,
    );
  }

  switch (type) {
    case PropertyType.apartment:
    case PropertyType.newBuildingApartment:
      put('total_area', info.totalArea);
      put('living_area', info.livingArea);
    case PropertyType.house:
      // Uyda IKKI maydon bor va ular BOSHQA birlikda: uy — m², yer — sotix.
      put('house_area', info.totalArea);
      put('land_area', info.landArea, toSotix: true);
    case PropertyType.land:
      put('land_area', info.landArea, toSotix: true);
    case PropertyType.commercial:
      put('premises_area', info.totalArea);
    case PropertyType.garage:
      put('garage_area', info.totalArea);
    case PropertyType.otherNonResidential:
      break;
  }

  String? fill(String current, String? value) =>
      current.trim().isEmpty ? value : null;

  return CadastreAutofill(
    address: fill(currentAddress, address),
    houseNumber: fill(currentHouseNumber, parts.houseNumber),
    apartmentNumber: fill(currentApartmentNumber, parts.apartmentNumber),
    regionName: hasRegion ? null : parts.regionName,
    districtName: hasDistrict ? null : parts.districtName,
    params: Map.unmodifiable(params),
  );
}

/// Butun son bo'lsa kasr qismsiz — "84", "84.0" emas. Maydon matn maydoni,
/// ya'ni foydalanuvchi buni AYNAN shunday ko'radi.
String formatAreaValue(double v) {
  final rounded = double.parse(v.toStringAsFixed(2));
  if (rounded == rounded.roundToDouble()) return rounded.toInt().toString();
  return rounded.toString();
}
