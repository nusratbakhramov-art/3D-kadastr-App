import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/market/listing_detail_screen.dart';

void main() {
  group('marketShareDescription', () {
    test('bo\'sh tavsifda null — qator umuman qo\'shilmaydi', () {
      // Hozircha prod e'lonlarining hech birida tavsif yo'q, shuning uchun
      // ulashish matni tavsifsiz ham to'g'ri ko'rinishi kerak.
      expect(marketShareDescription(null), isNull);
      expect(marketShareDescription(''), isNull);
      expect(marketShareDescription('   \n  '), isNull);
    });

    test('qisqa tavsif o\'zgarishsiz qoladi', () {
      expect(marketShareDescription('Zamonaviy oshxona'), 'Zamonaviy oshxona');
    });

    test('ko\'p qatorli tavsif bitta qatorga yig\'iladi', () {
      expect(
        marketShareDescription('Birinchi qator\n\n  ikkinchi   qator '),
        'Birinchi qator ikkinchi qator',
      );
    });

    test('uzun tavsif so\'z chegarasida kesiladi', () {
      final long = List.filled(60, 'sozlar').join(' '); // ≫180 belgi
      final out = marketShareDescription(long)!;

      expect(out.length, lessThanOrEqualTo(181));
      expect(out, endsWith('…'));
      // So'z o'rtasidan kesilmasin.
      expect(out, isNot(contains('sozla…')));
    });

    test('bo\'shliqsiz uzun matn ham kesiladi (cheksiz nom himoyasi)', () {
      final out = marketShareDescription('a' * 400)!;
      expect(out.length, 181);
      expect(out, endsWith('…'));
    });
  });

  group('marketGroupDigits', () {
    test('minglarni bo\'shliq bilan ajratadi', () {
      expect(marketGroupDigits(1000), '1 000');
      expect(marketGroupDigits(12500000), '12 500 000');
      expect(marketGroupDigits(999), '999');
    });
  });

  group('marketListingLink', () {
    test('backendId yo\'q bo\'lsa havola bo\'lmaydi', () {
      expect(marketListingLink(null), isNull);
    });

    test('AASA dagi yo\'l bilan bir xil bo\'ladi', () {
      // `/market/*` backend AASA'sida ro'yxatdan o'tgan — shakl o'zgarsa
      // Universal Link jim turib ishlamay qoladi.
      expect(marketListingLink(17), 'https://api.3dkadastr.uz/market/17');
    });
  });
}
