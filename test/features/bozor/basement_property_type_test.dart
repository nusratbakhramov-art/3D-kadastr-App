import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/bozor/data/bozor_draft_codec.dart';
import 'package:kadastr/features/bozor/data/cadastre_autofill.dart';
import 'package:kadastr/features/bozor/models/bozor_draft.dart';
import 'package:kadastr/features/bozor/models/param_schema.dart';
import 'param_schema_fixture.dart';

/// «Podval» — noturar joyning alohida turi.
///
/// Mijozning so'rovi: yerto'lani e'lon qilish mumkin bo'lsin. Uni mavjud
/// «Tijorat obyekti» ichiga yashirish yaramaydi — qidiruvda yerto'la ekani
/// ko'rinmay ketardi.
///
/// Parametrlari hozircha AYNAN tijorat joyiniki. Bu shu kodbazadagi mavjud
/// usul (`newBuildingApartment` ham oddiy kvartira maydonlarini ishlatadi),
/// ya'ni yangi maydon to'plami O'YLAB TOPILMAGAN. Bu testlar aynan shu
/// shartnomani ushlab turadi.
void main() {
  // Sxema backenddan keladi — testda uni qo'lda yuklaymiz.
  setUpAll(loadRealParamSchema);

  const l = Locale('uz');

  group('turlar ro\'yxati', () {
    test('noturar joy toifasida ko\'rinadi', () {
      expect(
        PropertyKind.nonResidential.types,
        contains(PropertyType.basement),
      );
    });

    test('turar joy toifasiga TUSHMAYDI', () {
      expect(
        PropertyKind.residential.types,
        isNot(contains(PropertyType.basement)),
      );
      expect(PropertyType.basement.kind, PropertyKind.nonResidential);
    });
  });

  group('wire kodi', () {
    test('kod `basement`, ikki tomonga ham o\'giriladi', () {
      expect(PropertyType.basement.code, 'basement');
      expect(propertyTypeFromCode('basement'), PropertyType.basement);
    });

    test('qoralamada saqlanadi va tiklanadi', () {
      final draft = BozorDraft()
        ..deal = DealType.rent
        ..type = PropertyType.basement;
      final back = draftFromPayload(draftToDraftPayload(draft));
      expect(back.type, PropertyType.basement);
    });
  });

  group('parametrlar', () {
    test('tijorat joyi bilan AYNAN bir xil to\'plam', () {
      expect(
        PropertyType.basement.paramFields.map((f) => f.key).toList(),
        PropertyType.commercial.paramFields.map((f) => f.key).toList(),
      );
    });

    test('parametrlar qadami BOR — maydon shu yerda so\'raladi', () {
      expect(PropertyType.basement.hasParamsStep, isTrue);
      expect(
        PropertyType.basement.paramFields.map((f) => f.key),
        contains('premises_area'),
      );
    });

    test('maydon m² da — birlik tijorat joyinikidek', () {
      final area = PropertyType.basement.paramFields.firstWhere(
        (f) => f.key == 'premises_area',
      );
      expect(area.unit, 'm²');
    });
  });

  test('reyestrdan maydon `premises_area` ga to\'ladi', () {
    expect(primaryAreaKey(PropertyType.basement), 'premises_area');
  });

  group('yorliqlar', () {
    test('tur nomi o\'z kalitidan keladi, tijoratnikidan emas', () {
      expect(PropertyType.basement.label(l), isNot(PropertyType.commercial.label(l)));
      // Kalit topilmasa `tr` kalitning o'zini qaytaradi — shunda ham
      // «tijorat» bilan chalkashmaydi.
      expect(PropertyType.basement.label(l), isNotEmpty);
    });

    test('tavsif va narx sarlavhalari ham ayrim', () {
      expect(
        PropertyType.basement.descriptionLabel(l),
        isNot(PropertyType.commercial.descriptionLabel(l)),
      );
      expect(
        PropertyType.basement.priceLabel(l, DealType.sale),
        isNot(PropertyType.commercial.priceLabel(l, DealType.sale)),
      );
    });
  });
}
