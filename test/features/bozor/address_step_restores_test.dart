import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/bozor/data/bozor_draft_codec.dart';
import 'package:kadastr/features/bozor/data/regions_repository.dart';
import 'package:kadastr/features/bozor/models/bozor_draft.dart';
import 'package:kadastr/features/bozor/screens/bozor_address_step_screen.dart';
import 'package:kadastr/features/services/widgets/wizard_nav_bar.dart';

/// 2-qadam qoralamadan/e'londan TIKLANISHI kerak.
///
/// SABAB (2026-09-11, prod'da ko'rindi): foydalanuvchi e'lonini tahrirlashga
/// kirdi va manzil qadamida faqat viloyat, tuman va xarita nuqtasi ko'rindi —
/// manzil, mo'ljal, uy raqami va qavatlar BO'SH edi. Sababi: bu ekranning
/// yetti `TextEditingController` i qoralamadan hech qachon to'ldirilmasdi
/// (qolgan qadamlar to'ldiradi).
///
/// Ikkinchi, jimroq oqibati: «Keyingisi» bosilganda `_onContinue` o'sha bo'sh
/// kontrollerlarni qoralamaga USTIDAN yozardi, ya'ni `PATCH` manzilni
/// tozalab yuborardi. Buni alohida test qilmaymiz — `_onContinue` KONTROLLER
/// matnini ko'chiradi, ya'ni tiklanish ishlasa o'chirilish ham bo'lmaydi;
/// tugmani bosish esa navigatsiya va fon saqlashni ishga tushirib testni
/// mo'rt qilardi.
void main() {
  BozorDraft filledDraft() {
    final d = BozorDraft(
      deal: DealType.rent,
      kind: PropertyKind.residential,
      type: PropertyType.apartment,
    );
    d.address
      ..regionId = 1
      ..regionName = 'Toshkent shahri'
      ..districtId = 2
      ..districtName = "Mirzo Ulug'bek tumani"
      ..address = 'Amir Temur shoh koʻchasi 12'
      ..landmark = 'Metro yonida'
      ..apartmentNumber = '45'
      ..entrance = '3'
      ..totalFloors = '9'
      ..floor = '5'
      ..lat = 41.25770
      ..lng = 69.20310;
    return d;
  }

  Future<void> pump(WidgetTester tester, BozorDraft d) async {
    // Sakkizta qator sukutdagi 600pt ga sig'maydi va `ListView` ko'rinmagan
    // elementni QURMAYDI — `find.text` esa faqat qurilganini topadi.
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: BozorAddressStepScreen(
          draft: d,
          regionsRepository: _FakeRegions(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('saqlangan manzil maydonlari EKRANDA ko\'rinadi', (tester) async {
    await pump(tester, filledDraft());

    expect(find.text('Amir Temur shoh koʻchasi 12'), findsOneWidget);
    expect(find.text('45'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    // Viloyat/tuman ilgari ham ko'rinardi — ular `_a` dan to'g'ridan o'qiladi.
    expect(find.text('Toshkent shahri'), findsOneWidget);
    expect(find.text("Mirzo Ulug'bek tumani"), findsOneWidget);
  });

  testWidgets('«Mo\'ljal» qatori formada YO\'Q, lekin qiymat yo\'qolmaydi', (
    tester,
  ) async {
    final d = filledDraft();
    await pump(tester, d);

    expect(
      find.text('Metro yonida'),
      findsNothing,
      reason: 'maydon mijoz talabi bilan olib tashlandi (MARKET-02)',
    );
    expect(
      d.address.landmark,
      'Metro yonida',
      reason: 'qator ko\'rinmasa ham eski e\'londagi qiymat saqlanib qolishi '
          'kerak — backendda maydon hali bor va PATCH uni tozalab '
          'yubormasligi shart',
    );
  });

  /// MARKET-02 ning YUBORISH tomoni.
  ///
  /// Qator formadan olib tashlandi, lekin maydonning o'zi modelda, kodekda va
  /// API'da QOLDI. Ikkita kafolat kerak:
  ///   1. yangi e'londa `landmark` kaliti payload'ga UMUMAN tushmaydi —
  ///      backendda u `str | None = None`, ya'ni bo'sh satr ham, o'ylab
  ///      topilgan qiymat ham yubormaymiz;
  ///   2. tahrirlanayotgan eski e'londa qiymat bor bo'lsa — u yuboriladi,
  ///      aks holda `PATCH` reyestrdagi mo'ljalni jimgina o'chirardi.
  ///
  /// `draftToPayload` yaratish, qoralama saqlash va `PATCH` — uchalasining
  /// yagona manbai (`draftToUpdatePayload` `address` ni o'zgarishsiz oladi),
  /// shuning uchun shu bitta funksiyani tekshirish yetarli.
  group('MARKET-02 — `landmark` serializatsiyasi', () {
    Map<String, Object?> addressOf(BozorDraft d) =>
        draftToPayload(d, const [])['address']! as Map<String, Object?>;

    test('bo\'sh mo\'ljal payload\'ga YOZILMAYDI', () {
      final d = filledDraft()..address.landmark = '';
      expect(addressOf(d).containsKey('landmark'), isFalse);
    });

    test('eski e\'londagi mo\'ljal payload\'da SAQLANADI', () {
      expect(addressOf(filledDraft())['landmark'], 'Metro yonida');
    });
  });

  testWidgets('to\'ldirilgan qoralamada «Keyingisi» DARHOL yoniq', (
    tester,
  ) async {
    await pump(tester, filledDraft());

    final nav = tester.widget<WizardNavBar>(find.byType(WizardNavBar));
    expect(
      nav.continueEnabled,
      isTrue,
      reason: 'maydonlar tiklanmasa tugma o\'chiq qolardi va foydalanuvchi '
          'hammasini qaytadan yozishga majbur bo\'lardi',
    );
  });
}

/// Tarmoqqa chiqmaydigan viloyat/tuman manbai.
class _FakeRegions extends RegionsRepository {
  @override
  Future<List<Region>> regions() async => const [
    Region(id: 1, name: 'Toshkent shahri'),
  ];

  @override
  Future<List<District>> districts(int regionId) async => const [
    District(id: 2, regionId: 1, name: "Mirzo Ulug'bek tumani"),
  ];
}
