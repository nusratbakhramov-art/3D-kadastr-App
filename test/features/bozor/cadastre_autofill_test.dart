// Reyestr javobidan e'lon maydonlariga NIMA tushishi.
//
// Bu yerdagi har bir test ekranda KO'RINMAYDIGAN xatoni qo'riqlaydi:
//
//   * yer maydoni sotixda, bino maydoni m² da — chalkashtirsak e'lon 100
//     barobar xato maydon bilan chiqadi va buni hech kim tekshirmaydi;
//   * har mulk turida asosiy maydonning KALITI boshqa, va u backenddagi
//     `primary_area_key` bilan mos kelmasa lenta filtri e'lonni topmaydi;
//   * foydalanuvchi qo'lda yozgan qiymat ustidan yozilsa — u o'zgarganini
//     sezmaydi.
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/bozor/data/cadastre_autofill.dart';
import 'package:kadastr/features/bozor/models/bozor_draft.dart';
import 'package:kadastr/features/services/api_cadastre_service.dart';

/// Yakka tartibdagi uy — jonli davreestr javobidagi raqamlar
/// (`10:06:44:02:02:0514`).
const _house = CadastreLookupResult(
  cadastreNumber: '10:06:44:02:02:0514',
  address: "Toshkent shahri, Sirg'ali tumani, Ko'hna Qumariq MFY, "
      "Oqsoqollar 4-tor ko'chasi, 4-uy",
  objectTypeHint: 'Yakka tartibdagi uy-joy',
  totalArea: 282.55,
  livingArea: 206.06,
  landArea: 1209,
);

/// Ko'p qavatli uydagi xonadon (`10:09:01:01:02:5942:0001:039`).
const _flat = CadastreLookupResult(
  cadastreNumber: '10:09:01:01:02:5942:0001:039',
  address: "Toshkent shahri, Mirzo Ulug‘bek, Xamid Olimjon MFY, "
      "Oqqo'rg'on ko'chasi, 6а-uy, 39-xonadon",
  objectTypeHint: "Ko'p qavatli uydagi xonadon",
  totalArea: 84.03,
  livingArea: 46.45,
);

void main() {
  group('maydon birligi', () {
    test('uyda yer maydoni SOTIXGA o\'giriladi, uy maydoni m² qoladi', () {
      final plan = buildCadastreAutofill(
        info: _house,
        type: PropertyType.house,
      );
      // 1209 m² = 12.09 sotix.
      expect(plan.params['land_area'], '12.09');
      expect(plan.params['house_area'], '282.55');
    });

    test('uchastkada ham yer maydoni sotixda', () {
      final plan = buildCadastreAutofill(
        info: _house,
        type: PropertyType.land,
      );
      expect(plan.params['land_area'], '12.09');
      // Uchastka e'lonida bino maydoni so'ralmaydi.
      expect(plan.params.containsKey('house_area'), isFalse);
    });

    test('butun son kasrsiz yoziladi — maydon MATN maydoni', () {
      const round = CadastreLookupResult(
        cadastreNumber: 'x',
        address: 'Toshkent shahri, Chilonzor, 1-uy',
        totalArea: 84,
        landArea: 1000,
      );
      final plan =
          buildCadastreAutofill(info: round, type: PropertyType.house);
      expect(plan.params['house_area'], '84');
      expect(plan.params['land_area'], '10');
    });
  });

  group('qaysi parametrga tushadi', () {
    test('har mulk turi o\'z asosiy maydon kalitini oladi', () {
      const expected = {
        PropertyType.apartment: 'total_area',
        PropertyType.newBuildingApartment: 'total_area',
        PropertyType.house: 'house_area',
        PropertyType.commercial: 'premises_area',
        PropertyType.garage: 'garage_area',
      };
      for (final entry in expected.entries) {
        final plan = buildCadastreAutofill(info: _flat, type: entry.key);
        expect(
          plan.params[entry.value],
          '84.03',
          reason: '${entry.key.name} → ${entry.value}',
        );
      }
    });

    test('kalitlar backenddagi primary_area_key bilan bir xil', () {
      // `app/services/listing_param_schema.py` dagi xarita.
      expect(primaryAreaKey(PropertyType.apartment), 'total_area');
      expect(primaryAreaKey(PropertyType.newBuildingApartment), 'total_area');
      expect(primaryAreaKey(PropertyType.house), 'house_area');
      expect(primaryAreaKey(PropertyType.land), 'land_area');
      expect(primaryAreaKey(PropertyType.commercial), 'premises_area');
      expect(primaryAreaKey(PropertyType.garage), 'garage_area');
      expect(primaryAreaKey(PropertyType.otherNonResidential), isNull);
    });

    test('«Boshqa noturar joy» da parametr umuman to\'ldirilmaydi', () {
      // Bu turda «Параметры» qadami yo'q — qiymat yuborsak backend uni
      // 400 bilan rad etardi.
      final plan = buildCadastreAutofill(
        info: _flat,
        type: PropertyType.otherNonResidential,
      );
      expect(plan.params, isEmpty);
    });

    test('kvartirada yashash maydoni ham to\'ladi', () {
      final plan =
          buildCadastreAutofill(info: _flat, type: PropertyType.apartment);
      expect(plan.params['total_area'], '84.03');
      expect(plan.params['living_area'], '46.45');
    });

    test('yo\'q yoki nolga teng maydon yozilmaydi', () {
      const empty = CadastreLookupResult(
        cadastreNumber: 'x',
        address: 'Toshkent shahri, Chilonzor, 1-uy',
        totalArea: 0,
      );
      final plan =
          buildCadastreAutofill(info: empty, type: PropertyType.apartment);
      expect(plan.params, isEmpty);
    });
  });

  group('ustidan YOZMAYDI', () {
    test('to\'lgan parametr o\'zgarmaydi', () {
      final plan = buildCadastreAutofill(
        info: _house,
        type: PropertyType.house,
        currentParams: const {'house_area': '300'},
      );
      expect(plan.params.containsKey('house_area'), isFalse);
      // Bo'sh qolgani esa baribir to'ladi.
      expect(plan.params['land_area'], '12.09');
    });

    test('to\'lgan matn maydonlari natijaga tushmaydi', () {
      final plan = buildCadastreAutofill(
        info: _flat,
        type: PropertyType.apartment,
        currentAddress: 'Qo\'lda yozilgan manzil',
        currentHouseNumber: '99',
        currentApartmentNumber: '7',
      );
      expect(plan.address, isNull);
      expect(plan.houseNumber, isNull);
      expect(plan.apartmentNumber, isNull);
    });

    test('faqat bo\'shliqdan iborat qiymat BO\'SH hisoblanadi', () {
      final plan = buildCadastreAutofill(
        info: _flat,
        type: PropertyType.apartment,
        currentAddress: '   ',
        currentParams: const {'total_area': '  '},
      );
      expect(plan.address, isNotNull);
      expect(plan.params['total_area'], '84.03');
    });

    test('viloyat/tuman allaqachon tanlangan bo\'lsa taklif qilinmaydi', () {
      final plan = buildCadastreAutofill(
        info: _flat,
        type: PropertyType.apartment,
        hasRegion: true,
        hasDistrict: true,
      );
      expect(plan.regionName, isNull);
      expect(plan.districtName, isNull);
    });
  });

  group('manzil qismlari', () {
    test('bo\'sh maydonlarga manzil, uy va xonadon tushadi', () {
      final plan =
          buildCadastreAutofill(info: _flat, type: PropertyType.apartment);
      expect(plan.address, contains('Xamid Olimjon'));
      expect(plan.houseNumber, '6а');
      expect(plan.apartmentNumber, '39');
      expect(plan.regionName, 'Toshkent shahri');
      expect(plan.districtName, 'Mirzo Ulug‘bek');
    });

    test('manzilsiz javob HECH NARSA to\'ldirmaydi', () {
      // Reyestr javob bermasa (yoki bo'sh javob bersa) parametrlarni ham
      // to'ldirmaslik kerak: maydon bor, manzil yo'q — bu natija emas.
      const blank = CadastreLookupResult(
        cadastreNumber: 'x',
        totalArea: 84.03,
      );
      final plan =
          buildCadastreAutofill(info: blank, type: PropertyType.apartment);
      expect(plan.isEmpty, isTrue);
    });
  });
}
