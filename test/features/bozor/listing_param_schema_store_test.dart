import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/bozor/models/bozor_draft.dart';
import 'package:kadastr/features/bozor/models/param_schema.dart';

import 'param_schema_fixture.dart';

/// Sxema BACKENDDAN keladi — bu testlar o'qish tomonini qotiradi.
///
/// Mijozning talabi (2026-09-23): yangi maydon yoki mulk turi qo'shish uchun
/// ilovani qayta chiqarish shart bo'lmasin. Ya'ni ilova o'zi bilmagan
/// maydonni ham chiza olishi va o'zi bilgan maydon yo'qolsa yiqilmasligi
/// kerak.
void main() {
  ListingParamSchemaDoc parse(Map<String, dynamic> j) =>
      ListingParamSchemaDoc.fromJson(j);

  group('ilova ichidagi nusxa', () {
    setUpAll(loadRealParamSchema);

    test('backenddagi fayl bilan AYNAN bir xil', () {
      // Ikkisi ajralib ketsa, offline foydalanuvchi eski maydonlarni
      // to'ldiradi va `submit` da 400 oladi.
      final asset = jsonDecode(File(kParamSchemaAsset).readAsStringSync());
      final backend = jsonDecode(
        File(
          '../backend/app/data/listing_param_schema.json',
        ).readAsStringSync(),
      );
      expect(asset, backend);
    });

    test('har bir mulk turi sxemada bor', () {
      for (final t in PropertyType.values) {
        // «Boshqa noturar joy» da parametr yo'q — bu ham javob.
        expect(
          ListingParamSchemaDoc.fromJson(
            jsonDecode(File(kParamSchemaAsset).readAsStringSync())
                as Map<String, dynamic>,
          ).types.containsKey(t.code),
          isTrue,
          reason: '${t.code} sxemada yo\'q',
        );
      }
    });

    test('tijorat maydonlari o\'qiladi: birlik, majburiylik, shart', () {
      final area = PropertyType.commercial.paramFields.firstWhere(
        (f) => f.key == 'premises_area',
      );
      expect(area.unit, 'm²');
      expect(area.optional, isFalse);
      expect(area.inStep, isTrue);

      final land = PropertyType.commercial.paramFields.firstWhere(
        (f) => f.key == 'land_area',
      );
      expect(land.condition?.key, 'with_land');
      expect(land.isVisible({'with_land': true}), isTrue);
      expect(land.isVisible({'with_land': false}), isFalse);
      expect(land.isVisible(const {}), isFalse);
    });

    test('`land_area` turar joyda SOTIX, tijoratda esa m²', () {
      // Aynan shu sabab birlik (TUR, MAYDON) juftiga bog'langan, maydon
      // kalitining o'ziga emas: bitta `unit` jadvali bilan ifodalab
      // bo'lmaydi.
      String? unitOf(PropertyType t) =>
          t.paramFields.firstWhere((f) => f.key == 'land_area').unit;
      expect(unitOf(PropertyType.house), 'sot.');
      expect(unitOf(PropertyType.land), 'sot.');
      expect(unitOf(PropertyType.commercial), 'm²');
      expect(unitOf(PropertyType.basement), 'm²');
    });
  });

  group('noma\'lum narsalarga chidaydi', () {
    test('ILOVA BILMAGAN maydon ham chiziladi', () {
      final doc = parse({
        'version': 9,
        'types': {
          'apartment': [
            {
              'key': 'solar_panels',
              'control': 'toggle',
              'optional': true,
              'unit': null,
              'options': null,
              'in_step': true,
              'section': 'main',
              'visible_when': null,
            },
          ],
        },
      });
      final f = doc.fieldsFor('apartment').single;
      expect(f.key, 'solar_panels');
      expect(f.control, ParamControl.toggle);
      expect(f.labelKey, 'bozor.param.solar_panels');
    });

    test('noma\'lum kontrol matn maydoniga tushadi, yiqilmaydi', () {
      final doc = parse({
        'version': 1,
        'types': {
          'apartment': [
            {'key': 'x', 'control': 'quantum_slider'},
          ],
        },
      });
      expect(doc.fieldsFor('apartment').single.control, ParamControl.text);
    });

    test('`optional` berilmasa IXTIYORIY deb olinadi', () {
      // Teskarisi xavfli: eski ilova yangi maydonni majburiy deb bilsa,
      // foydalanuvchi uni to'ldira olmay oqimda qulflanib qolardi.
      final doc = parse({
        'version': 1,
        'types': {
          'apartment': [
            {'key': 'x', 'control': 'text'},
          ],
        },
      });
      expect(doc.fieldsFor('apartment').single.optional, isTrue);
    });

    test('ILOVA BILMAGAN mulk turi ham sxema bilan keladi', () {
      final doc = parse({
        'version': 1,
        'types': {
          'penthouse': [
            {'key': 'roof_area', 'control': 'number', 'unit': 'm²'},
          ],
        },
      });
      expect(doc.fieldsFor('penthouse'), hasLength(1));
    });

    test('noma\'lum tur — bo\'sh ro\'yxat, istisno emas', () {
      final doc = parse({'version': 1, 'types': <String, dynamic>{}});
      expect(doc.fieldsFor('apartment'), isEmpty);
      expect(doc.fieldsFor(null), isEmpty);
    });
  });
}
