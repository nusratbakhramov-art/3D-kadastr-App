import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadastr/features/bozor/data/bozor_api.dart';
import 'package:kadastr/features/bozor/screens/bozor_type_step_screen.dart';
import 'package:kadastr/features/bozor/widgets/select_field.dart';
import 'package:kadastr/features/services/widgets/choice_tile.dart';

/// `bozor_sale_enabled` bayrog'ining mobil yarmi.
///
/// Sotuv sehrgari hali yarim (narx qadami ijara yorliqlarini beradi, "Сделка"
/// qadami yo'q), shuning uchun 1-qadamda "Продажа" faqat server bayroqni
/// yoqqanda ko'rinishi kerak. Testlar shu qalqonni qotiradi.
///
/// Yorliqlar shu yerda kalitning O'ZI bo'lib chiqadi (`bozor.deal.rent`):
/// `tr()` bundle yuklanmagan holatda kalitni qaytaradi — testda til
/// bundle'ini yuklash kerak emas.
void main() {
  BozorApi apiReturning({bool? saleEnabled, int status = 200}) {
    return BozorApi(
      client: MockClient((req) async {
        if (status != 200) return http.Response('boom', status);
        return http.Response(
          jsonEncode({
            'version': 1,
            'deal_types': const [],
            'kinds': const [],
            'types': const [],
            'kind_types': const <String, List<String>>{},
            'top_tier_enabled': false,
            // `null` — bayroqdan oldingi server: maydonni umuman yubormaydi.
            'sale_enabled': ?saleEnabled,
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
  }

  /// 1-qadamni chizadi va e'lon turi varag'ini ochadi.
  ///
  /// Bosish nuqtasi — birinchi [SelectField] ning ichki [InkWell] i: yorliq
  /// matni qatordan TASHQARIDA turadi, shuning uchun matn bo'yicha bosish
  /// varaqni ochmaydi.
  Future<void> openDealPicker(WidgetTester tester, BozorApi api) async {
    await tester.pumpWidget(MaterialApp(home: BozorTypeStepScreen(api: api)));
    // Bayroq so'rovi bloklovchi emas — javob keyingi freymlarda keladi.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(
      find.descendant(
        of: find.byType(SelectField).first,
        matching: find.byType(InkWell),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sale_enabled: false — varaqda faqat ijara', (tester) async {
    await openDealPicker(tester, apiReturning(saleEnabled: false));
    expect(find.byType(ChoiceTile), findsOneWidget);
    expect(find.text('bozor.deal.sale'), findsNothing);
  });

  testWidgets('sale_enabled: true — ikkala variant', (tester) async {
    await openDealPicker(tester, apiReturning(saleEnabled: true));
    expect(find.byType(ChoiceTile), findsNWidgets(2));
    expect(find.text('bozor.deal.sale'), findsOneWidget);
  });

  testWidgets('maydon yo\'q (eski server) — sotuv ko\'rinmaydi', (
    tester,
  ) async {
    await openDealPicker(tester, apiReturning());
    expect(find.byType(ChoiceTile), findsOneWidget);
    expect(find.text('bozor.deal.sale'), findsNothing);
  });

  testWidgets('xato/offline — ijara rejimi, ekran yiqilmaydi', (tester) async {
    await openDealPicker(tester, apiReturning(status: 500));
    expect(tester.takeException(), isNull);
    expect(find.byType(ChoiceTile), findsOneWidget);
    expect(find.text('bozor.deal.sale'), findsNothing);
  });

  testWidgets('bayroq o\'chiq bo\'lsa e\'lon turi sukut bo\'yicha ijara', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: BozorTypeStepScreen(api: apiReturning(status: 500))),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    // Maydon bo'sh turmaydi — qiymat sifatida ijara ko'rinadi, ya'ni "Далее"
    // ni faqat toifa/tur bloklaydi.
    expect(find.text('bozor.deal.rent'), findsOneWidget);
  });

  testWidgets('bayroq YOQIQ bo\'lsa e\'lon turi OLDINDAN to\'ldirilmaydi', (
    tester,
  ) async {
    // Regressiya qo'riqchisi. Avval bu shart `didChangeDependencies` da turgan
    // edi, u yerda esa `_saleEnabled` hamisha `false` bo'ladi (so'rov hali
    // ketmagan) — natijada e'lon turi bayroqdan QAT'I NAZAR `rent` ga
    // majburlanardi va bayroq `true` bo'lganda ham qaytmasdi. Sotuvchi 1-qadam
    // «В аренду» bilan to'lgan holda ochilganini sezmasdan "Далее" ni bosib,
    // ijara e'loni yaratib qo'yishi mumkin edi.
    await tester.pumpWidget(
      MaterialApp(home: BozorTypeStepScreen(api: apiReturning(saleEnabled: true))),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('bozor.deal.rent'), findsNothing);
    expect(find.text('bozor.deal.sale'), findsNothing);
  });
}
