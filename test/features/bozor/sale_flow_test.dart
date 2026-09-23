import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/bozor/data/bozor_api.dart';
import 'package:kadastr/features/bozor/data/bozor_draft_codec.dart';
import 'package:kadastr/features/bozor/data/param_options.dart';
import 'package:kadastr/features/bozor/models/bozor_draft.dart';
import 'package:kadastr/features/bozor/models/bozor_validation.dart';
import 'package:kadastr/features/bozor/screens/bozor_deal_step_screen.dart';
import 'package:kadastr/features/bozor/widgets/select_field.dart';
import 'param_schema_fixture.dart';

/// Sotuv oqimi (reja M3): 8 qadam, «Сделка» va sotuv narx shakli.
///
/// Bu oqim `bozor_sale_enabled` bayrog'i ostida turadi, ya'ni bayroq
/// yoqilgunicha uni HECH KIM ilovada bosib ko'rmaydi. Yagona qo'riqchi —
/// shu testlar.
///
/// Yorliqlar bu yerda kalitning O'ZI bo'lib chiqadi (`bozor.transaction.*`):
/// `tr()` bundle yuklanmagan holatda kalitni qaytaradi.
void main() {
  // Sxema backenddan keladi — testda uni qo'lda yuklaymiz.
  setUpAll(loadRealParamSchema);

  BozorDraft draft({
    DealType deal = DealType.sale,
    PropertyType type = PropertyType.apartment,
  }) => BozorDraft(deal: deal, kind: type.kind, type: type);

  // ── Qadamlar matritsasi ────────────────────────────────────────────────
  group('wizardStepsFor — (e\'lon turi × mulk turi)', () {
    test('sotuv + params bor tur → 8 qadam, «Сделка» 4-o\'rinda', () {
      final steps = wizardStepsFor(DealType.sale, PropertyType.apartment);
      expect(steps.length, 8);
      expect(steps[3], WizardStep.deal);
      expect(steps.indexOf(WizardStep.deal), lessThan(steps.indexOf(WizardStep.price)));
    });

    test('sotuv + «Другая нежилая» → 7 qadam (params yo\'q, deal bor)', () {
      final steps = wizardStepsFor(
        DealType.sale,
        PropertyType.otherNonResidential,
      );
      expect(steps.length, 7);
      expect(steps.contains(WizardStep.params), isFalse);
      expect(steps.contains(WizardStep.deal), isTrue);
      // Manzildan keyin to'g'ridan «Сделка».
      expect(steps[2], WizardStep.deal);
    });

    test('IJARA oqimi o\'zgarmagan — 7 va 6 qadam, «Сделка» YO\'Q', () {
      final rent = wizardStepsFor(DealType.rent, PropertyType.apartment);
      expect(rent.length, 7);
      expect(rent.contains(WizardStep.deal), isFalse);

      final rentOther = wizardStepsFor(
        DealType.rent,
        PropertyType.otherNonResidential,
      );
      expect(rentOther.length, 6);
      expect(rentOther.contains(WizardStep.deal), isFalse);
    });

    test('e\'lon turi tanlanmagan — ijara shakli (progress sakramasin)', () {
      expect(wizardStepsFor(null, null).length, 7);
      expect(wizardStepsFor(null, null).contains(WizardStep.deal), isFalse);
    });

    test('yangi bino kvartirasi kvartira bilan bir xil qadamlarga ega', () {
      expect(
        wizardStepsFor(DealType.sale, PropertyType.newBuildingApartment),
        wizardStepsFor(DealType.sale, PropertyType.apartment),
      );
    });
  });

  // ── setDeal: narx birligi ──────────────────────────────────────────────
  group('setDeal — narx birligi oqimga moslanadi', () {
    test('ijara → sotuv: davr olib tashlanadi, valyuta SAQLANADI', () {
      final d = BozorDraft(deal: DealType.rent);
      d.price.unit = 'USD/oy';
      d.setDeal(DealType.sale);
      expect(d.price.unit, 'USD', reason: 'sotuvda davr yo\'q');
    });

    test('sotuv → ijara: davr qaytadi va «Ипотека» o\'chadi', () {
      final d = BozorDraft(deal: DealType.sale);
      d.price
        ..unit = 'UZS'
        ..mortgage = true;
      d.transaction.ownersCount = '2';

      d.setDeal(DealType.rent);

      expect(d.price.unit, 'UZS/oy');
      expect(d.price.mortgage, isFalse, reason: 'ijarada ipoteka yo\'q');
      expect(
        d.transaction.ownersCount,
        isNull,
        reason: '«Сделка» ijara payload\'ida 400 beradi',
      );
    });

    test('sotuvga o\'tganda sutkalik narx tozalanadi', () {
      final d = BozorDraft(deal: DealType.rent);
      d.price.dailyAmount = '300000';
      d.setDeal(DealType.sale);
      expect(d.price.dailyAmount, isEmpty);
    });
  });

  // ── «Прописано» faqat kvartira turlarida ───────────────────────────────
  group('«Прописано» — turga bog\'liq', () {
    test('kvartira turlarida so\'raladi, qolganida yo\'q', () {
      expect(PropertyType.apartment.asksRegisteredCount, isTrue);
      expect(PropertyType.newBuildingApartment.asksRegisteredCount, isTrue);
      for (final t in [
        PropertyType.house,
        PropertyType.land,
        PropertyType.commercial,
        PropertyType.garage,
        PropertyType.otherNonResidential,
      ]) {
        expect(t.asksRegisteredCount, isFalse, reason: '$t');
      }
    });

    test('tur so\'ramaydiganiga o\'zgarsa qiymat TOZALANADI', () {
      final d = draft();
      d.transaction.registeredCount = '2';
      d.setType(PropertyType.house);
      expect(
        d.transaction.registeredCount,
        isNull,
        reason: 'osilib qolgan qiymat backendda 400 beradi',
      );
    });
  });

  // ── Payload ────────────────────────────────────────────────────────────
  group('payload — «Сделка» va «Ипотека»', () {
    test('sotuvda `deal` bo\'limi yuboriladi', () {
      final d = draft();
      d.transaction
        ..saleType = 'free_sale'
        ..ownershipYears = 'over_5'
        ..ownersCount = '2'
        ..registeredCount = '0';
      d.price.mortgage = true;

      final json = draftToPayload(d, const []);
      expect(json['deal'], {
        'sale_type': 'free_sale',
        'ownership_years': 'over_5',
        'owners_count': '2',
        'registered_count': '0',
      });
      expect((json['price'] as Map)['mortgage'], isTrue);
    });

    test('IJARADA `deal` kaliti UMUMAN bo\'lmaydi', () {
      final d = draft(deal: DealType.rent);
      d.transaction.ownersCount = '1'; // qoldiq — baribir yuborilmasin
      final json = draftToPayload(d, const []);
      expect(json.containsKey('deal'), isFalse);
      expect((json['price'] as Map)['mortgage'], isFalse);
    });

    test('«Прописано» so\'ralmaydigan turda `null` ketadi', () {
      final d = draft(type: PropertyType.house);
      d.transaction
        ..ownersCount = '1'
        ..registeredCount = '3'; // modelga to'g'ridan yozilgan
      final json = draftToPayload(d, const []);
      expect((json['deal'] as Map)['registered_count'], isNull);
    });

    test('payload → qoralama: «Сделка» tiklanadi', () {
      final d = draft();
      d.transaction
        ..saleType = 'alternative'
        ..ownersCount = '3';
      d.price.mortgage = true;

      final back = draftFromPayload(draftToPayload(d, const []));

      expect(back.transaction.saleType, 'alternative');
      expect(back.transaction.ownersCount, '3');
      expect(back.price.mortgage, isTrue);
    });

    test('yangi bino kvartirasining kodi to\'g\'ri o\'giriladi', () {
      final d = draft(type: PropertyType.newBuildingApartment);
      final json = draftToPayload(d, const []);
      expect(json['property_type'], 'new_building_apartment');
      expect(
        propertyTypeFromCode('new_building_apartment'),
        PropertyType.newBuildingApartment,
      );
    });
  });

  // ── Yakuniy darvoza ────────────────────────────────────────────────────
  group('draftBlockers — «Собственники» majburiy', () {
    BozorDraft filled({DealType deal = DealType.sale}) {
      final d = draft(deal: deal, type: PropertyType.otherNonResidential);
      d.address
        ..regionId = 1
        ..districtId = 2
        ..address = 'Toshkent, Yunusobod';
      d.price.amount = '450000000';
      d.title = 'Sotiladigan obyekt';
      d.description.text = 'Tavsif';
      d.contacts
        ..name = 'Asliddin'
        ..phones[0] = '996753211';
      return d;
    }

    test('sotuvda `ownersCount` bo\'sh — yuborishga to\'sqinlik qiladi', () {
      final blockers = draftBlockers(filled());
      expect(blockers.map((b) => b.step), contains(WizardStep.deal));
      expect(
        blockers.firstWhere((b) => b.step == WizardStep.deal).fieldLabelKeys,
        ['bozor.transaction.owners_count'],
      );
    });

    test('`ownersCount` to\'ldirilsa to\'siq qolmaydi', () {
      final d = filled()..transaction.ownersCount = '1';
      expect(draftBlockers(d), isEmpty);
    });

    test('IJARADA «Сделка» umuman tekshirilmaydi', () {
      final d = filled(deal: DealType.rent);
      expect(d.transaction.ownersCount, isNull);
      expect(draftBlockers(d), isEmpty);
    });
  });

  // ── Ekran ──────────────────────────────────────────────────────────────
  group('BozorDealStepScreen', () {
    Future<void> pump(WidgetTester tester, BozorDraft d) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BozorDealStepScreen(
            draft: d,
            optionsRepository: _FakeOptions(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('kvartirada TO\'RTTA qator', (tester) async {
      await pump(tester, draft());
      expect(find.byType(SelectField), findsNWidgets(4));
      expect(find.text('bozor.transaction.registered_count'), findsOneWidget);
    });

    testWidgets('uyda «Прописано» qatori YO\'Q — uchta qator', (tester) async {
      await pump(tester, draft(type: PropertyType.house));
      expect(find.byType(SelectField), findsNWidgets(3));
      expect(find.text('bozor.transaction.registered_count'), findsNothing);
    });

    testWidgets('«Собственники» tanlanmaguncha «Keyingisi» o\'chiq', (
      tester,
    ) async {
      final d = draft();
      await pump(tester, d);

      SelectField ownersRow() => tester.widget<SelectField>(
        find.byType(SelectField).at(2),
      );
      expect(ownersRow().required, isTrue);

      d.transaction.ownersCount = '1';
      await pump(tester, d);
      // Yorliq emas, KOD saqlanadi — ekranda esa yorliq ko'rinadi.
      expect(find.text('1 nafar'), findsOneWidget);
    });
  });
}

/// Tarmoqqa chiqmaydigan ro'yxat manbai.
class _FakeOptions extends ParamOptionsRepository {
  @override
  Future<List<ListingOption>> options(String key) async => switch (key) {
    'sale_type' => const [
      ListingOption(code: 'free_sale', label: 'Erkin sotuv'),
      ListingOption(code: 'alternative', label: 'Alternativa'),
    ],
    'ownership_years' => const [
      ListingOption(code: 'under_3', label: '3 yildan kam'),
      ListingOption(code: 'over_5', label: '5 yildan koʻp'),
    ],
    'owners_count' => const [
      ListingOption(code: '1', label: '1 nafar'),
      ListingOption(code: '2', label: '2 nafar'),
    ],
    'registered_count' => const [
      ListingOption(code: '0', label: 'Yoʻq'),
      ListingOption(code: '1', label: '1 nafar'),
    ],
    _ => const [],
  };
}
