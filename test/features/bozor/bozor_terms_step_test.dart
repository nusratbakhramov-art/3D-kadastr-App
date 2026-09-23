import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:kadastr/features/bozor/data/bozor_draft_codec.dart';
import 'package:kadastr/features/bozor/models/bozor_draft.dart';
import 'package:kadastr/features/bozor/screens/bozor_terms_step_screen.dart';
import 'package:kadastr/features/bozor/widgets/tier_card.dart';
import 'param_schema_fixture.dart';

/// Oxirgi qadam: tariflar YO'Q, backend «E'lon shartlari» matni va uning
/// ostida rozilik katakchasi; belgilangach `terms_version` serverga ketadi.
void main() {
  // Sxema backenddan keladi — testda uni qo'lda yuklaymiz.
  setUpAll(loadRealParamSchema);

  BozorDraft draft() => BozorDraft(
    deal: DealType.rent,
    kind: PropertyKind.residential,
    type: PropertyType.apartment,
  );

  Future<ListingTermsDoc> loader(String lang) async => ListingTermsDoc(
    title: 'E\'lon joylashtirish shartlari',
    html: '<p>1. Umumiy qoidalar</p><p>Matn ($lang)</p>',
    version: '7',
  );

  testWidgets('tarif kartalari yo\'q, hujjat matni ko\'rinadi', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BozorTermsStepScreen(draft: draft(), termsLoader: loader),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(TierCard), findsNothing);
    expect(find.text('bozor.terms.tier_top'), findsNothing);
    expect(find.text('E\'lon joylashtirish shartlari'), findsOneWidget);
    // HTML asinxron chiziladi — vidjetning o'zi va unga berilgan matn.
    final html = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
    expect(html.html, contains('Umumiy qoidalar'));
    expect(find.byType(Checkbox), findsOneWidget);
  });

  testWidgets(
    'katakcha hujjat yuklanmaguncha o\'chiq, belgilangach versiya yoziladi',
    (tester) async {
      final d = draft();
      var release = false;
      Future<ListingTermsDoc> slow(String lang) async {
        while (!release) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        return loader(lang);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: BozorTermsStepScreen(draft: d, termsLoader: slow),
        ),
      );
      await tester.pump();
      final before = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(before.onChanged, isNull, reason: 'hujjatsiz rozilik yo\'q');

      release = true;
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      final after = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(after.onChanged, isNotNull);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(d.terms.accepted, isTrue);
      expect(d.terms.acceptedVersion, '7');
      // Serverga `terms_version` bo'lib ketadi.
      final terms = draftToDraftPayload(d)['terms'] as Map;
      expect(terms['terms_version'], '7');
      expect(terms['tier'], 'standard');

      // Bekor qilinsa versiya ham tozalanadi.
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(d.terms.accepted, isFalse);
      expect(d.terms.acceptedVersion, isNull);
    },
  );

  testWidgets('hujjat yuklanmasa — xato matni va qayta urinish', (
    tester,
  ) async {
    var calls = 0;
    Future<ListingTermsDoc> failing(String lang) async {
      calls++;
      if (calls == 1) throw Exception('offline');
      return loader(lang);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: BozorTermsStepScreen(draft: draft(), termsLoader: failing),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('bozor.terms.doc_failed'), findsOneWidget);

    await tester.tap(find.text('bozor.pano.flow.retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(calls, 2);
    expect(find.byType(HtmlWidget), findsOneWidget);
  });
}
