/// Umumiy kiritish validatsiyalari — kalkulyator TZ wizardlari va boshqa
/// formalar uchun. Bitta joyda saqlanadi (telefon/email qoidalari bir xil
/// bo'lishi uchun).
library;

/// O'zbekiston telefon raqami to'g'riligini tekshiradi.
///
/// Faqat raqamlar ajratib olinadi, so'ng:
/// - `998` bilan boshlansa — jami 12 ta raqam bo'lishi shart (+998 90 123 45 67),
/// - aks holda — 9 ta raqam (operator + raqam, masalan 90 123 45 67).
///
/// Bo'sh satr `false` qaytaradi (majburiy maydon uchun). Ixtiyoriy holatda
/// chaqiruvchi tomonida bo'shlikni alohida tekshiring.
bool isValidUzPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return false;
  if (digits.startsWith('998')) return digits.length == 12;
  return digits.length == 9;
}

/// Email formati to'g'riligini tekshiradi. Bo'sh satr `true` — email ixtiyoriy
/// maydon, faqat kiritilgan bo'lsa formatini tekshiramiz.
bool isValidEmail(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return true;
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t);
}

/// STIR (9 raqam) yoki INN/JSHSHIR (14 raqam). Bo'sh bo'lsa `true` (ixtiyoriy).
bool isValidTin(String raw) {
  final t = raw.trim();
  return t.isEmpty || t.length == 9 || t.length == 14;
}
