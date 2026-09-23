import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/bozor/bozor_resume.dart';
import 'package:kadastr/features/bozor/bozor_routes.dart';
import 'package:kadastr/features/bozor/models/bozor_draft.dart';
import 'package:kadastr/features/bozor/screens/bozor_description_step_screen.dart';
import 'package:kadastr/features/bozor/screens/bozor_price_step_screen.dart';
import 'package:kadastr/features/bozor/screens/bozor_type_step_screen.dart';
import 'param_schema_fixture.dart';

/// Qoralama SAQLANGAN qadamdan davom ettirilganda oldingi qadamlar ham
/// navigatorda bo'lishi kerak: «Ortga» → oldingi qadam, header ← → ro'yxat.
///
/// Prod 2026-09-13: 6-qadamda saqlangan qoralamada «Ortga» bosilganda
/// foydalanuvchi to'g'ridan «Mening e'lonlarim» ga tushib qolardi.
void main() {
  // Sxema backenddan keladi — testda uni qo'lda yuklaymiz.
  setUpAll(loadRealParamSchema);

  BozorDraft draft() => BozorDraft(
    deal: DealType.rent,
    kind: PropertyKind.residential,
    type: PropertyType.apartment,
  );

  final pushed = <String>[];
  final observer = _PushObserver(pushed);
  setUp(pushed.clear);

  Future<NavigatorState> pumpHost(WidgetTester tester) async {
    late NavigatorState nav;
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
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

  testWidgets('description qadamidan «Ortga» → price qadami', (tester) async {
    final nav = await pumpHost(tester);
    final d = draft();
    unawaitedPush(nav, d, WizardStep.description);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(BozorDescriptionStepScreen), findsOneWidget);
    // Stack: RO'YXAT + type + address + params + price + description.
    final expected =
        d.wizardSteps.takeWhile((s) => s != WizardStep.description).length + 1;
    expect(
      pushed.where((n) => n.startsWith(bozorRoutePrefix)).length,
      expected,
    );
    expect(pushed.last, 'bozor/description');

    nav.pop(); // «Ortga» — sehrgar ekranlaridagi maybePop bilan bir xil
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BozorPriceStepScreen), findsOneWidget);
    expect(find.text('RO\'YXAT'), findsNothing);
    await flushTimers(tester);
  });

  testWidgets('header ← (closeBozorWizard) butun oqimni yopadi', (
    tester,
  ) async {
    final nav = await pumpHost(tester);
    unawaitedPush(nav, draft(), WizardStep.description);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    closeBozorWizard(tester.element(find.byType(BozorDescriptionStepScreen)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('RO\'YXAT'), findsOneWidget);
    expect(find.byType(BozorTypeStepScreen), findsNothing);
    await flushTimers(tester);
  });

  testWidgets('1-qadamdan davom — qo\'shimcha marshrut yo\'q', (tester) async {
    final nav = await pumpHost(tester);
    unawaitedPush(nav, draft(), WizardStep.type);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BozorTypeStepScreen), findsOneWidget);
    expect(pushed.where((n) => n.startsWith(bozorRoutePrefix)).length, 1);
    await flushTimers(tester);
  });
}

/// Qadam ekranlari tarmoq so'rovi taymerlarini (20 s timeout) boshlaydi —
/// `flutter_test` ochiq taymer bilan tugashga yo'l qo'ymaydi.
Future<void> flushTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 30));
}

void unawaitedPush(NavigatorState nav, BozorDraft d, WizardStep step) {
  // ignore: discarded_futures
  pushBozorDraftStack(nav, d, step);
}

class _PushObserver extends NavigatorObserver {
  _PushObserver(this.names);
  final List<String> names;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    names.add(route.settings.name ?? '');
  }
}
