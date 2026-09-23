import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/bozor/widgets/amount_input_formatter.dart';

/// Narx maydonining guruhlagichi.
///
/// Mijozning shikoyati: narxni raqamning O'RTASIDAN tahrirlab bo'lmaydi.
/// Sodda guruhlagich har bosishda kursorni matn oxiriga sakratadi, ya'ni
/// `5002323` dagi ikkinchi raqamni tuzatmoqchi bo'lgan odam har safar
/// oxiriga otilib ketadi. Shu sababli testlarning YARMI aynan kursor
/// haqida — matnning o'zi to'g'ri chiqishi yetarli emas.
void main() {
  const f = AmountInputFormatter();

  /// Klaviaturadan kiritishni taqlid qiladi: [before] matnining [at]
  /// o'rniga [typed] qo'yiladi.
  TextEditingValue type(String before, int at, String typed) {
    final next = before.substring(0, at) + typed + before.substring(at);
    return f.formatEditUpdate(
      TextEditingValue(
        text: before,
        selection: TextSelection.collapsed(offset: at),
      ),
      TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: at + typed.length),
      ),
    );
  }

  group('guruhlash', () {
    test('uchtalab ajratiladi', () {
      expect(groupDigits('5002323'), '5 002 323');
      expect(groupDigits('100'), '100');
      expect(groupDigits('1000'), '1 000');
      expect(groupDigits(''), '');
    });

    test('ajratgich e\'londagi narx bilan bir xil', () {
      // `formatBozorAmount` ham oddiy probel qo'yadi — ikkisi ajralsa,
      // kiritilayotgan narx va chop etilgan narx boshqacha ko'rinardi.
      expect(kAmountGroupSeparator, ' ');
    });

    test('xom raqamlar qaytariladi', () {
      expect(digitsOnly('5 002 323'), '5002323');
      expect(digitsOnly('12a3'), '123');
      expect(digitsOnly(''), '');
    });
  });

  group('oxiridan terish', () {
    test('raqam qo\'shilgach matn guruhlanadi', () {
      final r = type('5 002 32', 8, '3');
      expect(r.text, '5 002 323');
    });

    test('kursor oxirida qoladi', () {
      final r = type('5 002 32', 8, '3');
      expect(r.selection.baseOffset, r.text.length);
    });

    test('mingga o\'tganda ham surilmaydi', () {
      final r = type('100', 3, '0');
      expect(r.text, '1 000');
      expect(r.selection.baseOffset, 5);
    });
  });

  group('O\'RTADAN tahrirlash — asosiy shikoyat', () {
    test('o\'rtaga qo\'yilgan raqamdan keyin turadi', () {
      // `5 002 323` ning boshidagi «5» dan keyin «9»: `59 002 323`.
      final r = type('5 002 323', 1, '9');
      expect(r.text, '59 002 323');
      // Kursor «9» dan keyin — ya'ni ikkinchi belgidan keyin.
      expect(r.selection.baseOffset, 2);
    });

    test('yangi ajratgich paydo bo\'lganda ham to\'g\'ri sanaydi', () {
      // `12 345` ning o'rtasiga raqam: guruhlar qayta chiziladi.
      final r = type('12 345', 2, '9');
      expect(r.text, '129 345');
      expect(digitsOnly(r.text.substring(0, r.selection.baseOffset)), '129');
    });

    test('kursor chapidagi RAQAMLAR soni saqlanadi', () {
      // Kursor ajratgichning yonida turishi mumkin (`59| 002`) — bu
      // to'g'ri joy. Muhimi: uning chapida qancha raqam bo'lsa, shuncha
      // qolishi. Shuni tekshiramiz, belgi turini emas.
      for (final at in [1, 2, 4, 5, 7]) {
        const before = '5 002 323';
        final want = digitsOnly(before.substring(0, at)).length + 1;
        final r = type(before, at, '7');
        expect(
          digitsOnly(r.text.substring(0, r.selection.baseOffset)).length,
          want,
          reason: 'kursor $at o\'rnida',
        );
      }
    });
  });

  group('o\'chirish', () {
    TextEditingValue backspaceAt(String before, int caret) {
      final next = before.substring(0, caret - 1) + before.substring(caret);
      return f.formatEditUpdate(
        TextEditingValue(
          text: before,
          selection: TextSelection.collapsed(offset: caret),
        ),
        TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: caret - 1),
        ),
      );
    }

    test('oxirgi raqam o\'chsa guruhlar qayta chiziladi', () {
      final r = backspaceAt('1 000', 5);
      expect(r.text, '100');
      expect(r.selection.baseOffset, 3);
    });

    test('hammasi o\'chsa maydon bo\'sh qoladi', () {
      final r = f.formatEditUpdate(
        const TextEditingValue(text: '5'),
        const TextEditingValue(text: ''),
      );
      expect(r.text, '');
    });
  });

  group('chegara', () {
    test('12 xonadan ortig\'i qabul qilinmaydi', () {
      final r = f.formatEditUpdate(
        const TextEditingValue(text: ''),
        const TextEditingValue(text: '1234567890123456'),
      );
      expect(digitsOnly(r.text).length, 12);
    });

    test('raqam bo\'lmagan belgilar tushib qoladi', () {
      final r = f.formatEditUpdate(
        const TextEditingValue(text: ''),
        const TextEditingValue(text: r'12a3$4'),
      );
      expect(r.text, '1 234');
    });
  });
}
