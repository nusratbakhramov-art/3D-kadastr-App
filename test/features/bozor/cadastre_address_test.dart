// Reyestr manzilini e'lon maydonlariga ajratish.
//
// Nega bu testlar bor. Ajratish JIMGINA noto'g'ri ishlashi mumkin: tuman
// tanlanmay qolsa foydalanuvchi ko'radi va o'zi tanlaydi, lekin NOTO'G'RI
// tuman tanlansa u to'g'ri deb o'ylab tashlab ketadi — e'lon xato manzil
// bilan chiqadi. Shuning uchun bu yerdagi testlarning yarmi "topmasligi
// kerak" holatlarini qo'riqlaydi.
//
// Manzillar 2026-09-12 da davreestr.uz dan olingan JONLI javoblardan
// ko'chirilgan (apostroflar ham aynan o'sha shaklda — U+2018 va ASCII
// aralash, bu qasddan).
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/bozor/data/cadastre_address.dart';

/// `scripts/seed_market_regions.py` dagi ro'yxatning bir qismi.
const _cityDistricts = [
  'Bektemir',
  'Chilonzor',
  'Mirobod',
  "Mirzo Ulug'bek",
  'Olmazor',
  'Sergeli',
  'Shayxontohur',
  'Uchtepa',
  'Yakkasaroy',
  'Yangihayot',
  'Yashnobod',
  'Yunusobod',
];

const _provinceDistricts = [
  'Angren',
  'Bekobod',
  "Bo'ka",
  "Bo'stonliq",
  'Chinoz',
  'Chirchiq',
  'Ohangaron',
  "Oqqo'rg'on",
  'Olmaliq',
  'Parkent',
  'Piskent',
  'Qibray',
  'Quyichirchiq',
  "O'rtachirchiq",
  'Toshkent tumani',
  "Yangiyo'l",
  'Yuqorichirchiq',
  'Zangiota',
];

const _regions = ['Toshkent shahri', 'Toshkent viloyati', 'Andijon'];

void main() {
  group('parseCadastreAddress — jonli manzillar', () {
    test('kvartira: viloyat, tuman, uy va xonadon ajraladi', () {
      final p = parseCadastreAddress(
        "Toshkent shahri, Mirzo Ulug‘bek, Xamid Olimjon MFY, "
        "Oqqo'rg'on ko'chasi, 6а-uy, 39-xonadon",
      );
      expect(p.regionName, 'Toshkent shahri');
      expect(p.districtName, 'Mirzo Ulug‘bek');
      // Raqamdan keyingi harf KIRILLCHA — reyestrda aynan shunday keladi.
      expect(p.houseNumber, '6а');
      expect(p.apartmentNumber, '39');
    });

    test('uy (xonadonsiz): xonadon raqami null qoladi', () {
      final p = parseCadastreAddress(
        "Toshkent shahri, Sirg‘ali tumani, Ko'hna Qumariq MFY, "
        "Oqsoqollar 4-tor ko'chasi, 4-uy",
      );
      expect(p.districtName, 'Sirg‘ali tumani');
      expect(p.houseNumber, '4');
      expect(p.apartmentNumber, isNull);
    });

    test('tirnoq va lotincha bo\'lmagan bo\'lak ajratishni buzmaydi', () {
      final p = parseCadastreAddress(
        'Toshkent viloyati, Yuqorichirchiq tumani, Saksanota MFY, '
        '"HAYDAROV VAHID HAYDAROVICH" Vishneviy BUSH, 11-uy',
      );
      expect(p.regionName, 'Toshkent viloyati');
      expect(p.districtName, 'Yuqorichirchiq tumani');
      expect(p.houseNumber, '11');
    });

    test("qisqartirilgan tuman («Chirchiq sh.») ham bo'lak sifatida keladi", () {
      final p = parseCadastreAddress(
        'Toshkent viloyati, Chirchiq sh., Ishonch MFY, '
        "Chirchiq 50-yilligi shoh koʼchasi, 61-uy, 36-xonadon",
      );
      expect(p.districtName, 'Chirchiq sh.');
      expect(p.houseNumber, '61');
      expect(p.apartmentNumber, '36');
    });
  });

  group('parseCadastreAddress — taxmin qilmaydi', () {
    test("bo'sh yoki null manzil hamma maydonni bo'sh qoldiradi", () {
      for (final a in [null, '', '   ', ',,,']) {
        final p = parseCadastreAddress(a);
        expect(p.regionName, isNull, reason: 'manba: ${a ?? 'null'}');
        expect(p.districtName, isNull);
        expect(p.houseNumber, isNull);
        expect(p.apartmentNumber, isNull);
      }
    });

    test("uy bo'lagi tuman o'rniga tushib qolmaydi", () {
      // Ikki bo'lakli kalta manzil: ikkinchisi tuman EMAS.
      final p = parseCadastreAddress('Toshkent shahri, 4-uy');
      expect(p.regionName, 'Toshkent shahri');
      expect(p.districtName, isNull);
      expect(p.houseNumber, '4');
    });

    test("«uy-joy» kabi so'z uy raqami deb o'qilmaydi", () {
      final p = parseCadastreAddress(
        'Toshkent shahri, Uchtepa, Yakka tartibdagi uy-joy',
      );
      expect(p.houseNumber, isNull);
    });
  });

  group('matchPlaceIndex', () {
    test('apostrof shakli farq qilsa ham topadi', () {
      // davreestr U+2018, baza ASCII — normallashtirmasa hech qachon mos
      // kelmasdi.
      final i = matchPlaceIndex(_cityDistricts, 'Mirzo Ulug‘bek');
      expect(_cityDistricts[i!], "Mirzo Ulug'bek");
    });

    test("qo'shimchasi bor nom qo'shimchasizi bilan mos keladi", () {
      final i = matchPlaceIndex(_provinceDistricts, 'Chirchiq sh.');
      expect(_provinceDistricts[i!], 'Chirchiq');
      final j = matchPlaceIndex(_provinceDistricts, 'Yuqorichirchiq tumani');
      expect(_provinceDistricts[j!], 'Yuqorichirchiq');
    });

    test("viloyat qo'shimchasi KESILMAYDI — shahri va viloyati bir xil emas",
        () {
      // Eng qimmat xato: ikkalasi «toshkent» ga tushsa, shahar e'loni
      // viloyatga (yoki teskarisi) yozilardi.
      expect(_regions[matchPlaceIndex(_regions, 'Toshkent shahri')!],
          'Toshkent shahri');
      expect(_regions[matchPlaceIndex(_regions, 'Toshkent viloyati')!],
          'Toshkent viloyati');
    });

    test("ikki nomzod bir xil qisqarsa — hech biri tanlanmaydi", () {
      const ambiguous = ['Andijon shahri', 'Andijon tumani'];
      expect(matchPlaceIndex(ambiguous, 'Andijon'), isNull);
      // To'liq moslik esa baribir ishlaydi.
      expect(matchPlaceIndex(ambiguous, 'Andijon tumani'), 1);
    });

    test('boshqacha transliteratsiya topilmaydi — va bu ATAYLAB', () {
      // Reyestr «Sirg'ali», baza «Sergeli» deydi. Ularni bog'lash uchun
      // qo'lda lug'at kerak; lug'atsiz taxmin qilgandan ko'ra tumanni bo'sh
      // qoldirib, foydalanuvchiga tanlatgan ma'qul.
      expect(matchPlaceIndex(_cityDistricts, "Sirg‘ali tumani"), isNull);
    });

    test("bo'sh yoki null nomzod null beradi", () {
      expect(matchPlaceIndex(_cityDistricts, null), isNull);
      expect(matchPlaceIndex(_cityDistricts, '  '), isNull);
    });
  });
}
