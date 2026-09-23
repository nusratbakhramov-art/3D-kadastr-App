import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:kadastr/features/bozor/data/bozor_submit.dart';
import 'package:kadastr/features/bozor/models/bozor_draft.dart';
import 'package:kadastr/features/bozor/models/bozor_validation.dart';
import 'package:kadastr/features/bozor/models/param_schema.dart';
import 'package:kadastr/features/bozor/screens/bozor_terms_step_screen.dart';
import 'param_schema_fixture.dart';

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
  // Sxema backenddan keladi — testda uni qo'lda yuklaymiz.
  setUpAll(loadRealParamSchema);

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
    // Prod'da uchragan holat `house.bathroom_type` edi; 2026-09-23 da u
    // mijozning talabi bilan IXTIYORIY qilindi, shuning uchun namuna
    // sifatida hozir ham majburiy va qadamda KO'RINMAYDIGAN maydon
    // olinadi. Da'vo o'zgargani yo'q — tekshiruv qamrovi haqida.
    expect(offScreen, contains('apartment.living_area'));
  });

  _gateTests();
  _screenGateTest();

  group('missingRequired', () {
    test('uy: bathroom_type endi MAJBURIY EMAS', () {
      // 2026-09-23: mijoz «sanuzel turi» ni majburiy emas deb belgiladi.
      // Yonidagi `bathroom_location` allaqachon ixtiyoriy edi — ikkisi
      // bir-biriga zid turardi. Backendda ham aynan shunday
      // (`listing_param_schema.py`), parity testi buni qo'riqlaydi.
      final missing = missingRequired(PropertyType.house, {});
      expect(missing.map((f) => f.key), isNot(contains('bathroom_type')));
    });

    test('uy: bo‘sh qoralamada BOSHQA majburiylar baribir topiladi', () {
      // Yuqoridagi o'zgarish tekshiruvni butunlay o'chirib qo'ymaganini
      // qotiradi.
      final missing = missingRequired(PropertyType.house, {});
      expect(missing.map((f) => f.key), contains('house_area'));
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

/// Yakuniy darvoza — `draftBlockers()`.
///
/// SABAB (2026-09-10, prod): qoralamani davom ettirish sehrgarni SAQLANGAN
/// qadamdan ochadi. `current_step == 'terms'` bo'lsa foydalanuvchi to'g'ridan
/// 7-qadamga tushadi, 1–6 qadamlarning `_isComplete` lari umuman ishlamaydi,
/// va 7-qadam faqat rozilikni tekshirardi. Natijada `submit` serverdan
/// tushunarsiz 400 olardi.
BozorDraft _complete() {
  final d = BozorDraft(
    deal: DealType.rent,
    kind: PropertyKind.residential,
    type: PropertyType.house,
  );
  d.address
    ..regionId = 7
    ..districtId = 8
    ..address = 'Chilonzor 5'
    ..houseNumber = '12'
    ..totalFloors = '2';
  for (final f in PropertyType.house.paramFields) {
    if (f.optional || f.control == ParamControl.toggle) continue;
    d.params[f.key] = f.control == ParamControl.multiSelect ? ['x'] : 'x';
  }
  d.price.amount = '1000000';
  d.title = 'Chilonzorda uy';
  d.description.text = 'Tavsif';
  d.contacts.name = 'Ali';
  d.contacts.phones
    ..clear()
    ..add('901234567');
  return d;
}

void _gateTests() {
  group('draftBlockers', () {
    test('to‘liq qoralamada to‘siq YO‘Q', () {
      expect(draftBlockers(_complete()), isEmpty);
    });

    test('qadamda KO‘RINMAYDIGAN majburiy maydon bo‘sh → 3-qadam to‘sadi', () {
      // Prod'da bu `house.bathroom_type` edi (2026-09-10). U endi
      // ixtiyoriy, lekin da'vo o'sha-o'sha: ekranda ko'rinmaydigan majburiy
      // maydon ham darvozadan o'tkazmasligi kerak.
      final d = _complete();
      d.params.remove('house_area');
      final blockers = draftBlockers(d);
      expect(blockers, hasLength(1));
      expect(blockers.first.step, WizardStep.params);
      expect(blockers.first.fieldLabelKeys, contains('bozor.param.house_area'));
    });

    test('bathroom_type bo‘sh bo‘lsa TO‘SILMAYDI', () {
      final d = _complete();
      d.params.remove('bathroom_type');
      expect(draftBlockers(d), isEmpty);
    });

    test('bo‘sh qoralamada 1-qadam to‘sadi va QOLGANI sanalmaydi', () {
      // Turi yo'q bo'lsa qolgan qadamlarning qoidalari noaniq — "hamma narsa
      // yetishmaydi" degan foydasiz ro'yxat chiqmasligi kerak.
      final blockers = draftBlockers(BozorDraft());
      expect(blockers, hasLength(1));
      expect(blockers.first.step, WizardStep.type);
    });

    test('manzil maydonlari nomi bilan qaytadi', () {
      final d = _complete();
      d.address.houseNumber = '';
      final b = draftBlockers(d).firstWhere((x) => x.step == WizardStep.address);
      expect(b.fieldLabelKeys, contains('bozor.address.field.house_number'));
    });

    test('narx, tavsif va kontakt ham tekshiriladi', () {
      final d = _complete();
      d.price.amount = '';
      d.title = 'ab'; // 3 belgidan kam
      d.contacts.phones
        ..clear()
        ..add('90123'); // 9 raqam emas
      final steps = draftBlockers(d).map((b) => b.step);
      expect(steps, containsAll(<WizardStep>[
        WizardStep.price,
        WizardStep.description,
        WizardStep.contacts,
      ]));
    });

    test('«Boshqa noturar joy» da parametrlar qadami TEKSHIRILMAYDI', () {
      // Bu variantda 3-qadam umuman yo'q — bo'lmagan qadamni talab qilish
      // oqimni boshi berk qilardi.
      final d = BozorDraft(
        deal: DealType.rent,
        kind: PropertyKind.nonResidential,
        type: PropertyType.otherNonResidential,
      );
      d.address
        ..regionId = 7
        ..districtId = 8
        ..address = 'Chilonzor 5';
      d.price.amount = '100';
      d.title = 'Ombor';
      d.description.text = 'Tavsif';
      d.contacts.name = 'Ali';
      d.contacts.phones
        ..clear()
        ..add('901234567');
      expect(d.wizardSteps.contains(WizardStep.params), isFalse);
      expect(draftBlockers(d), isEmpty);
    });

    test('har qadam uchun sarlavha kaliti bor', () {
      for (final s in WizardStep.values) {
        expect(kStepTitleKeys[s], isNotNull, reason: '$s uchun kalit yo‘q');
      }
    });
  });
}

/// 7-qadam EKRANI darvozani haqiqatan chaqiradimi.
///
/// `draftBlockers()` ni to'g'ridan-to'g'ri sinash yetmaydi: kimdir ekrandagi
/// chaqiruvni o'chirib qo'ysa mantiq ishlashda davom etadi, lekin foydalanuvchi
/// yana serverdan 400 oladi. Shu sababli EKRAN darajasidagi test.
void _screenGateTest() {
  testWidgets('7-qadam: to‘liqsiz qoralama YUBORILMAYDI', (tester) async {
    var submitted = false;
    final draft = _complete();
    // Qadamda ko'rinmaydigan majburiy maydon (prod holati `bathroom_type`
    // edi; u 2026-09-23 da ixtiyoriy bo'ldi).
    draft.params.remove('house_area');
    draft.terms.accepted = true;

    await tester.pumpWidget(
      MaterialApp(
        home: BozorTermsStepScreen(
          draft: draft,
          submitter: _SpySubmitter(() => submitted = true),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('bozor.terms.submit'));
    await tester.pump();

    expect(submitted, isFalse, reason: 'server 400 bergandan ko‘ra oldin to‘smoq');
    // Xabar QAYERGA qaytishni aytadi: qadam raqami + nomi + maydon.
    expect(find.textContaining('bozor.params.title'), findsOneWidget);
    expect(find.textContaining('bozor.param.house_area'), findsOneWidget);

    // Toast 3 sekund turadi va o'z timer'i bor — uni tugatmasak
    // `flutter_test` "A Timer is still pending" deb yiqiladi.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('7-qadam: to‘liq qoralama yuborishga o‘tadi', (tester) async {
    var submitted = false;
    final draft = _complete()..terms.accepted = true;

    await tester.pumpWidget(
      MaterialApp(
        home: BozorTermsStepScreen(
          draft: draft,
          submitter: _SpySubmitter(() => submitted = true),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('bozor.terms.submit'));
    await tester.pump();

    expect(submitted, isTrue, reason: 'darvoza to‘liq qoralamani to‘smasligi kerak');
  });
}

/// Tarmoqqa chiqmaydigan `BozorSubmitter` — faqat chaqirilganini yozadi.
class _SpySubmitter extends BozorSubmitter {
  _SpySubmitter(this.onCalled);

  final void Function() onCalled;

  @override
  Future<Map<String, dynamic>> submit(
    BozorDraft draft, {
    SubmitProgress? onProgress,
  }) async {
    onCalled();
    return {'id': 1, 'status': 'pending'};
  }

  @override
  void dispose() {}
}
