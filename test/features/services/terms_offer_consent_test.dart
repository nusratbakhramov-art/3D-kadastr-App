import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/core/i18n/app_translations.dart';
import 'package:kadastr/features/services/widgets/terms_consent.dart';

/// The consent sheet is the OFFER ACCEPTANCE step — we sign no bilateral
/// contract, so this is where the service is legally formed and the generated
/// report cites it. Both ticks are load-bearing: the report asserts the client
/// accepted the offer AND acknowledged the fee is non-refundable. A gate that
/// lets either one slide would put an untrue sentence in a legal document.
void main() {
  const keys = {
    'services.widget.terms.sheet_title': 'Foydalanish shartlari',
    'services.widget.terms.accept': 'QABUL QILAMAN',
    'services.widget.terms.scroll_hint': 'Shartlarni oxirigacha o\'qing',
    'services.widget.terms.check_offer': 'Ofertani qabul qilaman',
    'services.widget.terms.check_refund': 'Pul qaytarilmasligiga roziman',
    'services.widget.terms.check_hint': 'Ikkala bandni belgilang',
    'services.widget.terms.para1': 'p1',
    'services.widget.terms.para2': 'p2',
    'services.widget.terms.para3': 'p3',
  };

  setUp(() {
    appTranslationsNotifier.value = AppTranslations(
      version: 1,
      byLang: {'uz': keys},
    );
  });

  tearDown(() => appTranslationsNotifier.value = AppTranslations.empty);

  Future<void> pumpSheet(WidgetTester tester, {required void Function(bool) onResult}) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('uz'),
        supportedLocales: const [Locale('uz')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  onResult(await showTermsAcceptanceSheet(context));
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // Terms fetch fails in tests (no network) → bundled fallback + the
    // "short content counts as read" timer.
    await tester.pump();
    // The terms fetch fails in tests (no network) → the bundled fallback text,
    // which is short enough that the sheet counts it as read on the next frame.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('accept stays disabled until BOTH consents are ticked',
      (tester) async {
    bool? result;
    await pumpSheet(tester, onResult: (r) => result = r);

    final button = find.widgetWithText(FilledButton, 'QABUL QILAMAN');
    expect(button, findsOneWidget);
    expect(tester.widget<FilledButton>(button).onPressed, isNull,
        reason: 'no consent given yet');

    await tester.tap(find.text('Ofertani qabul qilaman'));
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNull,
        reason: 'only the offer box is ticked — the refund one is missing');

    await tester.tap(find.text('Pul qaytarilmasligiga roziman'));
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('un-ticking a consent disables the button again',
      (tester) async {
    await pumpSheet(tester, onResult: (_) {});
    final button = find.widgetWithText(FilledButton, 'QABUL QILAMAN');

    await tester.tap(find.text('Ofertani qabul qilaman'));
    await tester.tap(find.text('Pul qaytarilmasligiga roziman'));
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);

    await tester.tap(find.text('Pul qaytarilmasligiga roziman'));
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
  });

  testWidgets('dismissing the sheet is not an acceptance', (tester) async {
    bool? result;
    await pumpSheet(tester, onResult: (r) => result = r);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
