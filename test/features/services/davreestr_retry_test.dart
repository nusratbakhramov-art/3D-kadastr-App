// 302 kelganda qayta urinish kerakmi — bitta qaror, ikki xil oqibat.
//
// ⚠️ NEGA BU TEST BOR. davreestr HAR QANDAY rad etishni `302 → /uz` bilan
// qaytaradi va sababini keyingi sahifa yuklanishiga flash qiladi. 302 ning
// o'z tanasi atigi «Redirecting to …» — unda hech qanday naqsh yo'q.
//
// Ilgari tasnif faqat javob tanasiga qarardi, ya'ni captcha xato bo'lsa ham
// «maxfiy kod noto» topilmasdi va QAYTA URINISH SIKLI UMUMAN ISHGA
// TUSHMASDI. Urinish bekorga sarflanib, foydalanuvchi «Ma'lumot olib
// bo'lmadi» ni ko'rardi — 2026-09-12 dagi «302 ko'p beryapti» shikoyati
// aynan shu edi.
//
// Teskari xato ham qimmat: tanilgan sababda (rate limit, topilmadi) qayta
// urinsak, sakkizta captcha bekorga yoqiladi va saytga keraksiz yuk tushadi.
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/services/data/davreestr_client.dart';

void main() {
  bool retry(String body, {bool redirect = true}) =>
      DavreestrClient.shouldRetryRejected(
        isRedirect: redirect,
        bodyLower: body.toLowerCase(),
      );

  test('302 + SABAB YO\'Q → qayta urinamiz (deyarli har doim captcha)', () {
    // Aynan foydalanuvchi ko'rgan tana.
    expect(
      retry('Redirecting to <a href="https://davreestr.uz/uz">…</a>.'),
      isTrue,
    );
    expect(retry(''), isTrue);
  });

  test('302 + «maxfiy kod noto» → qayta urinamiz (ochiq captcha xatosi)', () {
    // Bu shox ilgari ham ishlardi va ishlashda davom etadi — lekin u
    // `shouldRetryRejected` dan EMAS, o'z tekshiruvidan o'tadi.
    expect(retry('Maxfiy kod notoʻgʻri kiritildi'), isFalse,
        reason: 'ochiq sabab bor — o\'z shoxiga ketsin');
  });

  test('302 + RATE LIMIT → qayta urinmaymiz', () {
    // Sakkizta captcha yoqib, saytni yanada bo'g'ishning ma'nosi yo'q.
    expect(retry("Bazaga so'rovlar soni oshib ketdi"), isFalse);
    expect(retry('Rate limit exceeded'), isFalse);
  });

  test('302 + TOPILMADI → qayta urinmaymiz', () {
    // Raqam yo'q bo'lsa yangi captcha ham yordam bermaydi.
    expect(retry('Bunday kadastr raqami topilmadi'), isFalse);
  });

  test('302 BO\'LMASA hech qachon qayta urinmaymiz', () {
    // 200 javob o'z yo'lidan ketadi: yo natija, yo parser eskirgan.
    expect(retry('Redirecting to …', redirect: false), isFalse);
    expect(retry('', redirect: false), isFalse);
  });
}
