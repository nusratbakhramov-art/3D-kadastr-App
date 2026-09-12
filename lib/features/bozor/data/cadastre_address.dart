/// Reyestr manzilini e'lon maydonlariga ajratish.
///
/// davreestr bitta satr qaytaradi:
///
///     Toshkent shahri, Mirzo Ulug'bek, Xamid Olimjon MFY,
///     Oqqo'rg'on ko'chasi, 6а-uy, 39-xonadon
///
/// Sehrgarning 2-qadami esa buni bo'lib so'raydi: viloyat, tuman, manzil,
/// uy raqami, xonadon raqami. Shu fayl o'sha ajratishni bajaradi.
///
/// ⚠️ TAXMIN QILMAYDI. Har bir qism faqat ISHONCHLI tanilganda qaytariladi,
/// aks holda `null` — chaqiruvchi maydonni bo'sh qoldiradi va foydalanuvchi
/// o'zi to'ldiradi. Sabab: noto'g'ri to'ldirilgan tuman yoki uy raqami
/// bo'shidan YOMONROQ — foydalanuvchi to'g'ri deb o'ylab tashlab ketadi va
/// e'lon xato manzil bilan chiqadi.
library;

/// Reyestr manzilidan ajratib olingan qismlar. Har biri topilmasa `null`.
class CadastreAddressParts {
  const CadastreAddressParts({
    this.regionName,
    this.districtName,
    this.houseNumber,
    this.apartmentNumber,
  });

  /// Birinchi bo'lak — "Toshkent shahri", "Toshkent viloyati".
  final String? regionName;

  /// Ikkinchi bo'lak — "Mirzo Ulug'bek", "Chirchiq sh.", "Sirg'ali tumani".
  final String? districtName;

  /// "6а-uy" dan "6а".
  final String? houseNumber;

  /// "39-xonadon" dan "39".
  final String? apartmentNumber;
}

/// Reyestr ishlatadigan apostrof shakllari. Bittasiga keltirilmasa
/// "Mirzo Ulug‘bek" (U+2018) bazadagi "Mirzo Ulug'bek" (ASCII) bilan hech
/// qachon mos kelmaydi — va tuman JIMGINA tanlanmay qolardi.
final _apostrophes = RegExp('[‘’ʻʼ`´′]');

/// Joy nomini solishtirishga tayyorlaydi: kichik harf, bitta xil apostrof,
/// ortiqcha bo'shliqlarsiz. Qo'shimchalar (tumani/shahri) SAQLANADI —
/// ularni bu yerda kesish "Toshkent shahri" bilan "Toshkent viloyati" ni
/// bir xil qilib qo'yardi.
String normalizePlaceName(String value) => value
    .replaceAll(_apostrophes, "'")
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Ma'muriy birlik qo'shimchalari — faqat IKKINCHI urinishda kesiladi
/// ("Chirchiq sh." ↔ "Chirchiq").
final _placeSuffix = RegExp(
  r"\s+(tumani|tuman|shahri|shahar|sh\.|sh|viloyati|viloyat|t\.)$",
);

String _stripSuffix(String normalized) =>
    normalized.replaceFirst(_placeSuffix, '').trim();

/// [candidate] ga mos keluvchi nomning [names] dagi indeksi, yoki `null`.
///
/// Ikki bosqich:
///   1. To'liq moslik (normallashtirilgan holda) — eng ishonchlisi;
///   2. qo'shimchasiz moslik, LEKIN faqat natija YAGONA bo'lsa.
///
/// Ikkinchi bosqichning yagonalik sharti shart: viloyatlar ro'yxatida
/// "Andijon shahri" va "Andijon tumani" birga turadi va qo'shimchasiz
/// ikkalasi ham "andijon" bo'lib qoladi — tanlab bo'lmaydi, demak
/// tanlanmaydi.
int? matchPlaceIndex(List<String> names, String? candidate) {
  if (candidate == null) return null;
  final target = normalizePlaceName(candidate);
  if (target.isEmpty) return null;

  for (var i = 0; i < names.length; i++) {
    if (normalizePlaceName(names[i]) == target) return i;
  }

  final bare = _stripSuffix(target);
  if (bare.isEmpty) return null;
  int? found;
  for (var i = 0; i < names.length; i++) {
    if (_stripSuffix(normalizePlaceName(names[i])) != bare) continue;
    if (found != null) return null; // ikkitasi — tanlab bo'lmaydi
    found = i;
  }
  return found;
}

/// "6а-uy" / "39-xonadon" kabi bo'laklar. Raqamdan keyin harf kelishi
/// mumkin ("6а"), va u KIRILLCHA bo'lishi ham mumkin — reyestrda aynan
/// shunday uchraydi.
final _houseRe = RegExp(r'^(.{1,10}?)\s*-\s*uy$', caseSensitive: false);
final _apartmentRe = RegExp(
  r'^(.{1,10}?)\s*-\s*xonadon$',
  caseSensitive: false,
);

/// Reyestr manzilini qismlarga ajratadi.
CadastreAddressParts parseCadastreAddress(String? address) {
  final raw = address?.trim() ?? '';
  if (raw.isEmpty) return const CadastreAddressParts();

  final segments = [
    for (final s in raw.split(',')) s.trim(),
  ]..removeWhere((s) => s.isEmpty);
  if (segments.isEmpty) return const CadastreAddressParts();

  String? house;
  String? apartment;
  for (final segment in segments) {
    house ??= _houseRe.firstMatch(segment)?.group(1)?.trim();
    apartment ??= _apartmentRe.firstMatch(segment)?.group(1)?.trim();
  }

  // Birinchi ikki bo'lak — viloyat va tuman. Ular uy/xonadon bo'lagi bo'lib
  // qolsa (juda kalta manzil) joy nomi sifatida olinmaydi.
  String? placeAt(int i) {
    if (i >= segments.length) return null;
    final s = segments[i];
    if (_houseRe.hasMatch(s) || _apartmentRe.hasMatch(s)) return null;
    return s.isEmpty ? null : s;
  }

  return CadastreAddressParts(
    regionName: placeAt(0),
    districtName: placeAt(1),
    houseNumber: (house?.isEmpty ?? true) ? null : house,
    apartmentNumber: (apartment?.isEmpty ?? true) ? null : apartment,
  );
}
