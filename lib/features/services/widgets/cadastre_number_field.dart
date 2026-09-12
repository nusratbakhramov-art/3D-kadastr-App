/// Kadastr raqami maydoni — `NN:NN:NN:NN:NN:NNNN[:NNNN…]` niqobi bilan.
///
/// Niqob AI Baholash va 3D kadastr ekranlaridagi bilan bir xil xulqqa ega:
/// ikki nuqtalar yozilayotganda O'ZI qo'yiladi, kursor esa satr o'rtasiga
/// tahrir qilinganda oxiriga sakramaydi.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';

/// To'liq (yoki kengaytirilgan) kadastr raqami: asos `NN:NN:NN:NN:NN:NNNN`,
/// ixtiyoriy davomi — uchastka/bino/xonadon bloklari
/// (`10:09:01:01:02:5942:0001:039`).
final RegExp kCadastreNumberRe = RegExp(
  r'^\d{2}:\d{2}:\d{2}:\d{2}:\d{2}:\d{4}(:\d{1,4})*$',
);

class CadastreNumberField extends StatelessWidget {
  const CadastreNumberField({
    super.key,
    required this.controller,
    this.suffix,
  });

  final TextEditingController controller;

  /// Maydon ichidagi o'ng belgi — masalan qidiruv spinneri yoki tasdiq
  /// belgisi. `null` bo'lsa joy egallamaydi.
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = isDark ? const Color(0xFF1F2426) : Colors.white;
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : const Color(0xFFB4B9BF);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final borderColor = isDark
        ? const Color(0xFF2C3133)
        : const Color(0xFFE3E5E8);

    return TextField(
      controller: controller,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      // `phone` (not `number`) — Android'ning raqam klaviaturasi qo'yilgan
      // matndan raqam bo'lmagan belgilarni jimgina qirqib tashlaydi, ya'ni
      // "11:14:04:01:01:1630" ko'rinishidagi buferdagi qiymat niqobgacha
      // yetib kelmasdi.
      keyboardType: TextInputType.phone,
      inputFormatters: [CadastreMaskFormatter()],
      style: TextStyle(
        fontFamily: 'MTSText',
        fontSize: 15,
        letterSpacing: 0.3,
        color: textColor,
      ),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        hintText: 'XX:XX:XX:XX:XX:XXXX',
        hintStyle: TextStyle(
          fontFamily: 'MTSText',
          fontSize: 15,
          letterSpacing: 0.3,
          color: hintColor,
        ),
        suffixIcon: suffix,
        filled: true,
        fillColor: fillColor,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.splashGreen, width: 1.4),
        ),
      ),
    );
  }
}

class CadastreMaskFormatter extends TextInputFormatter {
  static const _segments = [2, 2, 2, 2, 2, 4];

  /// Asos — 14 raqam; qolgani uchastka/bino/xonadon dumi uchun
  /// (`10:09:01:01:02:5942:0001:039`).
  static const _maxDigits = 25;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final allDigits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final digits = allDigits.substring(
      0,
      allDigits.length.clamp(0, _maxDigits),
    );

    // Kursordan CHAPDA nechta raqam borligini sanaymiz — ikki nuqtalar qayta
    // qo'yilgach kursorni o'sha raqamdan keyin tiklash uchun (aks holda u har
    // safar satr oxiriga sakrab, o'rtadan tahrirlashni buzardi).
    final selEnd = newValue.selection.end.clamp(0, newValue.text.length);
    final digitsBeforeCaret = newValue.text
        .substring(0, selEnd)
        .replaceAll(RegExp(r'\D'), '')
        .length
        .clamp(0, digits.length);

    final buffer = StringBuffer();
    var consumed = 0;
    for (var i = 0; i < _segments.length; i++) {
      if (consumed >= digits.length) break;
      final take = _segments[i];
      final end = (consumed + take).clamp(0, digits.length);
      if (i > 0) buffer.write(':');
      buffer.write(digits.substring(consumed, end));
      consumed = end;
    }
    // Asosdan keyingi dum — 4 tadan bo'lib, ikki nuqta bilan ajratamiz.
    while (consumed < digits.length) {
      final end = (consumed + 4).clamp(0, digits.length);
      buffer.write(':');
      buffer.write(digits.substring(consumed, end));
      consumed = end;
    }
    final formatted = buffer.toString();

    // "Kursordan chapda N raqam" → formatlangan satrdagi o'rin (ikki
    // nuqtalarni hisobga olib).
    var offset = 0;
    var seen = 0;
    while (offset < formatted.length && seen < digitsBeforeCaret) {
      if (formatted[offset] != ':') seen++;
      offset++;
    }
    // Blok tugab, ajratgich oldida qolib ketsak — undan o'tamiz, shunda
    // yozish keyingi blokka tabiiy o'tadi.
    if (offset < formatted.length && formatted[offset] == ':') offset++;

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: offset.clamp(0, formatted.length),
      ),
    );
  }
}
