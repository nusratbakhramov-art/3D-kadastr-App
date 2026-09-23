/// Kadastr raqamining shakli — bitta joyda.
///
/// Raqam uch xil ko'rinishda uchraydi va ular BIR XIL obyektni bildirmaydi:
///
/// - yer uchastkasi — `10:10:03:03:01:5414`;
/// - uchastkadagi bino / xonadon — `10:10:03:03:01:5414/01` (geoportal aynan
///   shunday qaytaradi);
/// - bo'lingan uchastka — `10:09:01:01:02:5942:0001:039`.
///
/// Qoidalar ikki joyda takrorlanmasligi kerak edi: ekran raqamni qabul
/// qilish-qilmasligini, geoportal esa qaysi raqamni so'rashni shu yerdan
/// oladi.
library;

/// To'liq (qidirishga tayyor) raqammi.
///
/// ⚠️ `/` HAM AJRATGICH. U qabul qilinmaganida xaritadan uy tanlagan odam
/// boshi berk ko'chaga kirardi: raqam maydonga tushardi, lekin qidiruv
/// boshlanmas, tugma chiqmas va «Davom etish» o'chiq qolaverardi.
final RegExp kCadastreNumberRe = RegExp(
  r'^\d{2}:\d{2}:\d{2}:\d{2}:\d{2}:\d{4}([:/]\d{1,4})*$',
);

bool isFullCadastreNumber(String text) => kCadastreNumberRe.hasMatch(text);

/// Raqamning YER UCHASTKASI qismi — dumisiz.
///
/// Geoportal qatlamlarida FAQAT uchastka bor (jonli tekshirildi: `.../5414/01`
/// bilan 0 ta javob, dumsiz `...:5414` bilan 1 ta). Shuning uchun xaritadan
/// qidirishdan oldin raqam shu yerda qisqartiriladi, va ekran ham «xaritadagi
/// uchastka shu raqamnikimi» degan savolga shu asos bo'yicha javob beradi.
String cadastreBaseNumber(String number) {
  final trimmed = number.trim();
  final slash = trimmed.indexOf('/');
  final head = slash >= 0 ? trimmed.substring(0, slash) : trimmed;
  final blocks = head.split(':');
  if (blocks.length <= 6) return head;
  return blocks.take(6).join(':');
}
