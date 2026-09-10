import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/bozor/models/bozor_draft.dart';
import 'package:kadastr/features/bozor/models/param_schema.dart';

/// 3-qadam validatsiyasi qamrovi.
///
/// SABAB (2026-09-10, prod'da uchradi): `_isComplete()` faqat
/// `type.stepParamFields` ni tekshirardi, ya'ni qadam ekranida KO'RINMAYDIGAN
/// majburiy maydonlar hech qachon tekshirilmasdi. Foydalanuvchi 3-qadamdan
/// o'tib ketardi, yetti qadam to'ldirardi va oxirida
/// `POST /listings/drafts/1/submit` dan tushunarsiz 400 olardi:
///
///     'bathroom_type' toʻldirilishi shart
///
/// Backend sxemasi bilan nomuvofiqlik EMAS — ikkala sxema ham uni majburiy
/// deb belgilagan. Muammo faqat tekshiruv qamrovida edi.
///
/// Bu test ekran mantiqini takrorlaydi (`_missingRequired` private), lekin
/// asosiy da'voni qotiradi: MAJBURIY maydon qadamda ko'rinmasa ham
/// e'tiborsiz qolmasligi kerak.

/// Ekrandagi `_missingRequired` bilan bir xil qoida.
List<ParamField> missingRequired(PropertyType type, ParamValues values) {
  bool empty(Object? v) {
    if (v == null) return true;
    if (v is String) return v.trim().isEmpty;
    if (v is List) return v.isEmpty;
    return false;
  }

  return [
    for (final f in visibleParams(type.paramFields, values))
      if (!f.optional && f.control != ParamControl.toggle && empty(values[f.key]))
        f,
  ];
}

void main() {
  test('majburiy maydonlarning HAMMASI qadamda ko‘rinmaydi', () {
    // Bu test o'zi tuzatishni tekshirmaydi — u MUAMMONING BORLIGINI
    // qotiradi: agar kelajakda hamma majburiy maydon `inStep` bo'lib qolsa,
    // bu test yiqiladi va `_missingRequired` ning kengaytirilgan qamrovi
    // endi kerak emasligini bildiradi.
    final offScreen = <String>[];
    for (final t in PropertyType.values) {
      for (final f in t.paramFields) {
        if (!f.optional && !f.inStep && f.control != ParamControl.toggle) {
          offScreen.add('${t.name}.${f.key}');
        }
      }
    }
    expect(
      offScreen,
      isNotEmpty,
      reason: 'shu maydonlar uchun kengaytirilgan tekshiruv kerak',
    );
    // Prod'da uchragan aynan shu holat.
    expect(offScreen, contains('house.bathroom_type'));
  });

  group('missingRequired', () {
    test('uy: bo‘sh qoralamada bathroom_type YETISHMAYDI deb topiladi', () {
      final missing = missingRequired(PropertyType.house, {});
      expect(missing.map((f) => f.key), contains('bathroom_type'));
    });

    test('uy: bathroom_type to‘ldirilgach ro‘yxatdan chiqadi', () {
      final values = <String, Object?>{'bathroom_type': 'separate'};
      final missing = missingRequired(PropertyType.house, values);
      expect(missing.map((f) => f.key), isNot(contains('bathroom_type')));
    });

    test('kvartira: living_area va parking ham tekshiriladi', () {
      final missing =
          missingRequired(PropertyType.apartment, {}).map((f) => f.key);
      expect(missing, containsAll(<String>['living_area', 'parking']));
    });

    test('tijorat: oltita qadamdan tashqari maydon tekshiriladi', () {
      final missing =
          missingRequired(PropertyType.commercial, {}).map((f) => f.key);
      expect(
        missing,
        containsAll(<String>[
          'building_floors',
          'floor',
          'possible_purpose',
          'rooms_count',
          'entrance_kind',
          'renovation',
        ]),
      );
    });

    test('SHARTLI maydon sharti bajarilmasa TALAB QILINMAYDI', () {
      // `garage_*` faqat `parking == 'garage'` da ko'rinadi. Aks holda ular
      // majburiy bo'lsa ham so'ralmasligi kerak — aks holda foydalanuvchi
      // garaji yo'q kvartira uchun garaj maydonini to'ldirishga majbur bo'lardi.
      final noGarage = missingRequired(
        PropertyType.apartment,
        {'parking': 'yard'},
      ).map((f) => f.key);
      expect(noGarage, isNot(contains('garage_area')));

      final withGarage = missingRequired(
        PropertyType.apartment,
        {'parking': 'garage'},
      ).map((f) => f.key);
      expect(withGarage, contains('garage_area'));
    });

    test('toggle hech qachon yetishmaydi deb hisoblanmaydi', () {
      // Toggle har doim qiymatga ega (yoqilgan/o'chirilgan), `null` bo'lsa
      // "o'chirilgan" degani — uni talab qilish oqimni boshi berk qilardi.
      final missing = missingRequired(PropertyType.house, {});
      expect(
        missing.every((f) => f.control != ParamControl.toggle),
        isTrue,
      );
    });

    test('hamma majburiy maydon to‘ldirilsa ro‘yxat BO‘SH', () {
      final values = <String, Object?>{};
      for (final f in PropertyType.house.paramFields) {
        if (f.optional || f.control == ParamControl.toggle) continue;
        values[f.key] = f.control == ParamControl.multiSelect ? ['x'] : 'x';
      }
      expect(missingRequired(PropertyType.house, values), isEmpty);
    });
  });
}
