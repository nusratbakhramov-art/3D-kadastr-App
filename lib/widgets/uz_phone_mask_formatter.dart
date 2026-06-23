import 'package:flutter/services.dart';

/// Formats the national part of an Uzbek mobile number as `XX XXX-XX-XX`
/// (9 digits, no country code) and — crucially — maps the cursor THROUGH the
/// reformat, so backspacing or inserting in the middle keeps the caret where
/// the user expects instead of jumping it to the end. Hard-caps at 9 digits;
/// a pasted full number ("+998…" / "998…") drops the country code.
///
/// Shared by the login phone field and the Kadastr lead form.
class UzPhoneMaskFormatter extends TextInputFormatter {
  const UzPhoneMaskFormatter();

  static const int _maxDigits = 9;

  static bool _isDigit(String c) {
    if (c.isEmpty) return false;
    final code = c.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }

  /// `digits` (≤9) → `XX XXX-XX-XX`.
  static String format(String digits) {
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2) {
        buf.write(' ');
      } else if (i == 5 || i == 7) {
        buf.write('-');
      }
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Count digits to the LEFT of the cursor — this anchors the caret across
    // the reformat.
    final rawCursor =
        newValue.selection.baseOffset.clamp(0, newValue.text.length);
    final digitsBeforeCursor = newValue.text
        .substring(0, rawCursor)
        .replaceAll(RegExp(r'\D'), '')
        .length;

    var allDigits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (allDigits.length > _maxDigits && allDigits.startsWith('998')) {
      allDigits = allDigits.substring(3);
    }
    final clipped = allDigits.length > _maxDigits
        ? allDigits.substring(0, _maxDigits)
        : allDigits;

    final formatted = format(clipped);

    // Walk the formatted string until we've passed `digitsBeforeCursor` digits
    // — separators count toward the offset but not the digit total.
    final targetDigits = digitsBeforeCursor.clamp(0, clipped.length);
    var seen = 0;
    var pos = 0;
    while (pos < formatted.length && seen < targetDigits) {
      if (_isDigit(formatted[pos])) seen++;
      pos++;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: pos),
      composing: TextRange.empty,
    );
  }
}
