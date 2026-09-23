import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/bozor/bozor_resume.dart';
import 'package:kadastr/features/bozor/models/bozor_draft.dart';
import 'package:kadastr/features/bozor/screens/bozor_description_step_screen.dart';
import 'package:kadastr/features/bozor/screens/bozor_price_step_screen.dart';
import 'package:kadastr/features/bozor/screens/bozor_type_step_screen.dart';
import 'package:kadastr/features/services/widgets/service_app_bar.dart';
import 'package:kadastr/widgets/sheet_button.dart';
import 'param_schema_fixture.dart';

/// Sehrgar sarlavhasidagi ikki tugma (FLOW-01…07).
///
/// Mijoz sharhi: 6/8 «Tavsif» dagi ← foydalanuvchini bosh sahifaga otib
/// yuborardi — u yagona tugma bo'lib, butun oqimni yopardi. Endi:
///   * ← — bitta qadam orqaga, hech qanday tasdiq oynasisiz;
///   * × — oqimni tark etish, BITTA marta so'raladigan tasdiq bilan
///     (pastki DRAWER, `SheetButton` lar bilan — Material `AlertDialog` emas);
///   * 1-qadamda × yo'q (orqaga qaytadigan joy yo'q, ← ning o'zi chiqish).
void main() {
  // Sxema backenddan keladi — testda uni qo'lda yuklaymiz.
  setUpAll(loadRealParamSchema);

  BozorDraft draft() => BozorDraft(
    deal: DealType.rent,
    kind: PropertyKind.residential,
    type: PropertyType.apartment,
  );

  Future<NavigatorState> pumpHost(WidgetTester tester) async {
    late NavigatorState nav;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) {
            nav = Navigator.of(ctx);
            return const Scaffold(body: Text('RO\'YXAT'));
          },
        ),
      ),
    );
    return nav;
  }

  Future<void> openDescription(WidgetTester tester) async {
    final nav = await pumpHost(tester);
    // ignore: discarded_futures
    pushBozorDraftStack(nav, draft(), WizardStep.description);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BozorDescriptionStepScreen), findsOneWidget);
  }

  /// Oqimning oldingi qadamlari ham daraxtda turadi (marshrutlar yopilmagan),
  /// shuning uchun sarlavha AYNAN shu ekran ichidan izlanadi.
  ServiceAppBar appBar(WidgetTester tester, Type screen) =>
      tester.widget<ServiceAppBar>(
        find.descendant(
          of: find.byType(screen),
          matching: find.byType(ServiceAppBar),
        ),
      );

  /// Tasdiq — pastki drawer, ya'ni uni `SheetButton` lari bo'yicha topamiz.
  /// Birinchisi — «Davom etish» (yashil, oqimda qoladi), ikkinchisi —
  /// «Chiqish» (qizil tonal).
  Finder exitSheet() => find.byType(SheetButton);
  Finder stayButton() => exitSheet().first;
  Finder leaveButton() => exitSheet().last;

  void expectNoDialogWidgets(WidgetTester tester) {
    expect(
      find.byType(AlertDialog),
      findsNothing,
      reason: 'ilovada so\'rov oynalari DRAWER — Material dialog ishlatilmaydi',
    );
  }

  testWidgets('6/8: ← oldingi qadamga qaytaradi, tasdiq so\'ramaydi', (
    tester,
  ) async {
    await openDescription(tester);

    appBar(tester, BozorDescriptionStepScreen).onBack!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(BozorPriceStepScreen), findsOneWidget);
    expect(exitSheet(), findsNothing);
    expectNoDialogWidgets(tester);
    expect(find.text('RO\'YXAT'), findsNothing);
    await flushTimers(tester);
  });

  testWidgets('6/8: × drawer ochadi; «Davom etish» bosilsa oqimda qolamiz', (
    tester,
  ) async {
    await openDescription(tester);

    appBar(tester, BozorDescriptionStepScreen).onClose!();
    await tester.pumpAndSettle();
    expect(exitSheet(), findsNWidgets(2));
    expectNoDialogWidgets(tester);

    await tester.tap(stayButton());
    await tester.pumpAndSettle();
    expect(exitSheet(), findsNothing);
    expect(find.byType(BozorDescriptionStepScreen), findsOneWidget);
    await flushTimers(tester);
  });

  testWidgets('6/8: «Chiqish» bosilsa butun oqim yopiladi', (tester) async {
    await openDescription(tester);

    appBar(tester, BozorDescriptionStepScreen).onClose!();
    await tester.pumpAndSettle();
    await tester.tap(leaveButton());
    await tester.pumpAndSettle();

    expect(find.text('RO\'YXAT'), findsOneWidget);
    expect(find.byType(BozorDescriptionStepScreen), findsNothing);
    await flushTimers(tester);
  });

  testWidgets('× ikki marta bosilsa ham tasdiq BITTA marta chiqadi', (
    tester,
  ) async {
    await openDescription(tester);

    final close = appBar(tester, BozorDescriptionStepScreen).onClose!;
    close();
    close();
    await tester.pumpAndSettle();

    expect(
      exitSheet(),
      findsNWidgets(2),
      reason: 'ikkita ustma-ust drawer bo\'lsa, birinchisini yopish '
          'ikkinchisini ochiq qoldirardi — foydalanuvchi bir xil savolga '
          'ikki marta javob berardi (FLOW-07). Bitta drawer = 2 ta tugma.',
    );
    await tester.tap(stayButton());
    await tester.pumpAndSettle();
    expect(exitSheet(), findsNothing);
    await flushTimers(tester);
  });

  /// 1-QADAMDAGI TIZIM «ORQAGA» SI.
  ///
  /// Uy qoidasi (`pano_capture_flow`, `kadastr_submit_flow_screen`,
  /// `app_update_gate` da ham shunday): chiqishni ushlab qolish kerak bo'lsa
  /// `PopScope(canPop: false)` + `onPopInvokedWithResult`.
  ///
  /// Amalda bu nimani bildiradi:
  ///   * Android tizim tugmasi va har qanday dasturiy `maybePop` —
  ///     `onPopInvokedWithResult` ga tushadi va TASDIQ so'raladi;
  ///   * iOS'dagi chetdan surish — `canPop: false` da Flutter jestni UMUMAN
  ///     o'chiradi, ya'ni surish hech narsa qilmaydi.
  /// Ikkala yo'lda ham natija bitta: 1-qadamdan tasdiqsiz CHIQIB BO'LMAYDI.
  /// Aynan shuni qulflaymiz — «surish ishlamayapti» deb kimdir `canPop` ni
  /// `true` qilsa, e'lon jimgina tashlab ketiladigan bo'lib qoladi.
  testWidgets('1-qadam: pop BLOKLANGAN (iOS surishi chiqarib yubormaydi)', (
    tester,
  ) async {
    final nav = await pumpHost(tester);
    // ignore: discarded_futures
    pushBozorDraftStack(nav, draft(), WizardStep.type);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // `PopScope<T>` — generik, shuning uchun aniq turi bo'yicha emas,
    // predikat bo'yicha izlaymiz.
    final scope = tester.widgetList(
      find.descendant(
        of: find.byType(BozorTypeStepScreen),
        matching: find.byWidgetPredicate((w) => w is PopScope),
      ),
    ).cast<PopScope>().single;
    expect(scope.canPop, isFalse);
    await flushTimers(tester);
  });

  testWidgets('1-qadam: tizim «orqaga» si tasdiq so\'raydi va oqimda qoldiradi', (
    tester,
  ) async {
    final nav = await pumpHost(tester);
    // ignore: discarded_futures
    pushBozorDraftStack(nav, draft(), WizardStep.type);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Android tizim tugmasi / dasturiy pop — `onPopInvokedWithResult` yo'li.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(exitSheet(), findsNWidgets(2));

    await tester.tap(stayButton());
    await tester.pumpAndSettle();
    expect(find.byType(BozorTypeStepScreen), findsOneWidget);
    expect(find.text('RO\'YXAT'), findsNothing);
    await flushTimers(tester);
  });

  testWidgets('oraliq qadamda POP BLOKLANMAYDI — bitta qadam orqaga', (
    tester,
  ) async {
    await openDescription(tester);

    expect(
      find.descendant(
        of: find.byType(BozorDescriptionStepScreen),
        matching: find.byWidgetPredicate((w) => w is PopScope),
      ),
      findsNothing,
      reason: 'oraliq qadamda pop — oddiy «bitta qadam orqaga», ushlanmaydi',
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(BozorPriceStepScreen), findsOneWidget);
    expect(exitSheet(), findsNothing);
    await flushTimers(tester);
  });

  testWidgets('1-qadamda × umuman yo\'q', (tester) async {
    final nav = await pumpHost(tester);
    // ignore: discarded_futures
    pushBozorDraftStack(nav, draft(), WizardStep.type);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(BozorTypeStepScreen), findsOneWidget);
    expect(appBar(tester, BozorTypeStepScreen).onClose, isNull);
    await flushTimers(tester);
  });
}

/// Qadam ekranlari tarmoq so'rovi taymerlarini (20 s timeout) boshlaydi —
/// `flutter_test` ochiq taymer bilan tugashga yo'l qo'ymaydi.
Future<void> flushTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 30));
}
