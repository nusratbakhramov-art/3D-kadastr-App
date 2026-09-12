// "Taqiqni tekshirish" ekrani aytadigan yagona gap shu parserdan chiqadi.
//
// davreestr.uz natija sahifasi cheklov qatorini FAQAT cheklov bor obyektda
// chizadi — toza obyektda `cad_search_bans` katakchasi umuman yo'q. Ya'ni
// "taqiq yo'q" degan javob qatorning YO'QLIGIga tayanadi, bu esa xavfli
// assimetriya: sayt markupini o'zgartirsa yoki javob umuman natija sahifasi
// bo'lmasa, parser jimgina "toza" deb yuborishi mumkin. Shuning uchun bu
// yerdagi testlar ikkala yo'nalishni ham qo'riqlaydi.
//
// Markup 2026-09-12 da davreestr.uz dan olingan jonli javoblardan ko'chirilgan.
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/services/data/davreestr_client.dart';

/// Obyekt topilgan, lekin cheklov qatori yo'q — reyestrdagi TOZA obyekt.
const _clean = '''
<table class="table">
  <tbody>
    <tr><td><b>Obyekt turi:</b></td><td class="text-right">Ko'p qavatli uydagi xonadon</td></tr>
    <tr>
      <td><b>Umumiy foydali maydoni, (m<sup>2</sup>):</b></td>
      <td  class="text-right"><span>57.04 </span></br></td>
    </tr>
    <tr><td><b>Kadastr qiymati</b></td><td class="text-right">57496320 so'm<sup class="text-red">*</sup></td></tr>
  </tbody>
</table>
<p class="location-color">Toshkent shahri, Mirzo Ulug&#039;bek, Yalang&#039;och daxasi, 1-uy, 23-xonadon</p>
''';

/// Cheklov qatori + `ban-table` jadvali. Uchinchi yozuv ataylab bo'sh
/// "almashuv kodi" bilan — reyestrda bu katak ko'pincha bo'sh keladi.
const _restricted = '''
<table class="table">
  <tbody>
    <tr><td><b>Obyekt turi:</b></td><td class="text-right">Ko'p qavatli uydagi xonadon</td></tr>
    <tr>
      <td><b>Umumiy foydali maydoni, (m<sup>2</sup>):</b></td>
      <td  class="text-right"><span>84.03 </span></br></td>
    </tr>
    <tr>
      <td class="cad_search_bans" style="border-bottom: none !important;"><b>Obyektga nisbatan ta'qiq va cheklovlar:</b></td>
      <td style="border-bottom: none !important;"><p class="text-right text-danger">Mavjud</p><br></td>
    </tr>
    <tr>
      <td colspan="2">
        <div class="table-responsive">
          <table class="ban-table">
            <thead>
              <tr>
                <th style="text-align: center">Taqiq/cheklov raqami</th>
                <th style="text-align: center">Taqiq/cheklov turi</th>
                <th style="text-align: center">Kim tomonidan</th>
                <th style="text-align: center">Sana</th>
                <th style="text-align: center">Ijro xujjatining raqami</th>
                <th style="text-align: center">Ma'lumot almashuv orqali qo'yilganligi (almashuv kodi)</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td style="border: 1px solid #dcdcdc">T6-1009-25-30048</td>
                <td style="border: 1px solid #dcdcdc">Письмо</td>
                <td style="border: 1px solid #dcdcdc">Ген ПРОКУРАТУРА</td>
                <td style="border: 1px solid #dcdcdc">19.12.2025</td>
                <td style="border: 1px solid #dcdcdc">18\\55in-25</td>
                <td style="border: 1px solid #dcdcdc"></td>
              </tr>
              <tr>
                <td style="border: 1px solid #dcdcdc">T6-1009-26-16647</td>
                <td style="border: 1px solid #dcdcdc">Ограничение</td>
                <td style="border: 1px solid #dcdcdc">Банк_запретов</td>
                <td style="border: 1px solid #dcdcdc">14.09.2025</td>
                <td style="border: 1px solid #dcdcdc">170003/2025-52ii</td>
                <td style="border: 1px solid #dcdcdc">21207172-B</td>
              </tr>
            </tbody>
          </table>
        </div>
      </td>
    </tr>
  </tbody>
</table>
<p class="location-color">Toshkent shahri, Mirzo Ulug&#039;bek, Oqqo&#039;rg&#039;on ko&#039;chasi, 6a-uy, 39-xonadon</p>
''';

/// Reyestrda yo'q raqam — sahifada na obyekt, na cheklov bloki bor.
const _notFound = '''
<div class="search-result">
  <p>Davlat Reyestrida ma'lumotlar mavjud emas.</p>
</div>
''';

void main() {
  group('parseResultHtml — ta\'qiq va cheklovlar', () {
    test('cheklov qatori yo\'q obyekt = taqiq yo\'q', () {
      final r = DavreestrClient.parseResultHtml(_clean, '10:09:03:01:03:5039');
      expect(r.hasUsableData, isTrue);
      expect(r.hasRestrictions, isFalse);
      expect(r.restrictions, isEmpty);
    });

    test('cheklov qatori bor obyekt = taqiq bor, yozuvlar bilan', () {
      final r =
          DavreestrClient.parseResultHtml(_restricted, '10:09:01:01:02:5942');
      expect(r.hasRestrictions, isTrue);
      expect(r.restrictions, hasLength(2));

      final first = r.restrictions.first;
      expect(first.number, 'T6-1009-25-30048');
      // Reyestr turni va idorani ruscha qaytaradi — shundayligicha saqlanadi.
      expect(first.kind, 'Письмо');
      expect(first.authority, 'Ген ПРОКУРАТУРА');
      expect(first.date, '19.12.2025');
      expect(first.documentNumber, r'18\55in-25');
      // Reyestrda ko'pincha bo'sh keladigan katak — yozuvni yo'q qilmaydi.
      expect(first.exchangeCode, isEmpty);

      expect(r.restrictions.last.exchangeCode, '21207172-B');

      // `&#039;` kabi HTML-escape'lar ochiladi (manzil shu bilan keladi).
      expect(r.address, contains("Oqqo'rg'on"));
    });

    test('sarlavha qatori (<th>) yozuv sifatida hisoblanmaydi', () {
      final r =
          DavreestrClient.parseResultHtml(_restricted, '10:09:01:01:02:5942');
      expect(
        r.restrictions.map((e) => e.number),
        isNot(contains('Taqiq/cheklov raqami')),
      );
    });

    test('obyektning o\'zi topilmasa holat NOMA\'LUM bo\'ladi, "toza" emas', () {
      // Bu eng qimmat xato bo'lardi: reyestrda yo'q raqam (yoki rad etilgan
      // forma / rate-limit) ham cheklov bloki YO'Q sahifa qaytaradi. Parser
      // bunday javobni `false` ("taqiq yo'q") emas, `null` ("noma'lum") deb
      // belgilaydi — chaqiruvchi tekshirishni unutsa ham yashil javob chiqmaydi.
      final r = DavreestrClient.parseResultHtml(_notFound, '99:99:99:99:99:9999');
      expect(r.hasUsableData, isFalse);
      expect(r.hasRestrictions, isNull);
      expect(r.restrictions, isEmpty);
    });

    test('inkor matni yozilgan bo\'lsa ham taqiq yo\'q deb o\'qiladi', () {
      // Bugun sayt bunday chizmaydi (qator butunlay tushib qoladi), lekin
      // qaytarib qo'ysa parser uni to'g'ri o'qishi kerak.
      const html = '''
<tr>
  <td class="cad_search_bans"><b>Obyektga nisbatan ta'qiq va cheklovlar:</b></td>
  <td><p class="text-right">Mavjud emas</p></td>
</tr>
<p class="location-color">Toshkent shahri</p>
''';
      final r = DavreestrClient.parseResultHtml(html, '10:09:01:01:02:5942');
      expect(r.hasRestrictions, isFalse);
      expect(r.restrictions, isEmpty);
    });
  });
}
