/// Narx maydonining raqam guruhlagichi: `5002323` → `5 002 323`.
///
/// NEGA KERAK. E'lon narxlari millionlarda bo'ladi, guruhlanmagan
/// `5002323` ni bir qarashda o'qib bo'lmaydi — foydalanuvchi nolni sanab
/// chiqishga majbur. Ro'yxatda va detalda narx allaqachon guruhlangan
/// ([formatBozorAmount]), kiritish paytida esa emas edi.
///
/// ⚠️ KURSOR — SHU FAYLNING BUTUN MURAKKABLIGI. Sodda yechim (matnni qayta
/// yig'ib, kursorni oxiriga qo'yish) maydonni faqat oxiridan tahrirlanadigan
/// qilib qo'yadi: o'rtadagi raqamni tuzatmoqchi bo'lgan odamning kursori har
/// bosishda oxiriga sakrab ketadi. Shuning uchun kursorning chapidagi
/// RAQAMLAR sanaladi va yangi matnda aynan o'sha raqamdan keyin tiklanadi —
/// `ai_cadastre_screen.dart` dagi kadastr niqobi bilan bir xil usul.
library;

import 'package:flutter/services.dart';

/// Minglar orasidagi ajratgich. [formatBozorAmount] bilan BIR XIL bo'lishi
/// shart, aks holda kiritilayotgan narx va e'londagi narx boshqacha
/// ko'rinardi.
const String kAmountGroupSeparator = ' ';

/// Guruhlangan matndan faqat raqamlarni qaytaradi: `'5 002 323'` → `'5002323'`.
///
/// Qoralama va so'rov XOM raqamni saqlaydi: `num.tryParse('5 002 323')`
/// `null` qaytaradi, ya'ni ajratgichli matn bazaga `0` bo'lib tushardi.
String digitsOnly(String text) => text.replaceAll(RegExp(r'\D'), '');

/// `1234567` → `1 234 567`.
String groupDigits(String digits) {
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(kAmountGroupSeparator);
    buf.write(digits[i]);
  }
  return buf.toString();
}

class AmountInputFormatter extends TextInputFormatter {
  const AmountInputFormatter({this.maxDigits = 12});

  /// Xom raqamlar chegarasi. 12 xona = 999 milliard so'm; bundan kattasi
  /// e'lon emas, terish xatosi.
  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final all = digitsOnly(newValue.text);
    final digits = all.substring(0, all.length.clamp(0, maxDigits));
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }

    // Kursordan CHAPDA nechta RAQAM bor — ajratgichlar hisobga olinmaydi.
    final end = newValue.selection.end.clamp(0, newValue.text.length);
    final digitsBeforeCaret = digitsOnly(
      newValue.text.substring(0, end),
    ).length.clamp(0, digits.length);

    final text = groupDigits(digits);

    // O'sha raqamdan keyingi o'ringa qaytamiz: matnni boshidan yurib,
    // kerakli raqamni sanaganimizda to'xtaymiz.
    var offset = text.length;
    var seen = 0;
    for (var i = 0; i < text.length; i++) {
      if (seen == digitsBeforeCaret) {
        offset = i;
        break;
      }
      if (text[i] != kAmountGroupSeparator) seen++;
    }
    // ⚠️ Kursorni ajratgichdan «keyinga surish» KERAK EMAS va zararli:
    // `59| 002 323` — bu aynan «9» dan keyingi joy, ya'ni to'g'ri. Surilsa
    // kursor foydalanuvchi kiritgan raqamdan bitta o'ngga sakrardi.

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
